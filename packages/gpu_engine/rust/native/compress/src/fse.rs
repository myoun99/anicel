//! Finite State Entropy: the normalized counts a table is described by
//! (`FSE_readNCount`), the spread that turns them into a decoding table,
//! and the byte decoder Huffman weights are coded with
//! (`FSE_decompress_wksp`).

use crate::Corrupt;
use crate::bits::{Bits, Status, highbit};

pub(crate) const MIN_TABLE_LOG: i32 = 5;
const ABSOLUTE_MAX_TABLE_LOG: i32 = 15;

fn le32(src: &[u8], at: isize) -> u32 {
    let at = at as usize;
    u32::from_le_bytes(src[at..at + 4].try_into().expect("4 bytes"))
}

/// Moves `ip` past the bits counted so far — or, near the end of the
/// header, pins it 4 bytes from the end and keeps the count of bits in
/// the word read there.
fn advance(ip: &mut isize, bit_count: &mut i32, end: isize) {
    if *ip <= end - 7 || *ip + (*bit_count >> 3) as isize <= end - 4 {
        *ip += (*bit_count >> 3) as isize;
        *bit_count &= 7;
    } else {
        *bit_count -= (8 * (end - 4 - *ip)) as i32;
        *bit_count &= 31;
        *ip = end - 4;
    }
}

/// Reads a table description into `counts` (-1 = a "less than one"
/// symbol): the bytes it took. `max_symbol` comes in as the largest symbol
/// allowed and goes out as the last one described.
pub(crate) fn read_counts(
    counts: &mut [i16],
    max_symbol: &mut u32,
    table_log: &mut u32,
    src: &[u8],
) -> Result<usize, Corrupt> {
    if src.len() < 8 {
        // The reader wants 8 bytes; a shorter header is read from a copy.
        let mut padded = [0u8; 8];
        padded[..src.len()].copy_from_slice(src);
        let size = read_counts(counts, max_symbol, table_log, &padded)?;
        return if size > src.len() { Err(Corrupt) } else { Ok(size) };
    }
    let end = src.len() as isize;
    let mut ip: isize = 0;
    let symbols = *max_symbol + 1;
    counts[..symbols as usize].fill(0);
    let mut bit_stream = le32(src, ip);
    let mut nb_bits = (bit_stream & 0xF) as i32 + MIN_TABLE_LOG;
    if nb_bits > ABSOLUTE_MAX_TABLE_LOG {
        return Err(Corrupt);
    }
    bit_stream >>= 4;
    let mut bit_count: i32 = 4;
    *table_log = nb_bits as u32;
    let mut remaining: i32 = (1 << nb_bits) + 1;
    let mut threshold: i32 = 1 << nb_bits;
    nb_bits += 1;
    let mut symbol: u32 = 0;
    let mut previous_was_zero = false;
    loop {
        if previous_was_zero {
            // Each 0b11 repeat code is three more zero counts.
            let mut repeats = (!bit_stream | 0x8000_0000).trailing_zeros() >> 1;
            while repeats >= 12 {
                symbol += 3 * 12;
                if ip <= end - 7 {
                    ip += 3;
                } else {
                    bit_count -= (8 * (end - 7 - ip)) as i32;
                    bit_count &= 31;
                    ip = end - 4;
                }
                bit_stream = le32(src, ip) >> bit_count;
                repeats = (!bit_stream | 0x8000_0000).trailing_zeros() >> 1;
            }
            symbol += 3 * repeats;
            bit_stream >>= 2 * repeats;
            bit_count += 2 * repeats as i32;
            symbol += bit_stream & 3;
            bit_count += 2;
            if symbol >= symbols {
                break;
            }
            advance(&mut ip, &mut bit_count, end);
            bit_stream = le32(src, ip) >> bit_count;
        }
        let max = (2 * threshold - 1) - remaining;
        let mut count;
        if bit_stream & (threshold as u32 - 1) < max as u32 {
            count = (bit_stream & (threshold as u32 - 1)) as i32;
            bit_count += nb_bits - 1;
        } else {
            count = (bit_stream & (2 * threshold as u32 - 1)) as i32;
            if count >= threshold {
                count -= max;
            }
            bit_count += nb_bits;
        }
        count -= 1;
        // A count of -1 takes one cell, as a count of 1 does.
        remaining -= count.abs();
        counts[symbol as usize] = count as i16;
        symbol += 1;
        previous_was_zero = count == 0;
        if remaining < threshold {
            if remaining <= 1 {
                break;
            }
            nb_bits = highbit(remaining as u32) as i32 + 1;
            threshold = 1 << (nb_bits - 1);
        }
        if symbol >= symbols {
            break;
        }
        advance(&mut ip, &mut bit_count, end);
        bit_stream = le32(src, ip) >> bit_count;
    }
    if remaining != 1 || symbol > symbols || bit_count > 32 {
        return Err(Corrupt);
    }
    *max_symbol = symbol - 1;
    ip += ((bit_count + 7) >> 3) as isize;
    Ok(ip as usize)
}

/// The step that walks a table's cells once each (`FSE_TABLESTEP`).
pub(crate) fn table_step(size: usize) -> usize {
    (size >> 1) + (size >> 3) + 3
}

/// Lays each described symbol into the cells of a table of `1 << log`, the
/// way every FSE table is spread, and hands each cell its symbol and the
/// symbol's running count — what a decoder needs to derive its next state.
/// False when the counts do not fill the table exactly.
pub(crate) fn spread(counts: &[i16], log: u32, mut cell: impl FnMut(usize, usize, u32)) -> bool {
    let size = 1usize << log;
    let mask = size - 1;
    let step = table_step(size);
    let mut symbol_of = [0u8; 1 << MAX_SEQ_TABLE_LOG];
    let mut next = [0u32; 256];
    // "Less than one" symbols take the last cells, one each.
    let mut high = size - 1;
    for (symbol, &count) in counts.iter().enumerate() {
        if count == -1 {
            symbol_of[high] = symbol as u8;
            high = high.wrapping_sub(1);
            next[symbol] = 1;
        } else {
            next[symbol] = count as u32;
        }
    }
    let mut position = 0;
    for (symbol, &count) in counts.iter().enumerate() {
        for _ in 0..count.max(0) {
            symbol_of[position] = symbol as u8;
            position = (position + step) & mask;
            while position > high {
                position = (position + step) & mask;
            }
        }
    }
    if position != 0 {
        return false;
    }
    for (at, &symbol) in symbol_of[..size].iter().enumerate() {
        let state = next[symbol as usize];
        next[symbol as usize] += 1;
        cell(at, symbol as usize, state);
    }
    true
}

/// The largest table any zstd FSE table is: the sequence tables' 9.
pub(crate) const MAX_SEQ_TABLE_LOG: u32 = 9;

#[derive(Clone, Copy, Default)]
struct Cell {
    symbol: u8,
    nb_bits: u8,
    new_state: u16,
}

/// A byte-symbol decoding table (`FSE_DTable`).
struct Table {
    log: u32,
    /// No symbol takes half the table or more: every cell reads a bit.
    fast: bool,
    cells: [Cell; 1 << 6],
}

/// `FSE_buildDTable_internal`, for the tables of at most `1 << 6` cells
/// Huffman weights are read with.
fn build(counts: &[i16], log: u32) -> Option<Table> {
    let size = 1u32 << log;
    let mut table = Table { log, fast: true, cells: [Cell::default(); 1 << 6] };
    let large = 1i16 << (log - 1);
    table.fast = counts.iter().all(|&count| count < large);
    let laid = spread(counts, log, |at, symbol, state| {
        let nb_bits = log - highbit(state);
        table.cells[at] = Cell { symbol: symbol as u8, nb_bits: nb_bits as u8, new_state: ((state << nb_bits) - size) as u16 };
    });
    laid.then_some(table)
}

struct State {
    at: usize,
}

impl State {
    fn new(bits: &mut Bits, table: &Table) -> Self {
        let at = bits.read(table.log) as usize;
        bits.reload();
        State { at }
    }

    /// The state's symbol, moving it on (`FSE_decodeSymbol[Fast]`).
    #[inline(always)]
    fn symbol(&mut self, bits: &mut Bits, table: &Table) -> u8 {
        let cell = table.cells[self.at];
        let low = if table.fast { bits.read_fast(u32::from(cell.nb_bits)) } else { bits.read(u32::from(cell.nb_bits)) };
        self.at = usize::from(cell.new_state) + low as usize;
        cell.symbol
    }
}

/// `FSE_decompress_usingDTable_generic`: two interleaved states, run until
/// the stream overflows — the encoder flushes its states last, so the
/// final symbols are read without bits.
fn decode(dst: &mut [u8], src: &[u8], table: &Table) -> Result<usize, Corrupt> {
    let mut bits = Bits::new(src).ok_or(Corrupt)?;
    let mut one = State::new(&mut bits, table);
    let mut two = State::new(&mut bits, table);
    let end = dst.len();
    let mut op = 0;
    while bits.reload() == Status::Unfinished && op < end - 3 {
        dst[op] = one.symbol(&mut bits, table);
        dst[op + 1] = two.symbol(&mut bits, table);
        dst[op + 2] = one.symbol(&mut bits, table);
        dst[op + 3] = two.symbol(&mut bits, table);
        op += 4;
    }
    loop {
        if op > end - 2 {
            return Err(Corrupt);
        }
        dst[op] = one.symbol(&mut bits, table);
        op += 1;
        if bits.reload() == Status::Overflow {
            dst[op] = two.symbol(&mut bits, table);
            return Ok(op + 1);
        }
        if op > end - 2 {
            return Err(Corrupt);
        }
        dst[op] = two.symbol(&mut bits, table);
        op += 1;
        if bits.reload() == Status::Overflow {
            dst[op] = one.symbol(&mut bits, table);
            return Ok(op + 1);
        }
    }
}

/// Huffman weights, FSE-coded (`FSE_decompress_wksp` with a table log of at
/// most 6): how many were written into `dst`.
pub(crate) fn decode_weights(dst: &mut [u8], src: &[u8]) -> Result<usize, Corrupt> {
    const MAX_LOG: u32 = 6;
    let mut counts = [0i16; 256];
    let mut max_symbol = 255;
    let mut log = 0;
    let header = read_counts(&mut counts, &mut max_symbol, &mut log, src)?;
    if log > MAX_LOG {
        return Err(Corrupt);
    }
    let table = build(&counts[..=max_symbol as usize], log).ok_or(Corrupt)?;
    decode(dst, &src[header..], &table)
}
