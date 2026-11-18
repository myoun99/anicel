//! An engine NV12 frame laid into each buffer an encoder takes keeps every
//! byte, and only where it lies changes: packed out of the engine's rows,
//! and for the planar buffer its CbCr pairs parted into Cb's plane and
//! Cr's — no sum. ↩️It was held to what the colour law filled each buffer
//! with from the picture itself (`colour::from_rgba`) till that went
//! (2026-11-15, board trimmed-movie-decodes-to-nv12-Q2).

use super::{Nv12, lay};
use crate::colour::Planes;

const FRAME: (usize, usize) = (8, 6);

/// A byte of its own for each place `at` of a packed frame, so a byte laid
/// in the wrong place shows.
fn byte_at(at: usize) -> u8 {
    (at as u32).wrapping_mul(2_654_435_761).to_le_bytes()[3]
}

/// The frame packed: its Y rows, then its CbCr rows, `FRAME.0` bytes each.
fn packed() -> Vec<u8> {
    (0..FRAME.0 * FRAME.1 * 3 / 2).map(byte_at).collect()
}

/// The frame as the engine reads it back: rows `stride` apart, the bytes
/// past the frame's width not the frame's.
fn engine_frame(stride: usize) -> Vec<u8> {
    let (width, height) = FRAME;
    let mut bytes = vec![0xA5; Nv12::bytes_of(stride, height)];
    for row in 0..height * 3 / 2 {
        for column in 0..width {
            bytes[row * stride + column] = byte_at(row * width + column);
        }
    }
    bytes
}

/// The frame with its CbCr pairs parted: its Y rows packed, then Cb's plane,
/// then Cr's, half as wide and half as tall.
fn parted() -> Vec<u8> {
    let (width, height) = FRAME;
    let (pairs, rows) = (width / 2, height / 2);
    let mut buffer = packed();
    for row in 0..rows {
        for pair in 0..pairs {
            let at = (height + row) * width + pair * 2;
            buffer[width * height + row * pairs + pair] = byte_at(at);
            buffer[width * height + rows * pairs + row * pairs + pair] = byte_at(at + 1);
        }
    }
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
fn laid_side_by_side_is_every_byte_packed() {
    for stride in [8, 12, 64] {
        assert_eq!(laid(stride, semi_planar), packed(), "rows {stride} bytes apart");
    }
}

#[test]
fn laid_apart_parts_each_pair_into_its_planes() {
    assert_ne!(parted(), packed(), "⛔fixture: the two layouts differ");
    for stride in [8, 12, 64] {
        assert_eq!(laid(stride, planar), parted(), "rows {stride} bytes apart");
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
