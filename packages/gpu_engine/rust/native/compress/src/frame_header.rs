//! A zstd frame's header, read as the engine's zstd (1.5.6,
//! `ZSTD_getFrameHeader`) reads it — what it says of the content size is
//! Dart's to size a buffer by, so it is the C's to the edge cases, not
//! another reader's.

/// The size is not in the header.
pub const UNKNOWN: u64 = u64::MAX;
/// The bytes are not a frame header, or not all of one.
pub const ERROR: u64 = u64::MAX - 1;

const MAGIC: u32 = 0xFD2F_B528;
pub(crate) const SKIPPABLE_START: u32 = 0x184D_2A50;
pub(crate) const SKIPPABLE_MASK: u32 = 0xFFFF_FFF0;
/// Magic number and frame header descriptor.
pub(crate) const PREFIX: usize = 5;
pub(crate) const SKIPPABLE_HEADER: usize = 8;
const WINDOW_LOG_MIN: u32 = 10;
const WINDOW_LOG_MAX: u32 = 31;
const DICT_ID_BYTES: [usize; 4] = [0, 1, 2, 4];
const CONTENT_SIZE_BYTES: [usize; 4] = [0, 2, 4, 8];

pub(crate) fn le(bytes: &[u8]) -> u64 {
    bytes.iter().rev().fold(0, |value, &byte| (value << 8) | u64::from(byte))
}

/// What a zstd frame's header says.
pub(crate) struct Header {
    pub(crate) content_size: u64,
    pub(crate) window_size: u64,
    pub(crate) dict_id: u32,
    pub(crate) checksum: bool,
}

/// The header's length, from its descriptor byte
/// (`ZSTD_frameHeaderSize_internal`).
pub(crate) fn size(descriptor: u8) -> usize {
    let single_segment = descriptor >> 5 & 1 == 1;
    let size_id = usize::from(descriptor >> 6);
    PREFIX
        + usize::from(!single_segment)
        + DICT_ID_BYTES[usize::from(descriptor & 3)]
        + CONTENT_SIZE_BYTES[size_id]
        + usize::from(single_segment && size_id == 0)
}

/// The header of the zstd frame `src` begins with: None when it does not
/// begin with one, or does not hold all of it.
pub(crate) fn read(src: &[u8]) -> Option<Header> {
    if src.len() < PREFIX || le(&src[..4]) as u32 != MAGIC {
        return None;
    }
    let descriptor = src[4];
    let size = size(descriptor);
    // Reserved bits must be zero.
    if src.len() < size || descriptor & 0x08 != 0 {
        return None;
    }
    let single_segment = descriptor >> 5 & 1 == 1;
    let mut at = PREFIX;
    let mut window_size = 0;
    if !single_segment {
        let window = src[at];
        let log = u32::from(window >> 3) + WINDOW_LOG_MIN;
        if log > WINDOW_LOG_MAX {
            return None;
        }
        window_size = 1u64 << log;
        window_size += (window_size >> 3) * u64::from(window & 7);
        at += 1;
    }
    let dict_bytes = DICT_ID_BYTES[usize::from(descriptor & 3)];
    let dict_id = le(&src[at..at + dict_bytes]) as u32;
    at += dict_bytes;
    let content_size = match usize::from(descriptor >> 6) {
        0 if single_segment => u64::from(src[at]),
        0 => UNKNOWN,
        1 => le(&src[at..at + 2]) + 256,
        size_id => le(&src[at..at + CONTENT_SIZE_BYTES[size_id]]),
    };
    if single_segment {
        window_size = content_size;
    }
    Some(Header { content_size, window_size, dict_id, checksum: descriptor >> 2 & 1 == 1 })
}

pub(crate) fn is_skippable(magic: u32) -> bool {
    magic & SKIPPABLE_MASK == SKIPPABLE_START
}

/// The content size `src`'s first frame states (`ZSTD_getFrameContentSize`)
/// — 0 for a skippable frame, [`UNKNOWN`] when it states none, [`ERROR`]
/// when `src` does not hold a whole frame header.
pub fn content_size(src: &[u8]) -> u64 {
    if src.len() < PREFIX {
        return ERROR;
    }
    let magic = le(&src[..4]) as u32;
    if magic != MAGIC {
        return if is_skippable(magic) && src.len() >= SKIPPABLE_HEADER { 0 } else { ERROR };
    }
    read(src).map_or(ERROR, |header| header.content_size)
}
