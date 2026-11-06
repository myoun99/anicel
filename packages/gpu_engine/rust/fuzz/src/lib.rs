//! The Rust decoders, fed what no test thought of (native-memory-safety ③,
//! native-to-rust-Q2): one function here per fuzz target (fuzz_targets/),
//! each the door the app's bytes come in by. A target that panics, hangs or
//! runs out of memory on an input has found a bug in the crate it reads;
//! that input becomes a `cargo test` case there, held to the C.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

/// What a frame is decoded into when it states no size, or more: the crates
/// that read zstd themselves size their own buffers.
const ROOM: usize = 1 << 20;

/// Any bytes, as the app reads a cel (qa_cel_compressor.dart's
/// `readFrame`): the size the frame states, then the frame into that many
/// bytes — and, where the app gives up on a frame that states none, into
/// `ROOM`.
pub fn compress_decompress(frame: &[u8]) {
    let length = frame.len() as i64;
    // SAFETY: the slice holds the length passed.
    let stated = unsafe { compress::qa_zstd_decompressed_size(frame.as_ptr(), length) };
    let room = usize::try_from(stated).ok().filter(|size| (1..=ROOM).contains(size));
    let room = room.unwrap_or(ROOM);
    let mut out = vec![0u8; room];
    // SAFETY: both buffers hold the lengths passed, and are apart.
    unsafe { compress::qa_zstd_decompress(out.as_mut_ptr(), room as i64, frame.as_ptr(), length) };
}
