//! A platform with no bridge to Flutter's screen yet: the engine finds no
//! adapter there and makes no surface.

use std::ffi::c_void;

pub const BACKENDS: wgpu::Backends = wgpu::Backends::empty();

pub struct SharedHandle;

impl SharedHandle {
    pub fn raw(&self) -> *mut c_void {
        std::ptr::null_mut()
    }
}

pub fn create(
    _device: &wgpu::Device,
    _width: u32,
    _height: u32,
    _format: wgpu::TextureFormat,
) -> Result<(wgpu::Texture, SharedHandle), String> {
    Err("no bridge to Flutter's screen on this platform yet".into())
}

pub fn adapter_luid(_adapter: &wgpu::Adapter) -> Option<u64> {
    None
}

pub fn video_memory(_adapter: &wgpu::Adapter) -> Option<super::VideoMemory> {
    None
}
