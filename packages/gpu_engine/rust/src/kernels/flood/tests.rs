//! A bucket fill's reach on a real GPU, checked against what the app's fill
//! reaches by hand and against the ledger — never against a CPU copy of it
//! (`kernels/mod.rs` has why).

use std::sync::OnceLock;

use super::{Bounds, Extent, Finished, Flood, Flooded, MOST_GAP, Picture};
use crate::device::Engine;
use crate::kernels::composite::TILE;
use crate::kernels::mask::MaskPasses;
use crate::kernels::shared::words_buffer;
use crate::testing::{assert_pinned, first_engine, read_buffer};

pub(super) struct Rig {
    pub(super) engine: &'static Engine,
    pub(super) flood: Flood,
    pub(super) masks: MaskPasses,
}

/// One device and one compile for every test here, the stamp's and the
/// picture's (blend's tests have why).
pub(super) fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        Rig {
            engine,
            flood: Flood::new(engine),
            masks: MaskPasses::new(engine),
        }
    })
}

/// A straight RGBA8 pixel.
type Rgba = [u8; 4];

const WALL: Rgba = [255, 255, 255, 255];

/// A grid of `across` × `down` tiles of `colour` at each pixel, laid as the
/// composite lays its output tiles.
fn tiles(
    engine: &Engine,
    (across, down): (u32, u32),
    colour: impl Fn(u32, u32) -> Rgba,
) -> wgpu::Buffer {
    let mut words = vec![0u32; (across * down * TILE * TILE) as usize];
    for y in 0..down * TILE {
        for x in 0..across * TILE {
            let tile = (y / TILE) * across + x / TILE;
            let texel = (y % TILE) * TILE + x % TILE;
            words[(tile * TILE * TILE + texel) as usize] = u32::from_le_bytes(colour(x, y));
        }
    }
    words_buffer(engine, "flood picture", &words, wgpu::BufferUsages::STORAGE)
}

/// A flood read back: which pixels it filled, and its box.
struct Filled {
    words: Vec<u32>,
    stride: u32,
    bounds: Bounds,
}

impl Filled {
    fn at(&self, x: u32, y: u32) -> bool {
        self.words[(y * self.stride + x / 32) as usize] >> (x % 32) & 1 == 1
    }

    fn count(&self) -> u32 {
        self.words.iter().map(|word| word.count_ones()).sum()
    }
}

/// What a fill seeded at `seed` reaches over the whole of a grid of
/// `grid` tiles of `colour`.
fn flood(
    grid: (u32, u32),
    colour: impl Fn(u32, u32) -> Rgba,
    seed: (u32, u32),
    tolerance: u32,
) -> Filled {
    let whole = Extent {
        left: 0,
        top: 0,
        right: grid.0 * TILE,
        bottom: grid.1 * TILE,
    };
    flood_inside(grid, whole, colour, seed, tolerance)
}

fn flood_inside(
    grid: (u32, u32),
    inside: Extent,
    colour: impl Fn(u32, u32) -> Rgba,
    seed: (u32, u32),
    tolerance: u32,
) -> Filled {
    read_back(flooded(grid, inside, colour, seed, tolerance))
}

fn read_back(flooded: Flooded) -> Filled {
    let Flooded {
        filled,
        stride,
        bounds,
        ..
    } = flooded;
    let bytes = read_buffer(rig().engine, &filled);
    let words = bytes
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
        .collect();
    Filled {
        words,
        stride,
        bounds,
    }
}

/// What a fill seeded at `seed` that closes gaps of `gap` pixels reaches
/// over the whole of a grid of `grid` tiles of `colour`, or none where it
/// was refused.
fn gap_closed(
    grid: (u32, u32),
    colour: impl Fn(u32, u32) -> Rgba,
    seed: (u32, u32),
    tolerance: u32,
    gap: u32,
) -> Option<Filled> {
    let whole = extent(0, 0, grid.0 * TILE, grid.1 * TILE);
    gap_closed_inside(grid, whole, colour, seed, tolerance, gap)
}

fn gap_closed_inside(
    (across, down): (u32, u32),
    inside: Extent,
    colour: impl Fn(u32, u32) -> Rgba,
    seed: (u32, u32),
    tolerance: u32,
    gap: u32,
) -> Option<Filled> {
    let Rig { engine, flood, masks } = rig();
    let tiles = tiles(engine, (across, down), colour);
    let picture = Picture {
        tiles: &tiles,
        across,
        down,
        inside,
    };
    let flooded = flood.gap_closed(engine, masks, &picture, seed, tolerance, gap)?;
    Some(read_back(flooded))
}

fn flooded(
    (across, down): (u32, u32),
    inside: Extent,
    colour: impl Fn(u32, u32) -> Rgba,
    seed: (u32, u32),
    tolerance: u32,
) -> Flooded {
    let Rig { engine, flood, .. } = rig();
    let tiles = tiles(engine, (across, down), colour);
    let picture = Picture {
        tiles: &tiles,
        across,
        down,
        inside,
    };
    flood.region(engine, &picture, seed, tolerance).expect("a flood")
}

/// A finished fill read back: its crop, and its mask's bytes row after
/// row, padding gone.
fn finished(
    grid: (u32, u32),
    colour: impl Fn(u32, u32) -> Rgba,
    seed: (u32, u32),
    tolerance: u32,
    (expand, anti_alias): (u32, bool),
) -> (Extent, Vec<Vec<u8>>) {
    let whole = extent(0, 0, grid.0 * TILE, grid.1 * TILE);
    finished_inside(grid, whole, colour, seed, tolerance, (expand, anti_alias))
}

fn finished_inside(
    grid: (u32, u32),
    inside: Extent,
    colour: impl Fn(u32, u32) -> Rgba,
    seed: (u32, u32),
    tolerance: u32,
    (expand, anti_alias): (u32, bool),
) -> (Extent, Vec<Vec<u8>>) {
    let Rig { engine, flood, masks } = rig();
    let flooded = flooded(grid, inside, colour, seed, tolerance);
    let Finished { mask, crop } =
        flood.finish(engine, masks, &flooded, expand, anti_alias).expect("a finish");
    let width = (crop.right - crop.left) as usize;
    let stride = width.div_ceil(4) * 4;
    let bytes = read_buffer(engine, &mask);
    let rows = (0..(crop.bottom - crop.top) as usize)
        .map(|row| bytes[row * stride..row * stride + width].to_vec())
        .collect();
    (crop, rows)
}

fn bounds(left: u32, right: u32, top: u32, bottom: u32) -> Bounds {
    Bounds {
        left,
        right,
        top,
        bottom,
    }
}

#[test]
fn one_colour_fills_every_tile() {
    let filled = flood((2, 2), |_, _| [40, 80, 120, 255], (5, 200), 0);
    assert_eq!(filled.count(), 256 * 256);
    assert_eq!(filled.bounds, bounds(0, 255, 0, 255));
}

#[test]
fn a_wall_stops_the_fill_on_either_side_of_a_tile_edge() {
    for wall in [127, 128, 150] {
        let colour = |x: u32, _| if x == wall { WALL } else { [0, 0, 0, 255] };
        let left = flood((2, 2), colour, (3, 250), 0);
        let right = flood((2, 2), colour, (255, 0), 0);
        for y in [0, 127, 128, 255] {
            for x in [0, wall - 1, wall, wall + 1, 255] {
                assert_eq!(left.at(x, y), x < wall, "wall {wall}, left, ({x}, {y})");
                assert_eq!(right.at(x, y), x > wall, "wall {wall}, right, ({x}, {y})");
            }
        }
        assert_eq!(left.count(), wall * 256, "wall {wall}");
        assert_eq!(left.bounds, bounds(0, wall - 1, 0, 255));
        assert_eq!(right.bounds, bounds(wall + 1, 255, 0, 255));
        let on_it = flood((2, 2), colour, (wall, 130), 0);
        assert_eq!(on_it.count(), 256, "wall {wall}: the wall's own column");
        assert_eq!(on_it.bounds, bounds(wall, wall, 0, 255));
    }
}

/// Which of `probes` a fill from a row of `seed` reaches, `tolerance` its
/// reach: each probe hangs below the row alone, walled on its other sides.
fn probed(seed: Rgba, probes: &[Rgba], tolerance: u32) -> Vec<bool> {
    let colour = |x: u32, y: u32| match y {
        0 => seed,
        1 if x % 2 == 0 && ((x / 2) as usize) < probes.len() => probes[(x / 2) as usize],
        _ => WALL,
    };
    let filled = flood((1, 1), colour, (TILE - 1, 0), tolerance);
    (0..probes.len() as u32).map(|k| filled.at(k * 2, 1)).collect()
}

#[test]
fn each_channel_lies_within_the_tolerance_or_stops_the_fill() {
    let seed = [100, 100, 100, 255];
    let mut probes = Vec::new();
    for channel in 0..3 {
        for step in [-11, -10, 10, 11] {
            let mut probe = seed;
            probe[channel] = (100 + step) as u8;
            probes.push(probe);
        }
    }
    let reached = probed(seed, &probes, 10);
    let hand: Vec<bool> = (0..12).map(|k| k % 4 == 1 || k % 4 == 2).collect();
    assert_eq!(reached, hand);
}

#[test]
fn alpha_lies_within_the_tolerance_or_stops_the_fill() {
    // Black premultiplies to itself, so only alpha differs.
    let probes = [[0, 0, 0, 117], [0, 0, 0, 118], [0, 0, 0, 138], [0, 0, 0, 139]];
    assert_eq!(probed([0, 0, 0, 128], &probes, 10), [false, true, true, false]);
}

#[test]
fn pixels_compare_premultiplied() {
    // Clear pixels of any colour are one premultiplied — the screen shows
    // them alike. A half-clear (255, 0, 0, 128) premultiplies to
    // (128, 0, 0, 128); (127, 0, 0, 128) and (128, 0, 0, 128) both to
    // (64, 0, 0, 128), as 16256 and 16384 over 255 both round to 64.
    let probes = [[255, 0, 0, 0], [0, 255, 9, 0], [255, 0, 0, 128], [127, 0, 0, 128]];
    assert_eq!(probed([0, 0, 255, 0], &probes, 0), [true, true, false, false]);
    assert_eq!(probed([128, 0, 0, 128], &probes[2..], 0), [false, true]);
    assert_eq!(probed([255, 0, 0, 128], &probes[2..], 63), [true, false]);
    assert_eq!(probed([255, 0, 0, 128], &probes[2..], 64), [true, true]);
}

/// Squares of two colours a pixel each: a fill within 0 fills its seed
/// alone.
fn checker(x: u32, y: u32) -> Rgba {
    if (x + y) % 2 == 0 { [9, 9, 9, 255] } else { [200, 9, 9, 255] }
}

#[test]
fn diagonal_neighbours_never_join() {
    // A seed in each of a tile row's four words.
    for seed in [(127, 127), (128, 128), (0, 255), (200, 61), (45, 3)] {
        let filled = flood((2, 2), checker, seed, 0);
        assert_eq!(filled.count(), 1, "{seed:?}");
        assert!(filled.at(seed.0, seed.1), "{seed:?}");
        assert_eq!(filled.bounds, bounds(seed.0, seed.0, seed.1, seed.1));
    }
}

/// A corridor through 3 × 3 tiles that turns at each end of every eighth
/// row — walls at rows 4, 12, 20 …, the gap at their right end, then their
/// left — so the fill crosses tile edges across, back and down, over more
/// rounds than a batch holds.
fn serpent(x: u32, y: u32) -> Rgba {
    let gap = if (y / 8) % 2 == 0 { x >= 3 * TILE - 4 } else { x < 4 };
    if y % 8 == 4 && !gap { WALL } else { [30, 60, 90, 255] }
}

#[test]
fn a_winding_corridor_fills_whole_from_either_end() {
    let open = (0..3 * TILE)
        .flat_map(|y| (0..3 * TILE).map(move |x| (x, y)))
        .filter(|&(x, y)| serpent(x, y) != WALL)
        .count() as u32;
    for seed in [(0, 0), (3 * TILE - 1, 3 * TILE - 1)] {
        let filled = flood((3, 3), serpent, seed, 0);
        assert_eq!(filled.count(), open, "{seed:?}");
        for y in 0..3 * TILE {
            for x in 0..3 * TILE {
                assert_eq!(filled.at(x, y), serpent(x, y) != WALL, "{seed:?}: ({x}, {y})");
            }
        }
        assert_eq!(filled.bounds, bounds(0, 3 * TILE - 1, 0, 3 * TILE - 1));
    }
}

#[test]
fn nothing_past_the_picture_s_box_fills() {
    let inside = Extent {
        left: 3,
        top: 5,
        right: 200,
        bottom: 100,
    };
    let filled = flood_inside((2, 1), inside, |_, _| [0, 0, 0, 0], (100, 50), 0);
    assert_eq!(filled.count(), 197 * 95);
    assert_eq!(filled.bounds, bounds(3, 199, 5, 99));
    assert!(filled.at(3, 5) && filled.at(199, 99));
    assert!(!filled.at(2, 50) && !filled.at(200, 50) && !filled.at(100, 4) && !filled.at(100, 100));
}

#[test]
fn a_seed_off_the_box_or_a_box_off_the_grid_is_refused() {
    let Rig { engine, flood, .. } = rig();
    let tiles = tiles(engine, (1, 1), |_, _| [0, 0, 0, 255]);
    let picture = |left, top, right, bottom| Picture {
        tiles: &tiles,
        across: 1,
        down: 1,
        inside: Extent {
            left,
            top,
            right,
            bottom,
        },
    };
    assert!(flood.region(engine, &picture(10, 10, 20, 20), (9, 15), 0).is_none());
    assert!(flood.region(engine, &picture(10, 10, 20, 20), (20, 15), 0).is_none());
    assert!(flood.region(engine, &picture(10, 10, 20, 20), (15, 20), 0).is_none());
    assert!(flood.region(engine, &picture(0, 0, 129, 128), (5, 5), 0).is_none());
    assert!(flood.region(engine, &picture(0, 0, 128, 129), (5, 5), 0).is_none());
    assert!(flood.region(engine, &picture(10, 10, 10, 20), (10, 15), 0).is_none());
    let short = Picture {
        across: 2,
        ..picture(0, 0, 128, 128)
    };
    assert!(flood.region(engine, &short, (5, 5), 0).is_none());
    assert!(flood.region(engine, &picture(10, 10, 20, 20), (19, 19), 0).is_some());
}

/// Patches of a few colours, each a hash of its 8 × 8 cell, near enough
/// under some tolerances to join and not under others.
fn patches(x: u32, y: u32) -> Rgba {
    let cell = (x / 8).wrapping_mul(0x9e37_79b9) ^ (y / 8).wrapping_mul(0x85eb_ca6b);
    let mixed = cell ^ (cell >> 15);
    let level = (mixed % 5) as u8 * 6;
    [100 + level, 100, 100 - level, 255 - (mixed >> 8) as u8 % 3]
}

#[test]
fn every_device_floods_the_pinned_regions() {
    let mut bytes = Vec::new();
    for (seed, tolerance) in [((0, 0), 6), ((200, 130), 12), ((0, 0), 13)] {
        let filled = flood((3, 2), patches, seed, tolerance);
        bytes.extend(filled.words.iter().flat_map(|word| word.to_le_bytes()));
        let Bounds {
            left,
            right,
            top,
            bottom,
        } = filled.bounds;
        bytes.extend([left, right, top, bottom].iter().flat_map(|word| word.to_le_bytes()));
    }
    assert_pinned("flood/patches", &bytes);
}

fn extent(left: u32, top: u32, right: u32, bottom: u32) -> Extent {
    Extent {
        left,
        top,
        right,
        bottom,
    }
}

#[test]
fn an_expand_grows_a_lone_pixel_a_diamond_a_generation_at_a_time() {
    let (crop, rows) = finished((2, 2), checker, (200, 61), 0, (2, false));
    assert_eq!(crop, extent(198, 59, 203, 64));
    let within = |x: i32, y: i32| (x - 2).abs() + (y - 2).abs() <= 2;
    let hand: Vec<Vec<u8>> =
        (0..5).map(|y| (0..5).map(|x| if within(x, y) { 255 } else { 0 }).collect()).collect();
    assert_eq!(rows, hand);
}

#[test]
fn the_fill_s_ramp_spreads_a_pixel_past_its_outline() {
    // (3 · 255 + 3) / 7 = 109 at the pixel and (255 + 3) / 7 = 36 beside it,
    // where the selection's soften would keep 0.
    let (crop, rows) = finished((2, 2), checker, (200, 61), 0, (0, true));
    assert_eq!(crop, extent(199, 60, 202, 63));
    assert_eq!(rows, [[0, 36, 0], [36, 109, 36], [0, 36, 0]]);
}

#[test]
fn an_expanded_fill_softens_over_what_it_grew() {
    // Grown once, the pixel and its four sides are in. Softened, a side is
    // (3 · 255 + 255 + 3) / 7 = 146, a pixel between two sides
    // (2 · 255 + 3) / 7 = 73, one past a side 36, and the pixel itself
    // (7 · 255 + 3) / 7 = 255.
    let (crop, rows) = finished((2, 2), checker, (200, 61), 0, (1, true));
    assert_eq!(crop, extent(198, 59, 203, 64));
    let hand = [
        [0, 0, 36, 0, 0],
        [0, 73, 146, 73, 0],
        [36, 146, 255, 146, 36],
        [0, 73, 146, 73, 0],
        [0, 0, 36, 0, 0],
    ];
    assert_eq!(rows, hand);
}

#[test]
fn a_fill_is_finished_inside_the_picture_s_box() {
    // At a corner of the grid the crop is cut at its edges, and past them
    // there is nothing to grow from or soften with: the pixel itself is
    // (3 · 255 + 2 · 255 + 3) / 7 = 182.
    let (crop, rows) = finished((2, 2), checker, (0, 0), 0, (1, true));
    assert_eq!(crop, extent(0, 0, 3, 3));
    assert_eq!(rows, [[182, 146, 36], [146, 73, 0], [36, 0, 0]]);
    let (crop, rows) = finished((2, 2), checker, (255, 255), 0, (1, true));
    assert_eq!(crop, extent(253, 253, 256, 256));
    assert_eq!(rows, [[0, 0, 36], [0, 73, 146], [36, 146, 182]]);
}

#[test]
fn a_fill_s_crop_stops_at_the_picture_s_box_wherever_it_lies() {
    let inside = extent(3, 5, 200, 100);
    let (crop, rows) = finished_inside((2, 1), inside, |_, _| [0; 4], (100, 50), 0, (1, false));
    assert_eq!(crop, inside);
    assert!(rows.iter().all(|row| row.iter().all(|&byte| byte == 255)));
}

#[test]
fn a_fill_neither_expanded_nor_anti_aliased_is_its_flood_cropped() {
    let colour = |x: u32, _| if x == 150 { WALL } else { [0, 0, 0, 255] };
    let (crop, rows) = finished((2, 2), colour, (3, 250), 0, (0, false));
    assert_eq!(crop, extent(0, 0, 150, 256));
    assert!(rows.iter().all(|row| row.iter().all(|&byte| byte == 255)));
}

// ---- The gap close ----
//
// By hand, a 3-4 chamfer distance over a step (dx, dy) is 3 · max + min.

/// Whether `filled` holds exactly the pixels `hand` names over one tile,
/// and their box.
fn assert_fills(filled: &Filled, hand: impl Fn(u32, u32) -> bool, box_: Bounds) {
    let mut count = 0;
    for y in 0..TILE {
        for x in 0..TILE {
            assert_eq!(filled.at(x, y), hand(x, y), "({x}, {y})");
            count += u32::from(hand(x, y));
        }
    }
    assert_eq!(filled.count(), count);
    assert_eq!(filled.bounds, box_);
}

/// A wall down column 60 with a gap at rows 60 and 61.
fn gapped_wall(x: u32, y: u32) -> Rgba {
    if x == 60 && y != 60 && y != 61 { WALL } else { [0, 0, 0, 255] }
}

/// What a gap of 2 fills left of [`gapped_wall`]: what floods lies past 6
/// from the wall — x ≤ 57, and (58, 60) and (58, 61), 3 · 2 + 1 = 7 from
/// its ends — and nothing in the gap's three columns does. Taken back
/// within 6 of that: x ≤ 59, and the gap's own two pixels, 6 from (58, 60)
/// and (58, 61); (61, 60) is 9.
fn left_of_the_gapped_wall(x: u32, y: u32) -> bool {
    x <= 59 || (x == 60 && (y == 60 || y == 61))
}

#[test]
fn a_gap_close_leaks_through_no_gap_narrower_than_its_reach() {
    let closed = gap_closed((1, 1), gapped_wall, (10, 10), 0, 2).expect("a gap close");
    assert_fills(&closed, left_of_the_gapped_wall, bounds(0, 60, 0, 127));
    let leaked = flood((1, 1), gapped_wall, (10, 10), 0);
    assert_eq!(leaked.count(), TILE * TILE - (TILE - 2));
}

#[test]
fn a_gap_close_measures_over_a_box_anywhere_of_any_width() {
    // A box off the grid's corner and a column short of its tile: its
    // distances lie from (1, 2), and a row of them ends mid word.
    let inside = extent(1, 2, TILE, TILE);
    let closed = gap_closed_inside((1, 1), inside, gapped_wall, (10, 10), 0, 2);
    let hand = |x, y| x >= 1 && y >= 2 && left_of_the_gapped_wall(x, y);
    assert_fills(&closed.expect("a gap close"), hand, bounds(1, 60, 2, 127));
}

#[test]
fn a_seed_by_a_line_halves_its_gap_until_it_floods() {
    // The seed lies 6 from the wall down column 10: a gap of 4 halves to 2
    // — 6 is not past 6 — and to 1, whose threshold 3 the seed lies past.
    // The wall's one-pixel gap at row 100 is closed at that: (9, 100) is
    // 4 from its ends and floods, the gap itself is 3 from it.
    let colour = |x: u32, y: u32| if x == 10 && y != 100 { WALL } else { [0, 0, 0, 255] };
    let closed = gap_closed((1, 1), colour, (8, 50), 0, 4).expect("a gap close");
    assert_fills(&closed, |x, y| x <= 9 || (x, y) == (10, 100), bounds(0, 10, 0, 127));
}

#[test]
fn the_canvas_edge_is_no_barrier_to_a_gap_close() {
    // A wall along row 64 from column 3 leaves three pixels at the edge:
    // (0, 64) lies 9 from the wall, past a gap of 2's 6, so the fill goes
    // through — as an edge at 3 would have closed it.
    let colour = |x: u32, y: u32| if y == 64 && x >= 3 { WALL } else { [0, 0, 0, 255] };
    let closed = gap_closed((1, 1), colour, (64, 10), 0, 2).expect("a gap close");
    assert_fills(&closed, |x, y| y != 64 || x < 3, bounds(0, 127, 0, 127));
}

#[test]
fn a_gap_of_0_floods_as_a_plain_fill() {
    for (seed, tolerance) in [((0, 0), 6), ((200, 130), 12)] {
        let plain = flood((3, 2), patches, seed, tolerance);
        let closed = gap_closed((3, 2), patches, seed, tolerance, 0).expect("a gap close");
        assert_eq!(closed.words, plain.words, "{seed:?} within {tolerance}");
        assert_eq!(closed.bounds, plain.bounds, "{seed:?} within {tolerance}");
    }
}

#[test]
fn a_gap_past_a_word_s_third_is_refused() {
    let colour = |_, _| [0, 0, 0, 255];
    assert!(gap_closed((1, 1), colour, (5, 5), 0, MOST_GAP + 1).is_none());
    let widest = gap_closed((1, 1), colour, (5, 5), 0, MOST_GAP).expect("the widest gap");
    assert_eq!(widest.count(), TILE * TILE);
}

#[test]
fn every_device_closes_the_pinned_gaps() {
    let mut bytes = Vec::new();
    for gap in [1, 3, 8] {
        let filled = gap_closed((3, 2), patches, (200, 130), 12, gap).expect("a gap close");
        bytes.extend(filled.words.iter().flat_map(|word| word.to_le_bytes()));
        let Bounds {
            left,
            right,
            top,
            bottom,
        } = filled.bounds;
        bytes.extend([left, right, top, bottom].iter().flat_map(|word| word.to_le_bytes()));
    }
    assert_pinned("flood/patches-gap-closed", &bytes);
}

#[test]
fn every_device_finishes_the_pinned_fill() {
    let (crop, rows) = finished((3, 2), patches, (200, 130), 12, (2, true));
    let Extent {
        left,
        top,
        right,
        bottom,
    } = crop;
    let corners = [left, top, right, bottom];
    let mut bytes: Vec<u8> = corners.iter().flat_map(|word| word.to_le_bytes()).collect();
    bytes.extend(rows.concat());
    assert_pinned("flood/patches-finished", &bytes);
}
