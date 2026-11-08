//! The cel compressor (R-COMP): zstd, memory to memory — the C engine's
//! `qa_compress.c` over zstd 1.5.6, in Rust (native-to-rust, 저장). The C
//! was the answer key until the connection round deleted it
//! (connection-round-checklist H, 2026-11-08): the tests hold every export
//! to what it answered, kept in the ledger and in `fixtures/c_frames.bin`.
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
//! The decoder and the level-9 compressor ([`compress`], which says why
//! there is one level).
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

/// `src` compressed at level 9 into `dst` — the frame the C engine's
/// `qa_zstd_compress(…, 9)` wrote: the bytes written, or None when they do
/// not fit (`qa_zstd_compress_bound` is room enough) or `src` is empty.
///
/// THE LEVEL, AND THERE IS EXACTLY ONE (moved here from the app's
/// `anicelZstdLevel` when the level left the contract with Dart,
/// connection-round-checklist H, 관제 2026-11-08 06:21 — a level the caller
/// could pass was a wrong state the contract could hold).
///
/// 🪦19 WAS OFFERED AND REJECTED — 유저 확정 2026-08-30: 「9로통일이고
/// 19의 남은잔재는 깔끔하게 삭제하고싶어」. The numbers that settled it,
/// re-measured on cels from a real project, because the 「6ms → 30ms on a
/// 1MB cel」 that used to stand there did NOT reproduce:
///
/// | cel    | level 9 | level 19 |     | smaller |
/// |--------|---------|----------|-----|---------|
/// | 512KB  | 4.1ms   | 48ms     | 12× | 6–8%    |
/// | 768KB  | 4.1ms   | 50ms     | 12× | 6.9%    |
/// | 17.9MB | 256ms   | 5.4s     | 21× | 10.1%   |
///
/// So 19 bought 6–10% for 12–21× the compression time, and the multiplier
/// GREW with the cel — one big cel costs five seconds. Reading is
/// unaffected either way (1,522 MB/s against 1,496, which is noise), so
/// the whole cost sat on the save.
///
/// ⛔And it could never have been a simple flag on 「save」: a cel's level
/// is fixed when it COOLS (the app's `BrushFrameStore._coolLoop`), and a
/// save hands cold and file-backed bytes through untouched. Offering it
/// meant re-inflating and re-compressing every cel a save would otherwise
/// have copied — which is exactly the incremental-append fast path.
///
/// ⛔22 was never offered either: 0.4% smaller than 19 and 36× slower on
/// the same cel (measured 2026-08-29).
///
/// ⚠️This paragraph is the record, not a proposal. Anyone reaching for a
/// second level should read the table first.
pub fn compress(dst: &mut [u8], src: &[u8]) -> Option<usize> {
    encode::compress(dst, src)
}

/// Compresses `src` into `dst` at the one level ([`compress`]), answering
/// the byte count, or 0 when it does not fit or there is nothing to
/// compress. ↩️The C engine's took the level as a fifth argument, and the
/// app passed 9 alone.
///
/// # Safety
/// `dst` is null or holds `dst_capacity` bytes; `src` is null or holds
/// `src_size`; the two do not overlap.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_zstd_compress(dst: *mut u8, dst_capacity: i64, src: *const u8, src_size: i64) -> i64 {
    if dst.is_null() || src.is_null() || dst_capacity <= 0 || src_size <= 0 {
        return 0;
    }
    // SAFETY: the caller's contract.
    let (dst, src) = unsafe {
        (std::slice::from_raw_parts_mut(dst, dst_capacity as usize), std::slice::from_raw_parts(src, src_size as usize))
    };
    compress(dst, src).map_or(0, |written| written as i64)
}

#[cfg(test)]
mod tests;
