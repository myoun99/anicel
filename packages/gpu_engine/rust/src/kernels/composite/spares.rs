//! The buffers a walk makes for itself, kept past it for the next walk: what
//! a chained row's tiles, or a buffer's steps, are composited into before
//! the plan is laid ([`Composite::made`](super::Composite)) — as the
//! composite's work buffer is kept from one run to the next
//! ([`Work`](super::Work)), where there are many of them.
//!
//! 🚨WHY (card a-transform-drag-over-folder-rows-draws-a-frame-in-a-third-
//! of-a-second, 2026-11-20): a row with something in hand over it is a
//! buffer of its own in the plan (`_TreePlan._picture`: its tiles, what is
//! held, closed as a row), run first on every compose, and each run made
//! its buffer anew and let it go as the compose ended. 🔬A transform box
//! over 29 rows of S5_BA cut 352 made 29 of 12 to 13 MiB a compose — 350
//! to 510 MiB — and the longest composes of the drag stood 94 to 207 ms
//! in the device's allocator for them (서피스11 캔버스 베이스, the
//! Surface). What is in hand moves with each step, so the buffers are run
//! again each time; made again they need not be.
//!
//! 🚨A BUFFER COMES BACK AS ITS LAST HOLDER LETS GO OF IT ([`Lent`]) — the
//! walk that made it, once the plan it was laid on is submitted, and a
//! hold that keeps it past the walk ([`HeldChains`](super::held::HeldChains))
//! once it lets go. No one says when: who holds a [`Lent`] holds the
//! buffer, and it is no one's to take while any does. ⚠️A bare
//! `wgpu::Buffer` cloned out of one ([`Lent::buffer`]) is lent for the
//! walk it is bound in and no longer: what outlives the walk keeps the
//! [`Lent`].
//!
//! 🚨A KEPT ONE THAT HOLDS THE TILES ASKED SERVES, THE SMALLEST THAT DOES —
//! as the work buffer does (`Work`): a walk puts and reads the tiles it
//! asked for and none past them, and the kernels a chain runs take tiles
//! of no fewer bytes than their rectangle (`effects::blur`). 🔬Of just
//! the size asked alone, the box over 29 rows made 23 of its 24 buffers
//! anew at the one step of sixty where its float crossed a line of tiles
//! — each row's buffer a column of tiles wider, and narrower again as it
//! crosses back (the main PC, 2026-11-20). So a hold may weigh more than
//! its tiles (`Made::bytes`): what it holds is the buffer.
//!
//! ⛔ONE PAST WHAT A BINDING TAKES ([`room`]) SERVES AN ASK OF JUST ITS
//! SIZE ALONE: a walk's own buffer is bound whole — a page of the plan
//! it is laid on (`Pages::entries`), the tiles a chain's kernel reads
//! (`effects::blur`, which refuses tiles past a binding) — so handed to
//! a walk that asked for less, it would be refused where the buffer
//! that walk made itself would not, and one refused compose would leave
//! its refusal to the next (브러시/렌더링 2026-11-20, found reading,
//! before the spares landed; no device has made one).
//!
//! 🚨NOTHING OF WHAT AN EARLIER WALK LEFT IN ONE IS READ: a walk puts every
//! output tile whole — a word for each texel, nothing where it lies
//! outside (to_tiles.wgsl) — and copies each to its place in the output
//! (`Composite::walk_laid`), so a spare is written over whole before
//! anything reads it. A buffer some pass leaves in part untouched is no
//! spare of these: a blur's planes are made new still.
//!
//! 🚨NO MORE THAN ONE COMPOSE'S WORTH IS KEPT, TILL THE NEXT THAT TAKES
//! ANY: as a compose that took a spare ends — a kept picture's making,
//! all the walks its pool's pages cut it into (`Kept::make`), or a walk
//! in none —, the spares it did not take are let go: sizes move
//! with a view and a chain's reach, and one of a size no longer asked
//! for would be kept for nothing. ⛔A compose that takes none lets go of
//! none: each kept frame picture is a screen of its own
//! (`EngineFramePicture`), and a band's frame or a shot composed between
//! two steps of a drag is no sign the next step will not take them —
//! nor is the hand's rest that the next drag will not: let go of there,
//! each gesture's first compose would make them again, the frame a drag
//! stops on (card a-blur-drag-stops-once-on-its-first-frame). So what
//! lies here is what the last compose that took any made for itself. It
//! is counted among the bytes the engine keeps for no picture
//! (`gpu_engine_pictures_idle_bytes`) and given back with them
//! (`gpu_engine_pictures_give_back` — a memory warning, a closed
//! project collected, an allowance moved): as the pages no picture
//! holds are kept for the next picture and not given back at every trim
//! (H57, `EditorSessionManager._applyCacheBudgets`). ⏳브러시/렌더링
//! 2026-11-20, the user away, by H57's reason — theirs to overturn: let
//! go of as the hand rests, memory at rest would be less by one
//! compose's buffers (🔬363 MiB after a box over 29 rows of S5_BA cut
//! 352, the main PC).

use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use super::TILE_BYTES;
use crate::device::Engine;
use crate::kernels::shared::room;

/// The engine's spares ([`Engine`]'s `spares`): a clone is the same ones.
#[derive(Clone, Default)]
pub(crate) struct Spares(Arc<Mutex<Idle>>);

#[derive(Default)]
struct Idle {
    /// Each with whether it came back within the compose under way:
    /// that compose's then, which lets go of the others as it ends.
    kept: Vec<(bool, wgpu::Buffer)>,
    /// The composes under way: one within another is one — a walk within
    /// a picture's making (`Kept::make`), a walk within a walk.
    composing: u32,
    /// Whether the compose under way took one.
    took: bool,
    /// The buffers made, for the tests of what is made again.
    #[cfg(test)]
    made: u64,
}

/// A buffer, and the spares it goes back to once no one holds it — none
/// for one that is no spare ([`Lent::alone`]).
struct Spare {
    buffer: wgpu::Buffer,
    home: Option<Spares>,
}

impl Drop for Spare {
    fn drop(&mut self) {
        if let Some(home) = self.home.take() {
            home.given(self.buffer.clone());
        }
    }
}

/// A buffer held: it stays its holders' for as long as one of them lives,
/// a clone being one more holder, and goes back to the spares it came from
/// as the last lets go.
#[derive(Clone)]
pub(crate) struct Lent(Arc<Spare>);

impl Lent {
    /// `buffer` held as a [`Lent`] is, and no spare: let go of where its
    /// last holder is — what a chain put, made by its kernels.
    pub(crate) fn alone(buffer: wgpu::Buffer) -> Self {
        Self(Arc::new(Spare { buffer, home: None }))
    }

    /// The buffer, for the walk it is bound in (the head of this file).
    pub(crate) fn buffer(&self) -> &wgpu::Buffer {
        &self.0.buffer
    }
}

/// A buffer for `tiles` output tiles of a composite, new: nothing in it
/// (wgpu zeroes a new buffer).
pub(crate) fn out_of(engine: &Engine, tiles: usize) -> wgpu::Buffer {
    engine.device().create_buffer(&wgpu::BufferDescriptor {
        label: Some("composite out"),
        size: out_bytes(tiles),
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    })
}

/// The bytes `tiles` output tiles take — one tile's where there is none.
fn out_bytes(tiles: usize) -> u64 {
    (tiles.max(1) as u64) * TILE_BYTES
}

impl Spares {
    /// A buffer for `tiles` output tiles of a walk's own: the smallest
    /// kept that holds them and a binding takes whole, else a new one of
    /// just that size — its holder's till let go of ([`Lent`]). What it
    /// holds is whatever a walk left there (the head of this file).
    pub(crate) fn out(&self, engine: &Engine, tiles: usize) -> Lent {
        self.out_in(engine, tiles, room(engine))
    }

    /// [`Spares::out`], a binding taking `room` bytes.
    pub(super) fn out_in(&self, engine: &Engine, tiles: usize, room: u64) -> Lent {
        let bytes = out_bytes(tiles);
        let kept = {
            let mut idle = self.idle();
            idle.took = true;
            // Just the size asked, or more that a binding takes whole.
            let serves = |size: u64| size == bytes || (size > bytes && size <= room);
            let holds = |&(_, (_, kept)): &(usize, &(bool, wgpu::Buffer))| serves(kept.size());
            let smallest = idle.kept.iter().enumerate().filter(holds).min_by_key(|(_, (_, kept))| kept.size());
            let at = smallest.map(|(at, _)| at);
            at.map(|at| idle.kept.swap_remove(at).1)
        };
        let buffer = kept.unwrap_or_else(|| {
            #[cfg(test)]
            {
                self.idle().made += 1;
            }
            out_of(engine, tiles)
        });
        Lent(Arc::new(Spare { buffer, home: Some(self.clone()) }))
    }

    fn given(&self, buffer: wgpu::Buffer) {
        let mut idle = self.idle();
        let within = idle.composing > 0;
        idle.kept.push((within, buffer));
    }

    /// A compose is under way till what this answers is let go of — a
    /// picture's making, or a walk in none: as the outermost ends, having taken
    /// any, the spares that did not come back within it are let go (the
    /// head of this file), on `engine`'s thread for pages — the driver's
    /// letting go of them stands in no body's way.
    pub(crate) fn composing<'a>(&'a self, engine: &'a Engine) -> Composing<'a> {
        self.idle().composing += 1;
        Composing { spares: self, engine }
    }

    /// The bytes kept here, held by no one.
    pub(crate) fn bytes(&self) -> u64 {
        self.idle().kept.iter().map(|(_, kept)| kept.size()).sum()
    }

    /// Lets go of every spare kept — on the thread it is asked on, past
    /// the lock.
    pub(crate) fn let_go(&self) {
        let kept = std::mem::take(&mut self.idle().kept);
        drop(kept);
    }

    /// How many buffers were made here, none kept fitting.
    #[cfg(test)]
    pub(crate) fn made(&self) -> u64 {
        self.idle().made
    }

    fn idle(&self) -> MutexGuard<'_, Idle> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

/// A compose under way ([`Spares::composing`]).
pub(crate) struct Composing<'a> {
    spares: &'a Spares,
    engine: &'a Engine,
}

impl Drop for Composing<'_> {
    fn drop(&mut self) {
        let aged: Vec<wgpu::Buffer> = {
            let mut idle = self.spares.idle();
            idle.composing -= 1;
            if idle.composing > 0 {
                return;
            }
            let took = std::mem::take(&mut idle.took);
            let mut aged = Vec::new();
            for (within, buffer) in std::mem::take(&mut idle.kept) {
                if within || !took {
                    idle.kept.push((false, buffer));
                } else {
                    aged.push(buffer);
                }
            }
            aged
        };
        if !aged.is_empty() {
            self.engine.pages_posted(move || drop(aged));
        }
    }
}
