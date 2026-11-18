//! A word's raster, in the app's own faces: the cover its glyphs make
//! (`glyphs::covered`), cut to the box the app says — checked against that
//! cover pixel by pixel, where the box holds it and where it does not.

use super::super::glyphs::{Cluster, Run, Shape};
use super::super::glyphs_tests::{IDENTITY, faces};
use super::*;
use crate::testing::last_error;

/// "3a" at `size` px as a layout might set it: the baseline a size down.
fn word(size: f64) -> Vec<Placed> {
    let sixty_fourths = |px: f64| (px * 64.0).round() as i32;
    let baseline = sixty_fourths(size);
    let clusters = vec![
        Cluster { text: "3".into(), origin: [0, baseline] },
        Cluster { text: "a".into(), origin: [sixty_fourths(0.55 * size), baseline] },
    ];
    let run = Run { size: sixty_fourths(size), weight: 400, italic: false, clusters };
    vec![Placed { at: IDENTITY, shape: Shape::Letters(run) }]
}

/// `scale` pixels a px, the layout's origin `margin` pixels in.
fn laid(scale: f32, margin: f32) -> Affine {
    Affine { a: scale, b: 0.0, c: 0.0, d: scale, e: margin, f: margin }
}

/// The raster of `shapes` over `size`, over bytes that held something.
fn raster(shapes: &[Placed], to_raster: Affine, size: [u32; 2]) -> Vec<u8> {
    let mut bytes = vec![7; (size[0] * size[1]) as usize];
    assert_eq!(pixels(size), Some(bytes.len()), "{}", last_error());
    rastered(faces(), shapes, to_raster, size[0], &mut bytes);
    bytes
}

#[test]
fn a_word_s_raster_is_its_cover_where_the_box_holds_it_and_nothing_elsewhere() {
    for (size, scale, margin) in [(12.0, 1.0, 1.0), (13.0, 1.5, 1.0), (9.0, 4.0, 2.0), (20.0, 2.0, 1.0)] {
        let shapes = word(size);
        let to_raster = laid(scale, margin);
        let cover = covered(faces(), &shapes, Paint::Fill, to_raster).expect("the word has ink");
        let [left, top, right, bottom] = cover.at;
        assert!(left >= 0 && top >= 0, "LIVENESS {size} px: the ink lies in from the margin");
        // A box that holds the ink with room to spare.
        let box_ = [right as u32 + 3, bottom as u32 + 2];
        let bytes = raster(&shapes, to_raster, box_);
        let mut inked = 0;
        for y in 0..box_[1] as i32 {
            for x in 0..box_[0] as i32 {
                let byte = bytes[(y as u32 * box_[0]) as usize + x as usize];
                assert_eq!(byte, cover.byte(x, y), "{size} px ×{scale} at ({x}, {y})");
                inked += u32::from(byte > 0);
            }
        }
        assert!(inked > 0, "LIVENESS {size} px ×{scale}: the raster has ink");
    }
}

#[test]
fn ink_past_the_box_s_edges_is_cut_off_at_each_of_them() {
    let shapes = word(20.0);
    // The word laid up and left of the box, which ends
    // inside its ink along and down: every edge cuts it.
    let to_raster = Affine { a: 2.0, b: 0.0, c: 0.0, d: 2.0, e: -5.0, f: -20.0 };
    let cover = covered(faces(), &shapes, Paint::Fill, to_raster).expect("the word has ink");
    let [left, top, right, bottom] = cover.at;
    let box_ = [(right - 6) as u32, (bottom - 4) as u32];
    assert!(left < 0 && top < 0 && box_[0] > 8 && box_[1] > 8, "LIVENESS: {:?}", cover.at);
    let bytes = raster(&shapes, to_raster, box_);
    for y in 0..box_[1] as i32 {
        for x in 0..box_[0] as i32 {
            assert_eq!(bytes[(y as u32 * box_[0]) as usize + x as usize], cover.byte(x, y), "({x}, {y})");
        }
    }
    let edge = |x: i32, y: i32| cover.byte(x, y) > 0;
    let last = (box_[0] as i32 - 1, box_[1] as i32 - 1);
    assert!((0..=last.1).any(|y| edge(0, y)), "LIVENESS: ink on the left edge");
    assert!((0..=last.0).any(|x| edge(x, 0)), "LIVENESS: ink on the top edge");
    assert!((0..=last.1).any(|y| edge(last.0, y)), "LIVENESS: ink on the right edge");
    assert!((0..=last.0).any(|x| edge(x, last.1)), "LIVENESS: ink on the bottom edge");
}

#[test]
fn a_word_wholly_past_the_box_leaves_it_clear() {
    let shapes = word(12.0);
    for to_raster in [laid(1.0, 400.0), laid(1.0, -400.0)] {
        assert_eq!(raster(&shapes, to_raster, [9, 5]), vec![0; 45]);
    }
    // Past it one way alone: down the box, and along it.
    let below = Affine { a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: 1.0, f: 400.0 };
    let beside = Affine { a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: 400.0, f: 1.0 };
    for to_raster in [below, beside] {
        assert_eq!(raster(&shapes, to_raster, [30, 30]), vec![0; 900]);
    }
}

// A block from a pixel before a 12 × 16 px box to a pixel after it.
#[test]
fn the_raster_keeps_its_margin_where_ink_hangs_past_the_word() {
    let block = [Placed { at: IDENTITY, shape: Shape::Rect([-64, -64, 13 * 64, 17 * 64]) }];
    for times in [1u32, 2] {
        let bytes = raster(&block, laid(times as f32, times as f32), [14 * times, 18 * times]);
        assert!(bytes.iter().all(|&alpha| alpha == 255), "{times} times over: ink to every edge");
    }
}

#[test]
fn a_word_of_no_ink_is_its_box_of_nothing() {
    let space = [Placed {
        at: IDENTITY,
        shape: Shape::Letters(Run {
            size: 768,
            weight: 400,
            italic: false,
            clusters: vec![Cluster { text: " ".into(), origin: [0, 768] }],
        }),
    }];
    assert_eq!(raster(&space, laid(1.0, 1.0), [4, 17]), vec![0; 4 * 17]);
}

#[test]
fn a_raster_of_no_pixel_or_past_the_bound_holds_no_bytes_and_says_why() {
    for size in [[0, 16], [16, 0]] {
        assert_eq!(pixels(size), None);
        assert!(last_error().contains("pixels has none"), "{}", last_error());
    }
    for size in [[65_537, 1], [1, 65_537]] {
        assert_eq!(pixels(size), None);
        assert!(last_error().contains("a side is 65536 at most"), "{}", last_error());
    }
    // The bound itself is taken, each way.
    assert_eq!(pixels([65_536, 3]), Some(3 << 16));
    assert_eq!(pixels([3, 65_536]), Some(3 << 16));
    assert_eq!(pixels([14, 18]), Some(252));
}
