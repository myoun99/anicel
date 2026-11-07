//! The OS video codecs — the engine's `qa_video_encode.c` with its colour
//! and hardware laws (`qa_yuv601.h`, `qa_video_hardware_law.h`), in Rust
//! (native-to-rust, 저장) — Apple's writer included (`qa_video_apple.m`'s
//! AVAssetWriter half, through objc2) — and the decoder, `qa_video_decode.c`
//! (`decode`), whose AVAssetReader half 공통 adds. Until the
//! connection round the C is the answer key: the tests hold the exports to
//! the engine's.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

pub mod colour;
pub mod decode;
// Apple's writer is objc2 over AVFoundation, compiled on the main PC for the
// Apple targets (`cargo check`) and held to the C on the Mac CI job — the
// road 관제 set for every Apple piece of the engine (connection round, H).
pub mod export;
pub mod hardware_law;
