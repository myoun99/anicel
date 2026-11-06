//! The fill's and the eyedropper's picture on a real GPU, checked against
//! what the plan shows by hand and against the composite's own hand cases
//! — never against a CPU copy of it (`kernels/mod.rs` has why).

use super::{Shown, pick};
use super::super::tests::rig;
use super::super::{Extent, Finished};
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::composite::tests::{Pool, Rig as CompositeRig, rig as composite_rig};
use crate::kernels::composite::{Plan, Step, TILE, TILE_TEXELS, TileSet, WHOLE};
use crate::kernels::dab::stamp::tests::stamps;
use crate::kernels::dab::stamp::{Paint, Source};
use crate::kernels::shared::{ResampleMap, plane};
use crate::kernels::write::{Change, Write};
use crate::testing::read_buffer;

const BLUE: u32 = 30 | 90 << 8 | 220 << 16 | 255 << 24;
const RED: u32 = 200 | 100 << 8 | 50 << 16 | 255 << 24;
const BLACK: u32 = 255 << 24;
const ORANGE: [u8; 3] = [200, 100, 50];

/// Tile set `set` laid where it lies at `opacity`, normal.
fn laid(set: usize, opacity: u32) -> Step {
    Step::Row {
        set,
        keys: None,
        chain: None,
        map: ResampleMap::moved(0, 0),
        matrix: None,
        opacity,
        mode: NORMAL,
        masked: false,
    }
}

fn plan<'a>(pages: &'a [wgpu::Buffer], sets: &'a [TileSet], steps: &'a [Step]) -> Plan<'a> {
    Plan {
        pages,
        sets,
        keys: &[],
        matrices: &[],
        chains: &[],
        steps,
        mask: None,
    }
}

/// `colour` at (`x`, `y`), but nothing at the `holes`.
fn holed(holes: &[(i32, i32)], colour: u32, x: i32, y: i32) -> u32 {
    if holes.contains(&(x, y)) { 0 } else { colour }
}

/// `buffer`'s words.
fn words(buffer: &wgpu::Buffer) -> Vec<u32> {
    read_buffer(composite_rig().engine, buffer)
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
        .collect()
}

/// Blue over tiles (-2, -1) to (2, 3), shown over (-3, -8) to (130, 250):
/// the grid from tile (-1, -1), three across and three down.
fn blue_shown() -> Shown {
    let CompositeRig { engine, composite } = composite_rig();
    let mut pool = Pool::default();
    let sets = [pool.drawn(|_, _| BLUE, (-2, -1), (5, 5), |_, _| Some(0))];
    let pages = pool.upload(engine);
    let steps = [laid(0, WHOLE)];
    let extent = [-3, -8, 130, 250];
    Shown::of(engine, composite, &plan(&pages, &sets, &steps), extent).expect("shown")
}

// The picture is what the plan shows on every tile the box meets, row
// after row, and nothing past the box.
#[test]
fn a_picture_is_what_the_plan_shows_on_the_tiles_its_box_meets() {
    let shown = blue_shown();
    let picture = shown.picture();
    assert_eq!((picture.across, picture.down), (3, 3));
    let inside = Extent {
        left: 125,
        top: 120,
        right: 258,
        bottom: 378,
    };
    assert_eq!(picture.inside, inside);
    let read = words(&shown.out);
    let side = TILE;
    for y in 0..3 * side {
        for x in 0..3 * side {
            let tile = (y / side) * 3 + x / side;
            let texel = (tile as u64 * TILE_TEXELS) as usize + ((y % side) * side + x % side) as usize;
            let shows = (125..258).contains(&x) && (120..378).contains(&y);
            assert_eq!(read[texel], if shows { BLUE } else { 0 }, "({x}, {y})");
        }
    }
}

// A press on the canvas lands on the picture's grid, none off it, and a
// fill finished on the picture lies on the canvas where it was flooded.
#[test]
fn a_press_and_a_fill_go_between_the_canvas_and_the_picture() {
    let shown = blue_shown();
    assert_eq!(shown.on_grid((-3, -8)), Some((125, 120)));
    assert_eq!(shown.on_grid((-128, -128)), Some((0, 0)));
    assert_eq!(shown.on_grid((255, 255)), Some((383, 383)));
    let off = [(-129, 0), (256, 0), (0, -129), (0, 256)].map(|at| shown.on_grid(at));
    assert_eq!(off, [None; 4]);
    let finished = Finished {
        mask: plane(composite_rig().engine, "finished", 16),
        crop: Extent {
            left: 125,
            top: 130,
            right: 130,
            bottom: 133,
        },
    };
    let mask = shown.on_canvas(&finished);
    assert_eq!((mask.at, mask.size.width, mask.size.height), ((-3, 2), 5, 3));
}

// A box that ends on a tile's edge shows no tile past it: a box of three
// whole tiles is those three.
#[test]
fn a_box_ending_on_a_tile_s_edge_shows_no_tile_past_it() {
    let CompositeRig { engine, composite } = composite_rig();
    let pages = Pool::default().upload(engine);
    let extent = [-128, 0, 256, 128];
    let shown = Shown::of(engine, composite, &plan(&pages, &[], &[]), extent).expect("shown");
    let picture = shown.picture();
    assert_eq!((picture.across, picture.down), (3, 1));
    assert_eq!([shown.on_grid((256, 0)), shown.on_grid((0, 128))], [None; 2]);
}

// A box with no pixel shows nothing to read, and is refused.
#[test]
fn a_box_of_no_pixel_is_refused() {
    let CompositeRig { engine, composite } = composite_rig();
    let pages = Pool::default().upload(engine);
    for extent in [[5, 5, 5, 9], [5, 5, 9, 5], [5, 5, 4, 9]] {
        let shown = Shown::of(engine, composite, &plan(&pages, &[], &[]), extent);
        assert!(shown.is_none(), "{extent:?}");
    }
}

// The eyedropper picks what shows: red at 128 over opaque blue is the
// masked red's bytes in the composite's tests, 115 and all; red at 128 over
// nothing its own colour (I-163-Q6: a part-covered pixel picks its ink's);
// and nothing where nothing is laid — a pixel of alpha 0, or no tile. The
// canvas's last column has no pixel past it to end a box, and is refused.
#[test]
fn the_eyedropper_picks_what_the_plan_shows_or_nothing() {
    let CompositeRig { engine, composite } = composite_rig();
    let mut pool = Pool::default();
    let sets = [
        pool.drawn(|x, y| holed(&[(7, 3), (9, 4)], BLUE, x, y), (0, 0), (1, 1), |_, _| Some(0)),
        pool.drawn(|x, y| holed(&[(7, 3)], RED, x, y), (0, 0), (1, 1), |_, _| Some(0)),
    ];
    let pages = pool.upload(engine);
    let steps = [laid(0, WHOLE), laid(1, 32896)];
    let plan = plan(&pages, &sets, &steps);
    let at = |point| pick(engine, composite, &plan, point).expect("pick");
    assert_eq!([at((1, 2)), at((3, 7))], [Some([115, 95, 135]); 2]);
    assert_eq!(at((9, 4)), Some(ORANGE));
    assert_eq!([at((7, 3)), at((200, 3)), at((-1, 0))], [None; 3]);
    assert!(pick(engine, composite, &plan, (i32::MAX, 0)).is_none());
}

// The whole fill on the engine, as a tap lays it (stage 5): what the plan
// shows is flooded from the press, finished, stamped in the fill's colour
// and laid on its cel as a stroke is, and the write path keeps what
// changed — a ring of black across two tiles is filled orange inside and
// nothing else, and the eyedropper then picks orange there.
#[test]
fn a_fill_floods_what_shows_and_lands_on_its_cel() {
    let CompositeRig { engine, composite } = composite_rig();
    let fills = rig();
    let ring = |x: i32, y: i32| {
        let on = (20..=180).contains(&x) && (20..=100).contains(&y);
        on && (x == 20 || x == 180 || y == 20 || y == 100)
    };
    let mut pool = Pool::default();
    let cel = pool.drawn(|x, y| if ring(x, y) { BLACK } else { 0 }, (0, 0), (2, 1), |_, _| Some(0));
    let places = cel.tiles.clone();
    let mut pages = pool.upload(engine);
    let mut sets = vec![cel];
    let extent = [0, 0, 256, 128];
    let shown = Shown::of(engine, composite, &plan(&pages, &sets, &[laid(0, WHOLE)]), extent);
    let shown = shown.expect("shown");
    let seed = shown.on_grid((50, 50)).expect("a press on the grid");
    let flooded = fills.flood.region(engine, &shown.picture(), seed, 0).expect("flood");
    let finished = fills.flood.finish(engine, &fills.masks, &flooded, 0, false).expect("finish");
    let mask = shown.on_canvas(&finished);
    let fill = Source::Mask { mask: &mask, paint: &Paint::Colour(ORANGE), whole: false };
    let stamped = stamps().stamp(engine, &fill, pages.len() as u16).expect("stamp");
    pages.extend(stamped.pages);
    sets.push(stamped.set);
    let steps = [laid(0, WHOLE), laid(1, WHOLE)];
    let tiles = [(0, 0), (1, 0)];
    let landed = composite.run(engine, &plan(&pages, &sets, &steps), &tiles, extent, composite.widest());
    let out = landed.expect("land").out;
    let write = Write::new(engine).expect("compile the write path");
    assert_eq!(write.changed(engine, &pages, &out, &places), Some(vec![Change::Inked; 2]));
    let writes: Vec<_> = places.iter().enumerate().map(|(k, at)| (k, at.unwrap())).collect();
    Write::put(engine, &pages, &out, &writes).expect("put");
    let cel_words = words(&pages[0]);
    let side = TILE as i32;
    for (slot, column) in [(0, 0), (1, 1)] {
        for y in 0..side {
            for x in column * side..(column + 1) * side {
                let inside = (21..180).contains(&x) && (21..100).contains(&y);
                let want = if ring(x, y) {
                    BLACK
                } else if inside {
                    RED
                } else {
                    0
                };
                let texel = slot * TILE_TEXELS as usize + (y * side + x % side) as usize;
                assert_eq!(cel_words[texel], want, "({x}, {y})");
            }
        }
    }
    let shows = plan(&pages, &sets[..1], &steps[..1]);
    let at = |point| pick(engine, composite, &shows, point).expect("pick");
    assert_eq!([at((50, 50)), at((179, 99))], [Some(ORANGE); 2]);
    assert_eq!([at((20, 20)), at((5, 5))], [Some([0, 0, 0]), None]);
}
