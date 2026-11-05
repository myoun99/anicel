//! The row composite on a real GPU, checked against the ledger, against
//! itself cut into passes every way the device allows, and against what
//! the formulas give by hand — never against a CPU copy of them
//! (`kernels/mod.rs` has why).

use std::sync::{OnceLock, mpsc};

use super::{
    Batch, Budget, Composite, DEPTH, Laid, Step, TILE, TILE_TEXELS, TileAt, TileSet, check_depth,
    cut,
};
use crate::device::Engine;
use crate::kernels::shared::tests::{Picture, window};
use crate::kernels::shared::{ResampleMap, ResampleMode};
use crate::testing::{assert_pinned, first_engine};

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
        map,
        opacity,
        mode,
    }
}

/// A plan, what it lays and where it is looked at.
struct Scene {
    pool: Pool,
    sets: Vec<TileSet>,
    steps: Vec<Step>,
    tiles: Vec<(i32, i32)>,
}

/// Composites `scene` within `budget`; returns the output's bytes and how
/// many passes it took.
fn composite(scene: &Scene, budget: Budget) -> (Vec<u8>, usize) {
    let Rig { engine, composite } = rig();
    let pages = scene.pool.upload(engine);
    let done = composite
        .run(engine, &pages, &scene.sets, &scene.steps, &scene.tiles, budget)
        .expect("composite");
    (read(engine, &done.out), done.passes)
}

fn widest(scene: &Scene) -> Vec<u8> {
    composite(scene, rig().composite.widest()).0
}

/// At most `pages` pages and `tiles` output tiles a pass.
fn within(pages: usize, tiles: usize) -> Budget {
    Budget { pages, tiles }
}

fn read(engine: &Engine, buffer: &wgpu::Buffer) -> Vec<u8> {
    let readback = engine.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("composite readback"),
        size: buffer.size(),
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut encoder = engine
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
    encoder.copy_buffer_to_buffer(buffer, 0, &readback, 0, buffer.size());
    engine.queue.submit([encoder.finish()]);
    let (sender, receiver) = mpsc::channel();
    readback.map_async(wgpu::MapMode::Read, .., move |result| {
        let _ = sender.send(result);
    });
    engine.wait().expect("wait for the GPU");
    receiver.recv().expect("map_async answered").expect("map");
    readback.get_mapped_range(..).expect("mapped range").to_vec()
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

fn scenes() -> [(&'static str, Scene); 5] {
    [
        ("rows", rows()),
        ("folders", folders()),
        ("clips", clips()),
        ("spanning", spanning()),
        ("posed", posed()),
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
// between passes is kept as it was, 16 bits a channel.
#[test]
fn a_plan_cut_into_passes_composites_as_in_one() {
    let most = rig().composite.widest().pages;
    for (name, scene) in scenes() {
        let whole = widest(&scene);
        for pages in 1..most {
            let (cut, passes) = composite(&scene, within(pages, usize::MAX));
            assert!(cut == whole, "{name} at {pages} pages a pass");
            if name == "spanning" && pages == 1 {
                assert!(passes > 1, "the folder was never cut");
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
            let run = composite.run(engine, &pool, &scene.sets, &scene.steps, &scene.tiles, fewer);
            assert!(run.is_none(), "{n}");
        }
    }
}

// ---- The plan ----

#[test]
fn a_plan_must_close_what_it_opens_and_name_its_rows() {
    let close = Step::Close {
        opacity: WHOLE,
        mode: NORMAL,
    };
    assert!(check_depth(&[Step::Open, row(0, (0, 0), WHOLE, NORMAL), close], 1).is_some());
    assert!(check_depth(&[Step::Open], 1).is_none());
    assert!(check_depth(&[close], 1).is_none());
    assert!(check_depth(&[Step::CloseAtop], 1).is_none());
    assert!(check_depth(&[row(1, (0, 0), WHOLE, NORMAL)], 1).is_none());
    let deepest: Vec<Step> = (0..DEPTH - 1)
        .map(|_| Step::Open)
        .chain((0..DEPTH - 1).map(|_| close))
        .collect();
    assert!(check_depth(&deepest, 0).is_some());
    let deeper: Vec<Step> = (0..DEPTH)
        .map(|_| Step::OpenOpaque)
        .chain((0..DEPTH).map(|_| close))
        .collect();
    assert!(check_depth(&deeper, 0).is_none());
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
    let batches: Vec<_> = cut(&plan, 2).expect("a cut").iter().map(shape).collect();
    assert_eq!(
        batches,
        [
            (0, 3, 0, 1, vec![0, 1]),
            (3, 6, 1, 0, vec![2, 0]),
            (6, 7, 0, 0, vec![3]),
        ]
    );
}
