//! Frames and their blocks (zstd_decompress.c, zstd_decompress_block.c):
//! one-shot decompression of every frame in a buffer, as `ZSTD_decompress`
//! does it.

use crate::Corrupt;
use crate::frame_header::{self, UNKNOWN};
use crate::huffman;
use crate::sequences::{self, Entropy, Sequence};
use crate::xxhash::xxh64;

pub(crate) const BLOCK_SIZE_MAX: usize = 128 << 10;
/// `WILDCOPY_OVERLENGTH`.
const OVERLENGTH: usize = 32;
/// `ZSTD_LITBUFFEREXTRASIZE`: the literals the C keeps outside the output.
const EXTRA: usize = 1 << 16;

fn le_at(src: &[u8], at: usize, bytes: usize) -> usize {
    frame_header::le(&src[at..at + bytes]) as usize
}

/// Where the C keeps a block's literals (`ZSTD_allocateLiteralsBuffer`) —
/// which decides how far the block's output may run.
#[derive(Clone, Copy)]
enum Place {
    /// After the block, in the output buffer: the block may write up to
    /// them.
    Output,
    /// In a buffer of their own, or still in the source.
    Apart,
    /// The first ones at the end of the block's room in the output, the
    /// last `EXTRA` apart.
    Split,
}

fn place(capacity: usize, block_max: usize, size: usize) -> Place {
    if capacity > block_max + OVERLENGTH + size + OVERLENGTH {
        Place::Output
    } else if size <= EXTRA {
        Place::Apart
    } else {
        Place::Split
    }
}

/// What a frame keeps between its blocks (the `ZSTD_DCtx` a frame begins
/// afresh).
struct Frame<'s> {
    block_max: usize,
    huffman: &'s mut huffman::Table,
    literals_repeatable: bool,
    entropy: Entropy,
    literals: &'s mut [u8],
}

/// A block's literals section, decoded.
struct Literals {
    consumed: usize,
    size: usize,
    place: Place,
    /// Where they lie in the block, when they are used from there.
    raw: Option<usize>,
}

const RAW: u8 = 0;
const COMPRESSED: u8 = 2;
const REPEAT: u8 = 3;

/// `ZSTD_decodeLiteralsBlock`.
fn literals(frame: &mut Frame, src: &[u8], capacity: usize) -> Result<Literals, Corrupt> {
    if src.len() < 2 {
        return Err(Corrupt);
    }
    let kind = src[0] & 3;
    let format = (src[0] >> 2) & 3;
    let block_max = frame.block_max;
    let room = |size: usize| {
        if size > block_max || block_max.min(capacity) < size {
            Err(Corrupt)
        } else {
            Ok(place(capacity, block_max, size))
        }
    };
    match kind {
        COMPRESSED | REPEAT => {
            if kind == REPEAT && !frame.literals_repeatable {
                return Err(Corrupt);
            }
            if src.len() < 5 {
                return Err(Corrupt);
            }
            let word = le_at(src, 0, 4);
            let (single, header, size, compressed) = match format {
                0 | 1 => (format == 0, 3, (word >> 4) & 0x3FF, (word >> 14) & 0x3FF),
                2 => (false, 4, (word >> 4) & 0x3FFF, word >> 18),
                _ => (false, 5, (word >> 4) & 0x3FFFF, (word >> 22) + (usize::from(src[4]) << 10)),
            };
            if size > block_max || (!single && size < 6) || compressed + header > src.len() {
                return Err(Corrupt);
            }
            let place = room(size)?;
            let out = &mut frame.literals[..size];
            let stream = &src[header..header + compressed];
            match (kind, single) {
                (REPEAT, true) => huffman::single_with_previous_tree(out, stream, frame.huffman),
                (REPEAT, false) => huffman::four_with_previous_tree(out, stream, frame.huffman),
                (_, true) => huffman::single_with_new_tree(out, stream, frame.huffman),
                (_, false) => huffman::four_with_new_tree(out, stream, frame.huffman),
            }?;
            frame.literals_repeatable = true;
            Ok(Literals { consumed: header + compressed, size, place, raw: None })
        }
        RAW => {
            let (header, size) = match format {
                1 => (2, le_at(src, 0, 2) >> 4),
                3 if src.len() < 3 => return Err(Corrupt),
                3 => (3, le_at(src, 0, 3) >> 4),
                _ => (1, usize::from(src[0] >> 3)),
            };
            let place = room(size)?;
            if header + size + OVERLENGTH > src.len() {
                if header + size > src.len() {
                    return Err(Corrupt);
                }
                frame.literals[..size].copy_from_slice(&src[header..header + size]);
                return Ok(Literals { consumed: header + size, size, place, raw: None });
            }
            Ok(Literals { consumed: header + size, size, place: Place::Apart, raw: Some(header) })
        }
        // RLE: one byte, repeated.
        _ => {
            let (header, size) = match format {
                1 if src.len() < 3 => return Err(Corrupt),
                1 => (2, le_at(src, 0, 2) >> 4),
                3 if src.len() < 4 => return Err(Corrupt),
                3 => (3, le_at(src, 0, 3) >> 4),
                _ => (1, usize::from(src[0] >> 3)),
            };
            let place = room(size)?;
            frame.literals[..size].fill(src[header]);
            Ok(Literals { consumed: header + 1, size, place, raw: None })
        }
    }
}

/// The bytes `offset` back, `length` of them, copied forward one at a time
/// in effect — a match may overlap what it writes. `offset` is not 0.
#[inline(always)]
fn copy_match(out: &mut [u8], at: usize, offset: usize, length: usize) {
    let from = at - offset;
    if offset >= length {
        out.copy_within(from..from + length, at);
        return;
    }
    // The copied stretch repeats every `offset` bytes, and grows as it is
    // written: copy as much of it as is already there.
    let mut done = 0;
    while done < length {
        let count = (at + done - from).min(length - done);
        out.copy_within(from..from + count, at + done);
        done += count;
    }
}

/// `ZSTD_overlapCopy8`'s tables: how far a match fewer than 8 bytes back
/// moves for its second 4 bytes, and back for its next 8.
const SPREAD_ON: [usize; 8] = [0, 1, 2, 1, 4, 4, 4, 4];
const SPREAD_BACK: [usize; 8] = [8, 8, 8, 7, 8, 9, 10, 11];

#[inline(always)]
fn copy16(out: &mut [u8], to: usize, from: usize) {
    out.copy_within(from..from + 16, to);
}

/// The C's fast `ZSTD_execSequence`: a short stretch moves as one 16 bytes
/// and a match close behind in 8-byte steps, writing up to 32 bytes past
/// the sequence, which the next one writes over. The caller has checked
/// that the room for that is there, behind the literals too.
#[inline(always)]
fn execute_fast(out: &mut [u8], op: usize, literals: &[u8], used: usize, sequence: &Sequence) {
    let count = sequence.literals;
    if count <= 16 {
        out[op..op + 16].copy_from_slice(&literals[used..used + 16]);
    } else {
        out[op..op + count].copy_from_slice(&literals[used..used + count]);
    }
    let (mut to, length, offset) = (op + count, sequence.matched, sequence.offset);
    let mut from = to - offset;
    if offset >= 16 {
        if length <= 16 {
            copy16(out, to, from);
        } else if offset >= length {
            out.copy_within(from..from + length, to);
        } else {
            for step in (0..length).step_by(16) {
                copy16(out, to + step, from + step);
            }
        }
        return;
    }
    // The first 8 bytes spread the match to 8 or more behind.
    if offset < 8 {
        for k in 0..4 {
            out[to + k] = out[from + k];
        }
        from += SPREAD_ON[offset];
        out.copy_within(from..from + 4, to + 4);
        from = from + 8 - SPREAD_BACK[offset];
    } else {
        out.copy_within(from..from + 8, to);
        from += 8;
    }
    let end = to + length;
    to += 8;
    while to < end {
        out.copy_within(from..from + 8, to);
        to += 8;
        from += 8;
    }
}

/// `ZSTD_execSequence[End]`: the block may write up to `end`; `literals`
/// holds the block's `limit` of them and may run on past.
#[inline(always)]
fn execute(out: &mut [u8], op: &mut usize, end: usize, literals: &[u8], limit: usize, used: &mut usize, sequence: &Sequence) -> Result<(), Corrupt> {
    let length = sequence.literals + sequence.matched;
    if sequence.literals <= limit - *used
        && length + OVERLENGTH <= end - *op
        && *used + sequence.literals + OVERLENGTH <= literals.len()
        && sequence.offset <= *op + sequence.literals
    {
        execute_fast(out, *op, literals, *used, sequence);
        *op += length;
        *used += sequence.literals;
        return Ok(());
    }
    if length > end - *op || sequence.literals > limit - *used {
        return Err(Corrupt);
    }
    out[*op..*op + sequence.literals].copy_from_slice(&literals[*used..*used + sequence.literals]);
    *op += sequence.literals;
    *used += sequence.literals;
    // The frame is the whole history: nothing lies before its first byte.
    if sequence.offset > *op {
        return Err(Corrupt);
    }
    copy_match(out, *op, sequence.offset, sequence.matched);
    *op += sequence.matched;
    Ok(())
}

/// `ZSTD_decompressBlock_internal`: the bytes the block decoded to, at
/// `at` in the frame's output.
fn block(frame: &mut Frame, out: &mut [u8], at: usize, src: &[u8]) -> Result<usize, Corrupt> {
    if src.len() > frame.block_max {
        return Err(Corrupt);
    }
    let capacity = out.len() - at;
    let section = literals(frame, src, capacity)?;
    let rest = &src[section.consumed..];
    let (count, header) = sequences::read_header(&mut frame.entropy, rest)?;
    if capacity == 0 && count > 0 {
        return Err(Corrupt);
    }
    // With what lies after them, for the fast copies' overrun: the block's
    // own bytes after literals used in place (at least OVERLENGTH, by
    // `literals`), the buffer's slack after decoded ones.
    let literals: &[u8] = match section.raw {
        Some(start) => &src[start..],
        None => &frame.literals[..],
    };
    let limit = section.size;
    let end = match section.place {
        Place::Output => at + frame.block_max + OVERLENGTH,
        Place::Apart | Place::Split => out.len(),
    };
    // Split literals lie, but for the last EXTRA, from `region` of the
    // block's room in the output on: while a sequence takes its literals
    // from that part, its output must stay a wildcopy short of the next
    // one. A block within its size limit always does, by the EXTRA kept
    // apart; one past it can run into them, where the C reads back
    // literals it has overwritten — such a block is refused here instead.
    let mut in_output = match section.place {
        Place::Split => {
            let room = frame.block_max.min(capacity);
            Some((section.size - EXTRA, room - section.size + EXTRA - OVERLENGTH))
        }
        Place::Output | Place::Apart => None,
    };
    let mut op = at;
    let mut used = 0;
    if count > 0 {
        frame.entropy.repeatable = true;
        let mut decoder = sequences::Decoder::new(&rest[header..], &frame.entropy)?;
        for left in (1..=count).rev() {
            let sequence = decoder.next(left == 1);
            if let Some((part, region)) = in_output {
                let taken = used + sequence.literals;
                if taken > part {
                    in_output = None;
                } else if op - at + sequence.literals + sequence.matched + OVERLENGTH > region + taken {
                    return Err(Corrupt);
                }
            }
            execute(out, &mut op, end, literals, limit, &mut used, &sequence)?;
        }
        if !decoder.finished() {
            return Err(Corrupt);
        }
        let repeats = decoder.repeats.map(|offset| offset as u32);
        frame.entropy.repeats = repeats;
    }
    let last = limit - used;
    if last > end - op {
        return Err(Corrupt);
    }
    out[op..op + last].copy_from_slice(&literals[used..limit]);
    Ok(op + last - at)
}

pub(crate) const BLOCK_RAW: usize = 0;
pub(crate) const BLOCK_RLE: usize = 1;
pub(crate) const BLOCK_COMPRESSED: usize = 2;

/// `ZSTD_decompressFrame`: what the frame at the start of `src` decoded to
/// in `out`, and the bytes it took.
fn frame(out: &mut [u8], src: &[u8], huffman: &mut huffman::Table, literals: &mut [u8]) -> Result<(usize, usize), Corrupt> {
    // The smallest frame header, and a block header.
    if src.len() < 6 + 3 {
        return Err(Corrupt);
    }
    let header_size = frame_header::size(src[4]);
    if src.len() < header_size + 3 {
        return Err(Corrupt);
    }
    let header = frame_header::read(&src[..header_size]).ok_or(Corrupt)?;
    // No dictionary is ever loaded.
    if header.dict_id != 0 {
        return Err(Corrupt);
    }
    let block_max = header.window_size.min(BLOCK_SIZE_MAX as u64) as usize;
    let mut frame = Frame { block_max, huffman, literals_repeatable: false, entropy: Entropy::new(), literals };
    let mut ip = header_size;
    let mut op = 0;
    loop {
        if src.len() - ip < 3 {
            return Err(Corrupt);
        }
        let word = le_at(src, ip, 3);
        let kind = (word >> 1) & 3;
        let size = word >> 3;
        let taken = match kind {
            BLOCK_RLE => 1,
            BLOCK_RAW | BLOCK_COMPRESSED => size,
            _ => return Err(Corrupt),
        };
        ip += 3;
        if taken > src.len() - ip {
            return Err(Corrupt);
        }
        let body = &src[ip..ip + taken];
        let written = match kind {
            BLOCK_COMPRESSED => block(&mut frame, out, op, body)?,
            _ => {
                let written = if kind == BLOCK_RAW { taken } else { size };
                if written > out.len() - op {
                    return Err(Corrupt);
                }
                if kind == BLOCK_RAW {
                    out[op..op + written].copy_from_slice(body);
                } else {
                    out[op..op + written].fill(body[0]);
                }
                written
            }
        };
        op += written;
        ip += taken;
        if word & 1 == 1 {
            break;
        }
    }
    if header.content_size != UNKNOWN && op as u64 != header.content_size {
        return Err(Corrupt);
    }
    if header.checksum {
        if src.len() - ip < 4 || le_at(src, ip, 4) as u32 != xxh64(&out[..op], 0) as u32 {
            return Err(Corrupt);
        }
        ip += 4;
    }
    Ok((op, ip))
}

/// `ZSTD_decompress`: every frame in `src`, one after another into `dst`,
/// skippable frames skipped — the bytes written.
pub(crate) fn decompress(dst: &mut [u8], src: &[u8]) -> Result<usize, Corrupt> {
    let mut huffman = huffman::Table::new();
    let mut literals = vec![0u8; BLOCK_SIZE_MAX + OVERLENGTH];
    let mut ip = 0;
    let mut op = 0;
    while src.len() - ip >= frame_header::PREFIX {
        let rest = &src[ip..];
        if frame_header::is_skippable(le_at(rest, 0, 4) as u32) {
            // `readSkippableFrameSize`.
            if rest.len() < frame_header::SKIPPABLE_HEADER {
                return Err(Corrupt);
            }
            let size = le_at(rest, 4, 4) as u32;
            if size.wrapping_add(frame_header::SKIPPABLE_HEADER as u32) < size {
                return Err(Corrupt);
            }
            let skipped = frame_header::SKIPPABLE_HEADER + size as usize;
            if skipped > rest.len() {
                return Err(Corrupt);
            }
            ip += skipped;
            continue;
        }
        let (written, taken) = frame(&mut dst[op..], rest, &mut huffman, &mut literals)?;
        op += written;
        ip += taken;
    }
    // Every byte must belong to a frame.
    if ip != src.len() {
        return Err(Corrupt);
    }
    Ok(op)
}
