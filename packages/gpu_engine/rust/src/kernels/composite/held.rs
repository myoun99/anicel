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

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use crate::kernels::effects::blur::TileRect;

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
}

impl Held {
    fn bytes(&self) -> u64 {
        self.made.put.size() + self.made.under.as_ref().map_or(0, wgpu::Buffer::size)
    }
}

impl Drop for Held {
    fn drop(&mut self) {
        HELD_BYTES.fetch_sub(self.bytes(), Ordering::Relaxed);
    }
}

/// Chains' puts under the numbers the app gives them, shared by the plans
/// that name it.
#[derive(Clone, Default)]
pub(crate) struct HeldChains {
    held: Arc<Mutex<HashMap<u32, Held>>>,
}

impl HeldChains {
    /// What `id` keeps, where it was made over `rect` — and holds the tiles
    /// its chain ran on where it is laid `mixed`.
    pub(crate) fn over(&self, id: u32, rect: TileRect, mixed: bool) -> Option<Made> {
        let held = self.held();
        let held = held.get(&id)?;
        let fits = held.rect == rect && (!mixed || held.made.under.is_some());
        fits.then(|| held.made.clone())
    }

    /// Keeps `made` over `rect` under `id`, letting go of what it kept.
    pub(crate) fn keep(&self, id: u32, rect: TileRect, made: Made) {
        let held = Held { rect, made };
        HELD_BYTES.fetch_add(held.bytes(), Ordering::Relaxed);
        self.held().insert(id, held);
    }

    /// Lets go of what `id` keeps, if anything.
    pub(crate) fn let_go(&self, id: u32) {
        self.held().remove(&id);
    }

    /// The bytes `id` keeps — none where it keeps nothing.
    pub(crate) fn bytes_of(&self, id: u32) -> u64 {
        self.held().get(&id).map_or(0, Held::bytes)
    }

    fn held(&self) -> MutexGuard<'_, HashMap<u32, Held>> {
        self.held.lock().unwrap_or_else(PoisonError::into_inner)
    }
}
