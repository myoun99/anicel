//! The executor's C ABI on a real GPU: a plan built call by call composites
//! as the same plan built in Rust, shown onto a surface it lays the pixels a
//! run puts, a row whose pose lands nothing is left out, and what is refused
//! says why.

use super::*;
use crate::kernels::blend::mode::{MULTIPLY, NORMAL, SCREEN};
use crate::kernels::composite::tests::{mix, pixel_at, rig};
use crate::kernels::composite::{TILE, TILE_TEXELS};
use crate::kernels::pool::Pool;
use crate::kernels::shared::le_bytes;
use crate::platform::{gpu_engine_surface_free, gpu_engine_surface_new};
use crate::testing::read_buffer;

const IDENTITY: [f64; 9] = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
/// Moved left by 37.25 px and down by 9.5: a pose R1 samples, not copies.
const POSED: [f64; 9] = [1.0, 0.0, 37.25, 0.0, 1.0, -9.5, 0.0, 0.0, 1.0];
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

fn word(at: TileAt) -> u32 {
    u32::from(at.page) << 16 | u32::from(at.slot)
}

fn map(inverse: [f64; 9], mode: ResampleMode) -> ResampleMap {
    ResampleMap::new(inverse, 1.0, mode, 3 * TILE, TILE).expect("a pose that lands")
}

/// `plan` run by the C ABI over [`OUTPUT`], read back.
fn ran(pool: &Pool, plan: *const Planned, extent: [i32; 4]) -> Option<Vec<u8>> {
    let (engine, composite) = (rig().engine, &rig().composite);
    let tiles: Vec<i32> = OUTPUT.iter().flat_map(|&(column, row)| [column, row]).collect();
    // SAFETY: every pointer is live, `tiles` holds two words a tile.
    let out = unsafe {
        gpu_engine_composite_run(composite, engine, pool, plan, tiles.as_ptr(), OUTPUT.len(), extent.as_ptr())
    };
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
fn ran_in_rust(pool: &Pool, sets: &[TileSet], matrices: &[[u32; MATRIX_WORDS]], steps: &[Step]) -> Vec<u8> {
    let (engine, composite) = (rig().engine, &rig().composite);
    let plan = Plan { pages: pool.pages(), sets, keys: &[], matrices, chains: &[], steps, mask: None };
    let out = composite.run(engine, &plan, &OUTPUT, [0, 0, 300, 120], composite.widest()).expect("run");
    read_buffer(engine, &out.out)
}

fn last_error() -> String {
    let mut buffer = [0u8; 256];
    // SAFETY: `buffer` holds its length.
    let length = unsafe { crate::gpu_engine_last_error(buffer.as_mut_ptr(), buffer.len()) };
    String::from_utf8_lossy(&buffer[..length.min(buffer.len())]).into_owned()
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
        assert_eq!(gpu_engine_plan_set(plan, 0, 0, 2, 1, [word(at[0]), word(at[1])].as_ptr()), 0);
        assert_eq!(gpu_engine_plan_set(plan, 1, 0, 2, 1, [NO_TILE, word(at[2])].as_ptr()), 1);
        assert_eq!(gpu_engine_plan_matrix(plan, contrast.as_ptr()), 0);
        assert_eq!(gpu_engine_plan_matrix(plan, warm.as_ptr()), 1);
        gpu_engine_plan_solid(plan, 0xc0_33_66_99, 10, 4, 290, 100);
        gpu_engine_plan_open(plan, false);
        assert_eq!(gpu_engine_plan_row(plan, 0, -1, IDENTITY.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 65535, NORMAL), 1);
        assert_eq!(gpu_engine_plan_row(plan, 1, 0, POSED.as_ptr(), 2.0, PICK, 3 * TILE, TILE, 41000, SCREEN), 1);
        gpu_engine_plan_close(plan, 40000, MULTIPLY, -1);
        gpu_engine_plan_open(plan, false);
        assert_eq!(gpu_engine_plan_row(plan, 1, -1, IDENTITY.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 65535, NORMAL), 1);
        gpu_engine_plan_open(plan, true);
        assert_eq!(gpu_engine_plan_row(plan, 0, -1, POSED.as_ptr(), 1.0, NEAREST, 3 * TILE, TILE, 30000, MULTIPLY), 1);
        gpu_engine_plan_close_atop(plan);
        gpu_engine_plan_close(plan, 50000, NORMAL, 1);
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
        row(0, map(POSED, ResampleMode::Nearest), None, 30000, MULTIPLY),
        Step::CloseAtop,
        Step::Close { opacity: 50000, mode: NORMAL, matrix: Some(1), chain: None },
    ];
    let matrices = [matrix_words(&contrast).expect("held"), matrix_words(&warm).expect("held")];
    let built = ran(&pool, plan, [0, 0, 300, 120]).expect("run");
    // SAFETY: `plan` came from `gpu_engine_plan_new`.
    unsafe { gpu_engine_plan_free(plan) };
    assert_eq!(built, ran_in_rust(&pool, &sets, &matrices, &steps));
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
        gpu_engine_plan_set(plan, 0, 0, 3, 1, at.iter().map(|&at| word(at)).collect::<Vec<_>>().as_ptr());
        gpu_engine_plan_row(plan, 0, -1, IDENTITY.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 65535, NORMAL);
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
        gpu_engine_plan_set(plan, 0, 0, 2, 1, [word(at[0]), word(at[1])].as_ptr());
        gpu_engine_plan_row(plan, 0, -1, POSED.as_ptr(), 1.0, BLEND, 3 * TILE, TILE, 65535, NORMAL);
    }
    // Where the pose's tent reads stored pixels alone, so what it lays is
    // opaque: source y = y − 9 ± 1 inside the tiles from y = 10, source x =
    // x + 37.75 ± 1 inside them to x = 217.
    let rect = [5u32, 10, 217, 120];
    let extent = rect.map(|edge| edge as i32);
    let put = ran(&pool, plan, extent).expect("run");
    // SAFETY: `engine` is live.
    let surface = unsafe { gpu_engine_surface_new(engine, 3 * TILE, TILE, false) };
    assert!(!surface.is_null());
    // SAFETY: every pointer is live and made on `engine`.
    let passes = unsafe { gpu_engine_composite_show(&rig().composite, engine, &pool, plan, surface, rect.as_ptr()) };
    assert!(passes >= 1, "{}", last_error());
    // SAFETY: `surface` is live.
    let shown = engine.read_texture(unsafe { &(*surface).texture }).expect("read the surface");
    for y in rect[1] as i32..rect[3] as i32 {
        for x in rect[0] as i32..rect[2] as i32 {
            let texel = (y as usize * 3 * TILE as usize + x as usize) * 4;
            assert_eq!(shown[texel..texel + 4], pixel_at(&put, &OUTPUT, x, y), "({x}, {y})");
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
    let added = unsafe { gpu_engine_plan_row(plan, 0, -1, behind.as_ptr(), 1.0, BLEND, TILE, TILE, 65535, NORMAL) };
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
        assert_eq!(gpu_engine_plan_row(plan, 0, -1, IDENTITY.as_ptr(), 1.0, 2, TILE, TILE, 65535, NORMAL), -1);
        assert!(last_error().contains("sampling"), "{}", last_error());
        assert_eq!(gpu_engine_plan_matrix(plan, past.as_ptr()), -1);
        assert!(last_error().contains("matrix"), "{}", last_error());
        assert!((*plan).steps.is_empty() && (*plan).matrices.is_empty());
        gpu_engine_plan_row(plan, 5, -1, IDENTITY.as_ptr(), 1.0, BLEND, TILE, TILE, 65535, NORMAL);
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
