//! Linux (and anything else): no OS encoder story yet — the ffmpeg path
//! remains, chosen by the caller because `supported()` said so.

use super::{Job, set_error};

pub const SUPPORTED: bool = false;

pub fn probe(_container: i32, _codec: i32) -> bool {
    false
}

pub fn open(_job: &Job) -> bool {
    set_error("video export: no OS encoder on this platform");
    false
}

/// # Safety
/// Nothing is read.
pub unsafe fn write_frame(_rgba: *const u8) -> bool {
    false
}

/// # Safety
/// Nothing is read.
pub unsafe fn write_audio(_interleaved: *const i16, _frames: i32) -> bool {
    false
}

pub fn finish() -> bool {
    false
}

pub fn abort() {}
