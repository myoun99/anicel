//! The lens blur's row sums on a real GPU, checked against the ledger and
//! against what the light gives by hand — never against a CPU copy of it
//! (`kernels/mod.rs` has why). Every hand case is worked on the 16-bit
//! premultiplied scale, as light.wgsl's head lays it out.

use std::sync::OnceLock;

use super::super::TileRect;
use super::super::pictures::{LEDGER_TILES, ONE_TILE, WHITE, pattern, tiles};
use super::{LensSums, Light, MOST_GAIN};
use crate::device::Engine;
use crate::kernels::effects::tests::rgba;
use crate::testing::{assert_pinned, first_engine, read_buffer};

struct Rig {
    engine: &'static Engine,
    sums: LensSums,
}

/// One device and one compiled pass for every test here (blend's tests
/// have why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        Rig {
            engine,
            sums: LensSums::new(engine),
        }
    })
}

/// The sums a lens blur read over its picture.
struct Sums {
    picture: [i32; 4],
    words: Vec<u32>,
}

impl Sums {
    /// The sum of row `y` up to pixel `x`: red, green, blue, alpha.
    fn at(&self, x: i32, y: i32) -> [u64; 4] {
        let [left, top, right, _] = self.picture;
        let at = (((y - top) * (right - left) + x - left) * 8) as usize;
        [0, 1, 2, 3].map(|c| {
            u64::from(self.words[at + c * 2]) | u64::from(self.words[at + c * 2 + 1]) << 32
        })
    }
}

/// `rect`'s tiles holding `pixel`, summed over `picture` in `light` —
/// `None` where the sums refused them.
fn sums(
    rect: TileRect,
    picture: [i32; 4],
    light: Light,
    pixel: impl Fn(i32, i32) -> u32,
) -> Option<Sums> {
    let Rig { engine, sums } = rig();
    let out = sums.run(engine, &tiles(engine, rect, pixel), rect, picture, light)?;
    let words = read_buffer(engine, &out)
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
        .collect();
    Some(Sums { picture, words })
}

/// What one `word` alone reads as in `light`: the sum at the only pixel.
fn read(word: u32, light: Light) -> [u64; 4] {
    sums(ONE_TILE, [60, 60, 61, 61], light, |_, _| word).expect("sums").at(60, 60)
}

fn light(gain: f64, threshold: f64, saturation: f64, linear: bool) -> Light {
    Light {
        gain,
        threshold,
        saturation,
        linear,
    }
}

const TWO_TILES: TileRect = TileRect {
    x0: 0,
    y0: 0,
    columns: 2,
    rows: 1,
};

const W: u64 = 65535;

/// White on a picture four runs wide, red all round it: each pixel's sum
/// is the white up to it from the picture's left — across every run, and
/// none of the red.
#[test]
fn a_row_sums_up_to_each_pixel_across_its_runs() {
    let picture = [3, 10, 250, 12];
    let blurred = sums(TWO_TILES, picture, Light::STORED, |x, y| {
        if (3..250).contains(&x) && (10..12).contains(&y) {
            WHITE
        } else {
            rgba(255, 0, 0, 255)
        }
    })
    .expect("sums");
    for y in [10, 11] {
        for x in [3, 66, 67, 130, 131, 194, 195, 249] {
            let n = (x - 2) as u64;
            assert_eq!(blurred.at(x, y), [n * W; 4], "({x}, {y})");
        }
    }
}

/// Each row its own: white at every (y + 1)-th pixel, so row y's sum at x
/// is ⌊x / (y + 1)⌋ + 1 whites.
#[test]
fn each_row_sums_alone() {
    let picture = [0, 0, 256, 3];
    let blurred = sums(TWO_TILES, picture, Light::STORED, |x, y| {
        if x % (y + 1) == 0 { WHITE } else { 0 }
    })
    .expect("sums");
    for y in 0..3 {
        for x in [0, 63, 64, 127, 128, 191, 192, 255] {
            let n = (x / (y + 1) + 1) as u64;
            assert_eq!(blurred.at(x, y), [n * W; 4], "({x}, {y})");
        }
    }
}

/// White at the most gain: 101 · 65535 a channel, so a row of 768 passes
/// 2^32 — carried into the high word, run to run.
#[test]
fn a_boosted_row_sums_past_a_word() {
    let rect = TileRect {
        x0: 0,
        y0: 0,
        columns: 6,
        rows: 1,
    };
    let boosted = light(MOST_GAIN, 0.0, 0.0, false);
    let blurred = sums(rect, [0, 0, 768, 1], boosted, |_, _| WHITE).expect("sums");
    for x in [0, 63, 64, 649, 767] {
        let n = (x + 1) as u64;
        let colour = n * 101 * W;
        assert_eq!(blurred.at(x, 0), [colour, colour, colour, n * W], "{x}");
    }
}

/// Read as stored, a pixel is premultiplied as the other blurs read it:
/// half-clear red is 32896 red over 32896.
#[test]
fn as_stored_a_pixel_is_premultiplied() {
    assert_eq!(read(rgba(255, 0, 0, 128), Light::STORED), [32896, 0, 0, 32896]);
    assert_eq!(read(rgba(255, 255, 255, 0), light(100.0, 0.0, 1.0, true)), [0; 4]);
}

/// In linear light a byte is sRGB's curve: 128 is 14146 of 65535, 1 is 20,
/// and the ends are themselves.
#[test]
fn linear_light_reads_through_srgb() {
    let linear = light(0.0, 1.0, 0.0, true);
    assert_eq!(read(rgba(128, 1, 255, 255), linear), [14146, 20, 65535, 65535]);
    assert_eq!(read(rgba(0, 0, 0, 255), linear), [0, 0, 0, 65535]);
}

/// White past a threshold of nothing, gain 1: t = 1 · 1 · 1, white tint, so
/// each channel doubles — and stays doubled premultiplied by half (65792 =
/// 131070 · 32896 / 65535).
#[test]
fn a_gain_boosts_a_light_past_the_threshold() {
    let gain = light(1.0, 0.0, 0.0, false);
    assert_eq!(read(WHITE, gain), [131070, 131070, 131070, 65535]);
    assert_eq!(read(rgba(255, 255, 255, 128), gain), [65792, 65792, 65792, 32896]);
}

/// Grey 128 has luma 32896: a threshold there boosts nothing, one under it
/// boosts by t = round(32896 · 1 / 65535) = 1.
#[test]
fn only_a_luma_past_the_threshold_is_boosted() {
    let grey = rgba(128, 128, 128, 255);
    let at = |threshold: f64| read(grey, light(1.0, threshold / 65535.0, 0.0, false));
    assert_eq!(at(32896.0), [32896, 32896, 32896, 65535]);
    assert_eq!(at(32895.0), [32897, 32897, 32897, 65535]);
}

/// Red, gain 2, threshold 0: luma 13933, t = 5924. White tint (saturation
/// 0) gives each channel 5924; its own colour (saturation 1) gives red
/// 65535 / 13933 of it — 27864 — and green and blue none.
#[test]
fn the_saturation_tints_the_boost_by_its_own_colour() {
    let red = rgba(255, 0, 0, 255);
    assert_eq!(read(red, light(2.0, 0.0, 0.0, false)), [71459, 5924, 5924, 65535]);
    assert_eq!(read(red, light(2.0, 0.0, 1.0, false)), [93399, 0, 0, 65535]);
}

#[test]
fn a_light_past_its_range_is_refused() {
    let refused = [
        light(MOST_GAIN + 0.5, 0.0, 0.0, false),
        light(-1.0, 0.0, 0.0, false),
        light(1.0, 1.5, 0.0, false),
        light(1.0, 0.0, -0.1, false),
        light(f64::NAN, 0.0, 0.0, false),
    ];
    for light in refused {
        assert!(sums(ONE_TILE, [0, 0, 8, 8], light, |_, _| WHITE).is_none(), "{light:?}");
    }
}

/// The tiles of one where the rectangle says two: every blur's runner
/// refuses them before it reads a word.
#[test]
fn tiles_short_of_their_rectangle_are_refused() {
    let Rig { engine, sums } = rig();
    let one = tiles(engine, ONE_TILE, |_, _| WHITE);
    assert!(sums.run(engine, &one, TWO_TILES, [0, 0, 200, 8], Light::STORED).is_none());
}

#[test]
fn a_picture_reaching_past_the_tiles_or_holding_nothing_is_refused() {
    for picture in [[-1, 0, 10, 10], [0, 0, 129, 10], [5, 5, 5, 10], [5, 9, 9, 8]] {
        assert!(
            sums(ONE_TILE, picture, Light::STORED, |_, _| WHITE).is_none(),
            "{picture:?}"
        );
    }
}

// ---- The ledger ----

/// As stored and in linear light, a soft boost and the hardest, on the
/// whole tiles and inside them.
fn scenes() -> Vec<([i32; 4], Light)> {
    let whole = LEDGER_TILES.pixels();
    vec![
        (whole, Light::STORED),
        ([-100, 10, 250, 200], light(0.0, 1.0, 0.0, true)),
        (whole, light(37.5, 0.25, 0.6, true)),
        ([-128, 3, 129, 256], light(MOST_GAIN, 0.0, 1.0, false)),
    ]
}

#[test]
fn every_device_sums_the_pinned_picture() {
    let bytes: Vec<u8> = scenes()
        .into_iter()
        .flat_map(|(picture, light)| {
            sums(LEDGER_TILES, picture, light, pattern).expect("sums").words
        })
        .flat_map(|word| word.to_le_bytes())
        .collect();
    assert_pinned("effects/lens-sums", &bytes);
}
