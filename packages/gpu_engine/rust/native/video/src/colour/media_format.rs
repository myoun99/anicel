//! MediaFormat's names for the four a movie says of its pictures, each
//! against its H.273 code point ([`Colours`]): ONE TABLE AN ATTRIBUTE, read
//! off a movie by the reader ([`colours_of`]) and named by the writer
//! ([`name`]). The NDK keys take them as plain numbers (MediaFormat's
//! COLOR_STANDARD_*, COLOR_RANGE_* and COLOR_TRANSFER_*; no NDK header
//! carries the values).
//!
//! ⚠️A STANDARD IS TWO OF THE FOUR: MediaFormat names the primaries and the
//! matrix together — BT.601 NTSC is SMPTE C's primaries with BT.601's
//! matrix, the app's law. A standard is read as both, and named only where
//! both are one standard's: a movie naming one and not the other, or two
//! that no standard pairs, names no standard here rather than one it did
//! not say.

use ndk_sys::{
    AMEDIAFORMAT_KEY_COLOR_RANGE, AMEDIAFORMAT_KEY_COLOR_STANDARD, AMEDIAFORMAT_KEY_COLOR_TRANSFER, AMediaFormat,
    AMediaFormat_getInt32, AMediaFormat_setInt32,
};

use super::{Colours, code_of, name_of};

/// COLOR_STANDARD_BT709, _BT601_PAL, _BT601_NTSC and _BT2020, each the
/// code point its primaries and its matrix both are.
const STANDARDS: [(i32, u8); 4] = [(1, 1), (2, 5), (4, 6), (6, 9)];

/// COLOR_RANGE_LIMITED and _FULL.
const RANGES: [(i32, u8); 2] = [(2, 0), (1, 1)];

/// COLOR_TRANSFER_SDR_VIDEO — BT.709's curve, and BT.601's and BT.2020's,
/// which are the same curve — _LINEAR, _ST2084 and _HLG.
const TRANSFERS: [(i32, u8); 7] = [(3, 1), (3, 6), (3, 14), (3, 15), (1, 8), (6, 16), (7, 18)];

/// What `format` says its pictures are — unnamed for each key it does not
/// carry, or carries with a value no table names.
///
/// # Safety
/// `format` is a live format.
pub unsafe fn colours_of(format: *mut AMediaFormat) -> Colours {
    // SAFETY: the caller's contract; the keys are the NDK's own statics.
    let read = |key| {
        let mut value = 0;
        unsafe { AMediaFormat_getInt32(format, key, &mut value) }.then_some(value)
    };
    let standard = read(unsafe { AMEDIAFORMAT_KEY_COLOR_STANDARD });
    Colours {
        primaries: code_of(&STANDARDS, standard),
        transfer: code_of(&TRANSFERS, read(unsafe { AMEDIAFORMAT_KEY_COLOR_TRANSFER })),
        matrix: code_of(&STANDARDS, standard),
        range: code_of(&RANGES, read(unsafe { AMEDIAFORMAT_KEY_COLOR_RANGE })),
    }
}

/// `colours` named on `format`: each it has a name for, and nothing for
/// the rest — the standard only where the primaries and the matrix are
/// both its own.
///
/// # Safety
/// `format` is a live format of our own.
pub unsafe fn name(format: *mut AMediaFormat, colours: Colours) {
    let standard = name_of(&STANDARDS, colours.primaries).filter(|&standard| {
        name_of(&STANDARDS, colours.matrix) == Some(standard)
    });
    // SAFETY: the caller's contract; the keys are the NDK's own statics.
    let named = unsafe {
        [
            (AMEDIAFORMAT_KEY_COLOR_STANDARD, standard),
            (AMEDIAFORMAT_KEY_COLOR_RANGE, name_of(&RANGES, colours.range)),
            (AMEDIAFORMAT_KEY_COLOR_TRANSFER, name_of(&TRANSFERS, colours.transfer)),
        ]
    };
    for (key, value) in named {
        if let Some(value) = value {
            // SAFETY: as above.
            unsafe { AMediaFormat_setInt32(format, key, value) };
        }
    }
}
