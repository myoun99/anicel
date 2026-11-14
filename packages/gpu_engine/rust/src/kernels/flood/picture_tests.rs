//! The fill's and the eyedropper's picture on a real GPU, checked against
//! what the plan shows by hand and against the composite's own hand cases
//! — never against a CPU copy of it (`kernels/mod.rs` has why).

use super::{Shown, pick};
use super::super::tests::rig;
use super::super::{Extent, Finished};
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::composite::tests::{Pool, Rig as CompositeRig, mix, rig as composite_rig};
use crate::kernels::composite::tests::with_map;
use crate::kernels::composite::{Plan, Step, TILE, TILE_TEXELS, TileSet, WHOLE};
use crate::kernels::dab::stamp::tests::stamps;
use crate::kernels::dab::stamp::{Paint, Source};
use crate::kernels::shared::{ResampleMap, ResampleMode, plane};
use crate::kernels::write::{Change, Write};
use crate::testing::{last_error, read_buffer};

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

// A box past what a binding holds is refused where it is asked for, with
// why — before a tile of it is counted out: the canvas's every pixel is
// 2^48 tiles.
#[test]
fn a_box_past_what_a_binding_holds_is_refused_before_it_is_composited() {
    let CompositeRig { engine, composite } = composite_rig();
    let pages = Pool::default().upload(engine);
    let extent = [i32::MIN, i32::MIN, i32::MAX, i32::MAX];
    assert!(Shown::of(engine, composite, &plan(&pages, &[], &[]), extent).is_none());
    assert!(last_error().contains("exceeds a binding"), "{}", last_error());
}

/// An opaque pixel of its own at every (x, y): one a composite lays over
/// nothing as it is.
fn opaque(x: i32, y: i32) -> u32 {
    mix(x as u32 ^ mix(y as u32)) | 0xff00_0000
}

/// `shown`'s pixel at (`x`, `y`) of its space, of `read` — its tiles'
/// words —, or none off its grid.
fn shown_at(shown: &Shown, read: &[u32], (x, y): (i32, i32)) -> Option<u32> {
    let (column, row) = shown.on_grid((x, y))?;
    let tile = (row / TILE) * shown.across + column / TILE;
    let texel = (row % TILE) * TILE + column % TILE;
    Some(read[(u64::from(tile) * TILE_TEXELS) as usize + texel as usize])
}

// A picture read from a space moved whole pixels on the canvas is the
// picture word for word, each pixel where the move lands it — over tiles
// on both sides of the canvas's origin, slot after slot —, and nothing
// where it lands off the picture's box or past the box asked.
#[test]
fn a_picture_read_from_a_moved_space_is_the_picture_moved() {
    let CompositeRig { engine, composite } = composite_rig();
    let mut pool = Pool::default();
    let sets = [pool.drawn(opaque, (-1, -1), (4, 3), |_, _| Some(0))];
    let pages = pool.upload(engine);
    let steps = [laid(0, WHOLE)];
    let on_canvas = [-100, -60, 200, 150];
    let shown = Shown::of(engine, composite, &plan(&pages, &sets, &steps), on_canvas);
    let shown = shown.expect("shown");
    // A pixel of the space is the canvas's 37 to its right and 9 above.
    let (dx, dy) = (37, -9);
    let to_canvas = [1.0, 0.0, f64::from(dx), 0.0, 1.0, f64::from(dy), 0.0, 0.0, 1.0];
    let asked = [-150, -70, 180, 170];
    let posed = shown.posed(engine, composite, to_canvas, asked).expect("posed");
    assert_eq!((posed.grid, posed.across, posed.down), ((-2, -1), 4, 3));
    let read = words(&posed.out);
    let side = TILE as i32;
    let within = |[left, top, right, bottom]: [i32; 4], (x, y): (i32, i32)| {
        (left..right).contains(&x) && (top..bottom).contains(&y)
    };
    for y in -side..2 * side {
        for x in -2 * side..2 * side {
            let lands = (x + dx, y + dy);
            let shows = within(asked, (x, y)) && within(on_canvas, lands);
            let want = if shows { opaque(lands.0, lands.1) } else { 0 };
            assert_eq!(shown_at(&posed, &read, (x, y)), Some(want), "({x}, {y})");
        }
    }
}

// A picture read from a space turned and moved off whole pixels on the
// canvas is what a row of the picture's pixels posed there shows, to the
// byte: one resample, the row's own (R1's tent mean on a radius of a pixel
// at least) — and it shows something.
#[test]
fn a_picture_read_from_a_posed_space_is_a_row_of_it_posed_there() {
    let CompositeRig { engine, composite } = composite_rig();
    let mut pool = Pool::default();
    let sets = [pool.drawn(opaque, (-1, -1), (2, 2), |_, _| Some(0))];
    let pages = pool.upload(engine);
    let (whole, on_canvas) = ([laid(0, WHOLE)], [-128, -128, 128, 128]);
    let shown = Shown::of(engine, composite, &plan(&pages, &sets, &whole), on_canvas);
    let shown = shown.expect("shown");
    // Turned by the 3-4-5 angle, moved by a quarter and a half pixel.
    let to_canvas = [0.8, -0.6, 10.25, 0.6, 0.8, -30.5, 0.0, 0.0, 1.0];
    let asked = [-200, -160, 184, 224];
    let posed = shown.posed(engine, composite, to_canvas, asked).expect("posed");
    let map = ResampleMap::new(to_canvas, 1.0, ResampleMode::Blend, 384, 384);
    let row = [with_map(0, map.expect("a pose that lands"), WHOLE, NORMAL)];
    let direct = Shown::of(engine, composite, &plan(&pages, &sets, &row), asked).expect("row");
    let read = words(&posed.out);
    assert!(read == words(&direct.out), "a picture posed is not the row posed");
    let inked = read.iter().filter(|&&word| word != 0).count();
    assert!(inked > 128 * 128, "{inked} pixels show");
}

// A pose that lands nothing on the canvas reads nothing of it, and is
// refused with why.
#[test]
fn a_picture_read_through_a_pose_that_lands_nothing_is_refused() {
    let shown = blue_shown();
    let CompositeRig { engine, composite } = composite_rig();
    assert!(shown.posed(engine, composite, [0.0; 9], [0, 0, 8, 8]).is_none());
    assert!(last_error().contains("lands nothing"), "{}", last_error());
}

// A plan read through a pose is shown over no more of the canvas than the
// pose can read: a world past what a binding holds refuses nothing, and the
// picture is the row posed straight, to the byte — to the corners of the
// box asked, whose tent reads the canvas farthest.
#[test]
fn a_plan_read_through_a_pose_is_shown_only_where_the_pose_reads() {
    let CompositeRig { engine, composite } = composite_rig();
    let mut pool = Pool::default();
    let sets = [pool.drawn(opaque, (-1, -1), (2, 2), |_, _| Some(0))];
    let pages = pool.upload(engine);
    let whole = [laid(0, WHOLE)];
    // Turned by the 3-4-5 angle, moved by a quarter and a half pixel: the
    // box asked lands inside the four tiles drawn, a slack from their edges.
    let to_canvas = [0.8, -0.6, 10.25, 0.6, 0.8, -30.5, 0.0, 0.0, 1.0];
    let (asked, world) = ([-40, -30, 50, 60], [i32::MIN, i32::MIN, i32::MAX, i32::MAX]);
    let drawn = plan(&pages, &sets, &whole);
    let through = Shown::through(engine, composite, &drawn, to_canvas, asked, world);
    let through = through.expect("through");
    let map = ResampleMap::new(to_canvas, 1.0, ResampleMode::Blend, 90, 90);
    let row = [with_map(0, map.expect("a pose that lands"), WHOLE, NORMAL)];
    let direct = Shown::of(engine, composite, &plan(&pages, &sets, &row), asked).expect("row");
    let read = words(&through.out);
    assert!(read == words(&direct.out), "a plan read through a pose is not the row posed");
    assert_eq!(read.iter().filter(|&&word| word != 0).count(), 90 * 90);
}

// A plan read through a pose shows nothing past the world its maker draws
// in: read from a space moved whole pixels, each pixel is the plan's where
// the move lands it inside the world, and nothing where it lands past it.
#[test]
fn a_plan_read_through_a_pose_shows_nothing_past_the_world() {
    let CompositeRig { engine, composite } = composite_rig();
    let mut pool = Pool::default();
    let sets = [pool.drawn(opaque, (-1, -1), (4, 3), |_, _| Some(0))];
    let pages = pool.upload(engine);
    let steps = [laid(0, WHOLE)];
    let (dx, dy) = (37, -9);
    let to_canvas = [1.0, 0.0, f64::from(dx), 0.0, 1.0, f64::from(dy), 0.0, 0.0, 1.0];
    let (asked, world) = ([-150, -70, 180, 170], [-100, -60, 40, 150]);
    let drawn = plan(&pages, &sets, &steps);
    let through = Shown::through(engine, composite, &drawn, to_canvas, asked, world);
    let through = through.expect("through");
    let read = words(&through.out);
    let side = TILE as i32;
    let within = |[left, top, right, bottom]: [i32; 4], (x, y): (i32, i32)| {
        (left..right).contains(&x) && (top..bottom).contains(&y)
    };
    for y in -side..2 * side {
        for x in -2 * side..2 * side {
            let lands = (x + dx, y + dy);
            let shows = within(asked, (x, y)) && within(world, lands);
            let want = if shows { opaque(lands.0, lands.1) } else { 0 };
            assert_eq!(shown_at(&through, &read, (x, y)), Some(want), "({x}, {y})");
        }
    }
}

// A pose that reads nothing of the world reads a picture of nothing over
// the box asked — pressed and flooded as any other.
#[test]
fn a_plan_read_through_a_pose_off_the_world_is_a_picture_of_nothing() {
    let CompositeRig { engine, composite } = composite_rig();
    let mut pool = Pool::default();
    let sets = [pool.drawn(opaque, (-1, -1), (2, 2), |_, _| Some(0))];
    let pages = pool.upload(engine);
    let steps = [laid(0, WHOLE)];
    // A pixel of the space is the canvas's 5000 to its right.
    let to_canvas = [1.0, 0.0, 5000.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
    let (asked, world) = ([-100, -60, 100, 60], [-128, -128, 128, 128]);
    let drawn = plan(&pages, &sets, &steps);
    let through = Shown::through(engine, composite, &drawn, to_canvas, asked, world);
    let through = through.expect("through");
    assert_eq!((through.grid, through.across, through.down), ((-1, -1), 2, 2));
    assert!(words(&through.out).iter().all(|&word| word == 0));
    assert_eq!(through.on_grid((-100, -60)), Some((28, 68)));
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
