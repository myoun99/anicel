//! A wgpu texture that Flutter on Linux shows: a Vulkan image made on
//! wgpu's own device, in memory exported as a dma-buf, which Flutter's EGL
//! imports as the GL texture an FlTextureGL hands over.
//!
//! Each choice below is there because a source says so (gpu-engine-skeleton):
//! - Rgba8Unorm alone: Flutter's GL external texture takes GL_RGBA8 and
//!   nothing else (embedder/embedder_external_texture_gl.cc:153-156);
//!   DRM_FORMAT_ABGR8888 is that byte order.
//! - Vulkan, the backend Android's kernels already run on, rather than
//!   wgpu's GL: the dma-buf is how a Vulkan image reaches Flutter's EGL
//!   (gpu-engine-skeleton, 보드/인프라 2026-11-05).
//! - Made here, not by wgpu: wgpu-hal 30 imports dma-bufs
//!   (vulkan/device.rs:525) but exports none. The three extensions it
//!   needs are the ones wgpu turns on whenever the device has them
//!   (vulkan/adapter.rs:1344-1356).
//! - The LINEAR modifier: every EGL dma-buf importer takes it, so the
//!   plugin needs no modifier list of its own (보드/인프라, 2026-11-05).
//! - No release of the image to VK_QUEUE_FAMILY_FOREIGN_EXT: wgpu records
//!   no such barrier and leaves it to its caller (wgpu-hal-30.0.1/src/
//!   vulkan/device.rs:813-820). A LINEAR image has no compression for one
//!   to resolve, and the engine waits for the GPU before Flutter reads.
//! - Which GPU Flutter's EGL draws with is not handed to plugins, so the
//!   engine opens only where Vulkan lists one device (device.rs,
//!   `open_sole`); a PC with a GPU and Mesa's lavapipe lists two and opens
//!   none until the plugin round says how to match them.

use std::ffi::c_void;
use std::os::fd::{FromRawFd, OwnedFd};

use ash::{ext, khr, vk};
use wgpu::hal::api::Vulkan;

/// Flutter on Linux draws with GL; the engine reaches it through Vulkan.
pub const BACKENDS: wgpu::Backends = wgpu::Backends::VULKAN;

/// DRM_FORMAT_ABGR8888 (drm_fourcc.h): R, G, B, A in memory.
const ABGR8888: u32 = u32::from_le_bytes(*b"AB24");
/// DRM_FORMAT_MOD_LINEAR (drm_fourcc.h).
const MOD_LINEAR: u64 = 0;
const FORMAT: vk::Format = vk::Format::R8G8B8A8_UNORM;
const DMA_BUF: vk::ExternalMemoryHandleTypeFlags = vk::ExternalMemoryHandleTypeFlags::DMA_BUF_EXT;

/// The one plane Flutter's EGL imports the surface by.
#[repr(C)]
pub struct DmaBuf {
    pub fd: i32,
    pub fourcc: u32,
    pub offset: u64,
    pub stride: u64,
    pub modifier: u64,
}

/// The dma-buf's description, and the descriptor it names. The image
/// and its memory are wgpu's; closing the fd frees neither.
pub struct SharedHandle {
    plane: DmaBuf,
    _fd: OwnedFd,
}

impl SharedHandle {
    pub fn raw(&self) -> *mut c_void {
        (&raw const self.plane).cast_mut().cast()
    }
}

fn exportable(instance: &ash::Instance, physical: vk::PhysicalDevice) -> Result<(), String> {
    let mut modifier = vk::PhysicalDeviceImageDrmFormatModifierInfoEXT::default()
        .drm_format_modifier(MOD_LINEAR)
        .sharing_mode(vk::SharingMode::EXCLUSIVE);
    let mut external_info = vk::PhysicalDeviceExternalImageFormatInfo::default().handle_type(DMA_BUF);
    let info = vk::PhysicalDeviceImageFormatInfo2::default()
        .format(FORMAT)
        .ty(vk::ImageType::TYPE_2D)
        .tiling(vk::ImageTiling::DRM_FORMAT_MODIFIER_EXT)
        .usage(vk::ImageUsageFlags::STORAGE | vk::ImageUsageFlags::TRANSFER_SRC)
        .push_next(&mut external_info)
        .push_next(&mut modifier);
    let mut external = vk::ExternalImageFormatProperties::default();
    let mut properties = vk::ImageFormatProperties2::default().push_next(&mut external);
    // SAFETY: every structure is a local that outlives the call.
    unsafe { instance.get_physical_device_image_format_properties2(physical, &info, &mut properties) }
        .map_err(|error| format!("no linear storable rgba8 image here: {error}"))?;
    let features = external.external_memory_properties.external_memory_features;
    if !features.contains(vk::ExternalMemoryFeatureFlags::EXPORTABLE) {
        return Err("a linear rgba8 image cannot be exported as a dma-buf here".into());
    }
    Ok(())
}

fn memory_type(
    instance: &ash::Instance,
    physical: vk::PhysicalDevice,
    allowed: u32,
) -> Result<u32, String> {
    // SAFETY: only reads the device's memory types.
    let memory = unsafe { instance.get_physical_device_memory_properties(physical) };
    let types = &memory.memory_types[..memory.memory_type_count as usize];
    let allowed = |index: usize| allowed & (1 << index) != 0;
    let local = |index: usize| {
        types[index]
            .property_flags
            .contains(vk::MemoryPropertyFlags::DEVICE_LOCAL)
    };
    (0..types.len())
        .find(|&index| allowed(index) && local(index))
        .or_else(|| (0..types.len()).find(|&index| allowed(index)))
        .map(|index| index as u32)
        .ok_or_else(|| "no memory type takes the image".into())
}

/// The image, its dedicated exportable memory, and the dma-buf it is.
fn exported_image(
    instance: &ash::Instance,
    device: &ash::Device,
    physical: vk::PhysicalDevice,
    width: u32,
    height: u32,
) -> Result<(vk::Image, vk::DeviceMemory, OwnedFd), String> {
    let modifiers = [MOD_LINEAR];
    let mut modifier_list =
        vk::ImageDrmFormatModifierListCreateInfoEXT::default().drm_format_modifiers(&modifiers);
    let mut external = vk::ExternalMemoryImageCreateInfo::default().handle_types(DMA_BUF);
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
        .tiling(vk::ImageTiling::DRM_FORMAT_MODIFIER_EXT)
        .usage(vk::ImageUsageFlags::STORAGE | vk::ImageUsageFlags::TRANSFER_SRC)
        .sharing_mode(vk::SharingMode::EXCLUSIVE)
        .initial_layout(vk::ImageLayout::UNDEFINED)
        .push_next(&mut external)
        .push_next(&mut modifier_list);
    // SAFETY: `exportable` said the device takes this image.
    let image = unsafe { device.create_image(&info, None) }
        .map_err(|error| format!("vkCreateImage: {error}"))?;
    let made = (|| {
        // SAFETY: the image is live.
        let requirements = unsafe { device.get_image_memory_requirements(image) };
        let mut export = vk::ExportMemoryAllocateInfo::default().handle_types(DMA_BUF);
        let mut dedicated = vk::MemoryDedicatedAllocateInfo::default().image(image);
        let allocation = vk::MemoryAllocateInfo::default()
            .allocation_size(requirements.size)
            .memory_type_index(memory_type(instance, physical, requirements.memory_type_bits)?)
            .push_next(&mut export)
            .push_next(&mut dedicated);
        // SAFETY: the allocation is dedicated to the live image.
        let memory = unsafe { device.allocate_memory(&allocation, None) }
            .map_err(|error| format!("vkAllocateMemory: {error}"))?;
        let fd = (|| {
            // SAFETY: the memory was made for this image, whole.
            unsafe { device.bind_image_memory(image, memory, 0) }
                .map_err(|error| format!("vkBindImageMemory: {error}"))?;
            let get = vk::MemoryGetFdInfoKHR::default().memory(memory).handle_type(DMA_BUF);
            // SAFETY: the memory was allocated exportable as a dma-buf.
            let fd = unsafe { khr::external_memory_fd::Device::new(instance, device).get_memory_fd(&get) }
                .map_err(|error| format!("vkGetMemoryFdKHR: {error}"))?;
            // SAFETY: the call hands over a new descriptor of our own.
            Ok(unsafe { OwnedFd::from_raw_fd(fd) })
        })();
        match fd {
            Ok(fd) => Ok((memory, fd)),
            Err(error) => {
                // SAFETY: nothing else holds the memory yet.
                unsafe { device.free_memory(memory, None) };
                Err(error)
            }
        }
    })();
    match made {
        Ok((memory, fd)) => Ok((image, memory, fd)),
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
) -> Result<(wgpu::Texture, SharedHandle), String> {
    if format != wgpu::TextureFormat::Rgba8Unorm {
        return Err(format!("{format:?} is not a format Flutter's GL texture shows"));
    }
    // SAFETY: the raw device is only used to make an image and its memory,
    // never to change wgpu's own state.
    let hal_device = unsafe { device.as_hal::<Vulkan>() }.ok_or("not a Vulkan device")?;
    let enabled = hal_device.enabled_device_extensions();
    let needed = [
        khr::external_memory_fd::NAME,
        ext::external_memory_dma_buf::NAME,
        ext::image_drm_format_modifier::NAME,
    ];
    if let Some(missing) = needed.iter().find(|name| !enabled.contains(name)) {
        return Err(format!("the Vulkan device has no {}", missing.to_string_lossy()));
    }
    let instance = hal_device.shared_instance().raw_instance();
    let physical = hal_device.raw_physical_device();
    exportable(instance, physical)?;
    let (image, memory, fd) =
        exported_image(instance, hal_device.raw_device(), physical, width, height)?;
    let plane_0 = vk::ImageSubresource {
        aspect_mask: vk::ImageAspectFlags::MEMORY_PLANE_0_EXT,
        mip_level: 0,
        array_layer: 0,
    };
    // SAFETY: the image is live and has one memory plane.
    let layout = unsafe { hal_device.raw_device().get_image_subresource_layout(image, plane_0) };
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
                usage: wgpu::TextureUses::STORAGE_WRITE_ONLY | wgpu::TextureUses::COPY_SRC,
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
    let texture = unsafe {
        device.create_texture_from_hal::<Vulkan>(
            hal_texture,
            &wgpu::TextureDescriptor {
                label: Some("shared surface"),
                size,
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format,
                usage: wgpu::TextureUsages::STORAGE_BINDING | wgpu::TextureUsages::COPY_SRC,
                view_formats: &[],
            },
            wgpu::TextureUses::UNINITIALIZED,
        )
    };
    let plane = DmaBuf {
        fd: std::os::fd::AsRawFd::as_raw_fd(&fd),
        fourcc: ABGR8888,
        offset: layout.offset,
        stride: layout.row_pitch,
        modifier: MOD_LINEAR,
    };
    Ok((texture, SharedHandle { plane, _fd: fd }))
}

/// Vulkan names no adapter by LUID that Flutter's GL would match; Flutter
/// is matched by there being one device (device.rs, `open_sole`).
pub fn adapter_luid(_adapter: &wgpu::Adapter) -> Option<u64> {
    None
}

pub fn video_memory(_adapter: &wgpu::Adapter) -> Option<u64> {
    None
}

#[cfg(test)]
mod tests {
    use crate::kernels::fill::Fill;
    use crate::testing::{assert_pinned, first_engine};

    // fill's own ledger row (kernels/fill/tests.rs): 70 x 45, so the
    // plane's rows may be wider than the picture.
    const WIDTH: u32 = 70;
    const HEIGHT: u32 = 45;
    const BYTES_PER_TEXEL: usize = 4;

    // DMA_BUF_IOCTL_SYNC and its flags (linux/dma-buf.h): _IOW('b', 0,
    // struct dma_buf_sync { __u64 flags; }).
    const DMA_BUF_IOCTL_SYNC: libc::c_ulong = 0x4008_6200;
    const DMA_BUF_SYNC_READ: u64 = 1;
    const DMA_BUF_SYNC_END: u64 = 1 << 2;

    fn sync(fd: i32, flags: u64) {
        // SAFETY: `flags` is the struct the ioctl reads.
        let done = unsafe { libc::ioctl(fd, DMA_BUF_IOCTL_SYNC, &flags) };
        assert_eq!(done, 0, "DMA_BUF_IOCTL_SYNC");
    }

    // What Flutter's EGL imports is the dma-buf, not the wgpu texture: the
    // kernel's bytes must be in it, row for row, where the plane says.
    // Read by mapping it, which lavapipe's memory allows; a GPU whose
    // device-local memory the CPU cannot map would refuse the mmap with
    // the bridge itself sound.
    #[test]
    fn flutter_is_handed_the_bytes_the_kernel_wrote() {
        let engine = first_engine();
        let (texture, shared) =
            super::create(&engine.device, WIDTH, HEIGHT, wgpu::TextureFormat::Rgba8Unorm)
                .expect("shared surface");
        Fill::new(engine).run(engine, &texture, 7).expect("fill");
        let plane = &shared.plane;
        let (offset, stride) = (plane.offset as usize, plane.stride as usize);
        let length = offset + stride * HEIGHT as usize;
        // SAFETY: maps the dma-buf read-only for as long as its plane runs.
        let map = unsafe {
            libc::mmap(
                std::ptr::null_mut(),
                length,
                libc::PROT_READ,
                libc::MAP_SHARED,
                plane.fd,
                0,
            )
        };
        assert_ne!(map, libc::MAP_FAILED, "mmap the dma-buf");
        sync(plane.fd, DMA_BUF_SYNC_READ);
        let base = map.cast::<u8>();
        let row = WIDTH as usize * BYTES_PER_TEXEL;
        let bytes: Vec<u8> = (0..HEIGHT as usize)
            // SAFETY: each row lies inside the mapping, `stride` after the last.
            .flat_map(|y| unsafe { std::slice::from_raw_parts(base.add(offset + y * stride), row) }.to_vec())
            .collect();
        sync(plane.fd, DMA_BUF_SYNC_READ | DMA_BUF_SYNC_END);
        // SAFETY: unmaps exactly what was mapped above.
        unsafe { libc::munmap(map, length) };
        assert_pinned("fill/70x45-seed7-rgba", &bytes);
    }

    // Flutter's GL texture is GL_RGBA8 alone, so a BGRA surface is refused
    // rather than shown with red and blue swapped.
    #[test]
    fn a_bgra_surface_is_refused() {
        let engine = first_engine();
        let made = super::create(&engine.device, WIDTH, HEIGHT, wgpu::TextureFormat::Bgra8Unorm);
        assert!(made.is_err());
    }
}
