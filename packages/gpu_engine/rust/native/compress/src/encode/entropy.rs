//! A block's entropy stage (`ZSTD_entropyCompressSeqStore`,
//! `zstd_compress_sequences.c`): the literal section, then the sequences —
//! each of their three codes under the table that costs least (the
//! default, the previous block's, one described here, or one symbol) — in
//! one FSE bitstream.

use super::fse::{self, DESCRIPTION_BOUND, SYMBOLS, State, Table};
use super::literals::{self, Tree};
use super::stream::Stream;
use super::{Error, Repeat, TooSmall};
use crate::bits::highbit;
use crate::sequences::{
    BASIC, COMPRESSED, Code, LITERAL_LENGTHS, LL_BASE, LL_BITS, MATCH_LENGTHS, ML_BASE, ML_BITS, OFFSETS, RLE,
};

/// `set_repeat`.
const REPEAT: u8 = 3;
/// `LONGNBSEQ`.
const LONG_COUNT: usize = 0x7F00;
/// `DefaultMaxOff`: the default offset table stops at code 28.
const DEFAULT_MAX_OFFSET: u32 = 28;
/// `SUSPECT_UNCOMPRESSIBLE_LITERAL_RATIO`.
const SUSPECT_RATIO: usize = 20;

/// One sequence (`seqDef`): this many literals, then a match `ml_base + 3`
/// long at `off_base` — a repeat code 1..=3, or an offset + 3. Lengths
/// are held whole: the C keeps 16 bits and marks the one longer length,
/// whose code is then the largest — the code the whole value takes.
#[derive(Clone, Copy)]
pub(super) struct Sequence {
    pub(super) lit_length: u32,
    pub(super) off_base: u32,
    pub(super) ml_base: u32,
}

/// `seqStore_t`.
pub(super) struct Store {
    pub(super) sequences: Vec<Sequence>,
    pub(super) literals: Vec<u8>,
    codes: [Vec<u8>; 3],
}

impl Store {
    pub(super) fn new(block_size: usize) -> Self {
        let sequences = block_size / 4;
        Store {
            sequences: Vec::with_capacity(sequences),
            literals: Vec::with_capacity(block_size),
            codes: [Vec::with_capacity(sequences), Vec::with_capacity(sequences), Vec::with_capacity(sequences)],
        }
    }

    /// `ZSTD_resetSeqStore`.
    pub(super) fn clear(&mut self) {
        self.sequences.clear();
        self.literals.clear();
    }

    /// `ZSTD_storeSeq`: `literals` then a match.
    #[inline(always)]
    pub(super) fn push(&mut self, literals: &[u8], off_base: u32, match_length: usize) {
        self.literals.extend_from_slice(literals);
        self.sequences.push(Sequence {
            lit_length: literals.len() as u32,
            off_base,
            ml_base: (match_length - 3) as u32,
        });
    }
}

/// The FSE table a block hands the next, and whether it may be repeated.
#[derive(Clone)]
pub(super) struct Coder {
    table: Table,
    repeat: Repeat,
}

/// `ZSTD_entropyCTables_t`.
#[derive(Clone)]
pub(super) struct Entropy {
    tree: Tree,
    /// Literal lengths, offsets, match lengths.
    coders: [Coder; 3],
}

impl Entropy {
    /// `ZSTD_reset_compressedBlockState`.
    pub(super) fn new() -> Self {
        let coder = Coder { table: Table::new(), repeat: Repeat::None };
        Entropy {
            tree: Tree { table: super::huffman::Table::new(), repeat: Repeat::None },
            coders: [coder.clone(), coder.clone(), coder],
        }
    }
}

/// `ZSTD_LLcode`'s and `ZSTD_MLcode`'s tables: a value's code is the last
/// whose base it reaches.
const fn codes<const N: usize>(base: &[u32], minus: u32) -> [u8; N] {
    let mut table = [0u8; N];
    let mut code = 0;
    let mut value = 0;
    while value < N {
        while code + 1 < base.len() && base[code + 1] - minus <= value as u32 {
            code += 1;
        }
        table[value] = code as u8;
        value += 1;
    }
    table
}
const LL_CODE: [u8; 64] = codes(&LL_BASE, 0);
const ML_CODE: [u8; 128] = codes(&ML_BASE, 3);

/// `ZSTD_seqToCodes`.
fn to_codes(store: &mut Store) {
    let [ll, of, ml] = &mut store.codes;
    ll.clear();
    of.clear();
    ml.clear();
    for sequence in &store.sequences {
        let lit_length = sequence.lit_length;
        ll.push(if lit_length > 63 { (highbit(lit_length) + 19) as u8 } else { LL_CODE[lit_length as usize] });
        of.push(highbit(sequence.off_base) as u8);
        let ml_base = sequence.ml_base;
        ml.push(if ml_base > 127 { (highbit(ml_base) + 36) as u8 } else { ML_CODE[ml_base as usize] });
    }
}

/// `kInverseProbabilityLog256`: -log2(p / 256) in 1/256 bits.
const INVERSE_LOG: [u32; 256] = [
    0, 2048, 1792, 1642, 1536, 1453, 1386, 1329, 1280, 1236, 1197, 1162, 1130, 1100, 1073, 1047, 1024, 1001, 980, 960,
    941, 923, 906, 889, 874, 859, 844, 830, 817, 804, 791, 779, 768, 756, 745, 734, 724, 714, 704, 694, 685, 676, 667,
    658, 650, 642, 633, 626, 618, 610, 603, 595, 588, 581, 574, 567, 561, 554, 548, 542, 535, 529, 523, 517, 512, 506,
    500, 495, 489, 484, 478, 473, 468, 463, 458, 453, 448, 443, 438, 434, 429, 424, 420, 415, 411, 407, 402, 398, 394,
    390, 386, 382, 377, 373, 370, 366, 362, 358, 354, 350, 347, 343, 339, 336, 332, 329, 325, 322, 318, 315, 311, 308,
    305, 302, 298, 295, 292, 289, 286, 282, 279, 276, 273, 270, 267, 264, 261, 258, 256, 253, 250, 247, 244, 241, 239,
    236, 233, 230, 228, 225, 222, 220, 217, 215, 212, 209, 207, 204, 202, 199, 197, 194, 192, 190, 187, 185, 182, 180,
    178, 175, 173, 171, 168, 166, 164, 162, 159, 157, 155, 153, 151, 149, 146, 144, 142, 140, 138, 136, 134, 132, 130,
    128, 126, 123, 121, 119, 117, 115, 114, 112, 110, 108, 106, 104, 102, 100, 98, 96, 94, 93, 91, 89, 87, 85, 83, 82,
    80, 78, 76, 74, 73, 71, 69, 67, 66, 64, 62, 61, 59, 57, 55, 54, 52, 50, 49, 47, 46, 44, 42, 41, 39, 37, 36, 34, 33,
    31, 30, 28, 26, 25, 23, 22, 20, 19, 17, 16, 14, 13, 11, 10, 8, 7, 5, 4, 2, 1,
];

/// `ERROR(GENERIC)` as a cost: never the cheapest.
const NO_COST: usize = usize::MAX;

/// `ZSTD_crossEntropyCost`: `count` under the default distribution.
fn default_cost(code: &Code, count: &[u32], max: u32) -> usize {
    let shift = 8 - code.default_log;
    let cost: usize = (0..=max as usize)
        .map(|s| {
            let norm = if code.default[s] != -1 { code.default[s] as u32 } else { 1 };
            (count[s] * INVERSE_LOG[(norm << shift) as usize]) as usize
        })
        .sum();
    cost >> 8
}

/// `ZSTD_fseBitCost`: `count` under the previous block's table, when it
/// codes every symbol counted.
fn repeat_cost(table: &Table, count: &[u32], max: u32) -> usize {
    if table.max_symbol < max {
        return NO_COST;
    }
    let bad = (table.log + 1) << 8;
    let mut cost = 0;
    for s in 0..=max as usize {
        if count[s] == 0 {
            continue;
        }
        let bit_cost = table.bit_cost(s);
        if bit_cost >= bad {
            return NO_COST;
        }
        cost += count[s] as usize * bit_cost as usize;
    }
    cost >> 8
}

/// `ZSTD_NCountCost`: the bytes a new table's description takes.
fn description_cost(count: &[u32], max: u32, total: usize, max_log: u32) -> usize {
    let log = fse::optimal_table_log(max_log, total, max, 2);
    let mut norm = [0i16; SYMBOLS];
    if fse::normalize(&mut norm, log, count, total, max, total >= 2048).is_none() {
        return NO_COST;
    }
    fse::describe(&mut [0u8; DESCRIPTION_BOUND], &norm, max, log).unwrap_or(NO_COST)
}

/// `ZSTD_entropyCost`: `count` at its own entropy, in bits.
fn entropy_cost(count: &[u32], max: u32, total: usize) -> usize {
    let mut cost = 0u32;
    for &c in &count[..=max as usize] {
        let mut norm = (256 * c) as usize / total;
        if c != 0 && norm == 0 {
            norm = 1;
        }
        cost += c * INVERSE_LOG[norm];
    }
    (cost >> 8) as usize
}

/// `ZSTD_selectEncodingType` at lazy and beyond: the cheapest table kind
/// for one code, the repeat mode updated as the C does.
#[allow(clippy::too_many_arguments)]
fn select(
    repeat: &mut Repeat,
    count: &[u32],
    max: u32,
    most_frequent: usize,
    total: usize,
    max_log: u32,
    previous: &Table,
    code: &Code,
    default_allowed: bool,
) -> u8 {
    if most_frequent == total {
        *repeat = Repeat::None;
        return if default_allowed && total <= 2 { BASIC } else { RLE };
    }
    let basic = if default_allowed { default_cost(code, count, max) } else { NO_COST };
    let repeated = if *repeat != Repeat::None { repeat_cost(previous, count, max) } else { NO_COST };
    let compressed = (description_cost(count, max, total, max_log) << 3).wrapping_add(entropy_cost(count, max, total));
    if basic <= repeated && basic <= compressed {
        *repeat = Repeat::None;
        return BASIC;
    }
    if repeated <= compressed {
        return REPEAT;
    }
    *repeat = Repeat::Check;
    COMPRESSED
}

/// `ZSTD_buildCTable`: the table `kind` names laid into `next`, its
/// description (if any) into `out` — the bytes that took.
#[allow(clippy::too_many_arguments)]
fn build(
    out: &mut [u8],
    next: &mut Table,
    kind: u8,
    count: &mut [u32; SYMBOLS],
    max: u32,
    codes: &[u8],
    code: &Code,
    previous: &Table,
) -> Result<usize, Error> {
    match kind {
        RLE => {
            next.run(max as u8);
            *out.first_mut().ok_or(TooSmall)? = codes[0];
            Ok(1)
        }
        REPEAT => {
            next.clone_from(previous);
            Ok(0)
        }
        BASIC => {
            next.build(code.default, code.default.len() as u32 - 1, code.default_log);
            Ok(0)
        }
        _ => {
            let log = fse::optimal_table_log(code.max_log, codes.len(), max, 2);
            // The last code is coded by the first state, for free: its
            // count may come out of the distribution.
            let last = codes[codes.len() - 1] as usize;
            let mut total = codes.len();
            if count[last] > 1 {
                count[last] -= 1;
                total -= 1;
            }
            let mut norm = [0i16; SYMBOLS];
            fse::normalize(&mut norm, log, count, total, max, total >= 2048).ok_or(Error::Failed)?;
            let size = fse::describe(out, &norm, max, log).ok_or(TooSmall)?;
            next.build(&norm, max, log);
            Ok(size)
        }
    }
}

/// `ZSTD_encodeSequences`: the sequences, last first, under the three
/// tables — literal lengths, offsets, match lengths.
fn encode(out: &mut [u8], tables: [&Table; 3], store: &Store) -> Result<usize, TooSmall> {
    let [ll_table, of_table, ml_table] = tables;
    let [ll, of, ml] = &store.codes;
    let sequences = &store.sequences;
    let mut stream = Stream::new(out).ok_or(TooSmall)?;
    let n = sequences.len() - 1;
    let mut ml_state = State::first(ml_table, ml[n] as usize);
    let mut of_state = State::first(of_table, of[n] as usize);
    let mut ll_state = State::first(ll_table, ll[n] as usize);
    stream.add(u64::from(sequences[n].lit_length), u32::from(LL_BITS[ll[n] as usize]));
    stream.add(u64::from(sequences[n].ml_base), u32::from(ML_BITS[ml[n] as usize]));
    stream.add(u64::from(sequences[n].off_base), u32::from(of[n]));
    stream.flush();
    for i in (0..n).rev() {
        let (ll_code, of_code, ml_code) = (ll[i] as usize, of[i] as usize, ml[i] as usize);
        let ll_bits = u32::from(LL_BITS[ll_code]);
        let of_bits = of_code as u32;
        let ml_bits = u32::from(ML_BITS[ml_code]);
        of_state.encode(&mut stream, of_table, of_code);
        ml_state.encode(&mut stream, ml_table, ml_code);
        ll_state.encode(&mut stream, ll_table, ll_code);
        // The C's 64-bit flushes: the three states took at most 33 bits.
        if of_bits + ml_bits + ll_bits >= 64 - 7 - (9 + 9 + 8) {
            stream.flush();
        }
        stream.add(u64::from(sequences[i].lit_length), ll_bits);
        stream.add(u64::from(sequences[i].ml_base), ml_bits);
        if of_bits + ml_bits + ll_bits > 56 {
            stream.flush();
        }
        stream.add(u64::from(sequences[i].off_base), of_bits);
        stream.flush();
    }
    ml_state.close(&mut stream, ml_table);
    of_state.close(&mut stream, of_table);
    ll_state.close(&mut stream, ll_table);
    match stream.close() {
        0 => Err(TooSmall),
        size => Ok(size),
    }
}

/// `ZSTD_entropyCompressSeqStore_internal`.
fn code_block(store: &mut Store, previous: &Entropy, next: &mut Entropy, out: &mut [u8]) -> Result<usize, Error> {
    let count = store.sequences.len();
    let suspect = count == 0 || store.literals.len() / count >= SUSPECT_RATIO;
    let mut op = literals::compress(out, &store.literals, &previous.tree, &mut next.tree, suspect)?;
    if out.len() - op < 4 {
        return Err(TooSmall.into());
    }
    if count < 128 {
        out[op] = count as u8;
        op += 1;
    } else if count < LONG_COUNT {
        out[op] = ((count >> 8) + 0x80) as u8;
        out[op + 1] = count as u8;
        op += 2;
    } else {
        out[op] = 0xFF;
        out[op + 1..op + 3].copy_from_slice(&((count - LONG_COUNT) as u16).to_le_bytes());
        op += 3;
    }
    if count == 0 {
        next.coders.clone_from(&previous.coders);
        return Ok(op);
    }
    let kinds_at = op;
    op += 1;
    to_codes(store);
    let mut kinds = [0u8; 3];
    let mut last_description = 0;
    for (k, code) in [LITERAL_LENGTHS, OFFSETS, MATCH_LENGTHS].iter().enumerate() {
        let codes = &store.codes[k];
        let mut histogram = [0u32; SYMBOLS];
        for &c in codes {
            histogram[c as usize] += 1;
        }
        let mut max = code.max_symbol;
        while histogram[max as usize] == 0 {
            max -= 1;
        }
        let most_frequent = histogram.iter().copied().max().unwrap_or(0) as usize;
        let default_allowed = k != 1 || max <= DEFAULT_MAX_OFFSET;
        let coder = &mut next.coders[k];
        coder.repeat = previous.coders[k].repeat;
        let previous_table = &previous.coders[k].table;
        let kind = select(
            &mut coder.repeat,
            &histogram,
            max,
            most_frequent,
            count,
            code.max_log,
            previous_table,
            code,
            default_allowed,
        );
        let size = build(&mut out[op..], &mut coder.table, kind, &mut histogram, max, codes, code, previous_table)?;
        if kind == COMPRESSED {
            last_description = size;
        }
        op += size;
        kinds[k] = kind;
    }
    out[kinds_at] = (kinds[0] << 6) + (kinds[1] << 4) + (kinds[2] << 2);
    let tables = [&next.coders[0].table, &next.coders[1].table, &next.coders[2].table];
    let bits = encode(&mut out[op..], tables, store)?;
    // zstd 1.3.4 and before misread a description and bitstream under 4
    // bytes: such a block is stored instead.
    if last_description != 0 && last_description + bits < 4 {
        return Ok(0);
    }
    Ok(op + bits)
}

/// `ZSTD_entropyCompressSeqStore`: the coded block, or 0 when it is better
/// stored — it saves too little, or does not fit where the stored block
/// would.
pub(super) fn compress(
    store: &mut Store,
    previous: &Entropy,
    next: &mut Entropy,
    out: &mut [u8],
    block_size: usize,
) -> Result<usize, Error> {
    match code_block(store, previous, next, out) {
        Err(Error::TooSmall) if block_size <= out.len() => Ok(0),
        Err(error) => Err(error),
        Ok(size) if size >= block_size - ((block_size >> 6) + 2) => Ok(0),
        Ok(size) => Ok(size),
    }
}
