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
//! 🚨WHAT A CHAIN'S OPS PUT ARE SPARES TOO, AND WHAT A BLUR KEEPS BETWEEN
//! ITS PASSES (`kernels/chain`, `effects::blur`; card a-blur-run-makes-
//! its-planes-anew-every-time, 2026-11-20) — a colour step's tiles, a
//! row kept for a plug-in and what it made, a map drawn from rows
//! ([`Composite::copied_spare`](super::Composite)), a blur's tiles and
//! its planes: each run made them anew, and let the planes go as it
//! ended. 🔬A Gaussian on one row of S5_BA cut 352, its blurriness
//! scrubbed 1 to 60 pixels: three buffers a step, 79 to 90 MiB — 5.0
//! GiB over the sixty —, and taken again, three in the sixty (the main
//! PC, counted in the engine); on the Surface the process stood near
//! 11 GB while such a scrub lasted (서피스11 캔버스 베이스). What a
//! blur puts is its holder's — the walk it is laid in, a hold that
//! keeps it — and comes back as that lets go, where the driver's
//! letting go of one stood 48 to 62 ms on the engine's thread (the
//! Surface, the same day).
//!
//! 🚨A NEW ONE IS MADE A STEP UP ([`stepped`]): a blur's planes hold the
//! rows its passes read, more with each pixel of reach, so a value
//! scrubbed up asks a larger plane every step — 88 KiB to 3.6 MiB more
//! (🔬the same run) — and no kept one would hold it. 🔢The step is
//! 브러시/렌더링's (2026-11-20; no rule of the user's): an eighth of
//! the power of two under the size, so an eighth more at most.
//!
//! 🚨NOTHING OF WHAT AN EARLIER WALK LEFT IN ONE IS READ: a walk puts every
//! output tile whole — a word for each texel, nothing where it lies
//! outside (to_tiles.wgsl) — and copies each to its place in the output
//! (`Composite::walk_laid`), so a spare is written over whole before
//! anything reads it. A blur puts the pixels of its picture alone, so
//! the tiles it puts are zeroed first, in the encoder its passes are in
//! (`encode_cleared`) — what wgpu did for a buffer made new, at its
//! first use; its planes are read only where the pass before put them,
//! as one band's go to the next band uncleaned (`blur::bands`).
//!
//! 🚨THEY ARE KEPT WHILE A HAND IS AT WORK, AND NONE AT REST
//! ([`Spares::rest`]). 🗣️유저 2026-11-20 23:20 (a-transform-drag-over-
//! folder-rows-draws-a-frame-in-a-third-of-a-second-Q1 = b 「손을 떼면
//! 바로 놓는다」): 「들고있는게 너무 비효율적인거같은데. 첫프레임이멈추는걸
//! 고치려면 이게아니라 근본적으로 안무겁게 작동하게 하는게 맞지않을까?」
//! — and the words of the option chosen: 「끌기가 끝나 손이 쉬면 임시
//! 버퍼를 전부 놓습니다. 끄는 동안에는 … 다시 씁니다.」 So from one
//! compose to the next they are taken again, and once no compose has
//! been handed to the engine for a rest (`GpuEngine.restsAfter`, the
//! app's `EngineTileLedger.rest`) every one kept is let go
//! (`gpu_engine_pictures_rest`) — and from then till a compose takes one
//! again, one that comes home is kept for no one: what a hold kept, let
//! go of as a cache is trimmed, or a read freed. ⛔Not a list of the
//! doors a spare comes home by, each to arm a rest of its own: that a
//! rest keeps none is said in one place ([`Spares::given`]), by the one
//! flag a take ends.
//!
//! ↩️Kept through the hand's rest for some hours of 2026-11-20 (master
//! 9e0bcfe3f), one compose's worth, for the first compose of the next
//! gesture not to make them again — 🔬of S5_BA cut 352, the main PC: 171
//! MiB once the cut's own chains had run (22 with none kept), 222 after
//! a blur scrubbed on a row, 496 after a box over 29 rows. The user's
//! word is above: what a gesture's first compose costs is to be made
//! light where it is heavy, not bought with memory held at rest. ⚠️So
//! each gesture's first compose makes its buffers again — 🔬1 to 14 ms
//! on the main PC; on the Surface the composes that made 29 of them
//! stood 94 to 207 ms (the head of this file).
//!
//! 🚨WITHIN A HAND'S WORK, NO MORE THAN ONE COMPOSE'S WORTH: as a compose
//! that took a spare ends — a kept picture's making, all the walks its
//! pool's pages cut it into (`Kept::make`), or a walk in none —, the
//! spares it did not take are let go: sizes move with a view and a
//! chain's reach, and one of a size no longer asked for would be kept
//! for nothing. ⛔A compose that takes none lets go of none: each kept
//! frame picture is a screen of its own (`EngineFramePicture`), and a
//! band's frame or a shot composed between two steps of a drag is no
//! sign the next step will not take them. What lies here is counted
//! among the bytes the engine keeps for no picture
//! (`gpu_engine_pictures_idle_bytes`) and given back with them at once
//! where memory is asked for (`gpu_engine_pictures_give_back` — a memory
//! warning, a closed project collected, an allowance moved).
//!
//! 🚨WHAT IS LET GO OF WITH NO ONE WAITING FOR IT IS DROPPED ON THE
//! ENGINE'S THREAD FOR PAGES ([`Spares::dropping_on`]): the
//! driver's letting go of one buffer stood 48 to 62 ms on the Surface
//! (above), and stands in no body's way there.

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
    /// Whether the hand rests ([`Spares::rest`]), till one is taken
    /// again: what comes home meanwhile is kept for no one.
    resting: bool,
    /// Where what is let go of with no one waiting for it is dropped
    /// ([`Spares::dropping_on`]) — where it is let go, with none.
    drops_on: Option<Unwaited>,
    /// The buffers made, for the tests of what is made again.
    #[cfg(test)]
    made: u64,
}

/// What runs a job handed to it on a thread, its caller waiting for none
/// of it ([`Spares::dropping_on`]).
type Unwaited = Arc<dyn Fn(Box<dyn FnOnce() + Send>) + Send + Sync>;

/// A buffer, and the spares it goes back to once no one holds it — none
/// for one that is no spare (`Lent::alone`, a test's).
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
    /// last holder is — the tiles a test hands a chain, made by hand.
    #[cfg(test)]
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
    made_new(engine, "composite out", out_bytes(tiles))
}

/// A buffer of `bytes` a pass puts, another reads and a copy takes, new.
fn made_new(engine: &Engine, label: &str, bytes: u64) -> wgpu::Buffer {
    engine.device().create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: bytes,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    })
}

/// The bytes a spare asked `bytes` is made of: `bytes` up to the next
/// eighth of the power of two under them (the head of this file) — just
/// `bytes` where a binding of `room` bytes takes no more.
fn stepped(bytes: u64, room: u64) -> u64 {
    let step = (bytes.next_power_of_two() / 16).max(4);
    let up = bytes.div_ceil(step) * step;
    if up <= room { up } else { bytes }
}

/// The bytes `tiles` output tiles take — one tile's where there is none.
fn out_bytes(tiles: usize) -> u64 {
    (tiles.max(1) as u64) * TILE_BYTES
}

impl Spares {
    /// Spares whose buffers, let go of with no one waiting for it, are
    /// dropped in a job handed to `thread` — an engine's, its thread for
    /// pages (`Engine::pages_posted`; the head of this file).
    pub(crate) fn dropping_on(thread: impl Fn(Box<dyn FnOnce() + Send>) + Send + Sync + 'static) -> Self {
        let spares = Self::default();
        spares.idle().drops_on = Some(Arc::new(thread));
        spares
    }

    /// A buffer for `tiles` output tiles of a walk's own ([`Spares::of`]).
    pub(crate) fn out(&self, engine: &Engine, tiles: usize) -> Lent {
        self.of(engine, out_bytes(tiles))
    }

    /// A buffer of no fewer than `bytes`, a walk's own or a kernel's of
    /// its: the smallest kept that holds them and a binding takes whole,
    /// else a new one, a step up ([`stepped`]) — its holder's till let go
    /// of ([`Lent`]). What it holds is whatever its last holder left
    /// there (the head of this file).
    pub(crate) fn of(&self, engine: &Engine, bytes: u64) -> Lent {
        self.of_in(engine, bytes, room(engine))
    }

    /// [`Spares::of`], a binding taking `room` bytes.
    pub(super) fn of_in(&self, engine: &Engine, bytes: u64, room: u64) -> Lent {
        let kept = {
            let mut idle = self.idle();
            // A take in no compose is no compose's: the next to end, having
            // taken none itself, lets go of none for it.
            idle.took |= idle.composing > 0;
            // A hand is at work again ([`Spares::rest`]).
            idle.resting = false;
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
            made_new(engine, "spare", stepped(bytes, room))
        });
        Lent(Arc::new(Spare { buffer, home: Some(self.clone()) }))
    }

    /// `buffer` is no one's again: kept for the next take while a hand is
    /// at work, and for no one where it rests ([`Spares::rest`]).
    fn given(&self, buffer: wgpu::Buffer) {
        {
            let mut idle = self.idle();
            if !idle.resting {
                let within = idle.composing > 0;
                idle.kept.push((within, buffer));
                return;
            }
        }
        self.lets_go_of(vec![buffer]);
    }

    /// A compose is under way till what this answers is let go of — a
    /// picture's making, or a walk in none: as the outermost ends, having taken
    /// any, the spares that did not come back within it are let go (the
    /// head of this file).
    pub(crate) fn composing(&self) -> Composing<'_> {
        self.idle().composing += 1;
        Composing { spares: self }
    }

    /// The hand rests: every spare kept is let go of, and one that comes
    /// home from here on is kept for no one — till one is taken again
    /// ([`Spares::of`]), a hand at work (the head of this file).
    pub(crate) fn rest(&self) {
        let kept = {
            let mut idle = self.idle();
            idle.resting = true;
            std::mem::take(&mut idle.kept)
        };
        self.lets_go_of(kept.into_iter().map(|(_, buffer)| buffer).collect());
    }

    /// Lets go of `buffers`, no one waiting for it — past the lock.
    fn lets_go_of(&self, buffers: Vec<wgpu::Buffer>) {
        if !buffers.is_empty() {
            self.unwaited(move || drop(buffers));
        }
    }

    /// `work`, run where these spares drop what they let go of
    /// ([`Spares::dropping_on`]) — here, where they were made with no
    /// thread for it.
    pub(super) fn unwaited(&self, work: impl FnOnce() + Send + 'static) {
        let on = self.idle().drops_on.clone();
        match on {
            Some(thread) => thread(Box::new(work)),
            None => work(),
        }
    }

    /// The bytes kept here, held by no one.
    pub(crate) fn bytes(&self) -> u64 {
        self.idle().kept.iter().map(|(_, kept)| kept.size()).sum()
    }

    /// Lets go of every spare kept — on the thread it is asked on, past
    /// the lock: its caller waits for the bytes to be gone
    /// (`gpu_engine_pictures_give_back`).
    pub(crate) fn let_go(&self) {
        let kept = std::mem::take(&mut self.idle().kept);
        drop(kept);
    }

    /// How many buffers were made here, none kept fitting.
    #[cfg(test)]
    pub(crate) fn made(&self) -> u64 {
        self.idle().made
    }

    /// Writes over every spare kept, as holding what some run left there.
    #[cfg(test)]
    pub(crate) fn scribble(&self, engine: &Engine) {
        for (_, kept) in &self.idle().kept {
            engine.queue.write_buffer(kept, 0, &vec![0xa5; kept.size() as usize]);
        }
    }

    fn idle(&self) -> MutexGuard<'_, Idle> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

/// A compose under way ([`Spares::composing`]).
pub(crate) struct Composing<'a> {
    spares: &'a Spares,
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
        self.spares.lets_go_of(aged);
    }
}
