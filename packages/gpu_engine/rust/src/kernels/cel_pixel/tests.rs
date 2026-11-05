//! The cel pixel pass on a real GPU, checked against what C's pass gives
//! by hand and against the ledger — never against a CPU copy of it
//! (`kernels/mod.rs` has why). A cel's tiles are filled as the executor's
//! tests fill theirs (`Pool`); every scene names its pixels one by one, and
//! every pixel it does not name is nothing.

use std::collections::HashMap;
use std::sync::OnceLock;

use super::{CelPixels, Channel, Incoming, Mask, Passed, Selector, Verb};
use crate::device::Engine;
use crate::kernels::composite::tests::{Pool, mix};
use crate::kernels::composite::{TILE, TileSet};
use crate::kernels::effects::KeyRun;
use crate::kernels::mask::MaskBox;
use crate::kernels::shared::words_buffer;
use crate::testing::{assert_pinned, first_engine, read_buffer};

pub(super) const SIDE: i32 = TILE as i32;
const TEXELS: usize = (TILE * TILE) as usize;
/// 색 변환's channel: R, G and B; a pixel with no ink takes no part.
const COLOUR: Channel = Channel {
    bytes: 3,
    base: 0,
    stride: 1,
    takes_empty: false,
};
/// The alpha verbs' channel: every pixel covered takes part.
const ALPHA: Channel = Channel {
    bytes: 1,
    base: 3,
    stride: 0,
    takes_empty: true,
};

struct Rig {
    engine: &'static Engine,
    pass: CelPixels,
}

/// One device and one compiled pass for every test here (blend's tests
/// have why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        let pass = CelPixels::new(engine).expect("compile the cel pixel pass");
        Rig { engine, pass }
    })
}

pub(super) fn rgba(red: u32, green: u32, blue: u32, alpha: u32) -> u32 {
    red | green << 8 | blue << 16 | alpha << 24
}

/// A colour's value as a run holds it: the channel's byte i in bits 8i.
fn rgb(red: u32, green: u32, blue: u32) -> u32 {
    red | green << 8 | blue << 16
}

/// A cel: its pool and its tile set.
pub(super) struct Cel {
    pub(super) pool: Pool,
    pub(super) set: TileSet,
}

/// The cel whose pixel at (x, y) is `pixel(x, y)`, over the tiles of
/// `size` from `origin`, each on the page `place` gives it or none.
pub(super) fn cel(
    origin: (i32, i32),
    size: (u32, u32),
    pixel: impl Fn(i32, i32) -> u32,
    place: impl Fn(i32, i32) -> Option<u16>,
) -> Cel {
    let mut pool = Pool::default();
    let set = pool.drawn(pixel, origin, size, place);
    Cel { pool, set }
}

/// The cel of tile (0, 0) alone, on page 0, its pixels `named` and nothing
/// elsewhere.
pub(super) fn one(named: &[((i32, i32), u32)]) -> Cel {
    let named: HashMap<(i32, i32), u32> = named.iter().copied().collect();
    cel((0, 0), (1, 1), move |x, y| named.get(&(x, y)).copied().unwrap_or(0), |_, _| Some(0))
}

/// `verb` over `cel`, its passes cut at `cut`'s pages and tiles or as the
/// device cuts them: what it left, and its new pixels' words.
fn run(cel: &Cel, verb: &Verb, cut: Option<(usize, usize)>) -> Option<(Passed, Vec<u32>)> {
    under(cel, None, verb, cut)
}

/// `run` under `mask`.
fn under(
    cel: &Cel,
    mask: Option<&Mask>,
    verb: &Verb,
    cut: Option<(usize, usize)>,
) -> Option<(Passed, Vec<u32>)> {
    let Rig { engine, pass } = rig();
    let pages = cel.pool.upload(engine);
    let passed = match cut {
        Some(cut) => pass.run_by(engine, &pages, &cel.set, mask, verb, cut),
        None => pass.run(engine, &pages, &cel.set, mask, verb),
    }?;
    let out = read_buffer(engine, &passed.out)
        .chunks_exact(4)
        .map(|four| u32::from_le_bytes([four[0], four[1], four[2], four[3]]))
        .collect();
    Some((passed, out))
}

/// A selection's mask: its plane over its box.
pub(super) struct Masked {
    plane: wgpu::Buffer,
    at: (i32, i32),
    size: MaskBox,
}

impl Masked {
    pub(super) fn mask(&self) -> Mask<'_> {
        Mask {
            plane: &self.plane,
            at: self.at,
            size: self.size,
        }
    }
}

/// The mask over `size` pixels from `at` whose byte at the cel's pixel
/// (x, y) is `coverage(x, y)` — and 255 past the box in a row's last word,
/// which a pass must read as nothing all the same.
pub(super) fn masked(
    at: (i32, i32),
    size: (u32, u32),
    coverage: impl Fn(i32, i32) -> u8,
) -> Masked {
    let mut words = Vec::new();
    for y in 0..size.1 as i32 {
        for word in 0..size.0.div_ceil(4) {
            let byte = |i: u32| match word * 4 + i {
                x if x < size.0 => u32::from(coverage(at.0 + x as i32, at.1 + y)),
                _ => 255,
            };
            words.push((0..4).fold(0, |packed, i| packed | byte(i) << (8 * i)));
        }
    }
    let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
    Masked {
        plane: words_buffer(rig().engine, "mask", &words, usage),
        at,
        size: MaskBox {
            width: size.0,
            height: size.1,
        },
    }
}

/// The cel `passed` left: its walked tiles holding `out`, on page 0.
fn after(passed: &Passed, out: &[u32]) -> Cel {
    let tiles = passed.tiles.clone();
    let span = |at: fn(&(i32, i32)) -> i32| {
        let first = tiles.iter().map(at).min().unwrap();
        (first, (tiles.iter().map(at).max().unwrap() - first + 1) as u32)
    };
    let ((x0, columns), (y0, rows)) = (span(|tile| tile.0), span(|tile| tile.1));
    let out = out.to_vec();
    let pixel = move |x: i32, y: i32| {
        let tile = (x.div_euclid(SIDE), y.div_euclid(SIDE));
        let walked = tiles.iter().position(|&each| each == tile).expect("a walked tile");
        out[walked * TEXELS + (y.rem_euclid(SIDE) * SIDE + x.rem_euclid(SIDE)) as usize]
    };
    let walked = passed.tiles.clone();
    cel((x0, y0), (columns, rows), pixel, move |column, row| {
        walked.contains(&(column, row)).then_some(0)
    })
}

/// Fails unless the walked tile `tile` of `out` holds `scene`'s pixels but
/// for `changed`, which hold what it gives.
fn assert_tile(
    out: &[u32],
    tile: usize,
    origin: (i32, i32),
    scene: &[((i32, i32), u32)],
    changed: &[((i32, i32), u32)],
) {
    let scene: HashMap<(i32, i32), u32> = scene.iter().copied().collect();
    let changed: HashMap<(i32, i32), u32> = changed.iter().copied().collect();
    for y in 0..SIDE {
        for x in 0..SIDE {
            let at = (origin.0 + x, origin.1 + y);
            let wanted = changed.get(&at).or(scene.get(&at)).copied().unwrap_or(0);
            let put = out[tile * TEXELS + (y * SIDE + x) as usize];
            assert_eq!(put, wanted, "({}, {}): {put:#010x} for {wanted:#010x}", at.0, at.1);
        }
    }
}

fn recolour(value: &[u8]) -> Verb<'_> {
    Verb {
        channel: COLOUR,
        selector: None,
        threshold: 0,
        incoming: Incoming::Value(value),
    }
}

fn clear() -> Verb<'static> {
    Verb {
        channel: ALPHA,
        selector: None,
        threshold: 0,
        incoming: Incoming::Value(&[0]),
    }
}

/// A run of one key naming the colours within `tolerance` of `key` on
/// every channel — the tables `CelColorKey.matches` makes.
fn tables(key: [u32; 3], tolerance: u32) -> [[u32; 256]; 3] {
    key.map(|channel| {
        let mut table = [0u32; 256];
        for (byte, bit) in table.iter_mut().enumerate() {
            *bit = u32::from((byte as u32).abs_diff(channel) <= tolerance);
        }
        table
    })
}

fn selector(tables: &[[u32; 256]; 3], keeps_matches: bool) -> Selector<'_> {
    Selector {
        key: KeyRun {
            red: &tables[0],
            green: &tables[1],
            blue: &tables[2],
            restores: 0,
            maps: &[],
        },
        keeps_matches,
    }
}

// ---- Going forward ----

pub(super) const INK: u32 = 0x00_1e_14_0a; // rgb(10, 20, 30)
pub(super) const OTHER: u32 = 0x00_46_3c_32; // rgb(50, 60, 70)

/// 색 변환 over ink A on row 0 at 0..4 and 5..7, an empty pixel holding a
/// colour between them, B at 7 and at the start of row 1, A again on row 2:
/// the ink takes the new colour under its own alpha, the empty pixel takes
/// no part, and the runs go A × 6 — across the empty pixel —, B × 2 —
/// across the row's end —, A × 1.
#[test]
fn a_recolour_takes_the_ink_and_keeps_its_alpha() {
    let a = |alpha: u32| INK | alpha << 24;
    let b = |alpha: u32| OTHER | alpha << 24;
    let scene = [
        ((0, 0), a(200)),
        ((1, 0), a(200)),
        ((2, 0), a(255)),
        ((3, 0), a(1)),
        ((4, 0), rgba(9, 9, 9, 0)),
        ((5, 0), a(200)),
        ((6, 0), a(77)),
        ((7, 0), b(128)),
        ((0, 1), b(255)),
        ((3, 2), a(9)),
    ];
    let (passed, out) = run(&one(&scene), &recolour(&[1, 2, 3]), None).expect("run");
    assert_eq!(passed.tiles, [(0, 0)]);
    assert_eq!(passed.touched, [9]);
    assert_eq!(passed.runs, [vec![(INK, 6), (OTHER, 2), (INK, 1)]]);
    let new = |alpha| rgba(1, 2, 3, alpha);
    let changed = [
        ((0, 0), new(200)),
        ((1, 0), new(200)),
        ((2, 0), new(255)),
        ((3, 0), new(1)),
        ((5, 0), new(200)),
        ((6, 0), new(77)),
        ((7, 0), new(128)),
        ((0, 1), new(255)),
        ((3, 2), new(9)),
    ];
    assert_tile(&out, 0, (0, 0), &scene, &changed);
}

/// 픽셀 비우기 takes every pixel and empties it, its colour left under the
/// alpha of 0 — and 색 삭제 after it still names those pixels by that
/// colour, as the stored bytes hold it.
#[test]
fn a_clear_keeps_the_colour_that_a_selector_names_after_it() {
    let scene = [
        ((0, 0), INK | 255 << 24),
        ((1, 0), INK | 255 << 24),
        ((3, 0), rgba(40, 50, 60, 7)),
    ];
    let (passed, out) = run(&one(&scene), &clear(), None).expect("clear");
    assert_eq!(passed.touched, [TEXELS as u32]);
    // Every pixel's alpha, in walk order: 255, 255, 0 at (2, 0), 7, then
    // the rest of the tile's 0s.
    assert_eq!(passed.runs, [vec![(255, 2), (0, 1), (7, 1), (0, TEXELS as u32 - 4)]]);
    let changed = [((0, 0), INK), ((1, 0), INK), ((3, 0), rgba(40, 50, 60, 0))];
    assert_tile(&out, 0, (0, 0), &scene, &changed);

    let key = tables([10, 20, 30], 0);
    let delete = Verb {
        selector: Some(selector(&key, false)),
        ..clear()
    };
    let (again, _) = run(&after(&passed, &out), &delete, None).expect("delete");
    assert_eq!(again.touched, [2]);
    assert_eq!(again.runs, [vec![(0, 2)]]);
}

/// 2치화 at 128: an alpha at or over the cut goes whole, one under it
/// empty; the colour stays.
#[test]
fn a_cut_makes_the_alpha_whole_or_nothing() {
    let grey = |alpha| rgba(5, 6, 7, alpha);
    let alphas = [0, 1, 127, 128, 129, 255];
    let scene: Vec<((i32, i32), u32)> =
        alphas.iter().enumerate().map(|(x, &alpha)| ((x as i32, 0), grey(alpha))).collect();
    let cut = Verb {
        threshold: 128,
        incoming: Incoming::Value(&[255]),
        ..clear()
    };
    let (passed, out) = run(&one(&scene), &cut, None).expect("run");
    let rest = TEXELS as u32 - 6;
    let runs = [(0, 1), (1, 1), (127, 1), (128, 1), (129, 1), (255, 1), (0, rest)];
    assert_eq!(passed.runs, [runs.to_vec()]);
    let changed = [
        ((0, 0), grey(0)),
        ((1, 0), grey(0)),
        ((2, 0), grey(0)),
        ((3, 0), grey(255)),
        ((4, 0), grey(255)),
        ((5, 0), grey(255)),
    ];
    assert_tile(&out, 0, (0, 0), &scene, &changed);
}

/// 색 삭제 and 색 유지 by a key of (100, 150, 200) within 2: the key names
/// a pixel by its colour alone — one off by 2 on every channel, one with
/// no alpha, none off by 3 on any one channel — and 색 유지 takes the
/// others, nothing included.
#[test]
fn a_selector_names_its_pixels_by_colour_alone() {
    let scene = [
        ((0, 0), rgba(100, 150, 200, 255)),
        ((1, 0), rgba(102, 148, 202, 90)),
        ((2, 0), rgba(103, 150, 200, 255)),
        ((3, 0), rgba(100, 150, 200, 0)),
        ((4, 0), rgba(100, 153, 200, 255)),
        ((5, 0), rgba(100, 150, 197, 255)),
    ];
    let key = tables([100, 150, 200], 2);
    let delete = Verb {
        selector: Some(selector(&key, false)),
        ..clear()
    };
    let (passed, out) = run(&one(&scene), &delete, None).expect("delete");
    assert_eq!(passed.touched, [3]);
    assert_eq!(passed.runs, [vec![(255, 1), (90, 1), (0, 1)]]);
    let changed = [((0, 0), rgba(100, 150, 200, 0)), ((1, 0), rgba(102, 148, 202, 0))];
    assert_tile(&out, 0, (0, 0), &scene, &changed);

    let keep = Verb {
        selector: Some(selector(&key, true)),
        ..clear()
    };
    let (passed, out) = run(&one(&scene), &keep, None).expect("keep");
    assert_eq!(passed.touched, [TEXELS as u32 - 3]);
    // 255 at (2, 0), (4, 0) and (5, 0) — (3, 0) named between them —, then
    // the rest of the tile's 0s.
    assert_eq!(passed.runs, [vec![(255, 3), (0, TEXELS as u32 - 6)]]);
    let changed = [
        ((2, 0), rgba(103, 150, 200, 0)),
        ((4, 0), rgba(100, 153, 200, 0)),
        ((5, 0), rgba(100, 150, 197, 0)),
    ];
    assert_tile(&out, 0, (0, 0), &scene, &changed);
}

/// A channel of two bytes four apart — green and alpha —: each pixel with
/// ink takes the value's first byte on its green and its second on its
/// alpha, and a run holds them as one value, green in its low byte.
#[test]
fn a_channel_reads_and_writes_its_bytes_where_its_base_and_stride_put_them() {
    let scene = [
        ((0, 0), rgba(10, 20, 30, 200)),
        ((1, 0), rgba(10, 20, 30, 200)),
        ((2, 0), rgba(1, 2, 3, 0)),
    ];
    let green_alpha = Verb {
        channel: Channel {
            bytes: 2,
            base: 1,
            stride: 2,
            takes_empty: false,
        },
        ..recolour(&[7, 9])
    };
    let (passed, out) = run(&one(&scene), &green_alpha, None).expect("run");
    assert_eq!(passed.runs, [vec![(20 | 200 << 8, 2)]]);
    let changed = [((0, 0), rgba(10, 7, 30, 9)), ((1, 0), rgba(10, 7, 30, 9))];
    assert_tile(&out, 0, (0, 0), &scene, &changed);
}

/// Two tiles of one ink everywhere: a run ends at its tile, as C's — the
/// app's recipe builder joins them.
#[test]
fn a_run_ends_with_its_tile() {
    let ink = cel((0, 0), (2, 1), |_, _| INK | 255 << 24, |_, _| Some(0));
    let (passed, _) = run(&ink, &recolour(&[1, 2, 3]), None).expect("run");
    let whole = vec![(INK, TEXELS as u32)];
    assert_eq!(passed.runs, [whole.clone(), whole]);
}

/// The walk goes row by row over the cel's tiles, past the one it has none
/// of, each tile counting its own pixels and runs.
#[test]
fn the_walk_goes_row_by_row_past_a_missing_tile() {
    // Tile (c, r) holds c + 5 + 3r pixels of ink, one run.
    let pixel = |x: i32, y: i32| {
        let (column, row) = (x.div_euclid(SIDE), y.div_euclid(SIDE));
        let inked = column + 5 + 3 * row;
        if y.rem_euclid(SIDE) == 0 && x.rem_euclid(SIDE) < inked { INK | 255 << 24 } else { 0 }
    };
    let cel = cel((-1, -1), (3, 2), pixel, |column, row| ((column, row) != (0, 0)).then_some(0));
    let (passed, _) = run(&cel, &recolour(&[1, 2, 3]), None).expect("run");
    assert_eq!(passed.tiles, [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0)]);
    assert_eq!(passed.touched, [1, 2, 3, 4, 6]);
    let runs: Vec<Vec<(u32, u32)>> = [1, 2, 3, 4, 6].map(|count| vec![(INK, count)]).to_vec();
    assert_eq!(passed.runs, runs);
}

/// A cel of no tiles walks none.
#[test]
fn a_cel_of_no_tiles_walks_none() {
    let empty = cel((0, 0), (2, 2), |_, _| INK | 255 << 24, |_, _| None);
    let (passed, _) = run(&empty, &recolour(&[1, 2, 3]), None).expect("run");
    assert!(passed.tiles.is_empty() && passed.touched.is_empty() && passed.runs.is_empty());
}

// ---- Undo ----

/// A recolour over two tiles, then its undo by the recipe laid flat in
/// walk order: the second tile's pixel reads the recipe's fourth entry —
/// past the first tile's three pixels, not its two runs —, and every pixel
/// is back as it was.
#[test]
fn an_undo_puts_the_recipe_back_in_walk_order() {
    let scene = [
        ((0, 0), rgba(10, 20, 30, 200)),
        ((1, 0), rgba(10, 20, 30, 255)),
        ((2, 0), rgba(11, 21, 31, 255)),
        ((128, 0), rgba(12, 22, 32, 100)),
    ];
    let named: HashMap<(i32, i32), u32> = scene.iter().copied().collect();
    let two = cel((0, 0), (2, 1), move |x, y| named.get(&(x, y)).copied().unwrap_or(0), |_, _| {
        Some(0)
    });
    let (passed, out) = run(&two, &recolour(&[1, 2, 3]), None).expect("forward");
    let first = vec![(rgb(10, 20, 30), 2), (rgb(11, 21, 31), 1)];
    assert_eq!(passed.runs, [first, vec![(rgb(12, 22, 32), 1)]]);
    let recipe = [10, 20, 30, 10, 20, 30, 11, 21, 31, 12, 22, 32];
    let undo = Verb {
        incoming: Incoming::Recipe {
            bytes: &recipe,
            step: 3,
            count: 4,
        },
        ..recolour(&[])
    };
    let (undone, back) = run(&after(&passed, &out), &undo, None).expect("undo");
    assert_eq!(undone.touched, [3, 1]);
    assert!(undone.runs.is_empty());
    assert_tile(&back, 0, (0, 0), &scene, &[]);
    assert_tile(&back, 1, (128, 0), &scene, &[]);
}

/// A uniform recipe — one value stepped 0 — puts that value back on every
/// pixel it walks.
#[test]
fn a_uniform_recipe_is_one_value_for_every_pixel() {
    let scene = [((0, 0), INK | 200 << 24), ((5, 3), INK | 9 << 24)];
    let (passed, out) = run(&one(&scene), &recolour(&[1, 2, 3]), None).expect("forward");
    let undo = Verb {
        incoming: Incoming::Recipe {
            bytes: &[10, 20, 30],
            step: 0,
            count: 2,
        },
        ..recolour(&[])
    };
    let (_, back) = run(&after(&passed, &out), &undo, None).expect("undo");
    assert_tile(&back, 0, (0, 0), &scene, &[]);
}

/// An undo whose walk goes past its recipe is refused, as the app refuses
/// it; one that ends on it is not.
#[test]
fn an_undo_past_its_recipe_is_refused() {
    let scene = [((0, 0), INK | 255 << 24), ((1, 0), INK | 255 << 24), ((2, 0), INK | 255 << 24)];
    let undo = |count| Verb {
        incoming: Incoming::Recipe {
            bytes: &[10, 20, 30],
            step: 0,
            count,
        },
        ..recolour(&[])
    };
    assert!(run(&one(&scene), &undo(2), None).is_none());
    assert!(run(&one(&scene), &undo(3), None).is_some());
}

// ---- Under a selection ----

/// Ink everywhere on rows 0 to 3 from x = 0 to 7.
fn inked() -> Vec<((i32, i32), u32)> {
    (0..4).flat_map(|y| (0..8).map(move |x| ((x, y), INK | 255 << 24))).collect()
}

/// The mask from (2, 1), 3 × 2: 255, 128, 0 over 64, 1, 255.
fn feathered() -> Masked {
    masked((2, 1), (3, 2), |x, y| [[255, 128, 0], [64, 1, 255]][(y - 1) as usize][(x - 2) as usize])
}

/// 색 변환 to (200, 100, 50) under `feathered` over `inked`: a whole
/// coverage takes the colour, a partial one blends it into the old by
/// `_blend`'s mul-div-255 — (10, 20, 30) at 128 makes (105, 60, 40), at 64
/// (58, 40, 35), at 1 (11, 20, 30) —, and a 0 takes no part, nor does a
/// pixel past the box, where the plane's row holds 255 past it; the alpha
/// stays.
#[test]
fn a_mask_blends_the_value_by_its_coverage() {
    let scene = inked();
    let mask = feathered();
    let (passed, out) =
        under(&one(&scene), Some(&mask.mask()), &recolour(&[200, 100, 50]), None).expect("run");
    assert_eq!(passed.tiles, [(0, 0)]);
    assert_eq!(passed.touched, [5]);
    assert_eq!(passed.runs, [vec![(rgb(10, 20, 30), 5)]]);
    let changed = [
        ((2, 1), rgba(200, 100, 50, 255)),
        ((3, 1), rgba(105, 60, 40, 255)),
        ((2, 2), rgba(58, 40, 35, 255)),
        ((3, 2), rgba(11, 20, 30, 255)),
        ((4, 2), rgba(200, 100, 50, 255)),
    ];
    assert_tile(&out, 0, (0, 0), &scene, &changed);
}

/// That recolour undone under the same mask: the recipe is assigned at
/// every coverage, not blended — the pixel at 128 takes (10, 20, 30) back
/// whole — and the pixels the mask leaves out stay as they are.
#[test]
fn an_undo_under_a_mask_assigns_its_recipe() {
    let scene = inked();
    let mask = feathered();
    let forward = recolour(&[200, 100, 50]);
    let (passed, out) = under(&one(&scene), Some(&mask.mask()), &forward, None).expect("run");
    let undo = Verb {
        incoming: Incoming::Recipe {
            bytes: &[10, 20, 30],
            step: 0,
            count: 5,
        },
        ..recolour(&[])
    };
    let (undone, back) =
        under(&after(&passed, &out), Some(&mask.mask()), &undo, None).expect("undo");
    assert_eq!(undone.touched, [5]);
    assert_tile(&back, 0, (0, 0), &scene, &[]);
}

/// A mask from (-3, -2), 6 × 3, whole, over a cel of 3 × 2 tiles from
/// (-1, -1) inked everywhere: the walk takes the four tiles its box meets,
/// in their order, and the pixels under it alone — a tile left of the
/// canvas's origin reads the mask's first column at its pixel 125.
#[test]
fn a_mask_walks_the_tiles_its_box_meets() {
    let ink = INK | 255 << 24;
    let cel = cel((-1, -1), (3, 2), |_, _| ink, |_, _| Some(0));
    let mask = masked((-3, -2), (6, 3), |_, _| 255);
    let (passed, out) =
        under(&cel, Some(&mask.mask()), &recolour(&[1, 2, 3]), None).expect("run");
    assert_eq!(passed.tiles, [(-1, -1), (0, -1), (-1, 0), (0, 0)]);
    assert_eq!(passed.touched, [6, 6, 3, 3]);
    for (walked, &(column, row)) in passed.tiles.iter().enumerate() {
        for y in 0..SIDE {
            for x in 0..SIDE {
                let at = (column * SIDE + x, row * SIDE + y);
                let under = (-3..3).contains(&at.0) && (-2..1).contains(&at.1);
                let wanted = if under { rgba(1, 2, 3, 255) } else { ink };
                let put = out[walked * TEXELS + (y * SIDE + x) as usize];
                assert_eq!(put, wanted, "({}, {})", at.0, at.1);
            }
        }
    }
}

// ---- Pages and refusals ----

/// The cuts the passes below take: pages a pass and tiles a pass.
pub(super) const CUTS: [(usize, usize); 5] = [(1, 6), (2, 6), (3, 1), (3, 2), (1, 1)];

/// The hashed cel on one page, in one pass of all its tiles: what the
/// cuts are held against, not against each other — a cut that binds every
/// tile's page wrong is wrong in every cut alike (브러시/렌더링's u06).
fn in_one_pass(mask: Option<&Mask>, verb: &Verb) -> (Passed, Vec<u32>) {
    under(&hashed_cel_on(|_| 0), mask, verb, Some((1, 6))).expect("one pass")
}

/// The hashed cel on tiles spread over three pages, cut into passes by
/// its pages and by its tiles: 2치화 puts what it puts on one page in one
/// pass — each pass binding its own new pixels, its runs from where a
/// binding may start, and its tiles' starts —, and so does 색 변환 under a
/// mask over both rows of tiles, each pass given its own rows of it.
#[test]
fn a_cel_cut_into_passes_puts_what_one_pass_puts() {
    let cel = hashed_cel();
    let cut = Verb {
        threshold: 100,
        incoming: Incoming::Value(&[255]),
        ..clear()
    };
    let (whole, out) = in_one_pass(None, &cut);
    assert!(whole.tiles.len() == 5 && whole.runs.iter().all(|runs| runs.len() > 100));
    let mask = masked((-200, -60), (300, 150), |x, y| (x * 7 + y * 3) as u8);
    let (whole_under, out_under) = in_one_pass(Some(&mask.mask()), &recolour(&[1, 2, 3]));
    assert_eq!(whole_under.tiles.len(), 5);
    for cut_by in CUTS {
        let (cut_up, cut_out) = run(&cel, &cut, Some(cut_by)).expect("cut up");
        assert_eq!(cut_up.runs, whole.runs, "{cut_by:?}");
        assert!(cut_out == out, "{cut_by:?}");
        let verb = recolour(&[1, 2, 3]);
        let (under_up, under_out) = under(&cel, Some(&mask.mask()), &verb, Some(cut_by))
            .expect("cut up under the mask");
        assert_eq!(under_up.runs, whole_under.runs, "{cut_by:?} under the mask");
        assert!(under_out == out_under, "{cut_by:?} under the mask");
    }
}

/// 2치화 over the hashed cel undone by its runs laid flat, cut into passes
/// by its pages and its tiles: each pass reads its own pixels' part of the
/// recipe, and every pixel is back as the cel held it.
#[test]
fn an_undo_cut_into_passes_reads_each_pass_its_part_of_the_recipe() {
    let cut = Verb {
        threshold: 100,
        incoming: Incoming::Value(&[255]),
        ..clear()
    };
    let (passed, out) = in_one_pass(None, &cut);
    let recipe: Vec<u8> = passed
        .runs
        .iter()
        .flatten()
        .flat_map(|&(value, length)| std::iter::repeat_n(value as u8, length as usize))
        .collect();
    let count = recipe.len() as u64;
    let undo = Verb {
        incoming: Incoming::Recipe {
            bytes: &recipe,
            step: 1,
            count,
        },
        ..clear()
    };
    let cut_cel = after(&passed, &out);
    for cut_by in CUTS {
        let (undone, back) = run(&cut_cel, &undo, Some(cut_by)).expect("undo");
        assert_eq!(undone.tiles, passed.tiles, "{cut_by:?}");
        for (walked, &(column, row)) in undone.tiles.iter().enumerate() {
            for y in 0..SIDE {
                for x in 0..SIDE {
                    let at = (column * SIDE + x, row * SIDE + y);
                    let put = back[walked * TEXELS + (y * SIDE + x) as usize];
                    assert_eq!(put, hashed(at.0, at.1), "{cut_by:?} at {at:?}");
                }
            }
        }
    }
}

/// The hashed cel's pixel at (x, y): a quarter empty with a colour under
/// it, a quarter of one of four colours.
pub(super) fn hashed(x: i32, y: i32) -> u32 {
    let h = mix(x as u32 ^ mix(y as u32 ^ 0x5eed));
    let colour = match h & 3 {
        0 => [rgb(10, 20, 30), rgb(200, 10, 10), rgb(12, 18, 33), rgb(90, 90, 90)]
            [(h >> 2 & 3) as usize],
        _ => mix(h) & 0x00ff_ffff,
    };
    let alpha = match h >> 4 & 3 {
        0 => 0,
        1 => 255,
        _ => h >> 24,
    };
    colour | alpha << 24
}

/// Six tiles from (-2, -1) of `hashed` pixels, (0, 0) missing, on pages by
/// column.
pub(super) fn hashed_cel() -> Cel {
    hashed_cel_on(|column| column.rem_euclid(3) as u16)
}

/// The hashed cel, each tile on the page `page` gives its column.
pub(super) fn hashed_cel_on(page: impl Fn(i32) -> u16) -> Cel {
    cel((-2, -1), (3, 2), hashed, move |column, row| {
        ((column, row) != (0, 0)).then_some(page(column))
    })
}

#[test]
fn a_verb_the_pass_cannot_read_is_refused() {
    let ink = one(&[((0, 0), INK | 255 << 24)]);
    let channel = |bytes, base, stride| Verb {
        channel: Channel {
            bytes,
            base,
            stride,
            takes_empty: false,
        },
        ..recolour(&[1, 2, 3])
    };
    for verb in [channel(0, 0, 1), channel(4, 0, 1), channel(3, 2, 1), channel(2, 3, 1)] {
        assert!(run(&ink, &verb, None).is_none(), "{:?}", verb.channel);
    }
    let alpha = Verb {
        incoming: Incoming::Value(&[0]),
        ..channel(1, 3, 0)
    };
    assert!(run(&ink, &alpha, None).is_some());
    assert!(run(&ink, &recolour(&[1, 2]), None).is_none());
    let past = Verb {
        threshold: 256,
        ..clear()
    };
    assert!(run(&ink, &past, None).is_none());
    let recipe = |threshold, bytes: &'static [u8]| Verb {
        threshold,
        incoming: Incoming::Recipe {
            bytes,
            step: 3,
            count: 3,
        },
        ..recolour(&[])
    };
    assert!(run(&ink, &recipe(1, &[0; 9]), None).is_none());
    assert!(run(&ink, &recipe(0, &[0; 8]), None).is_none());
    assert!(run(&ink, &recipe(0, &[0; 9]), None).is_some());
}

#[test]
fn a_cel_past_its_pool_or_its_size_is_refused() {
    let Rig { engine, pass } = rig();
    let ink = one(&[((0, 0), INK | 255 << 24)]);
    let pages = ink.pool.upload(engine);
    let verb = recolour(&[1, 2, 3]);
    assert!(pass.run(engine, &pages[..0], &ink.set, None, &verb).is_none());
    // Two columns of one row, holding one tile.
    let short = TileSet {
        x0: 0,
        y0: 0,
        columns: 2,
        rows: 1,
        tiles: ink.set.tiles.clone(),
    };
    assert!(pass.run(engine, &pages, &short, None, &verb).is_none());
    assert!(pass.run_by(engine, &pages, &ink.set, None, &verb, (0, 1)).is_none());
    assert!(pass.run_by(engine, &pages, &ink.set, None, &verb, (1, 0)).is_none());
}

/// A mask whose plane holds a word fewer than its box's rows is refused;
/// one that holds them is not.
#[test]
fn a_mask_past_its_plane_is_refused() {
    let ink = one(&[((0, 0), INK | 255 << 24)]);
    // 12 bytes for a box of 16.
    let narrow = masked((0, 0), (4, 3), |_, _| 255);
    let short = Mask {
        size: MaskBox { width: 5, height: 2 },
        ..narrow.mask()
    };
    assert!(under(&ink, Some(&short), &recolour(&[1, 2, 3]), None).is_none());
    let mask = masked((0, 0), (5, 2), |_, _| 255);
    assert!(under(&ink, Some(&mask.mask()), &recolour(&[1, 2, 3]), None).is_some());
}

/// The most tiles a pass takes fit a binding at their worst, and one more
/// would not unless a dispatch reaches no more: going forward a tile's
/// worst is its runs, a pixel's value and rank each.
#[test]
fn a_pass_takes_as_many_tiles_as_a_binding_holds_at_their_worst() {
    let engine = rig().engine;
    let limits = engine.device.limits();
    let room = u64::from(limits.max_storage_buffer_binding_size).min(limits.max_buffer_size);
    let reach = u64::from(limits.max_compute_workgroups_per_dimension);
    let runs = TEXELS as u64 * 8;
    let most = super::most(engine, None, &recolour(&[1, 2, 3])).expect("most") as u64;
    assert!(most * runs <= room, "{most} tiles of {runs} bytes in {room}");
    // What a pass is given besides its tiles is a few kilobytes.
    assert!(most == reach || (most + 1) * runs + 65536 > room, "{most} of {reach}");
}

/// The hashed cel's 2치화 cut a tile a pass: each pass binds its own runs,
/// from where a binding may start at or under its first — within an
/// alignment of it — to past its last.
#[test]
fn each_pass_binds_its_runs_from_where_a_binding_may_start() {
    let Rig { engine, .. } = rig();
    let cel = hashed_cel();
    let cut = Verb {
        threshold: 100,
        incoming: Incoming::Value(&[255]),
        ..clear()
    };
    let (passed, _) = run(&cel, &cut, Some((1, 1))).expect("run");
    let runs: Vec<u32> = passed.runs.iter().map(|runs| runs.len() as u32).collect();
    let starts = super::starts(&passed.touched, &runs);
    let walk = super::walk(&cel.set, 3, None).expect("walk");
    let passes = super::runs(walk.iter().map(|tile| Some(tile.at.page)), 1, 1);
    let align = super::alignment(engine);
    for (run, _) in &passes {
        let bound = super::bound_runs(engine, &starts, run);
        let (first, end) = (u64::from(starts[run.start].1) * 8, u64::from(starts[run.end].1) * 8);
        assert!(bound.start % align == 0 && bound.start <= first, "{run:?}: {bound:?}");
        assert!(first < bound.start + align && end <= bound.end, "{run:?}: {bound:?}");
    }
}

/// A mask's box that ends on a tile's edge, or starts on one, walks no tile
/// past it: over 2 × 2 tiles from (0, 0), a box from (0, 0) 128 across and
/// down walks tile (0, 0) alone, and one from (128, 128) tile (1, 1).
#[test]
fn a_box_on_a_tile_edge_walks_no_tile_past_it() {
    let ink = INK | 255 << 24;
    let cel = cel((0, 0), (2, 2), |_, _| ink, |_, _| Some(0));
    for (at, walked) in [((0, 0), (0, 0)), ((128, 128), (1, 1))] {
        let mask = masked(at, (128, 128), |_, _| 255);
        let verb = recolour(&[1, 2, 3]);
        let (passed, _) = under(&cel, Some(&mask.mask()), &verb, None).expect("run");
        assert_eq!(passed.tiles, [walked], "{at:?}");
    }
}

// ---- The ledger ----

/// The hashed cel through 색 변환, 색 삭제 within 40 of one of its colours,
/// and 2치화 at 100.
#[test]
fn every_device_puts_the_pinned_verbs() {
    let cel = hashed_cel();
    let key = tables([10, 20, 30], 40);
    let verbs = [
        recolour(&[1, 2, 3]),
        Verb {
            selector: Some(selector(&key, false)),
            ..clear()
        },
        Verb {
            threshold: 100,
            incoming: Incoming::Value(&[255]),
            ..clear()
        },
    ];
    let mut bytes = Vec::new();
    for verb in &verbs {
        let (passed, out) = run(&cel, verb, None).expect("run");
        let runs = passed.runs.iter().flatten().flat_map(|&(value, length)| [value, length]);
        bytes.extend(out.into_iter().chain(runs).flat_map(u32::to_le_bytes));
    }
    assert_pinned("cel_pixel/verbs", &bytes);
}

/// The hashed cel through 색 변환 and 픽셀 비우기 under a mask over parts of
/// five of its tiles, a quarter of its bytes 0, a quarter 255, the rest
/// hashed.
#[test]
fn every_device_puts_the_verbs_under_a_mask() {
    let cel = hashed_cel();
    let mask = masked((-200, -60), (300, 150), |x, y| {
        let h = mix(x as u32 ^ mix(y as u32 ^ 0xfea7));
        match h & 3 {
            0 => 0,
            1 => 255,
            _ => (h >> 8) as u8,
        }
    });
    let mut bytes = Vec::new();
    for verb in [recolour(&[1, 2, 3]), clear()] {
        let (passed, out) = under(&cel, Some(&mask.mask()), &verb, None).expect("run");
        assert_eq!(passed.tiles.len(), 5);
        let runs = passed.runs.iter().flatten().flat_map(|&(value, length)| [value, length]);
        bytes.extend(out.into_iter().chain(runs).flat_map(u32::to_le_bytes));
    }
    assert_pinned("cel_pixel/masked", &bytes);
}
