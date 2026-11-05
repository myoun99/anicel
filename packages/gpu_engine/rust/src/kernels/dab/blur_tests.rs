//! The blur brush's dab on a real GPU, checked against the box passes by
//! hand and against the ledger — never against a CPU copy of them
//! (`kernels/mod.rs` has why). Every hand case is a step from nothing to
//! white, premultiplied — its four channels alike — blurred by boxes of
//! radius 1, each mean rounded half up; or one grey, which any box leaves
//! as it is.

use std::collections::HashMap;
use std::sync::OnceLock;

use super::super::tests::{along, filled, grain, radial, soft, square, texture, words};
use super::super::{Dab, Paper, StrokeTile};
use super::{Blurs, MOST_STRIPS_RADIUS, Route, Ways, Window};
use crate::kernels::composite::{Composite, TileAt, TileSet};
use crate::testing::{assert_pinned, first_engine};

const ONE: u32 = 65535;
const WHITE: [u8; 4] = [255; 4];
const SIDE: i32 = 128;

/// A step from nothing to 65535 at e, blurred by three boxes of radius 1,
/// at e − 4 .. e + 3 (past them it is the step itself):
/// - the first box puts 21845 at e − 1 and 43690 at e (65535 by thirds);
/// - the second, 7282 at e − 2 (21845 / 3 = 7281.7), 21845, 43690, and
///   58253 at e + 1 (174760 / 3 = 58253.3);
/// - the third, 2427 (7282 / 3 = 2427.3), 9709 (29127 / 3), 24272
///   (72817 / 3 = 24272.3), 41263 (123788 / 3 = 41262.7), 55826
///   (167478 / 3) and 63108 (189323 / 3 = 63107.7).
const STEP: [u32; 8] = [0, 2427, 9709, 24272, 41263, 55826, 63108, ONE];

/// The step's pixels at e − 4 .. e + 3 moved 32768/65535 of the way to
/// that blur, rounded half away from zero — up from nothing, down from
/// white: 2427 → 1213.5 → 1214, 9709 → 4854.6 → 4855, 24272 → 12136.2 →
/// 12136.
const HALFWAY: [u32; 8] = [0, 1214, 4855, 12136, ONE - 12136, ONE - 4855, ONE - 1214, ONE];

/// The step at `e` blurred, at `x`.
fn stepped(x: i32, e: i32) -> u32 {
    match x - e {
        offset if offset < -4 => 0,
        offset if offset > 3 => ONE,
        offset => STEP[(offset + 4) as usize],
    }
}

/// The picture of a step at x = `e`: nothing left of it, white from it on.
fn step_at(e: i32) -> impl Fn(i32, i32) -> [u32; 4] {
    move |x, _| if x >= e { [ONE; 4] } else { [0; 4] }
}

/// A stroke's picture after a blur: its tiles in slot order and their
/// planes.
struct Blurred {
    tiles: Vec<(i32, i32)>,
    planes: Vec<u32>,
}

impl Blurred {
    /// Pixel (x, y)'s four channels.
    fn at(&self, x: i32, y: i32) -> [u32; 4] {
        let tile = (x.div_euclid(SIDE), y.div_euclid(SIDE));
        let slot = self.tiles.iter().position(|&held| held == tile).expect("a stroke tile");
        let texel = slot * (SIDE * SIDE) as usize
            + (y.rem_euclid(SIDE) * SIDE + x.rem_euclid(SIDE)) as usize;
        let [low, high] = [self.planes[texel * 2], self.planes[texel * 2 + 1]];
        [low & 0xffff, low >> 16, high & 0xffff, high >> 16]
    }

    fn bytes(&self) -> Vec<u8> {
        self.planes.iter().flat_map(|word| word.to_le_bytes()).collect()
    }
}

/// The picture on `tiles` (slots in their order) holding `pixel`, blurred
/// under `dabs` over `paper` as a blur goes — or nothing, where the kernel
/// refused them — once a pass a dispatch is seen to move them alike.
fn blurred(
    tiles: &[(i32, i32)],
    pixel: impl Fn(i32, i32) -> [u32; 4],
    dabs: &[(Dab, u32)],
    paper: Option<&Paper>,
) -> Option<Blurred> {
    let mut planes = Vec::new();
    for &(column, row) in tiles {
        for y in 0..SIDE {
            for x in 0..SIDE {
                let [red, green, blue, alpha] = pixel(column * SIDE + x, row * SIDE + y);
                planes.extend([red | green << 16, blue | alpha << 16]);
            }
        }
    }
    let stroke: Vec<StrokeTile> = tiles
        .iter()
        .enumerate()
        .map(|(slot, &(column, row))| StrokeTile { column, row, slot: slot as u32 })
        .collect();
    let engine = first_engine();
    let picture = filled("test picture", &planes);
    let laid = Blurs::new(engine).blur(engine, &stroke, dabs, paper, &picture);
    let passes = filled("test picture", &planes);
    let by_passes =
        Blurs::new(engine).blur_by(engine, &stroke, dabs, paper, &passes, Route::Passes);
    assert_eq!(laid.is_some(), by_passes.is_some());
    laid?;
    assert!(words(&picture) == words(&passes), "a pass a dispatch moved them apart");
    Some(Blurred { tiles: tiles.to_vec(), planes: words(&picture) })
}

// A dab at full flow lays all of itself, so its pixels take the blur whole:
// along a row the three boxes of the step, down a column boxes of equal
// pixels, which leave them as they are. Nothing past the dab moves.
#[test]
fn a_dab_at_full_flow_puts_the_blur_itself() {
    let dab = square([60, 60, 68, 64], WHITE, 1.0);
    let blurred = blurred(&[(0, 0)], step_at(64), &[(dab, 1)], None).unwrap();
    for y in 60..64 {
        for x in 60..68 {
            assert_eq!(blurred.at(x, y), [stepped(x, 64); 4], "({x}, {y})");
        }
    }
    for (x, y) in [(59, 60), (68, 61), (61, 59), (66, 64)] {
        assert_eq!(blurred.at(x, y), step_at(64)(x, y), "({x}, {y})");
    }
}

// A dab at half flow lays 32768 (0.5 on the 16-bit scale, rounded), so a
// pixel moves 32768/65535 of the way to its blur.
#[test]
fn a_dab_moves_its_pixels_by_what_it_lays() {
    let dab = square([60, 60, 68, 64], WHITE, 0.5);
    let blurred = blurred(&[(0, 0)], step_at(64), &[(dab, 1)], None).unwrap();
    for y in 60..64 {
        for (x, &value) in (60..68).zip(&HALFWAY) {
            assert_eq!(blurred.at(x, y), [value; 4], "({x}, {y})");
        }
    }
}

// What a dab lays is measured onto nothing, white and opaque
// (BrushBlurPicture): its colour's own alpha does not thin it, and its
// opacity is the level it would settle at over nothing — at 0.5 it lays
// 32768, as half flow does, wherever the picture stands.
#[test]
fn a_dab_lays_what_it_would_onto_nothing() {
    let thin = square([60, 60, 68, 64], [200, 100, 50, 128], 1.0);
    let blurred_thin = blurred(&[(0, 0)], step_at(64), &[(thin, 1)], None).unwrap();
    let settling = Dab { opacity: 0.5, ..square([60, 60, 68, 64], WHITE, 1.0) };
    let blurred_half = blurred(&[(0, 0)], step_at(64), &[(settling, 1)], None).unwrap();
    for y in 60..64 {
        for x in 60..68 {
            assert_eq!(blurred_thin.at(x, y), [stepped(x, 64); 4], "({x}, {y})");
            assert_eq!(blurred_half.at(x, y), [HALFWAY[(x - 60) as usize]; 4], "({x}, {y})");
        }
    }
}

// Each dab reads what the one before it moved. The first puts the step's
// blur on x 60..63 (0, 2427, 9709, 24272) down every row the second reads;
// the second blurs x 64..67 from that: its boxes put 12136, 33172 and 51781
// (155342 / 3 = 51780.7) at 62..64, then 32363, 50163 (150488 / 3) and
// 60950 (182851 / 3) at 63..65, then 47825 (143476 / 3), 58883 (176648 / 3)
// and 64007 (192020 / 3) at 64..66 — where from the step as it was they
// would have put 41263, 55826 and 63108.
#[test]
fn each_dab_reads_what_the_one_before_it_moved() {
    let first = square([60, 56, 64, 72], WHITE, 1.0);
    let second = square([64, 59, 68, 69], WHITE, 1.0);
    let blurred = blurred(&[(0, 0)], step_at(64), &[(first, 1), (second, 1)], None).unwrap();
    let both = [0, 2427, 9709, 24272, 47825, 58883, 64007, ONE];
    for y in 59..69 {
        for (x, &value) in (60..68).zip(&both) {
            assert_eq!(blurred.at(x, y), [value; 4], "({x}, {y})");
        }
    }
    // Above and below the second, the first's alone.
    for y in [56, 58, 69, 71] {
        for x in 60..68 {
            assert_eq!(blurred.at(x, y), [if x < 64 { stepped(x, 64) } else { ONE }; 4]);
        }
    }
}

// A window across the canvas's origin reads four tiles, each by its slot,
// whatever order the stroke holds them in.
#[test]
fn a_window_across_tiles_reads_each_by_its_slot() {
    let tiles = [(0, 0), (-1, -1), (0, -1), (-1, 0)];
    let dab = square([-4, -2, 4, 2], WHITE, 1.0);
    let blurred = blurred(&tiles, step_at(0), &[(dab, 1)], None).unwrap();
    for y in -2..2 {
        for x in -4..4 {
            assert_eq!(blurred.at(x, y), [stepped(x, 0); 4], "({x}, {y})");
        }
    }
}

// A dab wider than a workgroup's room is cut into strips along its rows —
// 1018 px and the rest — and one taller into strips down its columns; the
// strips meet with no seam, each reading past what it puts as the passes
// read past the dab.
#[test]
fn strips_of_a_dab_meet_with_no_seam() {
    let wide: Vec<(i32, i32)> = (-1..9).map(|column| (column, 0)).collect();
    let dab = square([0, 60, 1100, 62], WHITE, 1.0);
    let across = blurred(&wide, step_at(550), &[(dab, 1)], None).unwrap();
    for y in 60..62 {
        for x in 0..1100 {
            assert_eq!(across.at(x, y), [stepped(x, 550); 4], "({x}, {y})");
        }
    }
    let tall: Vec<(i32, i32)> = (-1..9).map(|row| (0, row)).collect();
    let down = |_, y: i32| if y >= 550 { [ONE; 4] } else { [0; 4] };
    let dab = square([60, 0, 62, 1100], WHITE, 1.0);
    let downward = blurred(&tall, down, &[(dab, 1)], None).unwrap();
    for y in 0..1100 {
        for x in 60..62 {
            assert_eq!(downward.at(x, y), [stepped(y, 550); 4], "({x}, {y})");
        }
    }
}

// A blur reads three radii past its dab: the stroke must hold every tile
// that reaches — a dab 2 px into a tile at radius 1 reads the one before
// it, right, left, down or up. A radius of 0 blurs nothing.
#[test]
fn a_blur_the_kernel_cannot_lay_is_refused() {
    let dab = |region| square(region, WHITE, 1.0);
    let lone = [(0, 0)];
    assert!(blurred(&lone, step_at(64), &[(dab([120, 60, 126, 64]), 1)], None).is_none());
    assert!(blurred(&[(1, 0)], step_at(64), &[(dab([130, 60, 136, 64]), 1)], None).is_none());
    assert!(blurred(&lone, step_at(64), &[(dab([60, 120, 64, 126]), 1)], None).is_none());
    assert!(blurred(&[(0, 1)], step_at(64), &[(dab([60, 130, 64, 136]), 1)], None).is_none());
    assert!(blurred(&[(1, 0)], step_at(64), &[(dab([131, 60, 136, 64]), 1)], None).is_some());
    assert!(blurred(&lone, step_at(64), &[(dab([60, 60, 68, 64]), 0)], None).is_none());
}

// A dab the strips take goes by them: what its dispatches put between them
// is the rows' blur — the dab's columns on the window's lines, 8 by 10
// here — not a pass a dispatch's two planes, 12 by 10 each.
#[test]
fn a_dab_the_strips_take_goes_by_them() {
    let engine = first_engine();
    let picture = filled("test picture", &vec![0; (SIDE * SIDE * 2) as usize]);
    let lone = [StrokeTile { column: 0, row: 0, slot: 0 }];
    let dab = square([60, 60, 68, 64], WHITE, 1.0);
    let mut blurs = Blurs::new(engine);
    blurs.blur(engine, &lone, &[(dab, 1)], None, &picture).unwrap();
    assert_eq!(blurs.between.map(|between| between.size()), Some(10 * 8 * 8));
}

// A dab goes by strips up to MOST_STRIPS_RADIUS and a pass a dispatch past
// it — 171 too, which no strip of 1024 holds with its six radii. A box of
// one grey leaves it as it is, whichever way the passes go.
#[test]
fn a_box_past_the_strips_widest_goes_a_pass_a_dispatch() {
    let around: Vec<(i32, i32)> =
        (-5..6).flat_map(|row| (-5..6).map(move |column| (column, row))).collect();
    let at: HashMap<(i32, i32), usize> =
        around.iter().enumerate().map(|(slot, &tile)| (tile, slot)).collect();
    let middle = square([60, 60, 61, 61], WHITE, 1.0);
    let by_strips = |radius| {
        Window::of(&middle, radius, &at, Route::Strips)
            .map(|window| matches!(window.ways, Ways::Strips { .. }))
    };
    assert_eq!(by_strips(MOST_STRIPS_RADIUS), Some(true));
    assert_eq!(by_strips(MOST_STRIPS_RADIUS + 1), Some(false));
    let grey = [20000, 30000, 40000, 50000];
    for radius in [MOST_STRIPS_RADIUS, MOST_STRIPS_RADIUS + 1, 171] {
        let blurred = blurred(&around, |_, _| grey, &[(middle, radius)], None).unwrap();
        for y in 58..63 {
            for x in 58..63 {
                assert_eq!(blurred.at(x, y), grey, "{radius} ({x}, {y})");
            }
        }
    }
}

// A second tip's dab lays nothing on a stroke with no second plane, so it
// blurs nothing.
#[test]
fn a_second_tips_dab_blurs_nothing() {
    let dab = Dab { second: true, ..square([60, 60, 68, 64], WHITE, 1.0) };
    let blurred = blurred(&[(0, 0)], step_at(64), &[(dab, 1)], None).unwrap();
    for y in 58..66 {
        for x in 56..72 {
            assert_eq!(blurred.at(x, y), step_at(64)(x, y));
        }
    }
}

/// A premultiplied picture of hashed colours: every channel at or under
/// its alpha.
fn hashed(x: i32, y: i32) -> [u32; 4] {
    let at = (x.wrapping_mul(73856093) ^ y.wrapping_mul(19349663)) as u32;
    let hash = |salt: u32| (at ^ salt).wrapping_mul(2654435761) >> 16;
    let alpha = hash(0x9e37);
    [hash(0x1234) % (alpha + 1), hash(0x5678) % (alpha + 1), hash(0x9abc) % (alpha + 1), alpha]
}

#[test]
fn every_device_blurs_the_pinned_strokes() {
    let tiles: Vec<(i32, i32)> =
        (0..2).flat_map(|row| (-1..3).map(move |column| (column, row))).collect();
    let (coverage, pile, inner) = soft(13.77, 0.3);
    let profile = radial(&coverage, &pile, 14.27, inner);
    // 27.54 px a dab: the app's radius, max(1, round(27.54 / 6)), is 5.
    let rubbed: Vec<(Dab, u32)> =
        along(&profile, 24, |_, dab| dab.flow = 0.6).into_iter().map(|dab| (dab, 5)).collect();
    let plain = blurred(&tiles, hashed, &rubbed, None).unwrap();
    assert_pinned("dab/blur-planes", &plain.bytes());
    let grain = texture(&grain(), 32);
    let paper = Paper { texture: &grain, scale: 0.7, height: false };
    // An eraser's dab, every third, and an opacity under one: what a blur
    // dab lays is measured not erasing.
    let papered: Vec<(Dab, u32)> = along(&profile, 24, |k, dab| {
        dab.flow = 0.6;
        dab.opacity = 0.7;
        dab.erase = k % 3 == 0;
        dab.density = Some(0.3 + f64::from(k % 4) * 0.2);
    })
    .into_iter()
    .map(|dab| (dab, 5))
    .collect();
    let on_paper = blurred(&tiles, hashed, &papered, Some(&paper)).unwrap();
    assert_pinned("dab/blur-paper-planes", &on_paper.bytes());
}

// ---- The cel ----

/// A stroke tile's words: two a pixel.
const TILE_WORDS: usize = (SIDE * SIDE * 2) as usize;
/// What a picture holds before it is made of the cel.
const JUNK: u32 = 0xdead_beef;

/// One device's executor for every test here (composite's tests have why).
fn executor() -> &'static Composite {
    static EXECUTOR: OnceLock<Composite> = OnceLock::new();
    EXECUTOR.get_or_init(|| Composite::new(first_engine()).expect("compile the composite"))
}

/// A cel whose stored pixel at (x, y) is `stored(x, y)`, on the tiles of
/// `columns` × `rows` from `origin` but `holes`: its pages — one, a tile a
/// slot — and the tile set naming them.
fn cel_of(
    stored: impl Fn(i32, i32) -> u32,
    (x0, y0): (i32, i32),
    (columns, rows): (u32, u32),
    holes: &[(i32, i32)],
) -> (Vec<wgpu::Buffer>, TileSet) {
    let mut words = Vec::new();
    let mut tiles = Vec::new();
    for row in y0..y0 + rows as i32 {
        for column in x0..x0 + columns as i32 {
            if holes.contains(&(column, row)) {
                tiles.push(None);
                continue;
            }
            let slot = (words.len() / (SIDE * SIDE) as usize) as u16;
            for y in 0..SIDE {
                for x in 0..SIDE {
                    words.push(stored(column * SIDE + x, row * SIDE + y));
                }
            }
            tiles.push(Some(TileAt { page: 0, slot }));
        }
    }
    let set = TileSet { x0, y0, columns, rows, tiles };
    (vec![filled("test cel", &words)], set)
}

/// The stroke's `tiles`, each at the slot counted from the last — so none
/// sits at its own index.
fn stroke_of(tiles: &[(i32, i32)]) -> Vec<StrokeTile> {
    let last = tiles.len() - 1;
    let slot = |index: usize| (last - index) as u32;
    tiles
        .iter()
        .enumerate()
        .map(|(index, &(column, row))| StrokeTile { column, row, slot: slot(index) })
        .collect()
}

/// `tiles` of `cel` made into a picture over junk, blurred under `dabs`
/// and finished: the picture's words as it was made, and the finished
/// tiles', tile after tile in `tiles`' order.
fn rubbed(
    cel: &(Vec<wgpu::Buffer>, TileSet),
    tiles: &[(i32, i32)],
    dabs: &[(Dab, u32)],
) -> (Vec<u32>, Vec<u32>) {
    let engine = first_engine();
    let stroke = stroke_of(tiles);
    let mut blurs = Blurs::new(engine);
    let picture = filled("test picture", &vec![JUNK; tiles.len() * TILE_WORDS]);
    blurs.fill(engine, executor(), (&cel.0, &cel.1), &stroke, &picture).unwrap();
    let made = words(&picture);
    blurs.blur(engine, &stroke, dabs, None, &picture).unwrap();
    (made, words(&blurs.finish(engine, &stroke, &picture).unwrap()))
}

// A stroke tile is made of the cel's, each pixel premultiplied on the
// 16-bit scale — round(c·a·257 / 255): (255, 128, 0, 128) is 32896, 16513
// (4210688 / 255 = 16512.5), 0 and 32896; (200, 100, 50, 1) is 202
// (51400 / 255 = 201.6), 101, 50 and 257; (7, 7, 7, 7) is 49 (12593 / 255
// = 49.4) and 1799 — and of nothing where the cel has no tile.
#[test]
fn a_stroke_tile_is_made_of_the_cel_premultiplied() {
    let stored = |x: i32, y: i32| match (x, y) {
        (0, 0) => u32::from_le_bytes([255, 128, 0, 128]),
        (1, 0) => u32::from_le_bytes([200, 100, 50, 1]),
        (2, 0) => 0,
        _ => u32::from_le_bytes([7; 4]),
    };
    let cel = cel_of(stored, (0, 0), (2, 1), &[(1, 0)]);
    // (0, 0) at slot 1, the hole (1, 0) at slot 0.
    let (made, _) = rubbed(&cel, &[(0, 0), (1, 0)], &[]);
    let pixel = |slot: usize, texel: usize| {
        let at = slot * TILE_WORDS + texel * 2;
        let [low, high] = [made[at], made[at + 1]];
        [low & 0xffff, low >> 16, high & 0xffff, high >> 16]
    };
    assert_eq!(pixel(1, 0), [32896, 16513, 0, 32896]);
    assert_eq!(pixel(1, 1), [202, 101, 50, 257]);
    assert_eq!(pixel(1, 2), [0; 4]);
    assert_eq!(pixel(1, 3), [49, 49, 49, 1799]);
    assert_eq!(pixel(1, TILE_WORDS / 2 - 1), [49, 49, 49, 1799]);
    assert!((0..TILE_WORDS / 2).all(|texel| pixel(0, texel) == [0; 4]));
}

// Where no dab moved the picture a finished tile is the cel's own bytes:
// every channel's byte under every alpha comes back from its premultiplied
// form (blur_cel.wgsl has why) — and a pixel of no alpha is nothing, as
// the pool holds it. Nothing where the cel has no tile.
#[test]
fn every_stored_pixel_comes_back_from_its_picture() {
    // Tile (column, 0)'s texel t: alpha t / 256 + 64·column, and in red
    // its column plus 128 on odd rows — every byte —, the byte's opposite
    // in green, a third in blue.
    let stored = |x: i32, y: i32| {
        let alpha = (y * SIDE + x.rem_euclid(SIDE)) as u32 / 256 + 64 * x.div_euclid(SIDE) as u32;
        let byte = x.rem_euclid(SIDE) as u32 + 128 * (y as u32 % 2);
        if alpha == 0 {
            return 0;
        }
        byte | (255 - byte) << 8 | (byte ^ 0x5a) << 16 | alpha << 24
    };
    let cel = cel_of(stored, (0, 0), (5, 1), &[(4, 0)]);
    let tiles = [(2, 0), (4, 0), (0, 0), (3, 0), (1, 0)];
    let (_, finished) = rubbed(&cel, &tiles, &[]);
    for (index, &(column, _)) in tiles.iter().enumerate() {
        for texel in 0..(SIDE * SIDE) {
            let (x, y) = (column * SIDE + texel % SIDE, texel / SIDE);
            let want = if column == 4 { 0 } else { stored(x, y) };
            let got = finished[index * (SIDE * SIDE) as usize + texel as usize];
            assert_eq!(got, want, "({x}, {y})");
        }
    }
}

// A finished pixel is its picture stored: a step of white, rubbed whole by
// a dab of radius 1, holds the boxes' 2427, 9709, 24272, 41263, 55826 and
// 63108 at x 61..66 — white under alphas of round(v / 257): 9 (9.4), 38
// (37.8), 94 (94.4), 161 (160.6), 217 (217.2) and 246 (245.6). Past them,
// and past the dab, the cel as it was.
#[test]
fn a_moved_pixel_finishes_as_its_picture_stored() {
    let white = u32::from_le_bytes(WHITE);
    let cel = cel_of(|x, _| if x >= 64 { white } else { 0 }, (0, 0), (1, 1), &[]);
    let dab = square([60, 60, 68, 64], WHITE, 1.0);
    let (_, finished) = rubbed(&cel, &[(0, 0)], &[(dab, 1)]);
    let alphas = [0, 9, 38, 94, 161, 217, 246, 255];
    for y in 59..65 {
        for (x, &alpha) in (60..68).zip(&alphas) {
            let moved = (60..64).contains(&y) && alpha != 0;
            let want = match (moved, x >= 64) {
                (true, _) => 0x00ff_ffff | alpha << 24,
                (false, true) => white,
                (false, false) => 0,
            };
            assert_eq!(finished[(y * SIDE + x) as usize], want, "({x}, {y})");
        }
    }
}

// Most of a stroke's dabs meet no tile it has not made yet: a fill of no
// tiles, and a finish of none, run no pass.
#[test]
fn no_tile_to_make_or_finish_is_no_pass() {
    let engine = first_engine();
    let cel = cel_of(|_, _| 0, (0, 0), (1, 1), &[]);
    let picture = filled("test picture", &[JUNK; 2]);
    let blurs = Blurs::new(engine);
    assert!(blurs.fill(engine, executor(), (&cel.0, &cel.1), &[], &picture).is_some());
    assert!(blurs.finish(engine, &[], &picture).is_some());
    assert_eq!(words(&picture), [JUNK; 2]);
}

/// A stored pixel of a hashed cel: a quarter nothing, a quarter opaque, the
/// rest any alpha but none — and no colour where no alpha, as the pool
/// never holds (blend_pack8).
fn stored_hashed(x: i32, y: i32) -> u32 {
    let at = (x.wrapping_mul(83492791) ^ y.wrapping_mul(50331653)) as u32;
    let hash = |salt: u32| (at ^ salt).wrapping_mul(2654435761) >> 8;
    let alpha = match hash(0x51) & 3 {
        0 => 0,
        1 => 255,
        _ => (hash(0x77) & 0xff) | 1,
    };
    if alpha == 0 {
        return 0;
    }
    (hash(0x3c3c) & 0x00ff_ffff) | alpha << 24
}

#[test]
fn every_device_finishes_the_pinned_stroke() {
    let cel = cel_of(stored_hashed, (-1, 0), (4, 2), &[(2, 1)]);
    let tiles: Vec<(i32, i32)> =
        (0..2).flat_map(|row| (-1..3).map(move |column| (column, row))).collect();
    let (coverage, pile, inner) = soft(13.77, 0.3);
    let profile = radial(&coverage, &pile, 14.27, inner);
    let dabs: Vec<(Dab, u32)> =
        along(&profile, 24, |_, dab| dab.flow = 0.6).into_iter().map(|dab| (dab, 5)).collect();
    let (_, finished) = rubbed(&cel, &tiles, &dabs);
    let bytes: Vec<u8> = finished.iter().flat_map(|word| word.to_le_bytes()).collect();
    assert_pinned("dab/blur-finished", &bytes);
}
