//! The row composite on a real GPU, checked against the ledger, against
//! itself cut into passes every way the device allows, and against what
//! the formulas give by hand — never against a CPU copy of them
//! (`kernels/mod.rs` has why).

use std::sync::OnceLock;

use super::{
    Batch, Budget, Composite, DEPTH, KeyChain, Laid, Step, TILE, TILE_TEXELS, TileAt, TileSet,
    check_depth, cut,
};
use crate::device::Engine;
use crate::kernels::effects::KeyRun;
use crate::kernels::shared::tests::{Picture, window};
use crate::kernels::shared::{ResampleMap, ResampleMode};
use crate::testing::{assert_pinned, first_engine, read_buffer};

const NORMAL: u32 = 28;
const MULTIPLY: u32 = 3;
const SCREEN: u32 = 6;
const OVERLAY: u32 = 8;
const DIFFERENCE: u32 = 11;
const LINEAR_BURN: u32 = 13;
const WHOLE: u32 = 65535;

struct Rig {
    engine: &'static Engine,
    composite: Composite,
}

/// One device and one compiled pass for every test here, as the app opens
/// one device (blend's tests have why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        let composite = Composite::new(engine).expect("compile the composite");
        Rig { engine, composite }
    })
}

// ---- Rows to composite ----

/// A well-mixed u32 (lowbias32), for pictures no formula here can predict.
fn mix(mut h: u32) -> u32 {
    h ^= h >> 16;
    h = h.wrapping_mul(0x7feb_352d);
    h ^= h >> 15;
    h = h.wrapping_mul(0x846c_a68b);
    h ^ (h >> 16)
}

/// Row `seed`'s stored pixel at its own (x, y): a quarter nothing, a
/// quarter opaque, the rest any alpha — and no colour where no alpha, as a
/// stored pixel never holds (blend_pack8).
fn texel(seed: u32, x: i32, y: i32) -> u32 {
    let h = mix(seed.wrapping_mul(0x9e37_79b9) ^ mix(x as u32 ^ mix(y as u32)));
    let alpha = match h & 3 {
        0 => 0,
        1 => 255,
        _ => (h >> 24) | 1,
    };
    if alpha == 0 {
        return 0;
    }
    (mix(h) & 0x00ff_ffff) | (alpha << 24)
}

/// The pool a test fills: pages of whole tiles.
#[derive(Default)]
struct Pool {
    pages: Vec<Vec<u32>>,
}

impl Pool {
    /// The tile at (`column`, `row`) of a row whose pixel at its own
    /// (x, y) is `pixel(x, y)`, stored on `page`.
    fn put(
        &mut self,
        page: u16,
        pixel: &impl Fn(i32, i32) -> u32,
        column: i32,
        row: i32,
    ) -> TileAt {
        while self.pages.len() <= usize::from(page) {
            self.pages.push(Vec::new());
        }
        let words = &mut self.pages[usize::from(page)];
        let slot = (words.len() as u64 / TILE_TEXELS) as u16;
        let side = TILE as i32;
        for y in 0..side {
            for x in 0..side {
                words.push(pixel(column * side + x, row * side + y));
            }
        }
        TileAt { page, slot }
    }

    /// Row `seed` ([`texel`]): the tiles of `columns` × `rows` from
    /// (`x0`, `y0`), each on the page `place` gives it, or none.
    fn set(
        &mut self,
        seed: u32,
        origin: (i32, i32),
        size: (u32, u32),
        place: impl Fn(i32, i32) -> Option<u16>,
    ) -> TileSet {
        self.drawn(move |x, y| texel(seed, x, y), origin, size, place)
    }

    /// [`Pool::set`] for a row whose pixels are `pixel`'s.
    fn drawn(
        &mut self,
        pixel: impl Fn(i32, i32) -> u32,
        (x0, y0): (i32, i32),
        (columns, rows): (u32, u32),
        place: impl Fn(i32, i32) -> Option<u16>,
    ) -> TileSet {
        let mut tiles = Vec::new();
        for row in y0..y0 + rows as i32 {
            for column in x0..x0 + columns as i32 {
                tiles.push(place(column, row).map(|page| self.put(page, &pixel, column, row)));
            }
        }
        TileSet {
            x0,
            y0,
            columns,
            rows,
            tiles,
        }
    }

    fn upload(&self, engine: &Engine) -> Vec<wgpu::Buffer> {
        use wgpu::util::DeviceExt;
        self.pages
            .iter()
            .map(|words| {
                let bytes: Vec<u8> = words.iter().flat_map(|word| word.to_le_bytes()).collect();
                engine
                    .device
                    .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                        label: Some("test page"),
                        contents: if bytes.is_empty() { &[0; 4] } else { &bytes },
                        usage: wgpu::BufferUsages::STORAGE,
                    })
            })
            .collect()
    }
}

/// Tile set `set` moved by (`dx`, `dy`) whole pixels.
fn row(set: usize, (dx, dy): (i32, i32), opacity: u32, mode: u32) -> Step {
    with_map(set, ResampleMap::moved(dx, dy), opacity, mode)
}

fn with_map(set: usize, map: ResampleMap, opacity: u32, mode: u32) -> Step {
    Step::Row {
        set,
        keys: None,
        map,
        opacity,
        mode,
    }
}

/// `row` keyed by chain `chain`.
fn keyed(row: Step, chain: usize) -> Step {
    let Step::Row {
        set,
        map,
        opacity,
        mode,
        ..
    } = row
    else {
        unreachable!("only a row is keyed");
    };
    Step::Row {
        set,
        keys: Some(chain),
        map,
        opacity,
        mode,
    }
}

/// A plan, what it lays and where it is looked at.
struct Scene {
    pool: Pool,
    sets: Vec<TileSet>,
    keys: Vec<KeyChain>,
    steps: Vec<Step>,
    tiles: Vec<(i32, i32)>,
}

/// Composites `scene` within `budget`; returns the output's bytes and how
/// many passes it took.
fn composite(scene: &Scene, budget: Budget) -> (Vec<u8>, usize) {
    let Rig { engine, composite } = rig();
    let pages = scene.pool.upload(engine);
    let done = composite
        .run(engine, &pages, &scene.sets, &scene.keys, &scene.steps, &scene.tiles, budget)
        .expect("composite");
    (read_buffer(engine, &done.out), done.passes)
}

fn widest(scene: &Scene) -> Vec<u8> {
    composite(scene, rig().composite.widest()).0
}

/// At most `pages` pages and `tiles` output tiles a pass.
fn within(pages: usize, tiles: usize) -> Budget {
    Budget {
        pages,
        tiles,
        levels: DEPTH,
    }
}

/// The output pixel at canvas (x, y): `bytes` is `tiles`' pixels, tile
/// after tile, rows of 128 in each.
fn pixel_at(bytes: &[u8], tiles: &[(i32, i32)], x: i32, y: i32) -> [u8; 4] {
    let side = TILE as i32;
    let tile = tiles
        .iter()
        .position(|&at| at == (x.div_euclid(side), y.div_euclid(side)))
        .expect("a pixel of an output tile");
    let texel = tile * TILE_TEXELS as usize
        + (y.rem_euclid(side) * side + x.rem_euclid(side)) as usize;
    bytes[texel * 4..texel * 4 + 4].try_into().unwrap()
}

// ---- Keys ----

const KEY_RED: [u32; 3] = [200, 30, 40];
const KEY_GREEN: [u32; 3] = [20, 220, 60];

fn rgb(colour: [u32; 3]) -> u32 {
    colour[0] | (colour[1] << 8) | (colour[2] << 16)
}

/// Maps a key could be handed: an erase reads its map at the alpha, a
/// restore at what the chain took.
fn nothing(_: u32) -> u32 {
    0
}
fn half(alpha: u32) -> u32 {
    alpha.div_ceil(2)
}

/// One run of one key, naming exactly `colour`: it erases by `map` — or,
/// `restore`, gives back by it.
fn key_run(colour: [u32; 3], restore: bool, map: fn(u32) -> u32) -> Vec<u32> {
    let table = |byte: u32| {
        let mut table = [0u32; 256];
        table[byte as usize] = 1;
        table
    };
    let maps: Vec<u8> = (0..256).map(|alpha| map(alpha) as u8).collect();
    KeyRun {
        red: &table(colour[0]),
        green: &table(colour[1]),
        blue: &table(colour[2]),
        restores: u32::from(restore),
        maps: &maps,
    }
    .words()
}

/// Row `seed`'s pixel, or — a third of the time — [`KEY_RED`] or
/// [`KEY_GREEN`] at its alpha (whole where it has none).
fn spotted(seed: u32, x: i32, y: i32) -> u32 {
    let pixel = texel(seed, x, y);
    let colour = match mix(seed ^ mix(x as u32 ^ mix(!y as u32))) % 6 {
        0 => KEY_RED,
        1 => KEY_GREEN,
        _ => return pixel,
    };
    rgb(colour) | ((pixel >> 24).max(1) << 24)
}

/// `pixel` as one erasing key naming exactly `colour` leaves it: its alpha
/// a by `map(a)`, unless it has none.
fn keyed_by_hand(pixel: u32, colour: [u32; 3], map: fn(u32) -> u32) -> u32 {
    if pixel & 0x00ff_ffff != rgb(colour) || pixel >> 24 == 0 {
        return pixel;
    }
    (pixel & 0x00ff_ffff) | (map(pixel >> 24) << 24)
}

// ---- The ledger's scenes ----

/// Three rows moved by whole pixels — one by a negative tile and a bit —
/// in three modes, one with a hole, over five output tiles.
fn rows() -> Scene {
    let mut pool = Pool::default();
    let sets = vec![
        pool.set(1, (-1, 0), (3, 2), |_, _| Some(0)),
        pool.set(2, (0, 0), (2, 2), |c, r| ((c, r) != (1, 0)).then_some(1)),
        pool.set(3, (1, 1), (1, 1), |_, _| Some(2)),
    ];
    Scene {
        pool,
        sets,
        keys: Vec::new(),
        steps: vec![
            row(0, (0, 0), WHOLE, NORMAL),
            row(1, (37, -50), 40000, MULTIPLY),
            row(2, (-129, 3), WHOLE, SCREEN),
        ],
        tiles: vec![(0, 0), (1, 0), (0, 1), (1, 1), (-1, 0)],
    }
}

/// A folder in a folder, each closed in a mode at a strength, a row whose
/// tiles lie on two pages, and a row after them.
fn folders() -> Scene {
    let mut pool = Pool::default();
    let sets = vec![
        pool.set(11, (0, 0), (2, 1), |_, _| Some(0)),
        pool.set(12, (0, 0), (2, 2), |c, _| Some(1 + c as u16)),
        pool.set(13, (0, 0), (1, 2), |_, _| Some(3)),
        pool.set(14, (1, 0), (1, 1), |_, _| Some(4)),
    ];
    Scene {
        pool,
        sets,
        keys: Vec::new(),
        steps: vec![
            Step::Open,
            row(0, (0, 0), WHOLE, NORMAL),
            Step::Open,
            row(1, (5, 7), 50000, NORMAL),
            row(2, (64, 0), WHOLE, OVERLAY),
            Step::Close {
                opacity: 30000,
                mode: MULTIPLY,
            },
            Step::Close {
                opacity: 50000,
                mode: NORMAL,
            },
            row(3, (-3, 100), WHOLE, LINEAR_BURN),
        ],
        tiles: vec![(0, 0), (1, 0), (0, 1), (1, 1)],
    }
}

/// A row under two clipping groups: one whose scope reads its base made
/// opaque, laid in screen at a strength; one plain.
fn clips() -> Scene {
    let mut pool = Pool::default();
    let sets = vec![
        pool.set(21, (0, 0), (2, 2), |_, _| Some(0)),
        pool.set(22, (0, 0), (2, 1), |_, _| Some(1)),
        pool.set(23, (0, 0), (2, 2), |_, _| Some(2)),
        pool.set(24, (0, 0), (1, 1), |_, _| Some(3)),
        pool.set(25, (1, 1), (1, 1), |_, _| Some(1)),
        pool.set(26, (0, 1), (2, 1), |_, _| Some(2)),
    ];
    Scene {
        pool,
        sets,
        keys: Vec::new(),
        steps: vec![
            row(0, (0, 0), WHOLE, NORMAL),
            Step::Open,
            row(1, (0, 0), WHOLE, NORMAL),
            Step::OpenOpaque,
            row(2, (10, 20), WHOLE, MULTIPLY),
            row(3, (0, 0), 50000, NORMAL),
            Step::CloseAtop,
            Step::Close {
                opacity: 45000,
                mode: SCREEN,
            },
            Step::Open,
            row(4, (0, 0), WHOLE, NORMAL),
            Step::Open,
            row(5, (0, 0), 60000, NORMAL),
            Step::CloseAtop,
            Step::Close {
                opacity: WHOLE,
                mode: NORMAL,
            },
        ],
        tiles: vec![(0, 0), (1, 0), (0, 1), (1, 1)],
    }
}

/// A folder over six pages and a row on a seventh — the plan a small
/// device must cut inside the folder (관제 13:2x: a folder that spans pages
/// is among the cases).
fn spanning() -> Scene {
    let modes = [NORMAL, MULTIPLY, SCREEN, OVERLAY, DIFFERENCE, LINEAR_BURN, NORMAL];
    let mut pool = Pool::default();
    let sets: Vec<TileSet> = (0..7u32)
        .map(|k| pool.set(31 + k, (0, 0), (2, 2), move |_, _| Some(k as u16)))
        .collect();
    let mut steps = vec![Step::Open];
    steps.extend((0..6usize).map(|k| {
        row(k, (13 * k as i32, -7 * k as i32), 65535 - 6000 * k as u32, modes[k])
    }));
    steps.push(Step::Close {
        opacity: 60000,
        mode: DIFFERENCE,
    });
    steps.push(row(6, (3, 3), WHOLE, modes[6]));
    Scene {
        pool,
        sets,
        keys: Vec::new(),
        steps,
        tiles: vec![(0, 0), (1, 0), (0, 1), (1, 1)],
    }
}

/// Poses R1 takes, canvas pixel to the row's own, over a canvas of two by
/// two tiles. No sin or cos: the spec's 대조 필요 ①.
fn pose(name: &str) -> ResampleMap {
    use ResampleMode::{Blend, Pick};
    let affine = |a, b, c, d, e, f| [a, b, c, d, e, f, 0.0, 0.0, 1.0];
    // 1.3 times larger, a 3-4-5 turn.
    let turn = affine(0.8 / 1.3, -0.6 / 1.3, 60.0, 0.6 / 1.3, 0.8 / 1.3, -20.0);
    // Twice smaller, the other turn.
    let shrink = affine(1.6, -1.2, 30.0, 1.2, 1.6, -90.0);
    let tilt = [1.1, -0.3, 14.0, 0.05, 1.2, 1.0, 0.002, -0.001, 1.0];
    let (inverse, floor, mode) = match name {
        "turn" => (turn, 1.0, Blend),
        "turn-pick" => (turn, 1.0, Pick),
        "shrink" => (shrink, 1.0, Blend),
        "shrink-pick" => (shrink, 1.0, Pick),
        // Axis-aligned: Pick's exact path.
        "squeeze" => (affine(1.7, 0.0, 3.3, 0.0, 1.7, -5.1), 1.0, Pick),
        "tilt" => (tilt, 1.0, Blend),
        "tilt-pick" => (tilt, 1.0, Pick),
        // A 16 px tent half a pixel up and left.
        "blur" => (affine(1.0, 0.0, -0.5, 0.0, 1.0, -0.5), 16.0, Blend),
        _ => unreachable!("{name}"),
    };
    ResampleMap::new(inverse, floor, mode, 2 * TILE, 2 * TILE).expect("a map that lands")
}

/// Rows posed every way R1 takes among moved ones: in a folder, a turn in
/// multiply and an exact Pick in screen; in a clip whose base is moved, a
/// tilt in overlay over the base made opaque. Each posed row's tiles are
/// on one page, so it composites at one page a pass.
fn posed() -> Scene {
    let mut pool = Pool::default();
    let sets = vec![
        pool.set(61, (0, 0), (2, 2), |_, _| Some(0)),
        pool.set(62, (0, 0), (2, 2), |_, _| Some(1)),
        pool.set(63, (-1, 0), (3, 2), |_, _| Some(2)),
        pool.set(64, (0, 0), (2, 1), |_, _| Some(3)),
        pool.set(65, (0, 0), (2, 2), |_, _| Some(1)),
    ];
    Scene {
        pool,
        sets,
        keys: Vec::new(),
        steps: vec![
            row(0, (3, -2), WHOLE, NORMAL),
            Step::Open,
            pose_row(1, "turn", 50000, MULTIPLY),
            pose_row(2, "squeeze", WHOLE, SCREEN),
            Step::Close {
                opacity: 45000,
                mode: NORMAL,
            },
            Step::Open,
            row(3, (0, 10), WHOLE, NORMAL),
            Step::OpenOpaque,
            pose_row(4, "tilt", 60000, OVERLAY),
            Step::CloseAtop,
            Step::Close {
                opacity: WHOLE,
                mode: NORMAL,
            },
        ],
        tiles: vec![(0, 0), (1, 0), (0, 1), (1, 1)],
    }
}

fn pose_row(set: usize, name: &str, opacity: u32, mode: u32) -> Step {
    with_map(set, pose(name), opacity, mode)
}

/// Rows keyed before they are posed, over one with no keys: in a folder, a
/// moved row and a turn by one chain, and an exact Pick by a chain of two
/// runs — the first erases, the second gives back half of it. Each row's
/// tiles are on one page.
fn keyed_rows() -> Scene {
    let mut pool = Pool::default();
    let sets = vec![
        pool.drawn(|x, y| spotted(71, x, y), (0, 0), (2, 2), |_, _| Some(0)),
        pool.drawn(|x, y| spotted(72, x, y), (0, 0), (2, 2), |_, _| Some(1)),
        pool.drawn(|x, y| spotted(73, x, y), (-1, 0), (3, 2), |_, _| Some(2)),
    ];
    let keys = vec![
        KeyChain {
            runs: vec![key_run(KEY_RED, false, half)],
        },
        KeyChain {
            runs: vec![key_run(KEY_GREEN, false, nothing), key_run(KEY_GREEN, true, half)],
        },
    ];
    Scene {
        pool,
        sets,
        keys,
        steps: vec![
            row(0, (4, -6), WHOLE, NORMAL),
            Step::Open,
            keyed(row(0, (-9, 3), 50000, MULTIPLY), 0),
            keyed(pose_row(1, "turn", WHOLE, SCREEN), 0),
            keyed(pose_row(2, "squeeze", 60000, NORMAL), 1),
            Step::Close {
                opacity: 45000,
                mode: NORMAL,
            },
        ],
        tiles: vec![(0, 0), (1, 0), (0, 1), (1, 1)],
    }
}

/// Buffers nested twelve deep, past what a pass holds: going in, a row at
/// every depth in its own mode, every third buffer a clip's scope over the
/// one it opens on; a posed row at the bottom; coming out, each closed at
/// its own strength and mode, and rows laid on the way out too.
fn deep() -> Scene {
    let modes = [NORMAL, MULTIPLY, SCREEN, OVERLAY, DIFFERENCE, LINEAR_BURN];
    let mut pool = Pool::default();
    let sets: Vec<TileSet> = (0..6u32)
        .map(|n| pool.set(91 + n, (0, 0), (2, 2), |_, _| Some((n % 3) as u16)))
        .collect();
    let mut steps = Vec::new();
    let mut opened = Vec::new();
    for d in 0..12usize {
        let shift = (d as i32 * 7 - 30, 11 - d as i32 * 5);
        steps.push(row(d % 6, shift, 30000 + d as u32 * 3000, modes[d % 6]));
        let clip = d % 3 == 2;
        steps.push(if clip { Step::OpenOpaque } else { Step::Open });
        opened.push(clip);
    }
    steps.push(pose_row(5, "turn", WHOLE, NORMAL));
    for d in (0..12usize).rev() {
        steps.push(if opened[d] {
            Step::CloseAtop
        } else {
            Step::Close {
                opacity: 65535 - d as u32 * 2500,
                mode: modes[(d + 3) % 6],
            }
        });
        if d % 4 == 1 {
            steps.push(row((d + 2) % 6, (d as i32 - 6, d as i32 * 3), 50000, modes[(d + 1) % 6]));
        }
    }
    Scene {
        pool,
        sets,
        keys: Vec::new(),
        steps,
        tiles: vec![(0, 0), (1, 0), (0, 1), (1, 1)],
    }
}

fn scenes() -> [(&'static str, Scene); 7] {
    [
        ("rows", rows()),
        ("folders", folders()),
        ("clips", clips()),
        ("spanning", spanning()),
        ("posed", posed()),
        ("keyed", keyed_rows()),
        ("deep", deep()),
    ]
}

#[test]
fn every_device_composites_the_pinned_scenes() {
    for (name, scene) in scenes() {
        assert_pinned(&format!("composite/{name}"), &widest(&scene));
    }
}

// 관제 (gpu-canonical-store 13:2x): cut into passes any way the device's
// pages allow, a plan composites to the bytes it does in one — the stack
// between passes is kept as it was, 16 bits a channel. So it does held a
// few levels at a time, down to the two a close needs.
#[test]
fn a_plan_cut_into_passes_composites_as_in_one() {
    let most = rig().composite.widest().pages;
    for (name, scene) in scenes() {
        let (whole, passes) = composite(&scene, rig().composite.widest());
        if name == "deep" {
            assert!(passes > 1, "a tree past what a pass holds was never cut");
        }
        for pages in 1..most {
            let (cut, passes) = composite(&scene, within(pages, usize::MAX));
            assert!(cut == whole, "{name} at {pages} pages a pass");
            if name == "spanning" && pages == 1 {
                assert!(passes > 1, "the folder was never cut");
            }
        }
        for levels in 2..DEPTH {
            for pages in [1, most] {
                let budget = Budget {
                    levels,
                    ..within(pages, usize::MAX)
                };
                let (cut, _) = composite(&scene, budget);
                assert!(cut == whole, "{name} at {levels} levels and {pages} pages a pass");
            }
        }
    }
}

// The same where a binding holds fewer output tiles than the scene has:
// each run of tiles composites by itself, the last one short, and lands in
// its place among the others — with the stack kept between passes or not.
#[test]
fn output_tiles_taken_a_few_at_a_time_composite_as_all_at_once() {
    let most = rig().composite.widest().pages;
    for (name, scene) in scenes() {
        let whole = widest(&scene);
        for (pages, tiles) in [(most, 1), (most, 3), (1, 1), (1, 3)] {
            let (cut, passes) = composite(&scene, within(pages, tiles));
            assert!(cut == whole, "{name} at {pages} pages and {tiles} tiles a pass");
            let runs = scene.tiles.len().div_ceil(tiles);
            assert!(passes >= runs, "{name}: {passes} passes for {runs} runs of tiles");
        }
    }
}

// ---- By hand ----

fn bytes_of(texel: u32) -> [u8; 4] {
    texel.to_le_bytes()
}

// Over nothing a row lands its own colour at its own alpha — the weights
// sum to the alpha out — so a row alone, whole and normal, is its stored
// pixels moved, holes and all.
#[test]
fn a_row_alone_is_its_own_pixels_moved() {
    let mut pool = Pool::default();
    let sets = vec![pool.set(41, (-1, -1), (3, 3), |c, r| {
        ((c, r) != (0, 0)).then_some((c + 1) as u16 % 2)
    })];
    let (dx, dy) = (45, -77);
    let scene = Scene {
        pool,
        sets,
        keys: Vec::new(),
        steps: vec![row(0, (dx, dy), WHOLE, NORMAL)],
        tiles: vec![(0, 0), (1, 0), (0, 1), (-1, -1)],
    };
    let out = widest(&scene);
    let side = TILE as i32;
    for &(column, tile_row) in &scene.tiles {
        for y in tile_row * side..(tile_row + 1) * side {
            for x in column * side..(column + 1) * side {
                let (sx, sy) = (x - dx, y - dy);
                let tile = scene.sets[0].at(sx.div_euclid(side), sy.div_euclid(side));
                let want = tile.map_or(0, |_| texel(41, sx, sy));
                assert_eq!(pixel_at(&out, &scene.tiles, x, y), bytes_of(want), "({x}, {y})");
            }
        }
    }
}

// A row at no strength lays nothing, in any mode.
#[test]
fn a_row_at_no_strength_lays_nothing() {
    for mode in [NORMAL, MULTIPLY, SCREEN] {
        let mut pool = Pool::default();
        let sets = vec![pool.set(42, (0, 0), (1, 1), |_, _| Some(0))];
        let scene = Scene {
            pool,
            sets,
            keys: Vec::new(),
            steps: vec![row(0, (0, 0), 0, mode)],
            tiles: vec![(0, 0)],
        };
        assert!(widest(&scene).iter().all(|&byte| byte == 0), "mode {mode}");
    }
}

// A folder of one row, closed whole and normal, is that row.
#[test]
fn a_folder_of_one_row_is_that_row() {
    let scene = |steps: Vec<Step>| {
        let mut pool = Pool::default();
        let sets = vec![pool.set(43, (0, 0), (2, 1), |_, _| Some(0))];
        Scene {
            pool,
            sets,
            keys: Vec::new(),
            steps,
            tiles: vec![(0, 0), (1, 0)],
        }
    };
    let alone = widest(&scene(vec![row(0, (9, 9), 40000, NORMAL)]));
    let folded = widest(&scene(vec![
        Step::Open,
        row(0, (9, 9), 40000, NORMAL),
        Step::Close {
            opacity: WHOLE,
            mode: NORMAL,
        },
    ]));
    assert!(alone == folded);
}

// Twelve folders around one row, each closed whole and normal, are that
// row — however few stack levels a pass holds.
#[test]
fn folders_nested_past_what_a_pass_holds_are_their_row() {
    let scene = |steps: Vec<Step>| {
        let mut pool = Pool::default();
        let sets = vec![pool.set(44, (0, 0), (2, 1), |_, _| Some(0))];
        Scene {
            pool,
            sets,
            keys: Vec::new(),
            steps,
            tiles: vec![(0, 0), (1, 0)],
        }
    };
    let a_row = row(0, (9, 9), 40000, NORMAL);
    let close = Step::Close {
        opacity: WHOLE,
        mode: NORMAL,
    };
    let alone = widest(&scene(vec![a_row]));
    let nested: Vec<Step> = (0..12)
        .map(|_| Step::Open)
        .chain([a_row])
        .chain((0..12).map(|_| close))
        .collect();
    for levels in [2, 3, DEPTH] {
        let budget = Budget {
            levels,
            ..rig().composite.widest()
        };
        assert!(composite(&scene(nested.clone()), budget).0 == alone, "{levels} levels");
    }
}

/// A base: nothing on the left half of every tile, a grey of byte 128 at
/// `alpha` on the right.
fn half_base(alpha: u32) -> impl Fn(i32, i32) -> u32 {
    move |x, _| {
        if x.rem_euclid(TILE as i32) < 64 {
            0
        } else {
            (alpha << 24) | 0x0080_8080
        }
    }
}

/// A clipping group of `clipped` (opaque, everywhere) on [`half_base`],
/// its scope opened by `open`.
fn clip(base_alpha: u32, clipped: u32, mode: u32, open: Step) -> Vec<u8> {
    let mut pool = Pool::default();
    let sets = vec![
        pool.drawn(half_base(base_alpha), (0, 0), (1, 1), |_, _| Some(0)),
        pool.drawn(move |_, _| clipped, (0, 0), (1, 1), |_, _| Some(1)),
    ];
    widest(&Scene {
        pool,
        sets,
        keys: Vec::new(),
        steps: vec![
            Step::Open,
            row(0, (0, 0), WHOLE, NORMAL),
            open,
            row(1, (0, 0), WHOLE, mode),
            Step::CloseAtop,
            Step::Close {
                opacity: WHOLE,
                mode: NORMAL,
            },
        ],
        tiles: vec![(0, 0)],
    })
}

// What clips to a base shows only where the base is, at the base's alpha:
// opaque red on the opaque half, nothing on the empty one.
#[test]
fn a_clip_shows_its_rows_only_where_its_base_is() {
    let out = clip(255, 0xff00_00ff, NORMAL, Step::Open);
    assert_eq!(pixel_at(&out, &[(0, 0)], 10, 50), [0, 0, 0, 0]);
    assert_eq!(pixel_at(&out, &[(0, 0)], 100, 50), [255, 0, 0, 255]);
}

// White multiplied onto a half-there grey base: over the base made opaque
// it multiplies the grey (B = 32896), and srcATop gives it the base's
// alpha; opened plainly it multiplies nothing and lands white. Where the
// base is not, both are nothing.
#[test]
fn a_clipped_multiply_reads_the_base_made_opaque() {
    let read = clip(128, 0xffff_ffff, MULTIPLY, Step::OpenOpaque);
    let plain = clip(128, 0xffff_ffff, MULTIPLY, Step::Open);
    assert_eq!(pixel_at(&read, &[(0, 0)], 100, 1), [128, 128, 128, 128]);
    assert_eq!(pixel_at(&plain, &[(0, 0)], 100, 1), [255, 255, 255, 128]);
    assert_eq!(pixel_at(&read, &[(0, 0)], 1, 1), [0, 0, 0, 0]);
    assert_eq!(pixel_at(&plain, &[(0, 0)], 1, 1), [0, 0, 0, 0]);
}

/// `pixel` over `size` from canvas (0, 0), as R1's own harness takes a
/// source: nothing past it, as nothing is past a tile set.
fn picture_of(pixel: impl Fn(i32, i32) -> u32, (width, height): (u32, u32)) -> Picture {
    let mut picture = Picture::filled(width, height, 0);
    for y in 0..height {
        for x in 0..width {
            picture.put(x, y, pixel(x as i32, y as i32));
        }
    }
    picture
}

/// What R1's harness resamples over output `tiles`, as the executor lays
/// them out — what a row alone, whole and normal, must lay.
fn resampled(map: &ResampleMap, picture: &Picture, tiles: &[(i32, i32)]) -> Vec<u8> {
    let side = TILE as i32;
    tiles
        .iter()
        .flat_map(|&(column, row)| window(map, picture, (TILE, TILE), (column * side, row * side)))
        .flat_map(u32::to_le_bytes)
        .collect()
}

// A row in any pose lays what R1 resamples: the executor's one sample is
// R1's own, reading the row through its tile map, every tile here on a
// page of its own — out to output tiles the row does not reach.
#[test]
fn a_posed_row_lays_what_r1_resamples() {
    let picture = picture_of(|x, y| texel(51, x, y), (2 * TILE, 2 * TILE));
    let tiles = vec![(0, 0), (1, 0), (0, 1), (1, 1), (-1, 0), (2, 1)];
    let names = [
        "turn",
        "turn-pick",
        "shrink",
        "shrink-pick",
        "squeeze",
        "tilt",
        "tilt-pick",
        "blur",
    ];
    for name in names {
        let mut pool = Pool::default();
        let sets = vec![pool.set(51, (0, 0), (2, 2), |c, r| Some((r * 2 + c) as u16))];
        let scene = Scene {
            pool,
            sets,
            keys: Vec::new(),
            steps: vec![pose_row(0, name, WHOLE, NORMAL)],
            tiles: tiles.clone(),
        };
        assert!(widest(&scene) == resampled(&pose(name), &picture, &tiles), "{name}");
    }
}

// A row binds the pages its pixels can read and no more. Four tiles in a
// strip, each on a page of its own, under the first output tile:
// - moved left two tiles, it shows the third — one page;
// - under a 16 px tent half a pixel left, the second is read up to 15 px in,
//   past where the output tile's corners land, the rest not at all — two
//   pages, and a pass of one cannot take the row;
// - ten times larger from x = 100 with the same tent, the corners land by
//   112.8 and the tent reaches 128, one pixel into the second.
#[test]
fn a_row_binds_the_pages_its_pixels_read() {
    let picture = picture_of(|x, y| texel(52, x, y), (4 * TILE, TILE));
    let strip = |map: ResampleMap| {
        let mut pool = Pool::default();
        let sets = vec![pool.set(52, (0, 0), (4, 1), |c, _| Some(c as u16))];
        Scene {
            pool,
            sets,
            keys: Vec::new(),
            steps: vec![with_map(0, map, WHOLE, NORMAL)],
            tiles: vec![(0, 0)],
        }
    };
    let magnify = [0.1, 0.0, 100.0, 0.0, 0.1, 50.0, 0.0, 0.0, 1.0];
    let cases = [
        (ResampleMap::moved(-2 * TILE as i32, 0), 1),
        (pose("blur"), 2),
        (ResampleMap::new(magnify, 16.0, ResampleMode::Blend, TILE, TILE).unwrap(), 2),
    ];
    for (n, (map, pages)) in cases.into_iter().enumerate() {
        let scene = strip(map);
        let (out, passes) = composite(&scene, within(pages, usize::MAX));
        assert!(out == resampled(&map, &picture, &scene.tiles), "{n}");
        assert_eq!(passes, 1, "{n}");
        if pages > 1 {
            let Rig { engine, composite } = rig();
            let pool = scene.pool.upload(engine);
            let fewer = within(pages - 1, usize::MAX);
            let run = composite.run(engine, &pool, &scene.sets, &[], &scene.steps, &scene.tiles, fewer);
            assert!(run.is_none(), "{n}");
        }
    }
}

// A row's keys run on its stored pixels, before R1 poses them (캔버스
// 베이스, gpu-canonical-store 11-05 18:24): in any pose, a keyed row lays
// what R1 resamples from the picture keyed by hand.
#[test]
fn a_row_is_keyed_before_its_pose() {
    let picture = picture_of(|x, y| spotted(53, x, y), (2 * TILE, 2 * TILE));
    let keyed_picture = Picture {
        pixels: picture
            .pixels
            .iter()
            .map(|&pixel| keyed_by_hand(pixel, KEY_RED, half))
            .collect(),
        ..picture
    };
    let tiles = vec![(0, 0), (1, 0), (0, 1), (1, 1)];
    for name in ["move", "turn", "turn-pick", "shrink", "squeeze", "tilt", "blur"] {
        let map = match name {
            "move" => ResampleMap::moved(17, -5),
            _ => pose(name),
        };
        let mut pool = Pool::default();
        let sets = vec![pool.drawn(|x, y| spotted(53, x, y), (0, 0), (2, 2), |c, r| {
            Some((r * 2 + c) as u16)
        })];
        let scene = Scene {
            pool,
            sets,
            keys: vec![KeyChain {
                runs: vec![key_run(KEY_RED, false, half)],
            }],
            steps: vec![keyed(with_map(0, map, WHOLE, NORMAL), 0)],
            tiles: tiles.clone(),
        };
        assert!(widest(&scene) == resampled(&map, &keyed_picture, &tiles), "{name}");
    }
}

// Each run of a chain goes in its order, against the alpha the row stored,
// not what the runs before it left: erased to nothing and given back whole
// is the stored alpha; given back first, there is nothing yet to give, so
// the erase after it stands.
#[test]
fn every_run_of_a_chain_keys_against_the_stored_alpha() {
    let stored = rgb(KEY_RED) | (200 << 24);
    let chains = [
        (vec![key_run(KEY_RED, false, nothing), key_run(KEY_RED, true, nothing)], 200),
        (vec![key_run(KEY_RED, false, half), key_run(KEY_RED, true, half)], 150),
        (vec![key_run(KEY_RED, true, nothing), key_run(KEY_RED, false, half)], 100),
        (vec![key_run(KEY_RED, false, half), key_run(KEY_RED, false, half)], 50),
    ];
    for (n, (runs, alpha)) in chains.into_iter().enumerate() {
        let mut pool = Pool::default();
        let sets = vec![pool.drawn(move |_, _| stored, (0, 0), (1, 1), |_, _| Some(0))];
        let scene = Scene {
            pool,
            sets,
            keys: vec![KeyChain { runs }],
            steps: vec![keyed(row(0, (0, 0), WHOLE, NORMAL), 0)],
            tiles: vec![(0, 0)],
        };
        let want = rgb(KEY_RED) | (alpha << 24);
        assert_eq!(pixel_at(&widest(&scene), &[(0, 0)], 7, 9), bytes_of(want), "chain {n}");
    }
}

// Each row reads its own chain, and a row with none is not keyed: three
// rows of the same two colours side by side, one erasing red, one green,
// one neither.
#[test]
fn each_row_is_keyed_by_its_own_chain() {
    let red = rgb(KEY_RED) | (0xff << 24);
    let green = rgb(KEY_GREEN) | (0xff << 24);
    let mut pool = Pool::default();
    let pixel = move |x: i32, _: i32| if x.rem_euclid(2) == 0 { red } else { green };
    let sets = vec![pool.drawn(pixel, (0, 0), (1, 1), |_, _| Some(0))];
    let erase = |colour| KeyChain {
        runs: vec![key_run(colour, false, nothing)],
    };
    let side = TILE as i32;
    let scene = Scene {
        pool,
        sets,
        keys: vec![erase(KEY_GREEN), erase(KEY_RED)],
        steps: vec![
            keyed(row(0, (0, 0), WHOLE, NORMAL), 1),
            keyed(row(0, (side, 0), WHOLE, NORMAL), 0),
            row(0, (2 * side, 0), WHOLE, NORMAL),
        ],
        tiles: vec![(0, 0), (1, 0), (2, 0)],
    };
    let out = widest(&scene);
    let at = |column: i32, x: i32| pixel_at(&out, &scene.tiles, column * side + x, 3);
    let none = [0, 0, 0, 0];
    assert_eq!([at(0, 0), at(0, 1)], [none, bytes_of(green)]);
    assert_eq!([at(1, 0), at(1, 1)], [bytes_of(red), none]);
    assert_eq!([at(2, 0), at(2, 1)], [bytes_of(red), bytes_of(green)]);
}

// ---- The plan ----

#[test]
fn a_plan_must_close_what_it_opens_and_name_its_rows() {
    let close = Step::Close {
        opacity: WHOLE,
        mode: NORMAL,
    };
    assert!(check_depth(&[Step::Open, row(0, (0, 0), WHOLE, NORMAL), close], 1, 0).is_some());
    assert!(check_depth(&[Step::Open], 1, 0).is_none());
    assert!(check_depth(&[close], 1, 0).is_none());
    assert!(check_depth(&[Step::CloseAtop], 1, 0).is_none());
    assert!(check_depth(&[row(1, (0, 0), WHOLE, NORMAL)], 1, 0).is_none());
    let keyed_by_the_second = keyed(row(0, (0, 0), WHOLE, NORMAL), 1);
    assert!(check_depth(&[keyed_by_the_second], 1, 2).is_some());
    assert!(check_depth(&[keyed_by_the_second], 1, 1).is_none());
    // Past what a pass holds is a plan like any other: it is cut there.
    let deeper: Vec<Step> = (0..DEPTH)
        .map(|_| Step::OpenOpaque)
        .chain((0..DEPTH).map(|_| close))
        .collect();
    assert!(check_depth(&deeper, 0, 0).is_some());
}

// Pages 0, 1 | 2, 0 | 3 at two a pass: a pass ends where a third page would
// be bound, and starts at the depth the last one left.
#[test]
fn a_plan_is_cut_where_a_pass_runs_out_of_pages() {
    let laid = |pages: &[u16], step: Step| Laid {
        step,
        pages: pages.to_vec(),
    };
    let a_row = row(0, (0, 0), WHOLE, NORMAL);
    let close = Step::Close {
        opacity: WHOLE,
        mode: NORMAL,
    };
    let plan = [
        laid(&[0], a_row),
        laid(&[], Step::Open),
        laid(&[1], a_row),
        laid(&[2], a_row),
        laid(&[], close),
        laid(&[0], a_row),
        laid(&[3], a_row),
    ];
    let shape = |batch: &Batch| {
        (
            batch.begin,
            batch.end,
            batch.depth_in,
            batch.depth_out,
            batch.pages.clone(),
        )
    };
    let batches: Vec<_> = cut(&plan, 2, DEPTH).expect("a cut").iter().map(shape).collect();
    assert_eq!(
        batches,
        [
            (0, 3, 0, 1, vec![0, 1]),
            (3, 6, 1, 0, vec![2, 0]),
            (6, 7, 0, 0, vec![3]),
        ]
    );
}

// Three buffers deep around a row: a pass ends where a step would open past
// the levels it holds or close onto one under its base, and the next holds
// the levels around the depth there. At three levels a pass the inside runs
// from level 1 and the last close from 0 again; at two, nearly every open
// and close takes a pass of its own.
#[test]
fn a_plan_is_cut_where_it_leaves_the_levels_a_pass_holds() {
    let laid = |step: Step| Laid {
        step,
        pages: Vec::new(),
    };
    let close = Step::Close {
        opacity: WHOLE,
        mode: NORMAL,
    };
    let plan = [
        laid(Step::Open),
        laid(Step::Open),
        laid(Step::OpenOpaque),
        laid(row(0, (0, 0), WHOLE, NORMAL)),
        laid(Step::CloseAtop),
        laid(close),
        laid(close),
    ];
    let shape = |batch: &Batch| (batch.begin, batch.end, batch.base, batch.depth_in, batch.depth_out);
    let at = |levels| -> Vec<_> { cut(&plan, 1, levels).expect("a cut").iter().map(shape).collect() };
    assert_eq!(at(3), [(0, 2, 0, 0, 2), (2, 6, 1, 2, 1), (6, 7, 0, 1, 0)]);
    assert_eq!(
        at(2),
        [
            (0, 1, 0, 0, 1),
            (1, 2, 1, 1, 2),
            (2, 5, 2, 2, 2),
            (5, 6, 1, 2, 1),
            (6, 7, 0, 1, 0),
        ]
    );
    assert_eq!(at(DEPTH), [(0, 7, 0, 0, 0)]);
}
