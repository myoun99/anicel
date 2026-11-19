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
//! place of that size and hands the copy over
//! ([`Pool::settles_unwaited`]) — whatever is handed over after that reads
//! the tile folded, behind the copy. The caller's thread waits for nothing
//! of either: the page the places need is made on the pages' thread
//! before the fold is told ([`Room`]).
//!
//! ⏳The slot of a tile that lies folded still holds its bytes as they
//! were: the page of tiles whose every held slot lies folded is to give its
//! buffer back, in a lane of its own — the memory comes back there.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use super::{Ahead, Bounds, Page, Pool, Slots, Spare, Stamps, let_go_on_the_pages_thread};
use crate::device::{Engine, Sent};
use crate::kernels::composite::{FOLDED, GRANULE_BYTES, NO_TILE, TILE_BYTES, TileAt};
use crate::kernels::fold::{Fold, Folded, MOST_FOLDED_BYTES};
use crate::kernels::shared::kept_or_made;

/// The most a page of folded tiles holds: the granules a folded place's
/// number names under its bit ([`FOLDED`]) — 32 MiB.
pub(super) const MOST_FOLDED_PAGE_BYTES: u64 = FOLDED as u64 * GRANULE_BYTES;

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
    /// that holds them ([`run_taken`]); none where no run does.
    pub(super) fn taken(&mut self, granules: u16, stamp: u64) -> Option<u16> {
        let first = run_taken(&mut self.free, granules)? as u16;
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

/// A run of `granules` granules taken off the free runs `free` — the first
/// that holds them, from its beginning: where it begins, or none where no
/// run holds them. What a page of folded tiles gives a tile
/// ([`Arena::taken`]), and what a fold counts on of the runs as they stood
/// ([`Room::holds`]) — one giving, so the two never part.
fn run_taken(free: &mut Vec<(u32, u32)>, granules: u16) -> Option<u32> {
    let run = free.iter().position(|&(_, room)| room >= u32::from(granules))?;
    let (first, room) = free[run];
    match room == u32::from(granules) {
        true => drop(free.remove(run)),
        false => free[run] = (first + u32::from(granules), room - u32::from(granules)),
    }
    Some(first)
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
/// ([`Pool::settles_unwaited`]).
struct Batch {
    tiles: Vec<(TileAt, u64)>,
    /// None where the fold failed.
    folded: Option<Folded>,
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

/// What a fold's body is handed of the books, to have the page its tiles'
/// places need made before it is told ([`Pool::folds_unwaited`]): the free
/// runs as they stood, the page the pool may make
/// ([`Pool::folded_page_to_come`]), and where one made ahead is kept for
/// the settle ([`Pool::folded_page_taken`]).
///
/// 🚨THE CALLER'S THREAD WAITS FOR NO PAGE
/// (the-ui-thread-never-enters-the-driver): a settle is the UI's, and a pen
/// put down as it settles waits behind it. 🔬A page of tiles made while
/// its store's caller waited was 11 to 28 ms of the UI's thread, 35 to
/// 57 ms on the Surface ([`Pool::claimed`], [`Pool::make_a_page_ahead`]);
/// a page of folded tiles is a quarter of one. ↩️Till the verbs came
/// (2026-11-19) the settle made it on the pages' thread and waited, called
/// by the crate's tests alone.
///
/// The body knows what each tile folded takes, so no page is asked for
/// that the tiles do not need: it gives them runs as a settle will
/// ([`run_taken`]), of the runs as they stood. ⚠️One fold at a time, which
/// is its caller's to keep: a fold handed over before the last was settled
/// counts on runs the last one's tiles then take, and a tile of its own
/// that finds none is a fold's to take again.
struct Room {
    runs: Vec<Vec<(u32, u32)>>,
    page: Option<(u64, (Bounds, u64))>,
    ahead: Spare,
}

impl Room {
    /// Whether each of `granules` — what a folded tile takes, in the order
    /// a settle gives them places — finds a run: a page's first that holds
    /// it, a page after another ([`Pool::folded_room`]).
    fn holds(&mut self, granules: impl IntoIterator<Item = u16>) -> bool {
        let mut taken = |granules| self.runs.iter_mut().any(|free| run_taken(free, granules).is_some());
        granules.into_iter().all(&mut taken)
    }
}

impl Slots {
    /// The stamp of the tile in `slot` where it is held and lies as it
    /// is; none for a slot nobody holds, or of no such page, and for a
    /// tile that lies folded.
    fn as_it_is(&self, slot: usize) -> Option<u64> {
        let held = self.holds.get(slot).is_some_and(|&holds| holds > 0);
        (held && self.lying[slot] == NO_TILE).then(|| self.stamps[slot])
    }

    /// [`Slots::as_it_is`] where a fold is to take the tile: one handed to
    /// none as it is (`asked_to_fold`).
    fn to_fold(&self, slot: usize) -> Option<u64> {
        self.as_it_is(slot).filter(|&stamp| self.asked_to_fold[slot] != stamp)
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

    /// The tiles a fold is next handed — held, lying as they are, and
    /// handed to none as they are ([`Slots::to_fold`]) —, a page's before
    /// the next page's and `most` at most: no more than a page of folded
    /// tiles holds at the most each may take, so the one page a fold has
    /// made holds whatever they fold to ([`Room`]).
    ///
    /// None while no folded place was let go since a settle last left a
    /// tile for want of one ([`Pool::settles_unwaited`]) and the pool
    /// may make no page: handed over again as the pool stands it would
    /// fold to find none again, at every rest. 🔢브러시/렌더링's guard
    /// (11-19), no rule of the fold's: a smaller tile that a run left
    /// would hold waits with it, till a folded place is let go or the
    /// pool may make a page.
    pub(crate) fn to_fold(&self, most: usize) -> Vec<TileAt> {
        if self.left_for_room == Some(self.folded_let_gos) && !self.folded_page_may_come() {
            return Vec::new();
        }
        let most = most.min((self.folded_page_bytes() / MOST_FOLDED_BYTES) as usize);
        let pages = self.pages.iter().enumerate();
        let slots = pages.filter_map(|(page, book)| Some((page as u16, book.as_ref()?.slots()?)));
        let tiles = slots.flat_map(|(page, slots)| {
            let to_fold = move |slot: usize| slots.to_fold(slot).map(|_| TileAt { page, slot: slot as u16 });
            (0..slots.holds.len()).filter_map(to_fold)
        });
        tiles.take(most).collect()
    }

    /// Hands the engine's thread a fold of the tiles named at `places` —
    /// those a fold is to take ([`Slots::to_fold`]): held, as they are and
    /// handed to none before; the rest are passed over — by the kernels
    /// `fold`, its caller waiting for none of it ([`Engine::posted`]):
    /// `told` is called from
    /// a thread of the engine's once the GPU has said what each folds to
    /// and the page their places need is made ([`Room`]), with `number`
    /// and whether they folded — the caller's then to settle
    /// ([`Pool::settles_unwaited`]). How many it handed over; none, and
    /// `told` is not called.
    ///
    /// A TILE IS READ BEHIND EVERY PUT HANDED OVER BEFORE ITS FOLD: a slot
    /// is handed out with its put ([`Pool::lands_unwaited`]) or written
    /// before its verb returns, and what is handed to the engine's thread
    /// unwaited runs in the order it was handed, through a compile too
    /// (`EngineThread::stands_aside`). One whose put failed folds to
    /// whatever its slot holds, as it reads there; its holder lets it go
    /// where it is told so. ↩️Till the verbs came (11-19) this said the
    /// namer was to know its tiles written — of an order nobody had read.
    ///
    /// THE KERNELS ARE HANDED IN, COMPILED, and the body makes none: a
    /// body handed over unwaited keeps its turn through a compile, the
    /// jobs behind it waiting, and what it compiles is counted on its
    /// caller's thread ([`Engine::posted`]) — the UI's, which the app
    /// holds at none. A tile lies folded only by a fold, so the read
    /// that first meets one ([`Pool::gathered`]) finds the unfold kept
    /// by the engine: the two are compiled as one ([`Fold::new`]).
    ///
    /// # Safety
    /// `fold` is alive till `told` is called; `told` is one any thread
    /// may call.
    pub(crate) unsafe fn folds_unwaited(
        &mut self,
        engine: &Engine,
        fold: *const Fold,
        places: &[TileAt],
        (told, number): (extern "C" fn(u64, bool), u64),
    ) -> usize {
        let mut tiles = Vec::new();
        for &at in places {
            let slot = usize::from(at.slot);
            let Some(slots) = self.slots_at_mut(at) else {
                continue;
            };
            let Some(stamp) = slots.to_fold(slot) else {
                continue;
            };
            slots.asked_to_fold[slot] = stamp;
            tiles.push((at, stamp));
        }
        if tiles.is_empty() {
            return 0;
        }
        let count = tiles.len();
        let room = Room { runs: self.folded_runs(), page: self.folded_page_to_come(), ahead: self.folded_ahead.clone() };
        let handed = Sent((engine.clone(), fold, self.buffers.clone(), tiles, self.foldings.clone(), room));
        engine.posted(move || {
            let (engine, fold, pages, tiles, foldings, mut room) = handed.taken();
            let places: Vec<TileAt> = tiles.iter().map(|&(at, _)| at).collect();
            let pages_of = engine.clone();
            let then = move |folded: Option<Folded>| {
                let page = folded.as_ref().and_then(|folded| {
                    let (granules, page) = ((0..tiles.len()).filter_map(|tile| folded.granules(tile)), room.page);
                    page.filter(|_| !room.holds(granules))
                });
                let worked = folded.is_some();
                // Kept failed, too: the settle takes back that its
                // tiles were handed to a fold.
                foldings.held().push(Batch { tiles, folded });
                // Told behind the page, where one is asked for: the
                // settle the telling brings finds it made.
                let asked = page.is_some_and(|(bytes, within)| {
                    let page = ("pool page of folded tiles", bytes);
                    room.ahead.asked_of(&pages_of, page, within, move || told(number, worked))
                });
                if !asked {
                    told(number, worked);
                }
            };
            // 🚨THE ENGINE'S THREAD WAITS FOR NO GPU HERE, and goes on
            // to the job behind this one — a stroke's dab: what the
            // tiles fold to is told on a thread of the engine's waits
            // ([`Fold::folded_then`]).
            // SAFETY: alive till `told` is called (the function's contract).
            unsafe { &*fold }.folded_then(&engine, &pages, &places, then);
            // ⛔Not a body that failed, whatever it folded: its caller's
            // next done would fail by it ([`Engine::posted`]) — a
            // screen's frame, for tiles that stay as they are and read
            // as they did. `told` says it.
            Some(())
        });
        count
    }

    /// Gives each tile the folds told have folded a place of its own on a
    /// page of folded tiles — the first with a run that holds it, the page
    /// made ahead for them among these ([`Pool::folded_page_taken`]) —,
    /// hands the engine's thread the copy of its words there, and says in
    /// its slot's book that it lies there: whatever names it from here on
    /// reads it folded, behind the copy. Waits for nothing, the pages'
    /// thread neither ([`Room`]). How many it settled.
    ///
    /// Passed over, to stay as they are: a tile that folds to more than a
    /// folded tile takes; one let go, or let go and its slot handed out
    /// again, since the fold was asked — told by its stamp —; one settled
    /// already; and, a fold's to take again ([`Pool::to_fold`]), one no
    /// page has a run for and those of a fold that failed. ⛔Not every
    /// tile from the first that found none (the first cut, 11-19): a
    /// smaller one behind it has its run on a page made, and a rule that
    /// leaves it out is nobody's.
    pub(crate) fn settles_unwaited(&mut self, engine: &Engine) -> usize {
        self.folded_page_taken(engine);
        let batches = std::mem::take(&mut *self.foldings.held());
        // With nothing folded to settle, nothing is said of the room: a
        // tile the last settle left waits on as it did.
        if batches.is_empty() {
            return 0;
        }
        let (mut settled, mut left) = (0, false);
        for Batch { tiles, folded } in batches {
            let mut writes = Vec::new();
            for (index, &(at, stamp)) in tiles.iter().enumerate() {
                if self.as_it_is(at) != Some(stamp) {
                    continue;
                }
                // A fold that failed left its tiles as they are, a
                // fold's to take again: a device short of memory
                // refuses one, and is the device a fold serves
                // (🗣️관제 2026-11-15 05:09: 「메모리가 없을 때는 드물지
                // 않다」). Its caller is told it failed, and asks for no
                // more till its next rest.
                let Some(folded) = &folded else {
                    self.next_again(at);
                    continue;
                };
                let Some(granules) = folded.granules(index) else {
                    continue;
                };
                let Some(to) = self.folded_room(granules, stamp) else {
                    self.next_again(at);
                    left = true;
                    continue;
                };
                self.lies_at(at, to.word());
                writes.push((index, to));
            }
            settled += writes.len();
            // What was folded goes to the engine's thread whether a tile
            // of it was given a place or not: its words are a buffer, and
            // a buffer let go is the driver's. ⚠️No test tells where one
            // is let go.
            let Some(folded) = folded else {
                continue;
            };
            let handed = Sent((engine.clone(), self.buffers.clone(), folded, writes));
            engine.posted(move || {
                let (engine, pages, folded, writes) = handed.taken();
                match writes.is_empty() {
                    true => Some(()),
                    false => folded.put(&engine, &pages, &writes),
                }
            });
        }
        self.left_for_room = left.then_some(self.folded_let_gos);
        settled
    }

    /// Takes back that the tile named `at` — one that lies as it is —
    /// was handed to a fold: the next takes it ([`Pool::to_fold`]).
    fn next_again(&mut self, at: TileAt) {
        let slots = self.slots_at_mut(at).expect("a tile as it is lies in a slot");
        slots.asked_to_fold[usize::from(at.slot)] = 0;
    }

    /// The stamp of the tile named `at` where it is held and lies as it
    /// is ([`Slots::as_it_is`]); none for a name of no slot.
    fn as_it_is(&self, at: TileAt) -> Option<u64> {
        self.slots_at(at)?.as_it_is(usize::from(at.slot))
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

    /// The bytes of a page of folded tiles: a page of tiles',
    /// [`MOST_FOLDED_PAGE_BYTES`] at most.
    fn folded_page_bytes(&self) -> u64 {
        self.page_bytes().min(MOST_FOLDED_PAGE_BYTES)
    }

    /// The free runs of each page of folded tiles, a page's after
    /// another's, as they stand: what a fold's body counts on
    /// ([`Room::holds`]), in the order a settle asks the pages
    /// ([`Pool::folded_room`]).
    fn folded_runs(&self) -> Vec<Vec<(u32, u32)>> {
        let runs = |book: &Option<Page>| match book {
            Some(Page::Folded(arena)) => Some(arena.free.clone()),
            Some(Page::Tiles(_)) | None => None,
        };
        self.pages.iter().filter_map(runs).collect()
    }

    /// The page of folded tiles the pool may make next — its bytes, and
    /// the bounds it is made within grown by how many —; none where it may
    /// make none: a `TileAt` names no page more, or its own bytes hold
    /// none, asked here on the caller's thread ([`Pool::claimed`] says
    /// what asking another thread that cost).
    fn folded_page_to_come(&self) -> Option<(u64, (Bounds, u64))> {
        let bytes = self.folded_page_bytes();
        let (_, grows) = self.next_page_of(bytes).ok()?;
        self.within_its_bytes(grows).then(|| (bytes, (self.bounds(), grows)))
    }

    /// Whether a fold handed over as the pool stands could have a page
    /// made for its tiles: the pool may make one
    /// ([`Pool::folded_page_to_come`]), and none was refused within the
    /// bounds it has now ([`Ahead::Refused`]).
    fn folded_page_may_come(&self) -> bool {
        let refused = |asked| matches!(&*self.folded_ahead.held(), Ahead::Refused(refused) if *refused == asked);
        self.folded_page_to_come().is_some_and(|(_, (bounds, _))| !refused(bounds.asked()))
    }

    /// Puts the page of folded tiles made ahead ([`Room`]) in the books —
    /// where it was made within the bounds the pool has now, as a page of
    /// tiles made ahead is taken ([`Pool::claimed`]): one made within
    /// others goes, on the pages' thread.
    fn folded_page_taken(&mut self, engine: &Engine) {
        let bytes = self.folded_page_bytes();
        let now = self.next_page_of(bytes).ok().filter(|&(_, grows)| self.within_its_bytes(grows));
        let made = now.and_then(|(given_back, _)| Some((given_back, self.folded_ahead.taken_as(self.bounds().asked())?)));
        if let Some((given_back, page)) = made {
            let book = Page::Folded(Arena::of((bytes / GRANULE_BYTES) as u32));
            self.page_put(given_back, page, book);
        }
        let_go_on_the_pages_thread(engine, self.folded_ahead.taken());
    }

    /// Lets the folded place `lies` names go: its run free for the next
    /// tile folded — and counted, for the fold that waits for a place
    /// ([`Pool::to_fold`]). Nothing where it names none.
    pub(super) fn folded_let_go(&mut self, lies: TileAt) {
        let Some(Some(Page::Folded(arena))) = self.pages.get_mut(usize::from(lies.page)) else {
            return;
        };
        arena.let_go(lies.slot ^ FOLDED);
        self.folded_let_gos += 1;
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
