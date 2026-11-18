//! The editing screen on a real GPU: the kept canvas against the canvas
//! composited anew — made whole on pages of any size, made again where it
//! changed — and the screen against R1's own harness over that composite
//! and against the composite shown through the camera unkept; never
//! against a CPU copy of a formula (`kernels/mod.rs` has why).

use super::{Camera, Screen, affine, meets, row};
use crate::device::{Engine, gpu_engine_waits_here};
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::composite::abi::{gpu_engine_pictures_give_back, gpu_engine_pictures_idle_bytes};
use crate::kernels::composite::kept::tests::kept_bytes;
use crate::kernels::composite::kept::{Film, Kept, Tiles, plan};
use crate::kernels::composite::tests::{Pool, Rig, picture_of, rig, surface, surface_on, texel};
use crate::kernels::composite::{Budget, Composite, Plan, Step, TILE, TILE_BYTES, TileSet};
use crate::kernels::pool::Pictures;
use crate::kernels::shared::tests::{Picture, premultiplied, window};
use crate::kernels::shared::{ResampleMap, ResampleMode};
use crate::testing::{a_device_of_its_own, assert_pinned, last_error, read_buffer};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, LazyLock};
use std::time::Duration;

/// The canvas: odd both ways, its last column and row of tiles part full.
const CANVAS: (u32, u32) = (517, 301);
/// The canvas's pixels, [left, top, right, bottom): its page.
const PAGE: [i32; 4] = [0, 0, CANVAS.0 as i32, CANVAS.1 as i32];
const SCREEN: (u32, u32) = (64, 48);
/// The screen's floor, 1 (`resampleRadiusFloor`), and a wider one: the
/// camera samples on the floor the screen was made with.
const FLOORS: [f64; 2] = [1.0, 4.0];

/// A composite of `pixel` over a canvas of `size`, nothing past it, as a
/// composite ending at the canvas leaves it: its page, its tile set and its
/// pixels as R1's harness takes a source.
fn composite_of(pixel: impl Fn(i32, i32) -> u32, size: (u32, u32)) -> (Vec<wgpu::Buffer>, TileSet, Picture) {
    composite_on(rig().engine, pixel, size)
}

/// [`composite_of`] on `engine`.
fn composite_on(
    engine: &Engine,
    pixel: impl Fn(i32, i32) -> u32,
    (width, height): (u32, u32),
) -> (Vec<wgpu::Buffer>, TileSet, Picture) {
    let inside = |x: i32, y: i32| {
        let within = x < width as i32 && y < height as i32;
        if within { pixel(x, y) } else { 0 }
    };
    let tiles = (width.div_ceil(TILE), height.div_ceil(TILE));
    let mut pool = Pool::default();
    let set = pool.drawn(&inside, (0, 0), tiles, |_, _| Some(0));
    let picture = picture_of(&inside, (tiles.0 * TILE, tiles.1 * TILE));
    (pool.upload(engine), set, picture)
}

fn noise(seed: u32) -> impl Fn(i32, i32) -> u32 {
    move |x, y| texel(seed, x, y)
}

/// The camera at `scale`, turned by (cos, sin), the canvas's origin at
/// `pan` on the screen, in Blend.
fn camera(scale: f64, (cos, sin): (f64, f64), (x, y): (f64, f64)) -> Camera {
    let (a, b, d, e) = (cos / scale, sin / scale, -sin / scale, cos / scale);
    Camera {
        inverse: [a, b, -(a * x + b * y), d, e, -(d * x + e * y)],
        mode: ResampleMode::Blend,
    }
}

/// The scale `camera` shows at: what a failure names it by.
fn scale_of(camera: Camera) -> f64 {
    1.0 / camera.inverse[0].hypot(camera.inverse[1])
}

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
    let (pages, set, _) = composite_of(pixel, CANVAS);
    run_over_the_page(&laid(&pages, &set))
}

/// The page's tiles, row after row: every output tile of a run over it.
fn page_tiles() -> Vec<(i32, i32)> {
    let size = (CANVAS.0.div_ceil(TILE) as i32, CANVAS.1.div_ceil(TILE) as i32);
    (0..size.1).flat_map(|row| (0..size.0).map(move |column| (column, row))).collect()
}

/// `plan` composited over every tile of the page in one run.
fn run_over_the_page(plan: &Plan) -> Vec<u8> {
    let Rig { engine, composite } = rig();
    let done = composite.run(engine, plan, &page_tiles(), PAGE, composite.widest()).expect("run");
    read_buffer(engine, &done.out)
}

fn inside([left, top, right, bottom]: [i32; 4], x: i32, y: i32) -> bool {
    left <= x && x < right && top <= y && y < bottom
}

/// `plan` composited over the page and kept in `pictures`.
fn kept_in(pictures: &Pictures, plan: &Plan) -> Kept {
    let Rig { engine, composite } = rig();
    Kept::made_in(engine, composite, plan, PAGE, None, pictures, composite.widest()).expect("kept")
}

/// What `pictures` keeps and no picture holds ([`Pictures::idle_bytes`]),
/// once the pages' thread has made the page its pictures asked for ahead —
/// where less than half a page was left free (`Pool::make_a_page_ahead`).
fn idle_of(pictures: &Pictures) -> u64 {
    rig().engine.on_pages_thread(|| ());
    pictures.idle_bytes()
}

// A canvas of 5 × 3 tiles kept in a pool of a tile a page, two, four — the
// last page part full — and all on one is the canvas composited in one
// run, on as many pages as its tiles take.
#[test]
fn a_canvas_kept_on_pages_of_any_size_is_the_canvas_composited() {
    let want = composited_whole(noise(31));
    let (pages, set, _) = composite_of(noise(31), CANVAS);
    for per_page in [1, 2, 4, 15] {
        let pictures = Pictures::sized(per_page).expect("a pool");
        let kept = kept_in(&pictures, &laid(&pages, &set));
        assert_eq!(pictures.pages().len(), 15usize.div_ceil(per_page), "{per_page} a page");
        assert!(kept_bytes(&kept) == want, "{per_page} a page");
    }
}

// A canvas whose run takes several passes — its row's tiles on three
// pages, a page a pass — is kept as that run puts it: its output tiles
// wait in the work buffer past the stack one pass keeps for the next, and
// go to their slots from there.
#[test]
fn a_canvas_composited_in_several_passes_is_kept_as_the_run_puts_it() {
    let Rig { engine, composite } = rig();
    let mut pool = Pool::default();
    let set = pool.drawn(noise(31), (0, 0), (5, 3), |column, _| Some(column as u16 % 3));
    let pages = pool.upload(engine);
    let plan = laid(&pages, &set);
    let budget = Budget { pages: 1, ..composite.widest() };
    let tiles: Vec<(i32, i32)> = (0..3).flat_map(|row| (0..5).map(move |column| (column, row))).collect();
    let done = composite.run(engine, &plan, &tiles, PAGE, budget).expect("run");
    assert!(done.passes > 1, "the premise: a page a pass");
    let pictures = Pictures::sized(4).expect("a pool");
    let kept = Kept::made_in(engine, composite, &plan, PAGE, None, &pictures, budget).expect("kept");
    assert!(kept_bytes(&kept) == read_buffer(engine, &done.out));
}

// A picture let go leaves its slots free and its pages made: the next is
// kept on them — no page made for it — and is its own canvas composited,
// whatever the last left there.
#[test]
fn a_picture_let_go_leaves_its_pages_to_the_next() {
    let pictures = Pictures::sized(4).expect("a pool");
    let (pages, set, _) = composite_of(noise(31), CANVAS);
    let first = kept_in(&pictures, &laid(&pages, &set));
    let made = pictures.pages();
    assert_eq!(made.len(), 4);
    assert_eq!(idle_of(&pictures), 5 * TILE_BYTES, "15 tiles on pages of 16, and the page made ahead");
    drop(first);
    assert_eq!(idle_of(&pictures), 20 * TILE_BYTES);
    let (pages, set, _) = composite_of(noise(53), CANVAS);
    let next = kept_in(&pictures, &laid(&pages, &set));
    assert!(pictures.pages() == made, "a page is made for it");
    assert!(kept_bytes(&next) == composited_whole(noise(53)));
}

// Given back, the pool keeps no page no picture is on, and no picture
// keeps one made: a picture names the pages its tiles are on and no other,
// so one on the second page is as it was with the first given back, the
// next picture is kept in the place given back, and the last page, no
// picture's, is cut off.
#[test]
fn a_page_no_picture_is_on_is_given_back_and_no_picture_keeps_it_made() {
    let engine = rig().engine;
    let pictures = Pictures::sized(15).expect("a pool");
    let (pages, set, _) = composite_of(noise(31), CANVAS);
    let plan = laid(&pages, &set);
    let want = composited_whole(noise(31));
    let (first, second) = (kept_in(&pictures, &plan), kept_in(&pictures, &plan));
    let made = pictures.pages();
    assert_eq!(made.len(), 2);
    assert!(first.as_tiles().pages == &made[..1], "a picture names the pages up to its last");
    assert!(second.as_tiles().pages.iter().all(|page| *page == made[1]), "and none it is not on");
    drop(first);
    pictures.give_back(engine, 0);
    assert_eq!(idle_of(&pictures), TILE_BYTES, "the page given back's stand-in");
    assert!(kept_bytes(&second) == want);
    let third = kept_in(&pictures, &plan);
    assert_eq!(pictures.pages().len(), 2, "made again in the place given back");
    assert_eq!(idle_of(&pictures), 15 * TILE_BYTES, "the page made ahead of the next");
    assert!(kept_bytes(&third) == want && kept_bytes(&second) == want);
    drop(second);
    pictures.give_back(engine, 0);
    assert_eq!(pictures.pages().len(), 1, "the last page, no picture's, is cut off");
    assert!(kept_bytes(&third) == want);
}

// Given back past what may stay idle, the pool gives back its pages no
// picture is on, the last first, till the slots no picture holds are that
// many bytes — not till its pages are: the page a picture is on is none of
// what is idle, so of two pages no picture's one stays where a page may.
#[test]
fn the_pictures_pool_gives_back_till_what_is_idle_is_what_may_stay() {
    let engine = rig().engine;
    let pictures = Pictures::sized(15).expect("a pool");
    let (pages, set, _) = composite_of(noise(31), CANVAS);
    let plan = laid(&pages, &set);
    let kept = kept_in(&pictures, &plan);
    drop((kept_in(&pictures, &plan), kept_in(&pictures, &plan)));
    let page = 15 * TILE_BYTES;
    assert_eq!(pictures.pages().len(), 3, "the premise: a page a picture");
    assert_eq!(idle_of(&pictures), 3 * page, "two pages no picture is on, and the page made ahead");
    pictures.give_back(engine, page);
    assert_eq!(pictures.pages().len(), 2);
    assert_eq!(idle_of(&pictures), page);
    assert!(kept_bytes(&kept) == composited_whole(noise(31)));
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
    let pictures = Pictures::sized(2).expect("a pool");
    let mut kept = kept_in(&pictures, &laid(&pages, &set));
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
        kept.made_again(engine, composite, &laid(&pages, &set), stale, budget).expect("made again");
        assert!(kept_bytes(&kept) == composited_whole(&pixel), "{changes:?}");
    }
    let before = kept_bytes(&kept);
    let unmarked = move |x, y| if inside([400, 10, 420, 30], x, y) { 0 } else { pixel(x, y) };
    let (pages, set, _) = composite_of(&unmarked, CANVAS);
    kept.made_again(engine, composite, &laid(&pages, &set), |tile| tile == (0, 2), budget).expect("made again");
    assert!(kept_bytes(&kept) == before, "the tile made again holds no change");
    assert!(composited_whole(&unmarked) != before, "the change not marked is one the canvas shows");
}

/// The tile pixel (`x`, `y`) lies on.
fn tile_of(x: i32, y: i32) -> (i32, i32) {
    let side = TILE as i32;
    (x.div_euclid(side), y.div_euclid(side))
}

// Over a film, a canvas is made from its own plan on the tiles fresh marks
// meet — a stripe on a tile's last column, a block across four tiles of
// three pages — and is the film's as it is on every other; over a film of
// fewer tiles, its own past them too. Kept in a pool of a tile a page,
// two, and fifteen alike — and the film is as it was under it.
#[test]
fn a_canvas_made_over_a_film_is_its_own_where_fresh_and_the_films_elsewhere() {
    let Rig { engine, composite } = rig();
    let budget = composite.widest();
    let marks = [[127, 40, 128, 90], [250, 120, 270, 140]];
    let fresh = |tile| marks.iter().any(|&mark| meets(tile, mark));
    let (pages, set, _) = composite_of(noise(53), CANVAS);
    let film = laid(&pages, &set);
    let (pages, set, _) = composite_of(noise(71), CANVAS);
    let frame = laid(&pages, &set);
    let wants = [(5, 3), (2, 2)].map(|(columns, rows)| {
        composited_whole(|x, y| {
            let (column, row) = tile_of(x, y);
            let theirs = !fresh((column, row)) && column < columns && row < rows;
            if theirs { noise(53)(x, y) } else { noise(71)(x, y) }
        })
    });
    for per_page in [1, 2, 15] {
        let pictures = Pictures::sized(per_page).expect("a pool");
        let wide = kept_in(&pictures, &film);
        let narrow = Kept::made_in(engine, composite, &film, [0, 0, 256, 256], None, &pictures, budget).expect("film");
        for (under, want) in [&wide, &narrow].into_iter().zip(&wants) {
            let theirs = kept_bytes(under);
            let over: Film = (under, &fresh);
            let kept = Kept::made_in(engine, composite, &frame, PAGE, Some(over), &pictures, budget).expect("over");
            assert!(kept_bytes(&kept) == *want, "{per_page} a page");
            assert!(kept_bytes(under) == theirs, "{per_page} a page: the film under it");
        }
    }
}

// A picture laid over a film holds the film's own slots where it is not
// fresh — one slot more for its one fresh tile, nothing copied — and
// neither writes over a slot the other holds: a tile made again on either
// goes to a fresh slot, the other's bytes as they were. The film let go,
// its tiles the picture shows stay the picture's, whatever the next
// picture is kept on.
#[test]
fn a_picture_over_a_film_holds_the_films_slots_and_neither_writes_over_them() {
    let Rig { engine, composite } = rig();
    let budget = composite.widest();
    let pictures = Pictures::sized(15).expect("a pool");
    let (pages, set, _) = composite_of(noise(53), CANVAS);
    let mut film = kept_in(&pictures, &laid(&pages, &set));
    let (pages, set, _) = composite_of(noise(71), CANVAS);
    let frame = laid(&pages, &set);
    let fresh = |tile| tile == (0, 0);
    let over: Film = (&film, &fresh);
    let mut kept = Kept::made_in(engine, composite, &frame, PAGE, Some(over), &pictures, budget).expect("over");
    let idle = || idle_of(&pictures) / TILE_BYTES;
    assert_eq!((pictures.pages().len(), idle()), (2, 14), "16 slots held of 30");
    let weighed = |film: &Kept, kept: &Kept| [film.bytes(), kept.bytes(), pictures.unowned_bytes()].map(|bytes| bytes / TILE_BYTES);
    assert_eq!(weighed(&film, &kept), [15, 1, 0], "a tile shared is weighed once, by the picture that made it");
    let (theirs, its) = (kept_bytes(&film), kept_bytes(&kept));
    let (pages, set, _) = composite_of(noise(31), CANVAS);
    let other = laid(&pages, &set);
    film.made_again(engine, composite, &other, |tile| tile == (1, 0), budget).expect("made again");
    assert!(kept_bytes(&film) != theirs, "the film's tile is made again");
    assert!(kept_bytes(&kept) == its, "the film wrote over a tile the picture holds");
    assert_eq!(weighed(&film, &kept), [15, 1, 1], "the tile the film let go and the picture holds is nobody's own");
    let theirs = kept_bytes(&film);
    kept.made_again(engine, composite, &frame, |tile| tile == (2, 0), budget).expect("made again");
    let want = composited_whole(|x, y| match tile_of(x, y) {
        (0, 0) | (2, 0) => noise(71)(x, y),
        _ => noise(53)(x, y),
    });
    assert!(kept_bytes(&kept) == want);
    assert!(kept_bytes(&film) == theirs, "the picture wrote over a tile the film holds");
    assert_eq!(idle(), 12, "each tile made again took a slot the other left held");
    assert_eq!(weighed(&film, &kept), [15, 2, 1]);
    drop(film);
    assert_eq!(idle(), 15, "the film's own three are free");
    assert_eq!((kept.bytes(), pictures.unowned_bytes()), (2 * TILE_BYTES, 13 * TILE_BYTES), "and the picture's 15 held");
    let next = kept_in(&pictures, &other);
    assert_eq!((pictures.pages().len(), idle()), (2, 15), "and the page made ahead of the next");
    assert!(kept_bytes(&next) == composited_whole(noise(31)));
    assert!(kept_bytes(&kept) == want, "the next picture took a slot the picture holds");
}

// A picture is not laid over a film kept in another pool: a tile of one is
// no tile of the other's pages.
#[test]
fn a_picture_is_not_laid_over_a_film_of_another_pool() {
    let Rig { engine, composite } = rig();
    let (pages, set, _) = composite_of(noise(53), CANVAS);
    let plan = laid(&pages, &set);
    let (one, other) = (Pictures::sized(15).expect("a pool"), Pictures::sized(15).expect("a pool"));
    let film = kept_in(&one, &plan);
    let over: Film = (&film, &|_| false);
    let laid_over = Kept::made_in(engine, composite, &plan, PAGE, Some(over), &other, composite.widest());
    assert!(laid_over.is_none());
    assert!(last_error().contains("kept in another pool"), "{}", last_error());
    assert!(other.pages().is_empty(), "and nothing is held for it");
}

// The work buffer is the engine's, kept from one run to the next: a run
// that needs no more than the one kept makes none — a tile composited
// after the whole canvas runs in the canvas's —, and what the wider run
// left there is nothing to it: the tile as it was composited before. Let
// go, the next run makes its own. On an engine of its own: the tests' one
// runs every test's composites at once.
#[test]
fn a_run_takes_the_work_buffer_the_last_run_left() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let composite = Composite::new(&engine).expect("its executor");
    let (pages, set, _) = composite_on(&engine, noise(31), CANVAS);
    let plan = laid(&pages, &set);
    let run = |tiles: &[(i32, i32)]| {
        let done = composite.run(&engine, &plan, tiles, PAGE, composite.widest()).expect("run");
        engine.read_buffer(&done.out).expect("read back")
    };
    assert_eq!(engine.work.bytes(), 0);
    // The canvas's last tile, where the whole canvas's run leaves its
    // first.
    let last = [(4, 2)];
    let alone = run(&last);
    let narrow = engine.work.bytes();
    assert!(narrow > 0);
    let whole: Vec<(i32, i32)> = (0..3).flat_map(|row| (0..5).map(move |column| (column, row))).collect();
    let all = run(&whole);
    let wide = engine.work.bytes();
    assert!(wide > narrow, "a wider run makes one that holds it");
    assert!(all[..TILE_BYTES as usize] != alone[..], "the tiles are told apart");
    assert!(run(&last) == alone, "what the wider run left is read");
    assert_eq!(engine.work.bytes(), wide, "a buffer is made for a run the one kept holds");
    engine.work.let_go();
    assert_eq!(engine.work.bytes(), 0);
    assert!(run(&last) == alone);
    assert_eq!(engine.work.bytes(), narrow, "let go, the next run makes its own");
}

// What an engine keeps for pictures and no picture holds is counted and
// given back: nothing before a picture is kept; under a screen's canvas,
// the slots it leaves free on its pool's page and the work buffer its
// composite ran in; the screen let go, that page whole; given back past
// the work buffer's bytes, that buffer alone; and given back whole,
// nothing — the next screen shown as the first was. On an engine of its
// own: the tests' one keeps every test's pictures.
#[test]
fn an_engine_counts_what_no_picture_holds_and_gives_it_back() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let composite = Composite::new(&engine).expect("its executor");
    let (pages, set, _) = composite_on(&engine, noise(23), CANVAS);
    let plan = laid(&pages, &set);
    // SAFETY: the engine is live through every call.
    let idle = || unsafe { gpu_engine_pictures_idle_bytes(&engine) };
    let shown = || {
        let mut screen = Screen::new(PAGE, 1.0).expect("screen");
        screen.compose(&engine, &composite, &plan, PAGE, composite.widest()).expect("compose");
        let texture = surface_on(&engine, SCREEN, wgpu::TextureFormat::Rgba8Unorm);
        let (camera, whole) = (camera(0.1, (1.0, 0.0), (3.0, 2.0)), [0, 0, SCREEN.0, SCREEN.1]);
        screen.show(&engine, &composite, camera, &texture, whole, composite.widest()).expect("show");
        (screen, engine.read_texture(&texture).expect("read the surface back"))
    };
    assert_eq!(idle(), 0);
    let (screen, first) = shown();
    let (page, work) = (engine.pictures.pages()[0].size(), engine.work.bytes());
    assert!(0 < work && work < page, "the premise");
    assert_eq!(idle(), page - screen.bytes() + work);
    drop(screen);
    assert_eq!(idle(), page + work);
    // SAFETY: as above.
    unsafe { gpu_engine_pictures_give_back(&engine, work) };
    assert_eq!(idle(), work);
    // SAFETY: as above.
    unsafe { gpu_engine_pictures_give_back(&engine, 0) };
    assert_eq!(idle(), 0);
    assert!(engine.pictures.pages().is_empty());
    let (screen, next) = shown();
    assert!(next == first);
    assert_eq!(idle(), page - screen.bytes() + work);
}

// A screen is composed over a film before anything is composed on it: the
// film's canvas but where fresh marks, the whole canvas over a film of
// nothing composed — and then refused, with the engine's reason.
#[test]
fn a_screen_is_composed_over_a_film_before_anything_else_is() {
    let Rig { engine, composite } = rig();
    let budget = composite.widest();
    let (pages, set, _) = composite_of(noise(53), CANVAS);
    let (frame_pages, frame_set, _) = composite_of(noise(71), CANVAS);
    let frame = laid(&frame_pages, &frame_set);
    let mut film = Screen::new(PAGE, 1.0).expect("film");
    let mut over_nothing = Screen::new(PAGE, 1.0).expect("screen");
    over_nothing.compose_over(engine, composite, &frame, &film, [0, 0, 1, 1], budget).expect("over nothing");
    assert!(kept_bytes(over_nothing.canvas.as_ref().expect("composed")) == composited_whole(noise(71)));
    film.compose(engine, composite, &laid(&pages, &set), PAGE, budget).expect("film");
    let mut screen = Screen::new(PAGE, 1.0).expect("screen");
    screen.compose_over(engine, composite, &frame, &film, [0, 0, 1, 1], budget).expect("over the film");
    let want = composited_whole(|x, y| if tile_of(x, y) == (0, 0) { noise(71)(x, y) } else { noise(53)(x, y) });
    assert!(kept_bytes(screen.canvas.as_ref().expect("composed")) == want);
    assert!(screen.compose_over(engine, composite, &frame, &film, PAGE, budget).is_none());
    assert!(last_error().contains("before anything is composed"), "{}", last_error());
}

/// `screen` shown through `camera`, the surface read back.
fn shown_by(screen: &Screen, camera: Camera) -> Vec<u8> {
    let Rig { engine, composite } = rig();
    let texture = surface(SCREEN, wgpu::TextureFormat::Rgba8Unorm);
    let whole = [0, 0, SCREEN.0, SCREEN.1];
    screen.show(engine, composite, camera, &texture, whole, composite.widest()).expect("show");
    engine.read_texture(&texture).expect("read the surface back")
}

/// `canvas` shown through `camera` as it is, kept by no screen: the one
/// row a screen lays, over the composite's own tiles on a floor of 1.
fn shown_unkept(canvas: Tiles, camera: Camera) -> Vec<u8> {
    let Rig { engine, composite } = rig();
    let texture = surface(SCREEN, wgpu::TextureFormat::Rgba8Unorm);
    let whole = [0, 0, SCREEN.0, SCREEN.1];
    let map = ResampleMap::new(affine(camera.inverse), 1.0, camera.mode, 1, 1).expect("lands");
    let steps = [row(map)];
    composite.show(engine, &plan(canvas, &steps), &texture, whole, composite.widest()).expect("show");
    engine.read_texture(&texture).expect("read the surface back")
}

/// The screen through `camera` by R1's harness on `floor` over the canvas,
/// premultiplied as the app's one premultiply leaves it.
fn screen_by_r1(canvas: &Picture, floor: f64, camera: Camera) -> Vec<u8> {
    let map = ResampleMap::new(affine(camera.inverse), floor, camera.mode, 1, 1).expect("lands");
    let straight = window(&map, canvas, SCREEN, (0, 0));
    premultiplied(&straight).into_iter().flat_map(u32::to_le_bytes).collect()
}

/// Cameras each side of 1/16: at a half and at 1/16, and under it — where
/// a pixel's tent is cut at Blend's ceiling — at 1/20, at 1/40 turned
/// 3-4-5 and at 1/100.
fn cameras() -> [Camera; 5] {
    [
        camera(0.5, (1.0, 0.0), (-40.25, -20.5)),
        camera(0.0625, (1.0, 0.0), (10.5, 3.25)),
        camera(0.05, (1.0, 0.0), (12.25, 9.0)),
        camera(0.025, (0.8, 0.6), (30.0, 4.5)),
        camera(0.01, (1.0, 0.0), (20.75, 18.0)),
    ]
}

// The screen is R1 over its canvas through the camera at every scale, on
// the floor it was made with — under 1/16 too, where it read a halving
// stage of the canvas till 2026-11-19 (`Screen::show`): the one composite,
// a tent cut where R1 cuts it.
#[test]
fn the_screen_shows_r1_over_its_canvas_at_every_scale() {
    let Rig { engine, composite } = rig();
    let (pages, set, picture) = composite_of(noise(71), CANVAS);
    for floor in FLOORS {
        let mut screen = Screen::new(PAGE, floor).expect("screen");
        screen.compose(engine, composite, &laid(&pages, &set), PAGE, composite.widest()).expect("compose");
        for camera in cameras() {
            let scale = scale_of(camera);
            assert!(shown_by(&screen, camera) == screen_by_r1(&picture, floor, camera), "{floor} at {scale}");
        }
    }
}

#[test]
fn every_device_shows_the_pinned_far_screens() {
    let Rig { engine, composite } = rig();
    let (pages, set, _) = composite_of(noise(71), CANVAS);
    let mut screen = Screen::new(PAGE, 1.0).expect("screen");
    screen.compose(engine, composite, &laid(&pages, &set), PAGE, composite.widest()).expect("compose");
    let screens: Vec<u8> = cameras().into_iter().flat_map(|camera| shown_by(&screen, camera)).collect();
    assert_pinned("composite/screen-far", &screens);
}

// A screen over no pixel is refused, saying so: an extent with no width or
// no height, or turned inside out.
#[test]
fn a_screen_over_no_pixel_is_refused() {
    for extent in [[5, 0, 5, 9], [0, 9, 4, 9], [6, 0, 5, 9], [0, 9, 4, 8]] {
        assert!(Screen::new(extent, 1.0).is_none(), "{extent:?}");
        assert_eq!(crate::last_error(), format!("a screen over {extent:?} holds no pixel"));
    }
}

// The screen composes the canvas and shows it as that composite is shown
// through the camera unkept — magnified and turned, shrunk, and past 1/16
// — and a change composed on it is shown at every scale: the screen is
// the canvas's composite through the camera.
#[test]
fn the_screen_shows_its_canvas_as_the_composite_shown_through_the_camera() {
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
        assert!(shown_by(&screen, camera) == shown_unkept(Tiles { pages: &pages, set: &set }, camera));
    }
    let change = [60, 30, 300, 200];
    let red = move |x, y| if inside(change, x, y) { 0xff00_00ff } else { noise(17)(x, y) };
    let (pages, set, _) = composite_of(red, CANVAS);
    screen.compose(engine, composite, &laid(&pages, &set), change, budget).expect("compose");
    for &camera in &cameras {
        assert!(shown_by(&screen, camera) == shown_unkept(Tiles { pages: &pages, set: &set }, camera));
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

// A screen keeps nothing before its canvas is composed, then its canvas's
// tiles, every one a tile's bytes — the 5 × 3 tiles the canvas covers —
// and nothing more however far it is shown reduced (↩️the halvings it
// showed through under 1/16 besides, till 2026-11-19).
#[test]
fn a_screen_keeps_the_bytes_of_its_canvas_however_far_it_is_shown() {
    let Rig { engine, composite } = rig();
    let mut screen = Screen::new(PAGE, 1.0).expect("screen");
    assert_eq!(screen.bytes(), 0);
    let (pages, set, _) = composite_of(noise(31), CANVAS);
    screen.compose(engine, composite, &laid(&pages, &set), PAGE, composite.widest()).expect("compose");
    let canvas = 5 * 3 * TILE_BYTES;
    assert_eq!(screen.bytes(), canvas);
    for scale in [0.5, 0.03125, 0.0125] {
        shown_by(&screen, camera(scale, (1.0, 0.0), (0.0, 0.0)));
        assert_eq!(screen.bytes(), canvas, "at {scale} the canvas alone is read");
    }
}

// A screen shows its canvas once one is composed, and says so before.
#[test]
fn a_screen_is_shown_once_its_canvas_is_composed() {
    let Rig { engine, composite } = rig();
    let screen = Screen::new(PAGE, 1.0).expect("screen");
    let texture = surface(SCREEN, wgpu::TextureFormat::Rgba8Unorm);
    let shown = screen.show(engine, composite, camera(1.0, (1.0, 0.0), (0.0, 0.0)), &texture, [0, 0, 1, 1], composite.widest());
    assert!(shown.is_none());
    assert_eq!(crate::last_error(), "a screen is shown before anything is composed on it");
}

// 🚨A canvas a compose failed on is none (`Screen::compose`'s 🚨): the
// show after it fails by name, not with a canvas made again in part — the
// frame a screen puts up stays what it was — and the next compose lays
// it whole.
#[test]
fn a_compose_that_fails_leaves_no_canvas_to_show() {
    let Rig { engine, composite } = rig();
    let budget = composite.widest();
    let mut screen = Screen::new(PAGE, 1.0).expect("screen");
    let (pages, set, _) = composite_of(noise(41), CANVAS);
    screen.compose(engine, composite, &laid(&pages, &set), PAGE, budget).expect("compose");
    let refused = Plan { sets: &[], ..laid(&pages, &set) };
    assert!(screen.compose(engine, composite, &refused, [0, 0, 1, 1], budget).is_none());
    assert_eq!(crate::last_error(), "step 0 lays tile set 0 of 0");
    let texture = surface(SCREEN, wgpu::TextureFormat::Rgba8Unorm);
    let to = camera(1.0, (1.0, 0.0), (0.0, 0.0));
    let shown = screen.show(engine, composite, to, &texture, [0, 0, 1, 1], budget);
    assert!(shown.is_none(), "a canvas a compose failed on was shown");
    assert_eq!(crate::last_error(), "a screen is shown before anything is composed on it");
    let (pages, set, _) = composite_of(noise(42), CANVAS);
    screen.compose(engine, composite, &laid(&pages, &set), [0, 0, 1, 1], budget).expect("compose");
    assert!(canvas_bytes(&screen) == composited_whole(noise(42)), "not laid whole again");
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

// A screen shown waits for no GPU on the thread that asked
// (Composite::show's 🚨) — no wait is counted there —, and the engine's
// thread says once all of it is done (Engine::done_then): on an engine of
// its own — the tests' one is polled by every test at once —, the work
// submitted before the show is seen done by then, and nothing is left
// after it. ↩️It was done on the GPU when show returned, until a screen's
// frame was put up as the GPU finished it
// (a-float-in-hand-draws-the-frame-as-it-stands-Q2, 2026-11-12).
#[test]
fn a_screen_shown_waits_here_for_nothing_and_is_told_done() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let composite = Composite::new(&engine).expect("its executor");
    let mut screen = Screen::new(PAGE, 1.0).expect("screen");
    let (pages, set, _) = composite_on(&engine, noise(23), CANVAS);
    screen.compose(&engine, &composite, &laid(&pages, &set), [0, 0, 1, 1], composite.widest()).expect("compose");
    let seen = Arc::new(AtomicBool::new(false));
    let flag = Arc::clone(&seen);
    engine.queue.on_submitted_work_done(move || flag.store(true, Ordering::SeqCst));
    let size = (1024, 768);
    let texture = surface_on(&engine, size, wgpu::TextureFormat::Rgba8Unorm);
    let camera = camera(1.7, (0.6, 0.8), (500.0, 100.0));
    let whole = [0, 0, size.0, size.1];
    let waits = gpu_engine_waits_here();
    screen.show(&engine, &composite, camera, &texture, whole, composite.widest()).expect("show");
    assert_eq!(gpu_engine_waits_here(), waits, "the show waited here");
    let (tell, told) = std::sync::mpsc::channel();
    engine.done_then(move |done| {
        let _ = tell.send(done);
    });
    assert_eq!(told.recv_timeout(Duration::from_secs(60)), Ok(Ok(())), "told it is done");
    assert!(seen.load(Ordering::SeqCst), "told done before the work was");
    let after = engine.device().poll(wgpu::PollType::Poll).expect("poll");
    assert!(after.is_queue_empty(), "done left {after:?}");
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
// moved off the tile grid and by whole tiles, at 1/16 and over and under
// it.
#[test]
fn a_screen_before_the_page_shows_as_one_at_the_origin() {
    let Rig { engine, composite } = rig();
    let budget = composite.widest();
    let near = [camera(0.5, (1.0, 0.0), (-40.25, -20.5)), camera(2.0, (1.0, 0.0), (-300.5, -100.25))];
    let far = [camera(0.03125, (1.0, 0.0), (20.5, 18.0)), camera(0.0078125, (1.0, 0.0), (2.0, 1.5))];
    let cameras = [near, far].concat();
    for (x, y) in [(200, 150), (256, 128)] {
        let before = [-x, -y, PAGE[2] - x, PAGE[3] - y];
        let mut screen = Screen::new(before, 1.0).expect("screen");
        let (pages, set) = drawn_over(move |at_x, at_y| noise(29)(at_x + x, at_y + y), before);
        screen.compose(engine, composite, &laid(&pages, &set), before, budget).expect("compose");
        let mut origin = Screen::new(PAGE, 1.0).expect("screen");
        let (pages, set, _) = composite_of(noise(29), CANVAS);
        origin.compose(engine, composite, &laid(&pages, &set), PAGE, budget).expect("compose");
        for &camera in &cameras {
            let mut moved = camera;
            moved.inverse[2] += f64::from(x);
            moved.inverse[5] += f64::from(y);
            let scale = scale_of(camera);
            let shown = shown_by(&screen, camera);
            assert!(shown.iter().any(|&byte| byte != 0), "({x}, {y}) at {scale} shows nothing");
            assert!(shown == shown_by(&origin, moved), "({x}, {y}) at {scale}");
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
        let map = ResampleMap::new(affine(camera.inverse), 1.0, camera.mode, 1, 1).expect("lands");
        let by_r1: Vec<u8> = premultiplied(&window(&map, &canvas, SCREEN, (0, 0))).into_iter().flat_map(u32::to_le_bytes).collect();
        let scale = scale_of(camera);
        assert!(shown_by(&screen, camera) == by_r1, "at {scale}");
    }
}

/// A canvas kept over the page as a run over every tile of it puts it: its
/// tiles' bytes where it keeps them, nothing where it keeps none.
fn kept_over_the_page(kept: &Kept) -> Vec<u8> {
    let bytes = kept_bytes(kept);
    let mut placed = bytes.chunks(TILE_BYTES as usize);
    let nothing = vec![0; TILE_BYTES as usize];
    let tiles = &kept.as_tiles().set.tiles;
    assert_eq!(tiles.len(), page_tiles().len(), "the premise: a canvas over the page");
    tiles
        .iter()
        .flat_map(|tile| tile.map_or(&nothing[..], |_| placed.next().expect("its bytes")).to_vec())
        .collect()
}

/// `pixel`'s row over the canvas, nothing past it, with a tile where
/// `inked` says and none elsewhere: a sheet's ink, a few tiles a pen wrote
/// on.
fn inked_where(
    pixel: impl Fn(i32, i32) -> u32,
    inked: impl Fn(i32, i32) -> bool,
) -> (Vec<wgpu::Buffer>, TileSet) {
    let within = |x: i32, y: i32| x < CANVAS.0 as i32 && y < CANVAS.1 as i32;
    let pixel = |x, y| if within(x, y) { pixel(x, y) } else { 0 };
    let mut pool = Pool::default();
    let size = (CANVAS.0.div_ceil(TILE), CANVAS.1.div_ceil(TILE));
    let set = pool.drawn(pixel, (0, 0), size, |column, row| inked(column, row).then_some(0));
    (pool.upload(rig().engine), set)
}

/// Which of a tile set's tiles are there, row after row.
fn there(set: &TileSet) -> Vec<bool> {
    set.tiles.iter().map(Option::is_some).collect()
}

// A canvas keeps no tile nothing lays on — its row's tiles alone, a
// checker of them — and is the canvas composited all the same: nothing
// where it keeps none. Shown, magnified and under 1/16 alike, it is the
// row shown through the camera unkept — onto a surface that showed another
// canvas the frame before, so nothing of that stays where it keeps no
// tile.
#[test]
fn a_canvas_keeps_no_tile_nothing_lays_on_and_shows_nothing_there() {
    let Rig { engine, composite } = rig();
    let budget = composite.widest();
    let (pages, set) = inked_where(noise(41), |column, row| (column + row) % 2 == 0);
    let plan = laid(&pages, &set);
    let pictures = Pictures::sized(15).expect("a pool");
    let kept = kept_in(&pictures, &plan);
    assert_eq!(there(kept.as_tiles().set), there(&set));
    assert_eq!(kept.bytes(), 8 * TILE_BYTES, "8 of 15 tiles");
    assert_eq!(
        Kept::tiles_made(&plan, PAGE, &Pictures::sized(15).expect("a pool")),
        Some(8),
        "weighed before it is made as it is kept"
    );
    assert!(kept_over_the_page(&kept) == run_over_the_page(&plan));

    let (full_pages, full_set, _) = composite_of(noise(17), CANVAS);
    let mut full = Screen::new(PAGE, 1.0).expect("screen");
    full.compose(engine, composite, &laid(&full_pages, &full_set), PAGE, budget).expect("compose");
    let mut screen = Screen::new(PAGE, 1.0).expect("screen");
    screen.compose(engine, composite, &plan, PAGE, budget).expect("compose");
    for camera in [camera(0.4, (1.0, 0.0), (3.0, 2.0)), camera(0.03, (1.0, 0.0), (20.75, 18.0))] {
        let texture = surface(SCREEN, wgpu::TextureFormat::Rgba8Unorm);
        let whole = [0, 0, SCREEN.0, SCREEN.1];
        full.show(engine, composite, camera, &texture, whole, budget).expect("the frame before");
        screen.show(engine, composite, camera, &texture, whole, budget).expect("show");
        let shown = engine.read_texture(&texture).expect("read the surface back");
        assert!(shown == shown_unkept(Tiles { pages: &pages, set: &set }, camera), "{}", scale_of(camera));
    }
}

// Made again, a canvas takes a tile a change first lays on and lets go of
// one a change leaves nothing on — its slot free for the one taken — and
// is then the changed canvas composited anew. A tile marked that nothing
// lays on, before or after, stays none.
#[test]
fn a_canvas_made_again_takes_a_tile_first_laid_on_and_lets_go_of_one_left_bare() {
    let Rig { engine, composite } = rig();
    let budget = composite.widest();
    let before = |column, row| (column + row) % 2 == 0;
    let (pages, set) = inked_where(noise(41), before);
    let pictures = Pictures::sized(15).expect("a pool");
    let mut kept = kept_in(&pictures, &laid(&pages, &set));
    let idle = idle_of(&pictures);
    // (1, 0) is inked now and (0, 0) wiped; (3, 0) was bare and stays so.
    let after = move |column, row| (column, row) != (0, 0) && (before(column, row) || (column, row) == (1, 0));
    let (pages, set) = inked_where(noise(41), after);
    let plan = laid(&pages, &set);
    let stale = |tile| [(0, 0), (1, 0), (3, 0)].contains(&tile);
    kept.made_again(engine, composite, &plan, stale, budget).expect("made again");
    assert_eq!(there(kept.as_tiles().set), there(&set));
    assert!(kept_over_the_page(&kept) == run_over_the_page(&plan));
    assert_eq!(kept.bytes(), 8 * TILE_BYTES);
    assert_eq!(idle_of(&pictures), idle, "a slot taken, a slot let go");
}

// A solid lays the tiles its rectangle meets — the paper under a cut's
// rows — and a buffer opened and closed around the rows lays nothing of
// its own: a canvas keeps those and its row's one tile, and is the canvas
// composited.
#[test]
fn a_solid_lays_the_tiles_it_meets_and_a_buffer_lays_nothing_of_its_own() {
    let (pages, set) = inked_where(noise(41), |column, row| (column, row) == (4, 2));
    let steps = [
        Step::Solid {
            colour: 0xffff_ffff,
            rect: [10, 10, 140, 100],
        },
        Step::Open,
        row(ResampleMap::moved(0, 0)),
        Step::Close {
            opacity: 65535,
            mode: NORMAL,
            matrix: None,
            chain: None,
        },
    ];
    let plan = plan(Tiles { pages: &pages, set: &set }, &steps);
    let kept = kept_in(&Pictures::sized(15).expect("a pool"), &plan);
    let held: Vec<(i32, i32)> = kept.as_tiles().set.placed_under(None).map(|(tile, _)| tile).collect();
    assert_eq!(held, [(0, 0), (1, 0), (4, 2)]);
    assert_eq!(
        Kept::tiles_made(&plan, PAGE, &Pictures::sized(15).expect("a pool")),
        Some(held.len()),
        "weighed as it is kept"
    );
    assert!(kept_over_the_page(&kept) == run_over_the_page(&plan));
}
