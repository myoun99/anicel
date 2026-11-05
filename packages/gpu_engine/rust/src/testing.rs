//! What the GPU tests share.

use crate::device::Engine;
use crate::{fingerprint, platform};

/// The engine on the platform's first adapter.
pub fn first_engine() -> Engine {
    let instance = platform::instance();
    let adapter = platform::adapters(&instance)
        .into_iter()
        .next()
        .expect("these tests need a GPU adapter");
    Engine::on(instance, adapter).expect("open the engine")
}

/// Fails unless `bytes` are the ones the ledger pinned as `id`.
pub fn assert_pinned(id: &str, bytes: &[u8]) {
    assert_eq!(fingerprint::hex(fingerprint::of(bytes)), fingerprint::pinned(id), "{id}");
}
