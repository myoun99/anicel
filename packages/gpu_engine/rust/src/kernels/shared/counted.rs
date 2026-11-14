//! Bytes counted for as long as what holds them is alive. A kind of thing
//! the app keeps on the GPU counts its own in a static, and each one made
//! has a [`Counted`] beside its buffer: added as it is made, taken off as
//! it is dropped — no free has the taking to forget. What is read of the
//! static is what was made and not yet freed, which is how a test sees a
//! free that is gone: it answers every other test as one that frees (관제,
//! connection-round-checklist 2026-11-08 00:06: a leak mutant is not an
//! equivalent one).

use std::sync::atomic::{AtomicU64, Ordering};

/// `bytes` among a static's, for as long as this lives.
pub(crate) struct Counted {
    among: &'static AtomicU64,
    bytes: u64,
}

impl Counted {
    pub(crate) fn among(among: &'static AtomicU64, bytes: u64) -> Counted {
        among.fetch_add(bytes, Ordering::Relaxed);
        Counted { among, bytes }
    }
}

impl Drop for Counted {
    fn drop(&mut self) {
        self.among.fetch_sub(self.bytes, Ordering::Relaxed);
    }
}
