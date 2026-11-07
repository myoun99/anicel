//! A wgpu texture that Flutter on iOS and macOS shows: one IOSurface,
//! seen by wgpu's Metal device as the texture kernels write and by
//! Flutter as the CVPixelBuffer a FlutterTexture hands over.
//!
//! Each choice below is there because a source says so (gpu-engine-skeleton):
//! - 32BGRA: the only RGB layout `copyPixelBuffer` may return
//!   (darwin/common/framework/Headers/FlutterTexture.h:25-30); Flutter
//!   opens it as BGRA8Unorm through a CVMetalTextureCache and hands that
//!   to Impeller without a copy (FlutterDarwinExternalTextureMetal.mm:
//!   235-254, 359).
//! - The IOSurface properties and the texture descriptor are the ones
//!   Flutter's own macOS surfaces use (macos/framework/Source/
//!   FlutterSurface.mm:94-136), minus the render-target use no kernel
//!   needs.
//! - Which device Flutter draws with is not handed to plugins, so the
//!   engine opens only where there is one (device.rs, `open_sole`): a
//!   dual-GPU Intel Mac, where Flutter takes the integrated GPU and wgpu
//!   lists the discrete one first (FlutterRenderer.mm:46-56 against
//!   wgpu-hal-30.0.1/src/metal/mod.rs:200-205), opens none until the
//!   plugin round says how to match them.

use std::ffi::c_void;
use std::ptr::{self, NonNull};

use objc2::rc::Retained;
use objc2::runtime::ProtocolObject;
use objc2_core_foundation::{CFDictionary, CFNumber, CFRetained, CFString};
use objc2_core_video::{
    CVPixelBuffer, CVPixelBufferCreateWithIOSurface, kCVPixelFormatType_32BGRA, kCVReturnSuccess,
};
use objc2_io_surface::{
    IOSurfaceRef, kIOSurfaceAllocSize, kIOSurfaceBytesPerElement, kIOSurfaceBytesPerRow,
    kIOSurfaceHeight, kIOSurfacePixelFormat, kIOSurfaceWidth,
};
use objc2_metal::{
    MTLDevice, MTLPixelFormat, MTLTexture, MTLTextureDescriptor, MTLTextureType, MTLTextureUsage,
};
use wgpu::hal::api::Metal;

/// Flutter on Apple draws with Metal; no other wgpu backend reaches an
/// IOSurface.
pub const BACKENDS: wgpu::Backends = wgpu::Backends::METAL;

const BYTES_PER_TEXEL: usize = 4;

/// The CVPixelBuffer Flutter is handed, over the IOSurface the texture
/// writes. Each holds its own reference, so neither outlives the other's
/// pixels.
pub struct SharedHandle {
    pixels: CFRetained<CVPixelBuffer>,
    _surface: CFRetained<IOSurfaceRef>,
}

impl SharedHandle {
    /// Not retained for the caller: `copyPixelBuffer` hands Flutter a
    /// reference Flutter releases (FlutterDarwinExternalTextureMetal.mm:
    /// 84-87), so the plugin retains this before returning it.
    pub fn raw(&self) -> *mut c_void {
        CFRetained::as_ptr(&self.pixels).as_ptr().cast()
    }
}

fn number(value: usize) -> CFRetained<CFNumber> {
    CFNumber::new_i64(value as i64)
}

fn io_surface(width: u32, height: u32) -> Result<CFRetained<IOSurfaceRef>, String> {
    let (width, height) = (width as usize, height as usize);
    // SAFETY: reading the framework's constant keys.
    let keys: [&CFString; 6] = unsafe {
        [
            kIOSurfaceWidth,
            kIOSurfaceHeight,
            kIOSurfacePixelFormat,
            kIOSurfaceBytesPerElement,
            kIOSurfaceBytesPerRow,
            kIOSurfaceAllocSize,
        ]
    };
    // SAFETY: as above.
    let row = IOSurfaceRef::align_property(unsafe { kIOSurfaceBytesPerRow }, width * BYTES_PER_TEXEL);
    // SAFETY: as above.
    let size = IOSurfaceRef::align_property(unsafe { kIOSurfaceAllocSize }, height * row);
    let values = [
        number(width),
        number(height),
        number(kCVPixelFormatType_32BGRA as usize),
        number(BYTES_PER_TEXEL),
        number(row),
        number(size),
    ];
    let values: Vec<&CFNumber> = values.iter().map(|value| &**value).collect();
    let properties = CFDictionary::<CFString, CFNumber>::from_slices(&keys, &values);
    // SAFETY: every key is an IOSurface property whose value is a number.
    unsafe { IOSurfaceRef::new(properties.as_ref()) }.ok_or_else(|| "IOSurfaceCreate gave no surface".into())
}

fn pixel_buffer(surface: &IOSurfaceRef) -> Result<CFRetained<CVPixelBuffer>, String> {
    let mut out: *mut CVPixelBuffer = ptr::null_mut();
    // SAFETY: `out` is a local the call writes once.
    let status =
        unsafe { CVPixelBufferCreateWithIOSurface(None, surface, None, NonNull::from(&mut out)) };
    if status != kCVReturnSuccess {
        return Err(format!("CVPixelBufferCreateWithIOSurface: {status}"));
    }
    let out = NonNull::new(out).ok_or("CVPixelBufferCreateWithIOSurface gave no buffer")?;
    // SAFETY: a Create call hands over the one reference it made.
    Ok(unsafe { CFRetained::from_raw(out) })
}

fn metal_texture(
    device: &ProtocolObject<dyn MTLDevice>,
    surface: &IOSurfaceRef,
    width: u32,
    height: u32,
) -> Result<Retained<ProtocolObject<dyn MTLTexture>>, String> {
    // SAFETY: a plain 2D descriptor of the surface's own size and layout.
    let desc = unsafe {
        MTLTextureDescriptor::texture2DDescriptorWithPixelFormat_width_height_mipmapped(
            MTLPixelFormat::BGRA8Unorm,
            width as usize,
            height as usize,
            false,
        )
    };
    desc.setUsage(MTLTextureUsage::ShaderRead | MTLTextureUsage::ShaderWrite);
    // Plane 0 is the whole surface for BGRA.
    device
        .newTextureWithDescriptor_iosurface_plane(&desc, surface, 0)
        .ok_or_else(|| "newTextureWithDescriptor:iosurface:plane: gave no texture".into())
}

pub fn create(
    device: &wgpu::Device,
    width: u32,
    height: u32,
    format: wgpu::TextureFormat,
) -> Result<(wgpu::Texture, SharedHandle), String> {
    if format != wgpu::TextureFormat::Bgra8Unorm {
        return Err(format!("{format:?} is not a format Flutter's CVPixelBuffer shows"));
    }
    let surface = io_surface(width, height)?;
    let pixels = pixel_buffer(&surface)?;
    // SAFETY: the raw device is only used to make a texture, never to
    // change wgpu's own state.
    let hal_device = unsafe { device.as_hal::<Metal>() }.ok_or("not a Metal device")?;
    let raw = metal_texture(hal_device.raw_device(), &surface, width, height)?;
    drop(hal_device);
    // SAFETY: the texture is a single-mip, single-layer 2D texture of
    // exactly this size and format.
    let hal_texture = unsafe {
        wgpu::hal::metal::Device::texture_from_raw(
            raw,
            format,
            MTLTextureType::Type2D,
            1,
            1,
            wgpu::hal::CopyExtent {
                width,
                height,
                depth: 1,
            },
            None,
        )
    };
    let size = wgpu::Extent3d {
        width,
        height,
        depth_or_array_layers: 1,
    };
    // SAFETY: the texture matches the descriptor; Metal textures carry no
    // layout state for UNINITIALIZED to disagree with.
    let texture = unsafe {
        device.create_texture_from_hal::<Metal>(
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
    Ok((
        texture,
        SharedHandle {
            pixels,
            _surface: surface,
        },
    ))
}

/// Metal names no adapter by LUID; Flutter is matched by there being one
/// device (device.rs, `open_sole`).
pub fn adapter_luid(_adapter: &wgpu::Adapter) -> Option<u64> {
    None
}

/// The bytes every resource this process made on the adapter's device
/// holds — Metal's per-device count, which is per process as Windows'
/// `CurrentUsage` is. No budget: on Apple's unified memory the bound is
/// the RAM budget a pool is given (gpu-canonical-store 11-05 13:19 ②).
pub fn video_memory(adapter: &wgpu::Adapter) -> Option<super::VideoMemory> {
    // SAFETY: only reads the device's allocation count.
    let hal = unsafe { adapter.as_hal::<Metal>() }?;
    let used = hal.raw_device().currentAllocatedSize() as u64;
    Some(super::VideoMemory { used, budget: None })
}

#[cfg(test)]
mod tests {
    use objc2_core_video::{
        CVPixelBufferGetBaseAddress, CVPixelBufferGetBytesPerRow, CVPixelBufferGetPixelFormatType,
        CVPixelBufferLockBaseAddress, CVPixelBufferLockFlags, CVPixelBufferUnlockBaseAddress,
        kCVPixelFormatType_32BGRA, kCVReturnSuccess,
    };

    use crate::kernels::fill::Fill;
    use crate::testing::{assert_pinned, first_engine};

    // fill's own ledger row (kernels/fill/tests.rs): 70 x 45, so the
    // surface's aligned rows are wider than the picture.
    const WIDTH: u32 = 70;
    const HEIGHT: u32 = 45;

    // What Flutter reads is the CVPixelBuffer, not the wgpu texture: the
    // kernel's bytes must be there, row for row, and tagged with the one
    // RGB layout Flutter opens (FlutterDarwinExternalTextureMetal.mm:139).
    #[test]
    fn flutter_is_handed_the_bytes_the_kernel_wrote() {
        let engine = first_engine();
        let (texture, shared) =
            super::create(&engine.device, WIDTH, HEIGHT, wgpu::TextureFormat::Bgra8Unorm)
                .expect("shared surface");
        Fill::new(engine).run(engine, &texture, 7).expect("fill");
        let pixels = &*shared.pixels;
        assert_eq!(CVPixelBufferGetPixelFormatType(pixels), kCVPixelFormatType_32BGRA);
        // SAFETY: the buffer is live; the lock is released below.
        let locked = unsafe { CVPixelBufferLockBaseAddress(pixels, CVPixelBufferLockFlags::ReadOnly) };
        assert_eq!(locked, kCVReturnSuccess);
        let base = CVPixelBufferGetBaseAddress(pixels).cast::<u8>();
        let stride = CVPixelBufferGetBytesPerRow(pixels);
        let row = WIDTH as usize * super::BYTES_PER_TEXEL;
        let bytes: Vec<u8> = (0..HEIGHT as usize)
            // SAFETY: each row starts `stride` bytes after the last and
            // holds `row` bytes of picture while the base address is locked.
            .flat_map(|y| unsafe { std::slice::from_raw_parts(base.add(y * stride), row) }.to_vec())
            .collect();
        // SAFETY: balances the lock above.
        unsafe { CVPixelBufferUnlockBaseAddress(pixels, CVPixelBufferLockFlags::ReadOnly) };
        assert_pinned("fill/70x45-seed7-bgra", &bytes);
    }

    // Flutter shows 32BGRA alone among RGB layouts, so an RGBA surface is
    // refused rather than shown with red and blue swapped.
    #[test]
    fn an_rgba_surface_is_refused() {
        let engine = first_engine();
        let made = super::create(&engine.device, WIDTH, HEIGHT, wgpu::TextureFormat::Rgba8Unorm);
        assert!(made.is_err());
    }
}
