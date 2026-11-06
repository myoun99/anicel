//! The OS video codecs — the engine's `qa_video_encode.c` with its colour
//! and hardware laws (`qa_yuv601.h`, `qa_video_hardware_law.h`), in Rust
//! (native-to-rust, 저장). The decoder (`qa_video_decode.c`) and Apple's
//! side of both (`qa_video_apple.m`) join here. Until the connection round
//! the C is the answer key: the tests hold the exports to the engine's.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

pub mod colour;
// ⏳Apple's writer (`qa_video_apple.m`) is not here yet: the machine that
// ported this has no Apple target, so nothing could even compile it there —
// it joins with a build that can (native-to-rust-Q5). Until then the export
// is absent on Apple rather than answering for a writer it does not have.
#[cfg(not(target_vendor = "apple"))]
pub mod export;
pub mod hardware_law;
#[cfg(target_os = "android")]
mod ndk;
