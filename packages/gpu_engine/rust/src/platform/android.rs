//! Android: the engine presents into a window Flutter made — a
//! SurfaceProducer's ImageReader, whose buffers Impeller imports as they
//! are (Vulkan: image_external_texture_vk_impeller.cc:39-104; GLES:
//! image_external_texture_gl_impeller.cc:29-57) — through wgpu's Vulkan
//! swapchain on that window.
//!
//! Each choice below is there because a source says so (gpu-engine-skeleton):
//! - Vulkan only: whether GLES-only devices get compute is
//!   gpu-engine-feasibility's open question (Q3); the device stage 0
//!   measures on (SM-X910, Adreno 740) has Vulkan.
//! - the kernels store straight into the swapchain's image when its usages
//!   allow storage, which is per device (VkSurfaceCapabilitiesKHR::
//!   supportedUsageFlags); otherwise into a texture of the engine's own,
//!   copied into the image when it is presented — one GPU copy, which
//!   [`Window::direct`] reports.
//! - RGBA8 unorm: the bytes the kernels write are the bytes shown, with no
//!   sRGB encode between, as on Windows.
//! - Fifo: the one present mode every device has.

use std::ffi::c_void;
use std::ptr::NonNull;

use wgpu::rwh::{AndroidDisplayHandle, AndroidNdkWindowHandle, RawDisplayHandle, RawWindowHandle};

use crate::device::{Engine, storage_texture};
use crate::fail;

pub const BACKENDS: wgpu::Backends = wgpu::Backends::VULKAN;

/// Android shows a [`Window`], not a texture of the engine's: a surface
/// here is shared with nothing, for kernels and fingerprints.
pub struct SharedHandle;

impl SharedHandle {
    pub fn raw(&self) -> *mut c_void {
        std::ptr::null_mut()
    }
}

pub fn create(
    device: &wgpu::Device,
    width: u32,
    height: u32,
    format: wgpu::TextureFormat,
) -> Result<(wgpu::Texture, SharedHandle), String> {
    Ok((storage_texture(device, width, height, format), SharedHandle))
}

pub fn adapter_luid(_adapter: &wgpu::Adapter) -> Option<u64> {
    None
}

/// Android has no call that says how much video memory a process uses.
pub fn video_memory(_adapter: &wgpu::Adapter) -> Option<super::VideoMemory> {
    None
}
/// Why the device went — unsaid: Vulkan says that a device is lost, and
/// not why.
pub fn device_went_by(_device: &wgpu::Device) -> u32 {
    super::WENT_UNSAID
}

#[link(name = "android")]
unsafe extern "C" {
    fn ANativeWindow_fromSurface(env: *mut c_void, surface: *mut c_void) -> *mut c_void;
    fn ANativeWindow_release(window: *mut c_void);
}

/// One reference to an ANativeWindow, released when dropped.
struct NativeWindow(NonNull<c_void>);

impl Drop for NativeWindow {
    fn drop(&mut self) {
        // SAFETY: the reference came from ANativeWindow_fromSurface and is
        // released once.
        unsafe { ANativeWindow_release(self.0.as_ptr()) };
    }
}

/// A window Flutter shows, and the swapchain the engine presents into it.
pub struct Window {
    surface: wgpu::Surface<'static>,
    current: Option<wgpu::SurfaceTexture>,
    /// Where the kernels write when the swapchain's images take no stores.
    staging: Option<wgpu::Texture>,
    // Last, so it is dropped last: the window outlives the surface made on
    // it (fields drop in declaration order).
    _native: NativeWindow,
}

impl Window {
    fn new(engine: &Engine, native: NativeWindow, width: u32, height: u32) -> Option<Self> {
        if width == 0 || height == 0 {
            return fail(format!("a {width} × {height} window"));
        }
        let target = wgpu::SurfaceTargetUnsafe::RawHandle {
            raw_display_handle: Some(RawDisplayHandle::Android(AndroidDisplayHandle::new())),
            raw_window_handle: RawWindowHandle::AndroidNdk(AndroidNdkWindowHandle::new(native.0)),
        };
        // SAFETY: the window outlives the surface (`_native` drops last).
        let surface = match unsafe { engine.instance.create_surface_unsafe(target) } {
            Ok(surface) => surface,
            Err(error) => return fail(format!("create_surface: {error}")),
        };
        let caps = surface.get_capabilities(&engine.adapter);
        let format = wgpu::TextureFormat::Rgba8Unorm;
        if !caps.formats.contains(&format) {
            return fail(format!("the window offers {:?}, not {format:?}", caps.formats));
        }
        let direct = caps.usages.contains(wgpu::TextureUsages::STORAGE_BINDING);
        let usage = if direct {
            wgpu::TextureUsages::STORAGE_BINDING
        } else {
            wgpu::TextureUsages::COPY_DST
        };
        if !caps.usages.contains(usage) {
            return fail(format!("the window's images take neither stores nor copies: {:?}", caps.usages));
        }
        let Some(mut config) = surface.get_default_config(&engine.adapter, width, height) else {
            return fail("the window offers no present mode");
        };
        config.usage = usage;
        config.format = format;
        config.present_mode = wgpu::PresentMode::Fifo;
        surface.configure(&engine.device, &config);
        Some(Self {
            surface,
            current: None,
            staging: (!direct).then(|| storage_texture(&engine.device, width, height, format)),
            _native: native,
        })
    }

    /// Whether the kernels store straight into the swapchain's images, with
    /// no copy before Flutter's.
    pub fn direct(&self) -> bool {
        self.staging.is_none()
    }

    /// The texture this frame's kernels write: the swapchain's next image,
    /// or the engine's own texture that [`Self::present`] copies into it.
    pub(crate) fn target(&mut self) -> Option<&wgpu::Texture> {
        let current = match self.current.take() {
            Some(current) => current,
            None => match self.surface.get_current_texture() {
                wgpu::CurrentSurfaceTexture::Success(texture)
                | wgpu::CurrentSurfaceTexture::Suboptimal(texture) => texture,
                other => return fail(format!("get_current_texture: {other:?}")),
            },
        };
        let current = self.current.insert(current);
        Some(self.staging.as_ref().unwrap_or(&current.texture))
    }

    /// Hands the image the kernels wrote to Flutter, waiting for the GPU
    /// first, as `Fill::run` does: Flutter waits on an image's fence only
    /// from API 33 (FlutterRenderer.java:788-811), and minSdk is 29.
    fn present(&mut self, engine: &Engine) -> Option<()> {
        let Some(current) = self.current.take() else {
            return fail("present before anything was written");
        };
        if let Some(staging) = &self.staging {
            let mut encoder = engine
                .device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
            encoder.copy_texture_to_texture(
                staging.as_image_copy(),
                current.texture.as_image_copy(),
                staging.size(),
            );
            engine.queue.submit([encoder.finish()]);
            engine.wait()?;
        }
        engine.queue.present(current);
        Some(())
    }
}

/// The window of an `android.view.Surface`, for
/// `GpuEnginePlugin.nativeWindow`: a reference `gpu_engine_window_new`
/// takes over. 0 when there is none.
///
/// # Safety
/// Called by the JVM, with its `JNIEnv` and a `Surface`.
#[unsafe(no_mangle)]
pub unsafe extern "system" fn Java_com_myoun_gpu_1engine_GpuEnginePlugin_nativeWindow(
    env: *mut c_void,
    _plugin: *mut c_void,
    surface: *mut c_void,
) -> i64 {
    // SAFETY: see the function's contract.
    unsafe { ANativeWindow_fromSurface(env, surface) as i64 }
}

/// Makes the swapchain on `native`, a window from
/// `GpuEnginePlugin.nativeWindow`, whose reference it takes over even when
/// it fails. Null on failure; see the last error.
///
/// # Safety
/// `engine` is live; `native` is null or a reference nobody else releases.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_window_new(
    engine: *const Engine,
    native: *mut c_void,
    width: u32,
    height: u32,
) -> *mut Window {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    NonNull::new(native)
        .map(NativeWindow)
        .or_else(|| fail("no window"))
        .and_then(|native| Window::new(engine, native, width, height))
        .map_or(std::ptr::null_mut(), |window| Box::into_raw(Box::new(window)))
}

/// # Safety
/// `window` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_window_direct(window: *const Window) -> bool {
    // SAFETY: see the function's contract.
    unsafe { &*window }.direct()
}

/// The texture this frame's kernels write to `window` — the same one until
/// it is presented. Null on failure; see the last error.
///
/// # Safety
/// `window` is live; the texture lives until `window` is presented.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_window_target(window: *mut Window) -> *const wgpu::Texture {
    // SAFETY: see the function's contract.
    unsafe { &mut *window }
        .target()
        .map_or(std::ptr::null(), |texture| texture)
}

/// Shows what the kernels last wrote to `window`. False on failure; see
/// the last error.
///
/// # Safety
/// `engine` and `window` are live, and `window` was made on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_window_present(engine: *const Engine, window: *mut Window) -> bool {
    // SAFETY: see the function's contract.
    let (engine, window) = unsafe { (&*engine, &mut *window) };
    window.present(engine).is_some()
}

/// # Safety
/// `window` came from `gpu_engine_window_new`; Flutter's producer is
/// released after it, not before.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_window_free(window: *mut Window) {
    if !window.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(window) });
    }
}
