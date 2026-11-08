//! The executor's C ABI on a real GPU: a plan built call by call composites
//! as the same plan built in Rust, shown onto a surface it lays the pixels a
//! run puts, a screen composes and shows as one built in Rust does, a row
//! whose pose lands nothing is left out, and what is refused says why.

use super::*;
use crate::kernels::blend::mode::{MULTIPLY, NORMAL, SCREEN};
use crate::kernels::composite::tests::{mix, pixel_at, rig, surface};
use crate::kernels::composite::{NO_TILE, TILE, TILE_TEXELS, TileAt};
use crate::kernels::pool::Pool;
use crate::kernels::shared::le_bytes;
use crate::platform::{gpu_engine_surface_free, gpu_engine_surface_new};
use crate::testing::{last_error, read_buffer};

const IDENTITY: [f64; 9] = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
/// Moved left by 37.25 px and down by 9.5: a pose R1 samples, not copies.
const POSED: [f64; 9] = [1.0, 0.0, 37.25, 0.0, 1.0, -9.5, 0.0, 0.0, 1.0];
/// Moved right by 200 px, over the base of tile 3, and up by half a pixel:
/// every pixel's preimage split between two rows, which Pick breaks to the
/// one above and nearest to the one below.
const OVER: [f64; 9] = [1.0, 0.0, -200.0, 0.0, 1.0, 0.5, 0.0, 0.0, 1.0];
const NO_EDGE: [i32; 4] = [i32::MIN, i32::MIN, i32::MAX, i32::MAX];
const OUTPUT: [(i32, i32); 3] = [(0, 0), (1, 0), (2, 0)];
const BLEND: u32 = 0;
const PICK: u32 = 1;
const NEAREST: u32 = 3;

/// A tile of words of its own, `n`, opaque where `opaque` — else a pixel
/// of no alpha all 0, as a pass lays one.
fn tile(n: u32, opaque: bool) -> Vec<u8> {
    let word = |i| match mix(n.wrapping_mul(7919) ^ i) {
        word if opaque => word | 0xff00_0000,
        word if word >> 24 == 0 => 0,
        word => word,
    };
    le_bytes(&(0..TILE_TEXELS as u32).map(word).collect::<Vec<_>>())
}

/// A pool holding `tiles`, and their places.
fn stored(tiles: &[Vec<u8>]) -> (Pool, Vec<TileAt>) {
    let engine = rig().engine;
    let mut pool = Pool::new(engine, u64::MAX).expect("pool");
    let cel = pool.cel();
    let bytes: Vec<&[u8]> = tiles.iter().map(Vec::as_slice).collect();
    let places = pool.store(engine, cel, &bytes).expect("store");
    (pool, places)
}

fn map(inverse: [f64; 9], mode: ResampleMode) -> ResampleMap {
    ResampleMap::new(inverse, 1.0, mode, 3 * TILE, TILE).expect("a pose that lands")
}

/// `plan` run by the C ABI over [`OUTPUT`]: what it put, null where it
/// was refused.
fn run_out(pool: &Pool, plan: *const Planned, extent: [i32; 4]) -> *mut Composited {
    let (engine, composite) = (rig().engine, &rig().composite);
    let tiles: Vec<i32> = OUTPUT.iter().flat_map(|&(column, row)| [column, row]).collect();
    // SAFETY: every pointer is live, `tiles` holds two words a tile.
    unsafe { gpu_engine_composite_run(composite, engine, pool, plan, tiles.as_ptr(), OUTPUT.len(), extent.as_ptr()) }
}

/// `plan` run by the C ABI over [`OUTPUT`], read back.
fn ran(pool: &Pool, plan: *const Planned, extent: [i32; 4]) -> Option<Vec<u8>> {
    let engine = rig().engine;
    let out = run_out(pool, plan, extent);
    if out.is_null() {
        return None;
    }
    let mut bytes = vec![0; gpu_engine_composited_bytes(OUTPUT.len()) as usize];
    // SAFETY: `out` is live and `bytes` holds its capacity.
    let read = unsafe { gpu_engine_composited_read(engine, out, bytes.as_mut_ptr(), bytes.len()) };
    // SAFETY: `out` came from the run.
    unsafe { gpu_engine_composited_free(out) };
    read.then_some(bytes)
}

/// `plan` run in Rust over [`OUTPUT`], read back.
fn ran_in_rust(
    pool: &Pool,
    sets: &[TileSet],
    keys: &[KeyChain],
    matrices: &[[u32; MATRIX_WORDS]],
    chains: &[Chained],
    steps: &[Step],
) -> Vec<u8> {
    let (engine, composite) = (rig().engine, &rig().composite);
    let plan = Plan { pages: pool.pages(), sets, keys, matrices, chains, steps, mask: None };
    let out = composite.run(engine, &plan, &OUTPUT, [0, 0, 300, 120], composite.widest()).expect("run");
    read_buffer(engine, &out.out)
}

// Every call names a field of its step: a field put in another's place, or
// a set or matrix named by another index, composites other bytes — each
// sampling, both opens and both matrices among them.
#[test]
fn a_plan_built_call_by_call_composites_as_one_built_in_rust() {
    let tiles = [tile(1, false), tile(2, false), tile(3, true)];
    let (pool, at) = stored(&tiles);
    let contrast: [f64; MATRIX_WORDS] = [
        1.4, 0.0, 0.0, 0.0, -20.0, 0.0, 1.2, 0.1, 0.0, 5.0, 0.0, 0.0, 0.8, 0.0, 30.0, 0.0, 0.0, 0.0, 1.0, 0.0,
    ];
    let warm: [f64; MATRIX_WORDS] = [
        1.0, 0.0, 0.0, 0.0, 25.0, 0.0, 0.9, 0.0, 0.0, 0.0, 0.0, 0.0, 0.7, 0.0, -10.0, 0.0, 0.0, 0.0, 1.0, 0.0,
    ];
    let plan = gpu_engine_plan_new();
    // SAFETY: `plan` is live; each array holds what its call reads.
    unsafe {
        assert_eq!(gpu_engine_plan_set(plan, 0, 0, 2, 1, [at[0].word(), at[1].word()].as_ptr()), 0);
        assert_eq!(gpu_engine_plan_set(plan, 1, 0, 2, 1, [NO_TILE, at[2].word()].as_ptr()), 1);
        assert_eq!(gpu_engine_plan_matrix(plan, contrast.as_ptr()), 0);
        assert_eq!(gpu_engine_plan_matrix(plan, warm.as_ptr()), 1);
        gpu_engine_plan_solid(plan, 0xc0_33_66_99, 10, 4, 290, 100);
        gpu_engine_plan_open(plan, false);
        assert_eq!(gpu_engine_plan_row(plan, 0, -1, -1, -1, IDENTITY.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 65535, NORMAL), 1);
        assert_eq!(gpu_engine_plan_row(plan, 1, 0, -1, -1, POSED.as_ptr(), 2.0, PICK, 3 * TILE, TILE, 41000, SCREEN), 1);
        gpu_engine_plan_close(plan, 40000, MULTIPLY, -1, -1, 65535);
        gpu_engine_plan_open(plan, false);
        assert_eq!(gpu_engine_plan_row(plan, 1, -1, -1, -1, IDENTITY.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 65535, NORMAL), 1);
        gpu_engine_plan_open(plan, true);
        assert_eq!(gpu_engine_plan_row(plan, 0, -1, -1, -1, OVER.as_ptr(), 1.0, NEAREST, 3 * TILE, TILE, 30000, MULTIPLY), 1);
        gpu_engine_plan_close_atop(plan);
        gpu_engine_plan_close(plan, 50000, NORMAL, 1, -1, 65535);
    }
    let sets = [
        TileSet { x0: 0, y0: 0, columns: 2, rows: 1, tiles: vec![Some(at[0]), Some(at[1])] },
        TileSet { x0: 1, y0: 0, columns: 2, rows: 1, tiles: vec![None, Some(at[2])] },
    ];
    let row = |set, map, matrix, opacity, mode| Step::Row {
        set,
        keys: None,
        chain: None,
        map,
        matrix,
        opacity,
        mode,
        masked: false,
    };
    let posed = ResampleMap::new(POSED, 2.0, ResampleMode::Pick, 3 * TILE, TILE).expect("lands");
    let steps = [
        Step::Solid { colour: 0xc0_33_66_99, rect: [10, 4, 290, 100] },
        Step::Open,
        row(0, map(IDENTITY, ResampleMode::Blend), None, 65535, NORMAL),
        row(1, posed, Some(0), 41000, SCREEN),
        Step::Close { opacity: 40000, mode: MULTIPLY, matrix: None, chain: None },
        Step::Open,
        row(1, map(IDENTITY, ResampleMode::Blend), None, 65535, NORMAL),
        Step::OpenOpaque,
        row(0, map(OVER, ResampleMode::Nearest), None, 30000, MULTIPLY),
        Step::CloseAtop,
        Step::Close { opacity: 50000, mode: NORMAL, matrix: Some(1), chain: None },
    ];
    let matrices = [matrix_words(&contrast).expect("held"), matrix_words(&warm).expect("held")];
    let built = ran(&pool, plan, [0, 0, 300, 120]).expect("run");
    // SAFETY: `plan` came from `gpu_engine_plan_new`.
    unsafe { gpu_engine_plan_free(plan) };
    assert_eq!(built, ran_in_rust(&pool, &sets, &[], &matrices, &[], &steps));
}

// A row copied over nothing lays its stored bytes, tile for tile in the
// order asked — what the app reads a cel's tiles back by.
#[test]
fn a_row_copied_over_nothing_lays_the_bytes_stored() {
    let tiles = [tile(4, false), tile(5, false), tile(6, false)];
    let (pool, at) = stored(&tiles);
    let plan = gpu_engine_plan_new();
    // SAFETY: `plan` is live; each array holds what its call reads.
    unsafe {
        gpu_engine_plan_set(plan, 0, 0, 3, 1, at.iter().map(|&at| at.word()).collect::<Vec<_>>().as_ptr());
        gpu_engine_plan_row(plan, 0, -1, -1, -1, IDENTITY.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 65535, NORMAL);
    }
    let read = ran(&pool, plan, NO_EDGE).expect("run");
    // SAFETY: `plan` came from `gpu_engine_plan_new`.
    unsafe { gpu_engine_plan_free(plan) };
    assert_eq!(read, tiles.concat());
}

// Shown onto a surface, a plan lays inside the rectangle the pixels a run
// puts — premultiplied, which opaque pixels are already.
#[test]
fn a_plan_shown_onto_a_surface_lays_the_pixels_a_run_puts() {
    let tiles = [tile(7, true), tile(8, true)];
    let (pool, at) = stored(&tiles);
    let engine = rig().engine;
    let plan = gpu_engine_plan_new();
    // SAFETY: `plan` is live; each array holds what its call reads.
    unsafe {
        gpu_engine_plan_set(plan, 0, 0, 2, 1, [at[0].word(), at[1].word()].as_ptr());
        gpu_engine_plan_row(plan, 0, -1, -1, -1, POSED.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 65535, NORMAL);
    }
    // Where the pose's tent reads stored pixels alone, so what it lays is
    // opaque: source y = y − 9 ± 1 inside the tiles from y = 10, source x =
    // x + 37.75 ± 1 inside them to x = 217.
    let rect = [5u32, 10, 217, 120];
    let extent = rect.map(|edge| edge as i32);
    let put = ran(&pool, plan, extent).expect("run");
    // The surface as the platform makes the ones it shows: RGBA where it
    // can, else BGRA — Apple's make BGRA alone (platform/apple.rs), Linux's
    // RGBA alone.
    let (surface, bgra) = [false, true]
        .into_iter()
        // SAFETY: `engine` is live.
        .map(|bgra| (unsafe { gpu_engine_surface_new(engine, 3 * TILE, TILE, bgra) }, bgra))
        .find(|(surface, _)| !surface.is_null())
        .unwrap_or_else(|| panic!("{}", last_error()));
    // SAFETY: every pointer is live and made on `engine`.
    let passes =
        unsafe { gpu_engine_composite_show(&rig().composite, engine, &pool, plan, &(*surface).texture, rect.as_ptr()) };
    assert!(passes >= 1, "{}", last_error());
    // SAFETY: `surface` is live.
    let shown = engine.read_texture(unsafe { &(*surface).texture }).expect("read the surface");
    for y in rect[1] as i32..rect[3] as i32 {
        for x in rect[0] as i32..rect[2] as i32 {
            let texel = (y as usize * 3 * TILE as usize + x as usize) * 4;
            let [r, g, b, a] = pixel_at(&put, &OUTPUT, x, y);
            let want = if bgra { [b, g, r, a] } else { [r, g, b, a] };
            assert_eq!(shown[texel..texel + 4], want, "({x}, {y})");
        }
    }
    // SAFETY: neither is used again.
    unsafe {
        gpu_engine_surface_free(surface);
        gpu_engine_plan_free(plan);
    }
}

// A row whose pose lands nothing lays nothing, so it is left out of the
// plan, not refused.
#[test]
fn a_row_whose_pose_lands_nothing_is_left_out() {
    let behind = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, -1.0];
    let plan = gpu_engine_plan_new();
    // SAFETY: `plan` is live and `behind` holds nine.
    let added = unsafe { gpu_engine_plan_row(plan, 0, -1, -1, -1, behind.as_ptr(), 1.0, BLEND, TILE, TILE, 65535, NORMAL) };
    assert_eq!(added, 0);
    // SAFETY: `plan` is live.
    assert!(unsafe { &*plan }.steps.is_empty());
    // SAFETY: `plan` came from `gpu_engine_plan_new`.
    unsafe { gpu_engine_plan_free(plan) };
}

// What the ABI cannot add it refuses with a reason, and a plan the walk
// refuses runs to null with the walk's.
#[test]
fn what_is_refused_says_why() {
    let (pool, _) = stored(&[tile(9, false)]);
    let plan = gpu_engine_plan_new();
    let past = [1e12; MATRIX_WORDS];
    // SAFETY: `plan` is live; each array holds what its call reads.
    unsafe {
        assert_eq!(gpu_engine_plan_row(plan, 0, -1, -1, -1, IDENTITY.as_ptr(), 1.0, 2, TILE, TILE, 65535, NORMAL), -1);
        assert!(last_error().contains("sampling"), "{}", last_error());
        assert_eq!(gpu_engine_plan_matrix(plan, past.as_ptr()), -1);
        assert!(last_error().contains("matrix"), "{}", last_error());
        assert!((*plan).steps.is_empty() && (*plan).matrices.is_empty());
        gpu_engine_plan_row(plan, 5, -1, -1, -1, IDENTITY.as_ptr(), 1.0, BLEND, TILE, TILE, 65535, NORMAL);
    }
    assert!(ran(&pool, plan, NO_EDGE).is_none());
    assert!(last_error().contains("tile set 5"), "{}", last_error());
    // SAFETY: `plan` came from `gpu_engine_plan_new`.
    unsafe { gpu_engine_plan_free(plan) };
}

// The executor the app makes is the one the tests run: made and freed.
#[test]
fn the_c_abi_makes_an_executor_and_frees_it() {
    // SAFETY: the engine is live; the executor is freed before it.
    let composite = unsafe { gpu_engine_composite_new(rig().engine) };
    assert!(!composite.is_null(), "{}", last_error());
    // SAFETY: `composite` came from `gpu_engine_composite_new`.
    unsafe { gpu_engine_composite_free(composite) };
    assert_eq!(gpu_engine_composited_bytes(3), 3 * TILE_BYTES);
}

/// An iris of six sides turned by 20°, a little round and drawn out: its
/// sides, then its roundness, aspect and three turns as `lens` names them.
fn hexagon() -> (u32, [f64; 8]) {
    let (turn, half, side) = (20f64.to_radians(), 30f64.to_radians(), 60f64.to_radians());
    (6, [0.25, 1.25, turn.cos(), turn.sin(), half.cos(), half.sin(), side.cos(), side.sin()])
}

/// [`hexagon`]'s iris and then `rest` — the radius, the fringe, the light's
/// gain, threshold and saturation: the thirteen `gpu_engine_plan_chain_lens`
/// reads.
fn lens_words(rest: [f64; 5]) -> [f64; 13] {
    let (_, iris) = hexagon();
    std::array::from_fn(|at| if at < 8 { iris[at] } else { rest[at - 8] })
}

/// The lens of `l`, as `gpu_engine_plan_chain_lens` reads it.
fn lens_of(l: &[f64; 13], linear: bool, paper: Option<[i32; 4]>) -> Lens {
    let (sides, _) = hexagon();
    Lens {
        iris: Iris {
            sides,
            roundness: l[0],
            aspect: l[1],
            turn: [l[2], l[3]],
            half_side: [l[4], l[5]],
            side: [l[6], l[7]],
        },
        radius: l[8],
        fringe: l[9],
        light: Light { gain: l[10], threshold: l[11], saturation: l[12], linear },
        paper,
    }
}

/// A run of one key's tables: red under 128, any green, blue over 127 — a
/// quarter of a tile's colours —, its alpha map a third of what it reads.
fn quarter_run() -> ([[u32; 256]; 3], Vec<u8>) {
    let table = |inside: fn(usize) -> bool| std::array::from_fn(|byte| u32::from(inside(byte)));
    let tables = [table(|byte| byte < 128), table(|_| true), table(|byte| byte > 127)];
    (tables, (0..256).map(|alpha| (alpha / 3) as u8).collect())
}

/// A row of tile set `set`, keyed by `keys` or chained by `chain` if any,
/// posed by `map`, laid at `opacity` in `mode`.
fn row(set: usize, keys: Option<usize>, chain: Option<usize>, map: ResampleMap, opacity: u32, mode: u32) -> Step {
    Step::Row { set, keys, chain, map, matrix: None, opacity, mode, masked: false }
}

// Every call names a field of its op: a row keyed and a row chained, a
// chain of every op — a lens blur among them reading a map drawn from
// rows —, and a folder's close chained at a mix composite as the same
// plan built in Rust.
#[test]
fn a_keyed_and_chained_plan_built_call_by_call_composites_as_one_built_in_rust() {
    let tiles = [tile(4, true), tile(5, true), tile(6, false)];
    let (pool, at) = stored(&tiles);
    let (sides, _) = hexagon();
    let lens = lens_words([4.5, 80.0, 1.5, 0.7, 0.4]);
    let ([red, green, blue], maps) = quarter_run();
    let contrast: [f64; MATRIX_WORDS] = [
        1.4, 0.0, 0.0, 0.0, -20.0, 0.0, 1.2, 0.1, 0.0, 5.0, 0.0, 0.0, 0.8, 0.0, 30.0, 0.0, 0.0, 0.0, 1.0, 0.0,
    ];
    let paper = [0, 0, 250, 128];
    let repeat = [4, 6, 200, 120];
    let wide = [0, 0, 3 * TILE as i32, TILE as i32];
    let (sigmas, reaches) = ([1.0, 0.7], [3u32, 2]);
    let plate = [6, 0, 250, 128];
    let taps = [5u32, 3];
    let passes: [f64; 24] = [
        1.5, 0.5, 100.0, 60.0, 1.0, 0.0, 0.0, 1.0, 0.99, 0.01, -0.01, 0.99, //
        0.0, 2.0, 120.0, 40.0, 1.0, 0.05, 0.0, 1.0, 1.0, 0.0, 0.0, 1.02,
    ];
    let picture = [0, 0, 2 * TILE as i32, TILE as i32];
    let plan = gpu_engine_plan_new();
    // SAFETY: `plan` is live; each array holds what its call reads.
    unsafe {
        assert_eq!(gpu_engine_plan_set(plan, 0, 0, 2, 1, [at[0].word(), at[1].word()].as_ptr()), 0);
        assert_eq!(gpu_engine_plan_set(plan, 1, 0, 1, 1, [at[2].word()].as_ptr()), 1);
        assert_eq!(gpu_engine_plan_keys(plan), 0);
        for restores in [0, 1] {
            let added = gpu_engine_plan_key_run(plan, 0, red.as_ptr(), green.as_ptr(), blue.as_ptr(), restores, maps.as_ptr(), 1);
            assert_eq!(added, 1);
        }
        assert_eq!(gpu_engine_plan_row(plan, 1, -1, -1, -1, IDENTITY.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 65535, NORMAL), 1);
        assert_eq!(gpu_engine_plan_map_drawn(plan, 0, 4, 140.0, true), 0);
        assert_eq!(gpu_engine_plan_steps(plan), 0);
        assert_eq!(gpu_engine_plan_chain(plan, 0, 0, 2, 1), 0);
        assert_eq!(gpu_engine_plan_chain_matrix(plan, 0, contrast.as_ptr()), 0);
        assert_eq!(gpu_engine_plan_chain_keys(plan, 0, 0), 0);
        let blurred = gpu_engine_plan_chain_gaussian(plan, 0, sigmas.as_ptr(), reaches.as_ptr(), repeat.as_ptr(), 1, repeat.as_ptr());
        assert_eq!(blurred, 0);
        assert_eq!(gpu_engine_plan_chain_line(plan, 0, plate.as_ptr(), taps.as_ptr(), passes.as_ptr(), 2), 0);
        let lensed = gpu_engine_plan_chain_lens(plan, 0, picture.as_ptr(), sides, lens.as_ptr(), true, paper.as_ptr(), 0);
        assert_eq!(lensed, 0);
        assert_eq!(gpu_engine_plan_chain(plan, 0, 0, 3, 1), 1);
        let across = gpu_engine_plan_chain_gaussian(plan, 1, [0.7, 0.0].as_ptr(), [2u32, 0].as_ptr(), wide.as_ptr(), 0, wide.as_ptr());
        assert_eq!(across, 0);
        gpu_engine_plan_open(plan, false);
        assert_eq!(gpu_engine_plan_row(plan, 0, -1, 0, -1, POSED.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 60000, MULTIPLY), 1);
        assert_eq!(gpu_engine_plan_row(plan, 0, -1, -1, 0, IDENTITY.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 50000, SCREEN), 1);
        gpu_engine_plan_close(plan, 45000, NORMAL, -1, 1, 40000);
    }
    let sets = [
        TileSet { x0: 0, y0: 0, columns: 2, rows: 1, tiles: vec![Some(at[0]), Some(at[1])] },
        TileSet { x0: 1, y0: 0, columns: 1, rows: 1, tiles: vec![Some(at[2])] },
    ];
    let key_run = |restores| KeyRun { red: &red, green: &green, blue: &blue, restores, maps: &maps }.words();
    let keys = [KeyChain { runs: vec![key_run(0), key_run(1)] }];
    let map_rows = [row(1, None, None, map(IDENTITY, ResampleMode::Blend), 65535, NORMAL)];
    let line = |at: usize| {
        let m = &passes[12 * at..];
        LinePass {
            taps: taps[at],
            step: [m[0], m[1]],
            centre: [m[2], m[3]],
            first: [m[4], m[5], m[6], m[7]],
            each: [m[8], m[9], m[10], m[11]],
        }
    };
    let drawn = BlurMap {
        tiles: MapTiles::Drawn(&map_rows),
        channel: MapChannel::Luminance,
        focus: Focus { focal: 140.0, inverts: true },
    };
    let chains = [
        Chained {
            ops: vec![
                Op::Matrix(matrix_words(&contrast).expect("held")),
                Op::Keys(keys[0].clone()),
                Op::Gaussian(Blur {
                    across: Way { sigma: sigmas[0], reach: reaches[0] },
                    down: Way { sigma: sigmas[1], reach: reaches[1] },
                    picture: repeat,
                    edge: Edge::Repeat,
                    puts: repeat,
                }),
                Op::Line { plate, passes: vec![line(0), line(1)] },
                Op::Lens { picture, lens: lens_of(&lens, true, Some(paper)), map: Some(drawn) },
            ],
            rect: TileRect { x0: 0, y0: 0, columns: 2, rows: 1 },
        },
        Chained {
            ops: vec![Op::Gaussian(Blur {
                across: Way { sigma: 0.7, reach: 2 },
                down: Way { sigma: 0.0, reach: 0 },
                picture: wide,
                edge: Edge::Nothing,
                puts: wide,
            })],
            rect: TileRect { x0: 0, y0: 0, columns: 3, rows: 1 },
        },
    ];
    let steps = [
        Step::Open,
        row(0, Some(0), None, map(POSED, ResampleMode::Blend), 60000, MULTIPLY),
        row(0, None, Some(0), map(IDENTITY, ResampleMode::Blend), 50000, SCREEN),
        Step::Close { opacity: 45000, mode: NORMAL, matrix: None, chain: Some(BufferChain { chain: 1, mix: 40000 }) },
    ];
    let built = ran(&pool, plan, [0, 0, 300, 120]).unwrap_or_else(|| panic!("{}", last_error()));
    // SAFETY: `plan` came from `gpu_engine_plan_new`.
    unsafe { gpu_engine_plan_free(plan) };
    assert_eq!(built, ran_in_rust(&pool, &sets, &keys, &[], &chains, &steps));
}

// A map laid from what a run put is read as the tiles it holds, and the
// plan keeps them past the run's own free.
#[test]
fn a_map_laid_from_a_run_is_read_as_its_tiles() {
    let tiles = [tile(7, true), tile(8, true), tile(9, true)];
    let (pool, at) = stored(&tiles);
    let (sides, _) = hexagon();
    let lens = lens_words([5.0, 0.0, 0.0, 1.0, 0.0]);
    let picture = [0, 0, 3 * TILE as i32, TILE as i32];
    let words = [at[0].word(), at[1].word(), at[2].word()];
    let laid = gpu_engine_plan_new();
    let plan = gpu_engine_plan_new();
    // SAFETY: the plans are live; each array holds what its call reads.
    let out = unsafe {
        gpu_engine_plan_set(laid, 0, 0, 3, 1, words.as_ptr());
        gpu_engine_plan_row(laid, 0, -1, -1, -1, POSED.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 65535, NORMAL);
        let out = run_out(&pool, laid, NO_EDGE);
        gpu_engine_plan_set(plan, 0, 0, 3, 1, words.as_ptr());
        assert_eq!(gpu_engine_plan_map_laid(plan, out, 2, 90.0, false), 0);
        gpu_engine_plan_chain(plan, 0, 0, 3, 1);
        gpu_engine_plan_chain_lens(plan, 0, picture.as_ptr(), sides, lens.as_ptr(), false, std::ptr::null(), 0);
        gpu_engine_plan_row(plan, 0, -1, -1, 0, IDENTITY.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 65535, NORMAL);
        out
    };
    // SAFETY: `out` came from a run.
    let map_tiles = unsafe { &*out }.out.clone();
    // SAFETY: each came from its maker.
    unsafe {
        gpu_engine_composited_free(out);
        gpu_engine_plan_free(laid);
    }
    let built = ran(&pool, plan, [0, 0, 300, 120]).unwrap_or_else(|| panic!("{}", last_error()));
    // SAFETY: `plan` came from `gpu_engine_plan_new`.
    unsafe { gpu_engine_plan_free(plan) };
    let sets = [TileSet { x0: 0, y0: 0, columns: 3, rows: 1, tiles: at.iter().copied().map(Some).collect() }];
    let read = BlurMap {
        tiles: MapTiles::Laid(&map_tiles),
        channel: MapChannel::Blue,
        focus: Focus { focal: 90.0, inverts: false },
    };
    let chains = [Chained {
        ops: vec![Op::Lens { picture, lens: lens_of(&lens, false, None), map: Some(read) }],
        rect: TileRect { x0: 0, y0: 0, columns: 3, rows: 1 },
    }];
    let steps = [row(0, None, Some(0), map(IDENTITY, ResampleMode::Blend), 65535, NORMAL)];
    assert_eq!(built, ran_in_rust(&pool, &sets, &[], &[], &chains, &steps));
}

// What a chain's call cannot add says why.
#[test]
fn what_a_chain_s_call_refuses_says_why() {
    let ([red, green, blue], maps) = quarter_run();
    let many = vec![0u8; 256 * 33];
    let matrix = [0.0; MATRIX_WORDS];
    let picture = [0, 0, 1, 1];
    let (sides, _) = hexagon();
    let lens = lens_words([2.0, 0.0, 0.0, 1.0, 0.0]);
    let plan = gpu_engine_plan_new();
    // SAFETY: `plan` is live; each array holds what its call reads.
    unsafe {
        let run = |maps: &[u8], count| {
            gpu_engine_plan_key_run(plan, 0, red.as_ptr(), green.as_ptr(), blue.as_ptr(), 0, maps.as_ptr(), count)
        };
        assert_eq!(run(&maps, 1), -1);
        assert!(last_error().contains("no key chain 0"), "{}", last_error());
        gpu_engine_plan_keys(plan);
        assert_eq!(run(&many, 33), -1);
        assert!(last_error().contains("33 keys"), "{}", last_error());
        assert_eq!(gpu_engine_plan_chain_matrix(plan, 0, matrix.as_ptr()), -1);
        assert!(last_error().contains("no effect chain 0"), "{}", last_error());
        assert_eq!(gpu_engine_plan_chain_keys(plan, 0, 1), -1);
        assert!(last_error().contains("no key chain 1"), "{}", last_error());
        gpu_engine_plan_chain(plan, 0, 0, 1, 1);
        let lensed = gpu_engine_plan_chain_lens(plan, 0, picture.as_ptr(), sides, lens.as_ptr(), false, std::ptr::null(), 0);
        assert_eq!(lensed, -1);
        assert!(last_error().contains("no blur map 0"), "{}", last_error());
        assert_eq!(gpu_engine_plan_map_drawn(plan, 1, 0, 0.0, false), -1);
        assert!(last_error().contains("step 1 of 0"), "{}", last_error());
        assert_eq!(gpu_engine_plan_map_drawn(plan, 0, 5, 0.0, false), -1);
        assert!(last_error().contains("channel"), "{}", last_error());
        gpu_engine_plan_free(plan);
    }
}

// A screen composed and shown call by call is the screen built in Rust over
// the same plan: a posed row laid on the canvas at its own pixels over an
// extent the camera's view cuts, then the camera magnifying it 2× and
// turned past a quarter pixel — and so again after another plan composed
// where it changed. A sampling no mode has is refused, saying why, and the
// screen frees.
#[test]
fn a_screen_composed_and_shown_call_by_call_is_the_screen_in_rust() {
    let tiles = [tile(11, true), tile(12, false)];
    let (pool, at) = stored(&tiles);
    let (engine, composite) = (rig().engine, &rig().composite);
    let (plan, again) = (gpu_engine_plan_new(), gpu_engine_plan_new());
    // SAFETY: both plans are live; each array holds what its call reads.
    unsafe {
        gpu_engine_plan_set(plan, 0, 0, 2, 1, [at[0].word(), at[1].word()].as_ptr());
        gpu_engine_plan_set(again, 0, 0, 2, 1, [at[1].word(), at[0].word()].as_ptr());
        for laid in [plan, again] {
            gpu_engine_plan_row(laid, 0, -1, -1, -1, POSED.as_ptr(), 1.0, BLEND, 2 * TILE, TILE, 65535, NORMAL);
        }
    }
    // The camera reads about x 22 to 58 and y 13 to 48: it sees where these
    // end.
    let (extent, changed) = ([25, 15, 50, 45], [30, 20, 40, 30]);
    let camera = [0.4, 0.3, 20.25, -0.3, 0.4, 30.5, 0.0, 0.0, 1.0];
    let (size, rect) = ((64, 48), [3u32, 2, 60, 47]);
    // SAFETY: the extent holds four words.
    let screen = unsafe { gpu_engine_screen_new(extent.as_ptr(), 1.0) };
    assert!(!screen.is_null(), "{}", last_error());
    let mut in_rust = Screen::new(extent, 1.0).expect("screen");
    let in_rust_camera = Camera { inverse: camera, scale: 2.0, mode: ResampleMode::Nearest, size };
    let shown = surface(size, wgpu::TextureFormat::Rgba8Unorm);
    let mut screens = Vec::new();
    for (laid, over) in [(plan, extent), (again, changed)] {
        // SAFETY: every pointer is live and made on `engine`; each array
        // holds what its call reads.
        let passes = unsafe {
            assert!(gpu_engine_screen_compose(screen, composite, engine, &pool, laid, over.as_ptr()), "{}", last_error());
            gpu_engine_screen_show(screen, composite, engine, camera.as_ptr(), 2.0, NEAREST, 64, 48, &shown, rect.as_ptr())
        };
        assert!(passes >= 1, "{}", last_error());
        // SAFETY: `laid` is live.
        let planned = unsafe { &*laid };
        let chains = planned.chained();
        let laid = planned.plan(pool.pages(), &chains);
        in_rust.compose(engine, composite, &laid, over, composite.widest()).expect("compose");
        let want = surface(size, wgpu::TextureFormat::Rgba8Unorm);
        in_rust.show(engine, composite, in_rust_camera, &want, rect, composite.widest()).expect("show");
        assert!(engine.read_texture(&shown) == engine.read_texture(&want), "over {over:?}");
        screens.push(engine.read_texture(&shown));
    }
    assert!(screens[0] != screens[1], "the plan composed again shows a canvas of its own");
    // SAFETY: as above.
    let refused =
        unsafe { gpu_engine_screen_show(screen, composite, engine, IDENTITY.as_ptr(), 1.0, 2, 64, 48, &shown, rect.as_ptr()) };
    assert_eq!((refused, last_error()), (-1, "no sampling has id 2".to_string()));
    // SAFETY: none is used again.
    unsafe {
        gpu_engine_screen_free(screen);
        gpu_engine_plan_free(plan);
        gpu_engine_plan_free(again);
    }
}
