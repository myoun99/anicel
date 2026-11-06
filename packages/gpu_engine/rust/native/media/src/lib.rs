//! What the engine's audio and video codecs share of the OS media stacks —
//! the engine's `qa_win_media_foundation.c`, in Rust (native-to-rust, 저장).
//! The span reader (`qa_media_span.c`) and each OS's serving of it join here
//! with the decoders that read through them.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

#[cfg(windows)]
pub mod media_foundation;
