//! The ink scan on a real GPU, checked by hand — never against a CPU copy
//! of it (`kernels/mod.rs` has why) — and against the ledger. The cels are
//! the verbs' (`cel_pixel/tests.rs`).

use std::collections::HashSet;
use std::sync::OnceLock;

use super::{Ink, InkBox, TileInk};
use crate::device::Engine;
use crate::kernels::cel_pixel::tests::{CUTS, Cel, INK, cel, one, rgba};
use crate::kernels::composite::tests::mix;
use crate::testing::{assert_pinned, first_engine};

struct Rig {
    engine: &'static Engine,
    ink: Ink,
}

/// One device and one compiled scan for every test here (blend's tests
/// have why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        let ink = Ink::new(engine).expect("compile the ink scan");
        Rig { engine, ink }
    })
}

/// Each walked tile of `cel` and its ink, its passes cut at `cut`'s pages
/// and tiles or as the device cuts them.
fn scanned(cel: &Cel, cut: Option<(usize, usize)>) -> Option<Vec<TileInk>> {
    let Rig { engine, ink } = rig();
    let pages = cel.pool.upload(engine);
    match cut {
        Some(cut) => ink.run_by(engine, &pages, &cel.set, cut),
        None => ink.run(engine, &pages, &cel.set),
    }
}

/// The ink of tile (0, 0) alone, its pixels `named` and nothing elsewhere.
fn one_ink(named: &[((i32, i32), u32)]) -> Option<InkBox> {
    let scanned = scanned(&one(named), None).expect("scan");
    assert_eq!(scanned.len(), 1);
    scanned[0].ink
}

fn boxed(left: u32, top: u32, right: u32, bottom: u32) -> Option<InkBox> {
    Some(InkBox { left, top, right, bottom })
}

fn edges(ink: InkBox) -> [u32; 4] {
    [ink.left, ink.top, ink.right, ink.bottom]
}

const SOLID: u32 = INK | 255 << 24;

#[test]
fn a_pixel_of_any_alpha_is_a_box_of_itself() {
    assert_eq!(one_ink(&[((5, 9), INK | 1 << 24)]), boxed(5, 9, 6, 10));
}

#[test]
fn a_colour_with_no_alpha_is_no_ink() {
    assert_eq!(one_ink(&[]), None);
    assert_eq!(one_ink(&[((3, 3), rgba(9, 9, 9, 0))]), None);
    assert_eq!(one_ink(&[((3, 3), rgba(9, 9, 9, 0)), ((7, 2), SOLID)]), boxed(7, 2, 8, 3));
}

/// The least column and the least row may be two pixels', and so may the
/// greatest; a tile's corners make it whole either way round.
#[test]
fn each_edge_of_the_box_is_its_own_pixel_s() {
    assert_eq!(one_ink(&[((40, 90), SOLID), ((70, 20), SOLID)]), boxed(40, 20, 71, 91));
    assert_eq!(one_ink(&[((0, 0), SOLID), ((127, 127), SOLID)]), boxed(0, 0, 128, 128));
    assert_eq!(one_ink(&[((127, 0), SOLID), ((0, 127), SOLID)]), boxed(0, 0, 128, 128));
}

/// Tiles (−1, −1) and (0, −1) above (−1, 0) and (0, 0): ink at
/// (−128, −128) and (−100, −3) on the first — (0, 0) and (28, 125) in it —,
/// nothing on the second, none of the third, and ink at (5, 6) on the last.
/// The walk goes row by row past the tile the cel has none of.
#[test]
fn each_walked_tile_finds_its_own_ink() {
    let inked = [(-128, -128), (-100, -3), (5, 6)];
    let pixel = move |x, y| if inked.contains(&(x, y)) { SOLID } else { 0 };
    let cel = cel((-1, -1), (2, 2), pixel, |column, row| ((column, row) != (-1, 0)).then_some(0));
    let tile = |column, row, ink| TileInk { column, row, ink };
    let wanted = [
        tile(-1, -1, boxed(0, 0, 29, 126)),
        tile(0, -1, None),
        tile(0, 0, boxed(5, 6, 6, 7)),
    ];
    assert_eq!(scanned(&cel, None).expect("scan"), wanted);
}

#[test]
fn a_cel_of_no_tiles_walks_none() {
    let none = cel((0, 0), (2, 1), |_, _| SOLID, |_, _| None);
    assert_eq!(scanned(&none, None).expect("scan"), Vec::<TileInk>::new());
}

#[test]
fn a_scan_refuses_a_page_past_the_pool_and_a_pass_of_nothing() {
    let Rig { engine, ink } = rig();
    let cel = one(&[((1, 1), SOLID)]);
    let pages = cel.pool.upload(engine);
    assert!(ink.run(engine, &pages[..0], &cel.set).is_none());
    assert!(ink.run_by(engine, &pages, &cel.set, (0, 6)).is_none());
    assert!(ink.run_by(engine, &pages, &cel.set, (1, 0)).is_none());
}

/// Ink where a hash says, one pixel in 4,096, and nothing elsewhere.
fn sparse(x: i32, y: i32) -> u32 {
    if mix(x as u32 ^ mix(y as u32 ^ 0x1abe1)) % 4096 == 0 { SOLID } else { 0 }
}

/// The sparse cel over 3 × 2 tiles from (−2, −1), but for tile (0, 0),
/// each tile on the page `page` gives its column.
fn sparse_cel_on(page: impl Fn(i32) -> u16) -> Cel {
    let place = move |column, row| ((column, row) != (0, 0)).then_some(page(column));
    cel((-2, -1), (3, 2), sparse, place)
}

/// The sparse cel on tiles spread over three pages, cut into passes by its
/// pages and its tiles, finds what it finds on one page in one pass: each
/// pass puts its tiles' boxes at their place in the walk, which no two
/// tiles' boxes alike could tell apart.
#[test]
fn a_cel_cut_into_passes_finds_what_one_pass_finds() {
    let whole = scanned(&sparse_cel_on(|_| 0), Some((1, 6))).expect("one pass");
    let boxes: HashSet<_> = whole.iter().map(|tile| tile.ink.map(edges)).collect();
    assert!(whole.len() == 5 && boxes.len() == 5 && !boxes.contains(&None));
    let spread = sparse_cel_on(|column| column.rem_euclid(3) as u16);
    for cut in CUTS {
        assert_eq!(scanned(&spread, Some(cut)).expect("cut up"), whole, "{cut:?}");
    }
}

/// The sparse cel over three pages: the ledger's.
#[test]
fn every_device_finds_the_pinned_ink() {
    let found = scanned(&sparse_cel_on(|column| column.rem_euclid(3) as u16), None).expect("scan");
    let bytes: Vec<u8> = found
        .iter()
        .flat_map(|tile| {
            let ink = tile.ink.map_or([u32::MAX; 4], edges);
            [tile.column as u32, tile.row as u32].into_iter().chain(ink)
        })
        .flat_map(u32::to_le_bytes)
        .collect();
    assert_pinned("cel_pixel/ink", &bytes);
}
