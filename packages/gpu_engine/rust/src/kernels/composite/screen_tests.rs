//! The editing screen on a real GPU: the kept canvas against the canvas
//! composited anew — made whole on pages of any size, made again where it
//! changed — and the screen against the halvings showing that composite;
//! never against a CPU copy of a formula (`kernels/mod.rs` has why).

use super::{Screen, meets};
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::composite::halvings::tests::{CANVAS, SCREEN, camera, composite_of, kept_bytes, noise};
use crate::kernels::composite::halvings::{Camera, Halvings, Kept, Tiles};
use crate::kernels::composite::tests::{Rig, rig, surface};
use crate::kernels::composite::{Plan, Step, TILE, TileSet};
use crate::kernels::shared::ResampleMap;
use crate::testing::read_buffer;
use std::sync::LazyLock;

/// The one step laying a tile set whole and unposed: the canvas a composite
/// of it is.
static LAID: LazyLock<[Step; 1]> = LazyLock::new(|| {
    [Step::Row {
        set: 0,
        keys: None,
        chain: None,
        map: ResampleMap::moved(0, 0),
        matrix: None,
        opacity: 65535,
        mode: NORMAL,
        masked: false,
    }]
});

/// The plan laying `set`, on `pages`, by [`LAID`].
fn laid<'a>(pages: &'a [wgpu::Buffer], set: &'a TileSet) -> Plan<'a> {
    Plan {
        pages,
        sets: std::slice::from_ref(set),
        keys: &[],
        matrices: &[],
        chains: &[],
        steps: &*LAID,
        mask: None,
    }
}

/// `pixel` over the canvas, nothing past it, composited whole in one run:
/// what every kept canvas of it is held to.
fn composited_whole(pixel: impl Fn(i32, i32) -> u32) -> Vec<u8> {
    let Rig { engine, composite } = rig();
    let (pages, set, _) = composite_of(pixel, CANVAS);
    let size = (CANVAS.0.div_ceil(TILE) as i32, CANVAS.1.div_ceil(TILE) as i32);
    let tiles: Vec<(i32, i32)> = (0..size.1).flat_map(|row| (0..size.0).map(move |column| (column, row))).collect();
    let extent = [0, 0, CANVAS.0 as i32, CANVAS.1 as i32];
    let done = composite.run(engine, &laid(&pages, &set), &tiles, extent, composite.widest()).expect("run");
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
        let kept = Kept::made_by(engine, composite, &plan, CANVAS, per_page, composite.widest()).expect("kept");
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
    let kept = Kept::made_by(engine, composite, &laid(&pages, &set), CANVAS, 2, budget).expect("kept");
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
    let mut halvings = Halvings::new(CANVAS, 1.0).expect("halvings");
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
    let mut screen = Screen::new(CANVAS, 1.0).expect("screen");
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
    let mut screen = Screen::new(CANVAS, 1.0).expect("screen");
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
    let mut screen = Screen::new(CANVAS, 1.0).expect("screen");
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
}
