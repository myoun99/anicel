//! A fill's colour stamp on a real GPU, checked against what the app's
//! stamp holds by hand — never against a CPU copy of it (`kernels/mod.rs`
//! has why). How the executor lays it is composite's tests'.

use super::Stamped;
use super::super::tests::{Rig, rig};
use crate::kernels::composite::{TILE, TileAt};
use crate::kernels::mask::Mask;
use crate::kernels::mask::tests::masked;
use crate::testing::read_buffer;

const ORANGE: [u8; 3] = [200, 100, 50];
/// ORANGE as a stamp's word at alpha 0: R in the low byte.
const ORANGE_WORD: u32 = 0x0032_64c8;

/// Each of `stamped`'s pages read back, as words.
fn pages(stamped: &Stamped) -> Vec<Vec<u32>> {
    let engine = rig().engine;
    stamped
        .pages
        .iter()
        .map(|page| {
            read_buffer(engine, page)
                .chunks_exact(4)
                .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
                .collect()
        })
        .collect()
}

fn stamp(mask: &Mask, first_page: u16, per_page: usize) -> Stamped {
    let Rig { engine, flood, .. } = rig();
    flood.stamp_by(engine, mask, ORANGE, first_page, per_page).expect("stamp")
}

/// The word of canvas pixel (`x`, `y`) on its tile `at` of `stamped`, its
/// pages read back as `read`.
fn word(stamped: &Stamped, read: &[Vec<u32>], first_page: u16, (x, y): (i32, i32)) -> u32 {
    let side = TILE as i32;
    let set = &stamped.set;
    let (column, row) = (x.div_euclid(side) - set.x0, y.div_euclid(side) - set.y0);
    let TileAt { page, slot } = set.tiles[(row * set.columns as i32 + column) as usize].unwrap();
    let texel = (y.rem_euclid(side) * side + x.rem_euclid(side)) as usize;
    read[usize::from(page - first_page)][usize::from(slot) * (side * side) as usize + texel]
}

// A pixel the mask covers is the colour under its byte, and one it covers
// none — inside the box or past it — is nothing: [0, 128, 255] over
// [1, 0, 7] at (130, 5), on tile (1, 0) alone, the plane's 255 past the
// box's width read by none.
#[test]
fn a_stamp_is_its_colour_under_the_mask_s_byte() {
    let mask = masked((130, 5), (3, 2), |x, y| match (x - 130, y - 5) {
        (0, 0) | (1, 1) => 0,
        (1, 0) => 128,
        (2, 0) => 255,
        (0, 1) => 1,
        _ => 7,
    });
    let stamped = stamp(&mask.mask(), 3, usize::MAX);
    let set = &stamped.set;
    assert_eq!((set.x0, set.y0, set.columns, set.rows), (1, 0, 1, 1));
    assert_eq!(set.tiles, [Some(TileAt { page: 3, slot: 0 })]);
    let read = pages(&stamped);
    let at = |x, y| word(&stamped, &read, 3, (x, y));
    assert_eq!([at(130, 5), at(131, 6)], [0; 2]);
    assert_eq!(at(131, 5), ORANGE_WORD | 128 << 24);
    assert_eq!(at(132, 5), ORANGE_WORD | 255 << 24);
    assert_eq!(at(130, 6), ORANGE_WORD | 1 << 24);
    assert_eq!(at(132, 6), ORANGE_WORD | 7 << 24);
    let others = read[0].iter().enumerate().filter(|&(texel, &word)| {
        let (x, y) = (128 + (texel % 128) as i32, (texel / 128) as i32);
        word != 0 && !((130..133).contains(&x) && (5..7).contains(&y))
    });
    assert_eq!(others.count(), 0, "a word past the box");
}

// The row is every tile the box meets, row after row on the canvas's grid
// — a box across a tile corner and past the canvas's left meets four —,
// each a pixel the colour whole inside the box and nothing past it.
#[test]
fn a_stamp_s_tiles_are_every_tile_its_box_meets() {
    let (left, top, width, height) = (-3, 120, 6, 10);
    let mask = masked((left, top), (width, height), |_, _| 255);
    let stamped = stamp(&mask.mask(), 0, usize::MAX);
    let set = &stamped.set;
    assert_eq!((set.x0, set.y0, set.columns, set.rows), (-1, 0, 2, 2));
    let slots: Vec<_> = (0..4).map(|slot| Some(TileAt { page: 0, slot })).collect();
    assert_eq!(set.tiles, slots);
    let read = pages(&stamped);
    for y in 0..256 {
        for x in -128..128 {
            let inside = (left..left + width as i32).contains(&x)
                && (top..top + height as i32).contains(&y);
            let want = if inside { ORANGE_WORD | 255 << 24 } else { 0 };
            assert_eq!(word(&stamped, &read, 0, (x, y)), want, "({x}, {y})");
        }
    }
}

// A page holds the tiles it can, and the next takes the rest: four tiles
// two a page are pages 5 and 6, slots 0 and 1 each, the same words.
#[test]
fn a_stamp_past_a_page_goes_on_the_next() {
    let mask = masked((-3, 120), (6, 10), |x, y| (x + 3 + 10 * (y - 120)) as u8 + 1);
    let whole = stamp(&mask.mask(), 5, usize::MAX);
    let paged = stamp(&mask.mask(), 5, 2);
    let at = |page, slot| Some(TileAt { page, slot });
    assert_eq!(paged.set.tiles, [at(5, 0), at(5, 1), at(6, 0), at(6, 1)]);
    let (read_whole, read_paged) = (pages(&whole), pages(&paged));
    assert_eq!(read_paged.len(), 2);
    assert!(read_paged.concat() == read_whole.concat());
}

// A box with no pixels meets no tile, and puts no page.
#[test]
fn an_empty_mask_stamps_no_tile() {
    let mask = masked((40, 40), (0, 3), |_, _| 255);
    let stamped = stamp(&mask.mask(), 0, usize::MAX);
    assert_eq!((stamped.set.columns, stamped.set.rows), (0, 1));
    assert!(stamped.set.tiles.is_empty() && stamped.pages.is_empty());
}
