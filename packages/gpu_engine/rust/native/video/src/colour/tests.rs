//! The colour law, by hand: no export of the engine reaches `qa_yuv601.h` on
//! Windows (only the Android and Apple writers call it), so its answers are
//! pinned here — the C test's cases (qa_video_decode_law_test.c) and the
//! values the BT.601 integer formula gives, worked out on paper.

use super::{Picture, Planes, from_rgba, to_rgba};

/// One colour over a 2×2 frame: its Y, Cb and Cr.
fn ycc_of(rgb: [u8; 3]) -> [u8; 3] {
    let rgba: Vec<u8> = [rgb[0], rgb[1], rgb[2], 255].repeat(4);
    let mut y = [0u8; 4];
    let mut chroma = [0u8; 2];
    let picture = Picture { rgba: &rgba, width: 2, height: 2 };
    let mut planes = Planes { y: &mut y, y_stride: 2, chroma: &mut chroma, cb: 0, cr: 1, chroma_stride: 2, chroma_step: 2 };
    from_rgba(&picture, 2, 2, &mut planes);
    assert!(y.iter().all(|&luma| luma == y[0]), "a flat picture is flat");
    [y[0], chroma[0], chroma[1]]
}

// Each channel alone at full and at a step where the formula's rounding
// lands exactly on a multiple of 256, so a coefficient or a rounding term
// off by one moves an answer.
#[test]
fn a_colour_becomes_its_bt601_studio_values() {
    for (rgb, want) in [
        ([0, 0, 0], [16, 128, 128]),
        ([255, 255, 255], [235, 128, 128]),
        ([255, 0, 0], [82, 90, 240]),
        ([0, 255, 0], [144, 54, 34]),
        ([0, 0, 255], [41, 240, 110]),
        ([200, 100, 50], [123, 91, 175]),
        ([32, 32, 32], [44, 128, 128]),
        ([8, 0, 0], [18, 127, 132]),
        ([0, 0, 8], [17, 132, 127]),
    ] {
        assert_eq!(ycc_of(rgb), want, "{rgb:?}");
    }
}

// A 3×1 picture in a 4×4 frame, both layouts: rows and the chroma land where
// the strides say, a block takes its top-left pixel's chroma, the padding
// is white, and what lies past a stride is never written.
#[test]
fn the_planes_land_where_the_layout_says() {
    let rgba = [255, 0, 0, 255, 0, 0, 255, 255, 0, 255, 0, 255];
    let picture = Picture { rgba: &rgba, width: 3, height: 1 };
    let (red, blue, green, white) = ([82, 90, 240], [41, 240, 110], [144, 54, 34], [235, 128, 128]);
    for semi in [false, true] {
        let mut y = [0xAAu8; 6 * 4];
        let mut chroma = [0xAAu8; 6 * 2 + 1];
        let mut planes = if semi {
            Planes { y: &mut y, y_stride: 6, chroma: &mut chroma, cb: 0, cr: 1, chroma_stride: 6, chroma_step: 2 }
        } else {
            Planes { y: &mut y, y_stride: 6, chroma: &mut chroma, cb: 0, cr: 6, chroma_stride: 3, chroma_step: 1 }
        };
        from_rgba(&picture, 4, 4, &mut planes);
        assert_eq!(&y[..6], &[red[0], blue[0], green[0], white[0], 0xAA, 0xAA], "semi {semi}: the first row");
        for row in 1..4 {
            assert_eq!(&y[row * 6..row * 6 + 6], &[235, 235, 235, 235, 0xAA, 0xAA], "semi {semi}: row {row}");
        }
        let at = |block_row: usize, block: usize, which: usize| {
            if semi { chroma[block_row * 6 + block * 2 + which] } else { chroma[which * 6 + block_row * 3 + block] }
        };
        assert_eq!([at(0, 0, 0), at(0, 0, 1)], [red[1], red[2]], "semi {semi}: the top-left pixel's, not a mean");
        assert_eq!([at(0, 1, 0), at(0, 1, 1)], [green[1], green[2]], "semi {semi}: the second block");
        assert_eq!([at(1, 0, 0), at(1, 0, 1)], [white[1], white[2]], "semi {semi}: the padding");
        assert_eq!([at(1, 1, 0), at(1, 1, 1)], [white[1], white[2]], "semi {semi}: the padding");
    }
}

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
    to_rgba(&red_over_grey(false), 4, 4, 8, 6, false, &mut planar);
    assert_eq!(planar[..4], [255, 0, 0, 255], "red is red, and opaque");
    let last = (3 * 4 + 3) * 4;
    assert_eq!(planar[last..last + 4], [76, 76, 76, 255], "the bottom half is grey, not red");
    let mut semi = [0u8; 4 * 4 * 4];
    to_rgba(&red_over_grey(true), 4, 4, 8, 6, true, &mut semi);
    assert_eq!(semi, planar, "NV12 and I420 are the same picture");
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
        to_rgba(&frame, 2, 2, 2, 2, true, &mut rgba);
        assert_eq!(rgba[..3], want, "Y {luma} Cb {cb} Cr {cr}");
        assert!(rgba.chunks(4).all(|pixel| pixel == &rgba[..4]), "a flat frame is flat");
    }
}

// 🚨★★★THE TWO DIRECTIONS ARE ONE LAW: what a writer makes of a colour,
// the reader turns back into that colour (within 2), in both layouts — the
// C test's colours, the ones the Apple writer lost red on.
#[test]
fn a_colour_comes_back_where_it_was_written() {
    for rgb in [[20, 0, 0], [110, 0, 0], [200, 0, 0], [230, 0, 0], [0, 170, 0], [0, 0, 140], [90, 160, 40], [250, 250, 250]] {
        let rgba: Vec<u8> = [rgb[0], rgb[1], rgb[2], 255].repeat(3);
        let picture = Picture { rgba: &rgba, width: 3, height: 1 };
        for semi in [false, true] {
            let mut frame = [0u8; 4 * 4 * 3 / 2];
            let (y, chroma) = frame.split_at_mut(16);
            let mut planes = if semi {
                Planes { y, y_stride: 4, chroma, cb: 0, cr: 1, chroma_stride: 4, chroma_step: 2 }
            } else {
                Planes { y, y_stride: 4, chroma, cb: 0, cr: 4, chroma_stride: 2, chroma_step: 1 }
            };
            from_rgba(&picture, 4, 4, &mut planes);
            let mut back = [0u8; 4 * 4 * 4];
            to_rgba(&frame, 4, 4, 4, 4, semi, &mut back);
            for k in 0..3 {
                assert!(back[k].abs_diff(rgb[k]) <= 2, "{rgb:?} semi {semi}: {} came back {}", rgb[k], back[k]);
                assert_eq!(back[(3 * 4 + 3) * 4 + k], 255, "and the padding is white");
            }
        }
    }
}
