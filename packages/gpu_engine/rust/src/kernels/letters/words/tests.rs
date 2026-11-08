//! A word's bake, checked by hand and in the app's own faces — never
//! against a CPU copy of the average (`kernels/mod.rs`): the windows are
//! worked out below, and the faces' words are held to what F-297 asks of
//! them, down the line and along it. The pins came here with the bake from
//! the app (`a_baked_word_stands_where_the_word_does_test.dart`,
//! `tiny_glyphs_shrink_not_vanish_test.dart`).

use super::super::Cover;
use super::super::glyphs::{Affine, Cluster, Placed, Run, Shape, covered};
use super::super::glyphs_tests::{IDENTITY, faces};
use super::*;
use crate::testing::last_error;

/// "3" and, unless `alone`, "a" after it at `size` px, as a layout might
/// set them: the box 1.1 × 1.25 sizes, the baseline a size down.
fn word(size: f64, alone: bool) -> (Vec<Placed>, [f64; 2]) {
    let sixty_fourths = |px: f64| (px * 64.0).round() as i32;
    let baseline = sixty_fourths(size);
    let mut clusters = vec![Cluster { text: "3".into(), origin: [0, baseline] }];
    if !alone {
        clusters.push(Cluster { text: "a".into(), origin: [sixty_fourths(0.55 * size), baseline] });
    }
    let run = Run { size: sixty_fourths(size), bold: false, italic: false, clusters };
    let box_ = [if alone { 0.6 } else { 1.1 } * size, 1.25 * size];
    (vec![Placed { at: IDENTITY, shape: Shape::Letters(run) }], box_)
}

/// How many times the app rasters a word of `size` px over (word_bake.dart
/// `wordBakeScale`): enough to land it at 12 px or past.
fn times_for(size: f64) -> u32 {
    if size >= 12.0 { 1 } else { (12.0 / size).ceil() as u32 }
}

/// Where a bake's ink is: its weight, the centre of that weight, and the
/// rows that hold any.
struct Ink {
    sum: f64,
    cx: f64,
    cy: f64,
    rows: Vec<u32>,
}

fn ink_of(cover: &WordCover) -> Ink {
    let (mut sum, mut sum_x, mut sum_y, mut rows) = (0.0, 0.0, 0.0, Vec::new());
    for y in 0..cover.height {
        let line = &cover.bytes[(y * cover.width) as usize..((y + 1) * cover.width) as usize];
        for (x, &alpha) in line.iter().enumerate() {
            let alpha = f64::from(alpha);
            sum += alpha;
            sum_x += alpha * (x as f64 + 0.5);
            sum_y += alpha * (f64::from(y) + 0.5);
        }
        if line.iter().any(|&alpha| alpha > 0) {
            rows.push(y);
        }
    }
    Ink { sum, cx: sum_x / sum, cy: sum_y / sum, rows }
}

fn baked(shapes: &[Placed], size: [f64; 2], dpr: f64, times: u32, narrowed: [u32; 2]) -> WordCover {
    bake(faces(), shapes, dpr, times, size, narrowed).unwrap_or_else(|| panic!("{}", last_error()))
}

// Pixel i's window is [t(64(i − 1) + k), t(64i + k)) in k-ths of a raster
// pixel; raster pixel p is [pk, (p + 1)k).
#[test]
fn a_window_covers_its_raster_pixels_by_the_part_it_covers() {
    // 1:1 — each pixel is its own raster pixel, whole.
    assert_eq!(narrowed_windows(1, 64, 3, 3), [(0, vec![64]), (1, vec![64]), (2, vec![64])]);
    // Twice over: [0, 128) and [128, 256) in 64ths — two raster pixels each.
    assert_eq!(narrowed_windows(2, 64, 2, 4), [(0, vec![64, 64]), (2, vec![64, 64])]);
    // Narrowed to a half: [−32, 32) — the margin pixel and as much past the
    // raster —, then [32, 96) and [96, 160) in 32nds.
    assert_eq!(
        narrowed_windows(1, 32, 3, 5),
        [(0, vec![32]), (1, vec![32, 32]), (3, vec![32, 32])]
    );
    // To three quarters: [−16, 48), then [48, 112) — raster pixel 1 whole,
    // and a third of pixel 2 ([96, 144)).
    assert_eq!(narrowed_windows(1, 48, 2, 3), [(0, vec![48]), (1, vec![48, 16])]);
    // A window wholly past the raster covers none of it.
    assert_eq!(narrowed_windows(1, 64, 2, 1)[1].1, Vec::<u32>::new());
}

#[test]
fn a_window_inside_the_raster_is_its_whole_and_they_tile_it() {
    for times in 1..=4 {
        for k in 1..=MOST {
            let windows = narrowed_windows(times, k, 8, 1 << 12);
            for (i, (first, parts)) in windows.iter().enumerate().skip(1) {
                let why = format!("t {times}, k {k}, pixel {i}");
                assert_eq!(parts.iter().sum::<u32>(), 64 * times, "{why}: the whole of a window");
                // No gap and no overlap: the last raster pixel a window covers
                // in part is the next one's first.
                let (next, _) = windows.get(i + 1).cloned().unwrap_or((u32::MAX, Vec::new()));
                let end = first + parts.len() as u32;
                assert!(next == u32::MAX || next == end || next + 1 == end, "{why}");
            }
        }
    }
}

#[test]
fn a_field_of_one_value_stays_that_value_wherever_a_window_lies_in_it() {
    let raster = [40, 24];
    for times in [1, 2, 3, 4, MOST] {
        for k in [1, 6, 19, 32, 45, 54, 63, 64] {
            for value in [1, 128, 254, 255] {
                let field = Cover {
                    at: [-8, -8, raster[0] as i32 + 8, raster[1] as i32 + 8],
                    bytes: vec![value; (raster[0] as usize + 16) * (raster[1] as usize + 16)],
                };
                let boxed = [8, 5];
                let bytes = narrowed_cover(&field, raster, boxed, times, [k, 64]);
                let columns = narrowed_windows(times, k, boxed[0], raster[0]);
                let rows = narrowed_windows(times, 64, boxed[1], raster[1]);
                for (y, (top, down)) in rows.iter().enumerate() {
                    for (x, (left, along)) in columns.iter().enumerate() {
                        let inside = |(first, parts): (&u32, &Vec<u32>), extent: u32, whole: u32| {
                            parts.iter().sum::<u32>() == whole && first + parts.len() as u32 <= extent
                        };
                        if inside((top, down), raster[1], 64 * times) && inside((left, along), raster[0], 64 * times) {
                            assert_eq!(bytes[y * boxed[0] as usize + x], value, "t {times}, k {k}, ({x}, {y})");
                        }
                    }
                }
            }
        }
    }
}

// 유저 2026-08-28: 「줌인하면 텍스트는 선명하게 보고싶다」 — the average of one
// pixel is that pixel, so a word the app does not narrow keeps the raster.
#[test]
fn a_word_neither_narrowed_nor_rastered_over_is_its_raster_byte_for_byte() {
    for size in [12.0, 13.0, 20.0] {
        for dpr in [1.0, 1.5, 2.0] {
            let (shapes, box_) = word(size, false);
            let whole = baked(&shapes, box_, dpr, 1, [64, 64]);
            let to_box = Affine { a: dpr as f32, b: 0.0, c: 0.0, d: dpr as f32, e: 1.0, f: 1.0 };
            let raster = covered(faces(), &shapes, Paint::Fill, to_box).expect("the word has ink");
            let straight: Vec<u8> = (0..whole.height as i32)
                .flat_map(|y| (0..whole.width as i32).map(move |x| (x, y)))
                .map(|(x, y)| raster.byte(x, y))
                .collect();
            assert!(ink_of(&whole).sum > 0.0, "LIVENESS {size} px at {dpr}");
            assert_eq!(whole.bytes, straight, "{size} px at {dpr}");
        }
    }
}

// F-297 (유저 2026-10-05): 「3a로 글자가 폭이 부족해서 가로 짧아진다거나
// 할때, 글자의 세로길이나 세로 중앙정렬이 이상해짐. 3a만 이상하게 중앙에서
// 위에존재하고. 게다가 약간 흐려지는?」 — a word narrowed ALONG its line
// stands on the rows its un-narrowed bake does, the names beside it.
#[test]
fn a_word_narrowed_along_its_line_stands_on_the_rows_it_stood_on() {
    for size in [9.0, 11.0, 12.0, 13.0] {
        for dpr in [1.0, 1.25, 1.5, 2.0] {
            for alone in [true, false] {
                let (shapes, box_) = word(size, alone);
                let times = times_for(size);
                let whole = ink_of(&baked(&shapes, box_, dpr, times, [64, 64]));
                for k in [54, 45, 32, 19] {
                    let narrow = baked(&shapes, box_, dpr, times, [k, 64]);
                    let fit = f64::from(k) / 64.0;
                    let why = format!("{} at {size} px ×{k}/64 at {dpr}", if alone { "3" } else { "3a" });
                    let tall = (box_[1] * dpr).ceil() as u32 + 2;
                    assert_eq!(
                        (narrow.width, narrow.height),
                        ((box_[0] * fit * dpr).ceil() as u32 + 2, tall),
                        "{why}: the box is the narrowed word and a pixel round"
                    );
                    let narrow = ink_of(&narrow);
                    assert_eq!(narrow.rows, whole.rows, "{why}: 「세로길이」");
                    assert!((narrow.cy - whole.cy).abs() < 0.01, "{why}: 「3a만 … 위에」 {} {}", narrow.cy, whole.cy);
                    assert!(((narrow.cx - 1.0) - (whole.cx - 1.0) * fit).abs() < 0.1, "{why}: along, narrower");
                    assert!((narrow.sum / (whole.sum * fit) - 1.0).abs() < 0.02, "{why}: as much ink as that");
                }
            }
        }
    }
}

#[test]
fn a_word_narrowed_down_its_line_alone_is_averaged_down_it() {
    let (shapes, box_) = word(12.0, false);
    let whole = ink_of(&baked(&shapes, box_, 1.0, 1, [64, 64]));
    let squat = baked(&shapes, box_, 1.0, 1, [64, 32]);
    assert_eq!((squat.width, squat.height), ((box_[0]).ceil() as u32 + 2, (box_[1] * 0.5).ceil() as u32 + 2));
    let squat = ink_of(&squat);
    assert!((squat.cx - whole.cx).abs() < 0.01, "along: left alone");
    assert!(((squat.cy - 1.0) - (whole.cy - 1.0) * 0.5).abs() < 0.1);
    assert!((squat.sum / (whole.sum * 0.5) - 1.0).abs() < 0.02);
}

// A block from a pixel before a 12 × 16 px box to a pixel after it.
#[test]
fn the_bake_keeps_a_pixel_of_margin_round_the_word_where_ink_hangs_past_it() {
    let block = [vec![Placed { at: IDENTITY, shape: Shape::Rect([-64, -64, 13 * 64, 17 * 64]) }]];
    for times in [1, 2] {
        let cover = baked(&block[0], [12.0, 16.0], 1.0, times, [64, 64]);
        assert_eq!((cover.width, cover.height), (14, 18));
        assert!(cover.bytes.iter().all(|&alpha| alpha == 255), "{times} times over: ink to every edge");
    }
    // Narrowed to a half, the margin pixel is half overhang and half what
    // lies past the raster, which is nothing: 64 · 32 · 255 / 64² = 127.5.
    let cover = baked(&block[0], [12.0, 16.0], 1.0, 1, [32, 64]);
    let row = &cover.bytes[..cover.width as usize];
    assert_eq!(cover.width, 8);
    assert_eq!((row[0], row[7]), (127, 127), "the margins before and after the word");
    assert!(row[1..7].iter().all(|&alpha| alpha == 255), "the word between them");
}

#[test]
fn a_word_past_what_the_bake_takes_is_refused_with_why() {
    let (shapes, box_) = word(12.0, false);
    for (times, narrowed) in [(0, [64, 64]), (65, [64, 64]), (1, [0, 64]), (1, [64, 65])] {
        assert!(bake(faces(), &shapes, 1.0, times, box_, narrowed).is_none());
        assert!(last_error().contains("each is 1 to 64"), "{}", last_error());
    }
    for (size, dpr) in [([0.0, 16.0], 1.0), ([12.0, -1.0], 1.0), (box_, 0.0), ([f64::INFINITY, 16.0], 1.0)] {
        assert!(bake(faces(), &shapes, dpr, 1, size, [64, 64]).is_none());
        assert!(last_error().contains("has no pixels"), "{}", last_error());
    }
    assert!(bake(faces(), &shapes, 1.0, 64, [2000.0, 16.0], [64, 64]).is_none());
    assert!(last_error().contains("a side is 65536 at most"), "{}", last_error());
}

#[test]
fn a_word_of_no_ink_is_its_box_of_nothing() {
    let space = [Placed {
        at: IDENTITY,
        shape: Shape::Letters(Run { size: 768, bold: false, italic: false, clusters: vec![Cluster { text: " ".into(), origin: [0, 768] }] }),
    }];
    let cover = baked(&space, [3.0, 15.0], 1.0, 1, [32, 64]);
    assert_eq!((cover.width, cover.height), (4, 17));
    assert!(cover.bytes.iter().all(|&alpha| alpha == 0));
}
