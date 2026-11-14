//! The colour law's reading side, by hand: no decode reaches it on Windows
//! (only the Android reader calls it), so its answers are pinned here — the
//! C test's cases and the values the BT.601 integer formula gives, worked
//! out on paper. The writing side's are the GPU pass's own
//! (`gpu_engine` `kernels/export/tests.rs`). ↩️The law was the engine's
//! `qa_yuv601.h` and the cases `qa_video_decode_law_test.c`'s, until the
//! connection round deleted them (connection-round-checklist H,
//! 2026-11-08); the writing side was pinned here too while it was
//! `from_rgba` (till 2026-11-15).

use super::{Decoded, UNSPECIFIED, code_of, name_of, nv12_bytes, nv12_of, to_rgba};

/// The C test's frame: 4×4 in rows of 8, the chroma 6 rows down, every
/// unused byte 0xAA. The top chroma row is RED (Y 81, Cb 90, Cr 240), the
/// bottom one neutral.
fn red_over_grey(semi: bool) -> Vec<u8> {
    let (stride, slice) = (8, 6);
    let mut frame = vec![0xAA; stride * slice + if semi { stride * 3 } else { (stride / 2) * 3 * 2 }];
    for y in 0..4 {
        frame[y * stride..y * stride + 4].fill(81);
    }
    let base = stride * slice;
    for cx in 0..2 {
        if semi {
            frame[base + cx * 2..][..2].copy_from_slice(&[90, 240]);
            frame[base + stride + cx * 2..][..2].copy_from_slice(&[128, 128]);
        } else {
            let v = base + (stride / 2) * (slice / 2);
            (frame[base + cx], frame[v + cx]) = (90, 240);
            (frame[base + stride / 2 + cx], frame[v + stride / 2 + cx]) = (128, 128);
        }
    }
    frame
}

// The C test's: both strides walked (the furthest pixel lands in the
// padding if stride is read as width, and turns red if the chroma rows are
// confused), and NV12 is the same picture as I420.
#[test]
fn a_frame_reads_back_through_both_strides() {
    let mut planar = [0u8; 4 * 4 * 4];
    assert!(to_rgba(&red_over_grey(false), 4, 4, 8, 6, false, &mut planar));
    assert_eq!(planar[..4], [255, 0, 0, 255], "red is red, and opaque");
    let last = (3 * 4 + 3) * 4;
    assert_eq!(planar[last..last + 4], [76, 76, 76, 255], "the bottom half is grey, not red");
    let mut semi = [0u8; 4 * 4 * 4];
    assert!(to_rgba(&red_over_grey(true), 4, 4, 8, 6, true, &mut semi));
    assert_eq!(semi, planar, "NV12 and I420 are the same picture");
}

// ⚠️Short of its own planes, refused — not read past, which here is a panic
// and across the FFI the app gone. A byte short at the chroma's end in each
// layout; at the luma's, where a slice short of the picture puts the
// chroma first; and an output short of the picture.
#[test]
fn a_frame_short_of_its_own_planes_is_refused() {
    for (semi, needed) in [(false, 66), (true, 60)] {
        let frame = red_over_grey(semi);
        let mut rgba = [0u8; 4 * 4 * 4];
        assert!(to_rgba(&frame[..needed], 4, 4, 8, 6, semi, &mut rgba), "semi {semi}: to its last byte read");
        let mut untouched = [7u8; 4 * 4 * 4];
        assert!(!to_rgba(&frame[..needed - 1], 4, 4, 8, 6, semi, &mut untouched), "semi {semi}: a byte short");
        assert!(untouched.iter().all(|&byte| byte == 7), "semi {semi}: and nothing written");
    }
    let luma = [16u8; 4];
    let mut rgba = [0u8; 2 * 2 * 4];
    assert!(to_rgba(&luma, 2, 2, 2, 0, true, &mut rgba), "the luma's last byte is the last read");
    assert!(!to_rgba(&luma[..3], 2, 2, 2, 0, true, &mut rgba), "a byte short of the luma");
    assert!(!to_rgba(&luma, 2, 2, 2, 0, true, &mut rgba[..15]), "an output short of the picture");
}

// Limited range: 16 is black and 235 white — a converter written for full
// range answers 0 and 255 to other inputs. And colours off every axis: the
// last is one where each coefficient, one off, moves an answer (a mutant
// run found the middle one let three of them through).
#[test]
fn studio_values_become_their_colour() {
    for ([luma, cb, cr], want) in [
        ([16, 128, 128], [0, 0, 0]),
        ([235, 128, 128], [255, 255, 255]),
        ([123, 91, 175], [200, 101, 50]),
        ([45, 181, 141], [55, 2, 141]),
    ] {
        let frame = [luma, luma, luma, luma, cb, cr];
        let mut rgba = [0u8; 2 * 2 * 4];
        assert!(to_rgba(&frame, 2, 2, 2, 2, true, &mut rgba), "six bytes are the whole of it");
        assert_eq!(rgba[..3], want, "Y {luma} Cb {cb} Cr {cr}");
        assert!(rgba.chunks(4).all(|pixel| pixel == &rgba[..4]), "a flat frame is flat");
    }
}

// A decoder's 4:2:0 laid as NV12 with no sum: the C test's frame, both
// layouts, its rows wider than the picture and its chroma rows further
// down — the bytes as they are, the chroma pairs side by side.
#[test]
fn a_decoded_frame_is_laid_as_nv12_as_it_is() {
    for semi in [false, true] {
        let data = red_over_grey(semi);
        let frame = Decoded::in_one_buffer(&data, 8, 6, semi);
        let mut nv12 = vec![0u8; nv12_bytes(4, 4)];
        assert!(nv12_of(&frame, 4, 4, &mut nv12), "semi {semi}");
        assert!(nv12[..16].iter().all(|&luma| luma == 81), "semi {semi}: the luma as it is, packed");
        assert_eq!(nv12[16..], [90, 240, 90, 240, 128, 128, 128, 128], "semi {semi}: the pairs side by side");
    }
}

// An odd picture is padded even with its own last column and row — the
// chroma already covers it — and a frame short of the picture is refused
// with nothing written.
#[test]
fn an_odd_frame_is_padded_with_its_own_edge() {
    // 3x3 in rows of 4: luma = 10·row + column; chroma 2x2 pairs.
    let mut data: Vec<u8> = (0..4u8).flat_map(|row| (0..4u8).map(move |column| 10 * row + column)).collect();
    data.extend([1, 2, 3, 4, 5, 6, 7, 8]);
    let frame = Decoded::in_one_buffer(&data, 4, 4, true);
    let mut nv12 = vec![0u8; nv12_bytes(3, 3)];
    assert_eq!(nv12.len(), 4 * 4 * 3 / 2);
    assert!(nv12_of(&frame, 3, 3, &mut nv12));
    assert_eq!(&nv12[..16], [0, 1, 2, 2, 10, 11, 12, 12, 20, 21, 22, 22, 20, 21, 22, 22]);
    assert_eq!(&nv12[16..], [1, 2, 3, 4, 5, 6, 7, 8]);
    let mut untouched = vec![7u8; nv12.len()];
    let short = Decoded::in_one_buffer(&data[..data.len() - 1], 4, 4, true);
    assert!(!nv12_of(&short, 3, 3, &mut untouched), "a byte short of the last pair");
    assert!(untouched.iter().all(|&byte| byte == 7), "and nothing written");
    assert!(!nv12_of(&frame, 3, 3, &mut untouched[..11]), "an output short of the frame");
}

// One table a platform and an attribute, read both ways: the first name a
// code has is the one written, a name the table does not know reads as
// unnamed, and an unnamed code writes nothing.
#[test]
fn a_table_reads_and_names_its_codes() {
    let table = [("SMPTE170M", 6), ("BT709", 1), ("SMPTE_C", 6)];
    assert_eq!(code_of(&table, Some("SMPTE_C")), 6);
    assert_eq!(code_of(&table, Some("BT709")), 1);
    assert_eq!(code_of(&table, Some("film")), UNSPECIFIED);
    assert_eq!(code_of(&table, None), UNSPECIFIED);
    assert_eq!(name_of(&table, 6), Some("SMPTE170M"));
    assert_eq!(name_of(&table, 9), None);
    assert_eq!(name_of(&[("unnamed", UNSPECIFIED)], UNSPECIFIED), None, "2 is never written");
}
