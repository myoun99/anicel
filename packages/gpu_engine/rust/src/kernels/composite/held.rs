//! What effect chains put, held past the run that made them (folder holding
//! on the engine, 관제 11-08 22:14): a chain the plan names a hold for is
//! not run again while its hold keeps what it put over the same rectangle.
//!
//! 🚨WHY (flip lane ⓑ): the walk runs a chain over its whole rectangle on
//! every run ([`Composite::chained`](super::Composite)) — each page of a
//! frame laid, each step of a stroke drawn above a blurred folder. The old
//! canvas held the folders under the pen (`heldNodes`, BelowThePen) and the
//! frames made ahead held theirs; here one kind of hold does both, each in
//! the room the app gives it.
//!
//! 🚨THE APP GIVES THE NUMBER, BY WHAT THE CHAIN SHOWS: a number is one
//! picture of a folder or a row — its signature, compared whole, never a
//! hash — so another's put is never laid for it. The four cache questions
//! (관제 11-08 22:14): ①the signature changes where the folder does — a
//! stroke's step in it is another; ②a miss runs the chain once, as with no
//! hold, and keeps its buffer, no copy; ③the app lets a hold go first where
//! the screen's pictures want the room; ④the bytes are counted where a hold
//! keeps and lets go ([`held_bytes`]).
//!
//! 🚨A NUMBER IS ONE PICTURE FOR GOOD, NOT ONLY WHILE ITS PUT IS KEPT
//! (F-610, 2026-11-19): a kept picture's tile is told by the number of a
//! chain laid on it ([`Plan::made_of`](super::Plan::made_of)), and held
//! for another picture told the same long after the hold let the put go.
//! A number given to another picture later would show one's pixels in the
//! other — the app gives none twice (`EngineChainHolds.idOf`).

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use crate::kernels::effects::blur::TileRect;
use crate::kernels::shared::Counted;

/// The bytes every hold keeps, kept and not let go.
static HELD_BYTES: AtomicU64 = AtomicU64::new(0);

/// The bytes every hold keeps ([`HeldChains`]).
pub(crate) fn held_bytes() -> u64 {
    HELD_BYTES.load(Ordering::Relaxed)
}

/// What a chain put over its rectangle and, for a buffer crossfaded with it
/// at a mix under whole, the buffer's own tiles it ran on.
#[derive(Clone)]
pub(crate) struct Made {
    pub(crate) put: wgpu::Buffer,
    pub(crate) under: Option<wgpu::Buffer>,
}

/// [`Made`] over the tiles of `rect`, counted while it is kept.
struct Held {
    rect: TileRect,
    made: Made,
    _counted: Counted,
}

impl Made {
    fn bytes(&self) -> u64 {
        self.put.size() + self.under.as_ref().map_or(0, wgpu::Buffer::size)
    }
}

/// The holds made so far: each takes the next count for its own name
/// ([`HeldChains::id`]).
static HOLDS: AtomicU64 = AtomicU64::new(0);

/// Chains' puts under the numbers the app gives them, shared by the plans
/// that name it — a clone is the same hold.
#[derive(Clone)]
pub(crate) struct HeldChains {
    id: u64,
    held: Arc<Mutex<HashMap<u32, Held>>>,
}

impl Default for HeldChains {
    fn default() -> Self {
        Self { id: HOLDS.fetch_add(1, Ordering::Relaxed) + 1, held: Arc::default() }
    }
}

impl HeldChains {
    /// What names it apart from every other hold of this process, given to
    /// none again: each numbers its pictures from nothing, so a picture is
    /// a hold's and its number together ([`Plan::made_of`](super::Plan::made_of)).
    pub(crate) fn id(&self) -> u64 {
        self.id
    }

    /// A hold named `id`, for a test of what tells two holds apart.
    #[cfg(test)]
    pub(crate) fn named(id: u64) -> Self {
        Self { id, held: Arc::default() }
    }

    /// What `id` keeps, where it was made over `rect` — and holds the tiles
    /// its chain ran on where it is laid `mixed`.
    pub(crate) fn over(&self, id: u32, rect: TileRect, mixed: bool) -> Option<Made> {
        let held = self.held();
        let held = held.get(&id)?;
        let fits = held.rect == rect && (!mixed || held.made.under.is_some());
        fits.then(|| held.made.clone())
    }

    /// Keeps `made` over `rect` under `id`, letting go of what it kept —
    /// past the lock ([`Self::let_go`] has why).
    pub(crate) fn keep(&self, id: u32, rect: TileRect, made: Made) {
        let counted = Counted::among(&HELD_BYTES, made.bytes());
        let kept = self.held().insert(id, Held { rect, made, _counted: counted });
        drop(kept);
    }

    /// Lets go of what `id` keeps, if anything.
    ///
    /// 🚨ITS BUFFERS GO PAST THE LOCK: a put of 18–23 MiB takes the driver
    /// 48–63 ms to let go of (`device::posted_of` has the measure), on the
    /// engine's thread, the UI's waiting for none of it — and the UI's
    /// thread asks here what a number weighs ([`Self::bytes_of`]) as each
    /// run of a drag is done. Dropped by the statement that took it out,
    /// it went while the lock was still held, and that ask stood behind
    /// it. ⚠️No test tells the two apart: a buffer's drop cannot be
    /// watched from here (브러시/렌더링 2026-11-20).
    pub(crate) fn let_go(&self, id: u32) {
        let kept = self.held().remove(&id);
        drop(kept);
    }

    /// The bytes `id` keeps — none where it keeps nothing.
    pub(crate) fn bytes_of(&self, id: u32) -> u64 {
        self.held().get(&id).map_or(0, |held| held.made.bytes())
    }

    fn held(&self) -> MutexGuard<'_, HashMap<u32, Held>> {
        self.held.lock().unwrap_or_else(PoisonError::into_inner)
    }
}
