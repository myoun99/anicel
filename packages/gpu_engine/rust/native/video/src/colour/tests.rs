//! The colour law's reading side, by hand — every movie a document reads
//! as RGBA is made by it, on every OS (↩️only the Android reader called it
//! till 2026-11-16) — the C test's cases, the values each integer row
//! gives worked out on paper, and the size's rule. The writing side's
//! are the GPU pass's own
//! (`gpu_engine` `kernels/export/tests.rs`). ↩️The law was the engine's
//! `qa_yuv601.h` and the cases `qa_video_decode_law_test.c`'s, until the
//! connection round deleted them (connection-round-checklist H,
//! 2026-11-08); the writing side was pinned here too while it was
//! `from_rgba` (till 2026-11-15).

use super::{
    BT601, BT709, Colours, Decoded, MATRICES, Sums, UNSPECIFIED, code_of, name_of, nv12_bytes, nv12_of, rgba_of,
};

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

/// `data`, a decoder's buffer of a `width`×`height` frame as
/// [`Decoded::in_one_buffer`] reads it — `stride`, `slice`, `semi` — laid
/// as NV12 and made RGBA by BT.601 studio: what a backend lays and the law
/// then makes of it. None where either refuses.
fn shown_of(data: &[u8], (width, height): (usize, usize), (stride, slice, semi): (usize, usize, bool)) -> Option<Vec<u8>> {
    let mut nv12 = vec![0u8; nv12_bytes(width, height)];
    let mut rgba = vec![0u8; width * height * 4];
    let frame = Decoded::in_one_buffer(data, stride, slice, semi);
    (nv12_of(&frame, width, height, &mut nv12) && rgba_of(&nv12, (width, height), BT601[0], &mut rgba)).then_some(rgba)
}

/// The law by hand: a pixel of luma `l` and chroma (`cb`, `cr`), by `sums` —
/// the decoder's tests check `upright` against it too.
pub(crate) fn by_hand(l: u8, cb: u8, cr: u8, sums: Sums) -> [u8; 4] {
    let l = sums.luma * (i32::from(l) - sums.black);
    let (cb, cr) = (i32::from(cb) - 128, i32::from(cr) - 128);
    let [r, g, b] = [l + sums.red_cr * cr, l + sums.green_cb * cb + sums.green_cr * cr, l + sums.blue_cb * cb]
        .map(|sum| ((sum + 128) >> 8).clamp(0, 255) as u8);
    [r, g, b, 255]
}

// The C test's: both strides walked (the furthest pixel lands in the
// padding if stride is read as width, and turns red if the chroma rows are
// confused), and NV12 is the same picture as I420.
#[test]
fn a_frame_reads_back_through_both_strides() {
    let planar = shown_of(&red_over_grey(false), (4, 4), (8, 6, false)).expect("planar");
    assert_eq!(planar[..4], [255, 0, 0, 255], "red is red, and opaque");
    let last = (3 * 4 + 3) * 4;
    assert_eq!(planar[last..last + 4], [76, 76, 76, 255], "the bottom half is grey, not red");
    let semi = shown_of(&red_over_grey(true), (4, 4), (8, 6, true)).expect("semi");
    assert_eq!(semi, planar, "NV12 and I420 are the same picture");
}

// ⚠️Short of its own planes, refused — not read past, which here is a panic
// and across the FFI the app gone. A byte short at the chroma's end in each
// layout; at the luma's, where a slice short of the picture puts the
// chroma first; and the law's own two, an NV12 and an output short of the
// picture.
#[test]
fn a_frame_short_of_its_own_planes_is_refused() {
    for (semi, needed) in [(false, 66), (true, 60)] {
        let frame = red_over_grey(semi);
        assert!(shown_of(&frame[..needed], (4, 4), (8, 6, semi)).is_some(), "semi {semi}: to its last byte read");
        let mut untouched = vec![7u8; nv12_bytes(4, 4)];
        let short = Decoded::in_one_buffer(&frame[..needed - 1], 8, 6, semi);
        assert!(!nv12_of(&short, 4, 4, &mut untouched), "semi {semi}: a byte short");
        assert!(untouched.iter().all(|&byte| byte == 7), "semi {semi}: and nothing written");
    }
    let luma = [16u8; 4];
    assert!(shown_of(&luma, (2, 2), (2, 0, true)).is_some(), "the luma's last byte is the last read");
    assert!(shown_of(&luma[..3], (2, 2), (2, 0, true)).is_none(), "a byte short of the luma");
    let nv12 = [16u8, 16, 16, 16, 128, 128];
    let mut untouched = [7u8; 2 * 2 * 4];
    assert!(!rgba_of(&nv12[..5], (2, 2), BT601[0], &mut untouched), "an NV12 a byte short");
    assert!(untouched.iter().all(|&byte| byte == 7), "and nothing written");
    assert!(!rgba_of(&nv12, (2, 2), BT601[0], &mut untouched[..15]), "an output short of the picture");
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
        assert!(rgba_of(&frame, (2, 2), BT601[0], &mut rgba), "six bytes are the whole of it");
        assert_eq!(rgba[..3], want, "Y {luma} Cb {cb} Cr {cr}");
        assert!(rgba.chunks(4).all(|pixel| pixel == &rgba[..4]), "a flat frame is flat");
    }
}

// Every row of sums is its matrix's two weights (H.273's Kr and Kb) and its
// range, rounded — worked out again here, so no row was typed wrong; and
// BT.601's studio row is the app's own law, the NV12 pass's inverse.
#[test]
fn every_row_is_its_matrixs_two_weights() {
    let weights = |code| match code {
        1 => (0.2126, 0.0722),
        5 | 6 => (0.299, 0.114),
        7 => (0.212, 0.087),
        9 => (0.2627, 0.0593),
        _ => panic!("matrix {code} has no weights here"),
    };
    for (code, rows) in MATRICES {
        let (kr, kb): (f64, f64) = weights(code);
        let kg = 1.0 - kr - kb;
        for (full, sums) in [(false, rows[0]), (true, rows[1])] {
            let (luma, chroma) = if full { (1.0, 1.0) } else { (255.0 / 219.0, 255.0 / 224.0) };
            let at = |weight: f64| (weight * 256.0).round() as i32;
            let want = Sums {
                black: if full { 0 } else { 16 },
                luma: at(luma),
                red_cr: at(2.0 * (1.0 - kr) * chroma),
                green_cb: at(-2.0 * kb * (1.0 - kb) / kg * chroma),
                green_cr: at(-2.0 * kr * (1.0 - kr) / kg * chroma),
                blue_cb: at(2.0 * (1.0 - kb) * chroma),
            };
            assert_eq!(sums, want, "matrix {code}, full {full}");
        }
    }
    let law = Sums { black: 16, luma: 298, red_cr: 409, green_cb: -100, green_cr: -208, blue_cb: 516 };
    assert_eq!(BT601[0], law, "the app's own law: Y = ((66R + 129G + 25B + 128) >> 8) + 16, read back");
}

// 🗣️A movie that names no matrix is read by its size (유저 11-16, movie-
// frames-come-as-their-yuv-to-the-engine-Q1 (가)): HD — 1280 wide or more,
// or more than 576 tall — BT.709, else BT.601; a name always wins, and a
// range it does not name is studio.
#[test]
fn a_movie_that_names_no_matrix_is_read_by_its_size() {
    let named = |matrix, range| Colours { matrix, range, ..Colours::NONE };
    let none = Colours::NONE;
    assert_eq!(Sums::of(none, (1280, 576)), BT709[0], "1280 wide is HD, however tall");
    assert_eq!(Sums::of(none, (1279, 576)), BT601[0], "narrower, and 576 tall, is not");
    assert_eq!(Sums::of(none, (720, 577)), BT709[0], "more than 576 tall is HD");
    assert_eq!(Sums::of(none, (720, 480)), BT601[0], "NTSC's SD");
    assert_eq!(Sums::of(named(6, UNSPECIFIED), (1920, 1080)), BT601[0], "a name wins over the size");
    assert_eq!(Sums::of(named(1, UNSPECIFIED), (640, 480)), BT709[0], "both ways");
    assert_eq!(Sums::of(named(1, 1), (640, 480)), BT709[1], "full range where it says so");
    assert_eq!(Sums::of(named(UNSPECIFIED, 1), (640, 480)), BT601[1], "and with no matrix named");
    assert_eq!(Sums::of(named(8, 0), (1920, 1080)), BT709[0], "a matrix no table knows is read by its size");
    assert_eq!(Sums::of(named(8, 0), (640, 480)), BT601[0], "both ways");
}

// 🚨A row at a time is each pixel's own sum: the row's chroma spread first
// and every pixel written whole is the law worked a pixel at a time — by
// every row of sums, over an odd frame, each pixel its 2×2 block's chroma.
#[test]
fn a_row_at_a_time_is_each_pixels_own_sum() {
    let (width, height, padded, rows) = (7, 5, 8, 6);
    let mut seed = 0x2545_f491u32;
    let nv12: Vec<u8> = (0..nv12_bytes(width, height))
        .map(|_| {
            seed ^= seed << 13;
            seed ^= seed >> 17;
            seed ^= seed << 5;
            seed as u8
        })
        .collect();
    for sums in MATRICES.iter().flat_map(|(_, rows)| rows) {
        let mut rgba = vec![0u8; width * height * 4];
        assert!(rgba_of(&nv12, (width, height), *sums, &mut rgba));
        for (y, x) in (0..height).flat_map(|y| (0..width).map(move |x| (y, x))) {
            let chroma = padded * rows + (y / 2) * padded + (x / 2) * 2;
            let want = by_hand(nv12[y * padded + x], nv12[chroma], nv12[chroma + 1], *sums);
            assert_eq!(rgba[(y * width + x) * 4..][..4], want, "{sums:?} at ({x}, {y})");
        }
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
