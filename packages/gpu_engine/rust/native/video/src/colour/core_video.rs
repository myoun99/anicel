//! Apple's names for the four a movie says of its pictures: Core Video's,
//! which it turns into H.273 code points and back itself
//! (`CV…GetIntegerCodePointForString` and `…GetStringForIntegerCodePoint`)
//! — so Apple keeps no table here; the OS's is the one table, read off a
//! movie by the reader ([`colours_of`]) and named by the writer
//! ([`names_of`]). AVFoundation's colour names are the same strings.

use std::ffi::c_int;

use objc2_core_foundation::{CFBoolean, CFRetained, CFString};
use objc2_core_media::{
    CMFormatDescription, kCMFormatDescriptionExtension_ColorPrimaries, kCMFormatDescriptionExtension_FullRangeVideo,
    kCMFormatDescriptionExtension_TransferFunction, kCMFormatDescriptionExtension_YCbCrMatrix,
};
use objc2_core_video::{
    CVColorPrimariesGetIntegerCodePointForString, CVColorPrimariesGetStringForIntegerCodePoint,
    CVTransferFunctionGetIntegerCodePointForString, CVTransferFunctionGetStringForIntegerCodePoint,
    CVYCbCrMatrixGetIntegerCodePointForString, CVYCbCrMatrixGetStringForIntegerCodePoint,
    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
};

use super::{Colours, UNSPECIFIED};

/// A code point as [`Colours`] holds one: Core Video's 0 — a name it does
/// not know, or none — and anything past a byte are unnamed.
fn code(point: c_int) -> u8 {
    u8::try_from(point).ok().filter(|&point| point != 0).unwrap_or(UNSPECIFIED)
}

/// What a movie's format description says its pictures are — unnamed for
/// each extension it does not carry.
pub fn colours_of(format: &CMFormatDescription) -> Colours {
    // SAFETY (each): reading an extension of a live description by the
    // framework's own key.
    let extension = |key: &CFString| unsafe { format.extension(key) };
    let named = |key: &CFString| extension(key).and_then(|value| value.downcast::<CFString>().ok());
    let full = unsafe { extension(kCMFormatDescriptionExtension_FullRangeVideo) }
        .and_then(|value| value.downcast::<CFBoolean>().ok())
        .map(|full| full.value());
    Colours {
        primaries: code(CVColorPrimariesGetIntegerCodePointForString(
            unsafe { named(kCMFormatDescriptionExtension_ColorPrimaries) }.as_deref(),
        )),
        transfer: code(CVTransferFunctionGetIntegerCodePointForString(
            unsafe { named(kCMFormatDescriptionExtension_TransferFunction) }.as_deref(),
        )),
        matrix: code(CVYCbCrMatrixGetIntegerCodePointForString(
            unsafe { named(kCMFormatDescriptionExtension_YCbCrMatrix) }.as_deref(),
        )),
        range: full.map_or(UNSPECIFIED, u8::from),
    }
}

/// Core Video's names for `colours`' primaries, transfer and matrix — none
/// for each it leaves unnamed, or the OS has no name for.
pub fn names_of(colours: Colours) -> [Option<CFRetained<CFString>>; 3] {
    let point = |code: u8| (code != UNSPECIFIED).then_some(c_int::from(code));
    [
        point(colours.primaries).and_then(|code| CVColorPrimariesGetStringForIntegerCodePoint(code)),
        point(colours.transfer).and_then(|code| CVTransferFunctionGetStringForIntegerCodePoint(code)),
        point(colours.matrix).and_then(|code| CVYCbCrMatrixGetStringForIntegerCodePoint(code)),
    ]
}

/// The two-plane 4:2:0 a movie's pictures are in at `range`: full range's
/// where it says full, video range's otherwise — what an H.264 stream is
/// when it says nothing. ⛔Asked in the other range, the reader converts.
pub fn biplanar_of(range: u8) -> u32 {
    let (full, video) = (kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
    if range == 1 { full } else { video }
}
