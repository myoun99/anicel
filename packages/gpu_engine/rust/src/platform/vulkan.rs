//! What the platforms whose engine is a Vulkan device share — Android and
//! Linux.

use std::path::PathBuf;

use wgpu::hal::api::Vulkan;

/// What the driver makes of `device`'s pipelines kept in `folder`, or
/// nowhere where it is `None` (vendor/wgpu-hal, auxil/compile_cache.rs —
/// D3D12's by the same code).
pub fn keep_shaders(device: &wgpu::Device, folder: Option<PathBuf>) {
    // SAFETY: names only where the hal device keeps what it made.
    if let Some(hal_device) = unsafe { device.as_hal::<Vulkan>() } {
        hal_device.keep_shaders_in(folder);
    }
}

/// How many of `device`'s pipelines the folder it keeps them in has
/// answered ([`keep_shaders`]).
pub fn pipelines_found(device: &wgpu::Device) -> Option<u64> {
    // SAFETY: only reads a count.
    unsafe { device.as_hal::<Vulkan>() }.map(|hal_device| hal_device.pipelines_found())
}

/// How many looks of `device`'s pipeline compiles found another's turn
/// held, and waited.
#[cfg(test)]
pub fn pipelines_waited(device: &wgpu::Device) -> u64 {
    // SAFETY: only reads a count.
    unsafe { device.as_hal::<Vulkan>() }.map_or(0, |hal_device| hal_device.pipelines_waited())
}
