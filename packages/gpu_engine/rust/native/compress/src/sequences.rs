//! A compressed block's sequences: the three FSE tables (literal lengths,
//! offsets, match lengths) its header describes, and the sequences they
//! decode to — each "copy this many literals, then this many bytes from
//! this far back".

use std::sync::OnceLock;

use crate::Corrupt;
use crate::bits::{Bits, highbit};
use crate::fse;

pub(crate) const LL_BASE: [u32; 36] = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 0x80, 0x100, 0x200,
    0x400, 0x800, 0x1000, 0x2000, 0x4000, 0x8000, 0x10000,
];
pub(crate) const LL_BITS: [u8; 36] = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
];
pub(crate) const ML_BASE: [u32; 53] = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
    33, 34, 35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 0x83, 0x103, 0x203, 0x403, 0x803, 0x1003, 0x2003, 0x4003,
    0x8003, 0x10003,
];
pub(crate) const ML_BITS: [u8; 53] = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2,
    3, 3, 4, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
];
/// Offset code k reads k bits over a base of 2^k − 3: the values ≤ 3 are
/// the repeat codes.
const OF_BASE: [u32; 32] = {
    let mut base = [0u32; 32];
    let mut k = 1;
    while k < 32 {
        base[k] = if k == 1 { 1 } else { (1 << k) - 3 };
        k += 1;
    }
    base
};
const OF_BITS: [u8; 32] = {
    let mut bits = [0u8; 32];
    let mut k = 0;
    while k < 32 {
        bits[k] = k as u8;
        k += 1;
    }
    bits
};

const LL_DEFAULT: [i16; 36] = [
    4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 1, 1, 1, 1, 1, -1, -1, -1, -1,
];
const ML_DEFAULT: [i16; 53] = [
    1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1, -1, -1,
];
const OF_DEFAULT: [i16; 29] = [1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1];

/// The three codes: their largest symbol, largest table log, value bases,
/// extra bits, and default distribution (log 6, 5, 6).
pub(crate) struct Code {
    pub(crate) max_symbol: u32,
    pub(crate) max_log: u32,
    base: &'static [u32],
    bits: &'static [u8],
    pub(crate) default: &'static [i16],
    pub(crate) default_log: u32,
}

pub(crate) const LITERAL_LENGTHS: Code =
    Code { max_symbol: 35, max_log: 9, base: &LL_BASE, bits: &LL_BITS, default: &LL_DEFAULT, default_log: 6 };
pub(crate) const OFFSETS: Code =
    Code { max_symbol: 31, max_log: 8, base: &OF_BASE, bits: &OF_BITS, default: &OF_DEFAULT, default_log: 5 };
pub(crate) const MATCH_LENGTHS: Code =
    Code { max_symbol: 52, max_log: 9, base: &ML_BASE, bits: &ML_BITS, default: &ML_DEFAULT, default_log: 6 };

/// One cell of a sequence table (`ZSTD_seqSymbol`).
#[derive(Clone, Copy, Default, PartialEq, Eq, Debug)]
pub(crate) struct Cell {
    pub(crate) next_state: u16,
    pub(crate) extra_bits: u8,
    pub(crate) nb_bits: u8,
    pub(crate) base: u32,
}

/// Cells of the largest table (`MaxFSELog`): every table is held at this
/// size, so a state — always under its table's own size — indexes it
/// unchecked.
pub(crate) const CELLS: usize = 1 << 9;

#[derive(Clone)]
pub(crate) struct Table {
    pub(crate) log: u32,
    pub(crate) cells: Box<[Cell; CELLS]>,
}

/// `ZSTD_buildFSETable`: the counts were read whole, so they fill it.
fn build(counts: &[i16], log: u32, code: &Code) -> Table {
    let size = 1u32 << log;
    let mut cells = Box::new([Cell::default(); CELLS]);
    fse::spread(counts, log, |at, symbol, state| {
        let nb_bits = log - highbit(state);
        cells[at] = Cell {
            next_state: ((state << nb_bits) - size) as u16,
            extra_bits: code.bits[symbol],
            nb_bits: nb_bits as u8,
            base: code.base[symbol],
        };
    });
    Table { log, cells }
}

/// The predefined tables (`LL/OF/ML_defaultDTable`), built once.
pub(crate) fn defaults() -> &'static [Table; 3] {
    static DEFAULTS: OnceLock<[Table; 3]> = OnceLock::new();
    DEFAULTS.get_or_init(|| {
        [LITERAL_LENGTHS, OFFSETS, MATCH_LENGTHS].map(|code| build(code.default, code.default_log, &code))
    })
}

/// Which table a block's sequences use, for each of the three codes; a
/// block may keep the previous block's.
#[derive(Clone)]
pub(crate) enum Choice {
    Default,
    Own(Table),
}

/// What a frame keeps between its blocks for its sequences.
pub(crate) struct Entropy {
    pub(crate) tables: [Choice; 3],
    /// A block has decoded sequences: its tables may be repeated.
    pub(crate) repeatable: bool,
    pub(crate) repeats: [u32; 3],
}

impl Entropy {
    pub(crate) fn new() -> Self {
        Entropy { tables: [Choice::Default, Choice::Default, Choice::Default], repeatable: false, repeats: [1, 4, 8] }
    }
}

pub(crate) const BASIC: u8 = 0;
pub(crate) const RLE: u8 = 1;
pub(crate) const COMPRESSED: u8 = 2;

/// `ZSTD_buildSeqTable`: the bytes the description took.
fn read_table(choice: &mut Choice, kind: u8, code: &Code, src: &[u8], repeatable: bool) -> Result<usize, Corrupt> {
    match kind {
        RLE => {
            let symbol = *src.first().ok_or(Corrupt)?;
            if u32::from(symbol) > code.max_symbol {
                return Err(Corrupt);
            }
            let mut cells = Box::new([Cell::default(); CELLS]);
            cells[0] =
                Cell { next_state: 0, extra_bits: code.bits[symbol as usize], nb_bits: 0, base: code.base[symbol as usize] };
            *choice = Choice::Own(Table { log: 0, cells });
            Ok(1)
        }
        BASIC => {
            *choice = Choice::Default;
            Ok(0)
        }
        COMPRESSED => {
            let mut counts = [0i16; 53];
            let mut max_symbol = code.max_symbol;
            let mut log = 0;
            let size = fse::read_counts(&mut counts, &mut max_symbol, &mut log, src)?;
            if log > code.max_log {
                return Err(Corrupt);
            }
            *choice = Choice::Own(build(&counts[..=max_symbol as usize], log, code));
            Ok(size)
        }
        _ => {
            if repeatable { Ok(0) } else { Err(Corrupt) }
        }
    }
}

/// The sequences section's header (`ZSTD_decodeSeqHeaders`): how many
/// sequences, and the bytes the header took.
pub(crate) fn read_header(entropy: &mut Entropy, src: &[u8]) -> Result<(usize, usize), Corrupt> {
    let first = usize::from(*src.first().ok_or(Corrupt)?);
    let (count, mut at) = if first < 0x80 {
        (first, 1)
    } else if first == 0xFF {
        if src.len() < 3 {
            return Err(Corrupt);
        }
        (usize::from(u16::from_le_bytes([src[1], src[2]])) + 0x7F00, 3)
    } else {
        let second = usize::from(*src.get(1).ok_or(Corrupt)?);
        (((first - 0x80) << 8) + second, 2)
    };
    if count == 0 {
        // No sequences: the section ends here.
        return if at == src.len() { Ok((0, at)) } else { Err(Corrupt) };
    }
    let kinds = *src.get(at).ok_or(Corrupt)?;
    // The last field, Reserved, must be zero.
    if kinds & 3 != 0 {
        return Err(Corrupt);
    }
    at += 1;
    for (k, code) in [LITERAL_LENGTHS, OFFSETS, MATCH_LENGTHS].iter().enumerate() {
        let kind = (kinds >> (6 - 2 * k)) & 3;
        at += read_table(&mut entropy.tables[k], kind, code, &src[at..], entropy.repeatable)?;
    }
    Ok((count, at))
}

/// A decoded sequence.
pub(crate) struct Sequence {
    pub(crate) literals: usize,
    pub(crate) matched: usize,
    pub(crate) offset: usize,
}

/// The three states walking their tables over one bitstream
/// (`seqState_t`), with the repeat offsets.
pub(crate) struct Decoder<'a> {
    bits: Bits<'a>,
    tables: [&'a Table; 3],
    states: [usize; 3],
    pub(crate) repeats: [usize; 3],
}

impl<'a> Decoder<'a> {
    /// `ZSTD_initFseState` ×3 in the C's order: literal lengths, offsets,
    /// match lengths.
    pub(crate) fn new(src: &'a [u8], entropy: &'a Entropy) -> Result<Self, Corrupt> {
        let mut bits = Bits::new(src).ok_or(Corrupt)?;
        let defaults = defaults();
        let tables = [0, 1, 2].map(|k| match &entropy.tables[k] {
            Choice::Default => &defaults[k],
            Choice::Own(table) => table,
        });
        let mut states = [0; 3];
        for k in 0..3 {
            states[k] = bits.read(tables[k].log) as usize;
            bits.reload();
        }
        Ok(Decoder { bits, tables, states, repeats: entropy.repeats.map(|offset| offset as usize) })
    }

    /// `ZSTD_decodeSequence` (64-bit): the offset first, then the match
    /// length, then the literal length; the states move on unless it is
    /// the last.
    #[inline(always)]
    pub(crate) fn next(&mut self, last: bool) -> Sequence {
        let [ll, of, ml] = [0, 1, 2].map(|k| self.tables[k].cells[self.states[k] & (CELLS - 1)]);
        let mut sequence = Sequence { literals: ll.base as usize, matched: ml.base as usize, offset: 0 };
        let total_bits = u32::from(ll.extra_bits) + u32::from(ml.extra_bits) + u32::from(of.extra_bits);
        let repeats = &mut self.repeats;
        if of.extra_bits > 1 {
            let offset = of.base as usize + self.bits.read_fast(u32::from(of.extra_bits)) as usize;
            *repeats = [offset, repeats[0], repeats[1]];
            sequence.offset = offset;
        } else {
            let no_literals = usize::from(ll.base == 0);
            if of.extra_bits == 0 {
                let offset = repeats[no_literals];
                repeats[1] = repeats[1 - no_literals];
                repeats[0] = offset;
                sequence.offset = offset;
            } else {
                let code = of.base as usize + no_literals + self.bits.read_fast(1) as usize;
                let mut offset = if code == 3 { repeats[0].wrapping_sub(1) } else { repeats[code] };
                // 0 is not an offset: corrupt input is pushed out of range.
                offset = offset.wrapping_sub(usize::from(offset == 0));
                if code != 1 {
                    repeats[2] = repeats[1];
                }
                repeats[1] = repeats[0];
                repeats[0] = offset;
                sequence.offset = offset;
            }
        }
        if ml.extra_bits > 0 {
            sequence.matched += self.bits.read_fast(u32::from(ml.extra_bits)) as usize;
        }
        // 57 bits after a reload, minus the 26 the state updates may take.
        if total_bits >= 57 - (9 + 9 + 8) {
            self.bits.reload();
        }
        if ll.extra_bits > 0 {
            sequence.literals += self.bits.read_fast(u32::from(ll.extra_bits)) as usize;
        }
        if !last {
            for (k, cell) in [(0, ll), (2, ml), (1, of)] {
                self.states[k] = usize::from(cell.next_state) + self.bits.read(u32::from(cell.nb_bits)) as usize;
            }
            self.bits.reload();
        }
        sequence
    }

    /// The bitstream ended exactly where the sequences did.
    pub(crate) fn finished(&self) -> bool {
        self.bits.at_end()
    }
}
