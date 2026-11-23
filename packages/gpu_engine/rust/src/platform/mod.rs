//! The way to Flutter's screen without a copy, one file per platform with
//! the same face: Windows hands Flutter a texture the engine made
//! (windows.rs), and so do iOS and macOS, through an IOSurface (apple.rs),
//! Linux, through a dma-buf (linux.rs), and Android, through an
//! AHardwareBuffer (android.rs); the rest have no bridge yet.
//!
//! 🚨THE LAW OF A SCREEN'S BUFFER: what is handed to Flutter is laid out so
//! that the engine's device and Flutter's read it alike with nothing
//! handed between them — no compression for one to resolve, no layout for
//! one to change. Each platform keeps it by how it makes the buffer:
//! - Windows: ALLOW_SIMULTANEOUS_ACCESS — the texture decays to COMMON
//!   once the engine's work on it finishes (windows.rs).
//! - Linux: the LINEAR modifier (linux.rs).
//! - Android: CPU_READ_RARELY, which drivers lay out uncompressed
//!   (android.rs, `allocated`). A request to the driver, not a guarantee
//!   as LINEAR is — so the debug screen's check measures a buffer laid
//!   each way (the app's `ScreenCheck`, [`Laid`]).
//! - iOS and macOS: an IOSurface (apple.rs) — how Metal keeps it there has
//!   not been read (공통 2026-11-24).
//!
//! 🗣️유저 2026-11-24 (card the-galaxy-tab-canvas-went-slow-on-build-1095,
//! through 관제): 「2번은 안드만 해당이야? 통일해도 이거는 통일안된단거야?
//! 통일기준으로 정하면안되나」 — one law, which Android alone broke till
//! then (an OPTIMAL image laid as its driver chose).
//!
//! ⛔A LAW NOT YET KEPT, ON ANY PLATFORM: a buffer is drawn on again only
//! once Flutter has finished reading it. The app draws the next frame on
//! the buffer Flutter was shown before, as soon as it is shown the other
//! (the app's `ScreenTexture`), and nothing on any platform says Flutter's
//! GPU is done with it (risk 1 of that card; its fix goes to every
//! platform at once).

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

pub(crate) use native::{adapter_luid, asking_the_driver_of, device_went_by, video_memory};
#[cfg(windows)]
pub(crate) use native::committed_buffer;

use std::ffi::c_void;
use std::path::PathBuf;
use std::sync::{Mutex, PoisonError};

use crate::device::{Engine, Sent, let_go};
use crate::fail;

/// The instance the engine's adapters come from.
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
/// instead of compiling it again: on Windows what DXC makes, and what the
/// driver makes of each pipeline on it (vendor/wgpu-hal, compile_cache.rs).
/// 🗣️유저 2026-11-13,
/// the-wait-window-stands-seven-seconds-on-the-surface-Q1 「디스크 캐시」.
#[cfg_attr(not(windows), allow(unused_variables))]
pub(crate) fn keep_shaders(device: &wgpu::Device) {
    let folder = SHADERS_KEPT_IN.lock().unwrap_or_else(PoisonError::into_inner).clone();
    #[cfg(windows)]
    windows::keep_shaders(device, folder);
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
/// the OS gives it there where the OS says one — and what of its video
/// memory lies in the system's RAM where the OS says that: moved out past
/// the budget, or made there for the CPU to reach — and all the adapter's
/// own memory, where the OS says that.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct VideoMemory {
    pub used: u64,
    pub budget: Option<u64>,
    pub in_system: Option<u64>,
    pub total: Option<u64>,
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

/// What asks a device's driver whether it took the device
/// ([`asking_the_driver_of`]) — waiting on nothing, from whatever thread
/// asks. Why it did is [`device_went_by`]'s to say.
pub(crate) type DriverAsked = Box<dyn Fn() -> bool + Send>;

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
            .device()
            .features()
            .contains(wgpu::Features::BGRA8UNORM_STORAGE)
}

/// How a surface's memory is to be laid out, where the platform lets the
/// engine say: Android alone does (platform/android.rs, `allocated`) —
/// there a screen asks for the layout the CPU may read too, which drivers
/// keep uncompressed, and the debug screen's check makes one of each to
/// tell whether that was needed. The others take what they make.
#[derive(Clone, Copy)]
pub enum Laid {
    ForTheCpuToo,
    AsTheDriverChooses,
}

impl Surface {
    fn new(engine: &Engine, width: u32, height: u32, format: wgpu::TextureFormat, laid: Laid) -> Option<Self> {
        // Android's window refused one before it was a surface (2026-11-23):
        // an image of no texel is no image to Vulkan or D3D12.
        if width == 0 || height == 0 {
            return fail(format!("a {width} × {height} surface"));
        }
        if !stores(engine, format) {
            return fail("this adapter cannot store to bgra8unorm from a compute pass");
        }
        match native::create(engine.device(), width, height, format, laid) {
            Ok((texture, shared)) => Some(Self { texture, shared }),
            Err(error) => fail(error),
        }
    }
}

/// Makes a `width` × `height` texture of BGRA or RGBA 8-bit unorm texels,
/// shared with Flutter where the platform shares textures — laid out for
/// the CPU to read too where `for_the_cpu_too` and the platform lets it be
/// said ([`Laid`]). Null on failure; see the last error.
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_surface_new(
    engine: *const Engine,
    width: u32,
    height: u32,
    bgra: bool,
    for_the_cpu_too: bool,
) -> *mut Surface {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    let laid = if for_the_cpu_too { Laid::ForTheCpuToo } else { Laid::AsTheDriverChooses };
    engine.on_thread(|| {
        Surface::new(engine, width, height, surface_format(bgra), laid)
            .map_or(std::ptr::null_mut(), |surface| engine.hands(surface))
    })
}

/// # Safety
/// `surface` came from `gpu_engine_surface_new` and Flutter no longer
/// shows it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_surface_free(surface: *mut Surface) {
    // SAFETY: see the function's contract.
    unsafe { let_go(surface) };
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

/// Copies the pixels `rect` of what the kernels wrote to `surface` —
/// [left, top, right, bottom) — onto what Flutter shows of it, where the
/// two are apart (Android's screens on a device whose AHardwareBuffer
/// images take no stores, `platform/android.rs`, `Way::Copied`): on the
/// engine's thread in its turn, its caller waiting for none of it
/// ([`Engine::posted`]) — where it fails, the caller's next done fails by
/// it. Nothing where the two are one texture, every other surface.
///
/// The app asks it once a frame is drawn, of what the frame's draws wrote
/// (`GpuTarget.settle`), before it asks for the GPU's done: the frame is
/// shown once the copy is done too.
///
/// # Safety
/// `engine` and `surface` are live, `surface` made on `engine`; `rect`
/// holds four words. `surface` is let go of on the engine's thread
/// ([`let_go`]), behind this in turn.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_surface_settle(
    engine: *const Engine,
    surface: *const Surface,
    rect: *const u32,
) {
    // SAFETY: see the function's contract.
    let (engine, made) = unsafe { (&*engine, &*surface) };
    if made.shared.shown().is_none() {
        return;
    }
    // SAFETY: see the function's contract.
    let [left, top, right, bottom] = unsafe { *rect.cast::<[u32; 4]>() };
    let size = made.texture.size();
    let (right, bottom) = (right.min(size.width), bottom.min(size.height));
    if left >= right || top >= bottom {
        return;
    }
    let handed = Sent((engine.clone(), surface));
    engine.posted(move || {
        let (engine, surface) = handed.taken();
        // SAFETY: live till let go of, behind this (the function's
        // contract).
        let made = unsafe { &*surface };
        let shown = made.shared.shown()?;
        let at = wgpu::Origin3d { x: left, y: top, z: 0 };
        let mut encoder =
            engine.device().create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        encoder.copy_texture_to_texture(
            wgpu::TexelCopyTextureInfo {
                origin: at,
                ..made.texture.as_image_copy()
            },
            wgpu::TexelCopyTextureInfo {
                origin: at,
                ..shown.as_image_copy()
            },
            wgpu::Extent3d {
                width: right - left,
                height: bottom - top,
                depth_or_array_layers: 1,
            },
        );
        engine.queue.submit([encoder.finish()]);
        Some(())
    });
}

/// Copies the way a surface reaches Flutter's screen on `engine` — where
/// Android's cannot, what stands in the way ([`native::screen_said`]) —
/// into `buffer` (UTF-8) and returns its full length, for the debug
/// screen.
///
/// # Safety
/// `engine` is live and `buffer` holds `capacity` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_screen_said(
    engine: *const Engine,
    buffer: *mut u8,
    capacity: usize,
) -> usize {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    let said = engine.on_thread(|| native::screen_said(engine.device()));
    crate::copy_out(&said, buffer, capacity)
}

/// What Flutter opens the surface by — on Windows, an NT handle; on iOS
/// and macOS, a CVPixelBuffer the caller does not own (retain it before
/// handing it to Flutter); on Linux, the `DmaBuf` that describes the
/// plane; on Android, the AHardwareBuffer the caller does not own
/// (`GpuEnginePlugin.register` hands Flutter a reference of its own);
/// null where the platform shares no texture.
///
/// # Safety
/// `surface` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_surface_handle(surface: *const Surface) -> *mut c_void {
    // SAFETY: see the function's contract.
    unsafe { &*surface }.shared.raw()
}
