//! zstd's backward bit reader (`BIT_DStream_t`, bitstream.h): a stream is
//! read from its last byte towards its first, the highest bit first, and
//! its last byte carries a 1 above the stream's final bit.
//!
//! The reader is the C's to the bit, overreads included — a corrupt stream
//! reads garbage where the C's does, and stops being "at its end" for the
//! same reason — because whether a damaged frame is refused is the C's
//! answer the Rust must give.
//!
//! The container is 64 bits on every target, as the C's is on 64-bit ones;
//! the C's 32-bit build reads with a 32-bit container, which only changes
//! where a corrupt stream gives up.

/// What a reload found (`BIT_DStream_status`), in the C's order.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
pub(crate) enum Status {
    /// At least 57 bits are in the container.
    Unfinished,
    /// The stream's first byte is loaded, and bits remain.
    EndOfBuffer,
    /// Every bit is consumed, exactly.
    Completed,
    /// More bits were consumed than the stream has.
    Overflow,
}

const CONTAINER_BITS: u32 = 64;

pub(crate) struct Bits<'a> {
    /// The bytes the reader may load from: the stream, and for the Huffman
    /// fast decoder's hand-over everything before it down to `start`.
    buf: &'a [u8],
    /// The lowest byte the reader may load (the C's `start`).
    start: usize,
    /// Where the loaded 8 bytes begin (the C's `ptr`).
    ptr: usize,
    pub(crate) container: u64,
    pub(crate) consumed: u32,
}

fn le64(buf: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(buf[at..at + 8].try_into().expect("8 bytes"))
}

/// The index of the highest set bit (`ZSTD_highbit32`); `value` is not 0.
pub(crate) fn highbit(value: u32) -> u32 {
    31 - value.leading_zeros()
}

impl<'a> Bits<'a> {
    /// `BIT_initDStream` over all of `stream`: None when it is empty or its
    /// last byte holds no end mark.
    pub(crate) fn new(stream: &'a [u8]) -> Option<Self> {
        let size = stream.len();
        let last = *stream.last()?;
        if last == 0 {
            return None;
        }
        let consumed = 8 - highbit(u32::from(last));
        Some(if size >= 8 {
            Bits { buf: stream, start: 0, ptr: size - 8, container: le64(stream, size - 8), consumed }
        } else {
            let container = stream.iter().rev().fold(0, |value, &byte| (value << 8) | u64::from(byte));
            Bits { buf: stream, start: 0, ptr: 0, container, consumed: consumed + (8 - size as u32) * 8 }
        })
    }

    /// The reader the Huffman fast decoder hands a stream over in
    /// (`HUF_initRemainingDStream`): loaded at `ptr`, with `consumed` bits
    /// gone, free to reload down to the start of `buf`.
    pub(crate) fn resumed(buf: &'a [u8], ptr: usize, consumed: u32) -> Self {
        Bits { buf, start: 0, ptr, container: le64(buf, ptr), consumed }
    }

    /// The next `count` bits, not consumed (`BIT_lookBits`).
    #[inline(always)]
    pub(crate) fn look(&self, count: u32) -> u64 {
        let start = CONTAINER_BITS.wrapping_sub(self.consumed).wrapping_sub(count) & 63;
        (self.container >> start) & ((1u64 << count) - 1)
    }

    /// `BIT_lookBitsFast`: `count` is at least 1.
    #[inline(always)]
    pub(crate) fn look_fast(&self, count: u32) -> u64 {
        (self.container << (self.consumed & 63)) >> ((CONTAINER_BITS - count) & 63)
    }

    #[inline(always)]
    pub(crate) fn skip(&mut self, count: u32) {
        self.consumed += count;
    }

    #[inline(always)]
    pub(crate) fn read(&mut self, count: u32) -> u64 {
        let value = self.look(count);
        self.skip(count);
        value
    }

    /// `BIT_readBitsFast`: `count` is at least 1.
    #[inline(always)]
    pub(crate) fn read_fast(&mut self, count: u32) -> u64 {
        let value = self.look_fast(count);
        self.skip(count);
        value
    }

    #[inline(always)]
    fn reload_whole_bytes(&mut self) -> Status {
        self.ptr -= (self.consumed >> 3) as usize;
        self.consumed &= 7;
        self.container = le64(self.buf, self.ptr);
        Status::Unfinished
    }

    /// `BIT_reloadDStream`: refills the container without reading before
    /// `start`, and says what is left.
    #[inline(always)]
    pub(crate) fn reload(&mut self) -> Status {
        // Once overflowed, a stream stays so: nothing here lowers `consumed`.
        if self.consumed > CONTAINER_BITS {
            return Status::Overflow;
        }
        if self.ptr >= self.start + 8 {
            return self.reload_whole_bytes();
        }
        if self.ptr == self.start {
            return if self.consumed < CONTAINER_BITS { Status::EndOfBuffer } else { Status::Completed };
        }
        let mut bytes = (self.consumed >> 3) as usize;
        let mut status = Status::Unfinished;
        if bytes > self.ptr - self.start {
            bytes = self.ptr - self.start;
            status = Status::EndOfBuffer;
        }
        self.ptr -= bytes;
        self.consumed -= bytes as u32 * 8;
        self.container = le64(self.buf, self.ptr);
        status
    }

    /// `BIT_reloadDStreamFast`: Overflow once fewer than 8 bytes lie below
    /// the loaded ones; `consumed` is at most 64.
    #[inline(always)]
    pub(crate) fn reload_fast(&mut self) -> Status {
        if self.ptr < self.start + 8 {
            return Status::Overflow;
        }
        self.reload_whole_bytes()
    }

    /// Whether every bit was consumed, exactly (`BIT_endOfDStream`).
    pub(crate) fn at_end(&self) -> bool {
        self.ptr == self.start && self.consumed == CONTAINER_BITS
    }
}
