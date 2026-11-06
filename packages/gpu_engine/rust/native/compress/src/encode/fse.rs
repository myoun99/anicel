//! FSE, the encoding half (`fse_compress.c`): a histogram normalized to a
//! table of 2^log states, the header that describes it, the table, and the
//! states that code symbols with it.

use super::stream::Stream;
use crate::bits::highbit;
use crate::fse::{MAX_SEQ_TABLE_LOG, MIN_TABLE_LOG, spread};

/// `FSE_MAX_TABLELOG`.
const MAX_TABLE_LOG: u32 = 12;
/// The largest alphabet coded here: the match-length codes (`MaxSeq + 1`).
pub(super) const SYMBOLS: usize = 53;
/// The largest table coded here (`MaxFSELog`).
const STATES: usize = 1 << MAX_SEQ_TABLE_LOG;
/// `FSE_NCOUNTBOUND`: room for any table's description.
pub(super) const DESCRIPTION_BOUND: usize = 512;

/// `FSE_minTableLog`.
fn min_table_log(total: usize, max_symbol: u32) -> u32 {
    (highbit(total as u32) + 1).min(highbit(max_symbol) + 2)
}

/// `FSE_optimalTableLog_internal`: `minus` is 2 for FSE's own tables, 1
/// for a Huffman tree's depth.
pub(super) fn optimal_table_log(max_log: u32, total: usize, max_symbol: u32, minus: u32) -> u32 {
    // The C's U32 arithmetic: two symbols' worth wraps past every bound.
    let from_total = highbit((total - 1) as u32).wrapping_sub(minus);
    let mut log = max_log;
    if from_total < log {
        log = from_total;
    }
    let min_bits = min_table_log(total, max_symbol);
    if min_bits > log {
        log = min_bits;
    }
    log.clamp(MIN_TABLE_LOG as u32, MAX_TABLE_LOG)
}

/// `rtbTable`: how far past a whole state a small probability must reach
/// to round up.
const REST_TO_BEAT: [u64; 8] = [0, 473195, 504333, 520860, 550000, 700000, 750000, 830000];

/// `FSE_normalizeCount`: `count` (summing to `total`) scaled to 2^log
/// states. An absent symbol takes 0; one too rare for a state of its own
/// takes -1 ("less than one", a state from the top of the table) when
/// `low_probability` allows, else 1. None on the C's GENERIC error.
pub(super) fn normalize(
    norm: &mut [i16; SYMBOLS],
    log: u32,
    count: &[u32],
    total: usize,
    max_symbol: u32,
    low_probability: bool,
) -> Option<()> {
    if !(MIN_TABLE_LOG as u32..=MAX_TABLE_LOG).contains(&log) || log < min_table_log(total, max_symbol) {
        return None;
    }
    let low = if low_probability { -1 } else { 1 };
    let scale = 62 - log;
    let step = (1u64 << 62) / u64::from(total as u32);
    let v_step = 1u64 << (scale - 20);
    let mut still_to_distribute = 1i32 << log;
    let mut largest = 0;
    let mut largest_probability = 0i16;
    let low_threshold = (total >> log) as u32;
    for s in 0..=max_symbol as usize {
        debug_assert!(count[s] as usize != total, "a single symbol is coded as a run, never normalized");
        if count[s] == 0 {
            norm[s] = 0;
            continue;
        }
        if count[s] <= low_threshold {
            norm[s] = low;
            still_to_distribute -= 1;
        } else {
            let scaled = u64::from(count[s]) * step;
            let mut probability = (scaled >> scale) as i16;
            if probability < 8 {
                let rest_to_beat = v_step * REST_TO_BEAT[probability as usize];
                probability += i16::from(scaled - ((probability as u64) << scale) > rest_to_beat);
            }
            if probability > largest_probability {
                largest_probability = probability;
                largest = s;
            }
            norm[s] = probability;
            still_to_distribute -= i32::from(probability);
        }
    }
    if -still_to_distribute >= i32::from(norm[largest] >> 1) {
        normalize_slowly(norm, log, count, total, max_symbol, low)
    } else {
        norm[largest] += still_to_distribute as i16;
        Some(())
    }
}

/// `FSE_normalizeM2`: the second method, for when rounding took more than
/// half of the largest symbol's share.
fn normalize_slowly(
    norm: &mut [i16; SYMBOLS],
    log: u32,
    count: &[u32],
    mut total: usize,
    max_symbol: u32,
    low: i16,
) -> Option<()> {
    const NOT_YET_ASSIGNED: i16 = -2;
    let symbols = max_symbol as usize + 1;
    let mut distributed = 0u32;
    let low_threshold = (total >> log) as u32;
    let mut low_one = ((total * 3) >> (log + 1)) as u32;
    for s in 0..symbols {
        if count[s] == 0 {
            norm[s] = 0;
        } else if count[s] <= low_threshold {
            norm[s] = low;
            distributed += 1;
            total -= count[s] as usize;
        } else if count[s] <= low_one {
            norm[s] = 1;
            distributed += 1;
            total -= count[s] as usize;
        } else {
            norm[s] = NOT_YET_ASSIGNED;
        }
    }
    let mut to_distribute = (1u32 << log) - distributed;
    if to_distribute == 0 {
        return Some(());
    }
    if total / to_distribute as usize > low_one as usize {
        // Too little left for each: lower the bar for "one state".
        low_one = ((total * 3) / (to_distribute as usize * 2)) as u32;
        for s in 0..symbols {
            if norm[s] == NOT_YET_ASSIGNED && count[s] <= low_one {
                norm[s] = 1;
                distributed += 1;
                total -= count[s] as usize;
            }
        }
        to_distribute = (1u32 << log) - distributed;
    }
    if distributed as usize == symbols {
        // Every symbol is poor: the most frequent takes the rest.
        let (mut most, mut most_count) = (0, 0);
        for s in 0..symbols {
            if count[s] > most_count {
                most = s;
                most_count = count[s];
            }
        }
        norm[most] += to_distribute as i16;
        return Some(());
    }
    if total == 0 {
        // Every symbol was rare: the rest goes round them, a state each.
        let mut s = 0;
        while to_distribute > 0 {
            if norm[s] > 0 {
                to_distribute -= 1;
                norm[s] += 1;
            }
            s = (s + 1) % symbols;
        }
        return Some(());
    }
    let v_step_log = 62 - log;
    let mid = (1u64 << (v_step_log - 1)) - 1;
    let r_step = ((1u64 << v_step_log) * u64::from(to_distribute) + mid) / u64::from(total as u32);
    let mut tmp_total = mid;
    for s in 0..symbols {
        if norm[s] == NOT_YET_ASSIGNED {
            let end = tmp_total + u64::from(count[s]) * r_step;
            let weight = (end >> v_step_log) as u32 - (tmp_total >> v_step_log) as u32;
            if weight < 1 {
                return None;
            }
            norm[s] = weight as i16;
            tmp_total = end;
        }
    }
    Some(())
}

/// `FSE_writeNCount`: the description of `norm` a decoder reads back, or
/// None when `out` cannot hold it.
pub(super) fn describe(out: &mut [u8], norm: &[i16], max_symbol: u32, log: u32) -> Option<usize> {
    fn put(out: &mut [u8], at: usize, stream: u32) -> Option<()> {
        out.get_mut(at..at + 2)?.copy_from_slice(&(stream as u16).to_le_bytes());
        Some(())
    }
    let table_size = 1i32 << log;
    let alphabet = max_symbol as usize + 1;
    let mut at = 0;
    let mut stream = log - MIN_TABLE_LOG as u32;
    let mut bit_count = 4;
    let mut remaining = table_size + 1;
    let mut threshold = table_size;
    let mut nb_bits = log as i32 + 1;
    let mut symbol = 0;
    let mut previous_was_zero = false;
    while symbol < alphabet && remaining > 1 {
        if previous_was_zero {
            let mut start = symbol;
            while symbol < alphabet && norm[symbol] == 0 {
                symbol += 1;
            }
            if symbol == alphabet {
                break;
            }
            while symbol >= start + 24 {
                start += 24;
                stream = stream.wrapping_add(0xFFFF << bit_count);
                put(out, at, stream)?;
                at += 2;
                stream >>= 16;
            }
            while symbol >= start + 3 {
                start += 3;
                stream = stream.wrapping_add(3 << bit_count);
                bit_count += 2;
            }
            stream = stream.wrapping_add(((symbol - start) as u32) << bit_count);
            bit_count += 2;
            if bit_count > 16 {
                put(out, at, stream)?;
                at += 2;
                stream >>= 16;
                bit_count -= 16;
            }
        }
        let mut count = i32::from(norm[symbol]);
        symbol += 1;
        let max = (2 * threshold - 1) - remaining;
        remaining -= count.abs();
        count += 1;
        if count >= threshold {
            count += max;
        }
        stream = stream.wrapping_add((count as u32) << bit_count);
        bit_count += nb_bits;
        bit_count -= i32::from(count < max);
        previous_was_zero = count == 1;
        debug_assert!(remaining >= 1, "a normalized distribution never overdraws");
        while remaining < threshold {
            nb_bits -= 1;
            threshold >>= 1;
        }
        if bit_count > 16 {
            put(out, at, stream)?;
            at += 2;
            stream >>= 16;
            bit_count -= 16;
        }
    }
    debug_assert!(remaining == 1, "a normalized distribution fills its table");
    put(out, at, stream)?;
    Some(at + (bit_count as usize).div_ceil(8))
}

/// `FSE_symbolCompressionTransform`.
#[derive(Clone, Copy, Default)]
struct Transform {
    find_state: i32,
    nb_bits: u32,
}

/// `FSE_CTable`.
#[derive(Clone)]
pub(super) struct Table {
    pub(super) log: u32,
    pub(super) max_symbol: u32,
    states: [u16; STATES],
    symbols: [Transform; SYMBOLS],
}

impl Table {
    pub(super) fn new() -> Self {
        Table { log: 0, max_symbol: 0, states: [0; STATES], symbols: [Transform::default(); SYMBOLS] }
    }

    /// `FSE_buildCTable_wksp`. A symbol absent from `norm` keeps its old
    /// state step, as in the C — it is never coded.
    pub(super) fn build(&mut self, norm: &[i16], max_symbol: u32, log: u32) {
        let size = 1u32 << log;
        let norm = &norm[..=max_symbol as usize];
        self.log = log;
        self.max_symbol = max_symbol;
        let share = |s: usize| if norm[s] == -1 { 1 } else { norm[s] as u32 };
        let mut first = [0u32; SYMBOLS];
        for s in 1..norm.len() {
            first[s] = first[s - 1] + share(s - 1);
        }
        let states = &mut self.states;
        // The cells a decoder spreads, in order: each symbol's states go
        // to its cells in the order the cells come.
        let laid = spread(norm, log, |at, s, state| {
            states[(first[s] + state - share(s)) as usize] = (size + at as u32) as u16;
        });
        debug_assert!(laid, "a normalized distribution fills its table");
        let mut total = 0u32;
        for (s, &n) in norm.iter().enumerate() {
            let transform = &mut self.symbols[s];
            match n {
                0 => transform.nb_bits = ((log + 1) << 16) - size,
                -1 | 1 => {
                    transform.nb_bits = (log << 16) - size;
                    transform.find_state = total as i32 - 1;
                    total += 1;
                }
                n => {
                    let n = n as u32;
                    let max_bits_out = log - highbit(n - 1);
                    transform.nb_bits = (max_bits_out << 16) - (n << max_bits_out);
                    transform.find_state = total as i32 - n as i32;
                    total += n;
                }
            }
        }
    }

    /// `FSE_buildCTable_rle`: every symbol is `symbol`, coded in no bits.
    pub(super) fn run(&mut self, symbol: u8) {
        self.log = 0;
        self.max_symbol = u32::from(symbol);
        self.states[0] = 0;
        self.states[1] = 0;
        self.symbols[symbol as usize] = Transform::default();
    }

    /// `FSE_bitCost` at accuracy log 8: a symbol's cost in 1/256 bits.
    pub(super) fn bit_cost(&self, symbol: usize) -> u32 {
        const ACCURACY_LOG: u32 = 8;
        let nb_bits = self.symbols[symbol].nb_bits;
        let min_nb_bits = nb_bits >> 16;
        let threshold = (min_nb_bits + 1) << 16;
        let below = threshold - (nb_bits + (1 << self.log));
        let normalized = (below << ACCURACY_LOG) >> self.log;
        (min_nb_bits + 1) * (1 << ACCURACY_LOG) - normalized
    }
}

/// `FSE_CState_t`, its table passed to each call.
pub(super) struct State {
    value: u32,
}

impl State {
    /// `FSE_initCState2`: the first symbol coded — the last one a decoder
    /// reads — takes the smallest state that codes it.
    pub(super) fn first(table: &Table, symbol: usize) -> Self {
        let transform = table.symbols[symbol];
        let nb_bits_out = (transform.nb_bits + (1 << 15)) >> 16;
        let value = (nb_bits_out << 16).wrapping_sub(transform.nb_bits);
        State { value: u32::from(table.states[((value >> nb_bits_out) as i32 + transform.find_state) as usize]) }
    }

    /// `FSE_encodeSymbol`.
    #[inline(always)]
    pub(super) fn encode(&mut self, stream: &mut Stream, table: &Table, symbol: usize) {
        let transform = table.symbols[symbol];
        let nb_bits_out = (self.value + transform.nb_bits) >> 16;
        stream.add(u64::from(self.value), nb_bits_out);
        self.value = u32::from(table.states[((self.value >> nb_bits_out) as i32 + transform.find_state) as usize]);
    }

    /// `FSE_flushCState`.
    pub(super) fn close(&self, stream: &mut Stream, table: &Table) {
        stream.add(u64::from(self.value), table.log);
        stream.flush();
    }
}

/// `FSE_compress_usingCTable`: `src` coded with `table` into `out` — its
/// size, or 0 when `src` is too short to code or does not fit.
pub(super) fn code(out: &mut [u8], src: &[u8], table: &Table) -> usize {
    if src.len() <= 2 {
        return 0;
    }
    let Some(mut stream) = Stream::new(out) else {
        return 0;
    };
    // From the last symbol back, two interleaved states.
    let mut symbols = src.iter().rev().map(|&s| s as usize);
    let mut next = || symbols.next().expect("counted");
    let (mut one, mut two);
    if src.len() & 1 == 1 {
        one = State::first(table, next());
        two = State::first(table, next());
        one.encode(&mut stream, table, next());
        stream.flush();
    } else {
        two = State::first(table, next());
        one = State::first(table, next());
    }
    let mut left = src.len() - 2 - (src.len() & 1);
    if (src.len() - 2) & 2 != 0 {
        two.encode(&mut stream, table, next());
        one.encode(&mut stream, table, next());
        stream.flush();
        left -= 2;
    }
    for _ in 0..left / 4 {
        two.encode(&mut stream, table, next());
        one.encode(&mut stream, table, next());
        two.encode(&mut stream, table, next());
        one.encode(&mut stream, table, next());
        stream.flush();
    }
    two.close(&mut stream, table);
    one.close(&mut stream, table);
    stream.close()
}
