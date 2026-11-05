//! The iris's table on a real GPU, checked against the shape asked point
//! by point — the app's `pastTheIris` (test/helpers/iris_truth.dart), none
//! of the crossings iris_table.wgsl works a row out from — by hand, and
//! against the ledger. ⚠️A centre within [`BAND`] of the edge may fall
//! either way, as the app's own test has it
//! (an_iris_table_covers_its_shape_test).

use std::f64::consts::{PI, SQRT_2};
use std::sync::OnceLock;

use super::{Focus, Iris, IrisTable, MOST_RADIUS};
use crate::device::Engine;
use crate::testing::{assert_pinned, first_engine, read_buffer};

const BAND: f64 = 0.02;

struct Rig {
    engine: &'static Engine,
    table: IrisTable,
}

/// One device and one compiled pass for every test here (blend's tests
/// have why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        Rig {
            engine,
            table: IrisTable::new(engine),
        }
    })
}

/// A table, read: each shape's rows from `-reach` down, then each level's
/// head.
struct Laid {
    reach: i32,
    levels: usize,
    words: Vec<u32>,
}

impl Laid {
    fn rows(&self) -> usize {
        (2 * self.reach + 1) as usize
    }

    /// Row `dy` of level `level`'s outline (k 0) or core (k 1): its left and
    /// right column.
    fn row(&self, level: usize, k: usize, dy: i32) -> (i32, i32) {
        let at = ((level * 2 + k) * self.rows() + (dy + self.reach) as usize) * 2;
        (self.words[at] as i32, self.words[at + 1] as i32)
    }

    /// Level `level`'s head: its reach, the centres its outline and its core
    /// cover, and nothing.
    fn head(&self, level: usize) -> [u32; 4] {
        let at = self.levels * 2 * self.rows() * 2 + level * 4;
        self.words[at..at + 4].try_into().unwrap()
    }

    /// The centres level `level`'s outline (k 0) or core (k 1) covers.
    fn covered(&self, level: usize, k: usize) -> u32 {
        (-self.reach..=self.reach)
            .map(|dy| {
                let (left, right) = self.row(level, k, dy);
                (right - left + 1).max(0) as u32
            })
            .sum()
    }
}

/// The table of `iris` `radius` out — `None` where it refused it.
fn laid(iris: Iris, radius: f64, focus: Option<Focus>) -> Option<Laid> {
    let Rig { engine, table } = rig();
    let out = table.run(engine, iris, radius, focus)?;
    let words = read_buffer(engine, &out.table)
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
        .collect();
    let laid = Laid {
        reach: radius.floor() as i32,
        levels: if focus.is_some() { 256 } else { 1 },
        words,
    };
    let said = (laid.reach as u32, laid.rows() as u32, laid.levels as u32);
    assert_eq!((out.reach, out.rows, out.levels), said);
    Some(laid)
}

/// An iris turned by `rotation` (clockwise), each turn the host's cosine
/// and sine — as the app gives them.
fn iris(sides: u32, roundness: f64, aspect: f64, rotation: f64) -> Iris {
    let turn = |angle: f64| [angle.cos(), angle.sin()];
    let half = PI / f64::from(sides);
    Iris {
        sides,
        roundness,
        aspect,
        turn: turn(rotation),
        half_side: turn(half),
        side: turn(2.0 * half),
    }
}

/// The app's `pastTheIris`: how far the centre (dx, dy) about an iris's own
/// lies past the edge of `iris` drawn `radius` out — less than 0 inside —
/// asked point by point, unturned and unsqueezed, of the polygon drawn
/// `1 - roundness` as big.
fn past_the_iris(dx: i32, dy: i32, radius: f64, iris: &Iris) -> f64 {
    let [c, s] = iris.turn;
    let (dx, dy) = (f64::from(dx), f64::from(dy));
    let x = (c * dx + s * dy) / iris.aspect.min(1.0);
    let y = (-s * dx + c * dy) / (1.0 / iris.aspect).min(1.0);
    let corner = (1.0 - iris.roundness) * radius;
    let rounding = iris.roundness * radius;
    if corner <= 0.0 {
        return x.hypot(y) - rounding;
    }
    let sides = f64::from(iris.sides);
    let corners: Vec<(f64, f64)> = (0..iris.sides)
        .map(|k| {
            let angle = PI / 2.0 + PI / sides * f64::from(2 * k + 1);
            (corner * angle.cos(), corner * angle.sin())
        })
        .collect();
    let mut inside = true;
    let mut nearest = f64::INFINITY;
    for (k, &(ax, ay)) in corners.iter().enumerate() {
        let (bx, by) = corners[(k + 1) % corners.len()];
        // The corners run by a growing angle: the inside crosses positive.
        if (bx - ax) * (y - ay) - (by - ay) * (x - ax) < 0.0 {
            inside = false;
        }
        let (ex, ey) = (bx - ax, by - ay);
        let t = (((x - ax) * ex + (y - ay) * ey) / (ex * ex + ey * ey)).clamp(0.0, 1.0);
        nearest = nearest.min((ax + ex * t - x).hypot(ay + ey * t - y));
    }
    (if inside { -nearest } else { nearest }) - rounding
}

/// Each row of level `level`'s outline (k 0) or core (k 1) covers the
/// centres the iris `radius` out holds, and none it does not — but within
/// [`BAND`] of its edge; and none past its radius, so every centre it could
/// cover is asked.
fn expect_covers(table: &Laid, level: usize, k: usize, radius: f64, iris: &Iris, reason: &str) {
    let near = radius.floor() as i32 + 1;
    for dy in -table.reach..=table.reach {
        let (left, right) = table.row(level, k, dy);
        let within = left > right || (-near <= left && right <= near);
        assert!(within, "row {dy}: {left}..{right} of {iris:?}, r {radius} {reason}");
        for dx in -near..=near {
            let past = past_the_iris(dx, dy, radius, iris);
            if past.abs() < BAND {
                continue;
            }
            let covered = left <= dx && dx <= right;
            assert_eq!(covered, past < 0.0, "({dx}, {dy}) of {iris:?}, r {radius} {reason}");
        }
    }
}

/// The n-th of a run spread evenly over [0, 1): n·√p's fraction (a Weyl
/// sequence), each `p` its own run.
fn spread(n: u32, p: f64) -> f64 {
    (f64::from(n) * p.sqrt()).fract()
}

#[test]
fn every_shape_rounded_squeezed_and_turned_covers_exactly_the_centres_it_holds() {
    for trial in 0..300 {
        let radius = 0.5 + spread(trial, 2.0) * 30.0;
        let roundness = match trial % 3 {
            0 => 0.0,
            1 => 1.0,
            _ => spread(trial, 3.0),
        };
        let shape = iris(
            3 + (spread(trial, 5.0) * 8.0) as u32,
            roundness,
            10f64.powf(spread(trial, 7.0) * 2.0 - 1.0),
            (spread(trial, 11.0) * 2.0 - 1.0) * PI,
        );
        let table = laid(shape, radius, None).expect("table");
        assert_eq!(table.head(0)[0], radius.floor() as u32, "{shape:?}");
        expect_covers(&table, 0, 0, radius, &shape, "");
    }
}

/// Drawn 0.8 as big — the app's kCoreScale.
#[test]
fn its_core_is_the_iris_drawn_smaller_row_for_row() {
    let shape = iris(6, 0.3, 1.0, 0.4);
    let table = laid(shape, 17.0, None).expect("table");
    expect_covers(&table, 0, 1, 17.0 * 0.8, &shape, "core");
}

/// A centre within 2^-10 of the edge is on it, and one past that is not —
/// at a point (a triangle a quarter turned, its point out right on the
/// middle row), round a circle, and along an edge a row runs on (a square
/// whose bottom edge lies just past row 20). Each edge sits 3 or 5 · 2^-12
/// short of the column or row: either side of 2^-10 by 2^-12.
#[test]
fn a_centre_within_2_to_the_minus_10_of_the_edge_is_on_it() {
    let short = |by: f64| by / 4096.0;
    let pointed = Iris {
        turn: [0.0, 1.0],
        ..iris(3, 0.0, 1.0, 0.0)
    };
    let circle = iris(4, 1.0, 1.0, 0.0);
    for (shape, row) in [(pointed, (-10, 21)), (circle, (-21, 21))] {
        let on = laid(shape, 21.0 - short(3.0), None).expect("table");
        assert_eq!(on.row(0, 0, 0), row, "{shape:?}");
        let past = laid(shape, 21.0 - short(5.0), None).expect("table");
        assert_eq!(past.row(0, 0, 0), (row.0.max(-20), 20), "{shape:?}");
    }
    let square = iris(4, 0.0, 1.0, 0.0);
    let on = laid(square, (20.0 - short(3.0)) * SQRT_2, None).expect("table");
    assert_eq!(on.row(0, 0, 20), (-20, 20));
    let past = laid(square, (20.0 - short(5.0)) * SQRT_2, None).expect("table");
    assert_eq!((past.row(0, 0, 20), past.row(0, 0, 19)), ((1, 0), (-19, 19)));
    // Squeezed to half as tall, the 2^-10 is the iris's own, unsqueezed:
    // half that on the raster, so an edge 3 · 2^-12 past the row is past it.
    let squeezed = iris(4, 0.0, 2.0, 0.0);
    let on = laid(squeezed, (20.0 - short(1.0)) * 2.0 * SQRT_2, None).expect("table");
    assert_eq!(on.row(0, 0, 20), (-40, 40));
    let past = laid(squeezed, (20.0 - short(3.0)) * 2.0 * SQRT_2, None).expect("table");
    assert_eq!(past.row(0, 0, 20), (1, 0));
}

/// A level covers no row past its reach, as the app's table lays none —
/// though a triangle's point 3 · 2^-12 short of the row would put a centre
/// on it.
#[test]
fn a_level_covers_no_row_past_its_reach() {
    // Level 51 of 255 is a fifth of the radius: 11 - 3 · 2^-12.
    let radius = 5.0 * (11.0 - 3.0 / 4096.0);
    let focus = Focus {
        focal: 0.0,
        inverts: false,
    };
    let table = laid(iris(3, 0.0, 1.0, 0.0), radius, Some(focus)).expect("table");
    assert_eq!(table.head(51)[0], 10);
    assert_eq!(table.row(51, 0, -11), (1, 0));
    assert_eq!(table.row(51, 0, -10), (0, 0));
}

/// A level's head says its reach and the centres its outline and its core
/// cover, all their rows — what a pixel's mean is over.
#[test]
fn each_head_says_what_its_level_covers() {
    let shape = iris(7, 0.3, 1.6, 0.9);
    for focus in [None, Some(Focus { focal: 30.0, inverts: false })] {
        let table = laid(shape, 40.5, focus).expect("table");
        let levels: &[usize] = if focus.is_some() { &[0, 29, 30, 31, 128, 255] } else { &[0] };
        for &level in levels {
            let radius = focus.map_or(40.5, |_| 40.5 * (level as f64 - 30.0).abs() / 255.0);
            let covered = [0, 1].map(|k| table.covered(level, k));
            let want = [radius.floor() as u32, covered[0], covered[1], 0];
            assert_eq!(table.head(level), want, "level {level}");
        }
        assert!(table.head(levels[levels.len() - 1])[1] > 1000, "fixture: an iris that covers");
    }
}

/// The app's hand cases: a triangle points up and lies flat along its
/// bottom; a square stands square, an aspect of 2 is twice as wide as tall,
/// and a quarter turn is clockwise.
#[test]
fn a_triangle_points_up_a_square_stands_square_and_a_turn_is_clockwise() {
    let at_20 = |shape: Iris| laid(shape, 20.0, None).expect("table");
    let triangle = at_20(iris(3, 0.0, 1.0, 0.0));
    // Its bottom edge lies half its radius below the centre.
    let width = |(left, right): (i32, i32)| right - left;
    assert!(width(triangle.row(0, 0, 10)) > 30);
    assert!(width(triangle.row(0, 0, 11)) < 0);
    assert!(width(triangle.row(0, 0, -20)) <= 1);

    let half = (20.0 / SQRT_2).floor() as i32;
    let square = at_20(iris(4, 0.0, 1.0, 0.0));
    for dy in -20..=20_i32 {
        let want = if dy.abs() <= half { (-half, half) } else { (1, 0) };
        assert_eq!(square.row(0, 0, dy), want, "row {dy}");
    }
    let wide = at_20(iris(4, 0.0, 2.0, 0.0));
    assert_eq!(wide.row(0, 0, 0), (-half, half), "as wide");
    let top = (-20..=20).find(|&dy| width(wide.row(0, 0, dy)) >= 0);
    assert_eq!(top, Some(-(20.0 / SQRT_2 / 2.0).floor() as i32), "half as tall");

    // Its point out right on the middle row; its flat side upright, half
    // its radius left of the centre.
    let turned = at_20(iris(3, 0.0, 1.0, PI / 2.0));
    assert_eq!(turned.row(0, 0, 0), (-10, 20));
}

/// A blur map lays a level for each of its values: the radius times how far
/// the value — or its inverse — lies from the focal distance, over 255.
#[test]
fn a_blur_map_lays_a_level_for_each_of_its_values() {
    let shape = iris(5, 0.5, 1.0, 0.0);
    for most in [24.0, 600.0] {
        for inverts in [false, true] {
            let focus = Focus {
                focal: 100.5,
                inverts,
            };
            let table = laid(shape, most, Some(focus)).expect("table");
            for level in [0, 60, 100, 101, 200, 255] {
                let value = if inverts { 255 - level } else { level };
                let radius = most * (f64::from(value) - 100.5).abs() / 255.0;
                let reason = format!("level {level} of {most}, inverts {inverts}");
                assert_eq!(table.head(level as usize)[0], radius.floor() as u32, "{reason}");
                expect_covers(&table, level as usize, 0, radius, &shape, &reason);
            }
        }
    }
}

/// At the most radius, and squeezed the most across a quarter turn — 1/|D|
/// at its most —, every row's ends lie where the shape has them: the
/// products iris_table.wgsl makes stay inside their words. A triangle's
/// point reaches the most column, 2^13.
#[test]
fn the_widest_iris_lays_every_row() {
    let pointed = Iris {
        turn: [0.0, 1.0],
        ..iris(3, 0.0, 1.0, 0.0)
    };
    let table = laid(pointed, MOST_RADIUS, None).expect("table");
    assert_eq!(table.row(0, 0, 0), (-4096, 8192));
    for shape in [iris(8, 0.2, 0.7, 0.3), iris(5, 0.6, 0.1, PI / 2.0)] {
        let table = laid(shape, MOST_RADIUS, None).expect("table");
        assert_eq!(table.head(0)[..2], [8192, table.covered(0, 0)]);
        for dy in [-8192, -8000, -4000, -1, 0, 1, 5791, 8191, 8192] {
            let (left, right) = table.row(0, 0, dy);
            for dx in [left - 1, left, right, right + 1, 0] {
                let past = past_the_iris(dx, dy, MOST_RADIUS, &shape);
                if past.abs() < BAND {
                    continue;
                }
                assert_eq!(left <= dx && dx <= right, past < 0.0, "({dx}, {dy}) of {shape:?}");
            }
        }
    }
}

/// At no radius an iris covers nothing — a pixel the gather keeps as it is;
/// at half a pixel, its own centre.
#[test]
fn an_iris_at_the_ends_of_its_range_is_laid() {
    let nothing = laid(iris(4, 0.0, 1.0, 0.0), 0.0, None).expect("table");
    assert_eq!((nothing.row(0, 0, 0), nothing.head(0)), ((1, 0), [0; 4]));
    let centre = laid(iris(4, 0.0, 1.0, 0.0), 0.5, None).expect("table");
    assert_eq!(centre.row(0, 0, 0), (0, 0));
    let ends = [
        (iris(3, 1.0, 0.1, 0.0), Some(Focus { focal: 0.0, inverts: true })),
        (iris(10, 0.0, 10.0, PI), Some(Focus { focal: 255.0, inverts: false })),
    ];
    for (shape, focus) in ends {
        assert!(laid(shape, 9.0, focus).is_some(), "{shape:?} {focus:?}");
    }
}

#[test]
fn an_iris_past_its_range_is_refused() {
    let square = iris(4, 0.0, 1.0, 0.0);
    let at = |focal: f64| Some(Focus { focal, inverts: false });
    let refused = [
        (iris(2, 0.0, 1.0, 0.0), 10.0, None),
        (iris(11, 0.0, 1.0, 0.0), 10.0, None),
        (iris(4, -0.1, 1.0, 0.0), 10.0, None),
        (iris(4, 1.5, 1.0, 0.0), 10.0, None),
        (iris(4, 0.0, 0.05, 0.0), 10.0, None),
        (iris(4, 0.0, 11.0, 0.0), 10.0, None),
        (iris(4, 0.0, f64::NAN, 0.0), 10.0, None),
        (Iris { turn: [0.0, 0.0], ..square }, 10.0, None),
        (Iris { half_side: [1.0, 1.0], ..square }, 10.0, None),
        (Iris { side: [0.5, 0.5], ..square }, 10.0, None),
        (square, -1.0, None),
        (square, MOST_RADIUS + 0.5, None),
        (square, f64::NAN, None),
        (square, 10.0, at(-1.0)),
        (square, 10.0, at(255.5)),
    ];
    for (shape, radius, focus) in refused {
        assert!(laid(shape, radius, focus).is_none(), "{shape:?} {radius} {focus:?}");
    }
}

// ---- The ledger ----

/// Irises whose turns are worked out by square roots alone — the same on
/// every machine, where the host's own cosine and sine may differ by a bit:
/// a square, a rounded hexagon squeezed and turned, a pentagon at each of a
/// blur map's levels, a circle, and an octagon squeezed the most.
fn scenes() -> Vec<(Iris, f64, Option<Focus>)> {
    let (r2, r3, r5) = (0.5f64.sqrt(), 3f64.sqrt() / 2.0, 5f64.sqrt());
    let triangle = ([0.5, r3], [-0.5, r3]);
    let square = ([r2, r2], [0.0, 1.0]);
    let pentagon = (
        [(1.0 + r5) / 4.0, (10.0 - 2.0 * r5).sqrt() / 4.0],
        [(r5 - 1.0) / 4.0, (10.0 + 2.0 * r5).sqrt() / 4.0],
    );
    let hexagon = ([r3, 0.5], [0.5, r3]);
    let octagon = ([(2.0 + 2f64.sqrt()).sqrt() / 2.0, (2.0 - 2f64.sqrt()).sqrt() / 2.0], [r2, r2]);
    let shape = |sides, roundness, aspect, turn, (half_side, side)| Iris {
        sides,
        roundness,
        aspect,
        turn,
        half_side,
        side,
    };
    let focus = Focus {
        focal: 100.5,
        inverts: false,
    };
    vec![
        (shape(4, 0.0, 1.0, [1.0, 0.0], square), 20.0, None),
        (shape(6, 0.3, 1.6, [0.6, 0.8], hexagon), 37.25, None),
        (shape(5, 0.5, 0.4, [-0.8, 0.6], pentagon), 24.0, Some(focus)),
        (shape(3, 1.0, 1.0, [r3, -0.5], triangle), 9.5, None),
        (shape(8, 0.2, 0.1, [0.0, 1.0], octagon), 300.0, None),
    ]
}

#[test]
fn every_device_lays_the_pinned_tables() {
    let bytes: Vec<u8> = scenes()
        .into_iter()
        .flat_map(|(shape, radius, focus)| laid(shape, radius, focus).expect("table").words)
        .flat_map(|word| word.to_le_bytes())
        .collect();
    assert_pinned("effects/iris-table", &bytes);
}
