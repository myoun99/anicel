//! Every free of the C ABI gives back what its new took. A free whose drop
//! is gone answers every other test as one that frees — it only leaks —,
//! so this one counts the heap (관제, connection-round-checklist 2026-11-08
//! 00:06: a leak mutant is not an equivalent one). The table is every free
//! the sources export: one more there, and the scan fails until it is here.
//!
//! A thing is let go of on the thread of the engine that made it
//! (`device::Handed`), and what that thread gave back is counted here as
//! a body's is, its caller's (`device::Callers`) — so a free that waits
//! for its thing to be gone is called from the test's thread, as the app
//! calls it. One the GC calls waits for nothing ([`gives_back_unwaited`]).
//! What holds nothing of a device is no engine's (`device::hands_bytes`),
//! and its free lets go of it where it is called, as every free did.

use std::collections::BTreeSet;

use super::source_scan::verbs;
use crate::device::{gpu_engine_close, hands_bytes};
use crate::kernels::cel_pixel::abi::{
    gpu_engine_cel_passed_free, gpu_engine_cel_pixels_free, gpu_engine_cel_pixels_new,
    gpu_engine_ink_free, gpu_engine_ink_new,
};
use crate::kernels::cel_pixel::Passed;
use crate::kernels::dab::abi::{
    gpu_engine_dab_texture_free, gpu_engine_dab_texture_new, gpu_engine_stamp_landing_free,
    gpu_engine_stamp_landing_new, gpu_engine_stamp_picture_free, gpu_engine_stamp_picture_new,
    gpu_engine_blurs_free, gpu_engine_blurs_new, gpu_engine_stroke_free, gpu_engine_stroke_new,
};
use crate::kernels::composite::abi::{
    gpu_engine_chain_read_free, gpu_engine_chain_read_new, gpu_engine_composite_free, gpu_engine_composite_new,
    gpu_engine_composited_free, gpu_engine_held_free,
    gpu_engine_held_new, gpu_engine_mask_free, gpu_engine_mask_new, gpu_engine_plan_free, gpu_engine_plan_new,
    gpu_engine_put_picture_free, gpu_engine_put_picture_new, gpu_engine_screen_free, gpu_engine_screen_new,
};
use crate::kernels::composite::tests::rig as composite_rig;
use crate::kernels::composite::{Composited, TILE_TEXELS};
use crate::kernels::export::abi::{
    gpu_engine_export_cover, gpu_engine_export_cover_free, gpu_engine_export_free, gpu_engine_export_new,
    gpu_engine_export_opaque, gpu_engine_export_shown,
    gpu_engine_export_shown_free, gpu_engine_readout_free,
};
use crate::kernels::effects::blur::TileRect;
use crate::kernels::fill::{gpu_engine_fill_free, gpu_engine_fill_new};
use crate::kernels::flood::abi::{
    Filled, gpu_engine_flood_filled_free, gpu_engine_flood_picture_free,
    gpu_engine_flood_picture_new, gpu_engine_floods_free, gpu_engine_floods_new,
};
use crate::kernels::letters::Lettered;
use crate::kernels::letters::abi::{
    gpu_engine_faces_file, gpu_engine_faces_free, gpu_engine_faces_handed, gpu_engine_faces_of,
    gpu_engine_lettered_free, gpu_engine_letters_free,
    gpu_engine_letters_new,
};
use crate::kernels::letters::glyphs_tests::file;
use crate::kernels::mask::MaskBox;
use crate::kernels::mask::abi::{
    gpu_engine_selection_masks_free, gpu_engine_selection_masks_new, gpu_engine_selection_runs_free,
};
use crate::kernels::mask::runs::SelectionRuns;
use crate::kernels::plugin::abi::{gpu_engine_plugin_free, gpu_engine_plugin_open};
use crate::kernels::pool::{gpu_engine_pool_free, gpu_engine_pool_new};
use crate::kernels::timeline::grid::abi::{
    gpu_engine_grid_free, gpu_engine_grid_lay_free, gpu_engine_grid_lay_new, gpu_engine_grid_new,
    gpu_engine_grid_picture_free, gpu_engine_grid_picture_new,
};
use crate::platform::{gpu_engine_surface_free, gpu_engine_surface_new};
use crate::testing::{first_engine, held, last_error};

/// `free` let go of at least `made`'s box on this thread's heap: what the
/// box held may be more — a wgpu object's own bytes —, never less.
fn gives_back<T>(name: &str, made: *mut T, free: unsafe extern "C" fn(*mut T)) {
    assert!(!made.is_null(), "{name}: {}", last_error());
    let before = held();
    // SAFETY: `made` came from the new `free` pairs with, let go of once.
    unsafe { free(made) };
    let (freed, boxed) = (before - held(), size_of::<T>() as isize);
    assert!(freed >= boxed, "{name} gave back {freed} bytes of a {boxed}-byte box");
}

/// The same of a free the GC calls, which hands its thing to the engine's
/// thread and waits for none of it (`device::let_go_unwaited`): called
/// from a body, where the thing is let go of as the free is called. From
/// this thread such a free gives back nothing here, and [`gives_back`]
/// says so of one that came to wait for nothing; that what it hands over
/// is let go of there is the door's own test (`device::tests`).
fn gives_back_unwaited<T>(name: &str, made: *mut T, free: unsafe extern "C" fn(*mut T)) {
    first_engine().on_thread(|| gives_back(name, made, free));
}

/// A run's output tiles, one of them, as a box the app frees.
fn composited() -> Composited {
    let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
    let out = first_engine().device().create_buffer(&wgpu::BufferDescriptor {
        label: Some("frees' composited"),
        size: TILE_TEXELS * 4,
        usage,
        mapped_at_creation: false,
    });
    Composited { out, passes: 0 }
}

/// Each free, by its name, and a box of its own made and let go of.
fn frees() -> [(&'static str, fn(&'static str)); 36] {
    [
        ("gpu_engine_close", |name| {
            gives_back(name, first_engine().clone().boxed(), gpu_engine_close)
        }),
        ("gpu_engine_plan_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_plan_new(first_engine()) };
            gives_back(name, made, gpu_engine_plan_free)
        }),
        ("gpu_engine_composite_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_composite_new(first_engine()) };
            gives_back(name, made, gpu_engine_composite_free)
        }),
        ("gpu_engine_composited_free", |name| {
            gives_back(name, first_engine().hands(composited()), gpu_engine_composited_free)
        }),
        ("gpu_engine_screen_free", |name| {
            // SAFETY: the engine is live, and the extent holds four words.
            let made = unsafe { gpu_engine_screen_new(first_engine(), [0, 0, 4, 4].as_ptr(), 1.0) };
            gives_back(name, made, gpu_engine_screen_free)
        }),
        ("gpu_engine_mask_free", |name| {
            // SAFETY: the engine is live, and the bytes hold the mask's one.
            let made = unsafe { gpu_engine_mask_new(first_engine(), [255].as_ptr(), 0, 0, 1, 1) };
            gives_back(name, made, gpu_engine_mask_free)
        }),
        ("gpu_engine_put_picture_free", |name| {
            // SAFETY: the bytes hold the picture's four.
            let made = unsafe { gpu_engine_put_picture_new([255; 4].as_ptr(), 4) };
            gives_back(name, made, gpu_engine_put_picture_free)
        }),
        ("gpu_engine_held_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_held_new(first_engine()) };
            gives_back(name, made, gpu_engine_held_free)
        }),
        ("gpu_engine_blurs_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_blurs_new(first_engine()) };
            gives_back(name, made, gpu_engine_blurs_free)
        }),
        ("gpu_engine_stroke_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_stroke_new(first_engine()) };
            gives_back(name, made, gpu_engine_stroke_free)
        }),
        ("gpu_engine_stamp_landing_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_stamp_landing_new(first_engine()) };
            gives_back(name, made, gpu_engine_stamp_landing_free)
        }),
        ("gpu_engine_stamp_picture_free", |name| {
            // SAFETY: the engine is live, and the bytes hold the picture's one pixel.
            let made = unsafe { gpu_engine_stamp_picture_new(first_engine(), [255; 4].as_ptr(), 1, 1) };
            gives_back_unwaited(name, made, gpu_engine_stamp_picture_free)
        }),
        ("gpu_engine_dab_texture_free", |name| {
            let texels = [0.5f64; 4];
            // SAFETY: four texels, a side of two.
            gives_back(name, unsafe { gpu_engine_dab_texture_new(texels.as_ptr(), 2) }, gpu_engine_dab_texture_free);
        }),
        ("gpu_engine_chain_read_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_chain_read_new(first_engine()) };
            gives_back(name, made, gpu_engine_chain_read_free)
        }),
        ("gpu_engine_export_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_export_new(first_engine()) };
            gives_back(name, made, gpu_engine_export_free)
        }),
        ("gpu_engine_readout_free", |name| {
            // SAFETY: the engine is live.
            let (export, frame) = (unsafe { gpu_engine_export_new(first_engine()) }, composited());
            // SAFETY: all are live, made on the engine.
            let made = unsafe { gpu_engine_export_opaque(export, first_engine(), &frame, 1, 1) };
            gives_back(name, made, gpu_engine_readout_free);
            // SAFETY: `export` is live.
            unsafe { gpu_engine_export_free(export) };
        }),
        ("gpu_engine_export_shown_free", |name| {
            // As the surface free's: RGBA where the platform makes it, else
            // BGRA.
            let surface = [false, true]
                .into_iter()
                // SAFETY: the engine is live.
                .map(|bgra| unsafe { gpu_engine_surface_new(first_engine(), 4, 4, bgra) })
                .find(|surface| !surface.is_null())
                .unwrap_or_else(|| panic!("{name}: {}", last_error()));
            // SAFETY: both are live, made on the engine.
            let made = unsafe { gpu_engine_export_shown(first_engine(), surface, 4, 4) };
            gives_back(name, made, gpu_engine_export_shown_free);
            // SAFETY: `surface` is live.
            unsafe { gpu_engine_surface_free(surface) };
        }),
        ("gpu_engine_export_cover_free", |name| {
            let alpha = [255u8; 16];
            // SAFETY: the engine is live; `alpha` holds its 16 bytes.
            let made = unsafe { gpu_engine_export_cover(first_engine(), alpha.as_ptr(), 16, 4, 4) };
            gives_back(name, made, gpu_engine_export_cover_free)
        }),
        ("gpu_engine_fill_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_fill_new(first_engine()) };
            gives_back(name, made, gpu_engine_fill_free)
        }),
        ("gpu_engine_floods_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_floods_new(first_engine()) };
            gives_back(name, made, gpu_engine_floods_free)
        }),
        ("gpu_engine_selection_masks_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_selection_masks_new(first_engine()) };
            gives_back(name, made, gpu_engine_selection_masks_free)
        }),
        ("gpu_engine_selection_runs_free", |name| {
            let runs = SelectionRuns { offsets: vec![0, 0], ends: Vec::new() };
            gives_back(name, hands_bytes(runs), gpu_engine_selection_runs_free)
        }),
        ("gpu_engine_flood_picture_free", |name| {
            let rig = composite_rig();
            // SAFETY: the engine is live.
            let (pool, plan) =
                unsafe { (gpu_engine_pool_new(rig.engine, 1 << 20), gpu_engine_plan_new(rig.engine)) };
            // SAFETY: all are live, made on the engine; the extent holds four words.
            let made = unsafe {
                gpu_engine_flood_picture_new(
                    &rig.composite,
                    rig.engine,
                    pool,
                    plan,
                    [0, 0, 4, 4].as_ptr(),
                )
            };
            gives_back(name, made, gpu_engine_flood_picture_free);
            // SAFETY: each came from its new, let go of once.
            unsafe {
                gpu_engine_plan_free(plan);
                gpu_engine_pool_free(pool);
            }
        }),
        ("gpu_engine_flood_filled_free", |name| {
            let filled = Filled::new(composited().out, MaskBox { width: 1, height: 1 });
            gives_back(name, first_engine().hands(filled), gpu_engine_flood_filled_free)
        }),
        ("gpu_engine_cel_pixels_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_cel_pixels_new(first_engine()) };
            gives_back(name, made, gpu_engine_cel_pixels_free)
        }),
        ("gpu_engine_cel_passed_free", |name| {
            let Composited { out, .. } = composited();
            let passed = Passed { tiles: vec![], out, touched: vec![], runs: vec![] };
            gives_back(name, first_engine().hands(passed), gpu_engine_cel_passed_free)
        }),
        ("gpu_engine_ink_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_ink_new(first_engine()) };
            gives_back(name, made, gpu_engine_ink_free)
        }),
        ("gpu_engine_faces_free", |name| {
            let face = file("BIZUDPGothic-Regular.ttf");
            let handed = gpu_engine_faces_handed();
            // SAFETY: `handed` is set up once, after its one file; `face`
            // holds its length.
            let made = unsafe {
                gpu_engine_faces_file(handed, 0, face.as_ptr(), face.len());
                gpu_engine_faces_of(handed)
            };
            gives_back(name, made, gpu_engine_faces_free)
        }),
        ("gpu_engine_letters_free", |name| gives_back(name, gpu_engine_letters_new(), gpu_engine_letters_free)),
        ("gpu_engine_lettered_free", |name| {
            let rect = TileRect { x0: 0, y0: 0, columns: 1, rows: 1 };
            let made = first_engine().hands(Lettered { rect, tiles: composited().out });
            gives_back(name, made, gpu_engine_lettered_free)
        }),
        ("gpu_engine_plugin_free", |name| {
            let source = include_str!("../../../native/fx_wgsl/fixtures/invert.wgsl");
            // SAFETY: the engine is live; `source` holds its length.
            let made = unsafe { gpu_engine_plugin_open(first_engine(), source.as_ptr(), source.len(), true) };
            gives_back(name, made, gpu_engine_plugin_free)
        }),
        ("gpu_engine_pool_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_pool_new(first_engine(), 1 << 20) };
            gives_back(name, made, gpu_engine_pool_free)
        }),
        ("gpu_engine_grid_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_grid_new(first_engine()) };
            gives_back(name, made, gpu_engine_grid_free)
        }),
        ("gpu_engine_grid_lay_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_grid_lay_new(first_engine()) };
            gives_back(name, made, gpu_engine_grid_lay_free)
        }),
        ("gpu_engine_grid_picture_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_grid_picture_new(first_engine(), 4, 4) };
            gives_back(name, made, gpu_engine_grid_picture_free)
        }),
        ("gpu_engine_surface_free", |name| {
            // As the platform makes the ones it shows: RGBA where it can,
            // else BGRA — Apple's make BGRA alone (platform/apple.rs).
            let made = [false, true]
                .into_iter()
                // SAFETY: the engine is live.
                .map(|bgra| unsafe { gpu_engine_surface_new(first_engine(), 4, 4, bgra) })
                .find(|surface| !surface.is_null())
                .unwrap_or(std::ptr::null_mut());
            gives_back(name, made, gpu_engine_surface_free)
        }),
    ]
}

#[test]
fn every_free_gives_back_its_box() {
    for (name, free) in frees() {
        free(name);
    }
}

/// The frees the sources export: each verb named `gpu_engine_close` or
/// `gpu_engine_…_free`.
fn exported() -> BTreeSet<String> {
    let free = |name: &String| name == "gpu_engine_close" || name.ends_with("_free");
    verbs().into_keys().filter(free).collect()
}

// ⛔`gpu_engine_window_free` alone is not in the table: a window is an
// Android SurfaceProducer's, which no host test makes (platform/android.rs).
const UNMADE: [&str; 1] = ["gpu_engine_window_free"];

#[test]
fn every_free_the_sources_export_is_in_the_table() {
    let named = frees().into_iter().map(|(name, _)| name).chain(UNMADE);
    let (named, exported): (BTreeSet<String>, _) = (named.map(str::to_owned).collect(), exported());
    let off: Vec<_> = exported.difference(&named).collect();
    assert!(off.is_empty(), "a free the table does not make and let go of: {off:?}");
    let gone: Vec<_> = named.difference(&exported).collect();
    assert!(gone.is_empty(), "no free the sources export: {gone:?}");
}
