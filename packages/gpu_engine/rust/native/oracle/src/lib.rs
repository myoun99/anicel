//! What the native crates' tests share: a medium framed as the save frames
//! it ([`framed`]).
//!
//! ↩️The C answer key, which the crate is named for (native-to-rust, 관제
//! 2026-11-06). While the app's native C moved to Rust a module at a time,
//! each module to a crate beside this one, a module's Rust was held to the
//! C, byte for byte, through what the engine exported: the engine the app
//! shipped, as CMake built it — not the C compiled once more here, under
//! other flags — loaded from `QA_ENGINE_PATH`, and a missing engine
//! failed, never skipped. Each module's rows were pinned in the app's
//! ledger (native/ledger) while the C still answered them, and the key
//! went with the C once its last module had moved (2026-11-13,
//! connection-round-checklist).

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

/// `medium` framed as the save frames it (`writeMediaBlob`): the block size,
/// the medium's length, the count of blocks and each one's length, then the
/// blocks — every `block_bytes` of it the level-9 zstd frame, the Rust
/// compressor's (native/compress, the C's byte for byte). ↩️The C engine's
/// `qa_zstd_compress` wrote them until the connection round deleted it
/// (connection-round-checklist H, 2026-11-08).
///
/// One writing of it for every crate whose tests read a framed span (저장
/// 2026-11-07): media's span and stream tests and audio's each laid it out
/// themselves, and the video decoder's would have been a fourth.
/// `gpu_engine`'s `kernels/shared/one_framing.rs` reads for another.
///
/// ⚠️This is NOT the format's writer — that is `writeMediaBlob` in Dart, and
/// the Dart suite reads what THAT writes through the native reader
/// (`framed_media_reads_only_the_blocks_it_needs_test.dart`). A test here
/// has no other way to make a fixture, so this one only has to agree with
/// the layout `media::span` reads.
pub fn framed(medium: &[u8], block_bytes: usize) -> Vec<u8> {
    let blocks: Vec<Vec<u8>> = medium
        .chunks(block_bytes)
        .map(|block| {
            let mut frame = vec![0u8; compress::qa_zstd_compress_bound(block.len() as i64) as usize];
            let wrote = compress::compress(&mut frame, block).expect("a block compresses");
            frame.truncate(wrote);
            frame
        })
        .collect();
    let mut blob = (block_bytes as u32).to_le_bytes().to_vec();
    blob.extend_from_slice(&(medium.len() as u64).to_le_bytes());
    blob.extend_from_slice(&(blocks.len() as u32).to_le_bytes());
    for block in &blocks {
        blob.extend_from_slice(&(block.len() as u32).to_le_bytes());
    }
    blob.extend(blocks.concat());
    blob
}
