//! The halving stages on a real GPU: each stage against R1's own harness
//! over the stage above it, the screen against that harness over the stage
//! it reads, a line's alpha the same wherever it lies, and kept stages
//! against stages made anew — never against a CPU copy of a formula
//! (`kernels/mod.rs` has why).

use super::{Camera, Halvings, Kept, Tiles, affine, halved, onto_stage, stage_at};
use crate::kernels::composite::tests::{Pool, Rig, picture_of, pixel_at, rig, surface, texel};
use crate::device::Engine;
use crate::kernels::composite::{TILE, TILE_BYTES, TileAt, TileSet};
use crate::kernels::pool::gather;
use crate::kernels::shared::tests::{Picture, premultiplied, window};
use crate::kernels::shared::{ResampleMap, ResampleMode};
use crate::testing::assert_pinned;

/// The canvas: odd both ways, so every stage's last column and row lie
/// half past the one above it.
pub(crate) const CANVAS: (u32, u32) = (517, 301);
/// The canvas's pixels, [left, top, right, bottom): its page.
pub(crate) const PAGE: [i32; 4] = [0, 0, CANVAS.0 as i32, CANVAS.1 as i32];
pub(crate) const SCREEN: (u32, u32) = (64, 48);
/// The screen's floor, 1 (`resampleRadiusFloor`), and one past the tent a
/// half spans, 2 — what a stage reads on it is the screen's.
const FLOORS: [f64; 2] = [1.0, 4.0];

/// A composite of `pixel` over a canvas of `size`, nothing past it, as a
/// composite ending at the canvas leaves it: its page, its tile set and its
/// pixels as R1's harness takes a source.
pub(crate) fn composite_of(
    pixel: impl Fn(i32, i32) -> u32,
    size: (u32, u32),
) -> (Vec<wgpu::Buffer>, TileSet, Picture) {
    composite_on(rig().engine, pixel, size)
}

/// [`composite_of`] on `engine`.
pub(crate) fn composite_on(
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

pub(crate) fn noise(seed: u32) -> impl Fn(i32, i32) -> u32 {
    move |x, y| texel(seed, x, y)
}

/// The camera at `scale`, turned by (cos, sin), the canvas's origin at
/// `pan` on the screen.
pub(crate) fn camera(scale: f64, (cos, sin): (f64, f64), (x, y): (f64, f64)) -> Camera {
    let (a, b, d, e) = (cos / scale, sin / scale, -sin / scale, cos / scale);
    Camera {
        inverse: [a, b, -(a * x + b * y), d, e, -(d * x + e * y)],
        scale,
        mode: ResampleMode::Blend,
    }
}

/// `canvas` shown through `camera` by `halvings`, the surface read back.
fn shown(halvings: &mut Halvings, canvas: Tiles, camera: Camera) -> Vec<u8> {
    let Rig { engine, composite } = rig();
    let texture = surface(SCREEN, wgpu::TextureFormat::Rgba8Unorm);
    let whole = [0, 0, SCREEN.0, SCREEN.1];
    halvings
        .show(engine, composite, canvas, camera, &texture, whole, composite.widest())
        .expect("show");
    engine.read_texture(&texture).expect("read the surface back")
}

/// ①'s map, as the spec states it: x about 2x + 1, Blend on `floor`.
fn half(floor: f64) -> ResampleMap {
    let half = [2.0, 0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0, 1.0];
    ResampleMap::new(half, floor, ResampleMode::Blend, 1, 1).expect("a half lands")
}

/// Stages 1 to `k` of `canvas`, a canvas of `size`, by R1's harness on
/// `floor`: each the half of the one above, nothing past its ⌈⌉ size; with
/// those sizes.
fn stages_by_r1(
    canvas: &Picture,
    size: (u32, u32),
    floor: f64,
    k: usize,
) -> Vec<(Picture, (u32, u32))> {
    let mut stages: Vec<(Picture, (u32, u32))> = Vec::new();
    for _ in 0..k {
        let (above, (width, height)) =
            stages.last().map_or((canvas, size), |(picture, size)| (picture, *size));
        let size = (width.div_ceil(2), height.div_ceil(2));
        let tiles = (above.width.div_ceil(2), above.height.div_ceil(2));
        let halved = window(&half(floor), above, tiles, (0, 0));
        let pixel = |x: i32, y: i32| {
            let inside = x < size.0 as i32 && y < size.1 as i32;
            if inside { halved[(y as u32 * tiles.0 + x as u32) as usize] } else { 0 }
        };
        stages.push((picture_of(pixel, tiles), size));
    }
    stages
}

/// The screen through `camera` by R1's harness on `floor` over the canvas
/// or, under 1/16, the stage it reads, premultiplied as the app's one
/// premultiply leaves it.
fn screen_by_r1(canvas: &Picture, floor: f64, camera: Camera) -> Vec<u8> {
    let k = stage_at(camera.scale).expect("a stage");
    let stages = stages_by_r1(canvas, CANVAS, floor, k);
    let read = stages.last().map_or(canvas, |(picture, _)| picture);
    let inverse = affine(onto_stage(camera.inverse, k));
    let map = ResampleMap::new(inverse, floor, camera.mode, 1, 1).expect("lands");
    let straight = window(&map, read, SCREEN, (0, 0));
    premultiplied(&straight).into_iter().flat_map(u32::to_le_bytes).collect()
}

// ② by hand: stage 0 at 1/16 and over; under it the least k bringing the
// scale back to 1/16 or over — 1/20 by 2 to 1/10, 1/32 by 2 to 1/16 itself,
// 1/40 by 4 to 1/10, 1/100 by 8 to 2/25. Nothing for no scale.
#[test]
fn the_screen_reads_the_least_stage_back_at_1_in_16() {
    let under = |scale: f64| f64::from_bits(scale.to_bits() - 1);
    let cases = [(1.0, 0), (0.0625, 0), (under(0.0625), 1), (0.05, 1), (0.03125, 1)];
    let more = [(under(0.03125), 2), (0.025, 2), (0.01, 3)];
    for (scale, k) in cases.into_iter().chain(more) {
        assert_eq!(stage_at(scale), Some(k), "{scale}");
    }
    assert_eq!(stage_at(0.0), None);
    assert_eq!(stage_at(f64::NAN), None);
}

// ② by hand: a map onto stage 2 divides each entry by 4, the move with
// the rest; onto stage 0 it is the map itself.
#[test]
fn a_map_onto_a_stage_divides_it_by_its_power_of_two() {
    let inverse = [40.0, -3.0, 7.0, 2.0, 40.0, -5.0];
    let onto = [10.0, -0.75, 1.75, 0.5, 10.0, -1.25];
    assert_eq!(onto_stage(inverse, 2), onto);
    assert_eq!(onto_stage(inverse, 0), inverse);
}

// ① by hand: a stage's pixels are ⌊⌋ of half the left and top above it and
// ⌈⌉ of half the right and bottom, before the origin as past it — a stage
// of a pasteboard's world: -3 to -2, -5 to -3, and an edge at 0 stays.
#[test]
fn a_stage_spans_the_pixels_half_of_the_one_above_touches() {
    assert_eq!(halved([-3, -5, 7, 9]), [-2, -3, 4, 5]);
    assert_eq!(halved([-4, -6, -1, 0]), [-2, -3, 0, 0]);
    assert_eq!(halved([0, 0, 517, 301]), [0, 0, 259, 151]);
}

// ①: a stage is R1 Blend at a half of the one above on the screen's floor,
// over ⌈⌉ of its pixels and nothing past them — 517 × 301 to 259 × 151,
// 130 × 76, 65 × 38.
#[test]
fn a_stage_is_r1_blend_at_a_half_of_the_one_above() {
    let (pages, set, picture) = composite_of(noise(71), CANVAS);
    let canvas = Tiles { pages: &pages, set: &set };
    for floor in FLOORS {
        let mut halvings = Halvings::new(PAGE, floor).expect("halvings");
        drop(shown(&mut halvings, canvas, camera(0.01, (1.0, 0.0), (3.0, 2.0))));
        let by_r1 = stages_by_r1(&picture, CANVAS, floor, 3);
        let extents: Vec<[i32; 4]> = halvings.stages.iter().map(|stage| stage.kept.extent).collect();
        assert_eq!(extents, [[0, 0, 259, 151], [0, 0, 130, 76], [0, 0, 65, 38]]);
        for (stage, (picture, _)) in halvings.stages.iter().zip(&by_r1) {
            let bytes = kept_bytes(&stage.kept);
            let tiles: Vec<(i32, i32)> = stage.kept.set.placed_under(None).map(|(place, _)| place).collect();
            for y in 0..picture.height as i32 {
                for x in 0..picture.width as i32 {
                    let at = (y as u32 * picture.width + x as u32) as usize;
                    let word = u32::from_le_bytes(pixel_at(&bytes, &tiles, x, y));
                    let extent = stage.kept.extent;
                    assert_eq!(word, picture.pixels[at], "{floor} {extent:?} ({x}, {y})");
                }
            }
        }
    }
}

/// Cameras each side of 1/16: the canvas itself at a half and at 1/16, its
/// stages at 1/20, at 1/40 turned 3-4-5 and at 1/100.
fn cameras() -> [Camera; 5] {
    [
        camera(0.5, (1.0, 0.0), (-40.25, -20.5)),
        camera(0.0625, (1.0, 0.0), (10.5, 3.25)),
        camera(0.05, (1.0, 0.0), (12.25, 9.0)),
        camera(0.025, (0.8, 0.6), (30.0, 4.5)),
        camera(0.01, (1.0, 0.0), (20.75, 18.0)),
    ]
}

// ②: the screen is R1 over the canvas at 1/16 and over, and under it over
// the stage that leaves 1/16 or over, through the camera onto that stage —
// on the screen's floor, the stages' too.
#[test]
fn the_screen_shows_r1_over_the_stage_it_reads() {
    let (pages, set, picture) = composite_of(noise(71), CANVAS);
    let canvas = Tiles { pages: &pages, set: &set };
    for floor in FLOORS {
        let mut halvings = Halvings::new(PAGE, floor).expect("halvings");
        for camera in cameras() {
            let screen = shown(&mut halvings, canvas, camera);
            let scale = camera.scale;
            assert!(screen == screen_by_r1(&picture, floor, camera), "{floor} at {scale}");
        }
    }
}

#[test]
fn every_device_shows_the_pinned_far_screens() {
    let (pages, set, _) = composite_of(noise(71), CANVAS);
    let canvas = Tiles { pages: &pages, set: &set };
    let mut halvings = Halvings::new(PAGE, 1.0).expect("halvings");
    let screens: Vec<u8> =
        cameras().into_iter().flat_map(|camera| shown(&mut halvings, canvas, camera)).collect();
    assert_pinned("composite/screen-halved", &screens);
}

/// The alphas along a screen's row or column `at`, of a screen read back.
fn alphas_along(screen: &[u8], across: bool, at: u32) -> Vec<u32> {
    let (width, height) = SCREEN;
    let alpha = |x: u32, y: u32| u32::from(screen[((y * width + x) * 4 + 3) as usize]);
    match across {
        true => (0..width).map(|x| alpha(x, at)).collect(),
        false => (0..height).map(|y| alpha(at, y)).collect(),
    }
}

/// A one-pixel opaque line down the canvas at x = `at` — `across` false:
/// along it at y = `at` — shown at `scale` from the canvas's corner, the
/// alphas along the screen's third row or column, across the line.
fn line_shown(at: i32, across: bool, scale: f64) -> Vec<u32> {
    let size = if across { (1280, 256) } else { (256, 1280) };
    let line = move |x: i32, y: i32| {
        let crossed = if across { x } else { y };
        if crossed == at { 0xff00_0000 } else { 0 }
    };
    let (pages, set, _) = composite_of(line, size);
    let canvas = Tiles { pages: &pages, set: &set };
    let mut halvings = Halvings::new([0, 0, size.0 as i32, size.1 as i32], 1.0).expect("halvings");
    let screen = shown(&mut halvings, canvas, camera(scale, (1.0, 0.0), (0.0, 0.0)));
    alphas_along(&screen, across, 2)
}

// canvas base's 1/40 line (11-06 21:53, 11-07 02:04): a one-pixel line
// shown at 1/40 holds the same alpha, ±1, wherever it lies across a screen
// pixel's 40 — where one read cut at 16 px lost it between centres — down
// x and down y.
#[test]
fn a_line_at_1_in_40_holds_its_alpha_wherever_it_lies() {
    for across in [true, false] {
        let sums: Vec<u32> =
            (600..640).map(|at| line_shown(at, across, 0.025).iter().sum()).collect();
        let (least, most) = (sums.iter().min().unwrap(), sums.iter().max().unwrap());
        assert!(*least > 0 && most - least <= 1, "across {across}: {sums:?}");
    }
}

// No seam where the screen goes from the canvas to stage 1: across a line
// at 1/16 and just under it, no pixel's alpha moves by more than one step,
// wherever the line lies across a screen pixel's 16. Each pixel rounds on
// its own, so their sum can move by two: at x = 320 the canvas's 8.47 and
// 7.47 round to 8 and 7, stage 1's 8.5 and 7.5 to 9 and 8.
#[test]
fn a_line_holds_its_alpha_where_the_screen_takes_stage_1() {
    let under = f64::from_bits(0.0625f64.to_bits() - 1);
    for across in [true, false] {
        for at in 320..336 {
            let (over, under) = (line_shown(at, across, 0.0625), line_shown(at, across, under));
            let most = over.iter().zip(&under).map(|(o, u)| o.abs_diff(*u)).max();
            assert!(most <= Some(1), "across {across} at {at}: {over:?} {under:?}");
        }
    }
}

/// A kept picture's tiles, read back off the pages it names one after
/// another, row after row: each where the pool it is kept in placed it.
pub(crate) fn kept_bytes(kept: &Kept) -> Vec<u8> {
    let engine = rig().engine;
    let places: Vec<TileAt> = kept.places().collect();
    let mut bytes = vec![0; places.len() * TILE_BYTES as usize];
    let out = engine.readback(bytes.len() as u64);
    gather(engine, &kept.pages, &places, &out);
    engine.mapped_into(&out, &mut bytes).expect("read the tiles back");
    bytes
}

/// Every stage's pages, read back.
fn stage_bytes(halvings: &Halvings) -> Vec<Vec<u8>> {
    halvings.stages.iter().map(|stage| kept_bytes(&stage.kept)).collect()
}

fn inside([left, top, right, bottom]: [i32; 4], x: i32, y: i32) -> bool {
    left <= x && x < right && top <= y && y < bottom
}

// Kept stages are made again on the tiles that read a change, down every
// stage: red stripes against stage 1's tile edges, each read across the
// edge by the tent's reach past it alone — just right of x = 256, just over
// y = 256, just left of x = 256, just under y = 256 — and two dots in stage
// 1's opposite corner tiles, both marked before the screen reads, leave
// every stage as stages made anew over the changed composite. A change not
// marked, on the tiles the last stripe was made again on, leaves every
// stage as it was: the stages over it are kept, not made again.
#[test]
fn a_kept_stage_is_made_again_where_the_composite_changed() {
    let far = camera(0.01, (1.0, 0.0), (20.75, 18.0));
    let mut kept = Halvings::new(PAGE, 1.0).expect("halvings");
    let mut pixel: Box<dyn Fn(i32, i32) -> u32> = Box::new(noise(71));
    let (pages, set, _) = composite_of(&pixel, CANVAS);
    drop(shown(&mut kept, Tiles { pages: &pages, set: &set }, far));
    let rounds = [
        vec![[256, 120, 258, 200]],
        vec![[100, 254, 200, 256]],
        vec![[254, 20, 256, 60]],
        vec![[20, 20, 22, 22], [500, 280, 502, 282]],
        vec![[300, 256, 400, 258]],
    ];
    for stripes in rounds {
        for stripe in &stripes {
            let (before, stripe) = (pixel, *stripe);
            let red = move |x, y| if inside(stripe, x, y) { 0xff00_00ff } else { before(x, y) };
            pixel = Box::new(red);
            kept.changed(stripe);
        }
        let (pages, set, _) = composite_of(&pixel, CANVAS);
        let canvas = Tiles { pages: &pages, set: &set };
        drop(shown(&mut kept, canvas, far));
        let mut anew = Halvings::new(PAGE, 1.0).expect("halvings");
        drop(shown(&mut anew, canvas, far));
        assert!(stage_bytes(&kept) == stage_bytes(&anew), "{stripes:?}");
    }
    let made = stage_bytes(&kept);
    let unmarked = move |x, y| if inside([420, 260, 440, 280], x, y) { 0 } else { pixel(x, y) };
    let (pages, set, _) = composite_of(unmarked, CANVAS);
    let canvas = Tiles { pages: &pages, set: &set };
    drop(shown(&mut kept, canvas, far));
    assert!(stage_bytes(&kept) == made);
    let mut anew = Halvings::new(PAGE, 1.0).expect("halvings");
    drop(shown(&mut anew, canvas, far));
    assert!(stage_bytes(&anew) != made, "the change not marked is one a stage shows");
}

/// An empty change marks nothing: beside a real one far off, the tiles
/// between them — over a change no one marked — are not made again.
#[test]
fn an_empty_change_marks_nothing() {
    let far = camera(0.01, (1.0, 0.0), (20.75, 18.0));
    let real = [500, 280, 502, 282];
    let red = move |x, y| if inside(real, x, y) { 0xff00_00ff } else { noise(71)(x, y) };
    let between = move |x, y| if inside([250, 140, 260, 150], x, y) { 0 } else { red(x, y) };
    let mut kept = Halvings::new(PAGE, 1.0).expect("halvings");
    let (pages, set, _) = composite_of(noise(71), CANVAS);
    drop(shown(&mut kept, Tiles { pages: &pages, set: &set }, far));
    let (pages, set, _) = composite_of(between, CANVAS);
    kept.changed([20, 20, 20, 60]);
    kept.changed([20, 30, 60, 30]);
    kept.changed(real);
    drop(shown(&mut kept, Tiles { pages: &pages, set: &set }, far));
    let (pages, set, _) = composite_of(red, CANVAS);
    let mut anew = Halvings::new(PAGE, 1.0).expect("halvings");
    drop(shown(&mut anew, Tiles { pages: &pages, set: &set }, far));
    assert!(stage_bytes(&kept) == stage_bytes(&anew));
}

// A composite over no pixel has none to halve: an extent with no width or
// no height, or turned inside out, is refused, saying so.
#[test]
fn a_composite_over_no_pixel_is_refused() {
    for extent in [[5, 0, 5, 9], [0, 9, 4, 9], [6, 0, 5, 9], [0, 9, 4, 8]] {
        assert!(Halvings::new(extent, 1.0).is_none(), "{extent:?}");
        assert_eq!(crate::last_error(), format!("a composite over {extent:?} holds no pixel to halve"));
    }
}
