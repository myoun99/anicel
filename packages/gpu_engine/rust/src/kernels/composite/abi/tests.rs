//! The executor's C ABI on a real GPU: a plan built call by call composites
//! as the same plan built in Rust, shown onto a surface it lays the pixels a
//! run puts, a screen composes and shows as one built in Rust does, as a
//! range's mark under the mask the app keeps does, a row or a mark whose
//! pose lands nothing is left out, and what is refused says why.

use super::*;
use crate::kernels::blend::mode::{MULTIPLY, NORMAL, SCREEN};
use crate::kernels::composite::tests::{mix, pixel_at, rig, surface, surface_on};
use crate::kernels::composite::kept::tests::A_REST_S_FOLDS;
use crate::kernels::composite::{NO_TILE, TILE, TILE_TEXELS, TileAt};
use crate::kernels::fold::Fold;
use crate::kernels::mask::tests::masked;
use crate::kernels::pool::folded_tests::{self, scrubbed, settled};
use crate::kernels::pool::{Pool, gpu_engine_pool_release, gpu_engine_pool_store};
use crate::kernels::shared::le_bytes;
use crate::platform::{gpu_engine_surface_free, gpu_engine_surface_new};
use crate::testing::{a_device_of_its_own, done_here, first_engine, last_error, read_buffer, stored};

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

/// A plan of no steps, the tests' engine's to let go of.
fn planned() -> *mut Planned {
    // SAFETY: the engine is live.
    unsafe { gpu_engine_plan_new(first_engine()) }
}

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
    mask: Option<&Mask>,
) -> Vec<u8> {
    let (engine, composite) = (rig().engine, &rig().composite);
    let plan = Plan { pages: pool.pages(), sets, keys, matrices, chains, steps, mask, stamps: None };
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
    let plan = planned();
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
    assert_eq!(built, ran_in_rust(&pool, &sets, &[], &matrices, &[], &steps, None));
}

// A row copied over nothing lays its stored bytes, tile for tile in the
// order asked — what the app reads a cel's tiles back by.
#[test]
fn a_row_copied_over_nothing_lays_the_bytes_stored() {
    let tiles = [tile(4, false), tile(5, false), tile(6, false)];
    let (pool, at) = stored(&tiles);
    let plan = planned();
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
    let plan = planned();
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
        .map(|bgra| (unsafe { gpu_engine_surface_new(engine, 3 * TILE, TILE, bgra, true) }, bgra))
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
    let nowhere = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0];
    let plan = planned();
    // SAFETY: `plan` is live and `nowhere` holds nine.
    let added = unsafe { gpu_engine_plan_row(plan, 0, -1, -1, -1, nowhere.as_ptr(), 1.0, BLEND, TILE, TILE, 65535, NORMAL) };
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
    let plan = planned();
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
    let plan = planned();
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
            held: None,
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
            held: None,
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
    assert_eq!(built, ran_in_rust(&pool, &sets, &keys, &[], &chains, &steps, None));
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
    let laid = planned();
    let plan = planned();
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
        held: None,
    }];
    let steps = [row(0, None, Some(0), map(IDENTITY, ResampleMode::Blend), 65535, NORMAL)];
    assert_eq!(built, ran_in_rust(&pool, &sets, &[], &[], &chains, &steps, None));
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
    let plan = planned();
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

// A chain held call by call is laid from its hold while that keeps what it
// put: a plan over other tiles naming the same number lays it, until the
// hold lets it go. The bytes it keeps are counted; holding a chain the plan
// has not says why, and the hold frees.
#[test]
fn a_chain_held_call_by_call_lays_what_its_hold_keeps() {
    let tiles = [tile(7, true), tile(8, true), tile(9, true), tile(4, true), tile(5, true), tile(6, true)];
    let (pool, at) = stored(&tiles);
    let contrast: [f64; MATRIX_WORDS] = [
        1.4, 0.0, 0.0, 0.0, -20.0, 0.0, 1.2, 0.1, 0.0, 5.0, 0.0, 0.0, 0.8, 0.0, 30.0, 0.0, 0.0, 0.0, 1.0, 0.0,
    ];
    // SAFETY: the engine is live.
    let held = unsafe { gpu_engine_held_new(first_engine()) };
    let ran_from = |first: usize| {
        let words = [at[first].word(), at[first + 1].word(), at[first + 2].word()];
        let plan = planned();
        // SAFETY: `plan` and `held` are live; each array holds what its call
        // reads.
        unsafe {
            gpu_engine_plan_set(plan, 0, 0, 3, 1, words.as_ptr());
            gpu_engine_plan_chain(plan, 0, 0, 3, 1);
            assert_eq!(gpu_engine_plan_chain_matrix(plan, 0, contrast.as_ptr()), 0);
            assert_eq!(gpu_engine_plan_chain_held(plan, 0, held, 11), 0);
            gpu_engine_plan_row(plan, 0, -1, -1, 0, IDENTITY.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 65535, NORMAL);
        }
        let ran = ran(&pool, plan, NO_EDGE).unwrap_or_else(|| panic!("{}", last_error()));
        // SAFETY: `plan` came from `gpu_engine_plan_new`.
        unsafe { gpu_engine_plan_free(plan) };
        ran
    };
    let first = ran_from(0);
    // What the chain put is one of the engine's spares: of its three
    // tiles, or of more where another test here left one.
    // SAFETY: `held` is live.
    let kept = unsafe { gpu_engine_held_bytes_of(held, 11) };
    assert!(kept >= 3 * TILE_BYTES);
    assert!(gpu_engine_held_bytes() >= kept);
    assert_eq!(ran_from(3), first, "what it put laid");
    // 🚨Let go of on the engine's thread in turn, its caller waiting for
    // none of it (`device::posted_of` has why): still kept while a body
    // ahead has that thread, and gone once the thread has come to it.
    let (lets, released) = std::sync::mpsc::channel::<()>();
    let (began, begun) = std::sync::mpsc::channel();
    std::thread::scope(|scope| {
        scope.spawn(move || {
            first_engine().on_thread(|| {
                let _ = began.send(());
                let _ = released.recv_timeout(std::time::Duration::from_secs(20));
            })
        });
        begun.recv().expect("the body ahead began");
        // SAFETY: `held` is live.
        unsafe { gpu_engine_held_let_go(held, 11) };
        // SAFETY: `held` is live.
        let so_far = unsafe { gpu_engine_held_bytes_of(held, 11) };
        let _ = lets.send(());
        assert_eq!(so_far, kept, "waited for, or let go of ahead of its turn");
    });
    assert_eq!(done_here(first_engine()), Ok(()));
    // SAFETY: `held` is live.
    assert_eq!(unsafe { gpu_engine_held_bytes_of(held, 11) }, 0);
    assert_ne!(ran_from(3), first, "let go, it runs");
    let plan = planned();
    // SAFETY: `plan` and `held` are live, each freed once.
    unsafe {
        assert_eq!(gpu_engine_plan_chain_held(plan, 0, held, 11), -1);
        assert!(last_error().contains("no effect chain 0"), "{}", last_error());
        gpu_engine_plan_free(plan);
        gpu_engine_held_free(held);
    }
}

// A screen composed and shown call by call is the screen built in Rust over
// the same plan: a posed row laid on the canvas at its own pixels over an
// extent the camera's view cuts, then the camera magnifying it 2× and
// turned past a quarter pixel — and so again after another plan composed
// where it changed. A sampling no mode has is refused, the done after it
// saying why, and the screen frees.
#[test]
fn a_screen_composed_and_shown_call_by_call_is_the_screen_in_rust() {
    let tiles = [tile(11, true), tile(12, false)];
    let (pool, at) = stored(&tiles);
    let (engine, composite) = (rig().engine, &rig().composite);
    let (plan, again) = (planned(), planned());
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
    let camera = [0.4, 0.3, 20.25, -0.3, 0.4, 30.5];
    let (size, rect) = ((64, 48), [3u32, 2, 60, 47]);
    // SAFETY: the engine is live, and the extent holds four words.
    let screen = unsafe { gpu_engine_screen_new(first_engine(), extent.as_ptr(), 1.0) };
    assert!(!screen.is_null(), "{}", last_error());
    let mut in_rust = Screen::new(extent, 1.0).expect("screen");
    let in_rust_camera = Camera { inverse: camera, mode: ResampleMode::Nearest };
    let shown = surface(size, wgpu::TextureFormat::Rgba8Unorm);
    let mut screens = Vec::new();
    for (laid, over) in [(plan, extent), (again, changed)] {
        // SAFETY: every pointer is live and made on `engine`; each array
        // holds what its call reads.
        unsafe {
            gpu_engine_screen_compose(screen, composite, engine, &pool, laid, over.as_ptr());
            gpu_engine_screen_show(screen, composite, engine, camera.as_ptr(), NEAREST, &shown, rect.as_ptr());
        }
        done_here(engine).expect("composed and shown");
        // SAFETY: `laid` is live.
        let planned = unsafe { &*laid };
        planned
            .laid(&pool, |laid| in_rust.compose(engine, composite, laid, over, composite.widest()))
            .expect("compose");
        let want = surface(size, wgpu::TextureFormat::Rgba8Unorm);
        in_rust.show(engine, composite, in_rust_camera, &want, rect, composite.widest()).expect("show");
        assert!(engine.read_texture(&shown) == engine.read_texture(&want), "over {over:?}");
        screens.push(engine.read_texture(&shown));
    }
    assert!(screens[0] != screens[1], "the plan composed again shows a canvas of its own");
    // SAFETY: as above.
    unsafe { gpu_engine_screen_show(screen, composite, engine, camera.as_ptr(), 2, &shown, rect.as_ptr()) };
    let refused = "a body handed over unwaited failed: no sampling has id 2";
    assert_eq!(done_here(engine), Err(refused.to_string()));
    // SAFETY: none is used again.
    unsafe {
        gpu_engine_screen_free(screen);
        gpu_engine_plan_free(plan);
        gpu_engine_plan_free(again);
    }
}

// A buffer closed as a row call by call — over its own tiles through a
// matrix, and over a chain's through it — composites as the same plan
// built in Rust: each field in its place, its pose sampled as a row's is,
// Blend's radius among them.
#[test]
fn a_buffer_closed_as_a_row_call_by_call_composites_as_one_built_in_rust() {
    let tiles = [tile(1, false), tile(2, false), tile(3, true)];
    let (pool, at) = stored(&tiles);
    let contrast: [f64; MATRIX_WORDS] = [
        1.4, 0.0, 0.0, 0.0, -20.0, 0.0, 1.2, 0.1, 0.0, 5.0, 0.0, 0.0, 0.8, 0.0, 30.0, 0.0, 0.0, 0.0, 1.0, 0.0,
    ];
    let warm: [f64; MATRIX_WORDS] = [
        1.0, 0.0, 0.0, 0.0, 25.0, 0.0, 0.9, 0.0, 0.0, 0.0, 0.0, 0.0, 0.7, 0.0, -10.0, 0.0, 0.0, 0.0, 1.0, 0.0,
    ];
    let own = [0, 0, 2, 1];
    let plan = planned();
    // SAFETY: `plan` is live; each array holds what its call reads.
    unsafe {
        assert_eq!(gpu_engine_plan_set(plan, 0, 0, 2, 1, [at[0].word(), at[1].word()].as_ptr()), 0);
        assert_eq!(gpu_engine_plan_set(plan, 1, 0, 1, 1, [at[2].word()].as_ptr()), 1);
        assert_eq!(gpu_engine_plan_matrix(plan, warm.as_ptr()), 0);
        assert_eq!(gpu_engine_plan_chain(plan, 0, 0, 3, 1), 0);
        assert_eq!(gpu_engine_plan_chain_matrix(plan, 0, contrast.as_ptr()), 0);
        assert_eq!(gpu_engine_plan_row(plan, 0, -1, -1, -1, IDENTITY.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 65535, NORMAL), 1);
        gpu_engine_plan_open(plan, false);
        assert_eq!(gpu_engine_plan_row(plan, 0, -1, -1, -1, IDENTITY.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 65535, NORMAL), 1);
        assert_eq!(gpu_engine_plan_row(plan, 1, -1, -1, -1, OVER.as_ptr(), 1.0, NEAREST, 3 * TILE, TILE, 30000, MULTIPLY), 1);
        let closed = gpu_engine_plan_close_row(plan, -1, own.as_ptr(), 0, POSED.as_ptr(), 2.0, BLEND, 3 * TILE, TILE, 41000, SCREEN);
        assert_eq!(closed, 1);
        gpu_engine_plan_open(plan, false);
        assert_eq!(gpu_engine_plan_row(plan, 1, -1, -1, -1, IDENTITY.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 65535, NORMAL), 1);
        let closed = gpu_engine_plan_close_row(plan, 0, std::ptr::null(), -1, OVER.as_ptr(), 1.0, NEAREST, 3 * TILE, TILE, 50000, MULTIPLY);
        assert_eq!(closed, 1);
    }
    let sets = [
        TileSet { x0: 0, y0: 0, columns: 2, rows: 1, tiles: vec![Some(at[0]), Some(at[1])] },
        TileSet { x0: 1, y0: 0, columns: 1, rows: 1, tiles: vec![Some(at[2])] },
    ];
    let identity = map(IDENTITY, ResampleMode::Blend);
    let posed = ResampleMap::new(POSED, 2.0, ResampleMode::Blend, 3 * TILE, TILE).expect("lands");
    let steps = [
        row(0, None, None, identity, 65535, NORMAL),
        Step::Open,
        row(0, None, None, identity, 65535, NORMAL),
        row(1, None, None, map(OVER, ResampleMode::Nearest), 30000, MULTIPLY),
        Step::CloseRow {
            over: Over::Tiles(TileRect { x0: 0, y0: 0, columns: 2, rows: 1 }),
            map: posed,
            matrix: Some(0),
            opacity: 41000,
            mode: SCREEN,
        },
        Step::Open,
        row(1, None, None, identity, 65535, NORMAL),
        Step::CloseRow {
            over: Over::Chain(0),
            map: map(OVER, ResampleMode::Nearest),
            matrix: None,
            opacity: 50000,
            mode: MULTIPLY,
        },
    ];
    let chains = [Chained {
        ops: vec![Op::Matrix(matrix_words(&contrast).expect("held"))],
        rect: TileRect { x0: 0, y0: 0, columns: 3, rows: 1 },
        held: None,
    }];
    let matrices = [matrix_words(&warm).expect("held")];
    let built = ran(&pool, plan, [0, 0, 300, 120]).unwrap_or_else(|| panic!("{}", last_error()));
    // SAFETY: `plan` came from `gpu_engine_plan_new`.
    unsafe { gpu_engine_plan_free(plan) };
    assert_eq!(built, ran_in_rust(&pool, &sets, &[], &matrices, &chains, &steps, None));
}

// A buffer closed as a row whose pose lands nothing lays nothing, as such
// a row is left out: it is taken out with its steps — a buffer closed in it
// among them — and what came before it stays.
#[test]
fn a_buffer_closed_as_a_row_whose_pose_lands_nothing_is_taken_out() {
    let nowhere = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0];
    let own = [0, 0, 1, 1];
    let plan = planned();
    // SAFETY: `plan` is live; each array holds what its call reads.
    unsafe {
        gpu_engine_plan_solid(plan, 0xff00_00ff, 0, 0, 10, 10);
        gpu_engine_plan_open(plan, false);
        gpu_engine_plan_open(plan, false);
        gpu_engine_plan_row(plan, 0, -1, -1, -1, IDENTITY.as_ptr(), 1.0, BLEND, TILE, TILE, 65535, NORMAL);
        gpu_engine_plan_close(plan, 65535, NORMAL, -1, -1, 65535);
        gpu_engine_plan_row(plan, 0, -1, -1, -1, IDENTITY.as_ptr(), 1.0, BLEND, TILE, TILE, 65535, NORMAL);
        let closed = gpu_engine_plan_close_row(plan, -1, own.as_ptr(), -1, nowhere.as_ptr(), 1.0, BLEND, TILE, TILE, 65535, NORMAL);
        assert_eq!(closed, 0);
        assert!(matches!((&(*plan).steps)[..], [Step::Solid { .. }]), "{:?}", &(*plan).steps);
        gpu_engine_plan_free(plan);
    }
}

// What a row's close cannot add it refuses with a reason, adding nothing:
// a chain and tiles both or neither, tiles of no size there is, a sampling
// no mode has, no buffer open.
#[test]
fn what_a_row_s_close_refuses_says_why() {
    let (own, negative) = ([0, 0, 1, 1], [0, 0, -1, 1]);
    let plan = planned();
    let close = |chain, tiles: *const i32, sampling| {
        // SAFETY: `plan` is live; `tiles` is null or holds four words.
        unsafe {
            gpu_engine_plan_close_row(plan, chain, tiles, -1, IDENTITY.as_ptr(), 1.0, sampling, TILE, TILE, 65535, NORMAL)
        }
    };
    assert_eq!(close(-1, own.as_ptr(), BLEND), -1);
    assert!(last_error().contains("no buffer"), "{}", last_error());
    // SAFETY: `plan` is live.
    unsafe { gpu_engine_plan_open(plan, false) };
    assert_eq!(close(0, own.as_ptr(), BLEND), -1);
    assert!(last_error().contains("one"), "{}", last_error());
    assert_eq!(close(-1, std::ptr::null(), BLEND), -1);
    assert!(last_error().contains("one"), "{}", last_error());
    assert_eq!(close(-1, negative.as_ptr(), BLEND), -1);
    assert!(last_error().contains("-1 × 1"), "{}", last_error());
    assert_eq!(close(-1, own.as_ptr(), 2), -1);
    assert!(last_error().contains("sampling"), "{}", last_error());
    // SAFETY: `plan` is live, then freed.
    unsafe {
        assert!(matches!((&(*plan).steps)[..], [Step::Open]));
        gpu_engine_plan_free(plan);
    }
}

/// A range's cover at the canvas pixel (x, y): soft, each byte its own,
/// with a hole.
fn cover(x: i32, y: i32) -> u8 {
    match (x - 60).abs() < 9 && y < 20 {
        true => 0,
        false => (x * 37 + y * 11).rem_euclid(256) as u8 | 1,
    }
}

// A range's mark built call by call — its mask made of the bytes the app
// holds, a byte a pixel row after row, a row of 203 of them padded to
// whole words — over a row, posed and pushed, composites as the same plan
// built in Rust under the same mask: each byte in its place, Blend's
// radius among the pose's fields.
#[test]
fn a_mark_built_call_by_call_composites_as_one_built_in_rust() {
    let (pool, at) = stored(&[tile(4, true), tile(5, true)]);
    let (left, top, width, height) = (5, 3, 203, 70);
    let bytes: Vec<u8> =
        (0..height).flat_map(|y| (0..width).map(move |x| cover(left + x, top + y))).collect();
    let shift = [3 << 16 | 0x8000, -(2 << 16)];
    let plan = planned();
    // SAFETY: the engine is live and `bytes` holds `width × height`.
    let mask = unsafe { gpu_engine_mask_new(rig().engine, bytes.as_ptr(), left, top, width as u32, height as u32) };
    assert!(!mask.is_null(), "{}", last_error());
    // SAFETY: `plan` and `mask` are live; each array holds what its call
    // reads.
    unsafe {
        gpu_engine_plan_set(plan, 0, 0, 2, 1, [at[0].word(), at[1].word()].as_ptr());
        gpu_engine_plan_row(plan, 0, -1, -1, -1, POSED.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 65535, NORMAL);
        assert_eq!(gpu_engine_plan_mark(plan, POSED.as_ptr(), 2.0, BLEND, 3 * TILE, TILE, shift[0], shift[1]), 1);
        assert_eq!(gpu_engine_plan_mask(plan, mask), 0);
    }
    let built = ran(&pool, plan, [0, 0, 300, 120]).unwrap_or_else(|| panic!("{}", last_error()));
    // SAFETY: neither is used again.
    unsafe {
        gpu_engine_plan_free(plan);
        gpu_engine_mask_free(mask);
    }
    let sets = [TileSet { x0: 0, y0: 0, columns: 2, rows: 1, tiles: vec![Some(at[0]), Some(at[1])] }];
    let posed = ResampleMap::new(POSED, 2.0, ResampleMode::Blend, 3 * TILE, TILE).expect("lands");
    let steps = [row(0, None, None, map(POSED, ResampleMode::Blend), 65535, NORMAL), Step::Mark { map: posed, shift }];
    let range = masked((left, top), (width as u32, height as u32), cover);
    let want = ran_in_rust(&pool, &sets, &[], &[], &[], &steps, Some(&range.mask()));
    assert_eq!(built, want);
    // Not evidence — that the mark lays something over the row at all.
    assert_ne!(want, ran_in_rust(&pool, &sets, &[], &[], &[], &steps[..1], None));
}

// A mark whose pose lands nothing lays nothing, as such a row: it is left
// out.
#[test]
fn a_mark_whose_pose_lands_nothing_is_left_out() {
    let nowhere = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0];
    let plan = planned();
    // SAFETY: `plan` is live and `nowhere` holds nine; then it is freed.
    unsafe {
        assert_eq!(gpu_engine_plan_mark(plan, nowhere.as_ptr(), 1.0, BLEND, TILE, TILE, 0, 0), 0);
        assert!((*plan).steps.is_empty());
        gpu_engine_plan_free(plan);
    }
}

// What a mark's calls cannot do they refuse with a reason: a mask of no
// pixel, a second mask for one plan — the first kept —, a sampling no mode
// has.
#[test]
fn what_a_mark_refuses_says_why() {
    let bytes = [255u8; 4];
    // SAFETY: the engine is live and `bytes` holds what each call reads.
    let none = unsafe { gpu_engine_mask_new(rig().engine, bytes.as_ptr(), 0, 0, 0, 4) };
    assert!(none.is_null());
    assert!(last_error().contains("no pixel"), "{}", last_error());
    // SAFETY: as above.
    let (mask, other) = unsafe {
        (
            gpu_engine_mask_new(rig().engine, bytes.as_ptr(), 0, 0, 2, 2),
            gpu_engine_mask_new(rig().engine, bytes.as_ptr(), 9, 9, 4, 1),
        )
    };
    assert!(!mask.is_null() && !other.is_null(), "{}", last_error());
    let plan = planned();
    // SAFETY: every pointer is live and `IDENTITY` holds nine; then each is
    // freed.
    unsafe {
        assert_eq!(gpu_engine_plan_mask(plan, mask), 0);
        assert_eq!(gpu_engine_plan_mask(plan, other), -1);
        assert!(last_error().contains("one mask"), "{}", last_error());
        assert_eq!((*plan).mask.as_ref().map(|kept| kept.at), Some((0, 0)));
        assert_eq!(gpu_engine_plan_mark(plan, IDENTITY.as_ptr(), 1.0, 2, TILE, TILE, 0, 0), -1);
        assert!(last_error().contains("sampling"), "{}", last_error());
        assert!((*plan).steps.is_empty());
        gpu_engine_plan_free(plan);
        gpu_engine_mask_free(mask);
        gpu_engine_mask_free(other);
    }
}

// A plug-in's step names the plan's tile sets: the rows its read keeps,
// by slot, and what its put lays — a set the plan has not is refused, by
// its number, and adds no op.
#[test]
fn a_read_and_a_put_name_the_plans_tile_sets() {
    let plan = planned();
    // SAFETY: `plan` and `read` are live; each slice holds what its count
    // says.
    unsafe {
        let set = gpu_engine_plan_set(plan, 0, 0, 1, 1, [NO_TILE].as_ptr());
        let chain = gpu_engine_plan_chain(plan, 0, 0, 1, 1);
        let read = gpu_engine_chain_read_new(first_engine());
        assert_eq!(gpu_engine_plan_chain_read(plan, chain, read, [set, set].as_ptr(), 2), 0);
        assert_eq!(gpu_engine_plan_chain_put(plan, chain, set), 0);
        assert_eq!(gpu_engine_plan_chain_put(plan, chain, set + 1), -1);
        assert_eq!(last_error(), "no tile set 1 of 1");
        assert_eq!(gpu_engine_plan_chain_read(plan, chain, read, [set, set + 1].as_ptr(), 2), -1);
        assert_eq!(last_error(), "no tile set 1 of 1");
        match &(&(*plan).chains)[0].ops[..] {
            [(Op::Read { rows, .. }, None), (Op::Put(put), None)] => {
                assert_eq!(rows, &[set, set]);
                assert_eq!(*put, set);
            }
            _ => panic!("chain 0 holds other than its read and its put"),
        }
        gpu_engine_chain_read_free(read);
        gpu_engine_plan_free(plan);
    }
}

/// A plan of one row laying the tiles at `at` side by side, whole and
/// unposed, on `engine`, and the pixels they cover.
///
/// # Safety
/// `engine` is live; the plan is let go of once.
unsafe fn side_by_side(engine: &Engine, at: &[TileAt]) -> (*mut Planned, [i32; 4]) {
    let (words, count) = (at.iter().map(|at| at.word()).collect::<Vec<_>>(), at.len() as u32);
    // SAFETY: the engine is live, and each array holds what its call reads.
    unsafe {
        let plan = gpu_engine_plan_new(engine);
        gpu_engine_plan_set(plan, 0, 0, count, 1, words.as_ptr());
        gpu_engine_plan_row(plan, 0, -1, -1, -1, IDENTITY.as_ptr(), 1.0, BLEND, count * TILE, TILE, 65535, NORMAL);
        (plan, [0, 0, (count * TILE) as i32, TILE as i32])
    }
}

/// `screen` shown whole, a canvas pixel a pixel, by the C ABI — and, for
/// `in_rust`, a screen composed of `plan` in Rust shown so: told by
/// nothing, every tile of it made.
struct Shown<'a> {
    engine: &'a Engine,
    composite: &'a Composite,
    extent: [i32; 4],
}

impl Shown<'_> {
    const CAMERA: [f64; 6] = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0];

    fn rect(&self) -> [u32; 4] {
        [0, 0, self.extent[2] as u32, self.extent[3] as u32]
    }

    fn surface(&self) -> wgpu::Texture {
        surface_on(self.engine, (self.extent[2] as u32, self.extent[3] as u32), wgpu::TextureFormat::Rgba8Unorm)
    }

    /// # Safety
    /// `screen` is live, made on the engine.
    unsafe fn by_the_abi(&self, screen: *const Arc<ScreenAndBytes>) -> Vec<u8> {
        let (texture, rect) = (self.surface(), self.rect());
        // SAFETY: every pointer is live; each array holds what its call reads.
        unsafe {
            let camera = Self::CAMERA.as_ptr();
            gpu_engine_screen_show(screen, self.composite, self.engine, camera, NEAREST, &texture, rect.as_ptr());
        }
        done_here(self.engine).expect("shown");
        self.engine.read_texture(&texture).expect("read the surface back")
    }

    fn in_rust(&self, pool: &Pool, plan: &Planned) -> Vec<u8> {
        let widest = self.composite.widest();
        let mut screen = Screen::new(self.extent, 1.0).expect("screen");
        plan.laid(pool, |laid| screen.compose(self.engine, self.composite, laid, self.extent, widest)).expect("compose");
        let texture = self.surface();
        let camera = Camera { inverse: Self::CAMERA, mode: ResampleMode::Nearest };
        screen.show(self.engine, self.composite, camera, &texture, self.rect(), widest).expect("show");
        self.engine.read_texture(&texture).expect("read the surface back")
    }
}

// Two screens composed call by call of one plan hold one tile for the same
// input (F-610): the second weighs nothing, and shows what a screen of the
// plan made whole in Rust shows — as does a third composed over the first
// as its film, every tile of it fresh; the first let go, its tiles are
// counted as nobody's own for as long as another holds them. On an engine
// of its own: the tests' one keeps every test's pictures.
#[test]
fn screens_composed_of_the_same_hold_one_tile_weighed_once() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let composite = Composite::new(&engine).expect("its executor");
    let mut pool = Pool::new(&engine, u64::MAX).expect("pool");
    let cel = pool.cel();
    let at = pool.store(&engine, cel, &[&tile(21, true), &tile(22, false)]).expect("store");
    // SAFETY: the engine is live through every call, and what is made on
    // it is let go of once.
    unsafe {
        let (plan, extent) = side_by_side(&engine, &at);
        let shown = Shown { engine: &engine, composite: &composite, extent };
        let screens = [(); 2].map(|()| gpu_engine_screen_new(&engine, extent.as_ptr(), 1.0));
        for screen in screens {
            gpu_engine_screen_compose(screen, &composite, &engine, &pool, plan, extent.as_ptr());
        }
        done_here(&engine).expect("composed");
        let weighed = || {
            let unowned = gpu_engine_pictures_unowned_bytes(&engine);
            [gpu_engine_screen_bytes(screens[0]), gpu_engine_screen_bytes(screens[1]), unowned].map(|bytes| bytes / TILE_BYTES)
        };
        assert_eq!(weighed(), [2, 0, 0], "the second holds the first's two, and weighs none");
        assert!(shown.by_the_abi(screens[1]) == shown.in_rust(&pool, &*plan), "against it made whole");
        let over = gpu_engine_screen_new(&engine, extent.as_ptr(), 1.0);
        gpu_engine_screen_compose_over(over, screens[0], &composite, &engine, &pool, plan, extent.as_ptr());
        done_here(&engine).expect("composed over");
        assert_eq!(gpu_engine_screen_bytes(over), 0, "over a film, a fresh tile made of the same is held as well");
        assert!(shown.by_the_abi(over) == shown.in_rust(&pool, &*plan), "against it made whole");
        gpu_engine_screen_free(over);
        gpu_engine_screen_free(screens[0]);
        done_here(&engine).expect("let go");
        assert_eq!(weighed()[1..], [0, 2], "the first let go: its two are nobody's own, held still");
        gpu_engine_screen_free(screens[1]);
        done_here(&engine).expect("let go");
        assert_eq!(gpu_engine_pictures_unowned_bytes(&engine), 0, "nobody holds them");
        gpu_engine_plan_free(plan);
    }
}

// A screen no body comes to after a rest weighs its picture as it lies
// all the same (F-610): of two composed of the same, the one that made
// the tiles tells what the pool keeps made for them once the rest's folds
// are through — by the C ABI alone, as the app's budgets read it —, and
// let go, they are nobody's own as they lie. On an engine of its own, its
// pictures on pages of two tiles: the picture fills a page, and a rest
// folds every tile of it.
#[test]
fn a_screen_is_weighed_as_its_tiles_lie_once_a_rest_s_folds_are_through() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    engine.pictures.paged_by(2);
    let composite = Composite::new(&engine).expect("its executor");
    let mut pool = Pool::new(&engine, u64::MAX).expect("pool");
    let cel = pool.cel();
    let (a, b) = (folded_tests::tile(21, 1), folded_tests::tile(22, 2));
    let at = pool.store(&engine, cel, &[&a, &b]).expect("store");
    engine.on_thread(|| Fold::new(&engine)).expect("the fold's kernels");
    // SAFETY: the engine is live through every call, and what is made on
    // it is let go of once.
    unsafe {
        let (plan, extent) = side_by_side(&engine, &at);
        let screens = [(); 2].map(|()| gpu_engine_screen_new(&engine, extent.as_ptr(), 1.0));
        for screen in screens {
            gpu_engine_screen_compose(screen, &composite, &engine, &pool, plan, extent.as_ptr());
        }
        done_here(&engine).expect("composed");
        let weighed = || screens.map(|screen| gpu_engine_screen_bytes(screen));
        assert_eq!(weighed(), [2 * TILE_BYTES, 0], "the premise: as they were made");
        let rest = folded_tests::numbered();
        gpu_engine_pictures_rest(&engine, folded_tests::told, rest);
        let told = folded_tests::told_within(rest, A_REST_S_FOLDS);
        assert_eq!(told, Some(true), "the rest tells its caller the pictures were weighed again");
        let folded = engine.pictures.held_bytes();
        assert!(folded < TILE_BYTES, "the premise: both fold small, their page away — {folded}");
        assert_eq!(weighed(), [folded, 0], "told by the rest, no body come to it");
        gpu_engine_screen_free(screens[0]);
        done_here(&engine).expect("let go");
        let nobody_s = gpu_engine_pictures_unowned_bytes(&engine);
        assert_eq!((gpu_engine_screen_bytes(screens[1]), nobody_s), (0, folded), "nobody's own, as they lie");
        gpu_engine_screen_free(screens[1]);
        gpu_engine_plan_free(plan);
        done_here(&engine).expect("let go");
    }
}

// A plan is weighed call by call as the tiles a screen composed of it then
// comes to weigh (F-610), on the engine's thread in its turn: nothing is
// weighed as the call returns; with nothing kept, every tile of it; behind
// a compose of the same handed over before it — still on its way as the
// weigh is called —, none, that picture kept by the time it is weighed;
// and the screen let go, every tile again. On an engine of its own: the
// tests' one keeps every test's pictures.
#[test]
fn a_plan_is_weighed_on_the_engines_thread_behind_what_was_composed_before_it() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let composite = Composite::new(&engine).expect("its executor");
    let mut pool = Pool::new(&engine, u64::MAX).expect("pool");
    let cel = pool.cel();
    let at = pool.store(&engine, cel, &[&tile(21, true), &tile(22, false)]).expect("store");
    // What is handed over from here waits behind this, in its order, till
    // what it returns is sent to.
    let held = |engine: &Engine| {
        let (open, shut) = std::sync::mpsc::channel::<()>();
        engine.posted(move || shut.recv().ok());
        open
    };
    // SAFETY: the engine is live through every call, and what is made on
    // it is let go of once.
    unsafe {
        let (plan, extent) = side_by_side(&engine, &at);
        let told = || std::mem::take(&mut *WEIGHS_TOLD.lock().unwrap_or_else(PoisonError::into_inner));
        assert_eq!(gpu_engine_plan_weighed(plan), -1, "before any weigh");
        let open = held(&engine);
        gpu_engine_plan_weigh(plan, &engine, &pool, extent.as_ptr(), told_a_weigh, 7);
        assert_eq!((gpu_engine_plan_weighed(plan), told()), (-1, vec![]), "nothing is weighed on its caller's thread");
        open.send(()).expect("the engine's thread waits");
        done_here(&engine).expect("weighed");
        assert_eq!((gpu_engine_plan_weighed(plan), told()), (2, vec![(7, true)]), "nothing kept: its two tiles");
        let screen = gpu_engine_screen_new(&engine, extent.as_ptr(), 1.0);
        let open = held(&engine);
        gpu_engine_screen_compose(screen, &composite, &engine, &pool, plan, extent.as_ptr());
        gpu_engine_plan_weigh(plan, &engine, &pool, extent.as_ptr(), told_a_weigh, 8);
        assert_eq!(gpu_engine_screen_bytes(screen), 0, "premise: the compose is on its way still");
        open.send(()).expect("the engine's thread waits");
        done_here(&engine).expect("composed and weighed");
        assert_eq!(gpu_engine_screen_bytes(screen), 2 * TILE_BYTES, "premise: the picture is kept");
        assert_eq!(
            (gpu_engine_plan_weighed(plan), told()),
            (0, vec![(8, true)]),
            "behind the compose: its picture's tiles are held"
        );
        gpu_engine_screen_free(screen);
        gpu_engine_plan_weigh(plan, &engine, &pool, extent.as_ptr(), told_a_weigh, 9);
        done_here(&engine).expect("let go and weighed");
        assert_eq!((gpu_engine_plan_weighed(plan), told()), (2, vec![(9, true)]), "its picture let go: made again");
        gpu_engine_plan_free(plan);
        done_here(&engine).expect("let go");
    }
}

extern "C" fn told_nothing(_: u64, _: bool) {}

/// The weighs told, each by its number and whether it weighed: what the
/// engine's thread calls ([`gpu_engine_plan_weigh`]).
static WEIGHS_TOLD: Mutex<Vec<(u64, bool)>> = Mutex::new(Vec::new());

extern "C" fn told_a_weigh(number: u64, weighed: bool) {
    WEIGHS_TOLD.lock().unwrap_or_else(PoisonError::into_inner).push((number, weighed));
}

// A compose is told by the pool's stamps as they stood when it was called
// (🚨 on `gpu_engine_screen_compose`): a slot it names, let go and stored
// into again before it runs — the store's put handed over behind it, as
// the app's is —, is read as it was. The compose called after the store,
// of the same plan, is told apart from it and shows the tile stored: told
// by the stamps as they stand when each runs, both would be the one tile.
#[test]
fn a_compose_is_told_by_the_stamps_as_it_was_called() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let composite = Composite::new(&engine).expect("its executor");
    let mut pool = Pool::new(&engine, u64::MAX).expect("pool");
    let cel = pool.cel();
    let at = pool.store(&engine, cel, &[&tile(31, true)]).expect("store");
    let next = tile(32, true);
    // SAFETY: the engine is live through every call, what is made on it is
    // let go of once, and `next` outlives the store's put.
    unsafe {
        let (plan, extent) = side_by_side(&engine, &at);
        let shown = Shown { engine: &engine, composite: &composite, extent };
        let screens = [(); 2].map(|()| gpu_engine_screen_new(&engine, extent.as_ptr(), 1.0));
        let before = shown.in_rust(&pool, &*plan);
        // The engine's thread held: what is handed over from here waits
        // behind this, in its order.
        let (open, shut) = std::sync::mpsc::channel::<()>();
        engine.posted(move || shut.recv().ok());
        gpu_engine_screen_compose(screens[0], &composite, &engine, &pool, plan, extent.as_ptr());
        assert!(gpu_engine_pool_release(&mut pool, at[0].page, at[0].slot));
        let (mut page, mut slot) = (u16::MAX, u16::MAX);
        let tiles = [next.as_ptr()];
        let stored = gpu_engine_pool_store(&mut pool, &engine, cel.0, tiles.as_ptr(), 1, &mut page, &mut slot, told_nothing, 0);
        assert_eq!((stored, page, slot), (1, at[0].page, at[0].slot), "premise: the slot let go is handed out again");
        gpu_engine_screen_compose(screens[1], &composite, &engine, &pool, plan, extent.as_ptr());
        open.send(()).expect("the engine's thread waits");
        done_here(&engine).expect("composed");
        let after = shown.in_rust(&pool, &*plan);
        assert!(before != after, "premise: the two tiles differ");
        assert!(shown.by_the_abi(screens[0]) == before, "the first: the tile as it was when it was called");
        assert!(shown.by_the_abi(screens[1]) == after, "the second: the tile stored since");
        assert_eq!(screens.map(|screen| gpu_engine_screen_bytes(screen)), [TILE_BYTES; 2], "each its own tile");
        for screen in screens {
            gpu_engine_screen_free(screen);
        }
        gpu_engine_plan_free(plan);
        done_here(&engine).expect("let go");
    }
}

/// A plan of one set — `words`, three tiles in a row — laid as it is.
fn a_row_of_three(words: &[u32]) -> *mut Planned {
    let plan = planned();
    // SAFETY: `plan` is live; each array holds what its call reads.
    unsafe {
        gpu_engine_plan_set(plan, 0, 0, 3, 1, words.as_ptr());
        gpu_engine_plan_row(plan, 0, -1, -1, -1, IDENTITY.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 65535, NORMAL);
    }
    plan
}

/// `plan` composed unwaited on a screen of its own over `extent`, as the
/// camera that sees all of it shows it.
fn composed_and_shown(pool: &Pool, plan: *const Planned, extent: [i32; 4]) -> Vec<u8> {
    let (engine, composite) = (rig().engine, &rig().composite);
    let camera = [6.0, 0.0, 0.0, 0.0, 2.5, 0.0];
    let (size, rect) = ((64, 48), [0u32, 0, 64, 48]);
    let shown = surface(size, wgpu::TextureFormat::Rgba8Unorm);
    // SAFETY: every pointer is live and made on `engine`; each array holds
    // what its call reads; the screen is used by nothing after.
    unsafe {
        let screen = gpu_engine_screen_new(first_engine(), extent.as_ptr(), 1.0);
        assert!(!screen.is_null(), "{}", last_error());
        gpu_engine_screen_compose(screen, composite, engine, pool, plan, extent.as_ptr());
        gpu_engine_screen_show(screen, composite, engine, camera.as_ptr(), NEAREST, &shown, rect.as_ptr());
        done_here(engine).expect("composed and shown");
        gpu_engine_screen_free(screen);
    }
    engine.read_texture(&shown).expect("the screen shown")
}

// A plan names its tiles by their slots and is laid on where each lies as
// the pool's books stand, taken anew once a tile has moved: one folded
// after the plan was first laid is read folded, and one moved whole
// where it lies, their slots' bytes written
// over — run over the C ABI, and composed unwaited on the pool as it was
// taken, where it shows what a pool whose tiles lie as they are does —; a
// slot let go and handed out again is the tile now in it; and a set added
// to a plan laid already is laid with the rest.
#[test]
fn a_plan_is_laid_on_where_each_of_its_tiles_lies() {
    let engine = rig().engine;
    let tiles = [folded_tests::tile(1, 2), folded_tests::tile(2, 16), tile(3, true)];
    let (mut pool, at) = stored(&tiles);
    let words: Vec<u32> = at.iter().map(|&at| at.word()).collect();
    let (plan, extent) = (a_row_of_three(&words), [0, 0, 3 * TILE as i32, TILE as i32]);
    let as_stored = ran(&pool, plan, extent).expect("run");
    // The third, a pixel a colour, folds to more than a folded tile takes:
    // it lies whole on the page of the two folded.
    assert_eq!(settled(&mut pool, &at), 3);
    let (folded, whole) = (pool.lies(at[0]), pool.lies(at[2]));
    assert!(folded.folded().is_some() && whole.as_it_is().is_some());
    assert_eq!(whole.page, folded.page);
    scrubbed(rig().engine, &pool, &at);
    assert!(ran(&pool, plan, extent).as_ref() == Some(&as_stored), "run over the C ABI");
    // Laid once for the books as they stand: a frame lays its plan at each
    // run, show and compose.
    // SAFETY: `plan` is live.
    let (planned, lying) = (unsafe { &*plan }, pool.lying());
    assert!(Arc::ptr_eq(&planned.sets_lying(&lying), &planned.sets_lying(&pool.lying())));
    // Another pool's tiles are told apart, so neither screen is the
    // other's picture kept.
    let (as_they_are, places) = stored(&tiles);
    let plain = a_row_of_three(&places.iter().map(|&at| at.word()).collect::<Vec<_>>());
    let shown = composed_and_shown(&pool, plan, extent);
    assert!(shown == composed_and_shown(&as_they_are, plain, extent), "composed unwaited");
    assert!(shown.iter().any(|&byte| byte != 0));

    let again = folded_tests::tile(7, 4);
    pool.release(at[0]).expect("release");
    let cel = pool.cel();
    assert_eq!(pool.store(engine, cel, &[&again[..]]).expect("store"), [at[0]]);
    let other = a_row_of_three(&words);
    let now = ran(&pool, other, extent).expect("run");
    assert!(now != as_stored);
    assert!(ran(&pool, plan, extent).as_ref() == Some(&now), "the tile now in the slot");

    for laid in [plan, other] {
        // SAFETY: `laid` is live; each array holds what its call reads.
        unsafe {
            assert_eq!(gpu_engine_plan_set(laid, 1, 0, 1, 1, [at[1].word()].as_ptr()), 1);
            gpu_engine_plan_row(laid, 1, -1, -1, -1, POSED.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 30000, MULTIPLY);
        }
    }
    let with_more = ran(&pool, plan, extent).expect("a set added after a laying");
    assert!(with_more != now);
    // SAFETY: none is used again.
    unsafe {
        gpu_engine_plan_free(plan);
        gpu_engine_plan_free(plain);
        gpu_engine_plan_free(other);
    }
}
