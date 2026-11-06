//! `BIT_CStream_t`: an encoder's bitstream, written forward with the first
//! bit lowest so that a decoder reads it back from the end. Huffman's own
//! stream (`HUF_CStream_t`: top-aligned, two registers) lays down the same
//! bytes in another rhythm, so this one writer serves both.

/// `sizeof(size_t)`: the C stores a whole register at its write head, so a
/// stream whose head comes within one register of the end does not fit —
/// whatever it would have written there.
const REGISTER: usize = size_of::<usize>();

pub(super) struct Stream<'a> {
    out: &'a mut [u8],
    /// Whole bytes laid so far: the C's `ptr`, never pulled back to the end
    /// as `BIT_flushBits` does — a stream that crossed it fails at the
    /// close either way.
    head: usize,
    bits: u64,
    count: u32,
}

impl<'a> Stream<'a> {
    /// `BIT_initCStream`: None when `out` cannot hold a register.
    pub(super) fn new(out: &'a mut [u8]) -> Option<Self> {
        (out.len() > REGISTER).then_some(Stream { out, head: 0, bits: 0, count: 0 })
    }

    /// `BIT_addBits`: the low `count` bits of `value`, under 32.
    #[inline(always)]
    pub(super) fn add(&mut self, value: u64, count: u32) {
        self.bits |= (value & ((1 << count) - 1)) << self.count;
        self.count += count;
    }

    /// `BIT_flushBits`: the whole bytes out.
    #[inline(always)]
    pub(super) fn flush(&mut self) {
        let bytes = (self.count >> 3) as usize;
        let room = self.out.len().saturating_sub(self.head);
        if room >= 8 {
            self.out[self.head..self.head + 8].copy_from_slice(&self.bits.to_le_bytes());
        } else if room > 0 {
            self.out[self.head..].copy_from_slice(&self.bits.to_le_bytes()[..room]);
        }
        self.head += bytes;
        self.count &= 7;
        self.bits >>= bytes * 8;
    }

    /// `BIT_closeCStream`: the end mark and the last bits out — the
    /// stream's size, or 0 when it did not fit.
    pub(super) fn close(mut self) -> usize {
        self.add(1, 1);
        self.flush();
        if self.head >= self.out.len() - REGISTER {
            return 0;
        }
        self.head + usize::from(self.count > 0)
    }
}
