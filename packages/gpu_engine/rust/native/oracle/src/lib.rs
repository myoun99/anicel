//! What the native crates' tests share: a medium framed as the save frames
//! it ([`framed`]), and a file of a test's own in Temp ([`TempFile`]).
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

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU32, Ordering};

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

/// A file of a test's own in the temporary folder — named in Hangul, so
/// every test also walks the path through its one widening — gone when this
/// drops: at the test's end, or as it panics. Numbered too: the tests run
/// at once, and two of one name would write over each other's.
///
/// 🚨One writing of it for every crate whose tests lay a file in Temp (저장
/// 2026-11-16, card a-cargo-decode-test-leaves-its-movie-in-temp): audio's
/// tests kept this one for themselves, media's stream tests a second
/// (`Fixture`), and the rest laid a path and removed it at the test's end —
/// which a test that failed first never reached. The video decoder's movie
/// that its tests shared was removed by nothing: Temp kept one of every
/// run (169 on the Surface, 11-08 to 11-15).
pub struct TempFile(PathBuf);

impl TempFile {
    /// A path of [`TempFile`]'s with nothing at it yet: where the OS writes
    /// what a test then reads back (a movie the export writes).
    pub fn at(name: &str) -> TempFile {
        static MADE: AtomicU32 = AtomicU32::new(0);
        let number = MADE.fetch_add(1, Ordering::Relaxed);
        TempFile(std::env::temp_dir().join(format!("{}{number}-{name}", Self::mine())))
    }

    /// `bytes` in a file of [`TempFile::at`]'s.
    pub fn new(name: &str, bytes: &[u8]) -> TempFile {
        let file = TempFile::at(name);
        std::fs::write(&file.0, bytes).unwrap_or_else(|error| panic!("{}: {error}", file.0.display()));
        file
    }

    /// The files of this process's of `name` still in Temp — none, once
    /// each laid of that name has dropped: what a test reads to say it
    /// left nothing behind.
    pub fn left(name: &str) -> Vec<PathBuf> {
        let (mine, tail) = (Self::mine(), format!("-{name}"));
        let Ok(entries) = std::fs::read_dir(std::env::temp_dir()) else { return Vec::new() };
        entries
            .filter_map(|entry| entry.ok().map(|entry| entry.path()))
            .filter(|path| {
                path.file_name()
                    .and_then(|file| file.to_str())
                    .is_some_and(|file| file.starts_with(&mine) && file.ends_with(&tail))
            })
            .collect()
    }

    /// How the name of each of this process's begins.
    fn mine() -> String {
        format!("시험-{}-", std::process::id())
    }

    pub fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

#[cfg(test)]
mod tests {
    use super::TempFile;

    // 🚨A file a test lays goes with the test — at its end, and as it
    // panics: a test that failed first left its file for good while each
    // removed its own at its last line (card
    // a-cargo-decode-test-leaves-its-movie-in-temp).
    #[test]
    fn a_laid_file_goes_with_its_test_even_one_that_panics() {
        let laid = TempFile::new("laid.bin", b"bytes");
        assert_eq!(std::fs::read(laid.path()).expect("it is there"), b"bytes", "LIVENESS: laid");
        assert_eq!(TempFile::left("laid.bin"), [laid.path().to_path_buf()], "LIVENESS: seen while it is held");
        drop(laid);
        assert!(TempFile::left("laid.bin").is_empty(), "gone at the test's end");

        let failed = std::panic::catch_unwind(|| {
            let _laid = TempFile::new("failed.bin", b"bytes");
            panic!("a test that fails before its last line");
        });
        assert!(failed.is_err(), "LIVENESS: it panicked");
        assert!(TempFile::left("failed.bin").is_empty(), "gone as it panicked");
    }

    // Each is a file of its own, though two tests at once ask one name.
    #[test]
    fn two_of_one_name_are_two_files() {
        let (one, two) = (TempFile::new("twice.bin", b"one"), TempFile::new("twice.bin", b"two"));
        assert_ne!(one.path(), two.path());
        assert_eq!(std::fs::read(one.path()).expect("one"), b"one");
    }
}
