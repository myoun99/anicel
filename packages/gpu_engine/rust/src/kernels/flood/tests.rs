//! A bucket fill's reach on a real GPU, checked against what the app's fill
//! reaches by hand and against the ledger — never against a CPU copy of it
//! (`kernels/mod.rs` has why).

use std::sync::OnceLock;

use super::{Bounds, Extent, Flood, Flooded, Picture};
use crate::device::Engine;
use crate::kernels::composite::TILE;
use crate::kernels::shared::words_buffer;
use crate::testing::{assert_pinned, first_engine, read_buffer};

struct Rig {
    engine: &'static Engine,
    flood: Flood,
}

/// One device and one compile for every test here (blend's tests have
/// why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        Rig {
            engine,
            flood: Flood::new(engine),
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
    (across, down): (u32, u32),
    inside: Extent,
    colour: impl Fn(u32, u32) -> Rgba,
    seed: (u32, u32),
    tolerance: u32,
) -> Filled {
    let Rig { engine, flood } = rig();
    let tiles = tiles(engine, (across, down), colour);
    let picture = Picture {
        tiles: &tiles,
        across,
        down,
        inside,
    };
    let Flooded {
        filled,
        stride,
        bounds,
    } = flood.region(engine, &picture, seed, tolerance).expect("a flood");
    let bytes = read_buffer(engine, &filled);
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

#[test]
fn diagonal_neighbours_never_join() {
    let colour = |x: u32, y: u32| if (x + y) % 2 == 0 { [9, 9, 9, 255] } else { [200, 9, 9, 255] };
    // A seed in each of a tile row's four words.
    for seed in [(127, 127), (128, 128), (0, 255), (200, 61), (45, 3)] {
        let filled = flood((2, 2), colour, seed, 0);
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
    let Rig { engine, flood } = rig();
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
