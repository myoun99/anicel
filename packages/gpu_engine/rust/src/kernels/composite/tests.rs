//! The row composite on a real GPU, checked against the ledger, against
//! itself cut into passes every way the device allows, and against what
//! the formulas give by hand — never against a CPU copy of them
//! (`kernels/mod.rs` has why).

use std::sync::{OnceLock, mpsc};

use super::{
    Batch, Composite, DEPTH, Laid, Step, TILE, TILE_TEXELS, TileAt, TileSet, check_depth, cut,
};
use crate::device::Engine;
use crate::testing::{assert_pinned, first_engine};

const NORMAL: u32 = 28;
const MULTIPLY: u32 = 3;
const SCREEN: u32 = 6;
const OVERLAY: u32 = 8;
const DIFFERENCE: u32 = 11;
const LINEAR_BURN: u32 = 13;
const WHOLE: u32 = 65535;

struct Rig {
    engine: Engine,
    composite: Composite,
}

/// One device and one compiled pass for every test here, as the app opens
/// one device (blend's tests have why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        let composite = Composite::new(&engine).expect("compile the composite");
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

fn row(set: usize, (dx, dy): (i32, i32), opacity: u32, mode: u32) -> Step {
    Step::Row {
        set,
        dx,
        dy,
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

/// Composites `scene` with at most `pages_per_pass` pages a pass; returns
/// the output's bytes and how many passes it took.
fn composite(scene: &Scene, pages_per_pass: usize) -> (Vec<u8>, usize) {
    let Rig { engine, composite } = rig();
    let pages = scene.pool.upload(engine);
    let done = composite
        .run(engine, &pages, &scene.sets, &scene.steps, &scene.tiles, pages_per_pass)
        .expect("composite");
    (read(engine, &done.out), done.passes)
}

fn widest(scene: &Scene) -> Vec<u8> {
    composite(scene, rig().composite.pages_per_pass()).0
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

fn scenes() -> [(&'static str, Scene); 4] {
    [
        ("rows", rows()),
        ("folders", folders()),
        ("clips", clips()),
        ("spanning", spanning()),
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
    let most = rig().composite.pages_per_pass();
    for (name, scene) in scenes() {
        let (whole, _) = composite(&scene, most);
        for pages in 1..most {
            let (cut, passes) = composite(&scene, pages);
            assert!(cut == whole, "{name} at {pages} pages a pass");
            if name == "spanning" && pages == 1 {
                assert!(passes > 1, "the folder was never cut");
            }
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
    let laid = |page: Option<u16>, step: Step| Laid { step, page };
    let a_row = row(0, (0, 0), WHOLE, NORMAL);
    let close = Step::Close {
        opacity: WHOLE,
        mode: NORMAL,
    };
    let plan = [
        laid(Some(0), a_row),
        laid(None, Step::Open),
        laid(Some(1), a_row),
        laid(Some(2), a_row),
        laid(None, close),
        laid(Some(0), a_row),
        laid(Some(3), a_row),
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
    let batches: Vec<_> = cut(&plan, 2).iter().map(shape).collect();
    assert_eq!(
        batches,
        [
            (0, 3, 0, 1, vec![0, 1]),
            (3, 6, 1, 0, vec![2, 0]),
            (6, 7, 0, 0, vec![3]),
        ]
    );
}
