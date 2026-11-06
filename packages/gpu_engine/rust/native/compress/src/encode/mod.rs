//! The level-9 compressor: `ZSTD_compress(dst, src, 9)` of zstd 1.5.6, the
//! frame the C writes byte for byte (native-to-rust, 저장 → 캔버스 베이스
//! 2026-11-06) — the engine's `qa_zstd_compress` its answer key until the
//! connection round.
//!
//! One frame stating its content size: blocks of up to 128 KiB, each parsed
//! lazily into sequences (lazy.rs) and entropy-coded (entropy.rs) — or
//! stored, or one byte repeated, where the C would.
//!
//! Level 9 is btlazy2 up to 16 KiB and lazy2 past it. The C runs lazy2 over
//! rows of tagged positions when its build has 128-bit SIMD (SSE2 or NEON)
//! and over hash chains when not; every build the app ships has it — x64,
//! arm64, and Android arm64 only (android/app/build.gradle.kts
//! `abiFilters`) — so the rows are the one lazy2 here.

mod entropy;
mod fse;
mod huffman;
mod lazy;
mod literals;
mod stream;

#[cfg(test)]
mod tests;

use entropy::{Entropy, Store};
use lazy::{Finder, START};
use crate::frame::{BLOCK_COMPRESSED, BLOCK_RAW, BLOCK_RLE, BLOCK_SIZE_MAX};
use crate::frame_header::{MAGIC, WINDOW_LOG_MIN};

/// `HUF_repeat` and `FSE_repeat`: whether the previous block's table may
/// code this one — to be checked first. The C's third mode, `valid`, comes
/// from a dictionary only.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Repeat {
    None,
    Check,
}

/// `ERROR(dstSize_tooSmall)`.
struct TooSmall;

/// Why a block's entropy stage failed: out of room — where a stored block
/// may still fit — or any other error.
enum Error {
    TooSmall,
    Failed,
}

impl From<TooSmall> for Error {
    fn from(_: TooSmall) -> Self {
        Error::TooSmall
    }
}

/// `ZSTD_FRAMEHEADERSIZE_MAX`: the room the C asks before a header.
const HEADER_MAX: usize = 18;
/// `ZSTD_blockHeaderSize`.
const BLOCK_HEADER: usize = 3;
/// `ZSTD_blockHeaderSize + MIN_CBLOCK_SIZE + 1`: the room a block needs.
const BLOCK_ROOM: usize = BLOCK_HEADER + 2 + 1;
/// Below this a block is stored without parsing (`ZSTD_buildSeqStore`).
const MIN_BLOCK: usize = 2 + BLOCK_HEADER + 1 + 1;
/// `rleMaxLength`: a block of one byte repeated is sent as the byte when it
/// would code to less than this.
const RLE_MAX: usize = 25;
/// `ZSTD_CURRENT_MAX`: an index past it has the C rebase its tables
/// (`ZSTD_overflowCorrectIfNeeded`). Inputs that reach it are refused here
/// instead of ported (캔버스 베이스 2026-11-06): it is 3.5 GiB of one cel,
/// which the app never writes, and the rebase would be code no test reaches.
const CURRENT_MAX: usize = (3 << 29) + (1 << if usize::BITS == 32 { 30 } else { 31 });

/// `ZSTD_compressionParameters` at level 9, adjusted to the input.
#[derive(Clone, Copy)]
struct Params {
    window_log: u32,
    chain_log: u32,
    hash_log: u32,
    search_log: u32,
    min_match: u32,
    /// btlazy2's tree; else lazy2's rows.
    tree: bool,
}

impl Params {
    /// `ZSTD_getCParams(9, size, 0)`: level 9's row of
    /// `ZSTD_defaultCParameters` for the size, then
    /// `ZSTD_adjustCParams_internal`.
    fn new(size: usize) -> Self {
        let (window_log, chain_log, hash_log, search_log, min_match, tree) = if size <= 16 << 10 {
            (14, 15, 14, 5, 4, true)
        } else if size <= 128 << 10 {
            (17, 16, 17, 5, 4, false)
        } else if size <= 256 << 10 {
            (18, 18, 19, 5, 4, false)
        } else {
            (22, 20, 21, 4, 5, false)
        };
        // A window no larger than the input (6 bits at the least).
        let source_log = if size < 64 { 6 } else { usize::BITS - (size - 1).leading_zeros() };
        let window_log = u32::min(window_log, source_log);
        let hash_log = u32::min(hash_log, window_log + 1);
        // A tree's pairs take two entries a position.
        let cycle_log = chain_log - u32::from(tree);
        let chain_log = if cycle_log > window_log { chain_log - (cycle_log - window_log) } else { chain_log };
        Params { window_log: window_log.max(WINDOW_LOG_MIN), chain_log, hash_log, search_log, min_match, tree }
    }
}

/// `ZSTD_writeFrameHeader`: the content size stated, no checksum, no
/// dictionary; the window in one segment when it covers the input.
fn write_header(out: &mut [u8], window_log: u32, size: usize) -> Option<usize> {
    if out.len() < HEADER_MAX {
        return None;
    }
    let size = size as u64;
    let single = 1u64 << window_log >= size;
    let code = usize::from(size >= 256) + usize::from(size >= 65536 + 256) + usize::from(size >= 0xFFFF_FFFF);
    out[..4].copy_from_slice(&MAGIC.to_le_bytes());
    out[4] = u8::from(single) << 5 | (code as u8) << 6;
    let mut at = 5;
    if !single {
        out[at] = ((window_log - WINDOW_LOG_MIN) << 3) as u8;
        at += 1;
    }
    // Code 0 (under 256 bytes) is always one segment: the window is 1 KiB
    // at the least.
    let (length, value) = match code {
        0 => (1, size),
        1 => (2, size - 256),
        2 => (4, size),
        _ => (8, size),
    };
    out[at..at + length].copy_from_slice(&value.to_le_bytes()[..length]);
    Some(at + length)
}

/// `ZSTD_blockHeader`'s 24 bits.
fn write_block_header(out: &mut [u8], last: bool, kind: usize, size: usize) {
    let fields = u32::from(last) | (kind as u32) << 1 | (size as u32) << 3;
    out[..BLOCK_HEADER].copy_from_slice(&fields.to_le_bytes()[..BLOCK_HEADER]);
}

/// What a coded block hands the next (`ZSTD_compressedBlockState_t`).
#[derive(Clone)]
struct Block {
    reps: [u32; 3],
    entropy: Entropy,
}

impl Block {
    fn new() -> Self {
        Block { reps: [1, 4, 8], entropy: Entropy::new() }
    }
}

/// One compression's state (`ZSTD_CCtx`, fresh for each call).
struct Compressor {
    finder: Finder,
    store: Store,
    previous: Block,
    next: Block,
}

impl Compressor {
    /// `ZSTD_compressBlock_internal`: the block at `range` into `out` —
    /// its coded size, or 0 to store it, or 1 when it is the byte at
    /// `out[0]` repeated. A block too small to parse is stored, never
    /// sent as its byte repeated (the C's `goto out`).
    fn block(&mut self, out: &mut [u8], src: &[u8], range: std::ops::Range<usize>, first: bool) -> Option<usize> {
        let block = &src[range.clone()];
        if block.len() < MIN_BLOCK {
            return Some(0);
        }
        self.finder.skip_long_match(range.start);
        self.store.clear();
        self.next.reps = self.previous.reps;
        let last_literals = self.finder.parse(src, range.clone(), &mut self.next.reps, &mut self.store);
        self.store.literals.extend_from_slice(&src[range.end - last_literals..range.end]);
        let mut size =
            entropy::compress(&mut self.store, &self.previous.entropy, &mut self.next.entropy, out, block.len()).ok()?;
        // Never the first block: the zstd 1.4.3 command line and before
        // refused a frame opening with one.
        if !first && size < RLE_MAX && block.iter().all(|&byte| byte == block[0]) {
            out[0] = block[0];
            size = 1;
        }
        if size > 1 {
            std::mem::swap(&mut self.previous, &mut self.next);
        }
        Some(size)
    }
}

/// `src` compressed at level 9 into `dst`: the bytes written, or None when
/// they do not fit (`qa_zstd_compress_bound` is room enough) — or `src` is
/// empty, or past what this port takes ([`CURRENT_MAX`]).
pub(crate) fn compress(dst: &mut [u8], src: &[u8]) -> Option<usize> {
    if src.is_empty() || src.len() + START as usize > CURRENT_MAX {
        return None;
    }
    let params = Params::new(src.len());
    let mut op = write_header(dst, params.window_log, src.len())?;
    let block_size = BLOCK_SIZE_MAX.min((1 << params.window_log).min(src.len()));
    let mut compressor = Compressor {
        finder: Finder::new(&params),
        store: Store::new(block_size),
        previous: Block::new(),
        next: Block::new(),
    };
    let mut start = 0;
    while start < src.len() {
        if dst.len() - op < BLOCK_ROOM {
            return None;
        }
        let end = src.len().min(start + block_size);
        let last = end == src.len();
        compressor.finder.enter_block(start);
        let out = &mut dst[op..];
        op += match compressor.block(&mut out[BLOCK_HEADER..], src, start..end, start == 0)? {
            0 => {
                let length = end - start;
                if BLOCK_HEADER + length > out.len() {
                    return None;
                }
                write_block_header(out, last, BLOCK_RAW, length);
                out[BLOCK_HEADER..BLOCK_HEADER + length].copy_from_slice(&src[start..end]);
                BLOCK_HEADER + length
            }
            1 => {
                write_block_header(out, last, BLOCK_RLE, end - start);
                BLOCK_HEADER + 1
            }
            size => {
                write_block_header(out, last, BLOCK_COMPRESSED, size);
                BLOCK_HEADER + size
            }
        };
        start = end;
    }
    Some(op)
}
