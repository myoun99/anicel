//! Every free of the C ABI gives back what its new took. A free whose drop
//! is gone answers every other test as one that frees — it only leaks —,
//! so this one counts the heap (관제, connection-round-checklist 2026-11-08
//! 00:06: a leak mutant is not an equivalent one). The table is every free
//! the sources export: one more there, and the scan fails until it is here.

use std::collections::BTreeSet;

use super::source_scan::files_where;
use crate::device::gpu_engine_close;
use crate::kernels::cel_pixel::abi::{gpu_engine_ink_free, gpu_engine_ink_new};
use crate::kernels::composite::abi::{
    gpu_engine_composite_free, gpu_engine_composite_new, gpu_engine_composited_free,
    gpu_engine_plan_free, gpu_engine_plan_new, gpu_engine_screen_free, gpu_engine_screen_new,
};
use crate::kernels::composite::{Composited, TILE_TEXELS};
use crate::kernels::export::abi::{
    gpu_engine_export_free, gpu_engine_export_new, gpu_engine_export_opaque, gpu_engine_readout_free,
};
use crate::kernels::effects::blur::TileRect;
use crate::kernels::fill::{gpu_engine_fill_free, gpu_engine_fill_new};
use crate::kernels::letters::Lettered;
use crate::kernels::letters::abi::{
    gpu_engine_faces_free, gpu_engine_faces_new, gpu_engine_lettered_free, gpu_engine_letters_free,
    gpu_engine_letters_new, gpu_engine_word_cover_free, gpu_engine_word_free, gpu_engine_word_new,
};
use crate::kernels::letters::glyphs_tests::file;
use crate::kernels::letters::words::WordCover;
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

/// A run's output tiles, one of them, as a box the app frees.
fn composited() -> Composited {
    let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
    let out = first_engine().device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("frees' composited"),
        size: TILE_TEXELS * 4,
        usage,
        mapped_at_creation: false,
    });
    Composited { out, passes: 0 }
}

/// Each free, by its name, and a box of its own made and let go of.
fn frees() -> [(&'static str, fn(&'static str)); 19] {
    [
        ("gpu_engine_close", |name| {
            gives_back(name, Box::into_raw(Box::new(first_engine().clone())), gpu_engine_close)
        }),
        ("gpu_engine_plan_free", |name| gives_back(name, gpu_engine_plan_new(), gpu_engine_plan_free)),
        ("gpu_engine_composite_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_composite_new(first_engine()) };
            gives_back(name, made, gpu_engine_composite_free)
        }),
        ("gpu_engine_composited_free", |name| {
            gives_back(name, Box::into_raw(Box::new(composited())), gpu_engine_composited_free)
        }),
        ("gpu_engine_screen_free", |name| {
            // SAFETY: the extent holds four words.
            let made = unsafe { gpu_engine_screen_new([0, 0, 4, 4].as_ptr(), 1.0) };
            gives_back(name, made, gpu_engine_screen_free)
        }),
        ("gpu_engine_export_free", |name| gives_back(name, gpu_engine_export_new(), gpu_engine_export_free)),
        ("gpu_engine_readout_free", |name| {
            let (export, frame) = (gpu_engine_export_new(), composited());
            // SAFETY: all are live, made on the engine.
            let made = unsafe { gpu_engine_export_opaque(export, first_engine(), &frame, 1, 1) };
            gives_back(name, made, gpu_engine_readout_free);
            // SAFETY: `export` is live.
            unsafe { gpu_engine_export_free(export) };
        }),
        ("gpu_engine_fill_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_fill_new(first_engine()) };
            gives_back(name, made, gpu_engine_fill_free)
        }),
        ("gpu_engine_ink_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_ink_new(first_engine()) };
            gives_back(name, made, gpu_engine_ink_free)
        }),
        ("gpu_engine_faces_free", |name| {
            let face = file("BIZUDPGothic-Regular.ttf");
            // SAFETY: each pointer holds one, alive for the call.
            let made = unsafe { gpu_engine_faces_new(&face.as_ptr(), &face.len(), &0, 1) };
            gives_back(name, made, gpu_engine_faces_free)
        }),
        ("gpu_engine_letters_free", |name| gives_back(name, gpu_engine_letters_new(), gpu_engine_letters_free)),
        ("gpu_engine_lettered_free", |name| {
            let rect = TileRect { x0: 0, y0: 0, columns: 1, rows: 1 };
            let made = Box::into_raw(Box::new(Lettered { rect, tiles: composited().out }));
            gives_back(name, made, gpu_engine_lettered_free)
        }),
        ("gpu_engine_pool_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_pool_new(first_engine(), 1 << 20) };
            gives_back(name, made, gpu_engine_pool_free)
        }),
        ("gpu_engine_word_free", |name| gives_back(name, gpu_engine_word_new(), gpu_engine_word_free)),
        ("gpu_engine_word_cover_free", |name| {
            let made = Box::into_raw(Box::new(WordCover { width: 1, height: 1, bytes: vec![0] }));
            gives_back(name, made, gpu_engine_word_cover_free)
        }),
        ("gpu_engine_grid_free", |name| {
            // SAFETY: the engine is live.
            let made = unsafe { gpu_engine_grid_new(first_engine()) };
            gives_back(name, made, gpu_engine_grid_free)
        }),
        ("gpu_engine_grid_lay_free", |name| gives_back(name, gpu_engine_grid_lay_new(), gpu_engine_grid_lay_free)),
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

/// The frees `text` exports: each `extern "C"` function it defines named
/// `gpu_engine_close` or `gpu_engine_…_free`.
fn frees_in(text: &str) -> impl Iterator<Item = &str> {
    const EXPORTED: &str = "extern \"C\" fn ";
    text.match_indices(EXPORTED).filter_map(move |(at, _)| {
        let after = &text[at + EXPORTED.len()..];
        let end = after.find(|c: char| !(c.is_alphanumeric() || c == '_')).unwrap_or(after.len());
        let name = &after[..end];
        let free = name == "gpu_engine_close" || name.ends_with("_free");
        (name.starts_with("gpu_engine_") && free).then_some(name)
    })
}

// ⛔`gpu_engine_window_free` alone is not in the table: a window is an
// Android SurfaceProducer's, which no host test makes (platform/android.rs).
const UNMADE: [&str; 1] = ["gpu_engine_window_free"];

#[test]
fn every_free_the_sources_export_is_in_the_table() {
    let named: BTreeSet<&str> = frees().iter().map(|(name, _)| *name).chain(UNMADE).collect();
    let off = files_where("rs", |text| frees_in(text).any(|name| !named.contains(name)));
    assert!(off.is_empty(), "a free the table does not make and let go of: {off:?}");
    for name in named {
        let homes = files_where("rs", |text| frees_in(text).any(|free| free == name));
        assert!(!homes.is_empty(), "{name} is no free the sources export");
    }
}
