//! The one reader of a medium stored in a span of a file — as its own
//! bytes, or framed in zstd blocks — read a window at a time: the engine's
//! `qa_media_span.c`, in Rust (native-to-rust, 저장). See that file's header
//! for why there is one reader and for the framed layout, which Dart's
//! `writeMediaBlob` writes:
//!
//! ```text
//!   u32  blockBytes   uncompressed bytes per block
//!   u64  totalLength  uncompressed length of the whole medium
//!   u32  blockCount
//!   u32  ×blockCount  compressed length of each block, in order
//!   then each block, a zstd frame
//! ```
//!
//! all little-endian. Until the connection round the C is the answer key:
//! the tests hold every export to the engine's, the reads and what they
//! cost alike.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

use std::ffi::{CStr, c_char};
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::PathBuf;

/// Bytes before the block lengths: blockBytes, totalLength, blockCount.
const PREFIX: i64 = 16;

/// A block size no writer of this format has used, and no reader should
/// trust — the header is read from a file, and a number this size would
/// have one allocation take everything.
const MAX_BLOCK: i64 = 64 * 1024 * 1024;

/// What a framed span keeps: where each block lies, and the one block the
/// last window landed in — a document reads in windows far smaller than a
/// block, and decoding 512KB for each of them is the cost this exists to
/// not pay.
struct Framed {
    block_bytes: i64,
    /// Where each block starts in the stored bytes, and where the last ends.
    starts: Vec<i64>,
    stored_block: Vec<u8>,
    block: Vec<u8>,
    block_index: Option<i64>,
    block_size: i64,
}

/// A medium in `[base, base + stored_length)` of a file.
pub struct Span {
    file: File,
    base: i64,
    stored_length: i64,
    size: i64,
    framed: Option<Framed>,
    blocks_decoded: i64,
    stored_bytes_read: i64,
}

fn u32_at(bytes: &[u8], at: usize) -> u32 {
    u32::from_le_bytes(bytes[at..at + 4].try_into().expect("4 bytes"))
}

/// A path as the C opens one (`qa_open_path_read`): on Windows UTF-8 made
/// wide once — an ill-formed sequence replaced, a path of 1024 wide
/// characters or more refused rather than cut, since half a path names a
/// different file — and its bytes as they are everywhere else.
fn path_of(bytes: &[u8]) -> Option<PathBuf> {
    #[cfg(windows)]
    {
        let text = String::from_utf8_lossy(bytes);
        if text.encode_utf16().count() >= 1024 {
            return None;
        }
        Some(PathBuf::from(text.into_owned()))
    }
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        Some(PathBuf::from(std::ffi::OsStr::from_bytes(bytes)))
    }
}

impl Span {
    /// The medium stored in `[offset, offset + length)` of `path` — its own
    /// bytes, or a framed blob of them. None when the span is not inside
    /// the file, or a framed header does not hold together with the span
    /// it sits in.
    pub fn open(path: &[u8], offset: i64, length: i64, framed: bool) -> Option<Span> {
        if offset < 0 || length < 0 {
            return None;
        }
        let mut file = File::open(path_of(path)?).ok()?;
        // ⛔The span must be INSIDE the file. One that promises bytes the
        // file cannot supply is a truncated medium, which reads as a corrupt
        // one rather than as a span that was wrong.
        let file_size = i64::try_from(file.seek(SeekFrom::End(0)).ok()?).ok()?;
        if offset.checked_add(length).is_none_or(|end| end > file_size) {
            return None;
        }
        let mut span = Span {
            file,
            base: offset,
            stored_length: length,
            size: length,
            framed: None,
            blocks_decoded: 0,
            stored_bytes_read: 0,
        };
        if framed {
            span.framed = Some(span.open_framed()?);
        }
        Some(span)
    }

    /// Exactly `out.len()` stored bytes from `at` (from the span's base).
    fn read_stored(&mut self, at: i64, out: &mut [u8]) -> bool {
        let want = out.len() as i64;
        if at < 0 || at + want > self.stored_length {
            return false;
        }
        let read = self.file.seek(SeekFrom::Start((self.base + at) as u64)).is_ok() && self.file.read_exact(out).is_ok();
        if read {
            self.stored_bytes_read += want;
        }
        read
    }

    /// Reads the framed header and sizes the buffers, or None when it does
    /// not hold together with the span it sits in.
    fn open_framed(&mut self) -> Option<Framed> {
        let mut prefix = [0u8; PREFIX as usize];
        if !self.read_stored(0, &mut prefix) {
            return None;
        }
        let block_bytes = i64::from(u32_at(&prefix, 0));
        let total = u64::from(u32_at(&prefix, 4)) | u64::from(u32_at(&prefix, 8)) << 32;
        let block_count = i64::from(u32_at(&prefix, 12));
        if block_bytes <= 0 || block_bytes > MAX_BLOCK || total > i64::MAX as u64 {
            return None;
        }
        // ⛔The count must be the one the length implies: a header that says
        // otherwise was not written by this format's writer.
        if i128::from(block_count) != (i128::from(total) + i128::from(block_bytes) - 1) / i128::from(block_bytes) {
            return None;
        }
        let header_length = PREFIX + 4 * block_count;
        if header_length > self.stored_length {
            return None;
        }
        let mut lengths = vec![0u8; 4 * block_count as usize];
        if block_count > 0 && !self.read_stored(PREFIX, &mut lengths) {
            return None;
        }
        let mut starts = Vec::with_capacity(block_count as usize + 1);
        let mut at = header_length;
        let mut largest = 0;
        for block in 0..block_count as usize {
            let length = i64::from(u32_at(&lengths, 4 * block));
            starts.push(at);
            at += length;
            // A block that runs past the span is a torn entry, and reading
            // it would decode whatever follows it in the file.
            if length <= 0 || at > self.stored_length {
                return None;
            }
            largest = largest.max(length);
        }
        starts.push(at);
        self.size = total as i64;
        let (stored_block, block) =
            if block_count > 0 { (vec![0; largest as usize], vec![0; block_bytes as usize]) } else { (vec![], vec![]) };
        Some(Framed { block_bytes, starts, stored_block, block, block_index: None, block_size: 0 })
    }

    /// How many bytes the MEDIUM has — for a framed span, the decoded
    /// length.
    pub fn size(&self) -> i64 {
        self.size
    }

    /// Makes block `index` the decoded one, through the one-block cache.
    fn load_block(&mut self, index: i64) -> bool {
        let Some(mut framed) = self.framed.take() else {
            return false;
        };
        let loaded = self.decode_block(&mut framed, index);
        self.framed = Some(framed);
        loaded
    }

    fn decode_block(&mut self, framed: &mut Framed, index: i64) -> bool {
        if framed.block_index == Some(index) {
            return true;
        }
        let start = framed.starts[index as usize];
        let stored = (framed.starts[index as usize + 1] - start) as usize;
        let count = framed.starts.len() as i64 - 1;
        // The last block is short; every other one is exactly block_bytes.
        let expected = if index == count - 1 { self.size - framed.block_bytes * index } else { framed.block_bytes };
        framed.block_index = None;
        if !self.read_stored(start, &mut framed.stored_block[..stored]) {
            return false;
        }
        // ⛔A block that decodes to any other length is a broken file, not
        // a short one: the window it serves would be the wrong bytes.
        if compress::decompress(&mut framed.block, &framed.stored_block[..stored]) != Some(expected as usize) {
            return false;
        }
        self.blocks_decoded += 1;
        framed.block_index = Some(index);
        framed.block_size = expected;
        true
    }

    /// The medium's bytes from `position` into `out`: how many landed —
    /// short only at the end, 0 past it — or None when the file would not
    /// read or a block would not decode.
    pub fn read(&mut self, position: i64, out: &mut [u8]) -> Option<usize> {
        if position < 0 || out.is_empty() || position >= self.size {
            return Some(0);
        }
        let want = (out.len() as i64).min(self.size - position);
        let out = &mut out[..want as usize];
        if self.framed.is_none() {
            // 🚨base + position. Reading at `position` alone hands back
            // whatever precedes the medium in the file as if it were it.
            return self.read_stored(position, out).then_some(want as usize);
        }
        let mut wrote = 0;
        while wrote < want {
            let at = position + wrote;
            let block_bytes = self.framed.as_ref().expect("framed").block_bytes;
            let index = at / block_bytes;
            if !self.load_block(index) {
                return None;
            }
            let framed = self.framed.as_ref().expect("framed");
            let from = at - index * block_bytes;
            let take = (framed.block_size - from).min(want - wrote);
            out[wrote as usize..(wrote + take) as usize]
                .copy_from_slice(&framed.block[from as usize..(from + take) as usize]);
            wrote += take;
        }
        Some(wrote as usize)
    }

    /// What the span has cost so far: blocks decoded, and stored bytes read
    /// (the header included).
    pub fn stats(&self) -> (i64, i64) {
        (self.blocks_decoded, self.stored_bytes_read)
    }
}

/// `qa_media_span_open`.
///
/// # Safety
/// `utf8_path` is null or a NUL-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_media_span_open(utf8_path: *const c_char, offset: i64, length: i64, framed: i32) -> *mut Span {
    if utf8_path.is_null() {
        return std::ptr::null_mut();
    }
    // SAFETY: the caller's contract.
    let path = unsafe { CStr::from_ptr(utf8_path) }.to_bytes();
    Span::open(path, offset, length, framed != 0).map_or(std::ptr::null_mut(), |span| Box::into_raw(Box::new(span)))
}

/// `qa_media_span_size`.
///
/// # Safety
/// `span` is null or one [qa_media_span_open] answered and not closed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_media_span_size(span: *const Span) -> i64 {
    // SAFETY: the caller's contract.
    unsafe { span.as_ref() }.map_or(0, Span::size)
}

/// `qa_media_span_read`: -1 where [Span::read] answers None.
///
/// # Safety
/// `span` as for [qa_media_span_size]; `out` is null or holds `want` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_media_span_read(span: *mut Span, position: i64, out: *mut u8, want: i64) -> i64 {
    // SAFETY: the caller's contract.
    let Some(span) = (unsafe { span.as_mut() }) else {
        return 0;
    };
    if out.is_null() || want <= 0 {
        return 0;
    }
    // SAFETY: the caller's contract.
    let out = unsafe { std::slice::from_raw_parts_mut(out, want as usize) };
    span.read(position, out).map_or(-1, |wrote| wrote as i64)
}

/// `qa_media_span_close`.
///
/// # Safety
/// `span` as for [qa_media_span_size]; not used after.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_media_span_close(span: *mut Span) {
    if !span.is_null() {
        // SAFETY: the caller's contract — one of ours, closed once.
        drop(unsafe { Box::from_raw(span) });
    }
}

/// `qa_media_span_stats`.
///
/// # Safety
/// `span` as for [qa_media_span_size]; each out pointer null or writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_media_span_stats(span: *const Span, blocks_decoded: *mut i64, stored_bytes_read: *mut i64) {
    // SAFETY: the caller's contract.
    let (blocks, bytes) = unsafe { span.as_ref() }.map_or((0, 0), Span::stats);
    // SAFETY: the caller's contract.
    unsafe {
        if let Some(out) = blocks_decoded.as_mut() {
            *out = blocks;
        }
        if let Some(out) = stored_bytes_read.as_mut() {
            *out = bytes;
        }
    }
}

#[cfg(test)]
mod tests;
