//! The way to Flutter's screen without a copy, one file per platform with
//! the same face: Windows hands Flutter a texture the engine made
//! (windows.rs), and so do iOS and macOS, through an IOSurface (apple.rs),
//! and Linux, through a dma-buf (linux.rs); Android presents into a window
//! Flutter made (android.rs); the rest have no bridge yet.

#[cfg(target_os = "android")]
mod android;
#[cfg(target_vendor = "apple")]
mod apple;
#[cfg(target_os = "linux")]
mod linux;
#[cfg(not(any(
    windows,
    target_os = "android",
    target_vendor = "apple",
    target_os = "linux"
)))]
mod unsupported;
#[cfg(windows)]
mod windows;

#[cfg(target_os = "android")]
use self::android as native;
#[cfg(target_vendor = "apple")]
use self::apple as native;
#[cfg(target_os = "linux")]
use self::linux as native;
#[cfg(not(any(
    windows,
    target_os = "android",
    target_vendor = "apple",
    target_os = "linux"
)))]
use self::unsupported as native;
#[cfg(windows)]
use self::windows as native;

pub(crate) use native::{adapter_luid, device_went_by, video_memory};

use std::ffi::c_void;
use std::path::PathBuf;
use std::sync::{Mutex, PoisonError};

use crate::device::Engine;
use crate::fail;

/// The instance the engine's adapters come from. The engine keeps it:
/// Android's window surfaces must come from it too.
pub(crate) fn instance() -> wgpu::Instance {
    let mut desc = wgpu::InstanceDescriptor::new_without_display_handle();
    desc.backends = native::BACKENDS;
    #[cfg(windows)]
    {
        desc.backend_options.dx12.shader_compiler = windows::shader_compiler();
    }
    wgpu::Instance::new(desc)
}

/// The adapters the engine may open on, through the platform's backend.
pub(crate) fn adapters(instance: &wgpu::Instance) -> Vec<wgpu::Adapter> {
    pollster::block_on(instance.enumerate_adapters(native::BACKENDS))
}

/// The folder the app named for the shaders the engines it opens compile
/// ([`gpu_engine_keep_shaders_in`]) — none till it names one.
static SHADERS_KEPT_IN: Mutex<Option<PathBuf>> = Mutex::new(None);

/// Keeps what `device`'s shader compiler makes in the app's folder for
/// them ([`SHADERS_KEPT_IN`]), for the next launch to hand the driver
/// instead of compiling it again: on Windows what DXC makes
/// (vendor/wgpu-hal, dxil_cache.rs). 🗣️유저 2026-11-13,
/// the-wait-window-stands-seven-seconds-on-the-surface-Q1 「디스크 캐시」.
#[cfg_attr(not(windows), allow(unused_variables))]
pub(crate) fn keep_shaders(device: &wgpu::Device) {
    let folder = SHADERS_KEPT_IN.lock().unwrap_or_else(PoisonError::into_inner).clone();
    #[cfg(windows)]
    windows::keep_dxil(device, folder);
}

/// Names the folder — `folder`'s `length` bytes of UTF-8 — where each
/// engine opened from now on keeps the shaders it compiles
/// ([`keep_shaders`]); none where `length` is 0.
///
/// # Safety
/// `folder` holds `length` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_keep_shaders_in(folder: *const u8, length: usize) {
    let named = (length > 0).then(|| {
        // SAFETY: see the function's contract.
        let bytes = unsafe { std::slice::from_raw_parts(folder, length) };
        PathBuf::from(String::from_utf8_lossy(bytes).into_owned())
    });
    *SHADERS_KEPT_IN.lock().unwrap_or_else(PoisonError::into_inner) = named;
}

/// This process's use of the adapter's memory, in bytes, and the budget
/// the OS gives it there where the OS says one.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct VideoMemory {
    pub used: u64,
    pub budget: Option<u64>,
}

/// WHY A DEVICE WENT, as far as the engine can tell — what the app says of
/// it to the person once it stands on another (`gpu_engine_went_by`).
///
/// 🗣️유저 2026-11-11 (a-lost-gpu-device-keeps-the-unsaved-tiles): 「그래픽
/// 장치가 왜 다시시작되었는지는 알수있게. 사용자는 앱 원인인지 다른건지
/// 모르니까 어느정도는 투명하게. 물론 확실하게 모를 가능성 높으니 그 경우
/// 가능성높은 원인을 알려주도록」 — so a cause is named only where something
/// says it: the platform, of a device its driver took ([`device_went_by`]),
/// or wgpu, of one it gave up itself (`Engine::went_by`). This one is
/// where nothing does.
///
/// ⚠️The numbers are the ABI's: Dart names them in this order
/// (`GpuDeviceWent`).
pub const WENT_UNSAID: u32 = 0;
/// For want of video memory.
pub const WENT_BY_MEMORY: u32 = 1;
/// Over what this app sent it.
pub const WENT_BY_THIS_APP: u32 = 2;
/// Removed or turned off, or its driver upgraded.
pub const WENT_BY_REMOVAL: u32 = 3;
/// Reset over a command badly formed — whose, nothing says.
pub const WENT_BY_RESET: u32 = 4;
/// Reset by its driver, which failed.
pub const WENT_BY_DRIVER: u32 = 5;

/// A texture kernels write — and, where the platform shares textures,
/// Flutter shows.
pub struct Surface {
    pub(crate) texture: wgpu::Texture,
    shared: native::SharedHandle,
}

/// The format of a surface of BGRA or RGBA 8-bit unorm texels.
pub(crate) fn surface_format(bgra: bool) -> wgpu::TextureFormat {
    if bgra {
        wgpu::TextureFormat::Bgra8Unorm
    } else {
        wgpu::TextureFormat::Rgba8Unorm
    }
}

/// Whether a compute pass on `engine` stores to a surface of `format`:
/// BGRA only where the adapter has the feature (`Engine::on` asks for it
/// wherever it is). Asked before a surface is made, and before a pass that
/// stores to one is compiled ahead of it: the device would raise either.
pub(crate) fn stores(engine: &Engine, format: wgpu::TextureFormat) -> bool {
    format != wgpu::TextureFormat::Bgra8Unorm
        || engine
            .device
            .features()
            .contains(wgpu::Features::BGRA8UNORM_STORAGE)
}

impl Surface {
    fn new(engine: &Engine, width: u32, height: u32, format: wgpu::TextureFormat) -> Option<Self> {
        if !stores(engine, format) {
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
    Surface::new(engine, width, height, surface_format(bgra))
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

/// What Flutter opens the surface by — on Windows, an NT handle; on iOS
/// and macOS, a CVPixelBuffer the caller does not own (retain it before
/// handing it to Flutter); on Linux, the `DmaBuf` that describes the
/// plane; null where the platform shares no texture.
///
/// # Safety
/// `surface` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_surface_handle(surface: *const Surface) -> *mut c_void {
    // SAFETY: see the function's contract.
    unsafe { &*surface }.shared.raw()
}
