//! A wgpu texture that Flutter on Android shows: a Vulkan image made on
//! wgpu's own device, in the memory of an AHardwareBuffer the engine
//! allocated, which Flutter's Impeller imports as it imports an Image's
//! buffer (image_external_texture_vk_impeller.cc) — handed to it as the
//! one buffer of a texture of its own (`GpuEnginePlugin.register`,
//! `TextureRegistry.createHardwareBufferTexture`, which Anicel's Flutter
//! patch 0006 adds). Two such surfaces are shown turn about, as on every
//! other platform (the app's `ScreenTexture`).
//!
//! Each choice below is there because a source says so (gpu-engine-skeleton):
//! - Vulkan only: whether GLES-only devices get compute is
//!   gpu-engine-feasibility's open question (Q3); the device stage 0
//!   measures on (SM-X910, Adreno 740) has Vulkan.
//! - RGBA8 unorm: AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM is that byte
//!   order, and the bytes the kernels write are the bytes shown, with no
//!   sRGB encode between, as on Windows.
//! - Made here, not by wgpu: wgpu-hal 30 imports no AHardwareBuffer. The
//!   extension is turned on by Anicel's edit of the vendored wgpu-hal
//!   (vulkan/adapter.rs, `ANICEL`), where the device has it.
//! - The buffer's usage is GPU_SAMPLED_IMAGE, and CPU_READ_RARELY for a
//!   screen's ([`allocated`]): Flutter samples it, and
//!   no AHardwareBuffer usage stands for a Vulkan storage image — whether
//!   the kernels may store into one is the device's own answer
//!   ([`takes`]), asked before an image is made; where it says no, what
//!   they write is copied onto the buffer's image ([`Way::Copied`]).
//! - No release of the image to VK_QUEUE_FAMILY_FOREIGN_EXT, as on Linux
//!   (linux.rs): wgpu records no such barrier and leaves it to its caller
//!   (wgpu-hal-30.0.1/src/vulkan/device.rs:813-820). The image is OPTIMAL —
//!   the only tiling an AHardwareBuffer is imported by — so the law of a
//!   screen's buffer (platform/mod.rs) is kept by asking for
//!   CPU_READ_RARELY ([`allocated`]), which drivers lay out uncompressed.
//!   ⚠️A request, not a guarantee as Linux's LINEAR is: the debug screen's
//!   check measures a buffer laid each way (card
//!   the-galaxy-tab-canvas-went-slow-on-build-1095, ⓑ and ⓒ).
//!
//! ↩️TILL 2026-11-23 ANDROID ALONE SHOWED A WINDOW Flutter made — a
//! SurfaceProducer's queue, which only takes images an app cannot make —,
//! copying the engine's texture whole onto the queue's next image each
//! frame, on the engine's thread, and handing the image over once the GPU
//! had finished the copy. 🗣️유저 2026-11-22 「윈도랑 안드랑 다른거
//! 통일못하는거야?」, 2026-11-23 「통일을 말한게 언제적인데」 (card
//! the-galaxy-tab-canvas-went-slow-on-build-1095, 길 A): one way for
//! every platform. That way also placed a frame's picture apart from where
//! the layer tree put it — the raster took the queue's newest image, the
//! tree the frame before's place (card
//! panning-then-pen-jumps-the-android-canvas-a-frame, H68).

use std::ffi::c_void;
use std::ptr::NonNull;

use ash::vk;
use wgpu::hal::api::Vulkan;

use super::Laid;
use crate::device::storage_texture;

pub const BACKENDS: wgpu::Backends = wgpu::Backends::VULKAN;

const FORMAT: vk::Format = vk::Format::R8G8B8A8_UNORM;
const AHB: vk::ExternalMemoryHandleTypeFlags =
    vk::ExternalMemoryHandleTypeFlags::ANDROID_HARDWARE_BUFFER_ANDROID;

/// AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM (hardware_buffer.h).
const AHB_FORMAT_R8G8B8A8_UNORM: u32 = 1;
/// AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE (hardware_buffer.h).
const AHB_USAGE_GPU_SAMPLED_IMAGE: u64 = 1 << 8;
/// AHARDWAREBUFFER_USAGE_CPU_READ_RARELY (hardware_buffer.h).
const AHB_USAGE_CPU_READ_RARELY: u64 = 2;

/// AHardwareBuffer_Desc (hardware_buffer.h).
#[repr(C)]
struct BufferDesc {
    width: u32,
    height: u32,
    layers: u32,
    format: u32,
    usage: u64,
    stride: u32,
    rfu0: u32,
    rfu1: u64,
}

#[link(name = "android")]
unsafe extern "C" {
    fn AHardwareBuffer_allocate(desc: *const BufferDesc, out: *mut *mut vk::AHardwareBuffer) -> i32;
    fn AHardwareBuffer_release(buffer: *mut vk::AHardwareBuffer);
    fn AHardwareBuffer_toHardwareBuffer(env: *mut c_void, buffer: *mut vk::AHardwareBuffer) -> *mut c_void;
}

/// The engine's reference to the AHardwareBuffer a surface's image lives
/// in — what Flutter is handed (`gpu_engine_surface_handle`) — and, where
/// the kernels cannot store into that image ([`Way::Copied`]), the image
/// itself, which what they wrote is copied onto ([`Self::shown`]). The
/// image's memory holds a reference of the buffer's own, which wgpu lets
/// go of with it.
pub struct SharedHandle {
    buffer: NonNull<vk::AHardwareBuffer>,
    shown: Option<wgpu::Texture>,
}

// SAFETY: an AHardwareBuffer reference may be used and released on any
// thread (hardware_buffer.h).
unsafe impl Send for SharedHandle {}
// SAFETY: as above; nothing of it is changed through a shared reference.
unsafe impl Sync for SharedHandle {}

impl SharedHandle {
    pub fn raw(&self) -> *mut c_void {
        self.buffer.as_ptr().cast()
    }

    /// What Flutter shows, where it is not the texture the kernels write:
    /// the AHardwareBuffer's image on a device whose screens are copied
    /// onto ([`Way::Copied`]); none where the kernels store into it.
    pub fn shown(&self) -> Option<&wgpu::Texture> {
        self.shown.as_ref()
    }
}

impl Drop for SharedHandle {
    fn drop(&mut self) {
        // SAFETY: the reference came from AHardwareBuffer_allocate and is
        // released once.
        unsafe { AHardwareBuffer_release(self.buffer.as_ptr()) };
    }
}

/// How a device's screens reach Flutter's ([`way`]).
enum Way {
    /// The kernels store into the AHardwareBuffer's image itself.
    Direct,
    /// They store into a texture of the engine's own, and what of it
    /// changed is copied onto the buffer's image before a frame is shown
    /// (`gpu_engine_surface_settle`) — where the device makes no storable
    /// image of an AHardwareBuffer, which the words say why.
    ///
    /// 🗣️유저 2026-11-23 (card the-galaxy-tab-canvas-went-slow-on-build-1095-Q9
    /// 「그 기기만 바뀐 곳을 한 번 옮겨 보여 준다」, after 「판단하기전에
    /// 어느기기가 안되는지 조사해줘」: whether a device stores into one is its
    /// driver's choice, not its age — 관제's reading of the Vulkan spec and
    /// the CTS). The app's way to the screen stays one on every device; this
    /// is the engine's alone.
    Copied(String),
}

/// What the kernels do with an image they store into: store into it, and
/// copy from it (a view moved, `kernels/composite/moved.rs`; a readback).
const STORED: vk::ImageUsageFlags = vk::ImageUsageFlags::from_raw(
    vk::ImageUsageFlags::STORAGE.as_raw() | vk::ImageUsageFlags::TRANSFER_SRC.as_raw(),
);
/// What the engine does with an image it copies onto ([`Way::Copied`]).
const COPIED_ONTO: vk::ImageUsageFlags = vk::ImageUsageFlags::TRANSFER_DST;

/// Whether the device makes an image of [`FORMAT`] and `usage` in an
/// AHardwareBuffer's memory: `Ok` where it does, else what it said.
fn takes(instance: &ash::Instance, physical: vk::PhysicalDevice, usage: vk::ImageUsageFlags) -> Result<(), String> {
    let mut external_info = vk::PhysicalDeviceExternalImageFormatInfo::default().handle_type(AHB);
    let info = vk::PhysicalDeviceImageFormatInfo2::default()
        .format(FORMAT)
        .ty(vk::ImageType::TYPE_2D)
        .tiling(vk::ImageTiling::OPTIMAL)
        .usage(usage)
        .push_next(&mut external_info);
    let mut external = vk::ExternalImageFormatProperties::default();
    let mut properties = vk::ImageFormatProperties2::default().push_next(&mut external);
    // SAFETY: every structure is a local that outlives the call.
    match unsafe { instance.get_physical_device_image_format_properties2(physical, &info, &mut properties) } {
        Ok(()) => {}
        Err(vk::Result::ERROR_FORMAT_NOT_SUPPORTED) => return Err("no".to_owned()),
        Err(error) => return Err(format!("{error:?}")),
    }
    let features = external.external_memory_properties.external_memory_features;
    if !features.contains(vk::ExternalMemoryFeatureFlags::IMPORTABLE) {
        return Err("not-imported".to_owned());
    }
    Ok(())
}

/// The way the device's screens reach Flutter's ([`Way`]), or what stands
/// between it and a screen of an AHardwareBuffer, the first thing missing
/// named: the extension, Vulkan 1.1, or the device's answers for an image
/// stored into and one copied onto ([`takes`]).
fn way(hal_device: &wgpu::hal::vulkan::Device) -> Result<Way, String> {
    let name = ash::android::external_memory_android_hardware_buffer::NAME;
    if !hal_device.enabled_device_extensions().contains(&name) {
        return Err(format!("the Vulkan device has no {}", name.to_string_lossy()));
    }
    let shared = hal_device.shared_instance();
    // ⛔The question is Vulkan 1.1's own, of the instance and of the device
    // both. Of an instance made as 1.0, ash has no function for it and its
    // stand-in panics inside an `extern "system"` function — which no
    // `catch_unwind` catches: the process ends. (The extension is turned on
    // only on a 1.1 device, `ANICEL` in vulkan/adapter.rs.)
    if shared.instance_api_version() < vk::API_VERSION_1_1 {
        return Err("a Vulkan 1.0 instance".to_owned());
    }
    let (instance, physical) = (shared.raw_instance(), hal_device.raw_physical_device());
    match takes(instance, physical, STORED) {
        Ok(()) => Ok(Way::Direct),
        Err(stored) => match takes(instance, physical, COPIED_ONTO) {
            Ok(()) => Ok(Way::Copied(format!("ahb storage {stored}"))),
            Err(copied) => Err(format!("ahb storage {stored}  copy {copied}")),
        },
    }
}

/// 🔬What the device says of a screen of an AHardwareBuffer, for the debug
/// screen: `ahb` where the kernels store into one, `ahb copy — ` and why
/// where what they write is copied onto one ([`Way::Copied`]), else
/// `ahb no — ` and what stands in the way ([`way`]); and beside the first
/// two whether it would make one Flutter draws into (`color`, which every
/// device is expected to allow: a `no` there says the question itself did
/// not get through).
///
/// 🗣️공통 2026-11-22 23:50, of 유저's 「윈도랑 안드랑 다른거
/// 통일못하는거야?」 (card the-galaxy-tab-canvas-went-slow-on-build-1095):
/// whether the kernels could write that buffer is each device's own
/// answer, the Galaxy Tab's (Adreno 740) among them.
pub fn screen_said(device: &wgpu::Device) -> String {
    // SAFETY: the raw device is asked what it supports, and nothing of
    // wgpu's own state is changed.
    let Some(hal_device) = (unsafe { device.as_hal::<Vulkan>() }) else {
        return "ahb no — not a Vulkan device".to_owned();
    };
    let color = || {
        let shared = hal_device.shared_instance();
        let color = takes(
            shared.raw_instance(),
            hal_device.raw_physical_device(),
            vk::ImageUsageFlags::COLOR_ATTACHMENT | vk::ImageUsageFlags::SAMPLED,
        );
        color.err().unwrap_or_else(|| "yes".to_owned())
    };
    match way(&hal_device) {
        Ok(Way::Direct) => format!("ahb  color {}", color()),
        Ok(Way::Copied(why)) => format!("ahb copy — {why}  color {}", color()),
        Err(standing) => format!("ahb no — {standing}"),
    }
}

/// An AHardwareBuffer for a surface. [`Laid::ForTheCpuToo`] asks for one
/// the CPU may read now and then as well, which drivers lay out
/// uncompressed: no compression for the two devices to see differently,
/// where nothing hands the image from one to the other — the law of a
/// screen's buffer (platform/mod.rs).
///
/// 🗣️관제 2026-11-24 01:58 (card the-galaxy-tab-canvas-went-slow-on-build-1095,
/// ⓒ of risks 2 and 3, user asked as Q11): the screen asks for it — a
/// canvas always broken is worse than the bandwidth —, and the debug
/// screen's check measures both layouts, so one look at a device says
/// whether it was needed.
fn allocated(width: u32, height: u32, laid: Laid) -> Result<NonNull<vk::AHardwareBuffer>, String> {
    let cpu = match laid {
        Laid::ForTheCpuToo => AHB_USAGE_CPU_READ_RARELY,
        Laid::AsTheDriverChooses => 0,
    };
    let desc = BufferDesc {
        width,
        height,
        layers: 1,
        format: AHB_FORMAT_R8G8B8A8_UNORM,
        usage: AHB_USAGE_GPU_SAMPLED_IMAGE | cpu,
        stride: 0,
        rfu0: 0,
        rfu1: 0,
    };
    let mut buffer = std::ptr::null_mut();
    // SAFETY: `desc` is a live AHardwareBuffer_Desc and `buffer` a place
    // for the reference.
    let said = unsafe { AHardwareBuffer_allocate(&desc, &mut buffer) };
    match NonNull::new(buffer) {
        Some(buffer) if said == 0 => Ok(buffer),
        _ => Err(format!("AHardwareBuffer_allocate: {said}")),
    }
}

/// The image of `usage` in `buffer`'s memory, and that memory, imported and
/// bound.
fn imported_image(
    instance: &ash::Instance,
    device: &ash::Device,
    buffer: NonNull<vk::AHardwareBuffer>,
    (width, height): (u32, u32),
    usage: vk::ImageUsageFlags,
) -> Result<(vk::Image, vk::DeviceMemory), String> {
    let ahb = ash::android::external_memory_android_hardware_buffer::Device::new(instance, device);
    let mut format = vk::AndroidHardwareBufferFormatPropertiesANDROID::default();
    let mut properties = vk::AndroidHardwareBufferPropertiesANDROID::default().push_next(&mut format);
    // SAFETY: the buffer is live; every structure is a local.
    unsafe { ahb.get_android_hardware_buffer_properties(buffer.as_ptr(), &mut properties) }
        .map_err(|error| format!("vkGetAndroidHardwareBufferPropertiesANDROID: {error}"))?;
    let (size, memory_types) = (properties.allocation_size, properties.memory_type_bits);
    if format.format != FORMAT {
        return Err(format!("the buffer is {:?} to Vulkan, not {FORMAT:?}", format.format));
    }
    if memory_types == 0 {
        return Err("no memory type takes the buffer".to_owned());
    }
    let mut external = vk::ExternalMemoryImageCreateInfo::default().handle_types(AHB);
    let info = vk::ImageCreateInfo::default()
        .image_type(vk::ImageType::TYPE_2D)
        .format(FORMAT)
        .extent(vk::Extent3D {
            width,
            height,
            depth: 1,
        })
        .mip_levels(1)
        .array_layers(1)
        .samples(vk::SampleCountFlags::TYPE_1)
        .tiling(vk::ImageTiling::OPTIMAL)
        .usage(usage)
        .sharing_mode(vk::SharingMode::EXCLUSIVE)
        .initial_layout(vk::ImageLayout::UNDEFINED)
        .push_next(&mut external);
    // SAFETY: `way` said the device takes this image.
    let image = unsafe { device.create_image(&info, None) }.map_err(|error| format!("vkCreateImage: {error}"))?;
    let made = (|| {
        let mut import = vk::ImportAndroidHardwareBufferInfoANDROID::default().buffer(buffer.as_ptr());
        let mut dedicated = vk::MemoryDedicatedAllocateInfo::default().image(image);
        let allocation = vk::MemoryAllocateInfo::default()
            .allocation_size(size)
            .memory_type_index(memory_types.trailing_zeros())
            .push_next(&mut import)
            .push_next(&mut dedicated);
        // SAFETY: the allocation imports the live buffer, dedicated to the
        // live image; the memory takes a reference of the buffer's own.
        let memory = unsafe { device.allocate_memory(&allocation, None) }
            .map_err(|error| format!("vkAllocateMemory (import): {error}"))?;
        // SAFETY: the memory was imported for this image, whole.
        match unsafe { device.bind_image_memory(image, memory, 0) } {
            Ok(()) => Ok(memory),
            Err(error) => {
                // SAFETY: nothing else holds the memory yet.
                unsafe { device.free_memory(memory, None) };
                Err(format!("vkBindImageMemory: {error}"))
            }
        }
    })();
    match made {
        Ok(memory) => Ok((image, memory)),
        Err(error) => {
            // SAFETY: nothing else holds the image yet.
            unsafe { device.destroy_image(image, None) };
            Err(error)
        }
    }
}

pub fn create(
    device: &wgpu::Device,
    width: u32,
    height: u32,
    format: wgpu::TextureFormat,
    laid: Laid,
) -> Result<(wgpu::Texture, SharedHandle), String> {
    if format != wgpu::TextureFormat::Rgba8Unorm {
        return Err(format!("{format:?} is not a format Flutter's AHardwareBuffer texture shows"));
    }
    // SAFETY: the raw device is only used to make an image and its memory,
    // never to change wgpu's own state.
    let hal_device = unsafe { device.as_hal::<Vulkan>() }.ok_or("not a Vulkan device")?;
    let way = way(&hal_device)?;
    let ((vk_usage, hal_usage), usage) = match way {
        Way::Direct => (
            (STORED, wgpu::TextureUses::STORAGE_WRITE_ONLY | wgpu::TextureUses::COPY_SRC),
            wgpu::TextureUsages::STORAGE_BINDING | wgpu::TextureUsages::COPY_SRC,
        ),
        Way::Copied(_) => ((COPIED_ONTO, wgpu::TextureUses::COPY_DST), wgpu::TextureUsages::COPY_DST),
    };
    let buffer = SharedHandle {
        buffer: allocated(width, height, laid)?,
        shown: None,
    };
    let instance = hal_device.shared_instance().raw_instance();
    let (image, memory) =
        imported_image(instance, hal_device.raw_device(), buffer.buffer, (width, height), vk_usage)?;
    let size = wgpu::Extent3d {
        width,
        height,
        depth_or_array_layers: 1,
    };
    // SAFETY: the image is a single-mip, single-layer 2D image of exactly
    // this size and format; wgpu-hal takes the image and its memory.
    let hal_texture = unsafe {
        hal_device.texture_from_raw(
            image,
            &wgpu::hal::TextureDescriptor {
                label: Some("shared surface"),
                size,
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format,
                usage: hal_usage,
                memory_flags: wgpu::hal::MemoryFlags::empty(),
                view_formats: Vec::new(),
            },
            None,
            wgpu::hal::vulkan::TextureMemory::Dedicated(memory),
        )
    };
    drop(hal_device);
    // SAFETY: the texture matches the descriptor and is in UNDEFINED
    // layout, which is what UNINITIALIZED stands for.
    let imported = unsafe {
        device.create_texture_from_hal::<Vulkan>(
            hal_texture,
            &wgpu::TextureDescriptor {
                label: Some("shared surface"),
                size,
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format,
                usage,
                view_formats: &[],
            },
            wgpu::TextureUses::UNINITIALIZED,
        )
    };
    let mut buffer = buffer;
    Ok(match way {
        Way::Direct => (imported, buffer),
        Way::Copied(_) => {
            buffer.shown = Some(imported);
            (storage_texture(device, width, height, format), buffer)
        }
    })
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

/// The `android.hardware.HardwareBuffer` of `buffer`, a surface's
/// AHardwareBuffer (`gpu_engine_surface_handle`), for
/// `GpuEnginePlugin.register` to hand Flutter: a local reference of its
/// own, holding a reference of the buffer's own; null where there is none.
///
/// # Safety
/// Called by the JVM, with its `JNIEnv`; `buffer` is a live surface's.
#[unsafe(no_mangle)]
pub unsafe extern "system" fn Java_com_myoun_gpu_1engine_GpuEnginePlugin_hardwareBufferOf(
    env: *mut c_void,
    _plugin: *mut c_void,
    buffer: i64,
) -> *mut c_void {
    match NonNull::new(buffer as *mut vk::AHardwareBuffer) {
        // SAFETY: see the function's contract.
        Some(buffer) => unsafe { AHardwareBuffer_toHardwareBuffer(env, buffer.as_ptr()) },
        None => std::ptr::null_mut(),
    }
}
