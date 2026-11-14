//! The write path on a real GPU, checked by hand: a tile is unchanged only
//! where every byte is the stored one's, or — with none stored — where
//! every byte is 0; a changed one is inked only where a pixel's alpha is
//! not 0; and a copy lands in its slot and nowhere else.

use std::sync::OnceLock;

use super::Change::{Cleared, Inked, Same};
use super::{Change, Write};
use crate::device::Engine;
use crate::kernels::composite::tests::{Pool, mix};
use crate::kernels::composite::{TILE, TILE_TEXELS, TileAt, TileSet};
use crate::kernels::shared::{plane, words_buffer};
use crate::testing::{first_engine, read_buffer};

struct Rig {
    engine: &'static Engine,
    write: Write,
}

/// One device and one compiled test for every test here (blend's tests
/// have why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        let write = Write::new(engine).expect("compile the write path");
        Rig { engine, write }
    })
}

/// A picture's pixel (x, y) on the canvas.
fn pixel(x: i32, y: i32) -> u32 {
    mix(x as u32 ^ mix(y as u32))
}

/// The tile at (`column`, `row`) of [`pixel`]'s picture, as stored.
fn tile(column: i32, row: i32) -> Vec<u32> {
    let side = TILE as i32;
    (0..side)
        .flat_map(|y| (0..side).map(move |x| pixel(column * side + x, row * side + y)))
        .collect()
}

/// A tile of nothing but its word `at`.
fn only(at: usize, word: u32) -> Vec<u32> {
    let mut tile = vec![0; TILE_TEXELS as usize];
    tile[at] = word;
    tile
}

/// `tile` with its word `at` one off.
fn off(mut tile: Vec<u32>, at: usize) -> Vec<u32> {
    tile[at] ^= 1;
    tile
}

/// `tiles` one after another, as a pass puts them.
fn put(tiles: &[Vec<u32>]) -> wgpu::Buffer {
    let words = tiles.concat();
    let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
    words_buffer(rig().engine, "tiles put", &words, usage)
}

/// Whether each of `tiles` differs from what `set` stores where it goes,
/// the passes cut at `cut`'s pages and tiles or as the device cuts them.
fn changed(
    pool: &Pool,
    set: &TileSet,
    tiles: &[Vec<u32>],
    cut: Option<(usize, usize)>,
) -> Option<Vec<Change>> {
    let Rig { engine, write } = rig();
    let pages = pool.upload(engine);
    let put = put(tiles);
    match cut {
        Some(cut) => write.changed_by(engine, &pages, &put, &set.tiles, cut),
        None => write.changed(engine, &pages, &put, &set.tiles),
    }
}

fn words(bytes: &[u8]) -> Vec<u32> {
    bytes
        .chunks_exact(4)
        .map(|four| u32::from_le_bytes([four[0], four[1], four[2], four[3]]))
        .collect()
}

/// Four tiles, two to a page: the first and the last as stored, the second
/// with its last word one off and the third with its first — the words
/// the first lane and the last lane of a tile's workgroup take last and
/// first.
#[test]
fn a_tile_is_unchanged_only_where_every_word_is_the_stored_ones() {
    let mut pool = Pool::default();
    let set = pool.drawn(pixel, (0, 0), (2, 2), |_, row| Some(row as u16));
    let last = TILE_TEXELS as usize - 1;
    let tiles = [tile(0, 0), off(tile(1, 0), last), off(tile(0, 1), 0), tile(1, 1)];
    assert_eq!(
        changed(&pool, &set, &tiles, None).expect("changed"),
        [Same, Inked, Inked, Same]
    );
}

/// A tile stored is changed where it is another tile — each of the four
/// compared with where another one goes.
#[test]
fn a_tile_is_compared_with_its_own_place() {
    let mut pool = Pool::default();
    let set = pool.drawn(pixel, (0, 0), (2, 2), |_, row| Some(row as u16));
    let tiles = [tile(1, 0), tile(0, 0), tile(1, 1), tile(0, 1)];
    assert_eq!(changed(&pool, &set, &tiles, None).expect("changed"), [Inked; 4]);
}

/// A stored tile put with no ink left is cleared — every alpha byte 0,
/// whatever its colour bytes hold — and one with a pixel's alpha left at
/// its first or its last word, the words the first lane and the last lane
/// of a tile's workgroup take, is inked.
#[test]
fn a_tile_with_no_ink_left_is_cleared() {
    let mut pool = Pool::default();
    let set = pool.drawn(pixel, (0, 0), (2, 2), |_, row| Some(row as u16));
    let last = TILE_TEXELS as usize - 1;
    let colour_only: Vec<u32> = tile(1, 0).iter().map(|word| word & 0x00ff_ffff).collect();
    let nothing = vec![0; TILE_TEXELS as usize];
    let tiles = [nothing, colour_only, only(0, 1 << 24), only(last, 1 << 24)];
    assert_eq!(
        changed(&pool, &set, &tiles, None).expect("changed"),
        [Cleared, Cleared, Inked, Inked]
    );
}

/// A lane that meets its tile's ink in a word the same as the stored one,
/// and only then a word unlike it with no ink, still answers inked: the
/// unlike word adds to what the lane holds and takes none of it away. Here
/// the two are the first lane's first and second words, the tile's first
/// and its 256th (write.wgsl's lanes take words 256 apart); every other
/// word is the stored 0.
#[test]
fn a_lane_keeps_the_ink_it_met_before_an_unlike_word() {
    const INK: u32 = 0x80ff_0000;
    let mut pool = Pool::default();
    let stored = |x, y| if (x, y) == (0, 0) { INK } else { 0 };
    let set = pool.drawn(stored, (0, 0), (1, 1), |_, _| Some(0));
    let mut tile = only(0, INK);
    tile[2 * TILE as usize] = 1;
    assert_eq!(changed(&pool, &set, &[tile], None).expect("changed"), [Inked]);
}

/// Where nothing is stored, a tile of nothing is the same — it is not
/// written and takes no slot —, and one with a word of anything at its
/// first, a middle or its last word is changed: inked where that word's
/// alpha is not 0, cleared where it is.
#[test]
fn a_tile_where_nothing_is_stored_is_changed_unless_it_is_nothing() {
    let mut pool = Pool::default();
    let set = pool.drawn(pixel, (0, 0), (4, 1), |_, _| None);
    let last = TILE_TEXELS as usize - 1;
    let tiles = [vec![0; TILE_TEXELS as usize], only(0, 1), only(8_000, 1 << 31), only(last, 1)];
    assert_eq!(
        changed(&pool, &set, &tiles, None).expect("changed"),
        [Same, Cleared, Inked, Cleared]
    );
}

/// Seven tiles on three pages and on none, the passes cut every way: each
/// pass's tiles find their words among the write's (`first`) and their
/// pages among the pass's — the first two, on no page, a run that binds
/// none where a pass takes two tiles and one page.
#[test]
fn a_write_cut_into_passes_says_what_one_pass_says() {
    let pages = [None, None, Some(0), None, Some(1), Some(2), Some(0)];
    let mut pool = Pool::default();
    let set = pool.drawn(pixel, (0, 0), (7, 1), |column, _| pages[column as usize]);
    let last = TILE_TEXELS as usize - 1;
    let tiles = [
        only(5, 3),
        vec![0; TILE_TEXELS as usize],
        tile(2, 0),
        vec![0; TILE_TEXELS as usize],
        off(tile(4, 0), last),
        tile(5, 0),
        off(tile(6, 0), 300),
    ];
    let wanted = [Cleared, Same, Same, Same, Inked, Same, Inked];
    assert_eq!(changed(&pool, &set, &tiles, None).expect("changed"), wanted);
    for cut in [(1, 1), (1, 2), (2, 2), (3, 2), (1, 7), (3, 7)] {
        assert_eq!(changed(&pool, &set, &tiles, Some(cut)).expect("cut"), wanted, "{cut:?}");
    }
}

/// A write of no tiles says nothing, and binds nothing.
#[test]
fn a_write_of_no_tiles_says_nothing() {
    let Rig { engine, write } = rig();
    let pages = Pool::default().upload(engine);
    let none = plane(engine, "no tiles", 4);
    assert_eq!(write.changed(engine, &pages, &none, &[]).expect("none"), Vec::<Change>::new());
}

/// Each tile named lands whole in its slot, over what was there or in a
/// slot of its own; the tiles not named and the slots not written stay as
/// they were.
#[test]
fn a_put_copies_each_tile_named_to_its_slot() {
    let Rig { engine, .. } = rig();
    let mut pool = Pool::default();
    let _ = pool.drawn(pixel, (0, 0), (3, 2), |_, row| Some(row as u16));
    let pages = pool.upload(engine);
    let tiles = [only(0, 7), tile(9, 9), only(40, 9)];
    let writes = [(2, TileAt { page: 0, slot: 1 }), (0, TileAt { page: 1, slot: 2 })];
    Write::put(engine, &pages, &put(&tiles), &writes).expect("put");
    assert_eq!(
        words(&read_buffer(engine, &pages[0])),
        [tile(0, 0), tiles[2].clone(), tile(2, 0)].concat()
    );
    assert_eq!(
        words(&read_buffer(engine, &pages[1])),
        [tile(0, 1), tile(1, 1), tiles[0].clone()].concat()
    );
}

/// A test or a put refuses a place past the pool — a page it has not, a
/// slot past a page's tiles —, tiles put short of the places, and a cut
/// that binds no page or takes no tile.
#[test]
fn a_write_refuses_what_is_not_there() {
    let Rig { engine, write } = rig();
    let mut pool = Pool::default();
    let set = pool.drawn(pixel, (0, 0), (2, 1), |_, _| Some(0));
    let pages = pool.upload(engine);
    let two = put(&[tile(0, 0), tile(1, 0)]);
    let past_page = [Some(TileAt { page: 1, slot: 0 })];
    let past_slot = [Some(TileAt { page: 0, slot: 2 })];
    assert!(write.changed(engine, &pages, &two, &past_page).is_none());
    assert!(write.changed(engine, &pages, &two, &past_slot).is_none());
    assert!(write.changed(engine, &pages, &put(&[tile(0, 0)]), &set.tiles).is_none());
    assert!(write.changed_by(engine, &pages, &two, &set.tiles, (0, 2)).is_none());
    assert!(write.changed_by(engine, &pages, &two, &set.tiles, (1, 0)).is_none());
    let to = |slot| TileAt { page: 0, slot };
    assert!(Write::put(engine, &pages, &two, &[(2, to(0))]).is_none());
    assert!(Write::put(engine, &pages, &two, &[(0, to(2))]).is_none());
    assert!(Write::put(engine, &pages, &two, &[(0, TileAt { page: 1, slot: 0 })]).is_none());
    // Each in a test of its own with a good one first: nothing is copied.
    let before = words(&read_buffer(engine, &pages[0]));
    assert!(Write::put(engine, &pages, &two, &[(1, to(0)), (2, to(1))]).is_none());
    assert_eq!(words(&read_buffer(engine, &pages[0])), before);
}

/// A put copies only from tiles a copy may read, to pages a copy may
/// write.
#[test]
fn a_put_refuses_buffers_no_copy_takes() {
    let Rig { engine, .. } = rig();
    let mut pool = Pool::default();
    let _ = pool.drawn(pixel, (0, 0), (1, 1), |_, _| Some(0));
    let pages = pool.upload(engine);
    let to = [(0, TileAt { page: 0, slot: 0 })];
    let unread = words_buffer(engine, "unread", &tile(0, 0), wgpu::BufferUsages::STORAGE);
    assert!(Write::put(engine, &pages, &unread, &to).is_none());
    let unwritable = [plane(engine, "unwritable page", TILE_TEXELS * 4)];
    assert!(Write::put(engine, &unwritable, &put(&[tile(0, 0)]), &to).is_none());
}
