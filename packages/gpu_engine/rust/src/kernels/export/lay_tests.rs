//! A frame's last picture on the engine (gpu-export-path ①⑵): a frame the
//! export makes, and what is laid over it, checked against what the law
//! gives by hand — never against a CPU copy of it (`kernels/mod.rs`).

use super::shown_tests::shown;
use super::tests::rig;
use super::{Cover, Frame, Picture, Shown, Source};
use crate::testing::{last_error, read_buffer};

const WHITE: u32 = 0xffff_ffff;
const RED: u32 = 0xff00_00ff;

/// A frame of `width` x `height` the export made, laid with `ground`.
fn blank(width: u32, height: u32, ground: u32) -> Shown {
    let rig = rig();
    let frame = Shown::blank(rig.engine, Picture { width, height }).expect("blank");
    rig.lay.run(rig.engine, &frame, Source::Solid(ground), 255, None).expect("ground");
    frame
}

/// `width` x `height` of `word` — premultiplied, red the low byte — as the
/// app hands a picture it rastered.
fn uploaded(width: u32, height: u32, word: impl Fn(u32, u32) -> u32) -> Shown {
    let rgba: Vec<u8> = (0..height)
        .flat_map(|y| (0..width).map(move |x| (x, y)))
        .flat_map(|(x, y)| word(x, y).to_le_bytes())
        .collect();
    Shown::uploaded(rig().engine, &rgba, Picture { width, height }).expect("uploaded")
}

/// The words `frame` holds, row after row.
fn words(frame: &Shown) -> Vec<u32> {
    let bytes = read_buffer(rig().engine, &frame.rows);
    bytes.chunks_exact(4).map(|word| u32::from_le_bytes([word[0], word[1], word[2], word[3]])).collect()
}

/// Lays `source` at (`x`, `y`) over `onto` at `opacity`, under `cover`.
fn lay(onto: &Shown, source: &Shown, (x, y): (i32, i32), opacity: u8, cover: Option<&Cover>) {
    let rig = rig();
    rig.lay
        .run(rig.engine, onto, Source::Frame { frame: source, x, y }, opacity, cover)
        .expect("laid");
}

// A ground of straight 0x80 alpha, blue 0x40, green 0x80, red 0xff is kept
// premultiplied (premultiply.wgsl): red 255·128/255 = 128, green
// 128·128/255 = 64.25 → 64, blue 64·128/255 = 32.1 → 32.
#[test]
fn a_frame_the_export_makes_is_its_ground_premultiplied() {
    assert_eq!(words(&blank(5, 3, 0x8040_80ff)), vec![0x8020_4080; 15]);
}

#[test]
fn a_ground_of_no_alpha_leaves_the_frame_clear() {
    assert_eq!(words(&blank(5, 3, 0x00ff_ffff)), vec![0; 15]);
}

#[test]
fn an_opaque_picture_is_laid_where_it_stands_and_nothing_else_moves() {
    let frame = blank(6, 4, WHITE);
    lay(&frame, &uploaded(2, 2, |_, _| RED), (3, 1), 255, None);

    let inside = |at: usize| (3..5).contains(&(at % 6)) && (1..3).contains(&(at / 6));
    let expected: Vec<u32> = (0..24).map(|at| if inside(at) { RED } else { WHITE }).collect();
    assert_eq!(words(&frame), expected);
}

// Past the frame's left edge, only its column 1 meets it; past its right,
// nothing does.
#[test]
fn a_picture_past_the_frame_is_laid_where_they_meet() {
    let frame = blank(6, 4, WHITE);
    let picture = uploaded(2, 2, |x, y| [0xff00_ff00, RED][usize::from(x == 1 && y == 0)]);
    lay(&frame, &picture, (-1, 3), 255, None);
    lay(&frame, &picture, (6, 0), 255, None);

    let mut expected = vec![WHITE; 24];
    expected[18] = RED;
    assert_eq!(words(&frame), expected);
}

// Red over white at half: alpha out 1, and each colour the two weighed —
// green and blue 255·(1 − 128/255) = 127 (blend.wgsl, normal), red 255.
#[test]
fn half_an_opacity_lays_half_the_picture() {
    let frame = blank(3, 1, WHITE);
    lay(&frame, &uploaded(3, 1, |_, _| RED), (0, 0), 128, None);

    assert_eq!(words(&frame), vec![0xff7f_7fff; 3]);
}

// What a pixel takes is its cover's byte: none, half or all of the red.
#[test]
fn a_cover_lays_what_each_pixel_takes() {
    let rig = rig();
    let frame = blank(3, 1, WHITE);
    let cover = Cover::of(rig.engine, &[0, 128, 255], Picture { width: 3, height: 1 }).expect("cover");
    lay(&frame, &uploaded(3, 1, |_, _| RED), (0, 0), 255, Some(&cover));

    assert_eq!(words(&frame), vec![WHITE, 0xff7f_7fff, RED]);
}

// A picture under the frame thins what lies under it alone: half a red
// laid over nothing keeps its colour at half its alpha — premultiplied,
// red 255·128/255 = 128.
#[test]
fn half_a_picture_over_nothing_is_its_colour_at_half_its_alpha() {
    let frame = blank(2, 1, 0);
    lay(&frame, &uploaded(2, 1, |_, _| RED), (0, 0), 128, None);

    assert_eq!(words(&frame), vec![0x8000_0080; 2]);
}

// A frame shown from a BGRA surface is laid in its own colours, as one
// shown from an RGBA surface.
#[test]
fn a_frame_shown_is_laid_in_its_colours_however_its_surface_lies() {
    let picture = |x: u32, y: u32| 0xff00_0000 | (x * 40) << 16 | (y * 60) << 8 | 200;
    let laid = |bgra: bool| {
        let frame = blank(4, 3, WHITE);
        lay(&frame, &shown(4, 3, bgra, picture), (0, 0), 255, None);
        words(&frame)
    };

    let expected: Vec<u32> = (0..12).map(|at| picture(at % 4, at / 4)).collect();
    assert_eq!(laid(false), expected);
    assert_eq!(laid(true), expected);
}

// The conversions read a frame the export laid as a frame shown: its
// pixels, opaque everywhere.
#[test]
fn a_frame_laid_is_read_by_the_conversions() {
    let rig = rig();
    let frame = blank(5, 2, WHITE);
    lay(&frame, &uploaded(2, 2, |_, _| RED), (1, 0), 255, None);
    let picture = Picture { width: 5, height: 2 };

    let opaque = rig.opaque.run(rig.engine, Frame::Shown(&frame), picture).expect("opaque");
    assert_eq!(read_buffer(rig.engine, &opaque)[..4], 255u32.to_le_bytes());
    let rgb = rig.over_ground.run(rig.engine, Frame::Shown(&frame), picture, [0, 0, 0], None);
    let rgb = read_buffer(rig.engine, &rgb.expect("over ground"));
    assert_eq!(rgb[..9], [255, 255, 255, 255, 0, 0, 255, 0, 0]);
}

#[test]
fn a_cover_not_the_frame_s_size_is_refused() {
    let rig = rig();
    let frame = blank(3, 2, WHITE);
    let cover = Cover::of(rig.engine, &[255; 3], Picture { width: 3, height: 1 }).expect("cover");
    let laid = rig.lay.run(rig.engine, &frame, Source::Solid(RED), 255, Some(&cover));

    assert!(laid.is_none());
    assert_eq!(last_error(), "a 3x1 cover is not a 3x2 frame's");
}

#[test]
fn a_frame_shown_from_a_bgra_surface_is_not_laid_onto() {
    let rig = rig();
    let laid = rig.lay.run(rig.engine, &shown(3, 2, true, |_, _| RED), Source::Solid(RED), 255, None);

    assert!(laid.is_none());
    assert_eq!(last_error(), "a frame is laid onto as the export lays one: RGBA, not BGRA");
}

#[test]
fn a_picture_or_a_cover_of_too_few_bytes_is_refused() {
    let engine = rig().engine;
    let picture = Picture { width: 2, height: 2 };

    assert!(Shown::uploaded(engine, &[0; 15], picture).is_none());
    assert_eq!(last_error(), "a 2x2 picture is 16 bytes, not 15");
    assert!(Cover::of(engine, &[0; 3], picture).is_none());
    assert_eq!(last_error(), "a 2x2 cover is 4 bytes, not 3");
}
