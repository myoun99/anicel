//! The row composite on a real GPU, checked against the ledger, against
//! itself cut into passes every way the device allows, and against what
//! the formulas give by hand — never against a CPU copy of them
//! (`kernels/mod.rs` has why).

use std::sync::OnceLock;

use super::{
    Batch, Budget, Compiled, Composite, DEPTH, KeyChain, Laid, Plan, Step, TILE, TILE_TEXELS,
    TileAt, TileSet, check_depth, cut,
};
use crate::device::Engine;
use crate::kernels::blend::mode::{DIFFERENCE, LINEAR_BURN, MULTIPLY, NORMAL, OVERLAY, SCREEN};
use crate::kernels::effects::KeyRun;
use crate::kernels::mask::tests::masked;
use crate::kernels::mask::{Mask, MaskBox};
use crate::kernels::shared::tests::{Picture, premultiplied, window};
use crate::kernels::shared::{ResampleMap, ResampleMode, ResampleModes};
use crate::testing::{assert_pinned, first_engine, read_buffer};

const WHOLE: u32 = 65535;
/// An output with no edge: every pixel of every output tile as it is.
const EVERYWHERE: [i32; 4] = [i32::MIN, i32::MIN, i32::MAX, i32::MAX];

struct Rig {
    engine: &'static Engine,
    composite: Composite,
}

impl Rig {
    fn new() -> Self {
        let engine = first_engine();
        let composite = Composite::new(engine).expect("compile the composite");
        Rig { engine, composite }
    }
}

/// One device and one compiled pass for every test here, as the app opens
/// one device (blend's tests have why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(Rig::new)
}

/// A composite of its own, on the one device, for the tests that wait for
/// the passes it compiles apart: its thread then has only theirs to get
/// through, where the shared rig's has every other test's plans.
fn apart() -> &'static Rig {
    static APART: OnceLock<Rig> = OnceLock::new();
    APART.get_or_init(Rig::new)
}

// ---- Rows to composite ----

/// A well-mixed u32 (lowbias32), for pictures no formula here can predict.
pub(crate) fn mix(mut h: u32) -> u32 {
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

/// The pool a test fills: pages of whole tiles — the cel pixel pass's tests
/// (kernels/cel_pixel) fill theirs with it too.
#[derive(Default)]
pub(crate) struct Pool {
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
    pub(crate) fn drawn(
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

    /// The pages, as the store keeps them: read in a pass, written by the
    /// write path's copies (kernels/write) and read back.
    pub(crate) fn upload(&self, engine: &Engine) -> Vec<wgpu::Buffer> {
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
                        usage: wgpu::BufferUsages::STORAGE
                            | wgpu::BufferUsages::COPY_DST
                            | wgpu::BufferUsages::COPY_SRC,
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
        masked: false,
    }
}

/// `row` keyed by chain `chain`.
fn keyed(row: Step, chain: usize) -> Step {
    let Step::Row {
        set,
        map,
        opacity,
        mode,
        masked,
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
        masked,
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

impl Scene {
    /// The scene's plan over `pages`, its pool uploaded.
    fn plan<'a>(&'a self, pages: &'a [wgpu::Buffer]) -> Plan<'a> {
        Plan {
            pages,
            sets: &self.sets,
            keys: &self.keys,
            steps: &self.steps,
            mask: None,
        }
    }
}

/// Composites `scene` within `budget`; returns the output's bytes and how
/// many passes it took.
fn composite(scene: &Scene, budget: Budget) -> (Vec<u8>, usize) {
    composite_on(rig(), scene, budget)
}

fn composite_on(rig: &Rig, scene: &Scene, budget: Budget) -> (Vec<u8>, usize) {
    let Rig { engine, composite } = rig;
    let pages = scene.pool.upload(engine);
    let done = composite
        .run(engine, &scene.plan(&pages), &scene.tiles, EVERYWHERE, budget)
        .expect("composite");
    (read_buffer(engine, &done.out), done.passes)
}

fn widest(scene: &Scene) -> Vec<u8> {
    widest_on(rig(), scene)
}

fn widest_on(rig: &Rig, scene: &Scene) -> Vec<u8> {
    composite_on(rig, scene, rig.composite.widest()).0
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
            let run = composite.run(engine, &scene.plan(&pool), &scene.tiles, EVERYWHERE, fewer);
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
        live: Vec::new(),
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
        live: Vec::new(),
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

// Up seven at four levels a pass, a pass per level past the third; down to
// two, back up to five, and down to nothing. Where closing leaves a pass,
// the next holds half its levels under the depth (2 to 5 at depth 4), so
// the walk back up to five stays in it — held from the bottom (1 to 4), it
// would take one pass more.
#[test]
fn a_pass_closing_out_of_its_levels_holds_the_depth_in_the_middle() {
    let close = Step::Close {
        opacity: WHOLE,
        mode: NORMAL,
    };
    let a_row = row(0, (0, 0), WHOLE, NORMAL);
    let steps: Vec<Step> = (0..7)
        .map(|_| Step::Open)
        .chain([a_row])
        .chain((0..5).map(|_| close))
        .chain((0..3).map(|_| Step::Open))
        .chain([a_row])
        .chain((0..5).map(|_| close))
        .collect();
    let plan: Vec<Laid> = steps
        .into_iter()
        .map(|step| Laid {
            step,
            pages: Vec::new(),
            live: Vec::new(),
        })
        .collect();
    let shape = |batch: &Batch| (batch.begin, batch.end, batch.base, batch.depth_in, batch.depth_out);
    let batches: Vec<_> = cut(&plan, 1, 4).expect("a cut").iter().map(shape).collect();
    assert_eq!(
        batches,
        [
            (0, 3, 0, 0, 3),
            (3, 4, 1, 3, 4),
            (4, 5, 2, 4, 5),
            (5, 6, 3, 5, 6),
            (6, 11, 4, 6, 4),
            (11, 20, 2, 4, 2),
            (20, 22, 0, 2, 0),
        ]
    );
}

// A pass holds two levels at least — a buffer and the one it closes onto —
// and no more than its registers.
#[test]
fn a_pass_holds_two_levels_to_depth() {
    let Rig { engine, composite } = rig();
    let mut pool = Pool::default();
    let sets = vec![pool.set(45, (0, 0), (1, 1), |_, _| Some(0))];
    let pages = pool.upload(engine);
    let steps = [row(0, (0, 0), WHOLE, NORMAL)];
    let plan = Plan {
        pages: &pages,
        sets: &sets,
        keys: &[],
        steps: &steps,
        mask: None,
    };
    let run = |levels| {
        let budget = Budget {
            levels,
            ..composite.widest()
        };
        composite.run(engine, &plan, &[(0, 0)], EVERYWHERE, budget).is_some()
    };
    assert_eq!([run(1), run(2), run(DEPTH), run(DEPTH + 1)], [false, true, true, false]);
}

// ---- The screen ----

/// The screen's canvas: 200 × 150 on a grid of 2 × 2 tiles, so its right
/// and bottom edges fall inside a tile, with rows drawn past them.
const CANVAS: [i32; 4] = [0, 0, 200, 150];
const SCREEN_SIZE: (u32, u32) = (300, 200);
const NO_TURN: (f64, f64) = (1.0, 0.0);

/// The canvas's plan: a row of noise under one at most strengths, moved
/// across and multiplied, both drawn on every pixel of every tile.
fn canvas_scene() -> Scene {
    let mut pool = Pool::default();
    let sets = vec![
        pool.set(61, (0, 0), (2, 2), |_, _| Some(0)),
        pool.set(62, (0, 0), (2, 2), |c, r| Some(1 + ((r * 2 + c) % 2) as u16)),
    ];
    Scene {
        pool,
        sets,
        keys: Vec::new(),
        steps: vec![row(0, (0, 0), WHOLE, NORMAL), row(1, (-30, 20), 40000, MULTIPLY)],
        tiles: vec![(0, 0), (1, 0), (0, 1), (1, 1)],
    }
}

/// The canvas composited, ending at its edge: the page it left, and its
/// pixels as R1's harness takes a source.
fn composited_canvas() -> (wgpu::Buffer, Picture) {
    let Rig { engine, composite } = rig();
    let scene = canvas_scene();
    let pages = scene.pool.upload(engine);
    let plan = scene.plan(&pages);
    let done = composite
        .run(engine, &plan, &scene.tiles, CANVAS, composite.widest())
        .expect("composite the canvas");
    let bytes = read_buffer(engine, &done.out);
    let word = |x, y| u32::from_le_bytes(pixel_at(&bytes, &scene.tiles, x, y));
    (done.out, picture_of(word, (2 * TILE, 2 * TILE)))
}

/// The canvas's composite as the screen's one tile set: slot i of its page
/// is its output tile i, row by row.
fn canvas_set() -> TileSet {
    TileSet {
        x0: 0,
        y0: 0,
        columns: 2,
        rows: 2,
        tiles: (0..4).map(|slot| Some(TileAt { page: 0, slot })).collect(),
    }
}

/// The camera's map, screen pixel to canvas pixel: the canvas `zoom` times
/// larger, turned by (cos, sin) — none, or a 3-4-5 or 5-12-13 turn, whose
/// entries IEEE alone rounds — mirrored left to right if `mirror`, its
/// origin at `pan` on the screen.
fn camera(
    zoom: f64,
    (cos, sin): (f64, f64),
    mirror: bool,
    (x, y): (f64, f64),
    mode: ResampleMode,
) -> ResampleMap {
    let flip = if mirror { -1.0 } else { 1.0 };
    let (a, b) = (flip * cos / zoom, flip * sin / zoom);
    let (d, e) = (-sin / zoom, cos / zoom);
    let inverse = [a, b, -(a * x + b * y), d, e, -(d * x + e * y), 0.0, 0.0, 1.0];
    ResampleMap::new(inverse, 1.0, mode, SCREEN_SIZE.0, SCREEN_SIZE.1).expect("a camera lands")
}

/// The screen tests' cameras, by ④ as canvas base set it (11-05 21:39):
/// Nearest at 100% and over — moved, turned twice as large, mirrored half
/// again as large — and Blend under it — halved off the pixel grid, turned
/// at under a third.
fn cameras() -> [(&'static str, ResampleMap); 5] {
    use ResampleMode::{Blend, Nearest};
    [
        ("moved", camera(1.0, NO_TURN, false, (37.0, -12.0), Nearest)),
        ("turned", camera(2.0, (0.8, 0.6), false, (150.0, 20.0), Nearest)),
        ("mirrored", camera(1.5, NO_TURN, true, (290.0, 10.0), Nearest)),
        ("halved", camera(0.5, NO_TURN, false, (100.25, 60.5), Blend)),
        ("spun", camera(0.3, (12.0 / 13.0, 5.0 / 13.0), false, (150.0, 30.0), Blend)),
    ]
}

/// A surface a test can fill first and read back.
fn surface((width, height): (u32, u32), format: wgpu::TextureFormat) -> wgpu::Texture {
    rig().engine.device.create_texture(&wgpu::TextureDescriptor {
        label: Some("test surface"),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format,
        usage: wgpu::TextureUsages::STORAGE_BINDING
            | wgpu::TextureUsages::COPY_SRC
            | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    })
}

/// The canvas's composite `page` shown through `map` on `texture`, inside
/// `rect`; the whole texture read back, row after row.
fn shown(
    page: &wgpu::Buffer,
    map: ResampleMap,
    texture: &wgpu::Texture,
    rect: [u32; 4],
) -> Vec<u8> {
    shown_on(rig(), page, map, texture, rect)
}

fn shown_on(
    rig: &Rig,
    page: &wgpu::Buffer,
    map: ResampleMap,
    texture: &wgpu::Texture,
    rect: [u32; 4],
) -> Vec<u8> {
    let Rig { engine, composite } = rig;
    let sets = [canvas_set()];
    let steps = [with_map(0, map, WHOLE, NORMAL)];
    let plan = Plan {
        pages: std::slice::from_ref(page),
        sets: &sets,
        keys: &[],
        steps: &steps,
        mask: None,
    };
    composite.show(engine, &plan, texture, rect, composite.widest()).expect("show");
    engine.read_texture(texture).expect("read the surface back")
}

fn whole_screen() -> [u32; 4] {
    [0, 0, SCREEN_SIZE.0, SCREEN_SIZE.1]
}

/// What the screen must hold through `map`: R1's harness over the canvas's
/// pixels, premultiplied by the GPU's one premultiply.
fn screen_by_r1(map: &ResampleMap, canvas: &Picture) -> Vec<u8> {
    let straight = window(map, canvas, SCREEN_SIZE, (0, 0));
    premultiplied(&straight).into_iter().flat_map(bytes_of).collect()
}

// The screen shows what R1 resamples of the canvas's composite, as the
// app's one premultiply leaves it: the executor's one row sample, reading
// the composite's own tiles as a page, put on a surface — at 100% as a
// whole-pixel copy, magnified turned and mirrored (Nearest), reduced (Blend);
// past the canvas's edges inside its tiles, nothing.
#[test]
fn the_screen_shows_what_r1_resamples_of_the_canvas() {
    let (page, canvas) = composited_canvas();
    assert!(cameras()[0].1.is_copy(), "100% moved is R1's copy");
    for (name, map) in cameras() {
        let texture = surface(SCREEN_SIZE, wgpu::TextureFormat::Rgba8Unorm);
        let screen = shown(&page, map, &texture, whole_screen());
        assert!(screen == screen_by_r1(&map, &canvas), "{name}");
    }
}

#[test]
fn every_device_shows_the_pinned_screens() {
    let (page, _) = composited_canvas();
    let screens: Vec<u8> = cameras()
        .into_iter()
        .flat_map(|(_, map)| {
            let texture = surface(SCREEN_SIZE, wgpu::TextureFormat::Rgba8Unorm);
            shown(&page, map, &texture, whole_screen())
        })
        .collect();
    assert_pinned("composite/screen", &screens);
}

// A canvas's picture ends at the canvas though its tiles reach on: past the
// extent its output tiles hold nothing, and inside, what they hold with no
// edge — on all four sides, the canvas set in from the top left too.
#[test]
fn an_output_holds_nothing_past_its_extent() {
    let Rig { engine, composite } = rig();
    let scene = canvas_scene();
    let pages = scene.pool.upload(engine);
    let plan = scene.plan(&pages);
    let run = |extent| {
        let done = composite.run(engine, &plan, &scene.tiles, extent, composite.widest());
        read_buffer(engine, &done.expect("composite").out)
    };
    let whole = run(EVERYWHERE);
    let ended = run([3, 5, 200, 150]);
    for y in 0..2 * TILE as i32 {
        for x in 0..2 * TILE as i32 {
            let inside = (3..200).contains(&x) && (5..150).contains(&y);
            let want = if inside { pixel_at(&whole, &scene.tiles, x, y) } else { [0; 4] };
            assert_eq!(pixel_at(&ended, &scene.tiles, x, y), want, "({x}, {y})");
        }
    }
}

// A surface is written inside the rectangle shown and nowhere else — an
// atlas's other panels stay as they were — and inside, as the surface
// shown whole holds it there. The rectangle crosses a tile's edge.
#[test]
fn a_surface_is_written_inside_its_rectangle_only() {
    let (page, _) = composited_canvas();
    let (width, height) = SCREEN_SIZE;
    let (_, turned) = cameras()[1];
    let rgba = wgpu::TextureFormat::Rgba8Unorm;
    let whole = shown(&page, turned, &surface(SCREEN_SIZE, rgba), whole_screen());
    let marked = surface(SCREEN_SIZE, rgba);
    let marker = [9u8, 99, 199, 249];
    rig().engine.queue.write_texture(
        marked.as_image_copy(),
        &marker.repeat((width * height) as usize),
        wgpu::TexelCopyBufferLayout {
            offset: 0,
            bytes_per_row: Some(width * 4),
            rows_per_image: Some(height),
        },
        marked.size(),
    );
    let rect = [37, 21, 167, 161];
    let part = shown(&page, turned, &marked, rect);
    for y in 0..height {
        for x in 0..width {
            let at = ((y * width + x) * 4) as usize;
            let inside = (rect[0]..rect[2]).contains(&x) && (rect[1]..rect[3]).contains(&y);
            let want = if inside { &whole[at..at + 4] } else { &marker[..] };
            assert_eq!(&part[at..at + 4], want, "({x}, {y})");
        }
    }
}

// Windows' surface is BGRA: the same pixels, red and blue swapped, byte for
// byte. A device that cannot store BGRA makes no BGRA surface either
// (platform::Surface), so there is nothing to show on it.
#[test]
fn a_bgra_surface_holds_the_rgba_pixels_red_and_blue_swapped() {
    if !rig().engine.device.features().contains(wgpu::Features::BGRA8UNORM_STORAGE) {
        return;
    }
    let (page, _) = composited_canvas();
    let on = |map, format| shown(&page, map, &surface(SCREEN_SIZE, format), whole_screen());
    for (name, map) in cameras() {
        let rgba = on(map, wgpu::TextureFormat::Rgba8Unorm);
        let bgra = on(map, wgpu::TextureFormat::Bgra8Unorm);
        let swapped: Vec<u8> =
            rgba.chunks_exact(4).flat_map(|p| [p[2], p[1], p[0], p[3]]).collect();
        assert!(bgra == swapped, "{name}");
    }
}

// Where the canvas is half clear the screen holds it premultiplied, as the
// app's own upload does: (200, 100, 50) at 128 is (100, 50, 25) — moved
// ten pixels in, its 100 × 100 and nothing round it.
#[test]
fn the_screen_holds_the_canvas_premultiplied() {
    let Rig { engine, composite } = rig();
    let mut pool = Pool::default();
    let sets = vec![pool.drawn(|_, _| 0x8032_64c8, (0, 0), (1, 1), |_, _| Some(0))];
    let scene = Scene {
        pool,
        sets,
        keys: Vec::new(),
        steps: vec![row(0, (0, 0), WHOLE, NORMAL)],
        tiles: vec![(0, 0)],
    };
    let pages = scene.pool.upload(engine);
    let plan = scene.plan(&pages);
    let canvas = composite.run(engine, &plan, &scene.tiles, [0, 0, 100, 100], composite.widest());
    let canvas = canvas.expect("composite the canvas");
    let sets = [TileSet {
        x0: 0,
        y0: 0,
        columns: 1,
        rows: 1,
        tiles: vec![Some(TileAt { page: 0, slot: 0 })],
    }];
    let steps = [row(0, (10, 10), WHOLE, NORMAL)];
    let screen = Plan {
        pages: std::slice::from_ref(&canvas.out),
        sets: &sets,
        keys: &[],
        steps: &steps,
        mask: None,
    };
    let texture = surface((TILE, TILE), wgpu::TextureFormat::Rgba8Unorm);
    let whole = [0, 0, TILE, TILE];
    composite.show(engine, &screen, &texture, whole, composite.widest()).expect("show");
    let read = engine.read_texture(&texture).expect("read the surface back");
    let at = |x: u32, y: u32| -> [u8; 4] {
        read[((y * TILE + x) * 4) as usize..][..4].try_into().unwrap()
    };
    for (x, y) in [(10, 10), (109, 10), (10, 109), (109, 109)] {
        assert_eq!(at(x, y), [100, 50, 25, 128], "({x}, {y})");
    }
    for (x, y) in [(9, 50), (110, 50), (50, 9), (50, 110)] {
        assert_eq!(at(x, y), [0; 4], "({x}, {y})");
    }
}

// A rectangle is shown only where it is one, on the surface; a surface only
// in a format a pass stores to.
#[test]
fn a_surface_is_shown_only_inside_it_and_in_its_formats() {
    let Rig { engine, composite } = rig();
    let (page, _) = composited_canvas();
    let sets = [canvas_set()];
    let steps = [row(0, (0, 0), WHOLE, NORMAL)];
    let plan = Plan {
        pages: std::slice::from_ref(&page),
        sets: &sets,
        keys: &[],
        steps: &steps,
        mask: None,
    };
    let texture = surface(SCREEN_SIZE, wgpu::TextureFormat::Rgba8Unorm);
    let show = |texture: &wgpu::Texture, rect| {
        composite.show(engine, &plan, texture, rect, composite.widest()).is_some()
    };
    let (width, height) = SCREEN_SIZE;
    assert!(show(&texture, [0, 0, width, height]));
    assert!(!show(&texture, [0, 0, width + 1, height]));
    assert!(!show(&texture, [0, 0, width, height + 1]));
    assert!(!show(&texture, [5, 0, 5, height]));
    assert!(!show(&texture, [0, 7, width, 7]));
    let wide = surface(SCREEN_SIZE, wgpu::TextureFormat::Rgba16Float);
    assert!(!show(&wide, [0, 0, width, height]));
}

// A pass is compiled the first time a plan needs its output, modes and
// levels, and kept: a screen shows every frame, and a compile is far
// dearer than a frame. Shown again while its own is compiling, a screen
// takes the full pass — one, too — and starts no second compile; once its
// own is made, that is the one it takes.
#[test]
fn a_pass_is_compiled_once_for_its_output_and_modes() {
    let (page, _) = composited_canvas();
    let (_, turned) = cameras()[1];
    for _ in 0..2 {
        let texture = surface(SCREEN_SIZE, wgpu::TextureFormat::Rgba8Unorm);
        shown_on(apart(), &page, turned, &texture, whole_screen());
    }
    apart().composite.settle();
    // A screen is one row: one level.
    let own = Compiled {
        surface: Some("rgba8unorm"),
        modes: ResampleModes::default().with(&turned.words()),
        levels: 1,
    };
    let taken = apart().composite.pass(apart().engine, own);
    let passes = apart().composite.passes.lock();
    let passes = passes.unwrap_or_else(std::sync::PoisonError::into_inner);
    for compiled in [own, Compiled::full(own.surface)] {
        assert_eq!(passes.asked.iter().filter(|(asked, _)| *asked == compiled).count(), 1);
    }
    assert_eq!(passes.made(own), Some(taken));
}

// A plan's pass compiled for its own R1 modes and stack levels, on a
// thread, composites what the full one does, which serves until it is
// made: once made, every pinned scene and screen comes out the same from
// it.
#[test]
fn a_pass_compiled_for_a_plan_composites_as_the_full_one() {
    let scenes = scenes();
    let (page, _) = composited_canvas();
    let screens = || -> Vec<u8> {
        let shown_by = |(_, map)| {
            let texture = surface(SCREEN_SIZE, wgpu::TextureFormat::Rgba8Unorm);
            shown_on(apart(), &page, map, &texture, whole_screen())
        };
        cameras().into_iter().flat_map(shown_by).collect()
    };
    scenes.iter().for_each(|(_, scene)| drop(widest_on(apart(), scene)));
    drop(screens());
    apart().composite.settle();
    for (name, scene) in &scenes {
        assert_pinned(&format!("composite/{name}"), &widest_on(apart(), scene));
    }
    assert_pinned("composite/screen", &screens());
    // The rows scene's maps are all copies and it opens no group: a pass
    // compiled for no mode, holding one level.
    let copies = Compiled { surface: None, modes: ResampleModes::default(), levels: 1 };
    let passes = apart().composite.passes.lock();
    let passes = passes.unwrap_or_else(std::sync::PoisonError::into_inner);
    assert!(passes.made(copies).is_some());
}

// ---- Where a row is live ----

/// The output tiles the liveness tests look at: three along the strip, one
/// far past it, one under it.
const LOOKED_AT: [(i32, i32); 5] = [(0, 0), (1, 0), (2, 0), (5, 0), (0, 1)];

/// The output tiles along a strip of four.
const STRIP: [(i32, i32); 4] = [(0, 0), (1, 0), (2, 0), (3, 0)];

/// Moved half a pixel, a pose other than a copy: a row reads its box
/// widened by 16 px.
fn half_a_pixel() -> ResampleMap {
    let half = [1.0, 0.0, 0.5, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
    ResampleMap::new(half, 1.0, ResampleMode::Blend, TILE, TILE).unwrap()
}

// A row is live on the output tiles where it reads a stored tile on its
// pages. A strip of four tiles, each on the page of its column:
// - moved two tiles left, a copy, it is a step a page: page 2 lays output
//   tile 0 alone, page 3 tile 1 alone, and nothing reaches tile 2 or past;
// - moved half a pixel, any other pose, it reads its box widened by 16 px:
//   every tile along the strip, the one under it by its top 16 px, and not
//   the one far past it.
#[test]
fn a_row_is_live_where_it_reads_a_stored_tile() {
    let mut pool = Pool::default();
    let sets = vec![pool.set(53, (0, 0), (4, 1), |c, _| Some(c as u16))];
    let live = |map: ResampleMap| {
        let steps = [with_map(0, map, WHOLE, NORMAL)];
        let laid = super::lay(&steps, &sets, &LOOKED_AT, 4, 4).expect("lay");
        laid.into_iter().map(|each| (each.pages, each.live)).collect::<Vec<_>>()
    };
    assert_eq!(
        live(ResampleMap::moved(-2 * TILE as i32, 0)),
        [
            (vec![2], vec![true, false, false, false, false]),
            (vec![3], vec![false, true, false, false, false]),
        ]
    );
    assert_eq!(live(half_a_pixel()), [(vec![0, 1, 2, 3], vec![true, true, true, false, true])]);
}

// A row in a pose other than a copy, reaching more pages than a pass binds,
// is laid a group of output tiles at a time, a tile's pages never parted.
// Moved half a pixel over the strip, output tile c reads the tiles either
// side of it: 0 and 1, 0 to 2, 1 to 3, 2 and 3. At three pages a pass the
// first two output tiles are one group and the last two another; at four,
// all are one.
#[test]
fn a_row_s_output_tiles_are_grouped_by_the_pages_a_pass_binds() {
    let mut pool = Pool::default();
    let sets = vec![pool.set(53, (0, 0), (4, 1), |c, _| Some(c as u16))];
    let steps = [with_map(0, half_a_pixel(), WHOLE, NORMAL)];
    let groups = |pages_per_pass| {
        let laid = super::lay(&steps, &sets, &STRIP, 4, pages_per_pass).expect("lay");
        laid.into_iter().map(|each| (each.pages, each.live)).collect::<Vec<_>>()
    };
    assert_eq!(
        groups(3),
        [
            (vec![0, 1, 2], vec![true, true, false, false]),
            (vec![1, 2, 3], vec![false, false, true, true]),
        ]
    );
    assert_eq!(groups(4), [(vec![0, 1, 2, 3], vec![true; 4])]);
}

// Laid a group of output tiles at a time, a row lays what R1 resamples, a
// pass a group; over a row under it, it composites as when one pass binds
// every page, the stack kept between the groups. Two pages a pass take no
// output tile reading three.
#[test]
fn a_row_laid_a_group_at_a_time_composites_as_in_one() {
    let picture = picture_of(|x, y| texel(57, x, y), (4 * TILE, TILE));
    let strip = |steps: Vec<Step>| {
        let mut pool = Pool::default();
        let sets = vec![
            pool.set(57, (0, 0), (4, 1), |c, _| Some(c as u16)),
            pool.set(58, (0, 0), (4, 1), |_, _| Some(4)),
        ];
        Scene {
            pool,
            sets,
            keys: Vec::new(),
            steps,
            tiles: STRIP.to_vec(),
        }
    };
    let alone = strip(vec![with_map(0, half_a_pixel(), WHOLE, NORMAL)]);
    let (out, passes) = composite(&alone, within(3, usize::MAX));
    assert!(out == resampled(&half_a_pixel(), &picture, &STRIP));
    assert_eq!(passes, 2);
    let over = strip(vec![
        row(1, (0, 0), WHOLE, NORMAL),
        with_map(0, half_a_pixel(), 50000, MULTIPLY),
    ]);
    let (out, passes) = composite(&over, within(3, usize::MAX));
    assert!(out == widest(&over));
    assert_eq!(passes, 3);
    let Rig { engine, composite } = rig();
    let pool = alone.pool.upload(engine);
    let two = within(2, usize::MAX);
    assert!(composite.run(engine, &alone.plan(&pool), &STRIP, EVERYWHERE, two).is_none());
}

// The kernel samples a row only where it is live: a row over two output
// tiles, made dead on the second, lays its pixels on the first as a whole
// run does, and nothing on the second.
#[test]
fn a_row_lays_nothing_where_it_is_not_live() {
    let Rig { engine, composite } = rig();
    let mut pool = Pool::default();
    let sets = vec![pool.set(54, (0, 0), (2, 1), |_, _| Some(0))];
    let pages = pool.upload(engine);
    let steps = [row(0, (0, 0), WHOLE, NORMAL)];
    let plan = Plan {
        pages: &pages,
        sets: &sets,
        keys: &[],
        steps: &steps,
        mask: None,
    };
    let tiles = [(0, 0), (1, 0)];
    let whole = composite.run(engine, &plan, &tiles, EVERYWHERE, composite.widest());
    let whole = read_buffer(engine, &whole.expect("composite").out);
    let mut laid = super::lay(&steps, &sets, &tiles, 1, 1).expect("lay");
    laid[0].live[1] = false;
    let out = engine.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("test out"),
        size: 2 * TILE_TEXELS * 4,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    });
    composite
        .walk_laid(
            engine,
            &plan,
            &laid,
            &tiles,
            EVERYWHERE,
            None,
            &super::Target::Tiles(&out),
            composite.widest(),
        )
        .expect("walk");
    let culled = read_buffer(engine, &out);
    let half = (TILE_TEXELS * 4) as usize;
    assert!(culled[..half] == whole[..half], "the live tile");
    assert!(whole[half..].iter().any(|&byte| byte != 0), "the row reaches the second tile");
    assert!(culled[half..].iter().all(|&byte| byte == 0), "the dead tile");
}

// A step's bit is its own past the first word of steps: forty rows, two on
// output tile 0 alone (steps 16 and 33, each where another word's or
// another bit's step is dead there) and the rest on tile 1 alone. Tile 0
// is the two rows by themselves, tile 1 the rest by themselves.
#[test]
fn a_row_s_bit_is_its_own_past_a_word_of_steps() {
    let Rig { engine, composite } = rig();
    let mut pool = Pool::default();
    let on_first = pool.set(55, (0, 0), (1, 1), |_, _| Some(0));
    let on_second = pool.set(56, (1, 0), (1, 1), |_, _| Some(0));
    let sets = vec![on_first, on_second];
    let pages = pool.upload(engine);
    let first = [16, 33];
    let lays = |steps: &[Step]| {
        let plan = Plan {
            pages: &pages,
            sets: &sets,
            keys: &[],
            steps,
            mask: None,
        };
        let done = composite.run(engine, &plan, &[(0, 0), (1, 0)], EVERYWHERE, composite.widest());
        read_buffer(engine, &done.expect("composite").out)
    };
    let step = |k: usize| {
        let set = usize::from(!first.contains(&k));
        row(set, (0, 0), 20000 + 1000 * k as u32, [NORMAL, MULTIPLY, SCREEN][k % 3])
    };
    let all: Vec<Step> = (0..40).map(step).collect();
    let alone: Vec<Step> = first.iter().map(|&k| step(k)).collect();
    let rest: Vec<Step> = (0..40).filter(|k| !first.contains(k)).map(step).collect();
    let half = (TILE_TEXELS * 4) as usize;
    let (together, by_first, by_rest) = (lays(&all), lays(&alone), lays(&rest));
    assert!(together[..half] == by_first[..half], "tile 0");
    assert!(together[half..] == by_rest[half..], "tile 1");
}

// ---- Under a selection (R28) ----

/// `row` laid under the plan's mask.
fn masked_row(row: Step) -> Step {
    let Step::Row {
        set,
        keys,
        map,
        opacity,
        mode,
        ..
    } = row
    else {
        unreachable!("only a row is masked");
    };
    Step::Row {
        set,
        keys,
        map,
        opacity,
        mode,
        masked: true,
    }
}

/// Composites `scene` under `mask` within `budget`: the output's bytes, or
/// none where the plan is refused.
fn under(scene: &Scene, mask: Option<&Mask>, budget: Budget) -> Option<Vec<u8>> {
    let Rig { engine, composite } = rig();
    let pages = scene.pool.upload(engine);
    let plan = Plan {
        mask,
        ..scene.plan(&pages)
    };
    let done = composite.run(engine, &plan, &scene.tiles, EVERYWHERE, budget)?;
    Some(read_buffer(engine, &done.out))
}

const BLUE: u32 = 30 | 90 << 8 | 220 << 16 | 255 << 24;
const RED: u32 = 200 | 100 << 8 | 50 << 16 | 255 << 24;

/// Opaque blue on tile (0, 0) under red laid whole, normal, under the
/// plan's mask.
fn red_over_blue() -> Scene {
    let mut pool = Pool::default();
    let sets = vec![
        pool.drawn(|_, _| BLUE, (0, 0), (1, 1), |_, _| Some(0)),
        pool.drawn(|_, _| RED, (0, 0), (1, 1), |_, _| Some(0)),
    ];
    Scene {
        pool,
        sets,
        keys: Vec::new(),
        steps: vec![row(0, (0, 0), WHOLE, NORMAL), masked_row(row(1, (0, 0), WHOLE, NORMAL))],
        tiles: vec![(0, 0)],
    }
}

// A masked row is laid at its opacity under the mask's byte at the output
// pixel: red whole under 128 lands on opaque blue as red at 128 does —
// (200·32896 + 30·32639)/65535, 115, and the like (a stroke at 128 lands
// the same, dab/tests.rs) — whole under 255, and not at all under 0 or
// past the box, [1, 6) each way, though the plane holds 255 past its
// width.
#[test]
fn a_masked_row_is_laid_under_the_mask_s_byte() {
    let mask = masked((1, 1), (5, 5), |x, y| match (x, y) {
        (1, 1) => 128,
        (2, 2) => 0,
        _ => 255,
    });
    let scene = red_over_blue();
    let out = under(&scene, Some(&mask.mask()), rig().composite.widest()).expect("composite");
    let at = |x, y| pixel_at(&out, &scene.tiles, x, y);
    let (red, blue) = (bytes_of(RED), bytes_of(BLUE));
    assert_eq!(at(1, 1), [115, 95, 135, 255]);
    assert_eq!([at(3, 3), at(5, 5)], [red; 2]);
    assert_eq!([at(2, 2), at(0, 0), at(6, 5), at(5, 6), at(100, 3)], [blue; 5]);
}

// Under a mask of 255 a row is laid as under none, in every mode and at
// every opacity: 255 leaves the opacity as it is, so a row under no mask
// takes the same multiply.
#[test]
fn a_row_under_a_whole_mask_lays_as_under_none() {
    let mut scene = rows();
    scene.steps = scene.steps.into_iter().map(masked_row).collect();
    let mask = masked((-128, 0), (384, 256), |_, _| 255);
    let out = under(&scene, Some(&mask.mask()), rig().composite.widest());
    assert!(out == Some(widest(&rows())));
}

// A mask's byte and a row's opacity are one cover: under 128, a row at
// 32768 lays as one at round(32768·32896/65535) = 16448 under none.
#[test]
fn a_mask_s_byte_and_a_row_s_opacity_are_one_cover() {
    let mask = masked((-128, 0), (384, 256), |_, _| 128);
    for mode in [NORMAL, MULTIPLY, SCREEN, DIFFERENCE] {
        let topped = |opacity, laid: fn(Step) -> Step| {
            let mut scene = rows();
            scene.steps[2] = laid(row(2, (-129, 3), opacity, mode));
            scene
        };
        let budget = rig().composite.widest();
        let by_mask = under(&topped(32768, masked_row), Some(&mask.mask()), budget);
        assert!(by_mask == Some(widest(&topped(16448, |row| row))), "mode {mode}");
    }
}

/// Tiles of three tile rows, in no order, of a row laid whole, normal, and
/// `top` over it.
fn three_rows(top: Option<Step>) -> Scene {
    let mut pool = Pool::default();
    let sets = vec![
        pool.set(61, (-1, 0), (3, 3), |_, _| Some(0)),
        pool.set(62, (-1, 0), (3, 3), |c, r| Some((c + r).rem_euclid(2) as u16)),
    ];
    Scene {
        pool,
        sets,
        keys: Vec::new(),
        steps: [Some(row(0, (0, 0), WHOLE, NORMAL)), top].into_iter().flatten().collect(),
        tiles: vec![(1, 2), (-1, 0), (0, 2), (0, 0), (1, 1), (-1, 2)],
    }
}

// Under a mask of 0 and 255 alone, each output pixel is the plan's with
// the masked row or without it — where the box starts and ends inside a
// tile, whatever order the output tiles come in, and however few a pass
// takes: each pass reads the mask's rows its own tiles lie on.
#[test]
fn each_pass_reads_the_mask_s_rows_its_tiles_lie_on() {
    let coverage = |x: i32, y: i32| [0, 255][(mix(x as u32 ^ mix(y as u32)) & 1) as usize];
    let mask = masked((-60, 70), (300, 300), coverage);
    let top = row(1, (0, 0), WHOLE, SCREEN);
    let (with, without) = (widest(&three_rows(Some(top))), widest(&three_rows(None)));
    let scene = three_rows(Some(masked_row(top)));
    let most = rig().composite.widest().pages;
    let side = TILE as i32;
    for budget in [rig().composite.widest(), within(most, 1), within(most, 2), within(1, 4)] {
        let out = under(&scene, Some(&mask.mask()), budget).expect("composite");
        for &(column, tile_row) in &scene.tiles {
            for y in tile_row * side..(tile_row + 1) * side {
                for x in column * side..(column + 1) * side {
                    let inside = (-60..240).contains(&x) && (70..370).contains(&y);
                    let want = if inside && coverage(x, y) == 255 { &with } else { &without };
                    let got = pixel_at(&out, &scene.tiles, x, y);
                    assert_eq!(got, pixel_at(want, &scene.tiles, x, y), "({x}, {y}) at {budget:?}");
                }
            }
        }
    }
}

// A masked row needs the plan's mask, and the mask a plane that holds its
// box: 12 bytes for a box of 24 is refused.
#[test]
fn a_masked_row_needs_a_mask_that_holds_its_box() {
    let scene = red_over_blue();
    let budget = rig().composite.widest();
    assert!(under(&scene, None, budget).is_none());
    let mask = masked((0, 0), (4, 3), |_, _| 255);
    let short = Mask {
        size: MaskBox { width: 5, height: 3 },
        ..mask.mask()
    };
    assert!(under(&scene, Some(&short), budget).is_none());
    assert!(under(&scene, Some(&mask.mask()), budget).is_some());
}
