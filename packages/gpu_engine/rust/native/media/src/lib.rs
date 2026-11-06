//! What the engine's audio and video codecs share of the OS media stacks —
//! the engine's `qa_win_media_foundation.c`, in Rust (native-to-rust, 저장).
//! The span reader (`qa_media_span.c`) and each OS's serving of it join here
//! with the decoders that read through them.

#[cfg(windows)]
pub mod media_foundation;
