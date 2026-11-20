//! The composite's passes as it keeps them: the full ones, one to an
//! output, each in a cell of its own ([`Fulls`]), and a plan's own, made by
//! the thread that compiles them apart ([`Passes`]).
//!
//! 🚨NOTHING IS COMPILED UNDER A LOCK OF THESE. A verb's body runs on the
//! engine's thread, and one that waits there for a compile leaves that
//! thread to the bodies behind it — but one that waits for a lock another
//! holds across its compile waits for the lock, and every body behind it
//! with it (`EngineThread`, in `device.rs`). So the locks are in this file
//! and no further: nothing here is handed the engine, and without it
//! nothing compiles (🗣️관제 2026-11-14 02:29,
//! the-ui-thread-never-enters-the-driver: 「잠금 안에서 처음 컴파일되는 일이
//! 표현되지 않게」). A full pass is compiled outside its cell and put in it
//! (`kernels::shared`, `kept_or_made`, whose scan reads the sources for a
//! cell filled under its own lock).
//!
//! ↩️Till 2026-11-14 the full passes lay with a plan's own under one lock,
//! held by the composite itself, and the first full pass of an output the
//! executor was not made with was compiled under it.

use std::sync::{Arc, Mutex, MutexGuard, OnceLock, PoisonError};

use super::Compiled;

/// A full pass's cell: empty till the pass is made.
pub(super) type Cell = Arc<OnceLock<wgpu::ComputePipeline>>;

/// The pass that takes any plan (`Compiled::full`), one to an output — the
/// tiles', and a surface's of each format one is stored in.
#[derive(Default)]
pub(super) struct Fulls(Mutex<Vec<(Option<&'static str>, Cell)>>);

impl Fulls {
    fn held(&self) -> MutexGuard<'_, Vec<(Option<&'static str>, Cell)>> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// The cell of the full pass for `surface`'s output — the one cell that
    /// output has.
    pub(super) fn cell(&self, surface: Option<&'static str>) -> Cell {
        let mut cells = self.held();
        if let Some((_, cell)) = cells.iter().find(|(of, _)| *of == surface) {
            return Arc::clone(cell);
        }
        let cell = Cell::default();
        cells.push((surface, Arc::clone(&cell)));
        cell
    }

    /// The outputs that have a cell.
    #[cfg(test)]
    pub(super) fn outputs(&self) -> Vec<Option<&'static str>> {
        self.held().iter().map(|&(of, _)| of).collect()
    }
}

/// Every pass of a plan's own asked for, with its pipeline once the thread
/// that compiles passes apart has made it, and whether that thread runs.
#[derive(Default)]
pub(super) struct Passes(Mutex<Asked>);

#[derive(Default)]
struct Asked {
    passes: Vec<(Compiled, Option<wgpu::ComputePipeline>)>,
    compiling: bool,
}

impl Passes {
    fn held(&self) -> MutexGuard<'_, Asked> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// `compiled`'s pipeline, once made — asked by tests alone.
    #[cfg(test)]
    pub(super) fn made(&self, compiled: Compiled) -> Option<wgpu::ComputePipeline> {
        let held = self.held();
        let asked = held.passes.iter().find(|(asked, _)| *asked == compiled);
        asked.and_then(|(_, made)| made.clone())
    }

    /// `wanted`'s pipeline, once made — asked for from here on, if it was
    /// not —, and whether the thread that compiles apart is the caller's to
    /// start: where `wanted` is new and none runs. One thread at a time: a
    /// second would take a second core from the frames. No test sees it.
    pub(super) fn asked(&self, wanted: Compiled) -> (Option<wgpu::ComputePipeline>, bool) {
        let mut held = self.held();
        if let Some((_, made)) = held.passes.iter().find(|(asked, _)| *asked == wanted) {
            return (made.clone(), false);
        }
        held.passes.push((wanted, None));
        (None, !std::mem::replace(&mut held.compiling, true))
    }

    /// The pass to compile next — the latest asked for and not made — or
    /// none: the thread that compiles apart ends on that word, and runs no
    /// longer.
    pub(super) fn next(&self) -> Option<Compiled> {
        let mut held = self.held();
        let next = held.passes.iter().rev().find(|(_, made)| made.is_none()).map(|&(wanted, _)| wanted);
        if next.is_none() {
            held.compiling = false;
        }
        next
    }

    /// `wanted`'s pipeline, made.
    pub(super) fn put(&self, wanted: Compiled, pipeline: wgpu::ComputePipeline) {
        let mut held = self.held();
        if let Some((_, made)) = held.passes.iter_mut().find(|(asked, _)| *asked == wanted) {
            *made = Some(pipeline);
        }
    }

    /// Whether the thread that compiles apart runs.
    #[cfg(test)]
    pub(super) fn compiling(&self) -> bool {
        self.held().compiling
    }

    /// The passes asked for.
    #[cfg(test)]
    pub(super) fn asked_for(&self) -> Vec<Compiled> {
        self.held().passes.iter().map(|&(asked, _)| asked).collect()
    }
}
