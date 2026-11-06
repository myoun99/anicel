//! What the GPU tests share.

use std::sync::OnceLock;

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

/// `buffer`'s bytes once the GPU is done with all that was submitted — the
/// engine's own read-back (`Engine::read_buffer`), which the cel pixel pass
/// hands the app its runs by. The buffer is `COPY_SRC`.
pub fn read_buffer(engine: &Engine, buffer: &wgpu::Buffer) -> Vec<u8> {
    engine.read_buffer(buffer).expect("read back")
}

/// Fails unless `bytes` are the ones the ledger pinned as `id`.
pub fn assert_pinned(id: &str, bytes: &[u8]) {
    assert_eq!(fingerprint::hex(fingerprint::of(bytes)), fingerprint::pinned(id), "{id}");
}

#[test]
fn the_tests_share_one_device() {
    assert!(std::ptr::eq(first_engine(), first_engine()));
}
