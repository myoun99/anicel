//! The letters' layers laid on a real GPU — every value worked out by hand
//! from the executor's formula (`kernels/mod.rs` has why no CPU copy).

use super::{Cover, Layer, Lettered, lettered, paged, rect_of};
use crate::kernels::chain::tiles_of;
use crate::kernels::composite::tests::{pixel_at, rig};
use crate::testing::read_buffer;

const RED: u32 = 0xFF20_30D0;
const WHITE: u32 = 0xFFFF_FFFF;

/// A layer of `colour` covering the pixels from (`x`, `y`) along the row
/// by `bytes`.
fn layer(colour: u32, hard: bool, (x, y): (i32, i32), bytes: &[u8]) -> Layer {
    Layer {
        colour,
        hard,
        cover: Cover {
            at: [x, y, x + bytes.len() as i32, y + 1],
            bytes: bytes.to_vec(),
        },
    }
}

fn laid(layers: &[Layer]) -> Option<Lettered> {
    let rig = rig();
    lettered(rig.engine, &rig.composite, layers)
}

/// What `picture` holds at (`x`, `y`), A<<24|B<<16|G<<8|R.
fn at(picture: &Lettered, x: i32, y: i32) -> u32 {
    let bytes = read_buffer(rig().engine, &picture.tiles);
    u32::from_le_bytes(pixel_at(&bytes, &tiles_of(picture.rect), x, y))
}

#[test]
fn a_whole_cover_lays_the_colour_and_none_lays_nothing() {
    let picture = laid(&[layer(RED, false, (-3, 5), &[255, 0])]).expect("laid");
    assert_eq!(at(&picture, -3, 5), RED);
    assert_eq!(at(&picture, -2, 5), 0, "a pixel it does not cover holds nothing");
}

#[test]
fn a_part_cover_is_the_pixels_alpha() {
    let picture = laid(&[layer(RED, false, (0, 0), &[77, 1])]).expect("laid");
    assert_eq!(at(&picture, 0, 0), 77 << 24 | (RED & 0x00FF_FFFF));
    assert_eq!(at(&picture, 1, 0), 1 << 24 | (RED & 0x00FF_FFFF));
}

#[test]
fn a_translucent_colour_is_its_layers_strength() {
    let picture = laid(&[layer(0x40FF_8000, false, (2, 2), &[255])]).expect("laid");
    assert_eq!(at(&picture, 2, 2), 0x40FF_8000);
}

#[test]
fn hard_letters_cut_at_half_their_cover() {
    let picture = laid(&[layer(RED, true, (0, 0), &[127, 128, 255, 1])]).expect("laid");
    assert_eq!(at(&picture, 0, 0), 0, "127 of 255 is under half");
    assert_eq!(at(&picture, 1, 0), RED, "128 is half or more: whole");
    assert_eq!(at(&picture, 2, 0), RED);
    assert_eq!(at(&picture, 3, 0), 0);
}

#[test]
fn hard_letters_are_laid_at_their_colours_alpha() {
    let picture = laid(&[layer(0x40FF_8000, true, (0, 0), &[200])]).expect("laid");
    assert_eq!(at(&picture, 0, 0), 0x40FF_8000);
}

#[test]
fn a_layer_above_covers_the_one_under_it() {
    // The outline under the fill: where both cover, the fill's colour.
    let picture = laid(&[
        layer(RED, false, (0, 0), &[255, 255]),
        layer(WHITE, false, (1, 0), &[255, 255]),
    ])
    .expect("laid");
    assert_eq!(at(&picture, 0, 0), RED);
    assert_eq!(at(&picture, 1, 0), WHITE);
    assert_eq!(at(&picture, 2, 0), WHITE);
}

#[test]
fn the_rectangle_holds_every_cover_and_nothing_between() {
    // Two layers four tiles apart, one left of the origin: the rectangle
    // spans both, and a tile between them lays nothing.
    let picture = laid(&[
        layer(RED, false, (-129, -1), &[255]),
        layer(WHITE, false, (300, 260), &[255]),
    ])
    .expect("laid");
    let rect = picture.rect;
    assert_eq!((rect.x0, rect.y0, rect.columns, rect.rows), (-2, -1, 5, 4));
    assert_eq!(at(&picture, -129, -1), RED);
    assert_eq!(at(&picture, 300, 260), WHITE);
    assert_eq!(at(&picture, 64, 64), 0);
}

#[test]
fn a_cover_the_hard_cut_drops_whole_holds_no_tile() {
    // Its box reaches a tile of its own, and nothing of it is left there.
    let picture = laid(&[
        layer(RED, false, (0, 0), &[255]),
        layer(WHITE, true, (500, 0), &[127]),
    ])
    .expect("laid");
    assert_eq!(picture.rect.columns, 1, "the dropped layer's tile is no tile of the picture");
}

#[test]
fn a_cover_ending_on_a_tiles_edge_takes_no_tile_past_it() {
    let rect = rect_of(&[layer(RED, false, (127, 127), &[255])]).expect("a rectangle");
    assert_eq!((rect.x0, rect.y0, rect.columns, rect.rows), (0, 0, 1, 1));
}

#[test]
fn a_tile_a_layer_covers_nothing_of_is_stored_as_none() {
    // The layer's set names no slot there, so the page holds the one tile
    // it covers and the executor reads nothing for the other.
    let layers = [
        layer(RED, false, (0, 0), &[255]),
        layer(WHITE, false, (200, 0), &[255]),
    ];
    let rect = rect_of(&layers).expect("a rectangle");
    let (pages, sets) = paged(rig().engine, &layers, rect, &tiles_of(rect)).expect("paged");
    let slots = |set: &crate::kernels::composite::TileSet| set.tiles.iter().flatten().count();
    assert_eq!((slots(&sets[0]), slots(&sets[1])), (1, 1));
    assert_eq!(sets[0].tiles[1], None);
    assert_eq!(pages.len(), 1);
    assert_eq!(pages[0].size(), 2 * crate::kernels::composite::TILE_BYTES);
}

#[test]
fn letters_that_cover_nothing_are_no_row() {
    assert!(laid(&[layer(RED, false, (0, 0), &[0, 0])]).is_none());
    assert!(laid(&[]).is_none());
}
