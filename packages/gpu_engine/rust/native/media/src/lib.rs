//! What the engine's audio and video codecs share (native-to-rust, 저장):
//! starting Media Foundation, widening a path, reading a span, and reading
//! the head of an ISO or QuickTime box. Each OS's serving of a span joins
//! here with the decoders that read through it. ↩️The C engine's
//! `qa_win_media_foundation.c`, `qa_platform_path.h` and `qa_media_span.c`
//! until the connection round deleted them (connection-round-checklist H,
//! 2026-11-08).

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

pub mod iso_box;
#[cfg(windows)]
pub mod media_foundation;
#[cfg(target_os = "android")]
pub mod ndk;
pub mod path;
#[cfg(target_os = "android")]
pub mod served_span;
pub mod span;
