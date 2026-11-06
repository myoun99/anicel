//! A block's literal section (`zstd_compress_literals.c`): Huffman-coded
//! when that pays, else one byte repeated, else stored.

use super::huffman::{self, Table};
use super::{Repeat, TooSmall};
use crate::sequences::{BASIC, COMPRESSED, RLE};

/// `set_repeat`: the previous block's tree.
const REPEAT: u8 = 3;

/// The tree a block hands the next (`ZSTD_hufCTables_t`).
#[derive(Clone)]
pub(super) struct Tree {
    pub(super) table: Table,
    pub(super) repeat: Repeat,
}

/// `ZSTD_minLiteralsToCompress` at lazy2 and btlazy2: below it the bytes
/// are stored without trying.
const MIN_TO_CODE: usize = 8 << 3;

/// `ZSTD_noCompressLiterals` and `ZSTD_compressRleLiteralsBlock`'s
/// header: the kind, and the size in 5, 12 or 20 bits.
fn header(out: &mut [u8], kind: u8, size: usize) -> usize {
    let length = 1 + usize::from(size > 31) + usize::from(size > 4095);
    let fields = match length {
        1 => u32::from(kind) | (size as u32) << 3,
        2 => u32::from(kind) | 1 << 2 | (size as u32) << 4,
        _ => u32::from(kind) | 3 << 2 | (size as u32) << 4,
    };
    out[..length].copy_from_slice(&fields.to_le_bytes()[..length]);
    length
}

/// `ZSTD_noCompressLiterals`.
fn stored(out: &mut [u8], src: &[u8]) -> Result<usize, TooSmall> {
    let length = 1 + usize::from(src.len() > 31) + usize::from(src.len() > 4095);
    if src.len() + length > out.len() {
        return Err(TooSmall);
    }
    header(out, BASIC, src.len());
    out[length..length + src.len()].copy_from_slice(src);
    Ok(length + src.len())
}

/// `ZSTD_compressLiterals` at lazy2 and btlazy2: the section into `out`,
/// and the tree the next block may repeat into `next`.
pub(super) fn compress(
    out: &mut [u8],
    src: &[u8],
    previous: &Tree,
    next: &mut Tree,
    suspect_incompressible: bool,
) -> Result<usize, TooSmall> {
    let header_size = 3 + usize::from(src.len() >= 1 << 10) + usize::from(src.len() >= 16 << 10);
    let single = src.len() < 256;
    next.clone_from(previous);
    if src.len() < MIN_TO_CODE {
        return stored(out, src);
    }
    if out.len() < header_size + 1 {
        return Err(TooSmall);
    }
    let mut repeat = previous.repeat;
    let coded =
        huffman::compress(&mut out[header_size..], src, !single, &mut repeat, &mut next.table, suspect_incompressible);
    let kind = if repeat == Repeat::None { COMPRESSED } else { REPEAT };
    let min_gain = (src.len() >> 6) + 2;
    let coded = match coded {
        Some(size) if size != 0 && size < src.len() - min_gain => size,
        _ => {
            next.clone_from(previous);
            return stored(out, src);
        }
    };
    if coded == 1 {
        // Past the 64-byte floor a 1 is always the run (the C checks the
        // bytes only below 8).
        next.clone_from(previous);
        let length = header(out, RLE, src.len());
        out[length] = src[0];
        return Ok(length + 1);
    }
    if kind == COMPRESSED {
        next.repeat = Repeat::Check;
    }
    let (kind, size, coded32) = (u32::from(kind), src.len() as u32, coded as u32);
    match header_size {
        3 => {
            let fields = kind | u32::from(!single) << 2 | size << 4 | coded32 << 14;
            out[..3].copy_from_slice(&fields.to_le_bytes()[..3]);
        }
        4 => out[..4].copy_from_slice(&(kind | 2 << 2 | size << 4 | coded32 << 18).to_le_bytes()),
        _ => {
            out[..4].copy_from_slice(&(kind | 3 << 2 | size << 4 | coded32 << 22).to_le_bytes());
            out[4] = (coded >> 10) as u8;
        }
    }
    Ok(header_size + coded)
}
