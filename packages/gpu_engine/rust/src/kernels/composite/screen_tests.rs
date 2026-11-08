//! The editing screen on a real GPU: the kept canvas against the canvas
//! composited anew — made whole on pages of any size, made again where it
//! changed — and the screen against the halvings showing that composite;
//! never against a CPU copy of a formula (`kernels/mod.rs` has why).

use super::{Screen, meets};
use crate::device::Engine;
use crate::kernels::composite::halvings::tests::{
    CANVAS, PAGE, SCREEN, camera, composite_of, composite_on, kept_bytes, noise,
};
use crate::kernels::composite::halvings::{Camera, Halvings, Kept, Tiles, plan, row};
use crate::kernels::composite::tests::{Pool, Rig, picture_of, rig, surface, surface_on};
use crate::kernels::composite::{Composite, Plan, Step, TILE, TileSet};
use crate::kernels::shared::tests::{premultiplied, window};
use crate::kernels::shared::{ResampleMap, ResampleMode};
use crate::testing::read_buffer;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, LazyLock};

/// The one step laying a tile set whole and unposed: the canvas a composite
/// of it is.
static LAID: LazyLock<[Step; 1]> = LazyLock::new(|| [row(ResampleMap::moved(0, 0))]);

/// The plan laying `set`, on `pages`, by [`LAID`].
fn laid<'a>(pages: &'a [wgpu::Buffer], set: &'a TileSet) -> Plan<'a> {
    plan(Tiles { pages, set }, &*LAID)
}

/// `pixel` over the canvas, nothing past it, composited whole in one run:
/// what every kept canvas of it is held to.
fn composited_whole(pixel: impl Fn(i32, i32) -> u32) -> Vec<u8> {
    let Rig { engine, composite } = rig();
    let (pages, set, _) = composite_of(pixel, CANVAS);
    let size = (CANVAS.0.div_ceil(TILE) as i32, CANVAS.1.div_ceil(TILE) as i32);
    let tiles: Vec<(i32, i32)> = (0..size.1).flat_map(|row| (0..size.0).map(move |column| (column, row))).collect();
    let done = composite.run(engine, &laid(&pages, &set), &tiles, PAGE, composite.widest()).expect("run");
    read_buffer(engine, &done.out)
}

fn inside([left, top, right, bottom]: [i32; 4], x: i32, y: i32) -> bool {
    left <= x && x < right && top <= y && y < bottom
}

// A canvas of 5 × 3 tiles kept a tile a page, two, four — the last page
// part full — and all on one is the canvas composited in one run.
#[test]
fn a_canvas_kept_on_pages_of_any_size_is_the_canvas_composited() {
    let Rig { engine, composite } = rig();
    let want = composited_whole(noise(31));
    let (pages, set, _) = composite_of(noise(31), CANVAS);
    for per_page in [1, 2, 4, 15] {
        let plan = laid(&pages, &set);
        let kept = Kept::made_by(engine, composite, &plan, PAGE, per_page, composite.widest()).expect("kept");
        assert_eq!(kept.as_tiles().pages.len(), 15usize.div_ceil(per_page), "{per_page} a page");
        assert!(kept_bytes(&kept) == want, "{per_page} a page");
    }
}

// Kept two tiles a page, the canvas is made again on the tiles each change
// meets — a stripe on a tile's last column, one on the next tile's first,
// a dot in each far corner, a block across four tiles of three pages — and
// is then the changed canvas composited anew. A change the stale tiles do
// not hold is kept as it was.
#[test]
fn a_kept_canvas_is_made_again_on_the_tiles_a_change_meets() {
    let Rig { engine, composite } = rig();
    let (pages, set, _) = composite_of(noise(53), CANVAS);
    let budget = composite.widest();
    let kept = Kept::made_by(engine, composite, &laid(&pages, &set), PAGE, 2, budget).expect("kept");
    let mut pixel: Box<dyn Fn(i32, i32) -> u32> = Box::new(noise(53));
    let rounds = [
        vec![[127, 40, 128, 90]],
        vec![[128, 200, 129, 260]],
        vec![[0, 0, 1, 1], [516, 300, 517, 301]],
        vec![[250, 120, 270, 140]],
    ];
    for changes in rounds {
        for change in &changes {
            let (before, change) = (pixel, *change);
            pixel = Box::new(move |x, y| if inside(change, x, y) { 0xff00_ff00 } else { before(x, y) });
        }
        let (pages, set, _) = composite_of(&pixel, CANVAS);
        let stale = |tile| changes.iter().any(|&change| meets(tile, change));
        let made = kept.made_again(engine, composite, &laid(&pages, &set), stale, budget).expect("made again");
        assert!(made.is_some(), "{changes:?}");
        assert!(kept_bytes(&kept) == composited_whole(&pixel), "{changes:?}");
    }
    let before = kept_bytes(&kept);
    let unmarked = move |x, y| if inside([400, 10, 420, 30], x, y) { 0 } else { pixel(x, y) };
    let (pages, set, _) = composite_of(&unmarked, CANVAS);
    let made = kept.made_again(engine, composite, &laid(&pages, &set), |tile| tile == (0, 2), budget);
    assert_eq!(made.expect("made again"), Some([0, 256, 128, 384]));
    assert!(kept_bytes(&kept) == before, "the tile made again holds no change");
    assert!(composited_whole(&unmarked) != before, "the change not marked is one the canvas shows");
}

/// `screen` shown through `camera`, the surface read back.
fn shown_by(screen: &mut Screen, camera: Camera) -> Vec<u8> {
    let Rig { engine, composite } = rig();
    let texture = surface(SCREEN, wgpu::TextureFormat::Rgba8Unorm);
    let whole = [0, 0, SCREEN.0, SCREEN.1];
    screen.show(engine, composite, camera, &texture, whole, composite.widest()).expect("show");
    engine.read_texture(&texture).expect("read the surface back")
}

/// `canvas` shown through `camera` by halvings of its own.
fn halvings_show(canvas: Tiles, camera: Camera) -> Vec<u8> {
    let Rig { engine, composite } = rig();
    let texture = surface(SCREEN, wgpu::TextureFormat::Rgba8Unorm);
    let whole = [0, 0, SCREEN.0, SCREEN.1];
    let mut halvings = Halvings::new(PAGE, 1.0).expect("halvings");
    halvings.show(engine, composite, canvas, camera, &texture, whole, composite.widest()).expect("show");
    engine.read_texture(&texture).expect("read the surface back")
}

// The screen composes the canvas and shows it as halvings show that
// composite — magnified and turned, shrunk, and past 1/16 on a stage — and
// a change composed on it is shown at every scale, the stage it reads made
// again: the screen is the canvas's composite through the camera.
#[test]
fn the_screen_shows_its_canvas_as_the_halvings_show_the_composite() {
    let Rig { engine, composite } = rig();
    let budget = composite.widest();
    let cameras = [
        camera(3.0, (0.8, 0.6), (-200.25, -40.5)),
        camera(0.4, (1.0, 0.0), (3.0, 2.0)),
        camera(0.03, (1.0, 0.0), (20.75, 18.0)),
    ];
    let mut screen = Screen::new(PAGE, 1.0).expect("screen");
    let (pages, set, _) = composite_of(noise(17), CANVAS);
    screen.compose(engine, composite, &laid(&pages, &set), [0, 0, 1, 1], budget).expect("compose");
    for &camera in &cameras {
        assert!(shown_by(&mut screen, camera) == halvings_show(Tiles { pages: &pages, set: &set }, camera));
    }
    let change = [60, 30, 300, 200];
    let red = move |x, y| if inside(change, x, y) { 0xff00_00ff } else { noise(17)(x, y) };
    let (pages, set, _) = composite_of(red, CANVAS);
    screen.compose(engine, composite, &laid(&pages, &set), change, budget).expect("compose");
    for &camera in &cameras {
        assert!(shown_by(&mut screen, camera) == halvings_show(Tiles { pages: &pages, set: &set }, camera));
    }
}

// The first composite lays the canvas whole, whatever it is told changed;
// after it an empty change composites nothing — a plan of other pixels
// leaves the canvas as it was.
#[test]
fn the_first_composite_is_whole_and_an_empty_change_composites_nothing() {
    let Rig { engine, composite } = rig();
    let budget = composite.widest();
    let mut screen = Screen::new(PAGE, 1.0).expect("screen");
    let (pages, set, _) = composite_of(noise(5), CANVAS);
    screen.compose(engine, composite, &laid(&pages, &set), [0, 0, 0, 0], budget).expect("compose");
    let whole = canvas_bytes(&screen);
    assert!(whole == composited_whole(noise(5)));
    let (pages, set, _) = composite_of(noise(6), CANVAS);
    for empty in [[0, 0, 0, 0], [40, 40, 40, 90], [40, 40, 90, 40], [90, 40, 40, 90]] {
        screen.compose(engine, composite, &laid(&pages, &set), empty, budget).expect("compose");
        assert!(canvas_bytes(&screen) == whole, "{empty:?}");
    }
}

/// The canvas `screen` keeps, read back.
fn canvas_bytes(screen: &Screen) -> Vec<u8> {
    kept_bytes(screen.canvas.as_ref().expect("a canvas"))
}

// A screen shows its canvas once one is composed, and says so before.
#[test]
fn a_screen_is_shown_once_its_canvas_is_composed() {
    let Rig { engine, composite } = rig();
    let mut screen = Screen::new(PAGE, 1.0).expect("screen");
    let texture = surface(SCREEN, wgpu::TextureFormat::Rgba8Unorm);
    let shown = screen.show(engine, composite, camera(1.0, (1.0, 0.0), (0.0, 0.0)), &texture, [0, 0, 1, 1], composite.widest());
    assert!(shown.is_none());
    assert_eq!(crate::last_error(), "a screen is shown before anything is composed on it");
}

// A tile meets a rectangle holding one of its pixels: its first and last
// column and row, and not the pixel just past either.
#[test]
fn a_tile_meets_a_rectangle_holding_a_pixel_of_it() {
    assert!(meets((1, 0), [128, 0, 129, 1]));
    assert!(meets((1, 0), [255, 127, 256, 128]));
    assert!(!meets((1, 0), [127, 0, 128, 1]));
    assert!(!meets((1, 0), [256, 0, 257, 1]));
    assert!(!meets((1, 0), [128, 128, 129, 129]));
    assert!(meets((-1, -1), [-1, -1, 0, 0]));
    assert!(!meets((1, 0), [130, 10, 130, 20]));
    assert!(!meets((1, 0), [130, 10, 140, 10]));
    assert!(!meets((1, 0), [130, -20, 140, 0]));
}

// A screen shown is done on the GPU when show returns (Composite::show's
// 🚨): on an engine of its own — the tests' one is polled by every test at
// once —, the work submitted before the show is seen done inside it, and
// nothing it submitted is left after it.
#[test]
fn a_screen_shown_is_done_on_the_gpu_when_show_returns() {
    let engine = Engine::open_first().expect("an engine of its own");
    let composite = Composite::new(&engine).expect("its executor");
    let mut screen = Screen::new(PAGE, 1.0).expect("screen");
    let (pages, set, _) = composite_on(&engine, noise(23), CANVAS);
    screen.compose(&engine, &composite, &laid(&pages, &set), [0, 0, 1, 1], composite.widest()).expect("compose");
    let seen = Arc::new(AtomicBool::new(false));
    let flag = Arc::clone(&seen);
    engine.queue.on_submitted_work_done(move || flag.store(true, Ordering::SeqCst));
    let size = (1024, 768);
    let texture = surface_on(&engine, size, wgpu::TextureFormat::Rgba8Unorm);
    let camera = Camera { size, ..camera(1.7, (0.6, 0.8), (500.0, 100.0)) };
    let whole = [0, 0, size.0, size.1];
    screen.show(&engine, &composite, camera, &texture, whole, composite.widest()).expect("show");
    assert!(seen.load(Ordering::SeqCst), "the show waited on nothing");
    let after = engine.device.poll(wgpu::PollType::Poll).expect("poll");
    assert!(after.is_queue_empty(), "the show left {after:?}");
}

/// `pixel` over the pixels `extent`, nothing past it, on the tiles holding
/// them — before the origin too.
fn drawn_over(pixel: impl Fn(i32, i32) -> u32, extent: [i32; 4]) -> (Vec<wgpu::Buffer>, TileSet) {
    let side = TILE as i32;
    let [left, top, right, bottom] = extent;
    let first = (left.div_euclid(side), top.div_euclid(side));
    let end = ((right - 1).div_euclid(side) + 1, (bottom - 1).div_euclid(side) + 1);
    let tiles = ((end.0 - first.0) as u32, (end.1 - first.1) as u32);
    let held = |x, y| if inside(extent, x, y) { pixel(x, y) } else { 0 };
    let mut pool = Pool::default();
    let set = pool.drawn(held, first, tiles, |_, _| Some(0));
    (pool.upload(rig().engine), set)
}

// A screen over pixels before the page — left of it and over it, where a
// stroke on the pasteboard takes a frame's world — shows what one at the
// origin over the same picture shows through the camera moved with it:
// moved off the tile grid at 1/16 and over, and under it by whole tiles,
// so each stage it reads lies on the origin's stage's pixels.
#[test]
fn a_screen_before_the_page_shows_as_one_at_the_origin() {
    let Rig { engine, composite } = rig();
    let budget = composite.widest();
    let near = [camera(0.5, (1.0, 0.0), (-40.25, -20.5)), camera(2.0, (1.0, 0.0), (-300.5, -100.25))];
    let far = [camera(0.03125, (1.0, 0.0), (20.5, 18.0)), camera(0.0078125, (1.0, 0.0), (2.0, 1.5))];
    for ((x, y), cameras) in [((200, 150), &near[..]), ((256, 128), &far[..])] {
        let before = [-x, -y, PAGE[2] - x, PAGE[3] - y];
        let mut screen = Screen::new(before, 1.0).expect("screen");
        let (pages, set) = drawn_over(move |at_x, at_y| noise(29)(at_x + x, at_y + y), before);
        screen.compose(engine, composite, &laid(&pages, &set), before, budget).expect("compose");
        let mut origin = Screen::new(PAGE, 1.0).expect("screen");
        let (pages, set, _) = composite_of(noise(29), CANVAS);
        origin.compose(engine, composite, &laid(&pages, &set), PAGE, budget).expect("compose");
        for &camera in cameras {
            let mut moved = camera;
            moved.inverse[2] += f64::from(x);
            moved.inverse[5] += f64::from(y);
            let scale = camera.scale;
            let shown = shown_by(&mut screen, camera);
            assert!(shown.iter().any(|&byte| byte != 0), "({x}, {y}) at {scale} shows nothing");
            assert!(shown == shown_by(&mut origin, moved), "({x}, {y}) at {scale}");
        }
    }
}

// The screen is its two stages as R1 does each (c6 ④'s pins, 관제 11-08):
// a row turned 17° about the canvas's middle laid on the canvas at its own
// pixels, then the camera at zooms of no whole number — 1.37 in Nearest
// and 0.61 in Blend, as the app samples each — over the canvas's tile
// edges at x = 128 and y = 128: R1's harness over R1's harness, so no seam
// lies where one kept tile meets the next.
#[test]
fn the_screen_is_r1_through_the_camera_over_r1_laying_a_turned_row() {
    let Rig { engine, composite } = rig();
    let size = (2 * TILE, 2 * TILE);
    let (pages, set, source) = composite_of(noise(37), size);
    let (sin, cos) = 17f64.to_radians().sin_cos();
    let middle = f64::from(TILE);
    let turned = [cos, sin, middle * (1.0 - cos - sin), -sin, cos, middle * (1.0 - cos + sin), 0.0, 0.0, 1.0];
    let turned = ResampleMap::new(turned, 1.0, ResampleMode::Blend, size.0, size.1).expect("lands");
    let canvas = window(&turned, &source, size, (0, 0));
    let canvas = picture_of(|x, y| canvas[(y as u32 * size.0 + x as u32) as usize], size);
    let steps = [row(turned)];
    let whole = [0, 0, size.0 as i32, size.1 as i32];
    let mut screen = Screen::new(whole, 1.0).expect("screen");
    screen.compose(engine, composite, &plan(Tiles { pages: &pages, set: &set }, &steps), whole, composite.widest()).expect("compose");
    // The canvas's middle at the screen's.
    let at_middle = |scale: f64| (f64::from(SCREEN.0 / 2) - middle * scale, f64::from(SCREEN.1 / 2) - middle * scale);
    let cameras = [
        Camera { mode: ResampleMode::Nearest, ..camera(1.37, (1.0, 0.0), at_middle(1.37)) },
        camera(0.61, (1.0, 0.0), at_middle(0.61)),
    ];
    for camera in cameras {
        let map = ResampleMap::new(camera.inverse, 1.0, camera.mode, SCREEN.0, SCREEN.1).expect("lands");
        let by_r1: Vec<u8> = premultiplied(&window(&map, &canvas, SCREEN, (0, 0))).into_iter().flat_map(u32::to_le_bytes).collect();
        let scale = camera.scale;
        assert!(shown_by(&mut screen, camera) == by_r1, "at {scale}");
    }
}
