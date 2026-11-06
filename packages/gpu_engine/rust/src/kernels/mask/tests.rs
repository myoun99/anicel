//! The selection's mask finish on a real GPU, checked against what the
//! app's passes give by hand and against the ledger — never against a CPU
//! copy of them (`kernels/mod.rs` has why).

use std::sync::OnceLock;

use super::{Finish, MOST_FEATHER, Mask, MaskBox, MaskPasses};
use crate::device::Engine;
use crate::kernels::shared::words_buffer;
use crate::testing::{assert_pinned, first_engine, read_buffer};

struct Rig {
    engine: &'static Engine,
    passes: MaskPasses,
}

/// One device and one compile for every test here (blend's tests have
/// why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        Rig {
            engine,
            passes: MaskPasses::new(engine),
        }
    })
}

fn finish(grow: i32, feather: f64, anti_alias: bool) -> Finish {
    Finish {
        grow,
        feather,
        anti_alias,
    }
}

/// A mask read back: its box and its bytes, row after row, padding gone.
struct Finished {
    size: MaskBox,
    bytes: Vec<u8>,
}

impl Finished {
    fn at(&self, x: u32, y: u32) -> u8 {
        self.bytes[(y * self.size.width + x) as usize]
    }

    /// How many of its pixels are in.
    fn inside(&self) -> usize {
        self.bytes.iter().filter(|&&byte| byte != 0).count()
    }
}

/// The plane of `byte` at each pixel of `size`, as mask.wgsl lays it.
fn laid(size: MaskBox, byte: impl Fn(u32, u32) -> u8) -> Vec<u32> {
    let stride = size.width.div_ceil(4);
    let mut words = vec![0u32; (stride * size.height) as usize];
    for y in 0..size.height {
        for x in 0..size.width {
            let at = (y * stride + x / 4) as usize;
            words[at] |= u32::from(byte(x, y)) << (x % 4 * 8);
        }
    }
    words
}

/// A selection's mask: its plane over its box. The cel pixel verbs, the
/// lift and the executor's masked rows read theirs from here.
pub(crate) struct Masked {
    plane: wgpu::Buffer,
    at: (i32, i32),
    size: MaskBox,
}

impl Masked {
    pub(crate) fn mask(&self) -> Mask<'_> {
        Mask {
            plane: &self.plane,
            at: self.at,
            size: self.size,
        }
    }
}

/// The mask over `size` pixels from `at` whose byte at the canvas's pixel
/// (x, y) is `coverage(x, y)` — and 255 past the box in a row's last word,
/// which a pass must read as nothing all the same.
pub(crate) fn masked(
    at: (i32, i32),
    size: (u32, u32),
    coverage: impl Fn(i32, i32) -> u8,
) -> Masked {
    let mut words = Vec::new();
    for y in 0..size.1 as i32 {
        for word in 0..size.0.div_ceil(4) {
            let byte = |i: u32| match word * 4 + i {
                x if x < size.0 => u32::from(coverage(at.0 + x as i32, at.1 + y)),
                _ => 255,
            };
            words.push((0..4).fold(0, |packed, i| packed | byte(i) << (8 * i)));
        }
    }
    let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
    Masked {
        plane: words_buffer(first_engine(), "mask", &words, usage),
        at,
        size: MaskBox {
            width: size.0,
            height: size.1,
        },
    }
}

/// The mask of `byte` over `size` finished by `finish`, or none where it
/// was refused.
fn finished(size: MaskBox, finish: Finish, byte: impl Fn(u32, u32) -> u8) -> Option<Finished> {
    let Rig { engine, passes } = rig();
    let storage = wgpu::BufferUsages::STORAGE;
    let mask = words_buffer(engine, "mask in", &laid(size, byte), storage);
    let out = passes.selection(engine, &mask, size, finish)?;
    let read = read_buffer(engine, &out);
    let stride = (size.width.div_ceil(4) * 4) as usize;
    let bytes = read
        .chunks(stride)
        .take(size.height as usize)
        .flat_map(|row| &row[..size.width as usize])
        .copied()
        .collect();
    Some(Finished { size, bytes })
}

fn square(side: u32) -> MaskBox {
    MaskBox {
        width: side,
        height: side,
    }
}

/// A grow comes in a side at a time — a pixel two out is in after two
/// generations, a diagonal two sides away — and keeps the byte a pixel in
/// already had; the box's edge is no barrier.
#[test]
fn a_grow_comes_in_a_side_at_a_time() {
    let mask = finished(square(11), finish(2, 0.0, false), |x, y| match (x, y) {
        (5, 5) => 255,
        (1, 1) => 128,
        _ => 0,
    })
    .expect("grow");
    for (x, y) in [(5, 3), (6, 6), (7, 5), (0, 0), (3, 1), (2, 2)] {
        assert_eq!(mask.at(x, y), 255, "({x}, {y})");
    }
    for (x, y) in [(7, 6), (3, 2), (8, 5)] {
        assert_eq!(mask.at(x, y), 0, "({x}, {y})");
    }
    assert_eq!(mask.at(1, 1), 128);
    // 13 about the middle; 11 of the corner's 13 in the box.
    assert_eq!(mask.inside(), 24);
}

/// A shrink takes a pixel out where a side touches one out — past the box
/// is out, so its edge goes first, a row ending on a word's last byte too
/// — and keeps the byte of the rest.
#[test]
fn a_shrink_takes_the_sides_and_the_box_edge() {
    let size = MaskBox {
        width: 9,
        height: 7,
    };
    let mask = finished(size, finish(-1, 0.0, false), |x, y| match (x, y) {
        (4, 3) => 0,
        (6, 2) => 77,
        _ => 255,
    })
    .expect("shrink");
    for (x, y) in [(0, 3), (8, 0), (4, 6), (4, 2), (3, 3), (5, 3), (4, 4)] {
        assert_eq!(mask.at(x, y), 0, "({x}, {y})");
    }
    assert_eq!(mask.at(1, 1), 255);
    assert_eq!(mask.at(3, 2), 255);
    assert_eq!(mask.at(6, 2), 77);
    // The 7 × 5 inside the edge, less the hole and its four sides.
    assert_eq!(mask.inside(), 30);
    let whole = |_, _| 255;
    assert_eq!(finished(size, finish(-3, 0.0, false), whole).expect("three").inside(), 3);
    assert_eq!(finished(size, finish(-4, 0.0, false), whole).expect("four").inside(), 0);
    let words = MaskBox {
        width: 8,
        height: 3,
    };
    assert_eq!(finished(words, finish(-1, 0.0, false), whole).expect("words").inside(), 6);
}

/// The feather ramps a pixel in over its distance from the nearest one out
/// — 3 a side, 4 a corner, the box's edge at 3 — up to 3 a pixel of it,
/// rounded: at 2 pixels the edge's ring is 3 / 6 of 255, 128, and the
/// rest whole. At 2.5 about a hole, 3, 4, 6 and 7 are 102, 136, 204 and
/// 238 — the 6 two generations out — and whatever byte a pixel had, the
/// ramp is its byte. A feather too small for Q.8 makes every pixel in
/// whole.
#[test]
fn the_feather_ramps_in_from_the_edge_and_each_hole() {
    let edge = finished(square(9), finish(0, 2.0, false), |_, _| 255).expect("edge");
    for (x, y) in [(0, 0), (0, 4), (8, 8), (3, 8)] {
        assert_eq!(edge.at(x, y), 128, "({x}, {y})");
    }
    for (x, y) in [(1, 1), (4, 4), (7, 1)] {
        assert_eq!(edge.at(x, y), 255, "({x}, {y})");
    }
    let hole = finished(square(15), finish(0, 2.5, false), |x, y| match (x, y) {
        (7, 7) => 0,
        (11, 3) => 77,
        _ => 255,
    })
    .expect("hole");
    let cases = [
        ((7, 7), 0),
        ((8, 7), 102),
        ((8, 8), 136),
        ((9, 7), 204),
        ((7, 5), 204),
        ((9, 8), 238),
        ((10, 7), 255),
        ((0, 7), 102),
        ((1, 7), 204),
        ((2, 7), 255),
        ((11, 3), 255),
    ];
    for ((x, y), byte) in cases {
        assert_eq!(hole.at(x, y), byte, "({x}, {y})");
    }
    let small = finished(square(5), finish(0, 0.001, false), |x, y| {
        if (x, y) == (2, 2) { 77 } else { 255 }
    })
    .expect("small");
    assert!(small.bytes.iter().all(|&byte| byte == 255));
}

/// A distance past a byte: feathered over 100 pixels, the middle of a
/// whole 181-pixel square lies 3 + 90 · 3 from out — 273 of the ramp's
/// 300 · 3, 232.
#[test]
fn a_wide_feather_ramps_over_distances_past_a_byte() {
    let mask = finished(square(181), finish(0, 100.0, false), |_, _| 255).expect("wide");
    assert_eq!(mask.at(90, 90), 232);
}

/// The soften is (3 · centre + sides) / 7 where the sides differ — 182 at
/// a square's corner, 219 mid side — and never lights a pixel out: one
/// beside the square stays 0, where the unclamped soften would be 36.
#[test]
fn the_soften_keeps_inside_its_outline() {
    let mask = finished(square(9), finish(0, 0.0, true), |x, y| {
        if (3..=5).contains(&x) && (3..=5).contains(&y) { 255 } else { 0 }
    })
    .expect("soften");
    assert_eq!(mask.at(3, 3), 182);
    assert_eq!(mask.at(5, 5), 182);
    assert_eq!(mask.at(4, 3), 219);
    assert_eq!(mask.at(3, 4), 219);
    assert_eq!(mask.at(4, 4), 255);
    assert_eq!(mask.at(2, 4), 0);
    assert_eq!(mask.inside(), 9);
}

/// Grow, feather, soften — in that order: one pixel grown to a plus, its
/// arms 3 from out and its middle 4, feathered over 1.5 pixels (170 and
/// 227), then softened (105 and 194).
#[test]
fn the_finish_grows_then_feathers_then_softens() {
    let mask = finished(square(9), finish(1, 1.5, true), |x, y| {
        if (x, y) == (4, 4) { 255 } else { 0 }
    })
    .expect("finish");
    assert_eq!(mask.at(4, 4), 194);
    for (x, y) in [(3, 4), (5, 4), (4, 3), (4, 5)] {
        assert_eq!(mask.at(x, y), 105, "({x}, {y})");
    }
    assert_eq!(mask.inside(), 5);
}

/// The widest feather it takes ramps a small mask out to nothing — over
/// as many generations as the box is long, not one a pixel of feather.
#[test]
fn the_widest_feather_is_taken() {
    let widest = finish(0, MOST_FEATHER - 1.0, false);
    let mask = finished(square(9), widest, |_, _| 255).expect("widest");
    assert_eq!(mask.inside(), 0);
}

#[test]
fn a_mask_past_its_range_is_refused() {
    let Rig { engine, passes } = rig();
    let size = square(8);
    let storage = wgpu::BufferUsages::STORAGE;
    let mask = words_buffer(engine, "mask in", &laid(size, |_, _| 255), storage);
    let refused = [
        (MaskBox { width: 0, height: 8 }, finish(1, 0.0, false)),
        (MaskBox { width: 8, height: 0 }, finish(1, 0.0, false)),
        (square(9), finish(1, 0.0, false)),
        (size, finish(0, 0.0, false)),
        (size, finish(0, -2.0, false)),
        (size, finish(0, f64::NAN, false)),
        (size, finish(0, MOST_FEATHER, false)),
    ];
    for (size, finish) in refused {
        assert!(passes.selection(engine, &mask, size, finish).is_none(), "{size:?} {finish:?}");
    }
}

// ---- The gap close's distances ----

/// The distances from the pixels of `byte` over `size` whose byte is
/// `zero_when`, relaxed `generations` times, row after row, padding gone.
fn measured(
    size: MaskBox,
    zero_when: u8,
    generations: u32,
    byte: impl Fn(u32, u32) -> u8,
) -> Vec<Vec<u16>> {
    let Rig { engine, passes } = rig();
    let storage = wgpu::BufferUsages::STORAGE;
    let mask = words_buffer(engine, "mask in", &laid(size, byte), storage);
    let out = passes.distances(engine, &mask, size, zero_when, generations).expect("distances");
    let read = read_buffer(engine, &out);
    let stride = (size.width.div_ceil(2) * 4) as usize;
    read.chunks(stride)
        .take(size.height as usize)
        .map(|row| {
            row.chunks_exact(2)
                .take(size.width as usize)
                .map(|half| u16::from_le_bytes([half[0], half[1]]))
                .collect()
        })
        .collect()
}

fn row(bytes: &'static [u8]) -> (MaskBox, impl Fn(u32, u32) -> u8) {
    let size = MaskBox {
        width: bytes.len() as u32,
        height: 1,
    };
    (size, move |x: u32, _| bytes[x as usize])
}

/// Past the box is no neighbour: the row's last pixel reads no distance
/// in its word's other half, and the box's edge starts none of its own.
#[test]
fn a_gap_close_distance_reads_nothing_past_the_box() {
    let (size, bytes) = row(&[0, 255, 255]);
    assert_eq!(measured(size, 0, 2, bytes), [[0, 3, 6]]);
}

/// It is measured from the byte it is told — from what may not fill, then
/// from what flooded.
#[test]
fn a_distance_is_measured_from_the_byte_it_names() {
    let (size, bytes) = row(&[255, 0, 0, 7]);
    assert_eq!(measured(size, 255, 3, &bytes), [[0, 3, 6, 9]]);
    assert_eq!(measured(size, 0, 3, bytes), [[3, 0, 0, 3]]);
}

/// A side is 3 and a corner 4.
#[test]
fn a_corner_is_a_step_of_4() {
    let mask = measured(square(3), 0, 1, |x, y| if (x, y) == (1, 1) { 0 } else { 255 });
    assert_eq!(mask, [[4, 3, 4], [3, 0, 3], [4, 3, 4]]);
}

/// A generation settles a pixel more: past them, a distance is still the
/// farthest, no nearer than the app's — and past the box's longer side
/// every one has settled, however many are asked for.
#[test]
fn a_distance_settles_a_pixel_a_generation() {
    let (size, bytes) = row(&[0, 9, 9, 9, 9]);
    assert_eq!(measured(size, 0, 2, &bytes), [[0, 3, 6, 60000, 60000]]);
    assert_eq!(measured(size, 0, u32::MAX, bytes), [[0, 3, 6, 9, 12]]);
}

// ---- The ledger ----

/// Two discs and a stripe of lines, a few bytes partly in, over a box whose
/// rows end mid word.
fn pattern(x: u32, y: u32) -> u8 {
    let (x, y) = (x as i32, y as i32);
    let disc = |cx: i32, cy: i32, r: i32| (x - cx).pow(2) + (y - cy).pow(2) < r * r;
    if (x * 7 + y * 3) % 23 == 0 {
        return 96;
    }
    if disc(20, 20, 15) || disc(42, 26, 12) || (x + 2 * y) % 17 == 0 {
        255
    } else {
        0
    }
}

#[test]
fn every_device_finishes_the_pinned_masks() {
    let size = MaskBox {
        width: 61,
        height: 47,
    };
    let finishes = [
        finish(3, 0.0, false),
        finish(-2, 0.0, false),
        finish(0, 4.25, false),
        finish(2, 3.0, true),
        finish(-1, 0.0, true),
    ];
    let bytes: Vec<u8> = finishes
        .into_iter()
        .flat_map(|finish| finished(size, finish, pattern).expect("finish").bytes)
        .collect();
    assert_pinned("mask/selection-finish", &bytes);
}
