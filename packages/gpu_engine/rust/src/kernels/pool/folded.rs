//! The pool's tiles kept folded (F-610, 2026-11-19 — 🗣️유저, F-610-Q5:
//! 「압축은 … 결국은 3번대로 하자. 결과가 제일 좋으니까」): a tile's bytes
//! folded on the GPU (`kernels/fold`) and laid in as many granules as hold
//! them on a page of folded tiles, read there by every pass
//! (`shared/stored.wgsl`).
//!
//! 🚨A TILE'S NAME STAYS, ITS BYTES MOVE: the slot a tile was handed out at
//! names it for as long as it is held — in the app's ledger, an undo
//! record, a copy's table, a picture's telling by its stamp — and the
//! slot's book says where the tile lies now ([`Pool::lies`], [`Lying`]):
//! there as it is, or folded on another page of the pool. ⛔Not a place of
//! its own name for the folded tile, its holders told to take the new one
//! (the first draft, 11-19): every holder would let the old go and hold
//! the new, and one that did not would keep a slot of 64 KiB for good.
//!
//! A STORED TILE IS NEVER WRITTEN OVER (gpu-canonical-store 1a ①), so a
//! tile is folded once and what was read of it before stays true: the
//! bytes in its slot stand as they were, and a plan laid on the pool as it
//! was taken reads them there.
//!
//! IN TWO STEPS, the books the caller's as ever: a fold is handed to the
//! engine's thread, which waits for the GPU to say what each tile folds to
//! ([`Pool::folds_unwaited`]); once told, the caller's thread gives each a
//! place of that size and hands the copy over ([`Pool::settle`]) — whatever
//! is handed over after that reads the tile folded, behind the copy.
//!
//! ⏳The slot of a tile that lies folded still holds its bytes as they
//! were: the page of tiles whose every held slot lies folded is to give its
//! buffer back, in a lane of its own — the memory comes back there.

// ⏳What asks a fold and settles it is a lane's to come — the engine's
// verbs, and the app's ledger that names the tiles at rest: till then the
// crate's tests are what folds a pool's tile.
#![cfg_attr(not(test), allow(dead_code))]

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use super::{Full, Page, Pool, Slots, Stamps, made};
use crate::device::{Engine, Sent};
use crate::kernels::composite::{FOLDED, GRANULE_BYTES, NO_TILE, TILE_BYTES, TileAt};
use crate::kernels::fold::{Fold, Folded};
use crate::kernels::shared::kept_or_made;
use crate::platform;

/// The most a page of folded tiles holds: the granules a folded place's
/// number names under its bit ([`FOLDED`]) — 32 MiB.
const MOST_FOLDED_PAGE_BYTES: u64 = FOLDED as u64 * GRANULE_BYTES;

/// A page of folded tiles: its granules, each tile's in a run of them.
pub(super) struct Arena {
    /// The runs of granules no tile lies in — where each begins and how
    /// many it is —, in their order, no two side by side.
    free: Vec<(u32, u32)>,
    /// The granules of each tile lying on it, by where it begins.
    held: HashMap<u16, u16>,
    /// The stamp of the tile lying from each granule — its slot's, as it
    /// was handed out ([`super::Stamps`]): a tile folded is the bytes it
    /// was. 0 where none begins.
    pub(super) stamps: Arc<Vec<u64>>,
}

impl Arena {
    /// A page of `granules` granules, no tile on it.
    pub(super) fn of(granules: u32) -> Self {
        Self {
            free: vec![(0, granules)],
            held: HashMap::new(),
            stamps: Arc::new(vec![0; granules as usize]),
        }
    }

    /// A run of `granules` granules for a tile of `stamp`, the first one
    /// that holds them; none where no run does.
    pub(super) fn taken(&mut self, granules: u16, stamp: u64) -> Option<u16> {
        let run = self.free.iter().position(|&(_, room)| room >= u32::from(granules))?;
        let (first, room) = self.free[run];
        match room == u32::from(granules) {
            true => drop(self.free.remove(run)),
            false => self.free[run] = (first + u32::from(granules), room - u32::from(granules)),
        }
        let first = first as u16;
        self.held.insert(first, granules);
        Arc::make_mut(&mut self.stamps)[usize::from(first)] = stamp;
        Some(first)
    }

    /// Lets the run of the tile lying from `first` go, one with the free
    /// runs beside it. Nothing where no tile lies from there.
    pub(super) fn let_go(&mut self, first: u16) {
        let Some(granules) = self.held.remove(&first) else {
            return;
        };
        Arc::make_mut(&mut self.stamps)[usize::from(first)] = 0;
        let (mut first, mut room) = (u32::from(first), u32::from(granules));
        let after = self.free.partition_point(|&(begins, _)| begins < first);
        if self.free.get(after).is_some_and(|&(begins, _)| begins == first + room) {
            room += self.free.remove(after).1;
        }
        if after > 0 && self.free[after - 1].0 + self.free[after - 1].1 == first {
            let before = self.free.remove(after - 1);
            (first, room) = (before.0, before.1 + room);
            self.free.insert(after - 1, (first, room));
        } else {
            self.free.insert(after, (first, room));
        }
    }

    /// The bytes of the granules tiles lie in.
    pub(super) fn held_bytes(&self) -> u64 {
        self.held.values().map(|&granules| u64::from(granules) * GRANULE_BYTES).sum()
    }
}

/// Where each tile a pool holds lies, as it stood when this was taken
/// ([`Pool::lying`]) — with the pages, where what names tiles by their
/// slots is laid on them: a tile folded since lies where it lay then, its
/// slot's bytes untouched.
///
/// 🚨WHAT NAMES A TILE OVER THE C ABI IS READ TO A PLACE BY THIS, and
/// nothing is laid on a name (`composite::Named`, [`Lying::of_word`]): a
/// pass laid on a name reads the slot, whose bytes are the tile's no more
/// once the page of a folded tile is given back. None is made but by a
/// pool ([`Pool::lying`]) — a test's of no pool apart, where every name
/// is its own place.
#[derive(Clone)]
#[cfg_attr(test, derive(Default))]
pub(crate) struct Lying {
    /// Each page of tiles' slots — where the tile named by each lies
    /// folded, as a tile's word, or [`NO_TILE`] for one as it is; none for
    /// a page that is no page of tiles.
    pages: Vec<Option<Arc<Vec<u32>>>>,
    /// The pool's last move of a tile as this was taken ([`moved`]).
    as_of: u64,
}

/// The number of the next move of a tile, across every pool: no two
/// takings of books that differ say one number.
static MOVES: AtomicU64 = AtomicU64::new(1);

/// A move's number, each its own.
pub(super) fn moved() -> u64 {
    MOVES.fetch_add(1, Ordering::Relaxed)
}

impl Lying {
    /// Where the tile named `at` lies: `at` itself, as it is, or its
    /// folded place. A name of no slot of the pool's — a page laid after
    /// the pool's, a stroke's or a stamp's — is its own place.
    pub(crate) fn of(&self, at: TileAt) -> TileAt {
        let page = self.pages.get(usize::from(at.page)).and_then(Option::as_ref);
        let lies = page.and_then(|page| page.get(usize::from(at.slot))).copied();
        lies.and_then(TileAt::of_word).unwrap_or(at)
    }

    /// Where the tile `word` names lies ([`TileAt::word`]); none for
    /// [`NO_TILE`]. A tile the app names by itself, beside no set.
    pub(crate) fn of_word(&self, word: u32) -> Option<TileAt> {
        TileAt::of_word(word).map(|at| self.of(at))
    }

    /// What tells this taking from one a tile has moved since: two that
    /// say one number say one place of every name, and what was laid by
    /// the one stands by the other (a plan's sets, `composite/abi.rs`).
    pub(crate) fn as_of(&self) -> u64 {
        self.as_of
    }
}

/// A pool as a body handed over unwaited lays a plan on it: its pages,
/// where each tile lies on them, and what names their bytes — taken
/// together on the caller's thread, whose books go on. ⛔ONE taking: the
/// weigh and the screen's two composes each spelled what they took.
pub(crate) struct Taken {
    pub(crate) pages: Vec<wgpu::Buffer>,
    pub(crate) lying: Lying,
    pub(crate) stamps: Stamps,
}

/// The tiles a fold handed over unwaited folded, each by its name and its
/// stamp as the fold was asked: what the books give places to
/// ([`Pool::settle`]).
struct Batch {
    tiles: Vec<(TileAt, u64)>,
    folded: Folded,
}

/// What the folds handed over unwaited left, put where the engine's thread
/// has them folded and taken where the pool's caller settles them.
#[derive(Clone, Default)]
pub(super) struct Foldings(Arc<Mutex<Vec<Batch>>>);

impl Foldings {
    fn held(&self) -> MutexGuard<'_, Vec<Batch>> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

impl Pool {
    /// Where the tile named `at` lies now ([`Lying::of`]).
    pub(crate) fn lies(&self, at: TileAt) -> TileAt {
        let lies = self.slots_at(at).and_then(|slots| slots.lying.get(usize::from(at.slot))).copied();
        lies.and_then(TileAt::of_word).unwrap_or(at)
    }

    /// Where each tile it holds lies now ([`Lying`]): taken with the
    /// pages, where a plan is laid on them.
    pub(crate) fn lying(&self) -> Lying {
        let of = |page: &Option<Page>| {
            page.as_ref().and_then(Page::slots).map(|slots| slots.lying.clone())
        };
        Lying { pages: self.pages.iter().map(of).collect(), as_of: self.lying_as_of }
    }

    /// The pool as it stands, for a body handed over unwaited to lay a
    /// plan on ([`Taken`]).
    pub(crate) fn taken(&self) -> Taken {
        Taken { pages: self.buffers.clone(), lying: self.lying(), stamps: self.stamps() }
    }

    /// Hands the engine's thread a fold of the tiles named at `places` —
    /// those held, as they are and named once; the rest are passed over —,
    /// its caller waiting for none of it ([`Engine::posted`]): `told` is
    /// called from that thread once the GPU has said what each folds to,
    /// with `number` and whether it did — the caller's then to settle
    /// ([`Pool::settle`]). How many it handed over; none, and `told` is
    /// not called.
    ///
    /// 🚨THE TILES NAMED ARE WRITTEN, which is their namer's to know: a
    /// slot is handed out before its bytes are put there
    /// ([`Pool::lands_unwaited`]), and the books do not learn when they
    /// are — a tile folded before it was written would be whatever its
    /// slot held.
    pub(crate) fn folds_unwaited(
        &mut self,
        engine: &Engine,
        places: &[TileAt],
        (told, number): (extern "C" fn(u64, bool), u64),
    ) -> usize {
        let mut named = HashSet::new();
        let tiles: Vec<(TileAt, u64)> = places
            .iter()
            .filter(|&&at| named.insert(at))
            .filter_map(|&at| Some((at, self.as_it_is(at)?)))
            .collect();
        if tiles.is_empty() {
            return 0;
        }
        let count = tiles.len();
        let handed = Sent((engine.clone(), self.buffers.clone(), tiles, self.foldings.clone()));
        engine.posted(move || {
            let (engine, pages, tiles, foldings) = handed.taken();
            let places: Vec<TileAt> = tiles.iter().map(|&(at, _)| at).collect();
            let folded = Fold::new(&engine).and_then(|fold| fold.folded(&engine, &pages, &places));
            let folded = folded.map(|folded| foldings.held().push(Batch { tiles, folded }));
            told(number, folded.is_some());
            // ⛔Not a body that failed, whatever it folded: its caller's
            // next done would fail by it ([`Engine::posted`]) — a
            // screen's frame, for tiles that stay as they are and read
            // as they did. `told` says it.
            Some(())
        });
        count
    }

    /// Gives each tile the folds handed over have folded a place of its
    /// own on a page of folded tiles — the first with a run that holds it,
    /// else a new one —, hands the engine's thread the copy of its words
    /// there, and says in its slot's book that it lies there: whatever
    /// names it from here on reads it folded, behind the copy. How many it
    /// settled.
    ///
    /// Passed over, to stay as they are: a tile that folds to more than a
    /// folded tile takes; one let go, or let go and its slot handed out
    /// again, since the fold was asked — told by its stamp —; one settled
    /// already; and, where the pool makes no page more ([`Full`]), one no
    /// page made has a run for. ⛔Not every tile from the first that
    /// found none (the first cut, 11-19): a smaller one behind it has its
    /// run on a page made, and a rule that leaves it out is nobody's.
    pub(crate) fn settle(&mut self, engine: &Engine) -> usize {
        let batches = std::mem::take(&mut *self.foldings.held());
        // A page asked and not made is asked once a settling, not at each
        // tile left: where the budget says no, each asking is the pages'
        // thread's and the OS's count ([`Pool::folded_page`]) — the
        // caller's thread's wait, a tile.
        let mut full = false;
        let mut settled = 0;
        for Batch { tiles, folded } in batches {
            let mut writes = Vec::new();
            for (index, &(at, stamp)) in tiles.iter().enumerate() {
                let Some(granules) = folded.granules(index) else {
                    continue;
                };
                if self.as_it_is(at) != Some(stamp) {
                    continue;
                }
                let mut to = self.folded_room(granules, stamp);
                if to.is_none() && !full {
                    full = self.folded_page(engine).is_err();
                    to = self.folded_room(granules, stamp);
                }
                let Some(to) = to else {
                    continue;
                };
                self.lies_at(at, to.word());
                writes.push((index, to));
            }
            if writes.is_empty() {
                continue;
            }
            settled += writes.len();
            let handed = Sent((engine.clone(), self.buffers.clone(), folded, writes));
            engine.posted(move || {
                let (engine, pages, folded, writes) = handed.taken();
                folded.put(&engine, &pages, &writes)
            });
        }
        settled
    }

    /// The stamp of the tile named `at` where it is held and lies as it
    /// is; none for a name of no held slot, and for a tile that lies
    /// folded.
    fn as_it_is(&self, at: TileAt) -> Option<u64> {
        let (slots, slot) = (self.slots_at(at)?, usize::from(at.slot));
        let held = slots.holds.get(slot).is_some_and(|&holds| holds > 0);
        (held && slots.lying[slot] == NO_TILE).then(|| slots.stamps[slot])
    }

    /// The slots of the page of tiles `at` names; none where it names no
    /// such page.
    fn slots_at(&self, at: TileAt) -> Option<&Slots> {
        self.pages.get(usize::from(at.page))?.as_ref()?.slots()
    }

    fn slots_at_mut(&mut self, at: TileAt) -> Option<&mut Slots> {
        self.pages.get_mut(usize::from(at.page))?.as_mut()?.slots_mut()
    }

    /// Says in its slot's book where the tile named `at` lies — `lies` its
    /// folded place's word, or [`NO_TILE`] for its slot. 🚨THE ONE PLACE
    /// a slot's `lying` is written (`shared/one_name_to_a_place.rs` reads
    /// the source for another): what was taken of the books before says
    /// another number from here on ([`Lying::as_of`]), and what was laid
    /// by it is laid anew.
    pub(super) fn lies_at(&mut self, at: TileAt, lies: u32) {
        let slots = self.slots_at_mut(at).expect("a tile is named by a slot of a page of tiles");
        Arc::make_mut(&mut slots.lying)[usize::from(at.slot)] = lies;
        self.lying_as_of = moved();
    }

    /// A place of `granules` granules for a folded tile of `stamp`, on the
    /// first page of folded tiles with a run that holds it; none where no
    /// page made has one. A page just made has: it is a tile's bytes at
    /// least, and a folded tile half of them at most.
    fn folded_room(&mut self, granules: u16, stamp: u64) -> Option<TileAt> {
        let mut arenas = self.pages.iter_mut().enumerate().filter_map(|(page, book)| match book {
            Some(Page::Folded(arena)) => Some((page, arena)),
            Some(Page::Tiles(_)) | None => None,
        });
        arenas.find_map(|(page, arena)| {
            let first = arena.taken(granules, stamp)?;
            Some(TileAt { page: page as u16, slot: FOLDED | first })
        })
    }

    /// A new page of folded tiles — a page of tiles' bytes,
    /// [`MOST_FOLDED_PAGE_BYTES`] at most —, made within the pool's bytes
    /// and the budget as a page of tiles is ([`Pool::claimed`]), on the
    /// pages' thread while the caller waits: a fold is settled while a
    /// hand rests.
    ///
    /// ⏳Not the page made ahead ([`Pool::make_a_page_ahead`]): that one
    /// is a page of tiles' size, and asked for where a slot is handed out.
    fn folded_page(&mut self, engine: &Engine) -> Result<(), Full> {
        let bytes = self.page_bytes().min(MOST_FOLDED_PAGE_BYTES);
        let (given_back, grows) = self.next_page_of(bytes)?;
        // Its own bytes on the caller's thread, as a page of tiles' are
        // ([`Pool::claimed`] says what asking another cost).
        if !self.within_its_bytes(grows) {
            return Err(Full);
        }
        let bounds = self.bounds();
        let buffer = engine.on_pages_thread(|| {
            match bounds.fits(platform::video_memory(&engine.adapter), grows) {
                true => made(engine, "pool page of folded tiles", bytes),
                false => None,
            }
        });
        let book = Page::Folded(Arena::of((bytes / GRANULE_BYTES) as u32));
        self.page_put(given_back, buffer.ok_or(Full)?, book);
        Ok(())
    }

    /// Lets the folded place `lies` names go: its run free for the next
    /// tile folded. Nothing where it names none.
    pub(super) fn folded_let_go(&mut self, lies: TileAt) {
        let Some(Some(Page::Folded(arena))) = self.pages.get_mut(usize::from(lies.page)) else {
            return;
        };
        arena.let_go(lies.slot ^ FOLDED);
    }

    /// Copies the tiles named at `places`, each held, into `into` — a
    /// tile's bytes each, in order — and submits: one as it is off its
    /// slot, one that lies folded unfolded on the GPU first
    /// (`fold/unfold.wgsl`). What is read of the pool is a tile's bytes,
    /// whatever it lies as.
    pub(super) fn gathered(&self, engine: &Engine, places: &[TileAt], into: &wgpu::Buffer) -> Option<()> {
        let lying: Vec<TileAt> = places.iter().map(|&at| self.lies(at)).collect();
        let mut encoder = engine
            .device()
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        let mut folded = Vec::new();
        for (to, at) in (0..).step_by(TILE_BYTES as usize).zip(lying) {
            match at.as_it_is() {
                Some(from) => {
                    let page = &self.buffers[usize::from(at.page)];
                    encoder.copy_buffer_to_buffer(page, from, into, to, TILE_BYTES);
                }
                None => folded.push((to, at)),
            }
        }
        if !folded.is_empty() {
            let fold = kept_or_made(&self.fold, || Fold::new(engine)).as_ref()?;
            let places: Vec<TileAt> = folded.iter().map(|&(_, at)| at).collect();
            let unfolded = fold.unfolded(engine, &mut encoder, &self.buffers, &places)?;
            for (from, &(to, _)) in (0..).step_by(TILE_BYTES as usize).zip(&folded) {
                encoder.copy_buffer_to_buffer(&unfolded, from, into, to, TILE_BYTES);
            }
        }
        engine.queue.submit([encoder.finish()]);
        Some(())
    }
}
