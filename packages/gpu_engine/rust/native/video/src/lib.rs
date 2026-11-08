//! The OS video codecs, in Rust (native-to-rust, 저장): the movie writer
//! with its colour and hardware laws — Apple's writer among them,
//! AVAssetWriter through objc2 — and the decoder (`decode`), whose
//! AVAssetReader half 공통 added. ↩️They were the engine's
//! `qa_video_encode.c`, `qa_yuv601.h`, `qa_video_hardware_law.h`,
//! `qa_video_apple.m` and `qa_video_decode.c`, the answer key the tests held
//! the exports to, until the connection round deleted them
//! (connection-round-checklist H, 2026-11-08).

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

pub mod colour;
pub mod decode;
// Apple's writer is objc2 over AVFoundation, compiled on the main PC for the
// Apple targets (`cargo check`) and run on the Mac CI job (↩️held to the C
// there until the connection round deleted it) — the road 관제 set for
// every Apple piece of the engine (connection round, H).
pub mod export;
pub mod hardware_law;
