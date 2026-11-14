//! An engine NV12 frame laid into each buffer an encoder takes is the
//! buffer the colour law would have filled from the picture itself
//! (`colour::from_rgba`) — so taking the engine's bytes changes where the
//! sums are made, and not one byte of the movie.

use super::{Nv12, lay};
use crate::colour::{Picture, Planes, from_rgba};

/// A picture of odd size, so the frame round it carries padding; every
/// byte its own, so a byte laid in the wrong place shows.
const PICTURE: (usize, usize) = (7, 5);
const FRAME: (usize, usize) = (8, 6);

fn picture_bytes() -> Vec<u8> {
    let (width, height) = PICTURE;
    (0..width * height * 4).map(|at| (at as u32).wrapping_mul(2_654_435_761).to_le_bytes()[3]).collect()
}

/// The frame as the engine reads it back: one buffer, rows `stride` apart
/// past the frame's width, the bytes past it not the frame's.
fn engine_frame(stride: usize) -> Vec<u8> {
    let (width, height) = FRAME;
    let rgba = picture_bytes();
    let picture = Picture { rgba: &rgba, width: PICTURE.0, height: PICTURE.1 };
    let mut bytes = vec![0xA5; Nv12::bytes_of(stride, height)];
    let (y, chroma) = bytes.split_at_mut(stride * height);
    let mut planes = Planes { y, y_stride: stride, chroma, cb: 0, cr: 1, chroma_stride: stride, chroma_step: 2 };
    from_rgba(&picture, width, height, &mut planes);
    bytes
}

/// What the colour law fills a buffer of `layout` with from the picture.
fn filled(layout: fn(&mut [u8]) -> Planes) -> Vec<u8> {
    let (width, height) = FRAME;
    let rgba = picture_bytes();
    let picture = Picture { rgba: &rgba, width: PICTURE.0, height: PICTURE.1 };
    let mut buffer = vec![0; width * height * 3 / 2];
    from_rgba(&picture, width, height, &mut layout(&mut buffer));
    buffer
}

/// What laying the engine's frame fills a buffer of `layout` with.
fn laid(stride: usize, layout: fn(&mut [u8]) -> Planes) -> Vec<u8> {
    let (width, height) = FRAME;
    let bytes = engine_frame(stride);
    let frame = Nv12::over(&bytes, stride, width, height).expect("a frame its bytes hold");
    let mut buffer = vec![0; width * height * 3 / 2];
    lay(&frame, &mut layout(&mut buffer));
    buffer
}

/// Android's semi-planar buffer and Apple's two planes: Y, then CbCr side
/// by side, packed.
fn semi_planar(buffer: &mut [u8]) -> Planes<'_> {
    let width = FRAME.0;
    let (y, chroma) = buffer.split_at_mut(width * FRAME.1);
    Planes { y, y_stride: width, chroma, cb: 0, cr: 1, chroma_stride: width, chroma_step: 2 }
}

/// Android's planar (I420) fallback: Y, then Cb's plane, then Cr's.
fn planar(buffer: &mut [u8]) -> Planes<'_> {
    let (width, height) = FRAME;
    let luma = width * height;
    let (y, chroma) = buffer.split_at_mut(luma);
    Planes { y, y_stride: width, chroma, cb: 0, cr: luma / 4, chroma_stride: width / 2, chroma_step: 1 }
}

#[test]
fn laid_side_by_side_is_what_the_colour_law_fills() {
    let expected = filled(semi_planar);
    assert_ne!(expected, vec![0; expected.len()], "⛔fixture: a picture");
    for stride in [8, 12, 64] {
        assert_eq!(laid(stride, semi_planar), expected, "rows {stride} bytes apart");
    }
}

#[test]
fn laid_apart_is_what_the_colour_law_fills() {
    let expected = filled(planar);
    assert_ne!(expected, filled(semi_planar), "⛔fixture: the two layouts differ");
    for stride in [8, 12, 64] {
        assert_eq!(laid(stride, planar), expected, "rows {stride} bytes apart");
    }
}

#[test]
fn a_frame_its_bytes_cannot_hold_is_none() {
    let bytes = vec![0; Nv12::bytes_of(8, 6)];
    assert!(Nv12::over(&bytes, 8, 8, 6).is_some(), "⛔fixture: this one holds");
    assert!(Nv12::over(&bytes, 6, 8, 6).is_none(), "a stride short of the width");
    assert!(Nv12::over(&bytes, 8, 7, 6).is_none(), "an odd width");
    assert!(Nv12::over(&bytes, 8, 8, 5).is_none(), "an odd height");
    assert!(Nv12::over(&bytes[1..], 8, 8, 6).is_none(), "a byte short");
}
