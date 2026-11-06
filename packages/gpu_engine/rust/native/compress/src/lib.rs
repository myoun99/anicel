//! The cel compressor (R-COMP): zstd, memory to memory — the engine's
//! `qa_compress.c` over zstd 1.5.6, in Rust (native-to-rust, 저장). Until
//! the connection round the C is the answer key: the tests hold every
//! export to the engine's.
//!
//! zstd is ported, not swapped for a Rust zstd: the one there is decodes
//! the same bytes 3.8 times slower and compresses at one level only
//! (native-to-rust 2026-11-06 10:01, measured on the 617 frames of a real
//! project) — a cel is decompressed in frame time when it is first looked
//! at, so the decoder's speed is the scrubbing speed. This one takes 0.97
//! to 0.99 of the C's time on those 617 frames (2026-11-06) — by the C's
//! own wide copies (`frame::execute_fast`): copied byte-exact, a sequence
//! at a time, it took 1.65 times the C's.
//!
//! The decoder is here; the level-9 compressor joins it.
//!
//! The contract with Dart mirrors the rest of the engine: the caller owns
//! both buffers, sizes are exact, and a failure is a zero/negative return
//! rather than a partial write.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

mod bits;
mod encode;
mod frame;
pub mod frame_header;
mod fse;
mod huffman;
mod sequences;
mod xxhash;

/// A frame that cannot be decoded, for whatever reason: the C's error
/// codes all come out of the exports as the same 0.
#[derive(Debug, PartialEq, Eq)]
pub(crate) struct Corrupt;

/// `ZSTD_MAX_INPUT_SIZE`: the bound refuses sizes it could overflow on.
const MAX_INPUT: usize = if usize::BITS == 64 { 0xFF00_FF00_FF00_FF00u64 as usize } else { 0xFF00_FF00 };
/// `ZSTD_error_srcSize_wrong`, which `ZSTD_compressBound` answers as a
/// negative size.
const SRC_SIZE_WRONG: usize = 72;

/// `ZSTD_compressBound`.
fn compress_bound(size: usize) -> usize {
    const SMALL: usize = 128 << 10;
    if size >= MAX_INPUT {
        return 0usize.wrapping_sub(SRC_SIZE_WRONG);
    }
    size + (size >> 8) + if size < SMALL { (SMALL - size) >> 11 } else { 0 }
}

/// The most bytes `src_size` can compress to — the caller sizes its
/// destination with this before compressing.
#[unsafe(no_mangle)]
pub extern "C" fn qa_zstd_compress_bound(src_size: i64) -> i64 {
    if src_size <= 0 {
        return 0;
    }
    compress_bound(src_size as usize) as i64
}

/// The exact decompressed size a frame states, or -1 when the frame does
/// not carry one (zstd allows that; every frame this app writes does).
///
/// # Safety
/// `src` is null or holds `src_size` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_zstd_decompressed_size(src: *const u8, src_size: i64) -> i64 {
    if src.is_null() || src_size <= 0 {
        return -1;
    }
    // SAFETY: the caller's contract.
    let src = unsafe { std::slice::from_raw_parts(src, src_size as usize) };
    match frame_header::content_size(src) {
        frame_header::UNKNOWN | frame_header::ERROR => -1,
        size => size as i64,
    }
}

/// Every frame of `src` decompressed into `dst` (`ZSTD_decompress`): the
/// bytes written, or None when it does not decode — for the crates that
/// read zstd themselves.
pub fn decompress(dst: &mut [u8], src: &[u8]) -> Option<usize> {
    frame::decompress(dst, src).ok()
}

/// Decompresses into `dst`, answering the byte count, or 0 on failure.
///
/// # Safety
/// `dst` is null or holds `dst_capacity` bytes; `src` is null or holds
/// `src_size`; the two do not overlap.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_zstd_decompress(dst: *mut u8, dst_capacity: i64, src: *const u8, src_size: i64) -> i64 {
    if dst.is_null() || src.is_null() || dst_capacity <= 0 || src_size <= 0 {
        return 0;
    }
    // SAFETY: the caller's contract.
    let (dst, src) = unsafe {
        (std::slice::from_raw_parts_mut(dst, dst_capacity as usize), std::slice::from_raw_parts(src, src_size as usize))
    };
    frame::decompress(dst, src).map_or(0, |written| written as i64)
}

/// `src` compressed at level 9 into `dst` — the frame the engine's
/// `qa_zstd_compress(…, 9)` writes: the bytes written, or None when they do
/// not fit (`qa_zstd_compress_bound` is room enough) or `src` is empty.
pub fn compress(dst: &mut [u8], src: &[u8]) -> Option<usize> {
    encode::compress(dst, src)
}

#[cfg(test)]
mod tests;
