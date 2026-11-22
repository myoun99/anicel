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
//! - the kernels store into a texture of the engine's own, copied onto the
//!   swapchain's next image as it is presented — one GPU copy a frame
//!   ([`Window`] has why, and what stood here before).
//! - RGBA8 unorm: the bytes the kernels write are the bytes shown, with no
//!   sRGB encode between, as on Windows.
//! - Fifo: the one present mode every device has.

use std::ffi::c_void;
use std::ptr::NonNull;
use std::sync::{Arc, Mutex, PoisonError};

use ash::vk;
use wgpu::hal::api::Vulkan;
use wgpu::rwh::{AndroidDisplayHandle, AndroidNdkWindowHandle, RawDisplayHandle, RawWindowHandle};

use crate::device::{Engine, Sent, let_go, storage_texture};
use crate::{copy_out, fail};

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

/// What asks the device's driver whether it took the device — nothing:
/// Vulkan says that a device is lost where a call fails by it, and no
/// call asks.
pub fn asking_the_driver_of(_device: &wgpu::Device) -> Option<super::DriverAsked> {
    None
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
///
/// 🚨ITS CALLER WAITS FOR NO TURN OF THE ENGINE'S THREAD, TO DRAW ON IT OR
/// TO SHOW IT (the-ui-thread-never-enters-the-driver, as every other
/// platform's screens: two textures of the engine's own, shown turn about,
/// and no call at all). What the kernels write is a texture of the
/// engine's own, at one address for the window's life ([`Self::drawn`]),
/// so it is named with no hand on the device; and a present is a body
/// handed over ([`Self::shown`]): the swapchain's next image is asked
/// for there, the texture copied onto it, and the image handed to Flutter
/// once the GPU has finished the copy.
///
/// ↩️TILL 2026-11-21 THE THREAD THAT BUILDS THE APP'S FRAMES WAITED ON
/// THE ENGINE'S TWICE A FRAME OF EVERY SCREEN, on Android alone: for the
/// swapchain's next image before a frame was drawn — the kernels stored
/// straight into it where its usages allowed storage, a device's own
/// answer —, and for the present. Each stood behind every body handed
/// over before it — a stroke's steps, a compose, a rest's folds — and in
/// the driver's own wait for an image. 🗣️유저 2026-11-21, on a Galaxy Tab
/// S9 Ultra (Adreno 740), card
/// the-galaxy-tab-canvas-went-slow-on-build-1095: 「캔버스조작, 즉 팬이나
/// 줌이나 스트로크가 너무 느려졋어」, 「초기값 프로젝트에서도 그냥 열자마자
/// 느려」 — on no other platform. ⚠️Read in the sources, not measured on
/// that device: whether this is all of what it met is the device's to
/// say.
///
/// ↩️TAKEN OUT THE DAY IT LANDED, AND PUT BACK (f2020bee3 → d86f5b420,
/// 관제 2026-11-21 20:00 「되돌려라」: it was measured on an emulator
/// alone, and there only for its caller's waits; builds 1096 and 1097
/// showed a window the old way, their frame statistics the baseline it
/// is read against). Put back for what the old way cannot do besides: a
/// frame shown again is drawn where it changed alone (the app's
/// `EngineStackScreen.show`), which takes a texture that still holds the
/// frame before — this one —, where the swapchain's next image is another
/// each frame.
///
/// 🔬THE BASELINE, on that tablet (2960 × 1848), build 1097, 유저's two
/// photographs of its frame statistics (2026-11-22): a frame of the
/// canvas's screen 3584 × 2560 texels, drawn whole while a stroke was
/// drawn as while the view was zoomed; the GPU finishing it in 53.4 ms
/// (p50; p95 128.6), its draw waiting 0.3 ms and its show 0.7; the app's
/// raster at 3.0 ms (p50) and 56.2 (p95), its frames at 30.5 a second
/// zoomed. ⚠️What this way does to those is the tablet's to say: on an
/// emulator a stroke's frame drew one tile of 128 × 128 where the old way
/// drew the whole screen, and no time told the two apart — its GPU is
/// this machine's (the card's ㉠, 2026-11-22). A view moved past the
/// texture's room, or zoomed, is drawn whole here too, with a copy more.
/// 🗣️Put on that tablet as it is, with no switch back to the old way
/// (the card's Q4, 유저 2026-11-22: 「내자. 어차피 아직 아무도안써서
/// 문제없어」).
///
/// ⚖️One way for every device, and a copy a frame for it (브러시/렌더링
/// 2026-11-21): storing straight into the image keeps the copy where a
/// device allows it, and then the image must be had before a frame's
/// bodies are handed over — a second way to the screen, forked by a
/// device's answer that no test here takes.
pub struct Window {
    surface: wgpu::Surface<'static>,
    /// What the kernels write.
    drawn: wgpu::Texture,
    /// The image the last present copied [`Self::drawn`] onto, till it is
    /// handed to Flutter — shared with the body that hands it
    /// ([`Self::shown`]).
    copied: Arc<Mutex<Copied>>,
    /// What the device said, as the window was made, of an image made of
    /// an AHardwareBuffer ([`hardware_buffer_said`]).
    hardware_buffer: String,
    // Last, so it is dropped last: the window outlives the surface made on
    // it (fields drop in declaration order).
    _native: NativeWindow,
}

/// 🔬What the device says of an image made of an AHardwareBuffer — whether
/// a kernel could store into one (`STORAGE`), beside whether it could be
/// drawn into (`COLOR_ATTACHMENT`, which every device is expected to
/// allow: a `no` there says the question itself did not get through):
/// `ahb storage yes|no|… color yes|no|…`. Asked of Vulkan's physical
/// device, which is asked and changes nothing; and whatever becomes of
/// the asking, a window is made: a question that panics says `?`.
///
/// 🗣️공통 2026-11-22 23:50, of 유저's 「윈도랑 안드랑 다른거
/// 통일못하는거야?」 (card the-galaxy-tab-canvas-went-slow-on-build-1095):
/// Flutter's Android embedding would take a buffer the engine made, were
/// a door cut for it — and whether the kernels could write that buffer
/// is each device's own answer, the Galaxy Tab's (Adreno 740) among them.
/// The frame statistics show it while the engine's stages are on
/// (`gpu_engine_window_said`).
fn hardware_buffer_said(engine: &Engine) -> String {
    let asked = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| hardware_buffer_asked(engine)));
    asked.unwrap_or_else(|_| "ahb ?  the asking panicked".to_owned())
}

fn hardware_buffer_asked(engine: &Engine) -> String {
    // SAFETY: the raw device is asked what it supports, and nothing of
    // wgpu's own state is changed.
    let Some(device) = (unsafe { engine.device().as_hal::<Vulkan>() }) else {
        return "ahb ?  not a Vulkan device".to_owned();
    };
    let (shared, physical) = (device.shared_instance(), device.raw_physical_device());
    let instance = shared.raw_instance();
    // SAFETY: only reads the device's own properties.
    let speaks = unsafe { instance.get_physical_device_properties(physical) }.api_version;
    // ⛔The question is Vulkan 1.1's own, of the instance and of the device
    // both. Of an instance made as 1.0, ash has no function for it and
    // its stand-in panics inside an `extern "system"` function — which
    // no `catch_unwind` catches: the process ends.
    if shared.instance_api_version() < vk::API_VERSION_1_1 || speaks < vk::API_VERSION_1_1 {
        return "ahb ?  a Vulkan 1.0 device".to_owned();
    }
    let takes = |usage: vk::ImageUsageFlags| {
        let mut external_info = vk::PhysicalDeviceExternalImageFormatInfo::default()
            .handle_type(vk::ExternalMemoryHandleTypeFlags::ANDROID_HARDWARE_BUFFER_ANDROID);
        let info = vk::PhysicalDeviceImageFormatInfo2::default()
            .format(vk::Format::R8G8B8A8_UNORM)
            .ty(vk::ImageType::TYPE_2D)
            .tiling(vk::ImageTiling::OPTIMAL)
            .usage(usage | vk::ImageUsageFlags::SAMPLED)
            .push_next(&mut external_info);
        let mut external = vk::ExternalImageFormatProperties::default();
        let mut properties = vk::ImageFormatProperties2::default().push_next(&mut external);
        // SAFETY: every structure is a local that outlives the call.
        let asked =
            unsafe { instance.get_physical_device_image_format_properties2(physical, &info, &mut properties) };
        let imports = external
            .external_memory_properties
            .external_memory_features
            .contains(vk::ExternalMemoryFeatureFlags::IMPORTABLE);
        match asked {
            Ok(()) if imports => "yes".to_owned(),
            Ok(()) => "not-imported".to_owned(),
            Err(vk::Result::ERROR_FORMAT_NOT_SUPPORTED) => "no".to_owned(),
            Err(error) => format!("{error:?}"),
        }
    };
    format!(
        "ahb storage {}  color {}",
        takes(vk::ImageUsageFlags::STORAGE),
        takes(vk::ImageUsageFlags::COLOR_ATTACHMENT),
    )
}

/// The image a present copied onto, and which present's it is.
#[derive(Default)]
struct Copied {
    present: u64,
    image: Option<wgpu::SurfaceTexture>,
}

impl Drop for Window {
    fn drop(&mut self) {
        // The image not handed over yet goes before the surface it is of:
        // the body that would hand it finds none.
        self.copied.lock().unwrap_or_else(PoisonError::into_inner).image = None;
    }
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
        let usage = wgpu::TextureUsages::COPY_DST;
        if !caps.usages.contains(usage) {
            return fail(format!("the window's images take no copies: {:?}", caps.usages));
        }
        let Some(mut config) = surface.get_default_config(&engine.adapter, width, height) else {
            return fail("the window offers no present mode");
        };
        config.usage = usage;
        config.format = format;
        config.present_mode = wgpu::PresentMode::Fifo;
        surface.configure(engine.device(), &config);
        Some(Self {
            surface,
            drawn: storage_texture(engine.device(), width, height, format),
            copied: Arc::default(),
            hardware_buffer: hardware_buffer_said(engine),
            _native: native,
        })
    }

    /// What the window says of itself, a line each: what the device said
    /// of an AHardwareBuffer's image ([`hardware_buffer_said`]).
    fn said(&self) -> String {
        format!("{}\n", self.hardware_buffer)
    }

    /// The texture the kernels write, which [`Self::shown`] copies onto
    /// the swapchain's next image.
    pub(crate) fn drawn(&self) -> &wgpu::Texture {
        &self.drawn
    }

    /// What the kernels wrote, copied onto the swapchain's next image —
    /// submitted, and waited for by no one — and the image handed to
    /// Flutter once the GPU has finished the copy: Flutter waits on an
    /// image's fence only from API 33 (FlutterRenderer.java:788-811), and
    /// minSdk is 29. A body of the engine's thread, as the one that hands
    /// the image over is: a thread of the engine's for waits no caller
    /// stays for waits for the GPU between the two
    /// ([`Engine::done_then`]), and the bodies behind this one go on.
    ///
    /// One image is had at a time, so one a present before this copied
    /// onto goes up first where it has not: a present is asked for once
    /// the GPU has finished what its frame was drawn of
    /// (`ScreenTexture.present`), which that copy was submitted before.
    ///
    /// ⛔THE WHOLE IMAGE, EACH PRESENT — copying only what changed since an
    /// image last went out is not wgpu's to do (wgpu-core 30.0.1, read
    /// 2026-11-23 for 🗣️유저 11-22 「윈도랑 안드랑 다른거 통일못하는거야?」 ·
    /// 「그 길도 일단 확인가능한가?」, card
    /// the-galaxy-tab-canvas-went-slow-on-build-1095): an image is
    /// uninitialized each time the swapchain hands it over
    /// (present.rs:231-247); a copy onto less than all of it clears the
    /// whole first (command/transfer.rs:723-740, "we don't track
    /// subrects"); a read of it clears it too (transfer.rs:703-716); and
    /// its first use begins from Vulkan's UNDEFINED layout, which lets the
    /// driver throw its picture away (wgpu-hal vulkan/conv.rs:244). So
    /// what an image keeps cannot be asked through wgpu either: a probe
    /// that read a texel of each image as it came back was written and
    /// taken out that night — it would have said "nothing kept" on every
    /// device. That way needs a swapchain driven past wgpu.
    fn shown(&self, engine: &Engine) -> Option<()> {
        let mut copied = self.copied.lock().unwrap_or_else(PoisonError::into_inner);
        if let Some(before) = copied.image.take() {
            engine.queue.present(before);
        }
        let image = match self.surface.get_current_texture() {
            wgpu::CurrentSurfaceTexture::Success(image)
            | wgpu::CurrentSurfaceTexture::Suboptimal(image) => image,
            other => return fail(format!("get_current_texture: {other:?}")),
        };
        let mut encoder =
            engine.device().create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        encoder.copy_texture_to_texture(
            self.drawn.as_image_copy(),
            image.texture.as_image_copy(),
            self.drawn.size(),
        );
        engine.queue.submit([encoder.finish()]);
        copied.present += 1;
        let present = copied.present;
        copied.image = Some(image);
        drop(copied);
        let (hands, copied) = (engine.clone(), Arc::clone(&self.copied));
        engine.done_then(move |done| {
            let handing = hands.clone();
            hands.posted(move || {
                let mut copied = copied.lock().unwrap_or_else(PoisonError::into_inner);
                // Another present's by now.
                if copied.present != present {
                    return Some(());
                }
                // A copy the GPU did not finish is shown by no one — what
                // failed it is told where a done is asked for —, and a
                // window let go of meanwhile left no image (its `Drop`).
                match (copied.image.take(), done) {
                    (Some(image), Ok(())) => handing.queue.present(image),
                    (image, _) => drop(image),
                }
                Some(())
            });
        });
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
    engine.on_thread(|| {
        NonNull::new(native)
            .map(NativeWindow)
            .or_else(|| fail("no window"))
            .and_then(|native| Window::new(engine, native, width, height))
            .map_or(std::ptr::null_mut(), |window| engine.hands(window))
    })
}

/// The texture the kernels write for `window` — one for its life
/// ([`Window::drawn`]): where it is, read with no hand on the device.
///
/// # Safety
/// `window` is live; the texture lives as long as it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_window_target(window: *const Window) -> *const wgpu::Texture {
    // SAFETY: see the function's contract.
    std::ptr::from_ref(unsafe { &*window }.drawn())
}

/// Copies what `window` says of itself — what the device said of an
/// AHardwareBuffer's image ([`Window::said`]) — into `buffer` (UTF-8) and
/// returns its full length: what the window keeps on the heap, read with
/// no hand on the device.
///
/// # Safety
/// `window` is live and `buffer` holds `capacity` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_window_said(
    window: *const Window,
    buffer: *mut u8,
    capacity: usize,
) -> usize {
    // SAFETY: see the function's contract.
    copy_out(&unsafe { &*window }.said(), buffer, capacity)
}

/// Shows what the kernels last wrote to `window` ([`Window::shown`]), on
/// the engine's thread in its turn, its caller waiting for none of it
/// ([`Engine::posted`]): where it fails, the caller's next done fails by
/// it.
///
/// # Safety
/// `engine` and `window` are live, and `window` was made on `engine`.
/// `window` is let go of on the engine's thread ([`let_go`]), behind this
/// in turn.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_window_present(engine: *const Engine, window: *const Window) {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    let handed = Sent((engine.clone(), window));
    engine.posted(move || {
        let (engine, window) = handed.taken();
        // SAFETY: live till let go of, behind this (the function's
        // contract).
        unsafe { &*window }.shown(&engine)
    });
}

/// # Safety
/// `window` came from `gpu_engine_window_new`; Flutter's producer is
/// released after it, not before.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_window_free(window: *mut Window) {
    // SAFETY: see the function's contract.
    unsafe { let_go(window) };
}
