//! The Gaussian on a real GPU, checked against the ledger and against what
//! its weights give by hand — never against a CPU copy of the pass
//! (`kernels/mod.rs` has why). Every hand case is worked on the 16-bit
//! premultiplied scale: a pass's pixel its weights' sum rounded half up
//! once, then stored — alpha (a + 128) / 257, a colour over it.

use std::sync::OnceLock;

use super::super::pictures::{Blurred, LEDGER_TILES, ONE_TILE, WHITE, pattern, tiles, white};
use super::super::{TileRect, bands};
use super::{Blur, Edge, Gaussian, MOST_REACH, Way, planes, weights};
use crate::device::Engine;
use crate::kernels::composite::TILE_TEXELS;
use crate::kernels::effects::tests::rgba;
use crate::kernels::shared::room;
use crate::testing::{assert_pinned, first_engine};

struct Rig {
    engine: &'static Engine,
    blur: Gaussian,
}

/// One device and one compiled pass for every test here (blend's tests
/// have why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        Rig {
            engine,
            blur: Gaussian::new(engine),
        }
    })
}

/// The tiles of `rect` holding `pixel`, through `blur` in bands a binding
/// of `room` bytes holds — `None` where the blur refused them.
fn blur_in(
    rect: TileRect,
    blur: &Blur,
    pixel: impl Fn(i32, i32) -> u32,
    room: u64,
) -> Option<Blurred> {
    let Rig { engine, blur: gaussian } = rig();
    let out = gaussian.run_in(engine, &tiles(engine, rect, pixel), rect, blur, room)?;
    Some(Blurred::read(engine, rect, &out))
}

/// `blur_in`, on a binding of the device's.
fn blurred(rect: TileRect, blur: &Blur, pixel: impl Fn(i32, i32) -> u32) -> Option<Blurred> {
    blur_in(rect, blur, pixel, room(rig().engine))
}

/// A way of sigma 1 reaching 3: weights 26152 · 15862 · 3539 · 291 from
/// its middle (`the_weights_are_the_gaussian_s_in_integers`).
const ONE: Way = Way { sigma: 1.0, reach: 3 };
const NONE: Way = Way { sigma: 0.0, reach: 0 };

/// `across` and `down` over the whole of `rect`, nothing past it.
fn whole(rect: TileRect, across: Way, down: Way) -> Blur {
    Blur {
        across,
        down,
        picture: rect.pixels(),
        edge: Edge::Nothing,
        puts: rect.pixels(),
    }
}

/// 65535 at a pixel: its own weight and those either side, rounded — so
/// bytes 1 · 14 · 62 · 102 · 62 · 14 · 1 (26152 → 26152, (26152 + 128) /
/// 257 = 102).
const SPIKE: [u32; 7] = [1, 14, 62, 102, 62, 14, 1];

/// Sigma 1 reaching 3: e^(−i²/2) at 0 to 3 — 1, 0.6065, 0.1353, 0.0111 —
/// over their sum both sides, 2.50595, are 26152.16 · 15862.09 · 3539.31 ·
/// 290.52 of 65536. The floors sum to 65534 both sides: the pair of the
/// largest remainder, 0.52, takes the two left. Sigma ½ reaching 2:
/// 51548.70 · 6976.36 · 17.29, the floors 65534, 6976's pair the two.
/// Sigma 2 reaching 6: 13085.94 · 11548.30 · 7937.03 · 4248.38 · 1770.99 ·
/// 574.96 · 145.37, the floors 65529: the pairs of the largest remainders
/// — 0.99, 0.96, 0.38 — take six, and the middle the one left.
#[test]
fn the_weights_are_the_gaussian_s_in_integers() {
    assert_eq!(weights(1.0, 3), vec![26152, 15862, 3539, 291]);
    assert_eq!(weights(0.5, 2), vec![51548, 6977, 17]);
    assert_eq!(weights(2.0, 6), vec![13086, 11548, 7937, 4249, 1771, 575, 145]);
    // A sigma no pixel beside the middle holds a share of.
    assert_eq!(weights(0.05, 2), vec![65536, 0, 0]);
}

/// However far a way reaches, its weights sum to 65536 both sides and fall
/// away from the middle.
#[test]
fn every_way_s_weights_sum_whole_and_fall_from_the_middle() {
    for sigma in [0.3, 0.7, 1.3, 2.9, 7.5, 16.7, 50.0, 166.7] {
        for reach in [1, (3.0 * sigma) as u32, (3.0 * sigma) as u32 + 1] {
            let reach = reach.max(1);
            let weights = weights(sigma, reach);
            assert_eq!(weights.len(), reach as usize + 1, "{sigma} {reach}");
            let sum: u32 = weights[0] + 2 * weights[1..].iter().sum::<u32>();
            assert_eq!(sum, 65536, "{sigma} {reach}");
            assert!(weights.windows(2).all(|pair| pair[0] >= pair[1]), "{sigma} {reach}");
        }
    }
}

#[test]
fn one_pixel_spreads_along_its_row_by_the_weights() {
    let blur = whole(ONE_TILE, ONE, NONE);
    let blurred = blurred(ONE_TILE, &blur, |x, y| if (x, y) == (60, 60) { WHITE } else { 0 })
        .expect("blur");
    assert_eq!(blurred.row(60, 57..64), white(&SPIKE));
    assert_eq!(blurred.row(60, 56..57), vec![0]);
    // A way of no reach is left as it is.
    assert_eq!(blurred.row(59, 56..65), vec![0; 9]);
    assert_eq!(blurred.row(61, 56..65), vec![0; 9]);
}

#[test]
fn one_pixel_spreads_down_its_column_by_the_same_weights() {
    let blur = whole(ONE_TILE, NONE, ONE);
    let blurred = blurred(ONE_TILE, &blur, |x, y| if (x, y) == (60, 60) { WHITE } else { 0 })
        .expect("blur");
    assert_eq!(blurred.column(60, 57..64), white(&SPIKE));
    assert_eq!(blurred.column(59, 57..64), vec![0; 7]);
}

/// Both ways: the columns weigh the rows' 16-bit pixels, not their bytes —
/// 26152 at the middle goes to 26152 · 26152 / 65536 = 10436, byte 41; one
/// row off, 15862 · 26152 / 65536 = 6330, byte 25.
#[test]
fn the_columns_weigh_what_the_rows_left() {
    let blur = whole(ONE_TILE, ONE, ONE);
    let blurred = blurred(ONE_TILE, &blur, |x, y| if (x, y) == (60, 60) { WHITE } else { 0 })
        .expect("blur");
    let middle = white(&[0, 5, 25, 41, 25, 5, 0]);
    assert_eq!(blurred.column(60, 57..64), middle);
    assert_eq!(blurred.row(60, 57..64), middle);
    // One row off and along it, 6330 · 3839 · 857 · 70: bytes 25 · 15 · 3 · 0.
    assert_eq!(blurred.row(61, 57..64), white(&[0, 3, 15, 25, 15, 3, 0]));
}

/// Half-clear red over nothing: premultiplied, the nothing beside it
/// carries no colour, so what spreads stays red — only its alpha falls
/// (32896 to 13127 · 7962 · 1776 · 146, bytes 51 · 31 · 7 · 1).
#[test]
fn a_clear_neighbour_lends_no_colour() {
    let blur = whole(ONE_TILE, ONE, NONE);
    let blurred = blurred(ONE_TILE, &blur, |x, y| {
        if (x, y) == (60, 60) { rgba(255, 0, 0, 128) } else { 0 }
    })
    .expect("blur");
    let red: Vec<u32> = [1, 7, 31, 51, 31, 7, 1].iter().map(|&a| rgba(255, 0, 0, a)).collect();
    assert_eq!(blurred.row(60, 57..64), red);
}

/// White from x = 64 on, past the picture's left edge too — but the
/// picture starts there, and past it the blur reads nothing: x = 64 keeps
/// 26152 + 15862 + 3539 + 291 = 45844 of 65536 (45843, byte 178), 63 the
/// 19692 reaching in (77), 62 3830 (15), 61 291 (1), 60 none. The blur
/// puts from 60, and nothing left of it.
#[test]
fn past_its_picture_a_blur_reads_nothing_and_puts_past_it_as_far_as_asked() {
    let blur = Blur {
        across: ONE,
        down: NONE,
        picture: [64, 0, 128, 128],
        edge: Edge::Nothing,
        puts: [60, 0, 128, 128],
    };
    let blurred = blurred(ONE_TILE, &blur, |_, _| WHITE).expect("blur");
    assert_eq!(blurred.row(9, 58..68), white(&[0, 0, 0, 1, 15, 77, 178, 240, 254, 255]));
}

/// Across too: a blur along the rows alone reads the lines past its
/// picture as nothing, and puts none of them but those asked.
#[test]
fn past_its_picture_across_a_blur_reads_nothing_either() {
    let blur = Blur {
        across: ONE,
        down: NONE,
        picture: [0, 64, 128, 128],
        edge: Edge::Nothing,
        puts: [0, 60, 128, 128],
    };
    let blurred = blurred(ONE_TILE, &blur, |_, _| WHITE).expect("blur");
    for y in [60, 63] {
        assert_eq!(blurred.row(y, 30..34), vec![0; 4], "{y}");
    }
    assert_eq!(blurred.row(64, 30..34), white(&[255; 4]));
}

/// Repeat Edge Pixels: black then white across a 4 × 2 rectangle, red all
/// round it. Read past the rectangle, a pixel is the nearest inside —
/// never the red — so along the rows black reaches 3 past the middle and
/// white 3 past it either way; the columns, a pixel the same all the way
/// down, keep them; outside, nothing. 12's taps are white at 0 · 1 · 2 · 3
/// past it and black at 1 · 2 · 3 short: 26152 + 15862 + 3539 + 291 of
/// white, byte 178 — and 11 its mirror, 77.
#[test]
fn repeat_reads_the_nearest_pixel_inside_and_puts_nothing_outside() {
    let inside = [10, 20, 14, 22];
    let blur = Blur {
        across: ONE,
        down: ONE,
        picture: inside,
        edge: Edge::Repeat,
        puts: inside,
    };
    let blurred = blurred(ONE_TILE, &blur, |x, y| {
        if (10..14).contains(&x) && (20..22).contains(&y) {
            if x < 12 { rgba(0, 0, 0, 255) } else { WHITE }
        } else {
            rgba(255, 0, 0, 255)
        }
    })
    .expect("blur");
    let grey: Vec<u32> = [15, 77, 178, 240].iter().map(|&c| rgba(c, c, c, 255)).collect();
    assert_eq!(blurred.row(20, 10..14), grey);
    assert_eq!(blurred.row(21, 10..14), grey);
    for (x, y) in [(9, 20), (14, 21), (10, 19), (13, 22), (0, 0), (127, 127)] {
        assert_eq!(blurred.at(x, y), 0, "({x}, {y})");
    }
}

/// White stays white however far a way reaches: 65535 under weights of
/// 65536 is 65535 · 65536 — what a u32 holds with the half beside it.
#[test]
fn white_stays_white_however_far_a_way_reaches() {
    let far = Way { sigma: 16.7, reach: 50 };
    let blur = Blur {
        across: far,
        down: far,
        picture: ONE_TILE.pixels(),
        edge: Edge::Repeat,
        puts: ONE_TILE.pixels(),
    };
    let blurred = blurred(ONE_TILE, &blur, |_, _| WHITE).expect("blur");
    assert!(blurred.words.iter().all(|&word| word == WHITE));
}

#[test]
fn a_blur_of_no_reach_is_refused() {
    assert!(blurred(ONE_TILE, &whole(ONE_TILE, NONE, NONE), |_, _| WHITE).is_none());
}

#[test]
fn a_reach_past_the_farthest_is_refused() {
    let far = Way { sigma: 1.0, reach: MOST_REACH + 1 };
    for blur in [whole(ONE_TILE, far, NONE), whole(ONE_TILE, NONE, far)] {
        assert!(blurred(ONE_TILE, &blur, |_, _| WHITE).is_none(), "{blur:?}");
    }
}

#[test]
fn a_way_that_reaches_by_no_sigma_is_refused() {
    for sigma in [0.0, -1.0, f64::NAN, f64::INFINITY] {
        let blur = whole(ONE_TILE, Way { sigma, reach: 2 }, NONE);
        assert!(blurred(ONE_TILE, &blur, |_, _| WHITE).is_none(), "{sigma}");
    }
    let unreached = Way { sigma: f64::NAN, reach: 0 };
    assert!(blurred(ONE_TILE, &whole(ONE_TILE, ONE, unreached), |_, _| WHITE).is_none());
}

#[test]
fn a_picture_or_a_rectangle_put_past_the_tiles_or_holding_nothing_is_refused() {
    for inside in [[-1, 0, 10, 10], [0, 0, 129, 10], [5, 5, 5, 10], [5, 9, 9, 8]] {
        let mut blur = whole(ONE_TILE, ONE, ONE);
        blur.picture = inside;
        assert!(blurred(ONE_TILE, &blur, |_, _| WHITE).is_none(), "picture {inside:?}");
        let mut blur = whole(ONE_TILE, ONE, ONE);
        blur.puts = inside;
        assert!(blurred(ONE_TILE, &blur, |_, _| WHITE).is_none(), "puts {inside:?}");
    }
}

// ---- The ledger ----

/// Each way alone and both, both edges, a picture inside the tiles and a
/// rectangle put past it, and reaches past a workgroup's pixels.
fn scenes() -> Vec<Blur> {
    let tiles = LEDGER_TILES.pixels();
    let inside = [-100, 10, 90, 200];
    vec![
        whole(LEDGER_TILES, Way { sigma: 1.0, reach: 3 }, Way { sigma: 1.7, reach: 5 }),
        whole(LEDGER_TILES, Way { sigma: 0.7, reach: 2 }, NONE),
        Blur {
            across: NONE,
            down: Way { sigma: 1.3, reach: 4 },
            picture: inside,
            edge: Edge::Repeat,
            puts: inside,
        },
        Blur {
            across: Way { sigma: 23.3, reach: 70 },
            down: Way { sigma: 0.7, reach: 2 },
            picture: inside,
            edge: Edge::Nothing,
            puts: tiles,
        },
        whole(LEDGER_TILES, Way { sigma: 0.3, reach: 1 }, Way { sigma: 11.0, reach: 33 }),
    ]
}

/// The ledger's blurs in bands, a binding holding the tiles and no more
/// than the plane of a quarter of the rows above the middle, are the
/// blurs whole, byte for byte (connection-round-checklist ④): the lines
/// past a band its columns read are worked out again as the whole works
/// them out — in bands where both ways go, a way alone holding no plane.
#[test]
fn a_picture_in_bands_is_blurred_as_it_is_whole() {
    for blur in scenes() {
        let [_, first, _, end] = blur.puts;
        let middle = first + (end - first) / 2;
        let quarter = (end - first + 3) / 4;
        let tiles = LEDGER_TILES.tiles() * TILE_TEXELS * 4;
        let room = planes(&blur, [middle - quarter, middle]).max(tiles);
        let cut = bands([first, end], |band| planes(&blur, band) <= room);
        let count = cut.map_or(0, |cut| cut.len());
        let both = blur.across.reach > 0 && blur.down.reach > 0;
        assert_eq!(count > 1, both, "{blur:?}: {count} bands");
        let whole = blurred(LEDGER_TILES, &blur, pattern).expect("whole");
        let banded = blur_in(LEDGER_TILES, &blur, pattern, room).expect("bands");
        assert!(banded.words == whole.words, "{blur:?}: the bands put the whole's bytes");
    }
}

/// The cut halves until every band fits, its bands one after another, as
/// even as whole rows go — down to bands of one row, and none past them.
#[test]
fn the_rows_halve_until_each_band_fits() {
    let rows = |band: [i32; 2]| band[1] - band[0];
    assert_eq!(bands([0, 10], |band| rows(band) <= 10), Some(vec![[0, 10]]));
    assert_eq!(
        bands([0, 10], |band| rows(band) <= 3),
        Some(vec![[0, 2], [2, 5], [5, 7], [7, 10]])
    );
    assert_eq!(bands([4, 7], |band| rows(band) <= 1), Some(vec![[4, 5], [5, 6], [6, 7]]));
    assert_eq!(bands([0, 10], |_| false), None);
}

/// A binding that holds no band of one row refuses the blur.
#[test]
fn a_picture_no_band_of_one_row_fits_is_refused() {
    assert!(blur_in(ONE_TILE, &whole(ONE_TILE, ONE, ONE), pattern, 0).is_none());
}

#[test]
fn every_device_blurs_the_pinned_picture() {
    let bytes: Vec<u8> = scenes()
        .iter()
        .flat_map(|blur| blurred(LEDGER_TILES, blur, pattern).expect("blur").words)
        .flat_map(|word| word.to_le_bytes())
        .collect();
    assert_pinned("effects/blur", &bytes);
}
