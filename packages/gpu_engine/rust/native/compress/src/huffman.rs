//! Huffman-coded literals (huf_decompress.c): the tree description, the
//! single-symbol (X1) and double-symbol (X2) decoding tables, and the
//! decoders — one stream or four, the four through the C's fast loop when
//! it takes them and its plain loop when it does not.
//!
//! The fast loop is not an optimisation the Rust may leave out: it does not
//! hold a stream to ending exactly where its bits do, so a corrupt stream
//! the plain loop refuses can come out of the fast one — and which loop
//! decodes a block is the C's choice the Rust makes the same way.

use crate::Corrupt;
use crate::bits::{Bits, Status, highbit};
use crate::fse;

pub(crate) const TABLE_LOG_MAX: u32 = 12;
/// `HUF_DECODER_FAST_TABLELOG`: tables are widened to it, and the fast
/// loop takes only tables of exactly it.
const FAST_TABLE_LOG: u32 = 11;
pub(crate) const SYMBOLS: usize = 256;

#[derive(Clone, Copy, Default)]
struct X1 {
    nb_bits: u8,
    byte: u8,
}

/// One or two symbols: `length` of `sequence`'s bytes, little end first.
#[derive(Clone, Copy, Default)]
struct X2 {
    sequence: u16,
    nb_bits: u8,
    length: u8,
}

/// The decoding table a frame keeps between its blocks (`HUF_DTable`): a
/// block that repeats the previous tree decodes with whichever kind the
/// previous one built.
pub(crate) struct Table {
    double: bool,
    log: u32,
    x1: Box<[X1; 1 << TABLE_LOG_MAX]>,
    x2: Box<[X2; 1 << TABLE_LOG_MAX]>,
}

impl Table {
    pub(crate) fn new() -> Self {
        Table {
            double: false,
            log: 0,
            x1: Box::new([X1::default(); 1 << TABLE_LOG_MAX]),
            x2: Box::new([X2::default(); 1 << TABLE_LOG_MAX]),
        }
    }
}

/// A tree's weights (`HUF_readStats`): the bytes the description took, how
/// many symbols it has, and its table log. `ranks[w]` counts weight w.
fn read_weights(weights: &mut [u8; SYMBOLS], ranks: &mut [u32; 13], src: &[u8]) -> Result<(usize, usize, u32), Corrupt> {
    let first = *src.first().ok_or(Corrupt)? as usize;
    let (size, count) = if first >= 128 {
        // Raw 4-bit weights, two to a byte.
        let count = first - 127;
        let size = count.div_ceil(2);
        if size + 1 > src.len() {
            return Err(Corrupt);
        }
        for n in (0..count).step_by(2) {
            weights[n] = src[1 + n / 2] >> 4;
            weights[n + 1] = src[1 + n / 2] & 15;
        }
        (size, count)
    } else {
        if first + 1 > src.len() {
            return Err(Corrupt);
        }
        (first, fse::decode_weights(&mut weights[..SYMBOLS - 1], &src[1..1 + first])?)
    };
    ranks.fill(0);
    let mut total = 0u32;
    for &weight in &weights[..count] {
        if u32::from(weight) > TABLE_LOG_MAX {
            return Err(Corrupt);
        }
        ranks[weight as usize] += 1;
        total += (1 << weight) >> 1;
    }
    if total == 0 {
        return Err(Corrupt);
    }
    let log = highbit(total) + 1;
    if log > TABLE_LOG_MAX {
        return Err(Corrupt);
    }
    // The last symbol's weight is implied: what makes the total a power of 2.
    let rest = (1 << log) - total;
    if 1 << highbit(rest) != rest {
        return Err(Corrupt);
    }
    let last = highbit(rest) + 1;
    weights[count] = last as u8;
    ranks[last as usize] += 1;
    if ranks[1] < 2 || ranks[1] & 1 != 0 {
        return Err(Corrupt);
    }
    Ok((size + 1, count + 1, log))
}

/// `HUF_readDTableX1_wksp`: the bytes the description took.
fn read_x1(table: &mut Table, src: &[u8]) -> Result<usize, Corrupt> {
    let mut weights = [0u8; SYMBOLS];
    let mut ranks = [0u32; 13];
    let (size, symbols, mut log) = read_weights(&mut weights, &mut ranks, src)?;
    // Narrow trees are widened to the fast loop's log: every weight moves
    // up by the difference.
    if log < FAST_TABLE_LOG {
        let scale = FAST_TABLE_LOG - log;
        for weight in &mut weights[..symbols] {
            if *weight != 0 {
                *weight += scale as u8;
            }
        }
        for w in (scale as usize + 1..=FAST_TABLE_LOG as usize).rev() {
            ranks[w] = ranks[w - scale as usize];
        }
        ranks[1..=scale as usize].fill(0);
        log = FAST_TABLE_LOG;
    }
    table.double = false;
    table.log = log;
    // Symbols in order of weight, then each weight's cells in that order.
    let mut starts = [0u32; 13];
    let mut next = 0;
    for w in 0..=log as usize {
        starts[w] = next;
        next += ranks[w];
    }
    let mut sorted = [0u8; SYMBOLS];
    for (symbol, &weight) in weights[..symbols].iter().enumerate() {
        sorted[starts[weight as usize] as usize] = symbol as u8;
        starts[weight as usize] += 1;
    }
    let mut symbol = ranks[0] as usize;
    let mut cell = 0;
    for w in 1..=log {
        let length = (1usize << w) >> 1;
        let entry_bits = (log + 1 - w) as u8;
        for &byte in &sorted[symbol..symbol + ranks[w as usize] as usize] {
            table.x1[cell..cell + length].fill(X1 { nb_bits: entry_bits, byte });
            cell += length;
        }
        symbol += ranks[w as usize] as usize;
    }
    Ok(size)
}

fn x2_entry(symbol: u32, nb_bits: u32, base: u32, level: u8) -> X2 {
    let sequence = if level == 1 { symbol } else { base + (symbol << 8) };
    X2 { sequence: sequence as u16, nb_bits: nb_bits as u8, length: level }
}

/// Every symbol of `symbols` at `nb_bits`, each over the cells a code that
/// long covers (`HUF_fillDTableX2ForWeight`).
fn fill_weight(cells: &mut [X2], symbols: &[u8], nb_bits: u32, log: u32, base: u32, level: u8) {
    let length = 1usize << ((log - nb_bits) & 0x1F);
    for (at, &symbol) in symbols.iter().enumerate() {
        cells[at * length..(at + 1) * length].fill(x2_entry(u32::from(symbol), nb_bits, base, level));
    }
}

struct X2Plan<'a> {
    log: u32,
    sorted: &'a [u8; SYMBOLS],
    /// `starts[w]`: where weight w's symbols begin in `sorted`.
    starts: &'a [u32; 15],
    ranks: &'a [[u32; 13]; 12],
    max_weight1: usize,
    baseline: u32,
}

/// The second symbols after a first one of `consumed` bits
/// (`HUF_fillDTableX2Level2`): cells too short for any second code keep
/// the first symbol alone.
fn fill_level2(cells: &mut [X2], plan: &X2Plan, consumed: u32, min_weight: usize, first: u32) {
    let ranks = &plan.ranks[consumed as usize];
    if min_weight > 1 {
        cells[..ranks[min_weight] as usize].fill(x2_entry(first, consumed, 0, 1));
    }
    for w in min_weight..plan.max_weight1 {
        let symbols = &plan.sorted[plan.starts[w] as usize..plan.starts[w + 1] as usize];
        let nb_bits = plan.baseline - w as u32 + consumed;
        fill_weight(&mut cells[ranks[w] as usize..], symbols, nb_bits, plan.log, first, 2);
    }
}

/// `HUF_readDTableX2_wksp`: the bytes the description took.
fn read_x2(table: &mut Table, src: &[u8]) -> Result<usize, Corrupt> {
    let mut weights = [0u8; SYMBOLS];
    let mut counts = [0u32; 13];
    let (size, symbols, tree_log) = read_weights(&mut weights, &mut counts, src)?;
    let log = if tree_log <= FAST_TABLE_LOG { FAST_TABLE_LOG } else { TABLE_LOG_MAX };
    let mut max_weight = tree_log as usize;
    while counts[max_weight] == 0 {
        max_weight -= 1;
    }
    // starts[w + 1] runs ahead while sorting; starts[w] is then weight w's
    // first symbol, and weight-0 symbols sort to the end.
    let mut starts = [0u32; 15];
    let mut next = 0;
    for w in 1..=max_weight {
        starts[w + 1] = next;
        next += counts[w];
    }
    starts[1] = next;
    starts[max_weight + 2] = next;
    let mut sorted = [0u8; SYMBOLS];
    for (symbol, &weight) in weights[..symbols].iter().enumerate() {
        let at = &mut starts[weight as usize + 1];
        sorted[*at as usize] = symbol as u8;
        *at += 1;
    }
    starts[1] = 0;
    // Where each weight's cells begin, at every depth a first symbol can
    // leave for a second.
    let mut ranks = [[0u32; 13]; 12];
    let rescale = log as i32 - tree_log as i32 - 1;
    let mut next = 0;
    for w in 1..=max_weight {
        ranks[0][w] = next;
        next += counts[w] << (w as i32 + rescale);
    }
    let min_bits = tree_log + 1 - max_weight as u32;
    for consumed in min_bits..log - min_bits + 1 {
        for w in 1..=max_weight {
            ranks[consumed as usize][w] = ranks[0][w] >> consumed;
        }
    }
    let baseline = tree_log + 1;
    let plan = X2Plan { log, sorted: &sorted, starts: &starts, ranks: &ranks, max_weight1: max_weight + 1, baseline };
    let scale = baseline as i32 - log as i32;
    let min_bits = baseline - max_weight as u32;
    for w in 1..=max_weight {
        let symbols = &sorted[starts[w] as usize..starts[w + 1] as usize];
        let nb_bits = baseline - w as u32;
        let start = ranks[0][w] as usize;
        if log - nb_bits >= min_bits {
            let length = 1usize << (log - nb_bits);
            let min_weight = (nb_bits as i32 + scale).max(1) as usize;
            for (at, &first) in symbols.iter().enumerate() {
                fill_level2(&mut table.x2[start + at * length..], &plan, nb_bits, min_weight, u32::from(first));
            }
        } else {
            fill_weight(&mut table.x2[start..], symbols, nb_bits, log, 0, 1);
        }
    }
    table.double = true;
    table.log = log;
    Ok(size)
}

#[inline(always)]
fn symbol_x1(bits: &mut Bits, table: &Table) -> u8 {
    let cell = table.x1[bits.look_fast(table.log) as usize];
    bits.skip(u32::from(cell.nb_bits));
    cell.byte
}

/// `HUF_decodeStreamX1`: fills `out` from where the stream stands, four
/// symbols a reload while the stream lasts and the rest without one.
fn stream_x1(out: &mut [u8], bits: &mut Bits, table: &Table) {
    let end = out.len();
    let mut p = 0;
    if end > 3 {
        while bits.reload() == Status::Unfinished && p + 3 < end {
            for _ in 0..4 {
                out[p] = symbol_x1(bits, table);
                p += 1;
            }
        }
    } else {
        bits.reload();
    }
    for byte in &mut out[p..] {
        *byte = symbol_x1(bits, table);
    }
}

/// Writes what a cell's `sequence` holds at `p` — both bytes, as the C's
/// two-byte store does, where `out` has room for them.
#[inline(always)]
fn put_x2(out: &mut [u8], p: usize, sequence: u16) {
    let [low, high] = sequence.to_le_bytes();
    if let Some(byte) = out.get_mut(p) {
        *byte = low;
    }
    if let Some(byte) = out.get_mut(p + 1) {
        *byte = high;
    }
}

#[inline(always)]
fn symbol_x2(out: &mut [u8], p: usize, bits: &mut Bits, table: &Table) -> usize {
    let cell = table.x2[bits.look_fast(table.log) as usize];
    put_x2(out, p, cell.sequence);
    bits.skip(u32::from(cell.nb_bits));
    usize::from(cell.length)
}

/// `HUF_decodeLastSymbolX2`: one byte of the cell, and — when the cell
/// held two — its bits taken only up to the stream's end.
fn last_symbol_x2(out: &mut [u8], p: usize, bits: &mut Bits, table: &Table) {
    let cell = table.x2[bits.look_fast(table.log) as usize];
    out[p] = cell.sequence as u8;
    if cell.length == 1 {
        bits.skip(u32::from(cell.nb_bits));
    } else if bits.consumed < 64 {
        bits.skip(u32::from(cell.nb_bits));
        bits.consumed = bits.consumed.min(64);
    }
}

/// `HUF_decodeStreamX2` over `out[p..end]`.
fn stream_x2(out: &mut [u8], mut p: usize, end: usize, bits: &mut Bits, table: &Table) {
    if end - p >= 8 {
        if table.log <= 11 {
            while bits.reload() == Status::Unfinished && p + 9 < end {
                for _ in 0..5 {
                    p += symbol_x2(out, p, bits, table);
                }
            }
        } else {
            while bits.reload() == Status::Unfinished && p + 7 < end {
                for _ in 0..4 {
                    p += symbol_x2(out, p, bits, table);
                }
            }
        }
    } else {
        bits.reload();
    }
    if end - p >= 2 {
        while bits.reload() == Status::Unfinished && p + 2 <= end {
            p += symbol_x2(out, p, bits, table);
        }
        while p + 2 <= end {
            p += symbol_x2(out, p, bits, table);
        }
    }
    if p < end {
        last_symbol_x2(out, p, bits, table);
    }
}

/// One stream (`HUF_decompress1X{1,2}_usingDTable_internal`): `out` is
/// filled, and the stream must end exactly where its symbols do.
fn single(out: &mut [u8], src: &[u8], table: &Table) -> Result<(), Corrupt> {
    let mut bits = Bits::new(src).ok_or(Corrupt)?;
    if table.double {
        let end = out.len();
        stream_x2(out, 0, end, &mut bits, table);
    } else {
        stream_x1(out, &mut bits, table);
    }
    if bits.at_end() { Ok(()) } else { Err(Corrupt) }
}

fn le16(src: &[u8], at: usize) -> usize {
    usize::from(u16::from_le_bytes([src[at], src[at + 1]]))
}

/// Four streams, the plain way (`HUF_decompress4X{1,2}_usingDTable_
/// internal_body`): in step while all four last, then one by one, each
/// held to ending exactly.
fn four_plain(out: &mut [u8], src: &[u8], table: &Table) -> Result<(), Corrupt> {
    if src.len() < 10 || out.len() < 6 {
        return Err(Corrupt);
    }
    let lengths = [le16(src, 0), le16(src, 2), le16(src, 4)];
    let used = lengths.iter().sum::<usize>() + 6;
    if used > src.len() {
        return Err(Corrupt);
    }
    let begins = [6, 6 + lengths[0], 6 + lengths[0] + lengths[1], used];
    let ends = [begins[1], begins[2], begins[3], src.len()];
    let size = out.len();
    let segment = size.div_ceil(4);
    let starts = [0, segment, 2 * segment, 3 * segment];
    if starts[3] > size {
        return Err(Corrupt);
    }
    let mut streams = Vec::with_capacity(4);
    for k in 0..4 {
        streams.push(Bits::new(&src[begins[k]..ends[k]]).ok_or(Corrupt)?);
    }
    let mut op = starts;
    let limit = [starts[1], starts[2], starts[3], size];
    if size - op[3] >= 8 {
        if table.double {
            while op[3] + 7 < size {
                for _ in 0..4 {
                    for k in 0..4 {
                        op[k] += symbol_x2(out, op[k], &mut streams[k], table);
                    }
                }
                let mut going = true;
                for stream in &mut streams {
                    going &= stream.reload_fast() == Status::Unfinished;
                }
                if !going {
                    break;
                }
            }
        } else {
            while op[3] + 3 < size {
                for _ in 0..4 {
                    for k in 0..4 {
                        out[op[k]] = symbol_x1(&mut streams[k], table);
                        op[k] += 1;
                    }
                }
                let mut going = true;
                for stream in &mut streams {
                    going &= stream.reload_fast() == Status::Unfinished;
                }
                if !going {
                    break;
                }
            }
        }
    }
    if (0..3).any(|k| op[k] > limit[k]) {
        return Err(Corrupt);
    }
    for k in 0..4 {
        if table.double {
            stream_x2(out, op[k], limit[k], &mut streams[k], table);
        } else {
            stream_x1(&mut out[op[k]..limit[k]], &mut streams[k], table);
        }
    }
    if streams.iter().all(Bits::at_end) { Ok(()) } else { Err(Corrupt) }
}

/// The fast loop's view of the four streams (`HUF_DecompressFastArgs`):
/// each stream's container holds its bits from the top, with a 1 below the
/// last valid one, so its trailing zeros count what it consumed.
struct Fast {
    ip: [usize; 4],
    op: [usize; 4],
    bits: [u64; 4],
    /// Where each stream's bytes begin; a stream may read below, but must
    /// not end up more than 8 bytes below.
    begins: [usize; 4],
}

fn le64(src: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(src[at..at + 8].try_into().expect("8 bytes"))
}

/// `HUF_initFastDStream`.
fn fast_bits(src: &[u8], at: usize) -> u64 {
    let last = src[at + 7];
    let consumed = if last == 0 { 0 } else { 8 - highbit(u32::from(last)) };
    (le64(src, at) | 1) << consumed
}

/// `HUF_DecompressFastArgs_init`: None when the fast loop does not take
/// the block.
fn fast_start(size: usize, src: &[u8], table: &Table) -> Result<Option<Fast>, Corrupt> {
    if size == 0 {
        return Ok(None);
    }
    if src.len() < 10 {
        return Err(Corrupt);
    }
    if table.log != FAST_TABLE_LOG {
        return Ok(None);
    }
    let lengths = [le16(src, 0), le16(src, 2), le16(src, 4)];
    let last = src.len().wrapping_sub(lengths.iter().sum::<usize>() + 6);
    let begins = [6, 6 + lengths[0], 6 + lengths[0] + lengths[1], 6 + lengths[0] + lengths[1] + lengths[2]];
    if lengths.iter().any(|&length| length < 8) || last < 8 {
        return Ok(None);
    }
    if last > src.len() {
        return Err(Corrupt);
    }
    let ip = [begins[1] - 8, begins[2] - 8, begins[3] - 8, src.len() - 8];
    let segment = size.div_ceil(4);
    let op = [0, segment, 2 * segment, 3 * segment];
    if op[3] >= size {
        return Ok(None);
    }
    let bits = ip.map(|at| fast_bits(src, at));
    Ok(Some(Fast { ip, op, bits, begins }))
}

/// Reloads a fast stream: whole bytes back into the container, the 1
/// marker below them again.
#[inline(always)]
fn fast_reload(fast: &mut Fast, k: usize, src: &[u8]) {
    let consumed = fast.bits[k].trailing_zeros();
    fast.ip[k] -= (consumed >> 3) as usize;
    fast.bits[k] = (le64(src, fast.ip[k]) | 1) << (consumed & 7);
}

/// The fast loop stops when a stream has crossed below the one before it:
/// the streams lie in order, so that is corruption.
fn crossed(fast: &Fast) -> bool {
    (1..4).any(|k| fast.ip[k] < fast.ip[k - 1])
}

/// `HUF_decompress4X1_usingDTable_internal_fast_c_loop`: five symbols of
/// each stream a round, as many rounds as the output and the input are
/// sure to hold — a round consumes at most 5 × 11 bits, under 7 bytes, of
/// a stream, and no stream lies below the first.
fn fast_loop_x1(out: &mut [u8], src: &[u8], table: &Table, fast: &mut Fast) {
    let size = out.len();
    loop {
        let rounds = ((size - fast.op[3]) / 5).min(fast.ip[0] / 7);
        if rounds == 0 || crossed(fast) {
            return;
        }
        for _ in 0..rounds {
            for symbol in 0..5 {
                for k in 0..4 {
                    let cell = table.x1[(fast.bits[k] >> 53) as usize];
                    fast.bits[k] <<= cell.nb_bits & 0x3F;
                    out[fast.op[k] + symbol] = cell.byte;
                }
            }
            for k in 0..4 {
                fast.op[k] += 5;
                fast_reload(fast, k, src);
            }
        }
    }
}

/// `HUF_decompress4X2_usingDTable_internal_fast_c_loop`: five cells of
/// each stream a round. A round writes at most 10 bytes of a stream and at
/// least 5, so the rounds the outputs are sure to hold are counted against
/// the last stream's progress — fewer run when its cells hold two symbols.
fn fast_loop_x2(out: &mut [u8], src: &[u8], table: &Table, fast: &mut Fast) {
    let ends = [fast.op[1], fast.op[2], fast.op[3], out.len()];
    loop {
        let rounds = (0..4).map(|k| (ends[k] - fast.op[k]) / 10).fold(fast.ip[0] / 7, usize::min);
        if rounds == 0 || crossed(fast) {
            return;
        }
        let limit = fast.op[3] + rounds * 5;
        while fast.op[3] < limit {
            for _ in 0..5 {
                for k in 0..4 {
                    let cell = table.x2[(fast.bits[k] >> 53) as usize];
                    let [low, high] = cell.sequence.to_le_bytes();
                    out[fast.op[k]] = low;
                    out[fast.op[k] + 1] = high;
                    fast.bits[k] <<= cell.nb_bits & 0x3F;
                    fast.op[k] += usize::from(cell.length);
                }
            }
            for k in 0..4 {
                fast_reload(fast, k, src);
            }
        }
    }
}

/// `HUF_decompress4X{1,2}_usingDTable_internal_fast`: the fast loop, then
/// each stream finished by the plain one-stream decoder — held to its
/// segment, not to its bits. None when the fast loop does not take it.
fn four_fast(out: &mut [u8], src: &[u8], table: &Table) -> Result<Option<()>, Corrupt> {
    let Some(mut fast) = fast_start(out.len(), src, table)? else {
        return Ok(None);
    };
    if table.double {
        fast_loop_x2(out, src, table, &mut fast);
    } else {
        fast_loop_x1(out, src, table, &mut fast);
    }
    let size = out.len();
    let segment = size.div_ceil(4);
    let mut end = 0;
    for k in 0..4 {
        end = if segment <= size - end { end + segment } else { size };
        if fast.op[k] > end || (fast.ip[k] as isize) < fast.begins[k] as isize - 8 {
            return Err(Corrupt);
        }
        let mut bits = Bits::resumed(src, fast.ip[k], fast.bits[k].trailing_zeros());
        if table.double {
            stream_x2(out, fast.op[k], end, &mut bits, table);
        } else {
            stream_x1(&mut out[fast.op[k]..end], &mut bits, table);
        }
    }
    Ok(Some(()))
}

fn four(out: &mut [u8], src: &[u8], table: &Table) -> Result<(), Corrupt> {
    match four_fast(out, src, table)? {
        Some(()) => Ok(()),
        None => four_plain(out, src, table),
    }
}

/// Literals in one stream under a new tree (`HUF_decompress1X1_DCtx_wksp`:
/// always single-symbol).
pub(crate) fn single_with_new_tree(out: &mut [u8], src: &[u8], table: &mut Table) -> Result<(), Corrupt> {
    let header = read_x1(table, src)?;
    if header >= src.len() {
        return Err(Corrupt);
    }
    single(out, &src[header..], table)
}

/// Literals in one stream under the previous block's tree.
pub(crate) fn single_with_previous_tree(out: &mut [u8], src: &[u8], table: &Table) -> Result<(), Corrupt> {
    single(out, src, table)
}

/// Which table decodes four streams faster (`HUF_selectDecoder`): the C's
/// measured costs, and its choice is the Rust's.
fn prefers_double(size: usize, compressed: usize) -> bool {
    const COSTS: [[(u32, u32); 2]; 16] = [
        [(0, 0), (1, 1)],
        [(0, 0), (1, 1)],
        [(150, 216), (381, 119)],
        [(170, 205), (514, 112)],
        [(177, 199), (539, 110)],
        [(197, 194), (644, 107)],
        [(221, 192), (735, 107)],
        [(256, 189), (881, 106)],
        [(359, 188), (1167, 109)],
        [(582, 187), (1570, 114)],
        [(688, 187), (1712, 122)],
        [(825, 186), (1965, 136)],
        [(976, 185), (2131, 150)],
        [(1180, 186), (2070, 175)],
        [(1377, 185), (1731, 202)],
        [(1412, 185), (1695, 202)],
    ];
    let q = if compressed >= size { 15 } else { compressed * 16 / size };
    let d256 = (size >> 8) as u32;
    let [single, double] = COSTS[q];
    let single = single.0 + single.1 * d256;
    let mut double = double.0 + double.1 * d256;
    double += double >> 5;
    double < single
}

/// Literals in four streams under a new tree (`HUF_decompress4X_hufOnly_
/// wksp`).
pub(crate) fn four_with_new_tree(out: &mut [u8], src: &[u8], table: &mut Table) -> Result<(), Corrupt> {
    if out.is_empty() || src.is_empty() {
        return Err(Corrupt);
    }
    let header = if prefers_double(out.len(), src.len()) { read_x2(table, src)? } else { read_x1(table, src)? };
    if header >= src.len() {
        return Err(Corrupt);
    }
    four(out, &src[header..], table)
}

/// Literals in four streams under the previous block's tree.
pub(crate) fn four_with_previous_tree(out: &mut [u8], src: &[u8], table: &Table) -> Result<(), Corrupt> {
    four(out, src, table)
}
