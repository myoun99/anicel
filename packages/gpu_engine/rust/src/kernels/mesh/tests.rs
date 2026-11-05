//! A mesh's owners on a real GPU and its triangles' maps, checked against
//! what the app's `transformStampDabMesh` gives by hand and against the
//! ledger — never against a CPU copy of the pass (`kernels/mod.rs` has
//! why).

use std::sync::OnceLock;

use super::{MeshGrid, MeshOwners, affines};
use crate::device::Engine;
use crate::kernels::shared::{ResampleMap, ResampleMode};
use crate::testing::{assert_pinned, first_engine, read_buffer};

struct Rig {
    engine: &'static Engine,
    owners: MeshOwners,
}

/// One device and one compile for every test here (blend's tests have
/// why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        Rig {
            engine,
            owners: MeshOwners::new(engine),
        }
    })
}

/// A mesh dragged to `destination`, resting on itself.
fn dragged(columns: u32, rows: u32, destination: Vec<[f64; 2]>) -> MeshGrid {
    MeshGrid {
        columns,
        rows,
        source: destination.clone(),
        destination,
    }
}

/// One cell's corners: top-left, top-right, bottom-left, bottom-right.
fn cell(corners: [[f64; 2]; 4]) -> MeshGrid {
    dragged(1, 1, corners.to_vec())
}

/// Each pixel's owner, row after row, or none where it was refused.
fn owned(mesh: &MeshGrid, at: (i32, i32), size: (u32, u32)) -> Option<Vec<u32>> {
    let Rig { engine, owners } = rig();
    let out = owners.owners(engine, mesh, at, size)?;
    let read = read_buffer(engine, &out);
    let words = read.chunks(4).map(|word| u32::from_le_bytes(word.try_into().unwrap()));
    Some(words.take((size.0 * size.1) as usize).collect())
}

/// The owners, a string a row: the order's digit, `.` for none.
fn drawn(mesh: &MeshGrid, at: (i32, i32), size: (u32, u32)) -> Vec<String> {
    let owners = owned(mesh, at, size).expect("owners");
    owners
        .chunks(size.0 as usize)
        .map(|row| {
            row.iter()
                .map(|&owner| match owner {
                    u32::MAX => '.',
                    order => char::from_digit(order, 10).expect("an order under 10"),
                })
                .collect()
        })
        .collect()
}

const SQUARE: [[f64; 2]; 4] = [[0.0, 0.0], [4.0, 0.0], [0.0, 4.0], [4.0, 4.0]];
/// SQUARE turned over, right for left: its den is negative.
const MIRRORED: [[f64; 2]; 4] = [[4.0, 0.0], [0.0, 0.0], [4.0, 4.0], [0.0, 4.0]];

/// A cell's top-left triangle paints what it holds, the diagonal's centres
/// with it; the bottom-right the rest; past the mesh nothing.
#[test]
fn the_first_triangle_holding_a_centre_paints_it() {
    let expected = ["......", ".0000.", ".0001.", ".0011.", ".0111.", "......"];
    assert_eq!(drawn(&cell(SQUARE), (-1, -1), (6, 6)), expected);
}

/// A centre on the mesh's own edge is in — closed, unlike a selection's
/// half-open rows: the corners' pixels are painted.
#[test]
fn a_centre_on_the_mesh_s_edge_is_in() {
    let inset = cell([[0.5, 0.5], [3.5, 0.5], [0.5, 3.5], [3.5, 3.5]]);
    let expected = ["0000.", "0001.", "0011.", "0111.", "....."];
    assert_eq!(drawn(&inset, (0, 0), (5, 5)), expected);
}

/// A cell turned over holds its centres all the same, by den's sign.
#[test]
fn a_cell_turned_over_holds_its_centres() {
    assert_eq!(drawn(&cell(MIRRORED), (0, 0), (4, 4)), ["0000", "1000", "1100", "1110"]);
}

/// A triangle 200 pixels on a side, its den past 2^31, holds its centres
/// all the same.
#[test]
fn a_large_triangle_holds_its_centres() {
    let large = cell(SQUARE.map(|[x, y]| [50.0 * x, 50.0 * y]));
    assert_eq!(drawn(&large, (98, 98), (4, 4)), ["0000", "0001", "0011", "0111"]);
}

/// A triangle inside an earlier one paints nothing: its centres are the
/// earlier one's.
#[test]
fn a_triangle_inside_an_earlier_one_paints_nothing() {
    let folded = cell([[0.0, 0.0], [4.0, 0.0], [0.0, 4.0], [1.0, 1.0]]);
    assert_eq!(drawn(&folded, (0, 0), (4, 4)), ["0000", "000.", "00..", "0..."]);
}

/// A triangle with no area paints nothing, though its line runs through
/// centres.
#[test]
fn a_triangle_with_no_area_paints_nothing() {
    let flat = cell([[0.5, 0.5], [1.5, 1.5], [2.5, 2.5], [3.5, 3.5]]);
    assert_eq!(drawn(&flat, (0, 0), (4, 4)), ["....", "....", "....", "...."]);
}

/// The order runs row by row, cell by cell, two triangles a cell.
#[test]
fn the_order_runs_by_row_then_column() {
    let points = (0..3)
        .flat_map(|row| (0..3).map(move |column| [4.0 * f64::from(column), 4.0 * f64::from(row)]))
        .collect();
    let expected = [
        "00002222", "00012223", "00112233", "01112333", "44446666", "44456667", "44556677",
        "45556777",
    ];
    assert_eq!(drawn(&dragged(2, 2, points), (0, 0), (8, 8)), expected);
}

/// The output lies anywhere within the reach.
#[test]
fn the_output_reads_the_canvas_where_it_lies() {
    let moved = cell([[-4.0, 2.0], [0.0, 2.0], [-4.0, 6.0], [0.0, 6.0]]);
    assert_eq!(drawn(&moved, (-3, 2), (3, 3)), ["000", "001", "011"]);
}

/// A mesh running past the output paints only the output: what it holds
/// past the right edge is no pixel of the next row.
#[test]
fn a_mesh_past_the_output_paints_only_the_output() {
    assert_eq!(drawn(&cell(MIRRORED), (0, 0), (2, 2)), ["00", "10"]);
}

#[test]
fn a_mesh_or_an_output_past_the_reach_is_refused() {
    let reach = 1 << 15;
    let outputs = [((0, 0), (0, 4)), ((0, 0), (4, 0)), ((-reach - 1, 0), (4, 4))];
    for (at, size) in outputs {
        assert!(owned(&cell(SQUARE), at, size).is_none(), "{at:?} {size:?}");
    }
    assert!(owned(&cell(SQUARE), (reach - 4, -reach), (4, 4)).is_some());
    let far = cell([[0.0, 0.0], [32768.0, 0.0], [0.0, 4.0], [4.0, 4.0]]);
    assert!(owned(&far, (0, 0), (4, 4)).is_none());
    let short = dragged(1, 1, SQUARE[..3].to_vec());
    assert!(owned(&short, (0, 0), (4, 4)).is_none());
    let no_column = dragged(0, 1, SQUARE[..2].to_vec());
    assert!(owned(&no_column, (0, 0), (4, 4)).is_none());
    let no_row = dragged(1, 0, SQUARE[..2].to_vec());
    assert!(owned(&no_row, (0, 0), (4, 4)).is_none());
}

// ---- The maps ----

/// The maps of a mesh resting on `source` dragged to `destination`, its
/// source counted from `origin`.
fn maps(
    source: [[f64; 2]; 4],
    destination: [[f64; 2]; 4],
    origin: (f64, f64),
) -> Vec<Option<ResampleMap>> {
    let mesh = MeshGrid {
        columns: 1,
        rows: 1,
        source: source.to_vec(),
        destination: destination.to_vec(),
    };
    affines(&mesh, origin, 1.0, ResampleMode::Blend).expect("maps")
}

/// The map whose entries are `[a, b, c, d, e, f]`, Q.20.
fn map(entries: [i64; 6]) -> Option<ResampleMap> {
    let map = ResampleMap::affine(entries.map(i128::from), 1.0, ResampleMode::Blend);
    Some(map.expect("a map within R1's ranges"))
}

const ONE: i64 = 1 << 20;

/// A mesh at rest maps each pixel to itself wherever it lies; the source's
/// corner shifts what it reads.
#[test]
fn a_mesh_at_rest_maps_to_itself() {
    let still = map([ONE, 0, 0, 0, ONE, 0]);
    assert_eq!(maps(SQUARE, SQUARE, (0.0, 0.0)), [still, still]);
    let away = [[1.0, 3.0], [5.0, 3.0], [1.0, 7.0], [5.0, 7.0]];
    assert_eq!(maps(away, away, (0.0, 0.0)), [still, still]);
    let from = map([ONE, 0, -5 << 19, 0, ONE, 1 << 20]);
    assert_eq!(maps(SQUARE, SQUARE, (2.5, -1.0)), [from, from]);
    let (floor, pick) = (2.5, ResampleMode::Pick);
    let picked = ResampleMap::affine([ONE, 0, 0, 0, ONE, 0].map(i128::from), floor, pick);
    let asked = affines(&cell(SQUARE), (0.0, 0.0), floor, pick).expect("maps");
    assert_eq!(asked, [picked, picked]);
}

/// Dragged to twice its size, a mesh reads half a pixel a pixel from where
/// it rests.
#[test]
fn a_mesh_dragged_twice_as_large_reads_at_half() {
    let rest = [[10.0, 20.0], [14.0, 20.0], [10.0, 24.0], [14.0, 24.0]];
    let large = [[0.0, 0.0], [8.0, 0.0], [0.0, 8.0], [8.0, 8.0]];
    let half = map([ONE / 2, 0, 10 << 20, 0, ONE / 2, 20 << 20]);
    assert_eq!(maps(rest, large, (0.0, 0.0)), [half, half]);
}

/// Turned over, a mesh reads right to left: its den's sign turns the map.
#[test]
fn a_mesh_turned_over_reads_right_to_left() {
    let flipped = map([-ONE, 0, 4 << 20, 0, ONE, 0]);
    assert_eq!(maps(SQUARE, MIRRORED, (0.0, 0.0)), [flipped, flipped]);
}

/// The map's entries round as the spec's divr: to the nearest, a half up —
/// a third to 349525, less a third to −349525; half of a Q.20 step to 1,
/// less half to 0.
#[test]
fn a_map_rounds_by_divr() {
    let unit = [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0], [1.0, 1.0]];
    let three = [[0.0, 0.0], [3.0, 0.0], [0.0, 3.0], [3.0, 3.0]];
    let third = 349_525;
    assert_eq!(maps(unit, three, (0.0, 0.0))[0], map([third, 0, 0, 0, third, 0]));
    let turned = [[1.0, 0.0], [0.0, 0.0], [1.0, 1.0], [0.0, 1.0]];
    assert_eq!(maps(turned, three, (0.0, 0.0))[0], map([-third, 0, 1 << 20, 0, third, 0]));
    let hair = 1.0 / 256.0;
    let wide = [[0.0, 0.0], [8192.0, 0.0], [0.0, 8192.0], [8192.0, 8192.0]];
    let up = [[0.0, 0.0], [hair, 0.0], [0.0, hair], [hair, hair]];
    assert_eq!(maps(up, wide, (0.0, 0.0))[0], map([1, 0, 0, 0, 1, 0]));
    let down = [[0.0, 0.0], [-hair, 0.0], [0.0, hair], [-hair, hair]];
    assert_eq!(maps(down, wide, (0.0, 0.0))[0], map([0, 0, 0, 0, 1, 0]));
}

/// c rounds as the spec's rnd, a half up and otherwise down: a = −1 (Q.20)
/// times a corner at x = 0.5 (Q.8) is −128 in Q.28, half a Q.20 step below
/// 0, which rnd takes up to 0; at x = 0.75 it is −192, which rnd floors to
/// −1 rather than cutting toward 0.
#[test]
fn a_map_s_offset_rounds_by_rnd() {
    let hair = 1.0 / 256.0;
    let rest = [[0.0, 0.0], [-hair, 0.0], [0.0, 16.0], [-hair, 16.0]];
    let at = |x: f64| [[x, 0.0], [x + 4096.0, 0.0], [x, 4096.0], [x + 4096.0, 4096.0]];
    assert_eq!(maps(rest, at(0.5), (0.0, 0.0))[0], map([-1, 0, 0, 0, 4096, 0]));
    assert_eq!(maps(rest, at(0.75), (0.0, 0.0))[0], map([-1, 0, 1, 0, 4096, 0]));
}

/// A triangle with no area, or one whose map is past R1's ranges — 2^11
/// source pixels a pixel or more, either way —, has no map: it lands
/// nothing. The mesh hands R1 the exact entries, so the range is R1's own.
#[test]
fn a_triangle_with_no_map_lands_nothing() {
    let flat = [[0.5, 0.5], [1.5, 1.5], [2.5, 2.5], [3.5, 3.5]];
    assert_eq!(maps(SQUARE, flat, (0.0, 0.0)), [None, None]);
    let hair = 1.0 / 256.0;
    let thin = [[0.0, 0.0], [hair, 0.0], [0.0, 1.0], [hair, 1.0]];
    let eight = [[0.0, 0.0], [8.0, 0.0], [0.0, 1.0], [8.0, 1.0]];
    assert_eq!(maps(eight, thin, (0.0, 0.0)), [None, None]);
    let turned = [[8.0, 0.0], [0.0, 0.0], [8.0, 1.0], [0.0, 1.0]];
    assert_eq!(maps(turned, thin, (0.0, 0.0)), [None, None]);
    let less = 8.0 - hair;
    let under = [[0.0, 0.0], [less, 0.0], [0.0, 1.0], [less, 1.0]];
    assert_eq!(maps(under, thin, (0.0, 0.0))[0], map([2047 << 20, 0, 0, 0, ONE, 0]));
    let blend = ResampleMode::Blend;
    assert!(affines(&cell(SQUARE), (32768.0, 0.0), 1.0, blend).is_none());
    assert!(affines(&cell(SQUARE), (32767.0, 0.0), 1.0, blend).is_some());
}

// ---- The ledger ----

#[test]
fn every_device_gives_the_pinned_owners() {
    let mut points: Vec<[f64; 2]> = (0..3)
        .flat_map(|row| {
            (0..4).map(move |column| [12.0 * f64::from(column), 12.0 * f64::from(row)])
        })
        .collect();
    points[1] = [17.25, 3.5];
    points[4] = [-2.5, 13.0];
    points[6] = [9.75, 14.125];
    points[11] = [30.5, 27.75];
    let owners = owned(&dragged(3, 2, points), (-3, -2), (40, 30)).expect("owners");
    assert!(owners.contains(&u32::MAX) && owners.contains(&0) && owners.contains(&11));
    let bytes: Vec<u8> = owners.iter().flat_map(|owner| owner.to_le_bytes()).collect();
    assert_pinned("mesh/owners", &bytes);
}
