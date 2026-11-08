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
//
// The voice take's denoiser and the conform's resampler (H, 관제 2026-11-08
// 05:58): `qa_audio_denoise_f32` and `qa_audio_resample*` ·
// `qa_audio_resampler_*` are answered here, and the C's are gone.
pub use audio_denoise;
// ⚠️audio_mix carries the mix bus too, and naming the crate exports all of
// it: `qa_audio_mix` · `qa_audio_bus_to_*` · `qa_audio_*_sizeof` are then in
// this library AND in the C engine, which still answers them for the app
// until the mixer moves (관제 2026-11-08 06:15 ⓑ — ⛔the crate is not split
// to keep them out). Apart, they cannot meet: Windows, Linux and Android
// open the two libraries by their own handles, and on Apple's the C is
// linked into the app's executable while this library is a framework the
// code asset loads after it, so `DynamicLibrary.process()` finds the C's
// first (as the platforms' loaders are documented — not measured on a
// device; 타임라인/콘티 06:17). 🚨The mixer's own move binds it with
// `@Native`, as the resampler is bound — never through `process()`, whose
// answer, while both carry a name, is the order the images loaded in.
pub use audio_mix;
pub use compress;
pub use display;
pub use fx_plugin;
pub use image_encode;
// The four memory questions (H, 관제 2026-11-08 14:51):
// `qa_physical_memory_bytes` · `qa_process_footprint_bytes` ·
// `qa_available_memory_bytes` · `qa_app_memory_limit_bytes` are answered
// here, and the C's are gone.
pub use memory;
pub use pen;

// The Runner finds the pen ledger's class by name (ios/Runner/
// AppDelegate.swift), and an initializer of the pen crate registers it as
// the image it is in loads — this library, carried here: no code calls the
// initializer, and it must be linked all the same (보드/인프라 2026-11-08
// 03:49 ⓔ). The test binary links the crate as the library does.
#[cfg(all(test, target_vendor = "apple"))]
#[test]
fn the_pen_ledger_s_class_is_registered_as_the_library_loads() {
    assert!(objc2::runtime::AnyClass::get(c"QaPenLedger").is_some());
}

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

/// This thread's last error, as [`fail`] recorded it.
pub(crate) fn last_error() -> String {
    LAST_ERROR.with(|last| last.borrow().clone())
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
