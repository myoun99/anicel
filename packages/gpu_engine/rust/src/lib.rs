//! Anicel's GPU engine (gpu-engine-skeleton). Measurement only so far —
//! nothing in the app calls it yet.
//!
//! One place per job, so an area's session writes only its own folder
//! (the frame posted on gpu-engine-skeleton, 2026-11-05):
//! - `device` — the wgpu device every kernel runs on.
//! - `platform` — the texture Flutter shows, one file per platform.
//! - `kernels/<area>` — an area's shaders, its C ABI and its GPU tests.
//! - `fingerprint` — the CRC-32 pinned bytes are compared by.
//! - `testing` — what the GPU tests share.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

mod device;
mod fingerprint;
mod kernels;
mod platform;
#[cfg(test)]
mod testing;

// THE APP LOADS ONE RUST LIBRARY, AND IT CARRIES EACH native/ CRATE THE APP
// CALLS (connection-round-checklist A; the fx plugin host first, 관제
// 2026-11-08 03:39): a crate this one depends on but never names is not
// linked, and its extern "C" functions are not exported (Cargo.toml's
// workspace note, measured 2026-11-06) — named here, they are.
pub use display;
pub use fx_plugin;

use std::cell::RefCell;

thread_local! {
    static LAST_ERROR: RefCell<String> = const { RefCell::new(String::new()) };
}

/// Records `message` as this thread's last error, for the caller to read
/// through `gpu_engine_last_error` after a call reports failure.
pub(crate) fn fail<T>(message: impl Into<String>) -> Option<T> {
    LAST_ERROR.with(|last| *last.borrow_mut() = message.into());
    None
}

/// Copies `text` into a caller's buffer of `capacity` bytes; returns its
/// full length, which may exceed `capacity`.
pub(crate) fn copy_out(text: &str, buffer: *mut u8, capacity: usize) -> usize {
    let bytes = text.as_bytes();
    if !buffer.is_null() && capacity > 0 {
        let count = bytes.len().min(capacity);
        // SAFETY: the caller hands a buffer of `capacity` bytes.
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), buffer, count) };
    }
    bytes.len()
}

/// Copies this thread's last error (UTF-8) into `buffer`; returns its
/// full length.
///
/// # Safety
/// `buffer` holds `capacity` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_last_error(buffer: *mut u8, capacity: usize) -> usize {
    LAST_ERROR.with(|last| copy_out(&last.borrow(), buffer, capacity))
}
