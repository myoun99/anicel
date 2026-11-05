//! What the GPU tests share.

use std::sync::{OnceLock, mpsc};

use crate::device::Engine;
use crate::{fingerprint, platform};

/// The engine on the platform's first adapter, opened once for the whole
/// test process, as the app opens one device: blend's tests opened one
/// per test, put eighteen D3D12 devices up at once, and the process died
/// on a cold compile (exit 2173, RTX 4080, 2026-11-05). Every kernel
/// folder's tests come here, so none has to make the same fix of its own
/// (관제, gpu-engine-skeleton 2026-11-05 14:49).
pub fn first_engine() -> &'static Engine {
    static ENGINE: OnceLock<Engine> = OnceLock::new();
    ENGINE.get_or_init(|| {
        let instance = platform::instance();
        let adapter = platform::adapters(&instance)
            .into_iter()
            .next()
            .expect("these tests need a GPU adapter");
        Engine::on(instance, adapter).expect("open the engine")
    })
}

/// `buffer`'s bytes once the GPU is done with all that was submitted. The
/// buffer is `COPY_SRC`. Blend's and the composite's tests each read one
/// back the same way, the export's tests a third, so the hand is here.
pub fn read_buffer(engine: &Engine, buffer: &wgpu::Buffer) -> Vec<u8> {
    let readback = engine.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("test readback"),
        size: buffer.size(),
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut encoder = engine
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
    encoder.copy_buffer_to_buffer(buffer, 0, &readback, 0, buffer.size());
    engine.queue.submit([encoder.finish()]);
    let (sender, receiver) = mpsc::channel();
    readback.map_async(wgpu::MapMode::Read, .., move |result| {
        let _ = sender.send(result);
    });
    engine.wait().expect("wait for the GPU");
    receiver.recv().expect("map_async answered").expect("map");
    readback.get_mapped_range(..).expect("mapped range").to_vec()
}

/// Fails unless `bytes` are the ones the ledger pinned as `id`.
pub fn assert_pinned(id: &str, bytes: &[u8]) {
    assert_eq!(fingerprint::hex(fingerprint::of(bytes)), fingerprint::pinned(id), "{id}");
}

#[test]
fn the_tests_share_one_device() {
    assert!(std::ptr::eq(first_engine(), first_engine()));
}
