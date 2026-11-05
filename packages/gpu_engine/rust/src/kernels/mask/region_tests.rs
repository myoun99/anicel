//! A selection's hard mask on a real GPU, checked against what the app's
//! `maskFor` gives by hand and against the ledger — never against a CPU
//! copy of it (`kernels/mod.rs` has why).

use std::sync::OnceLock;

use super::Combine::{Add, Intersect, Replace, Subtract};
use super::{Combine, Operand, RegionMask, Step};
use crate::device::Engine;
use crate::kernels::mask::MaskBox;
use crate::testing::{assert_pinned, first_engine, read_buffer};

struct Rig {
    engine: &'static Engine,
    mask: RegionMask,
}

/// One device and one compile for every test here (blend's tests have
/// why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        Rig {
            engine,
            mask: RegionMask::new(engine),
        }
    })
}

type Ring = Vec<[f64; 2]>;

fn rect(left: f64, top: f64, right: f64, bottom: f64) -> Ring {
    vec![[left, top], [right, top], [right, bottom], [left, bottom]]
}

fn copies(combine: Combine, polygons: Vec<Ring>) -> Step {
    Step {
        combine,
        operand: Operand::Copies(polygons),
    }
}

fn shape(combine: Combine, polygon: Ring) -> Step {
    copies(combine, vec![polygon])
}

fn nested(combine: Combine, steps: Vec<Step>) -> Step {
    Step {
        combine,
        operand: Operand::Region(steps),
    }
}

/// The mask's bytes over `width` × `height` from (`left`, `top`), row after
/// row, or none where it was refused.
fn masked(steps: &[Step], at: (i32, i32), width: u32, height: u32) -> Option<Vec<u8>> {
    let Rig { engine, mask } = rig();
    let size = MaskBox { width, height };
    let out = mask.selection(engine, steps, at, size)?;
    let stride = (width.div_ceil(4) * 4) as usize;
    let read = read_buffer(engine, &out);
    Some(
        read.chunks(stride)
            .take(height as usize)
            .flat_map(|row| &row[..width as usize])
            .copied()
            .collect(),
    )
}

/// The mask a row a string: `#` in, `.` out.
fn drawn(steps: &[Step], at: (i32, i32), width: u32, height: u32) -> Vec<String> {
    let bytes = masked(steps, at, width, height).expect("a mask");
    bytes
        .chunks(width as usize)
        .map(|row| {
            row.iter()
                .map(|&byte| match byte {
                    255 => '#',
                    0 => '.',
                    _ => panic!("a hard mask holds {byte}"),
                })
                .collect()
        })
        .collect()
}

/// A pixel is in by its centre, half-open: an edge through a centre takes
/// it on the left of the selection and the top, and leaves it on the right
/// and the bottom.
#[test]
fn a_pixel_is_in_by_its_centre() {
    let inner = [shape(Replace, rect(1.0, 1.0, 4.0, 3.0))];
    assert_eq!(drawn(&inner, (0, 0), 6, 4), ["......", ".###..", ".###..", "......"]);
    let through = [shape(Replace, rect(0.5, 0.5, 3.5, 2.5))];
    assert_eq!(drawn(&through, (0, 0), 6, 4), ["###...", "###...", "......", "......"]);
}

/// The same on a slant: the diagonal's centres are out of the triangle left
/// of it and in the one right of it.
#[test]
fn a_slanted_edge_through_centres_keeps_the_half_open_rule() {
    let left = [shape(Replace, vec![[0.0, 0.0], [4.0, 4.0], [0.0, 4.0]])];
    assert_eq!(drawn(&left, (0, 0), 4, 4), ["....", "#...", "##..", "###."]);
    let right = [shape(Replace, vec![[0.0, 0.0], [4.0, 0.0], [4.0, 4.0]])];
    assert_eq!(drawn(&right, (0, 0), 4, 4), ["####", ".###", "..##", "...#"]);
}

/// A vertex on a row's scanline is crossed by one of its two edges only:
/// the diamond's top and bottom meet nothing, its sides a row each.
#[test]
fn a_vertex_on_a_scanline_is_crossed_once() {
    let diamond = vec![[2.5, 0.5], [4.5, 2.5], [2.5, 4.5], [0.5, 2.5]];
    let expected = [".....", ".##..", "####.", ".##..", "....."];
    assert_eq!(drawn(&[shape(Replace, diamond)], (0, 0), 5, 5), expected);
}

/// Each step folds by the mode table from what the steps before it
/// selected — from nothing at the first.
#[test]
fn the_steps_fold_by_the_mode_table() {
    let a = || rect(0.0, 0.0, 4.0, 2.0);
    let b = || rect(2.0, 1.0, 6.0, 3.0);
    let folded = |second: Combine| {
        drawn(&[shape(Replace, a()), shape(second, b())], (0, 0), 6, 3)
    };
    assert_eq!(folded(Replace), ["......", "..####", "..####"]);
    assert_eq!(folded(Add), ["####..", "######", "..####"]);
    assert_eq!(folded(Subtract), ["####..", "##....", "......"]);
    assert_eq!(folded(Intersect), ["......", "..##..", "......"]);
    let nothing = ["......", "......", "......"];
    assert_eq!(drawn(&[shape(Add, a())], (0, 0), 6, 3), ["####..", "####..", "......"]);
    assert_eq!(drawn(&[shape(Subtract, a())], (0, 0), 6, 3), nothing);
    assert_eq!(drawn(&[shape(Intersect, a())], (0, 0), 6, 3), nothing);
    assert_eq!(drawn(&[], (0, 0), 6, 3), nothing);
}

/// The polygons of one act fold as their union, where they overlap too —
/// and narrowing to an act is narrowing to that union, not to each.
#[test]
fn an_act_s_polygons_fold_as_their_union() {
    let a = || rect(0.0, 0.0, 4.0, 2.0);
    let b = || rect(2.0, 1.0, 6.0, 3.0);
    let whole = || rect(0.0, 0.0, 6.0, 3.0);
    let union = ["####..", "######", "..####"];
    assert_eq!(drawn(&[copies(Replace, vec![a(), b()])], (0, 0), 6, 3), union);
    let narrowed = [shape(Replace, whole()), copies(Intersect, vec![a(), b()])];
    assert_eq!(drawn(&narrowed, (0, 0), 6, 3), union);
    let each = [shape(Replace, whole()), shape(Intersect, a()), shape(Intersect, b())];
    assert_eq!(drawn(&each, (0, 0), 6, 3), ["......", "..##..", "......"]);
}

/// A nested selection folds in as one operand, folded from nothing itself:
/// the wall less A ∩ B is not the wall less A less B — and a selection two
/// deep folds the same way.
#[test]
fn a_nested_selection_folds_as_one_operand() {
    let a = || rect(0.0, 0.0, 4.0, 2.0);
    let b = || rect(2.0, 1.0, 6.0, 3.0);
    let whole = || rect(0.0, 0.0, 6.0, 3.0);
    let both = || vec![shape(Replace, a()), shape(Intersect, b())];
    let inverse = [shape(Replace, whole()), nested(Subtract, both())];
    assert_eq!(drawn(&inverse, (0, 0), 6, 3), ["######", "##..##", "######"]);
    let stepwise = [shape(Replace, whole()), shape(Subtract, a()), shape(Subtract, b())];
    assert_eq!(drawn(&stepwise, (0, 0), 6, 3), ["....##", "......", "##...."]);
    let added = [nested(Add, vec![shape(Add, a())])];
    assert_eq!(drawn(&added, (0, 0), 6, 3), ["####..", "####..", "......"]);
    let twice = [
        shape(Replace, whole()),
        nested(Subtract, vec![shape(Replace, whole()), nested(Subtract, vec![shape(Add, b())])]),
    ];
    assert_eq!(drawn(&twice, (0, 0), 6, 3), ["......", "..####", "..####"]);
    let side_by_side = [
        nested(Replace, vec![shape(Replace, a())]),
        nested(Intersect, vec![shape(Add, b())]),
    ];
    assert_eq!(drawn(&side_by_side, (0, 0), 6, 3), ["......", "..##..", "......"]);
}

/// A ring of no points selects nothing, as no edge crosses a row.
#[test]
fn an_empty_ring_selects_nothing() {
    let empty = [copies(Replace, vec![Vec::new()])];
    assert_eq!(drawn(&empty, (0, 0), 3, 2), ["...", "..."]);
}

/// A crossing as far into the box as the reach allows: in the widest box,
/// from the reach's left end to 3000.25 is 35767 columns, and to 32767.75
/// every column but the first.
#[test]
fn a_crossing_lies_as_far_into_the_box_as_the_reach() {
    let wide = [shape(Replace, rect(-32767.0, 0.0, 3000.25, 1.0))];
    let bytes = masked(&wide, (-32768, 0), 65536, 1).expect("the widest box");
    assert_eq!(bytes[0], 0);
    assert!(bytes[1..35768].iter().all(|&byte| byte == 255));
    assert!(bytes[35768..].iter().all(|&byte| byte == 0));
    let widest = [shape(Replace, rect(-32767.0, 0.0, 32767.75, 1.0))];
    let bytes = masked(&widest, (-32768, 0), 65536, 1).expect("the widest box");
    assert_eq!(bytes[0], 0);
    assert!(bytes[1..].iter().all(|&byte| byte == 255));
}

/// Even-odd: a polygon wound twice round a square selects nothing, and a
/// bow tie keeps its two wings.
#[test]
fn a_polygon_is_in_where_it_is_crossed_an_odd_number_of_times() {
    let square = [[1.0, 0.0], [3.0, 0.0], [3.0, 2.0], [1.0, 2.0]];
    let twice: Ring = square.iter().chain(&square).copied().collect();
    assert_eq!(drawn(&[shape(Replace, twice)], (0, 0), 4, 2), ["....", "...."]);
    let bow = vec![[0.0, 0.0], [4.0, 2.0], [4.0, 0.0], [0.0, 2.0]];
    assert_eq!(drawn(&[shape(Replace, bow)], (0, 0), 6, 2), ["#..#..", "#..#.."]);
}

/// The box lies anywhere within the canvas's reach; a polygon past it on
/// both sides fills its rows, one wholly beside it leaves them empty.
#[test]
fn the_box_reads_the_canvas_where_it_lies() {
    let at = (-3, 2);
    let near = [shape(Replace, rect(-10.0, 0.0, -1.0, 3.5))];
    assert_eq!(drawn(&near, at, 5, 2), ["##...", "....."]);
    let across = [shape(Replace, rect(-100.0, 0.0, 100.0, 10.0))];
    assert_eq!(drawn(&across, at, 5, 2), ["#####", "#####"]);
    for beside in [rect(10.0, 0.0, 20.0, 10.0), rect(-20.0, 0.0, -10.0, 10.0)] {
        assert_eq!(drawn(&[shape(Replace, beside)], at, 5, 2), [".....", "....."]);
    }
}

/// A row ends anywhere in a word of bits: one bit short of it, on its last
/// bit, one past it.
#[test]
fn a_row_ends_anywhere_in_a_word() {
    for width in [31, 32, 33, 64] {
        let whole = [shape(Replace, rect(-1.0, 0.0, 100.0, 1.0))];
        assert_eq!(drawn(&whole, (0, 0), width, 1), ["#".repeat(width as usize)]);
    }
    let to_32 = [shape(Replace, rect(0.0, 0.0, 32.0, 1.0))];
    assert_eq!(drawn(&to_32, (0, 0), 33, 1), [format!("{}.", "#".repeat(32))]);
    let from_31 = [shape(Replace, rect(31.0, 0.0, 40.0, 1.0))];
    assert_eq!(drawn(&from_31, (0, 0), 33, 1), [format!("{}##", ".".repeat(31))]);
}

/// A point is put in Q.8 first — the one value the spec changes: 1.501
/// rounds onto the centre 1.5, which it then lets in, and 1.502 past it.
#[test]
fn a_point_is_put_in_q8() {
    let from = |left: f64| drawn(&[shape(Replace, rect(left, 0.0, 3.0, 1.0))], (0, 0), 4, 1);
    assert_eq!(from(1.501), [".##."]);
    assert_eq!(from(1.502), ["..#."]);
}

#[test]
fn a_box_or_a_point_past_the_reach_is_refused() {
    let square = || vec![shape(Replace, rect(0.0, 0.0, 2.0, 2.0))];
    let reach = 1 << 15;
    let boxes = [
        ((0, 0), 0, 4),
        ((0, 0), 4, 0),
        ((-reach - 1, 0), 4, 4),
        ((0, reach - 3), 4, 4),
    ];
    for (at, width, height) in boxes {
        assert!(masked(&square(), at, width, height).is_none(), "{at:?} {width}x{height}");
    }
    assert!(masked(&square(), (-reach, reach - 4), 4, 4).is_some());
    for far in [32768.0, -32768.0, f64::NAN] {
        let step = [shape(Replace, vec![[0.0, 0.0], [far, 0.0], [0.0, 2.0]])];
        assert!(masked(&step, (0, 0), 4, 4).is_none(), "{far}");
    }
    let near = [shape(Replace, vec![[0.0, 0.0], [32767.99, 0.0], [0.0, 2.0]])];
    assert!(masked(&near, (0, 0), 4, 4).is_some());
}

// ---- The ledger ----

/// A ring of `count` points over the box from `seed` — a lasso that crosses
/// itself, in sevenths of a pixel.
fn lasso(seed: u32, count: usize) -> Ring {
    let mut state = seed;
    let mut next = || {
        state = state.wrapping_mul(1_103_515_245).wrapping_add(12_345) & 0x7fff_ffff;
        state
    };
    (0..count)
        .map(|_| {
            let x = -9.0 + f64::from(next() >> 8 & 0x7f) * 0.7 + f64::from(next() % 7) / 7.0;
            let y = 1.0 + f64::from(next() >> 8 & 0x3f) * 0.9 + f64::from(next() % 7) / 7.0;
            [x, y]
        })
        .collect()
}

#[test]
fn every_device_masks_the_pinned_selection() {
    let mirrored = |ring: &Ring| ring.iter().map(|&[x, y]| [77.0 - x, y]).collect();
    let first = lasso(7, 40);
    let steps = [
        copies(Replace, vec![mirrored(&first), first]),
        shape(Add, rect(20.25, 10.75, 51.6, 30.125)),
        nested(
            Subtract,
            vec![
                shape(Replace, rect(30.0, 20.0, 60.0, 50.5)),
                shape(Intersect, lasso(11, 25)),
            ],
        ),
        shape(Add, vec![[3.5, 40.0], [12.25, 58.0], [-2.0, 55.5]]),
    ];
    let bytes = masked(&steps, (-5, 3), 77, 53).expect("the selection");
    assert!(bytes.iter().any(|&byte| byte == 0) && bytes.iter().any(|&byte| byte == 255));
    assert_pinned("mask/selection-region", &bytes);
}
