//! The way to Flutter's screen without a copy, one file per platform with
//! the same face: Windows hands Flutter a texture the engine made
//! (windows.rs); Android presents into a window Flutter made (android.rs);
//! the rest have no bridge yet.

#[cfg(target_os = "android")]
mod android;
#[cfg(not(any(windows, target_os = "android")))]
mod unsupported;
#[cfg(windows)]
mod windows;

#[cfg(target_os = "android")]
use self::android as native;
#[cfg(not(any(windows, target_os = "android")))]
use self::unsupported as native;
#[cfg(windows)]
use self::windows as native;

pub(crate) use native::{adapter_luid, video_memory};

use std::ffi::c_void;

use crate::device::Engine;
use crate::fail;

/// The instance the engine's adapters come from. The engine keeps it:
/// Android's window surfaces must come from it too.
pub(crate) fn instance() -> wgpu::Instance {
    let mut desc = wgpu::InstanceDescriptor::new_without_display_handle();
    desc.backends = native::BACKENDS;
    wgpu::Instance::new(desc)
}

/// The adapters the engine may open on, through the platform's backend.
pub(crate) fn adapters(instance: &wgpu::Instance) -> Vec<wgpu::Adapter> {
    pollster::block_on(instance.enumerate_adapters(native::BACKENDS))
}

/// A texture kernels write — and, where the platform shares textures,
/// Flutter shows.
pub struct Surface {
    pub(crate) texture: wgpu::Texture,
    shared: native::SharedHandle,
}

impl Surface {
    fn new(engine: &Engine, width: u32, height: u32, format: wgpu::TextureFormat) -> Option<Self> {
        let storable = engine
            .device
            .features()
            .contains(wgpu::Features::BGRA8UNORM_STORAGE);
        if format == wgpu::TextureFormat::Bgra8Unorm && !storable {
            return fail("this adapter cannot store to bgra8unorm from a compute pass");
        }
        match native::create(&engine.device, width, height, format) {
            Ok((texture, shared)) => Some(Self { texture, shared }),
            Err(error) => fail(error),
        }
    }
}

/// Makes a `width` × `height` texture of BGRA or RGBA 8-bit unorm texels,
/// shared with Flutter where the platform shares textures. Null on
/// failure; see the last error.
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_surface_new(
    engine: *const Engine,
    width: u32,
    height: u32,
    bgra: bool,
) -> *mut Surface {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    let format = if bgra {
        wgpu::TextureFormat::Bgra8Unorm
    } else {
        wgpu::TextureFormat::Rgba8Unorm
    };
    Surface::new(engine, width, height, format)
        .map_or(std::ptr::null_mut(), |surface| Box::into_raw(Box::new(surface)))
}

/// # Safety
/// `surface` came from `gpu_engine_surface_new` and Flutter no longer
/// shows it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_surface_free(surface: *mut Surface) {
    if !surface.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(surface) });
    }
}

/// The texture a kernel writes to fill `surface`.
///
/// # Safety
/// `surface` is live; the texture lives as long as it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_surface_texture(surface: *const Surface) -> *const wgpu::Texture {
    // SAFETY: see the function's contract.
    &unsafe { &*surface }.texture
}

/// What Flutter opens the surface by — on Windows, an NT handle; null
/// where the platform shares no texture.
///
/// # Safety
/// `surface` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_surface_handle(surface: *const Surface) -> *mut c_void {
    // SAFETY: see the function's contract.
    unsafe { &*surface }.shared.raw()
}
