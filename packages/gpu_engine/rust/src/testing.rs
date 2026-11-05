//! What the GPU tests share.

use crate::device::Engine;
use crate::{fingerprint, platform};

/// The engine on the platform's first adapter.
pub fn first_engine() -> Engine {
    let adapter = platform::adapters()
        .into_iter()
        .next()
        .expect("these tests need a GPU adapter");
    Engine::on(adapter).expect("open the engine")
}

/// A texture a compute pass stores to and a test reads back — not shared
/// with Flutter, so a kernel's tests need no screen.
pub fn storage_texture(
    engine: &Engine,
    width: u32,
    height: u32,
    format: wgpu::TextureFormat,
) -> wgpu::Texture {
    engine.device.create_texture(&wgpu::TextureDescriptor {
        label: Some("test target"),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format,
        usage: wgpu::TextureUsages::STORAGE_BINDING | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    })
}

/// Fails unless `bytes` are the ones the ledger pinned as `id`.
pub fn assert_pinned(id: &str, bytes: &[u8]) {
    assert_eq!(fingerprint::hex(fingerprint::of(bytes)), fingerprint::pinned(id), "{id}");
}
