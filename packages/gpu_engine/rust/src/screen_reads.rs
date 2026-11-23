//! WHAT FLUTTER'S GPU HAS STILL TO READ OF EACH SCREEN'S TEXTURE — told by
//! Anicel's Flutter, patch 0007: a texture of a hardware buffer tells, by
//! the function its producer handed it, how many of its paints the raster
//! has submitted and how many the GPU has read (`ReadSignal`,
//! image_external_texture.h). A screen draws a surface again only where
//! nothing it showed is still to be read (`ScreenTexture`).
//!
//! 🗣️관제 2026-11-24 02:3x (card the-galaxy-tab-canvas-went-slow-on-build-1095,
//! risk 1): a buffer is not written while the GPU may still read it — what
//! Flutter's own frames say, not a guess of how far behind its GPU runs.
//!
//! A texture Flutter tells nothing of — an engine without 0007, a platform
//! whose textures tell nothing (Windows' GL opens its handle on the CPU,
//! external_texture_d3d.cc) — has nothing still to read: its screen draws
//! by the frames alone.

use std::collections::HashMap;
use std::sync::{LazyLock, Mutex, PoisonError};

/// What the raster submitted of a texture's paints, and what the GPU read.
#[derive(Clone, Copy, Default)]
struct Reads {
    submitted: u64,
    read: u64,
}

/// Each texture told of, by its Flutter id, while its screen keeps it.
static READS: LazyLock<Mutex<HashMap<i64, Reads>>> = LazyLock::new(Mutex::default);

fn reads() -> std::sync::MutexGuard<'static, HashMap<i64, Reads>> {
    READS.lock().unwrap_or_else(PoisonError::into_inner)
}

/// `ReadSignal`'s kinds (image_external_texture.h, patch 0007).
const SUBMITTED: i32 = 0;
const READ: i32 = 1;

/// Flutter tells of `texture`: its paints through `count` submitted
/// (`kind` 0), or read (`kind` 1). Called on Flutter's raster thread and
/// on Impeller's fence waiter, so the table's lock is all it takes; a
/// texture not kept ([`gpu_engine_screen_reads_keep`]) — one told of after
/// it was let go — is told of for nothing.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_screen_read(texture: i64, kind: i32, count: u64) {
    let mut reads = reads();
    let Some(of) = reads.get_mut(&texture) else {
        return;
    };
    match kind {
        SUBMITTED => of.submitted = of.submitted.max(count),
        READ => of.read = of.read.max(count),
        _ => {}
    }
}

/// `texture` is told of from now on: none of its paints submitted or read.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_screen_reads_keep(texture: i64) {
    reads().insert(texture, Reads::default());
}

/// `texture` is told of no more.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_screen_reads_forget(texture: i64) {
    reads().remove(&texture);
}

/// How many of `texture`'s paints the raster has submitted and the GPU
/// has not read: none, for one Flutter tells nothing of.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_screen_unread(texture: i64) -> u64 {
    reads().get(&texture).map_or(0, |of| of.submitted.saturating_sub(of.read))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn what_is_submitted_is_unread_till_it_is_read_and_a_texture_let_go_is_told_of_for_nothing() {
        const TEXTURE: i64 = -7001;
        gpu_engine_screen_read(TEXTURE, SUBMITTED, 3);
        assert_eq!(gpu_engine_screen_unread(TEXTURE), 0, "not kept: told of for nothing");

        gpu_engine_screen_reads_keep(TEXTURE);
        gpu_engine_screen_read(TEXTURE, SUBMITTED, 3);
        assert_eq!(gpu_engine_screen_unread(TEXTURE), 3);
        gpu_engine_screen_read(TEXTURE, READ, 2);
        assert_eq!(gpu_engine_screen_unread(TEXTURE), 1);
        // Told out of order — the fence waiter's threads — the newest stands.
        gpu_engine_screen_read(TEXTURE, SUBMITTED, 2);
        gpu_engine_screen_read(TEXTURE, READ, 3);
        assert_eq!(gpu_engine_screen_unread(TEXTURE), 0);
        gpu_engine_screen_read(TEXTURE, READ, 1);
        assert_eq!(gpu_engine_screen_unread(TEXTURE), 0);

        gpu_engine_screen_reads_forget(TEXTURE);
        gpu_engine_screen_read(TEXTURE, SUBMITTED, 9);
        assert_eq!(gpu_engine_screen_unread(TEXTURE), 0);
    }
}
