//! Media Foundation's names for the four a movie says of its pictures, each
//! against its H.273 code point ([`Colours`]): ONE TABLE AN ATTRIBUTE, read
//! off a movie by the reader ([`colours_of`]) and named by the writer
//! ([`name`]), so what the one understands the other says.

use windows::Win32::Media::MediaFoundation::*;
use windows::core::GUID;

use super::{Colours, code_of, name_of};

const PRIMARIES: [(MFVideoPrimaries, u8); 10] = [
    (MFVideoPrimaries_BT709, 1),
    (MFVideoPrimaries_BT470_2_SysM, 4),
    (MFVideoPrimaries_BT470_2_SysBG, 5),
    (MFVideoPrimaries_SMPTE170M, 6),
    (MFVideoPrimaries_SMPTE240M, 7),
    (MFVideoPrimaries_BT2020, 9),
    (MFVideoPrimaries_XYZ, 10),
    (MFVideoPrimaries_DCI_P3, 11),
    (MFVideoPrimaries_EBU3213, 22),
    // ⚠️After SMPTE170M, so 6 is written SMPTE170M: written SMPTE_C, Media
    // Foundation's muxer puts 8 — film — in the file (`export/windows.rs`,
    // `video_type`). Read, it is the same primaries.
    (MFVideoPrimaries_SMPTE_C, 6),
];

const TRANSFERS: [(MFVideoTransferFunction, u8); 12] = [
    (MFVideoTransFunc_709, 1),
    (MFVideoTransFunc_22, 4),
    (MFVideoTransFunc_28, 5),
    (MFVideoTransFunc_240M, 7),
    (MFVideoTransFunc_10, 8),
    (MFVideoTransFunc_Log_100, 9),
    (MFVideoTransFunc_Log_316, 10),
    (MFVideoTransFunc_sRGB, 13),
    (MFVideoTransFunc_2020, 14),
    (MFVideoTransFunc_2084, 16),
    (MFVideoTransFunc_HLG, 18),
    (MFVideoTransFunc_2020_const, 14),
];

const MATRICES: [(MFVideoTransferMatrix, u8); 5] = [
    (MFVideoTransferMatrix_BT709, 1),
    (MFVideoTransferMatrix_BT601, 6),
    (MFVideoTransferMatrix_SMPTE240M, 7),
    (MFVideoTransferMatrix_BT2020_10, 9),
    // BT.470 System B/G's matrix is BT.601's, coefficient for coefficient.
    (MFVideoTransferMatrix_BT601, 5),
];

const RANGES: [(MFNominalRange, u8); 2] = [(MFNominalRange_16_235, 0), (MFNominalRange_0_255, 1)];

/// What `media_type` says its pictures are — [`super::UNSPECIFIED`] for
/// each attribute it does not carry, or carries with a value no table
/// names.
pub fn colours_of(media_type: &IMFMediaType) -> Colours {
    // SAFETY: reading an attribute of a live type.
    let read = |key: &GUID| unsafe { media_type.GetUINT32(key) }.ok().map(|value| value as i32);
    Colours {
        primaries: code_of(&PRIMARIES, read(&MF_MT_VIDEO_PRIMARIES).map(MFVideoPrimaries)),
        transfer: code_of(&TRANSFERS, read(&MF_MT_TRANSFER_FUNCTION).map(MFVideoTransferFunction)),
        matrix: code_of(&MATRICES, read(&MF_MT_YUV_MATRIX).map(MFVideoTransferMatrix)),
        range: code_of(&RANGES, read(&MF_MT_VIDEO_NOMINAL_RANGE).map(MFNominalRange)),
    }
}

/// `colours` named on `media_type`: each it has a name for, and nothing for
/// the rest — a movie that names nothing makes a type that names nothing.
pub fn name(media_type: &IMFMediaType, colours: Colours) {
    let named = [
        (&MF_MT_VIDEO_PRIMARIES, name_of(&PRIMARIES, colours.primaries).map(|name| name.0)),
        (&MF_MT_TRANSFER_FUNCTION, name_of(&TRANSFERS, colours.transfer).map(|name| name.0)),
        (&MF_MT_YUV_MATRIX, name_of(&MATRICES, colours.matrix).map(|name| name.0)),
        (&MF_MT_VIDEO_NOMINAL_RANGE, name_of(&RANGES, colours.range).map(|name| name.0)),
    ];
    for (key, value) in named {
        if let Some(value) = value {
            // SAFETY: setting an attribute on a type of our own. The C set
            // these unchecked: a type that would not take them is turned
            // away by the writer it is offered to.
            let _ = unsafe { media_type.SetUINT32(key, value as u32) };
        }
    }
}
