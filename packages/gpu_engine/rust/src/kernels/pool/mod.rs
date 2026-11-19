//! The tile pool — where a cel's tiles are stored on the engine
//! (gpu-canonical-store 1a ①, 브러시/렌더링 11-05 11:45; ④ 13:19): pages of
//! straight RGBA8 128² tiles, a tile a slot, named (page, slot) by a
//! [`TileAt`] — the pages every pass binds and the write path copies to. A
//! page holds what one binding does, 128 MiB at most (2048 tiles at
//! WebGPU's least binding). A cel's tiles go to a page of its own first,
//! then to any page with a slot free, and a page is made only where none
//! has one: a cel stored at once lies on a page or two, and the cels a
//! frame shows on the few pages their tiles fill — on a device that binds
//! few pages a pass, the passes a composite takes.
//!
//! ↩️A cel kept to pages of its own (1a ④, 11-05) until it was measured in
//! the app (캔버스 베이스, gpu-canonical-store 11-08 02:54 — the Surface,
//! S5_BA cut 352): each cel of 17 to 240 tiles opened a page of 128 MiB,
//! nine of them filled 1152 MiB holding 399 of the cut's 8658 tiles, and a
//! frame of its 68 rows would have bound 68 pages. Its 8658 tiles, 541
//! MiB, fit on five.
//!
//! A held tile is never written over: a write takes a fresh slot (the write
//! path's `put` copies where it is told — no caller writes in place,
//! 캔버스 베이스 11-07 08:3x), and the slot it replaces is released. Holds
//! are counted here — a cel's map, an undo record, a stroke's result each
//! hold the slots they name — and a slot held by none is free. The slot
//! released last on a page is the next one it hands out, so a cel that
//! keeps replacing its tiles keeps to its pages. A page with every slot
//! free is the next one a cel needs, and stays made till its store gives
//! back what nobody holds ([`Pool::give_back`] — the memory warning, a
//! project closed, its budget falling under the pages made): making a
//! page is 44 to 89 ms (캔버스 베이스, gpu-canonical-store 11-08 02:54), a
//! lag each time a cut was opened again were pages given back as they
//! emptied.
//!
//! A pool makes no page past the bytes it is given, past the budget the OS
//! gives this process — or the one it is told to keep to instead —, nor one
//! the driver refuses: it is [`Full`], one answer to all three, and its
//! store cools a cel — reads its tiles back, releases them — and asks again
//! (gpu-canonical-store 11-07 09:00, 관제 09:04: 「한 증상에 법 하나」).
//!
//! The next page is made ahead of the tile that needs it — on a thread of
//! its own, waited for by none — once less than half a page is free, and
//! the store takes it with no wait ([`Pool::make_a_page_ahead`]).
//!
//! The app stores through the C ABI below (connection-round-checklist B,
//! screen-on-the-engine): tiles it holds on the CPU, each in a fresh slot
//! of a cel, and back to the pool when it lets one go. A full pool is
//! answered by the app's ledger (lib/src/native/engine_tile_ledger.dart):
//! it lets go the slots of tiles whose bytes it holds and no call of its
//! holds, as the app's tile pictures were, then reads to RAM the tiles the
//! engine alone holds and lets those slots go, and stores what a call holds
//! past the bytes it gives and, last, past the OS's budget. ↩️Till 11-10 it
//! did the first alone and the 11-07 law above stood only in these notes: a
//! tile the engine alone held kept its slot, and at the OS's line a landing
//! had none.

mod folded;
#[cfg(test)]
pub(crate) mod folded_tests;
#[cfg(test)]
mod tests;

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock, PoisonError};

use crate::device::{Engine, Sent, let_go};
use crate::fail;
use crate::kernels::composite::{FOLDED, MadeOf, NO_TILE, TILE, TILE_BYTES, TileAt};
use crate::kernels::fold::Fold;
use crate::kernels::export::abi::{Readout, readout};
use crate::kernels::shared::room;
use crate::kernels::write::Write;
use crate::platform::{self, VideoMemory};

pub(crate) use folded::{Lying, Taken};
use folded::{Arena, Foldings};

/// The most a page holds where a binding holds more (1a ④).
const MOST_PAGE_BYTES: u64 = 128 << 20;
/// The most a page of the pictures' pool holds ([`Pictures`]): a 4K
/// canvas's tiles — 3840 × 2160 lies on 30 × 17 = 510 tiles, and this is
/// 512.
///
/// ⛔Not the cels' 128 MiB: a page is made whole for the first picture,
/// and the slots of it no picture holds are bytes the app has for
/// nothing — a blank project's pictures are a few MiB. 🔬Main PC, RTX 4080,
/// DX12, a blank project's first strokes (2026-11-13, an allocator that
/// says each block it makes): at 128 MiB the pictures' first page took a
/// new 256 MiB block of the device's allocator beside the cels' first
/// page — 512 to 768 MiB reserved.
// ⏳My number, not measured against the passes a show takes where a
// picture's tiles lie on more pages: to be settled from the Surface's
// probe (H57).
const MOST_PICTURE_PAGE_BYTES: u64 = 32 << 20;
/// The pages a pool may have: a `TileAt` names each by a u16.
const MOST_NAMED: usize = u16::MAX as usize + 1;
/// The slots a page may have: a `TileAt` names each by a u16 under the
/// bit that says a folded tile's ([`FOLDED`]), so no slot of a tile as it
/// is reads as a folded one's.
const MOST_SLOTS: usize = FOLDED as usize;

/// The budget a pool keeps to in place of the OS's till one is set
/// ([`Pool::set_budget_instead`]): none — the OS's — in the app.
#[cfg(not(test))]
const BUDGET_TILL_ONE_IS_SET: Option<u64> = None;

/// cargo test's pool keeps to no budget but its own bytes till a test sets
/// one: the test's numbers, never the machine's as it happens to stand.
///
/// 🗣️관제 2026-11-16 (pool-tests-ride-the-os-vram-budget): 「시험은 기계의
/// 살아 있는 상태에 기대지 않는다 — OS 예산 자체를 재는 시험이 아니면 시험이
/// 쓰는 풀은 예산을 스스로 정한다」. The budget the OS gives this process
/// moves with whatever else runs: 🔬the main PC, 20:13 — 13.9 of 16 GB of
/// VRAM taken by the user's own app and other tests — and 29 tests of this
/// crate found a pool full at its first page, a landing of an unrelated
/// lane refused for it. Set here, where every pool is made, not test by
/// test. A test that keeps a pool to the OS's budget sets it so and says
/// `os` in its name (`kernels/shared/every_test_pool.rs`).
#[cfg(test)]
const BUDGET_TILL_ONE_IS_SET: Option<u64> = Some(u64::MAX);

/// A cel the pool stores tiles for — what names the pages its tiles go to
/// first.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Cel(pub(crate) u32);

/// The pool makes no page more: past its bytes, past the OS's budget,
/// refused by the driver, or past what a `TileAt` names.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Full;

/// What a page holds: tiles as they are, a slot each, or tiles folded,
/// each in as many granules as hold it (`folded.rs`).
enum Page {
    Tiles(Slots),
    Folded(Arena),
}

impl Page {
    /// Its slots, where it is a page of tiles.
    fn slots(&self) -> Option<&Slots> {
        match self {
            Self::Tiles(slots) => Some(slots),
            Self::Folded(_) => None,
        }
    }

    fn slots_mut(&mut self) -> Option<&mut Slots> {
        match self {
            Self::Tiles(slots) => Some(slots),
            Self::Folded(_) => None,
        }
    }

    /// Each tile's stamp: by its slot, or by the granule it lies from.
    fn stamps(&self) -> &Arc<Vec<u64>> {
        match self {
            Self::Tiles(slots) => &slots.stamps,
            Self::Folded(arena) => &arena.stamps,
        }
    }
}

/// What a page of tiles' slots hold.
struct Slots {
    /// Each slot's holds; a slot of none is free.
    holds: Vec<u32>,
    /// The free slots, the one released last at the end.
    free: Vec<u16>,
    /// The cel whose tiles go to it first; none while every slot is free.
    cel: Option<Cel>,
    /// Each slot's stamp: the pool's count of slots handed out as it was
    /// handed out last ([`Pool::fresh`]) — 0 for one never handed out.
    /// Shared with the [`Stamps`] taken of it, and copied where a slot is
    /// handed out while one of them stands.
    stamps: Arc<Vec<u64>>,
    /// Where each slot's tile lies folded, as a tile's word — [`NO_TILE`]
    /// for one that lies in its slot as it is (`folded.rs`). Shared with
    /// the [`Lying`] taken of it, and copied where a tile is settled
    /// while one of them stands.
    lying: Arc<Vec<u32>>,
    /// The stamp of the tile each slot held as it was last handed to a
    /// fold ([`Pool::folds_unwaited`]) — 0 for one handed to none, left
    /// for want of a place, or left by a fold that failed: a tile is
    /// folded once, and what its slot is handed out to next is another
    /// tile, told by its stamp. ⛔No
    /// mark cleared where a slot is handed out: a site that forgot would
    /// leave its tiles as they are for good.
    asked_to_fold: Vec<u64>,
}

/// What names the bytes of each tile a pool holds, as they were when it
/// was taken ([`Pool::stamps`]): a slot's stamp is its alone among every
/// slot the pool has handed out, and a held tile is never written over, so
/// two tiles of one stamp are the same bytes — a slot handed out again has
/// another. What a picture's tile is told by, with the steps laid on it
/// (composite's `Plan::made_of`): a (page, slot) alone names whatever was
/// stored there last.
///
/// 🗣️F-610 (유저 2026-11-18, in chat: 「셀 원본을 합쳐서 1048 인데 합성 그림이
/// 6000 인 게 아주 말이 안 되네 … 원본이 있는데 재생 소재를 만들 이유가
/// 없잖아」, and F-610-Q2 「같은 타일은 한 벌만」): a frame's picture kept a
/// tile of its own for every tile of its canvas, the ones no frame changes
/// among them.
#[derive(Clone)]
pub(crate) struct Stamps {
    /// The pool they are of ([`Pool::id`]): a stamp is a slot's alone
    /// among its own pool's.
    pool: u64,
    pages: Vec<Option<Arc<Vec<u64>>>>,
}

impl Stamps {
    /// The pool they are of, one number a pool of this process.
    pub(crate) fn pool(&self) -> u64 {
        self.pool
    }

    /// The stamp of the tile at `at` — its slot's, or, where it lies
    /// folded, its granule's, which is the stamp of the slot that names
    /// it —; none where the pool had handed no such slot out.
    pub(crate) fn of(&self, at: TileAt) -> Option<u64> {
        let page = self.pages.get(usize::from(at.page))?.as_ref()?;
        page.get(usize::from(at.slot & !FOLDED)).copied().filter(|&stamp| stamp != 0)
    }
}

/// The pools made so far in this process: the next one's number is one
/// more ([`Pool::id`]).
static POOLS: AtomicU64 = AtomicU64::new(0);

pub(crate) struct Pool {
    /// Its number among the pools of this process, from 1: what its stamps
    /// are told apart from another pool's by ([`Stamps::pool`]).
    id: u64,
    buffers: Vec<wgpu::Buffer>,
    /// Each page's slots; none where the page was given back and a tile's
    /// stand-in is its buffer, as a `TileAt` names a page by its place.
    pages: Vec<Option<Page>>,
    slots: usize,
    most_pages: usize,
    most_bytes: u64,
    /// The budget kept to in place of the one the OS gives this process —
    /// the OS's where none ([`Pool::set_budget_instead`]).
    budget_instead: Option<u64>,
    cels: u32,
    /// The slots handed out so far: the next one's stamp is one more
    /// ([`Stamps`]).
    handed: u64,
    /// The places a store handed over unwaited held and its write did not
    /// fill ([`Writing::write`]), till its caller asks
    /// ([`gpu_engine_pool_unwritten`]).
    unwritten: Unwritten,
    /// The page made ahead of the store that needs it
    /// ([`Pool::make_a_page_ahead`]).
    ahead: Spare,
    /// The page of folded tiles made ahead of the settle that needs it
    /// (`folded.rs`, `Room`): taken, or let go, by the settle its fold's
    /// telling brings.
    folded_ahead: Spare,
    /// The folded places let go so far ([`Pool::folded_let_go`]).
    folded_let_gos: u64,
    /// What [`Pool::folded_let_gos`] was as a settle last left a tile for
    /// want of a place — none where the last left none: while the two
    /// are one, and no page may come, no fold is handed a tile
    /// ([`Pool::to_fold`]). ⛔No word set where room is out and cleared
    /// where it comes: what clears it is a count that moved, which no
    /// site forgets to say.
    left_for_room: Option<u64>,
    /// What the folds handed over unwaited have folded, till the books
    /// give each a place ([`Pool::settles_unwaited`]).
    foldings: Foldings,
    /// The unfold, compiled where a read first meets a tile that lies
    /// folded ([`Pool::gathered`]).
    fold: OnceLock<Option<Fold>>,
    /// The last move of a tile of its own ([`Pool::lies_at`]) — its
    /// making, till one moves —, by its number among every pool's
    /// (`folded::moved`): what a taking of where its tiles lie is told
    /// by ([`Lying::as_of`]).
    lying_as_of: u64,
}

/// The places stores handed over unwaited could not write, said where the
/// engine's thread learns it and taken where the store's caller asks.
#[derive(Clone, Default)]
struct Unwritten(Arc<Mutex<Vec<TileAt>>>);

impl Unwritten {
    fn held(&self) -> MutexGuard<'_, Vec<TileAt>> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

/// What a page is made within: the pool's bytes, the most it may make and
/// the budget kept to in place of the OS's — as the pool stood, for the
/// pages' thread to ask of a page made ahead ([`Pool::make_a_page_ahead`])
/// as it is asked of one a store waits for.
#[derive(Clone, Copy)]
struct Bounds {
    bytes: u64,
    most_bytes: u64,
    budget_instead: Option<u64>,
}

impl Bounds {
    /// Whether the pool's bytes grown by `grows` keep within them, and what
    /// this process uses — the OS's count, the pool's own bytes where it
    /// says none — grown so keeps within the budget: the one kept to
    /// instead where there is one, else the OS's where it says one.
    fn fits(self, memory: Option<VideoMemory>, grows: u64) -> bool {
        let used = memory.as_ref().map_or(self.bytes, |memory| memory.used);
        let budget = self.budget_instead.or(memory.as_ref().and_then(|memory| memory.budget));
        let within_budget = budget.is_none_or(|budget| used.checked_add(grows).is_some_and(|sum| sum <= budget));
        self.within_its_bytes(grows) && within_budget
    }

    fn within_its_bytes(self, grows: u64) -> bool {
        self.bytes + grows <= self.most_bytes
    }

    fn asked(self) -> Asked {
        Asked { bytes: self.bytes, budget_instead: self.budget_instead }
    }
}

/// What a page made ahead was asked against: the pool's bytes and the
/// budget kept to in place of the OS's, as they stood. Not the most it may
/// make: its taker asks that again on its own numbers ([`Pool::claimed`]).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Asked {
    bytes: u64,
    budget_instead: Option<u64>,
}

/// The page made ahead of the store that needs it ([`Pool::make_a_page_ahead`]).
#[derive(Debug, Default)]
enum Ahead {
    #[default]
    Unasked,
    /// Handed to the pages' thread, not made yet.
    Making,
    Made(wgpu::Buffer, Asked),
    /// Refused by the budget or the driver, and not asked again as they
    /// were asked.
    Refused(Asked),
}

/// [`Ahead`], where the pages' thread makes the page and the store's
/// caller takes it.
#[derive(Clone, Default)]
struct Spare(Arc<Mutex<Ahead>>);

impl Spare {
    fn held(&self) -> MutexGuard<'_, Ahead> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// The page made ahead, taken — none left to take; none where none is
    /// made.
    fn taken(&self) -> Option<wgpu::Buffer> {
        self.taken_where(|_| true)
    }

    /// [`Spare::taken`] where the page was asked against `asked`; none
    /// taken where it was asked against other bounds.
    fn taken_as(&self, asked: Asked) -> Option<wgpu::Buffer> {
        self.taken_where(|made| *made == asked)
    }

    fn taken_where(&self, take: impl Fn(&Asked) -> bool) -> Option<wgpu::Buffer> {
        let mut ahead = self.held();
        if !matches!(&*ahead, Ahead::Made(_, made) if take(made)) {
            return None;
        }
        let Ahead::Made(page, _) = std::mem::take(&mut *ahead) else { unreachable!("matched above") };
        Some(page)
    }

    /// The page made ahead, taken — and one being made called off: its
    /// making lets it go where it is made ([`Spare::made`]). A refusal
    /// stands.
    ///
    /// 🚨A PAGE BEING MADE IS CALLED OFF, NOT LEFT TO COME: made on a thread
    /// of its own, it can be made after a give-back that let go what was
    /// made — 🧪a pool given back to its stand-in held a page more once
    /// the making ended (`screen_tests.rs`, 2026-11-16). On the engine's
    /// thread a page asked for before the give-back was made before it.
    fn called_off(&self) -> Option<wgpu::Buffer> {
        let mut ahead = self.held();
        match std::mem::take(&mut *ahead) {
            Ahead::Made(page, _) => Some(page),
            Ahead::Unasked | Ahead::Making => None,
            refused @ Ahead::Refused(_) => {
                *ahead = refused;
                None
            }
        }
    }

    /// What the making of a page asked against `asked` ended in — the page,
    /// or none where it was refused —, kept where it is still asked for;
    /// where it was called off meanwhile ([`Spare::called_off`]), the page
    /// goes here.
    fn made(&self, page: Option<wgpu::Buffer>, asked: Asked) {
        let mut ahead = self.held();
        if matches!(&*ahead, Ahead::Making) {
            *ahead = page.map_or(Ahead::Refused(asked), |page| Ahead::Made(page, asked));
        }
    }

    /// Has the pages' thread ([`Engine::pages_posted`]) make `page` — its
    /// label and its bytes — within `bounds` grown by `grows`
    /// ([`Bounds::fits`], [`made`]), its caller waiting for none of it,
    /// and run `then` there once it is made or refused: where none is made
    /// or being made, and none was refused within these bounds
    /// ([`Ahead::Refused`]). Whether it was asked; where not, `then` is
    /// not run.
    ///
    /// 🚨ONE ASKING (2026-11-19): the page of tiles made ahead of a store
    /// ([`Pool::make_a_page_ahead`]) and the page of folded tiles made
    /// ahead of a settle (`folded.rs`, `Room`) are asked, made and refused
    /// alike — each a spare of its own, taken where its pool needs it.
    fn asked_of(
        &self,
        engine: &Engine,
        (label, bytes): (&'static str, u64),
        (bounds, grows): (Bounds, u64),
        then: impl FnOnce() + Send + 'static,
    ) -> bool {
        let asked = bounds.asked();
        let mut ahead = self.held();
        match &*ahead {
            Ahead::Unasked => {}
            Ahead::Refused(refused) if *refused != asked => {}
            Ahead::Making | Ahead::Made(..) | Ahead::Refused(_) => return false,
        }
        *ahead = Ahead::Making;
        drop(ahead);
        let handed = Sent((engine.clone(), self.clone()));
        engine.pages_posted(move || {
            let (engine, ahead) = handed.taken();
            let page = match bounds.fits(platform::video_memory(&engine.adapter), grows) {
                true => made(&engine, label, bytes),
                false => None,
            };
            // A refusal fails nothing: the pool is full where a store next
            // needs a page, as it is told there.
            ahead.made(page, asked);
            then();
        });
        true
    }
}

/// A landing's write, held apart from its pool for the engine's thread
/// ([`Pool::lands_unwaited`]): the pages as they stood, the places its
/// books gave, and where to say it failed.
pub(crate) struct Writing {
    pages: Vec<wgpu::Buffer>,
    places: Vec<TileAt>,
    unwritten: Unwritten,
}

impl Writing {
    /// The pool's pages as they stood when its places were booked: what a
    /// put reads the cel's tiles on, by the places they were given then.
    pub(crate) fn pages(&self) -> &[wgpu::Buffer] {
        &self.pages
    }

    /// Copies `tiles` — straight RGBA8, a tile's bytes each, one a place —
    /// into the places, by the write path in one submit.
    fn write(&self, engine: &Engine, tiles: &[&[u8]]) -> Option<()> {
        let staging = engine.device().create_buffer(&wgpu::BufferDescriptor {
            label: Some("tiles stored"),
            size: self.places.len() as u64 * TILE_BYTES,
            usage: wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: true,
        });
        let copied = match staging.get_mapped_range_mut(..) {
            Ok(mut mapped) => {
                let bytes = TILE_BYTES as usize;
                for (at, tile) in tiles[..self.places.len()].iter().enumerate() {
                    mapped.slice(at * bytes..(at + 1) * bytes).copy_from_slice(tile);
                }
                Some(())
            }
            Err(error) => fail(format!("get_mapped_range_mut: {error}")),
        };
        staging.unmap();
        copied.and_then(|()| self.put_from(engine, &staging, 0..self.places.len()))
    }

    /// Copies the tiles of `out` — straight RGBA8, tile after tile — that
    /// `tiles` names, the i-th into the i-th place, by the write path in
    /// one submit.
    ///
    /// A device gone is put nothing, and says so: wgpu lays and copies on
    /// one with no error, so a put would be told it went where nothing did
    /// (🔬2026-11-18, a plate of letters on an engine lost for memory).
    /// ⚠️As a store's copy tells one (its staging is not mapped,
    /// [`Writing::write`]): every put handed over unwaited
    /// ([`Pool::lands_unwaited`]) says alike what it did not put.
    pub(crate) fn put_from(
        &self,
        engine: &Engine,
        out: &wgpu::Buffer,
        tiles: impl IntoIterator<Item = usize>,
    ) -> Option<()> {
        if engine.gone() {
            return fail("the device is gone: nothing is put");
        }
        let writes: Vec<(usize, TileAt)> = tiles.into_iter().zip(self.places.iter().copied()).collect();
        Write::put(engine, &self.pages, out, &writes)
    }

    /// [`Writing::write`], its places said unwritten where it fails.
    fn write_or_say(&self, engine: &Engine, tiles: &[&[u8]]) -> Option<()> {
        let written = self.write(engine, tiles);
        if written.is_none() {
            self.unwritten.held().extend_from_slice(&self.places);
        }
        written
    }
}

impl Pool {
    /// A pool of pages as large as a binding of this device holds, 128 MiB
    /// at most, that makes no more pages than `most_bytes` hold — 1a ③'s
    /// budget, its store's to give.
    pub(crate) fn new(engine: &Engine, most_bytes: u64) -> Option<Self> {
        Self::paged(engine, MOST_PAGE_BYTES, most_bytes)
    }

    /// [`Pool::new`] of pages of `most_page_bytes` at most.
    fn paged(engine: &Engine, most_page_bytes: u64, most_bytes: u64) -> Option<Self> {
        let slots = (room(engine).min(most_page_bytes) / TILE_BYTES) as usize;
        // ⚠️No test reaches the pages' bound: 65,536 pages to make. It
        // stands so a page past what a TileAt names is refused, not named
        // as another.
        Self::sized(slots, MOST_NAMED, most_bytes)
    }

    /// A pool of pages of `slots` tiles, `most_pages` pages and
    /// `most_bytes` at most.
    fn sized(slots: usize, most_pages: usize, most_bytes: u64) -> Option<Self> {
        if !(1..=MOST_SLOTS).contains(&slots) {
            return fail(format!("a page of {slots} tiles; one holds 1 to {MOST_SLOTS}"));
        }
        let pages = Vec::new();
        Some(Self {
            id: POOLS.fetch_add(1, Ordering::Relaxed) + 1,
            buffers: Vec::new(),
            pages,
            slots,
            most_pages,
            most_bytes,
            budget_instead: BUDGET_TILL_ONE_IS_SET,
            cels: 0,
            handed: 0,
            unwritten: Unwritten::default(),
            ahead: Spare::default(),
            folded_ahead: Spare::default(),
            folded_let_gos: 0,
            left_for_room: None,
            foldings: Foldings::default(),
            fold: OnceLock::new(),
            lying_as_of: folded::moved(),
        })
    }

    /// The pages, as a plan and the write path take them.
    pub(crate) fn pages(&self) -> &[wgpu::Buffer] {
        &self.buffers
    }

    /// What names the bytes of each tile it holds now ([`Stamps`]): taken
    /// with the pages, where a plan is laid on them.
    pub(crate) fn stamps(&self) -> Stamps {
        let of = |page: &Option<Page>| page.as_ref().map(|page| page.stamps().clone());
        Stamps { pool: self.id, pages: self.pages.iter().map(of).collect() }
    }

    /// The pool as one that has handed `handed` slots out already: a
    /// test's, of stamps past a word's reach.
    #[cfg(test)]
    pub(crate) fn handed_already(&mut self, handed: u64) {
        self.handed = handed;
    }

    /// The bytes of the pages made — a page counts whole, its free slots
    /// too, as it stays made, and a page given back its stand-in.
    pub(crate) fn bytes(&self) -> u64 {
        self.buffers.iter().map(wgpu::Buffer::size).sum()
    }

    /// The bytes of the page made ahead of the store that needs it
    /// ([`Pool::make_a_page_ahead`]), and of the page of folded tiles
    /// made ahead of a settle (`folded.rs`, `Room`) — none till it is
    /// made.
    ///
    /// ⛔Not among [`Pool::bytes`], which the budget and the give-back read
    /// as the pages a store took. ★Counted beside them for the memory census
    /// (관제 2026-11-15, a-picture-lay-holds-the-raster-thread): off the books
    /// it would be a share of the GPU's memory that no row names.
    pub(crate) fn ahead_bytes(&self) -> u64 {
        let made = |ahead: &Spare| match &*ahead.held() {
            Ahead::Made(page, _) => page.size(),
            Ahead::Unasked | Ahead::Making | Ahead::Refused(_) => 0,
        };
        made(&self.ahead) + made(&self.folded_ahead)
    }

    /// The bytes of the slots nobody holds on the pages made — a page given
    /// back's stand-in among them: made, and no tile's — and of the
    /// granules no folded tile lies in.
    pub(crate) fn idle_bytes(&self) -> u64 {
        let held = |page: &Page| match page {
            Page::Tiles(slots) => (slots.holds.len() - slots.free.len()) as u64 * TILE_BYTES,
            Page::Folded(arena) => arena.held_bytes(),
        };
        self.bytes() - self.pages.iter().flatten().map(held).sum::<u64>()
    }

    /// Makes no page more past `most_bytes`: the pages made stay (its store
    /// gives back what nobody holds, [`Pool::give_back`]), and the next is
    /// made only within it — the budget its store gives, again when the
    /// allowance moves.
    pub(crate) fn set_most_bytes(&mut self, most_bytes: u64) {
        self.most_bytes = most_bytes;
    }

    /// Keeps to `budget` in place of the budget the OS gives this process,
    /// and the OS's again where none: past any budget for the tiles its
    /// store must place — Windows only advises one, and moves a process
    /// past it out to system memory (platform/windows.rs, F-569) —, and
    /// none left as a test has a device at its line.
    pub(crate) fn set_budget_instead(&mut self, budget: Option<u64>) {
        self.budget_instead = budget;
    }

    /// Gives back the pages nobody's — every slot free —, the last first,
    /// till the pages hold `most_bytes` or none is nobody's: those past the
    /// last held cut off, one before it kept a tile's stand-in in its
    /// place, made again there when a cel next needs a page. No plan binds
    /// one: none of its slots is held, so no tile set names it.
    pub(crate) fn give_back(&mut self, engine: &Engine, most_bytes: u64) {
        // The page made ahead first: no tile's, and the last one made.
        if self.bytes() + self.page_bytes() > most_bytes {
            self.let_the_page_ahead_go(engine);
        }
        while let Some(last) = self.pages.last() {
            let gone = match last {
                None => true,
                Some(_) => nobody_s(last) && self.bytes() > most_bytes,
            };
            if !gone {
                break;
            }
            self.pages.pop();
            self.buffers.pop();
        }
        for page in (0..self.pages.len()).rev() {
            if self.bytes() <= most_bytes {
                return;
            }
            if !nobody_s(&self.pages[page]) {
                continue;
            }
            // ⚠️No test reaches a driver's refusal ([`made`] says why): the
            // page stays made where its stand-in is refused.
            let Some(stand_in) = made(engine, "a page given back", TILE_BYTES) else {
                return;
            };
            self.buffers[page] = stand_in;
            self.pages[page] = None;
        }
    }

    /// The tiles a page holds.
    pub(crate) fn slots(&self) -> usize {
        self.slots
    }

    /// A cel: what the pages its tiles go to first are named by.
    pub(crate) fn cel(&mut self) -> Cel {
        self.cels += 1;
        Cel(self.cels)
    }

    /// A free slot for a tile of `cel`, held once: on the first of its
    /// pages with one free, else on a page of nobody's — its then —, else
    /// on the first page with one free, else on a new page, its. And the
    /// next page asked for ahead of the tile that will need it
    /// ([`Pool::make_a_page_ahead`]).
    ///
    /// ⛔ONE PLACE FOR BOTH POOLS (관제 2026-11-16 02:58, card
    /// a-picture-lay-holds-the-raster-thread): the cels' pool asked ahead
    /// at its store alone, and the pictures' ([`Pictures`]) never — its
    /// pages made where a picture needed one, 10 of them 48 to 188 ms of
    /// the engine's thread on the Surface (FNK_02 cut 59, the onion on,
    /// 2026-11-16 02:4x).
    pub(crate) fn fresh(&mut self, engine: &Engine, cel: Cel) -> Result<TileAt, Full> {
        let own = |page: &Option<Page>| {
            let slots = page.as_ref().and_then(Page::slots);
            slots.is_some_and(|slots| slots.cel == Some(cel) && !slots.free.is_empty())
        };
        let page = match self.pages.iter().position(own) {
            Some(page) => page,
            None => self.claimed(engine, cel)?,
        };
        self.handed += 1;
        let book = self.pages[page].as_mut().and_then(Page::slots_mut).expect("a page found or made is one of tiles");
        let slot = book.free.pop().expect("a page found or made has a slot free");
        book.holds[usize::from(slot)] = 1;
        Arc::make_mut(&mut book.stamps)[usize::from(slot)] = self.handed;
        self.make_a_page_ahead(engine);
        Ok(TileAt { page: page as u16, slot })
    }

    /// `count` fresh slots of `cel`, held: as many of them, the first, as
    /// the pool has room for — the books of a store ([`Pool::store`]).
    pub(crate) fn places(&mut self, engine: &Engine, cel: Cel, count: usize) -> Vec<TileAt> {
        let mut places = Vec::with_capacity(count);
        while places.len() < count {
            match self.fresh(engine, cel) {
                Ok(at) => places.push(at),
                Err(Full) => break,
            }
        }
        places
    }

    /// The write of tiles into `places`, held apart from the pool for the
    /// engine's thread ([`Pool::lands_unwaited`]).
    fn writing(&self, places: Vec<TileAt>) -> Writing {
        Writing { pages: self.buffers.clone(), places, unwritten: self.unwritten.clone() }
    }

    /// `count` fresh places of `cel` booked here ([`Pool::places`]) — all,
    /// or the first few where the pool is full at the next — and `put`
    /// handed to the engine's thread to put their tiles there, its caller
    /// waiting for none of it ([`Engine::posted`]): `told` is called from
    /// that thread once it has run, with `number` and whether it put them;
    /// one that did not is told by the caller's next done too. None booked,
    /// nothing is handed over and `told` is not called. The places, in
    /// their order.
    ///
    /// 🚨ONE ROAD (rule of three, 2026-11-18): the pool's store
    /// (`gpu_engine_pool_store`, B1-b of the-ui-thread-never-enters-the-driver),
    /// the letters' plate (`gpu_engine_letters_land`) and a stroke on its way
    /// (`gpu_engine_stroke_land_unwaited`) each booked its places here and
    /// handed the engine's thread its put — the third came, and they are
    /// one. The books stay the caller's, so its slots are told at once.
    ///
    /// ⛔Told by a call of its own, not the caller's done: a done is told of
    /// the first body handed over that failed since the last, whoever asks
    /// it (`Engine::done_then`), and a landing asking one would take what
    /// the screen's present is to be told of its compose.
    ///
    /// # Safety
    /// What `put` holds is alive, and in no other thread's hands, till it
    /// has run; `told` is one any thread may call.
    pub(crate) unsafe fn lands_unwaited(
        &mut self,
        engine: &Engine,
        (cel, count): (Cel, usize),
        (told, number): (extern "C" fn(u64, bool), u64),
        put: impl FnOnce(&Engine, &Writing) -> Option<()> + 'static,
    ) -> Vec<TileAt> {
        let places = self.places(engine, cel, count);
        if places.is_empty() {
            return places;
        }
        let handed = Sent((engine.clone(), self.writing(places.clone()), put));
        engine.posted(move || {
            let (engine, writing, put) = handed.taken();
            let put = put(&engine, &writing);
            told(number, put.is_some());
            put
        });
        places
    }

    /// `tiles` — straight RGBA8, a tile's bytes each — each in a fresh slot
    /// of `cel`, copied there by the write path in one submit: as many of
    /// them, the first, as the pool has room for. A tile is never written
    /// where one is stored ([`Write::put`] where it is told). The crate's
    /// tests' store, on whatever thread they call it — the app's hands its
    /// copy to the engine's thread (`gpu_engine_pool_store`).
    #[cfg(test)]
    pub(crate) fn store(&mut self, engine: &Engine, cel: Cel, tiles: &[&[u8]]) -> Option<Vec<TileAt>> {
        if let Some(tile) = tiles.iter().find(|tile| tile.len() as u64 != TILE_BYTES) {
            return fail(format!("a tile of {} bytes; one holds {TILE_BYTES}", tile.len()));
        }
        let places = self.places(engine, cel, tiles.len());
        if places.is_empty() {
            return Some(places);
        }
        // ⚠️No test reaches the release below: `put` refuses only what this
        // store never hands it (a tile past the staging, a place past the
        // pages — a mutant of it lived, 11-07). It stands so a refusal the
        // write path learns later holds no slot for a tile that never landed.
        if self.writing(places.clone()).write(engine, tiles).is_none() {
            for &at in &places {
                self.release(at);
            }
            return None;
        }
        Some(places)
    }

    /// One more hold of the tile at `at`. Nothing where none holds it: a
    /// free slot is handed out by [`Pool::fresh`], not held. A picture
    /// laid over a film holds the film's tiles it shows as they are
    /// (kept.rs, `Kept::made_over`).
    // ⏳An undo record's or a stroke result's hold: the flip lane's
    // (connection-round-checklist B ⓓ) — while the CPU's tiles are the
    // canonical ones, the app's map holds each slot once.
    pub(crate) fn hold(&mut self, at: TileAt) -> Option<()> {
        let holds = &mut self.held(at)?.holds[usize::from(at.slot)];
        *holds += 1;
        Some(())
    }

    /// One hold fewer of the tile at `at`: its slot free once none holds
    /// it — and the place it lay folded in, where it did —, and its page
    /// nobody's once every slot of it is. Nothing where none holds it.
    pub(crate) fn release(&mut self, at: TileAt) -> Option<()> {
        let (book, slot) = (self.held(at)?, usize::from(at.slot));
        book.holds[slot] -= 1;
        if book.holds[slot] > 0 {
            return Some(());
        }
        book.free.push(at.slot);
        if book.free.len() == book.holds.len() {
            book.cel = None;
        }
        // Its folded place goes with it: the slot names no tile, and the
        // one it is handed out to next lies in it as it is.
        if let Some(lies) = TileAt::of_word(book.lying[slot]) {
            self.lies_at(at, NO_TILE);
            self.folded_let_go(lies);
        }
        Some(())
    }

    /// The bytes of the tiles at `places`, each held, copied into `into` —
    /// a tile's bytes each, in order — in one submit and one map: what a
    /// save, a cel cooled and an undo record parked read of the tiles the
    /// pool holds (connection-round-checklist B ⓓ). Nothing where one is
    /// not held or `into` is not their bytes.
    pub(crate) fn read(&self, engine: &Engine, places: &[TileAt], into: &mut [u8]) -> Option<()> {
        let bytes = places.len() as u64 * TILE_BYTES;
        if into.len() as u64 != bytes {
            return fail(format!("{} bytes to read {} tiles into; they hold {bytes}", into.len(), places.len()));
        }
        self.all_held(places)?;
        // ⚠️No test tells this from a read of nothing mapped: DX12 maps a
        // buffer of no bytes as one of some (mutant R03 lived, 11-09). It
        // stands so a read of no tile waits for no GPU and asks no driver
        // for a buffer of no bytes.
        if places.is_empty() {
            return Some(());
        }
        let readback = engine.readback(bytes);
        self.gathered(engine, places, &readback)?;
        engine.mapped_into(&readback, into)
    }

    /// The tiles at `places`, each held, side by side in a buffer of their
    /// own the CPU maps — a tile's bytes each, in order —, their copy
    /// submitted and none of it waited for: what a readout maps once the
    /// GPU is done, the wait the engine's thread's
    /// (`gpu_engine_pool_readout`) — the copies the app keeps of what the
    /// engine alone holds, taken while a hand rests with no wait on the
    /// thread its frames are built on (🗣️관제 2026-11-12,
    /// a-lost-gpu-device-keeps-the-unsaved-tiles: 「붙잡으면 (B) 안에서
    /// 엔진 스레드 비동기로 옮긴 뒤 착지한다」).
    ///
    /// 🚨THE BYTES ARE THE ONES EACH SLOT HOLDS AS THIS IS ASKED: the copy
    /// is submitted here, ahead of whatever is submitted after it, so a
    /// slot let go and written over meanwhile is read as it was — the tile
    /// that was asked for, never the one that took its slot.
    ///
    /// Nothing where one is not held, or none is asked.
    pub(crate) fn read_out(&self, engine: &Engine, places: &[TileAt]) -> Option<wgpu::Buffer> {
        self.all_held(places)?;
        if places.is_empty() {
            return fail("no tile to read out");
        }
        let out = engine.readback(places.len() as u64 * TILE_BYTES);
        self.gathered(engine, places, &out)?;
        Some(out)
    }

    /// Whether a tile is held at each of `places` ([`Self::holding`]).
    fn all_held(&self, places: &[TileAt]) -> Option<()> {
        places.iter().try_for_each(|&at| self.holding(at))
    }

    /// The page of the tile at `at`, held; nothing where the pool has no
    /// such slot or none holds it.
    fn held(&mut self, at: TileAt) -> Option<&mut Slots> {
        self.holding(at)?;
        self.pages[usize::from(at.page)].as_mut().and_then(Page::slots_mut)
    }

    /// Whether a tile is held at `at`; nothing where the pool has no such
    /// slot or none holds it.
    fn holding(&self, at: TileAt) -> Option<()> {
        let pages = self.pages.len();
        let book = match self.pages.get(usize::from(at.page)) {
            Some(Some(Page::Tiles(book))) => book,
            // A tile is held by the slot that names it, wherever it lies.
            Some(Some(Page::Folded(_))) => return fail(format!("{at:?} on a page of folded tiles")),
            Some(None) => return fail(format!("{at:?} on a page given back")),
            None => return fail(format!("{at:?} of a pool of {pages} pages")),
        };
        match book.holds.get(usize::from(at.slot)).copied() {
            Some(0) => fail(format!("{at:?} is free")),
            Some(_) => Some(()),
            None => fail(format!("{at:?} past a page of {} tiles", book.holds.len())),
        }
    }

    /// The holds of the tile at `at` — none where the pool has no such
    /// slot. ⚠️Said of none as no failure, where [`Pool::holding`] says one:
    /// a picture let go asks it of every tile it held.
    fn holds(&self, at: TileAt) -> u32 {
        let page = self.pages.get(usize::from(at.page)).and_then(Option::as_ref).and_then(Page::slots);
        page.and_then(|page| page.holds.get(usize::from(at.slot)).copied()).unwrap_or(0)
    }

    /// A page for `cel`'s tiles where it has none with a slot free: one of
    /// nobody's, its then; one of another cel's with a slot free; or a new
    /// one, its — where one was given back, made again in its place.
    fn claimed(&mut self, engine: &Engine, cel: Cel) -> Result<usize, Full> {
        if let Some(page) = self.pages.iter().position(nobody_s) {
            let slots = self.pages[page].as_mut().and_then(Page::slots_mut);
            slots.expect("a page nobody's is one of tiles").cel = Some(cel);
            return Ok(page);
        }
        let with_room = |page: &Option<Page>| {
            page.as_ref().and_then(Page::slots).is_some_and(|slots| !slots.free.is_empty())
        };
        if let Some(page) = self.pages.iter().position(with_room) {
            return Ok(page);
        }
        let (given_back, grows) = self.next_page()?;
        // 🚨Its own bytes are asked here, on the caller's thread: only the
        // OS's count is the device's. 🔬The Surface, FNK_02 cut 59 as the
        // onion's ghosts were laid (2026-11-15, card
        // a-picture-lay-holds-the-raster-thread): a pool full by its bytes
        // went to the engine's thread to be told so, behind the copies
        // handed over unwaited — at each of the 567 stores a pass its
        // ledger made room for, 692 ms of the UI's thread a pass against
        // 41, one up to 27.7 ms.
        if !self.within_its_bytes(grows) {
            self.let_the_page_ahead_go(engine);
            return Err(Full);
        }
        // A page made ahead is taken here, no thread of the engine's asked
        // ([`Pool::make_a_page_ahead`]) — where it was asked against the
        // budget kept to now: one asked against another is a page the
        // budget this pool keeps to never allowed.
        let asked = self.bounds().asked();
        let buffer = match self.ahead.taken_as(asked) {
            Some(page) => page,
            // 🚨The budget is asked and the page made on the pages' thread
            // ([`Engine::on_pages_thread`]), where a store's books are kept
            // on its caller's (B1-b of the-ui-thread-never-enters-the-driver,
            // 2026-11-15): the OS's count and the driver are the device's.
            // ↩️Till 2026-11-16 on the engine's thread, where the bodies
            // handed over behind it waited for it (`Engine`'s `pages`).
            // 🔬Six stores of 371 made a page, S5_BA cut 352 filling its
            // band — 11 to 28 ms each for a page of 128 MiB, the store's
            // caller waiting (k884): the wait a page made ahead spares.
            None => engine
                .on_pages_thread(|| {
                    // The pages' thread runs what it is handed in turn: a
                    // page being made ahead is made by now.
                    // ⚠️No test tells this from the page made again below
                    // (mutant P14 lived, 11-15): the same page either way,
                    // the pages' thread's milliseconds apart.
                    if let Some(page) = self.ahead.taken_as(asked) {
                        return Some(page);
                    }
                    // One made against another budget goes, here where the
                    // pages are let go, and the page is asked for as the
                    // pool stands.
                    drop(self.ahead.taken());
                    // ⚠️No test lowers the budget the OS gives: `fits` is
                    // tried on the numbers, and a page here against a
                    // budget kept to in its place
                    // ([`Pool::set_budget_instead`]).
                    let memory = platform::video_memory(&engine.adapter);
                    if !self.fits(memory, grows) {
                        return None;
                    }
                    // The OS's budget is asked here, not set on the
                    // instance as wgpu's `memory_budget_thresholds`: a
                    // threshold refuses whatever the engine makes, its
                    // other makes have no error scope, and wgpu's default
                    // for an error none catches panics
                    // (wgpu-30.0.1/src/backend/wgpu_core.rs:692) — past the
                    // FFI, the app aborts. A pool refusing at the budget
                    // lets a pass's own buffers go over it a while instead.
                    // Nor `for_device_loss`: the canonical tiles are on the
                    // device (브러시/렌더링 11-07, 관제 09:04).
                    made(engine, "pool page", self.page_bytes())
                })
                .ok_or(Full)?,
        };
        // The first slot first: the one handed out last is first in line.
        let free = (0..self.slots).rev().map(|slot| slot as u16).collect();
        let (holds, stamps) = (vec![0; self.slots], Arc::new(vec![0; self.slots]));
        let lying = Arc::new(vec![NO_TILE; self.slots]);
        let asked_to_fold = vec![0; self.slots];
        let book = Page::Tiles(Slots { holds, free, cel: Some(cel), stamps, lying, asked_to_fold });
        Ok(self.page_put(given_back, buffer, book))
    }

    /// Puts a page made — its buffer and its book — in the place of the
    /// one given back, `given_back`, or after the last: where it is.
    fn page_put(&mut self, given_back: Option<usize>, buffer: wgpu::Buffer, book: Page) -> usize {
        match given_back {
            Some(page) => {
                self.buffers[page] = buffer;
                self.pages[page] = Some(book);
                page
            }
            None => {
                self.buffers.push(buffer);
                self.pages.push(Some(book));
                self.pages.len() - 1
            }
        }
    }

    /// Whether the pool's bytes grown by `grows` keep within them, and what
    /// this process uses grown so keeps within the budget ([`Bounds::fits`]).
    fn fits(&self, memory: Option<VideoMemory>, grows: u64) -> bool {
        self.bounds().fits(memory, grows)
    }

    /// Whether the pool's bytes grown by `grows` keep within the bytes it
    /// may make ([`Pool::set_most_bytes`]): its own numbers, whatever
    /// thread asks.
    fn within_its_bytes(&self, grows: u64) -> bool {
        self.bounds().within_its_bytes(grows)
    }

    /// The bounds a page is made within, as the pool stands.
    fn bounds(&self) -> Bounds {
        Bounds { bytes: self.bytes(), most_bytes: self.most_bytes, budget_instead: self.budget_instead }
    }

    /// Where the next page is made — in the place of the first one given
    /// back, else after the last — and the bytes it grows the pool by; full
    /// where a `TileAt` names no page more.
    fn next_page(&self) -> Result<(Option<usize>, u64), Full> {
        self.next_page_of(self.page_bytes())
    }

    /// [`Pool::next_page`] for a page of `bytes`: a page of folded tiles
    /// is made where a page of tiles is.
    fn next_page_of(&self, bytes: u64) -> Result<(Option<usize>, u64), Full> {
        let given_back = self.pages.iter().position(Option::is_none);
        if given_back.is_none() && self.pages.len() >= self.most_pages {
            return Err(Full);
        }
        Ok((given_back, bytes - given_back.map_or(0, |page| self.buffers[page].size())))
    }

    /// Has the pages' thread ([`Engine::pages_posted`]) make the pool's next
    /// page ahead of the tile that will need it, waiting for none of it:
    /// where less than half a page is free on the pages made, none is made
    /// or being made, and the pool may make one — within its bytes, asked
    /// here; within the budget and as the driver allows, asked there
    /// ([`Bounds::fits`], [`made`]),
    /// and not again till the pool's bytes or the budget kept to instead
    /// move. [`Pool::claimed`] takes it. Where the pool may make no page
    /// more, one made goes.
    ///
    /// 🔬WHY (card a-picture-lay-holds-the-raster-thread, 2026-11-15): with
    /// the onion's cels let go once laid (브러시/렌더링's lane
    /// walk-looks-and-lets-go, the user's Q1 「굽고 나면 놓는다」), the pool
    /// on the Surface held 640 MB and made its pages as FNK_02 cut 59's
    /// ghosts were laid — 35.0, 39.3, 40.6 and 56.6 ms of the UI's thread,
    /// each a store waiting for the engine's thread to make one behind the
    /// copies handed over before it.
    ///
    /// ⛔Not a page kept spare from the first (캔버스 베이스's call, 11-15):
    /// on a weak device it is 128 MiB held for nothing till the pool needs
    /// it. One is made once the pool is half a page from needing it, and
    /// none past the bytes it may make — a pool at its line keeps none.
    /// ⏳Half a page is my number, not measured against how fast a pass
    /// fills one. ⛔Not counted in [`Pool::bytes`]: the books count a page
    /// once a store takes it, and the pages' thread makes this one in its
    /// own time — a count that moved with it would answer two reads of a
    /// pool no store touched between them differently.
    ///
    /// 🔬NOT ON THE ENGINE'S THREAD (↩️till 2026-11-16 — the Surface, FNK_02
    /// cut 59 with the onion on, 02:4x): a page made ahead was made there,
    /// 48 to 55 ms, 156 to 195 ms as memory filled, and the UI's waits
    /// handed over behind it stood as long — a screen let go 61.5 ms, a
    /// composite's done 98.7 ms. A store asked for it once its copy was
    /// handed over, which would have waited 11 to 28 ms behind the page;
    /// on a thread of its own it is asked where a slot is taken
    /// ([`Pool::fresh`]).
    fn make_a_page_ahead(&mut self, engine: &Engine) {
        let grows = self.next_page().ok().map(|(_, grows)| grows).filter(|&grows| self.within_its_bytes(grows));
        let Some(grows) = grows else {
            self.let_the_page_ahead_go(engine);
            return;
        };
        let free: usize =
            self.pages.iter().flatten().filter_map(Page::slots).map(|slots| slots.free.len()).sum();
        if 2 * free >= self.slots {
            return;
        }
        let page = ("pool page", self.page_bytes());
        self.ahead.asked_of(engine, page, (self.bounds(), grows), || ());
    }

    /// Lets the page made ahead go, on the pages' thread — where pages are
    /// made — and waits for none of it; calls off one being made
    /// ([`Spare::called_off`]).
    fn let_the_page_ahead_go(&self, engine: &Engine) {
        let_go_on_the_pages_thread(engine, self.ahead.called_off());
    }

    fn page_bytes(&self) -> u64 {
        self.slots as u64 * TILE_BYTES
    }
}

/// Lets `page` go on the pages' thread ([`Engine::pages_posted`]), its
/// caller waiting for none of it: a buffer let go is the driver's.
/// Nothing where there is none.
fn let_go_on_the_pages_thread(engine: &Engine, page: Option<wgpu::Buffer>) {
    if let Some(page) = page {
        let handed = Sent(page);
        engine.pages_posted(move || drop(handed.taken()));
    }
}

/// The pool the engine keeps its pictures in — a screen's canvas, a
/// frame's picture kept for playback (`composite::kept`, `Kept`): each
/// a cel of it, its tiles in slots held as a cel's are and
/// free once it is dropped, on pages that stay made till they are given
/// back ([`Pictures::give_back`]) — the cels' law, by the cels' code.
///
/// 🗣️유저 2026-11-13 (H57-Q1 「C · 합성 전체를 엔진 스레드로 … 할수있는거
/// 다하고싶음」, and in chat 「B도 하면 좋은건가? 통일적인 면에서도
/// 좋아보이는데 … 근본/구조적 해결을 원해. 작업이 크더라도」 — B is this).
/// ↩️Till then a picture was kept on buffers of its own, made with it and
/// gone with it. 🔬Surface Pro 11, S5_BA cut 352 (캔버스 베이스, H57,
/// 2026-11-13): a picture let go emptied a 256 MiB block of the device's
/// allocator, which destroyed it, and the next picture made it again —
/// 32 to 55 ms each on the thread that asked, five such stops (68 ms the
/// longest) each time the playback's pictures were laid again.
///
/// ⛔Not the cels' pool: that one is [`Full`] at the budget its store
/// gives, and its store cools a cel for it. A picture is let go by the
/// budget of what keeps it — the app's picture stores — so this pool
/// refuses at no budget of its own, only where the driver does, as a
/// picture's own buffer was refused.
#[derive(Clone, Default)]
pub(crate) struct Pictures(Arc<Shelf>);

/// What every hand on the pictures' pool shares: its books, and the bytes
/// of the tiles no picture weighs ([`Told::unowned`]) as the books last
/// left them — read by a thread that waits for no book
/// ([`Pictures::unowned_bytes`]).
#[derive(Default)]
struct Shelf {
    books: Mutex<Books>,
    unowned: AtomicU64,
}

/// What the pictures' pool keeps: its pages, and which of the tiles on
/// them a picture need not make ([`Told`]).
#[derive(Default)]
struct Books {
    pool: Option<Pool>,
    told: Told,
}

/// ONE TILE FOR THE SAME INPUT (F-610): the pictures' tiles by what each is
/// made of (composite's `Plan::made_of` — the steps laid on it, and the
/// stamp of every stored tile they read), so a picture whose tile is made
/// of what a kept one is holds that one and makes none.
///
/// 🗣️유저 2026-11-18 (F-610, in chat): 「셀 원본을 합쳐서 1048 인데 합성 그림이
/// 6000 인 게 아주 말이 안 되네. 적어도 1048 이거나 그거보단 낮아야 … 그게
/// 아니라면 원본이 있는데 재생 소재를 만들 이유가 없잖아」 — and F-610-Q2
/// 「같은 타일은 한 벌만」. 🔬Main PC, a copy of the user's .tvpp (canvas
/// 7751×4396, 2135 tiles a picture, 27 pictures of one cut, 2026-11-18):
/// 38.2% of the tiles had the paper alone laid on them and 57.1% one row —
/// nearly all of it a row no frame of the cut changes —, each kept again
/// by every frame's picture: 3602.8 MB, where one tile for the same input
/// is 253.8 MB.
///
/// A tile is told for as long as a picture holds it: its last hold gone,
/// its slot is free and its telling forgotten ([`Pictures::release`]).
#[derive(Default)]
struct Told {
    /// The tile made of each telling.
    made: HashMap<MadeOf, TileAt>,
    /// Each such tile's telling: what is forgotten with the tile.
    of: HashMap<TileAt, MadeOf>,
    /// The tiles their maker let go while another picture holds them:
    /// weighed by no picture (kept.rs, `Kept::bytes` — a picture weighs
    /// the tiles it made), and kept all the same.
    unowned: HashSet<TileAt>,
}

impl Told {
    /// The tile at `at` is no picture's: told by nothing, nobody's.
    fn forget(&mut self, at: TileAt) {
        if let Some(of) = self.of.remove(&at) {
            self.made.remove(&of);
        }
        self.unowned.remove(&at);
    }
}

impl Pictures {
    fn kept(&self) -> MutexGuard<'_, Books> {
        self.0.books.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// A pool of pages of `slots` tiles, for a test to see a picture go on
    /// to its next page.
    #[cfg(test)]
    pub(crate) fn sized(slots: usize) -> Option<Self> {
        Some(Self::of(Self::unbounded(Pool::sized(slots, MOST_NAMED, u64::MAX)?)))
    }

    /// The pictures kept in `pool`, for a test to say how many pages it
    /// makes.
    #[cfg(test)]
    fn of(pool: Pool) -> Self {
        let books = Mutex::new(Books { pool: Some(pool), told: Told::default() });
        Self(Arc::new(Shelf { books, unowned: AtomicU64::new(0) }))
    }

    /// `pool` kept to no budget (⛔ above).
    fn unbounded(mut pool: Pool) -> Pool {
        pool.set_budget_instead(Some(u64::MAX));
        pool
    }

    /// What `work` answers of the pool — made here where no picture has
    /// asked yet. ⚠️The pool is held for as long as `work` runs, so no run
    /// is made within it: a picture holds its slots first and is run onto
    /// them after ([`Pictures::fresh`]) — a picture dropped on one thread
    /// waits for no run of another's.
    fn with<T>(&self, engine: &Engine, work: impl FnOnce(&mut Pool) -> Option<T>) -> Option<T> {
        self.told_with(engine, |pool, _| work(pool))
    }

    /// [`Self::with`], and what the pool's tiles are told by beside it.
    fn told_with<T>(
        &self,
        engine: &Engine,
        work: impl FnOnce(&mut Pool, &mut Told) -> Option<T>,
    ) -> Option<T> {
        let mut kept = self.kept();
        if kept.pool.is_none() {
            let pool = Pool::paged(engine, MOST_PICTURE_PAGE_BYTES, u64::MAX)?;
            kept.pool = Some(Self::unbounded(pool));
        }
        let Books { pool, told } = &mut *kept;
        work(pool.as_mut().expect("made above"), told)
    }

    /// A picture's name in the pool ([`Pool::cel`]).
    pub(crate) fn cel(&self, engine: &Engine) -> Option<Cel> {
        self.with(engine, |pool| Some(pool.cel()))
    }

    /// The tiles a page of the pool takes.
    pub(crate) fn slots(&self, engine: &Engine) -> Option<usize> {
        self.with(engine, |pool| Some(pool.slots()))
    }

    /// One more hold of each of `places` ([`Pool::hold`]) — and none more
    /// of any where one of them is not held.
    pub(crate) fn hold(&self, engine: &Engine, places: &[TileAt]) -> Option<()> {
        self.with(engine, |pool| {
            let held = places.iter().take_while(|&&at| pool.hold(at).is_some()).count();
            if held < places.len() {
                for &at in &places[..held] {
                    pool.release(at);
                }
                return None;
            }
            Some(())
        })
    }

    /// `count` fresh slots of `cel`, each held once ([`Pool::fresh`]), and
    /// the pool's pages as they then are: what a run is put onto. None
    /// held where the pool makes no page more.
    pub(crate) fn fresh(
        &self,
        engine: &Engine,
        cel: Cel,
        count: usize,
    ) -> Option<(Vec<TileAt>, Vec<wgpu::Buffer>)> {
        self.with(engine, |pool| {
            let mut places = Vec::with_capacity(count);
            while places.len() < count {
                match pool.fresh(engine, cel) {
                    Ok(at) => places.push(at),
                    Err(Full) => {
                        for &at in &places {
                            pool.release(at);
                        }
                        return fail("the pictures' pool makes no page more");
                    }
                }
            }
            Some((places, pool.pages().to_vec()))
        })
    }

    /// One more hold of the tile made of each of `made_of` where one is
    /// kept, and its place — none where no tile is made of it yet, or it
    /// is told by nothing ([`Told`]).
    pub(crate) fn held_as(
        &self,
        engine: &Engine,
        made_of: &[Option<MadeOf>],
    ) -> Option<Vec<Option<TileAt>>> {
        self.told_with(engine, |pool, told| {
            let held = |of: &Option<MadeOf>| {
                let at = *told.made.get(of.as_ref()?)?;
                pool.hold(at).map(|()| at)
            };
            Some(made_of.iter().map(held).collect())
        })
    }

    /// Whether a tile made of each of `made_of` is kept — none where it is
    /// told by nothing: what [`Self::held_as`] would hold, and holds none
    /// of. ⚠️Of the books as they are, no pool made for the asking.
    pub(crate) fn keeps(&self, made_of: &[Option<MadeOf>]) -> Vec<bool> {
        let kept = self.kept();
        made_of.iter().map(|of| of.as_ref().is_some_and(|of| kept.told.made.contains_key(of))).collect()
    }

    /// The tiles at `made` — each in a fresh slot, and run onto — told
    /// from here on by what each is made of: the tile the next picture
    /// made of the same holds ([`Self::held_as`]). A telling that has its
    /// tile keeps it.
    pub(crate) fn kept_as(&self, made: impl Iterator<Item = (MadeOf, TileAt)>) {
        let mut kept = self.kept();
        let told = &mut kept.told;
        for (of, at) in made {
            if !told.made.contains_key(&of) {
                told.made.insert(of.clone(), at);
                told.of.insert(at, of);
            }
        }
    }

    /// One hold fewer of each of `places`: a picture dropped, or its tile
    /// made again in another slot — a tile nobody holds then told by
    /// nothing. `left` are those of them their picture made and holds
    /// nowhere now: nobody's own from here on, for as long as another
    /// picture holds one ([`Self::unowned_bytes`]).
    pub(crate) fn release(
        &self,
        places: impl Iterator<Item = TileAt>,
        left: impl Iterator<Item = TileAt>,
    ) {
        let mut kept = self.kept();
        let Books { pool: Some(pool), told } = &mut *kept else {
            return;
        };
        let places: Vec<TileAt> = places.collect();
        for &at in &places {
            pool.release(at);
        }
        for at in places {
            if pool.holds(at) == 0 {
                told.forget(at);
            }
        }
        told.unowned.extend(left.filter(|&at| pool.holds(at) > 0));
        self.0.unowned.store(told.unowned.len() as u64 * TILE_BYTES, Ordering::Relaxed);
    }

    /// The bytes of the tiles pictures hold that none of them weighs — their
    /// maker gone ([`Told::unowned`]) —, as the last release left them:
    /// what the budgets and the census weigh beside each picture's own
    /// (`gpu_engine_pictures_unowned_bytes`). ⚠️Read off no book: the
    /// thread a frame is built on asks it, and a book may be held while a
    /// page is made ([`Self::with`]).
    pub(crate) fn unowned_bytes(&self) -> u64 {
        self.0.unowned.load(Ordering::Relaxed)
    }

    /// Whether this is the pool `other` is: a tile of one is no tile of
    /// another's pages.
    pub(crate) fn is(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0, &other.0)
    }

    /// The pages the tiles at `places` — each held — are on, each at its
    /// own place, as a plan takes a picture's: up to the last of them, and
    /// where none of them is on a page before it, the first that one is on
    /// in its place.
    ///
    /// ⚠️NOT THE POOL'S PAGES WHOLE: a picture that kept every page would
    /// keep made a page the pool gave back ([`Pictures::give_back`]) —
    /// a page is its buffer for as long as anyone keeps it. No pass binds a
    /// page none of its tiles is on (composite/mod.rs, `lay`), so what
    /// stands in such a place is read by nothing.
    pub(crate) fn pages_of(&self, places: impl Iterator<Item = TileAt>) -> Vec<wgpu::Buffer> {
        let kept = self.kept();
        let Some(pages) = kept.pool.as_ref().map(Pool::pages) else {
            return Vec::new();
        };
        let mut on = vec![false; pages.len()];
        for at in places {
            on[usize::from(at.page)] = true;
        }
        let (Some(first), Some(last)) = (on.iter().position(|&on| on), on.iter().rposition(|&on| on)) else {
            return Vec::new();
        };
        (0..=last).map(|page| pages[if on[page] { page } else { first }].clone()).collect()
    }

    /// The pool's pages, for a test to count them.
    #[cfg(test)]
    pub(crate) fn pages(&self) -> Vec<wgpu::Buffer> {
        self.kept().pool.as_ref().map_or_else(Vec::new, |pool| pool.pages().to_vec())
    }

    /// Gives back the pages no picture is on, the last first — the page made
    /// ahead first of all —, till the slots no picture holds are `most_idle`
    /// bytes or no such page is left ([`Pool::give_back`]). ⛔Not till the
    /// pages are that many: a page a picture is on is none of what is idle,
    /// and a line that moved under the pictures leaves them their pages
    /// (`gpu_engine_pictures_give_back`).
    pub(crate) fn give_back(&self, engine: &Engine, most_idle: u64) {
        if let Some(pool) = self.kept().pool.as_mut() {
            let held = pool.bytes() - pool.idle_bytes();
            pool.give_back(engine, held.saturating_add(most_idle));
        }
    }

    /// The bytes of the slots no picture holds on the pages made
    /// ([`Pool::idle_bytes`]), and of the page made ahead of the picture
    /// that will need it ([`Pool::ahead_bytes`]): made, and no picture's.
    ///
    /// ★The page made ahead counted (관제 2026-11-16 08:28 ①, card
    /// a-picture-lay-holds-the-raster-thread): the memory census reads this
    /// line, and the give-back weighs it (`gpu_engine_pictures_give_back`)
    /// — off it, the page would be a share of the GPU's memory no row names
    /// and no warning lets go.
    pub(crate) fn idle_bytes(&self) -> u64 {
        self.kept().pool.as_ref().map_or(0, |pool| pool.idle_bytes() + pool.ahead_bytes())
    }
}

/// Copies the tiles at `places` on `pages`, each as it is, into `into` —
/// a tile's bytes each, in order — and submits: a kept picture's off its
/// own pages, for a test to read. ↩️The pool's read too, till its tiles
/// could lie folded ([`Pool::gathered`], 2026-11-19).
#[cfg(test)]
pub(crate) fn gather(
    engine: &Engine,
    pages: &[wgpu::Buffer],
    places: &[TileAt],
    into: &wgpu::Buffer,
) {
    let mut encoder = engine
        .device()
        .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
    for (to, at) in (0..).step_by(TILE_BYTES as usize).zip(places) {
        let page = &pages[usize::from(at.page)];
        let from = u64::from(at.slot) * TILE_BYTES;
        encoder.copy_buffer_to_buffer(page, from, into, to, TILE_BYTES);
    }
    engine.queue.submit([encoder.finish()]);
}

/// Whether `page` is made and nobody's: a page of tiles, every slot of
/// it free. ⏳A page of folded tiles no tile lies on stays made: its
/// giving back is the lane's that gives a folded tile's slot back
/// (`folded.rs`).
fn nobody_s(page: &Option<Page>) -> bool {
    matches!(page, Some(Page::Tiles(Slots { cel: None, .. })))
}

/// A page's buffer of `size` bytes — a page or a page given back's stand-in
/// —, or none where the device refuses it for want of memory.
///
/// ⚠️No test reaches a driver's refusal: a 0% threshold opens no device,
/// wgpu's own zero buffer refused first
/// (wgpu-core-30.0.1/src/device/resource.rs:464), and wgpu makes no D3D12
/// buffer past 2 GiB (wgpu-hal-30.0.1/src/dx12/adapter.rs:916), too few
/// bytes for a driver to refuse.
///
/// ⚖️APART FROM wgpu's ALLOCATOR, ON WINDOWS ALONE
/// ([`platform::committed_buffer`] has the Surface's numbers): wgpu makes a
/// buffer within the one lock of its allocator, held as long as a new
/// block of the device's memory takes, and a page made on the pages'
/// thread so held each body of the engine's thread that made a buffer
/// meanwhile. ⏳Whether the Vulkan and Metal backends' allocators hold
/// their bodies so is not measured: Android's — the old devices', the
/// weakest — is to be (관제 2026-11-16 08:28, card
/// a-picture-lay-holds-the-raster-thread), and its pages made apart too
/// where they do.
fn made(engine: &Engine, label: &str, size: u64) -> Option<wgpu::Buffer> {
    let desc = wgpu::BufferDescriptor {
        label: Some(label),
        size,
        // Bound by the passes, copied to by the write path and copied
        // from where its bytes are read back (connection-round-checklist
        // B: saving, cooling, an undo record parked).
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    };
    #[cfg(windows)]
    return platform::committed_buffer(engine.device(), &desc);
    #[cfg(not(windows))]
    return made_by_wgpu(engine, &desc);
}

/// [`made`] by wgpu's own allocator: none where the device refuses it for
/// want of memory.
#[cfg(not(windows))]
fn made_by_wgpu(engine: &Engine, desc: &wgpu::BufferDescriptor) -> Option<wgpu::Buffer> {
    let made = engine.device().push_error_scope(wgpu::ErrorFilter::OutOfMemory);
    let buffer = engine.device().create_buffer(desc);
    match pollster::block_on(made.pop()) {
        Some(_) => None,
        None => Some(buffer),
    }
}

/// A pool that makes no page past `most_bytes` (1a ③ — its store gives
/// the budget). Null on failure; see the last error.
///
/// 🚨★A POOL IS ITS CALLER'S ALONE: its books — which slot holds what, and
/// its pages — are read and written by its verbs with no lock: on the
/// calling thread (`gpu_engine_pool_store`, `gpu_engine_pool_release`),
/// and on the engine's while the caller stays in the call
/// (`gpu_engine_pool_read`). So one thread calls a pool's verbs, one at a
/// time: the isolate that has it (`GpuPool`, which nothing makes again
/// from its address). What a body leans on it for
/// (the-ui-thread-never-enters-the-driver, 2026-11-15): one that waits for
/// the GPU leaves the engine's thread to the bodies behind it
/// (`Engine::wait_within`), and comes back to books no body of another
/// caller wrote meanwhile — a cel's pixels counted, read and then put
/// (`CelPixels::passed`), a read of the pool itself. Each verb's
/// `# Safety` says it by "its caller's alone".
///
/// # Safety
/// `engine` is live; the pool is freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_new(engine: *const Engine, most_bytes: u64) -> *mut Pool {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.on_thread(|| {
        Pool::new(engine, most_bytes).map_or(std::ptr::null_mut(), |pool| engine.hands(pool))
    })
}

/// # Safety
/// `pool` came from `gpu_engine_pool_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_free(pool: *mut Pool) {
    // SAFETY: see the function's contract.
    unsafe { let_go(pool) };
}

/// The side of the tiles a pool stores, in texels: a tile is that square of
/// straight RGBA8.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_tile_side() -> u32 {
    TILE
}

/// A cel of its own, by the number the store names it with.
///
/// # Safety
/// `pool` is live and its caller's alone (`gpu_engine_pool_new`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_cel(pool: *mut Pool) -> u32 {
    // SAFETY: see the function's contract.
    let pool = unsafe { &mut *pool };
    pool.cel().0
}

/// Gives the `count` tiles at `tiles` — straight RGBA8, a tile's bytes at
/// each — fresh slots of the cel `cel`, writes each one's place to `pages`
/// and `slots`, and hands their copy there to the engine's thread, waiting
/// for none of it ([`Pool::lands_unwaited`], which says how `told` is
/// called with `number`). Returns how many it gave a slot, the first of
/// them: all, or fewer where the pool is full at the next. The places of a
/// copy not written are told by [`gpu_engine_pool_unwritten`] too. Each
/// slot it gives has the next page made ahead where one is near
/// ([`Pool::fresh`]).
///
/// 🚨WHY UNWAITED (B1-b of the-ui-thread-never-enters-the-driver,
/// 2026-11-15): after the screen's compose and show were handed over, the
/// store was what the UI's thread waited on most — 395 calls and 630 ms of
/// S5_BA cut 352 filling its band, up to 30.6 ms one (k851); of its body,
/// the staging made, mapped and filled took 68%, the put and submit 22%
/// (k884). The books stay the caller's, so its slots are told at once, as
/// before. ⛔The bytes are not copied here first: that copy is the staging's
/// own, which the caller would then pay.
///
/// # Safety
/// `pool` and `engine` are live, the pool made on `engine` and its
/// caller's alone (`gpu_engine_pool_new`); `tiles` holds `count` pointers
/// to a tile's bytes each, alive till `told` is called — the engine's
/// thread reads them then; `pages` and `slots` hold `count` each; and
/// `told` is one any thread may call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_store(
    pool: *mut Pool,
    engine: *const Engine,
    cel: u32,
    tiles: *const *const u8,
    count: usize,
    pages: *mut u16,
    slots: *mut u16,
    told: extern "C" fn(u64, bool),
    number: u64,
) -> usize {
    // SAFETY: see the function's contract.
    let (pool, engine) = unsafe { (&mut *pool, &*engine) };
    // SAFETY: `tiles` holds `count` pointers.
    let bytes: Vec<*const u8> = (0..count).map(|at| unsafe { *tiles.add(at) }).collect();
    let put = move |engine: &Engine, writing: &Writing| {
        let tiles: Vec<&[u8]> = bytes
            .iter()
            // SAFETY: a tile's bytes at each pointer, alive till `told` is
            // called (the function's contract).
            .map(|&at| unsafe { std::slice::from_raw_parts(at, TILE_BYTES as usize) })
            .collect();
        writing.write_or_say(engine, &tiles)
    };
    // SAFETY: each pointer's bytes are alive till `told` is called (the
    // function's contract); `told` is one any thread may call.
    let places = unsafe { pool.lands_unwaited(engine, (Cel(cel), count), (told, number), put) };
    for (at, place) in places.iter().enumerate() {
        // SAFETY: `pages` and `slots` hold `count` each, and no more are given.
        unsafe {
            *pages.add(at) = place.page;
            *slots.add(at) = place.slot;
        }
    }
    places.len()
}

/// Writes to `pages` and `slots` the places stores handed over unwaited
/// held and did not write since this was last asked — `capacity` at most,
/// the rest kept for the next ask — and returns how many it wrote: theirs
/// to let go, whose tiles are not there ([`gpu_engine_pool_store`]).
///
/// # Safety
/// `pool` is live and its caller's alone (`gpu_engine_pool_new`), and
/// `pages` and `slots` hold `capacity` each.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_unwritten(
    pool: *mut Pool,
    pages: *mut u16,
    slots: *mut u16,
    capacity: usize,
) -> usize {
    // SAFETY: see the function's contract.
    let pool = unsafe { &mut *pool };
    let unwritten: Vec<TileAt> = {
        let mut held = pool.unwritten.held();
        let taken = held.len().min(capacity);
        held.drain(..taken).collect()
    };
    for (at, place) in unwritten.iter().enumerate() {
        // SAFETY: `pages` and `slots` hold `capacity` each, and no more are written.
        unsafe {
            *pages.add(at) = place.page;
            *slots.add(at) = place.slot;
        }
    }
    unwritten.len()
}

/// Hands the engine's thread a fold of the tiles of `pool` next to fold —
/// `most` of them at most ([`Pool::to_fold`]) — by the kernels `fold`,
/// waiting for none of it ([`Pool::folds_unwaited`], which says how
/// `told` is called with `number`, and why the kernels are handed in):
/// `gpu_engine_pool_settle` is its caller's once it is told.
/// Returns how many it handed over; none, and `told` is not called — no
/// tile of the pool's is left to fold as it stands.
///
/// # Safety
/// `pool` and `engine` are live, the pool made on `engine` and its
/// caller's alone (`gpu_engine_pool_new`); `fold` came from
/// `gpu_engine_fold_new` on `engine` and is alive till `told` is called;
/// `told` is one any thread may call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_fold(
    pool: *mut Pool,
    engine: *const Engine,
    fold: *const Fold,
    most: usize,
    told: extern "C" fn(u64, bool),
    number: u64,
) -> usize {
    // SAFETY: see the function's contract.
    let (pool, engine) = unsafe { (&mut *pool, &*engine) };
    let tiles = pool.to_fold(most);
    // SAFETY: `fold` is alive till `told` is called, and `told` is one any
    // thread may call (the function's contract).
    unsafe { pool.folds_unwaited(engine, fold, &tiles, (told, number)) }
}

/// Gives the tiles the folds told have folded their places, and hands
/// their copy there to the engine's thread, waiting for none of it
/// ([`Pool::settles_unwaited`]). Returns how many it settled.
///
/// # Safety
/// `pool` and `engine` are live, the pool made on `engine` and its
/// caller's alone (`gpu_engine_pool_new`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_settle(pool: *mut Pool, engine: *const Engine) -> usize {
    // SAFETY: see the function's contract.
    let (pool, engine) = unsafe { (&mut *pool, &*engine) };
    pool.settles_unwaited(engine)
}

/// Lets the slot at (`page`, `slot`) go — the store let its tile go. False
/// where none holds it; see the last error.
///
/// # Safety
/// `pool` is live and its caller's alone (`gpu_engine_pool_new`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_release(pool: *mut Pool, page: u16, slot: u16) -> bool {
    // SAFETY: see the function's contract.
    let pool = unsafe { &mut *pool };
    pool.release(TileAt { page, slot }).is_some()
}

/// Reads the `count` tiles `tiles` names — each a tile's word
/// ([`TileAt::word`]) — back into `into`, a tile's bytes each, in order
/// ([`Pool::read`]). False where one is not held; see the last error.
///
/// # Safety
/// `pool` and `engine` are live, the pool made on `engine` and its
/// caller's alone (`gpu_engine_pool_new`); `tiles` holds `count` words and
/// `into` the bytes of `count` tiles.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_read(
    pool: *const Pool,
    engine: *const Engine,
    tiles: *const u32,
    count: usize,
    into: *mut u8,
) -> bool {
    // SAFETY: see the function's contract.
    let (pool, engine) = unsafe { (&*pool, &*engine) };
    engine.on_thread(|| {
        // SAFETY: `tiles` holds `count` words.
        let Some(places) = (unsafe { named(tiles, count) }) else {
            return false;
        };
        // SAFETY: `into` holds the bytes of `count` tiles.
        let into = unsafe { std::slice::from_raw_parts_mut(into, count * TILE_BYTES as usize) };
        pool.read(engine, &places, into).is_some()
    })
}

/// The `count` tiles `tiles` names — each a tile's word ([`TileAt::word`])
/// — on their way back ([`Pool::read_out`]): their bytes as their slots
/// hold them now, a tile's each, in order, for a readout to map once the
/// GPU is done (`gpu_engine_readout_map_then`, the wait the engine's
/// thread's) and hand over as rows of a tile's bytes
/// (`gpu_engine_readout_rows`).
/// Submits the work and waits for none of it. Null where one is not held
/// or none is asked; see the last error.
///
/// # Safety
/// `pool` and `engine` are live, the pool made on `engine` and its
/// caller's alone (`gpu_engine_pool_new`); `tiles` holds `count` words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_readout(
    pool: *const Pool,
    engine: *const Engine,
    tiles: *const u32,
    count: usize,
) -> *mut Readout {
    // SAFETY: see the function's contract.
    let (pool, engine) = unsafe { (&*pool, &*engine) };
    engine.on_thread(|| {
        // SAFETY: `tiles` holds `count` words.
        let places = unsafe { named(tiles, count) };
        let out = places.and_then(|places| pool.read_out(engine, &places));
        readout(engine, out, count as u64 * TILE_BYTES)
    })
}

/// The tiles the `count` words at `tiles` name, or nothing where one names
/// none; see the last error.
///
/// # Safety
/// `tiles` holds `count` words.
unsafe fn named(tiles: *const u32, count: usize) -> Option<Vec<TileAt>> {
    // SAFETY: see the function's contract.
    let words = unsafe { std::slice::from_raw_parts(tiles, count) };
    let places = words.iter().copied().map(TileAt::of_word).collect::<Option<Vec<_>>>();
    places.or_else(|| fail("a tile to read named by no tile's word"))
}

/// Makes no page more past `most_bytes` ([`Pool::set_most_bytes`]) — the
/// store's budget as the allowance moves, and past it for the tiles one of
/// its calls holds.
///
/// # Safety
/// `pool` is live and its caller's alone (`gpu_engine_pool_new`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_most_bytes(pool: *mut Pool, most_bytes: u64) {
    // SAFETY: see the function's contract.
    let pool = unsafe { &mut *pool };
    pool.set_most_bytes(most_bytes);
}

/// Keeps to `bytes` in place of the budget the OS gives this process
/// ([`Pool::set_budget_instead`]); the OS's again where negative.
///
/// # Safety
/// `pool` is live and its caller's alone (`gpu_engine_pool_new`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_budget_instead(pool: *mut Pool, bytes: i64) {
    // SAFETY: see the function's contract.
    let pool = unsafe { &mut *pool };
    pool.set_budget_instead(u64::try_from(bytes).ok());
}

/// Gives back the pages nobody holds till the pages hold `most_bytes`
/// ([`Pool::give_back`]).
///
/// # Safety
/// `pool` and `engine` are live, the pool made on `engine` and its
/// caller's alone (`gpu_engine_pool_new`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_give_back(pool: *mut Pool, engine: *const Engine, most_bytes: u64) {
    // SAFETY: see the function's contract.
    let (pool, engine) = unsafe { (&mut *pool, &*engine) };
    engine.on_thread(|| {
        pool.give_back(engine, most_bytes);
    })
}

/// The bytes of the pages a pool has made ([`Pool::bytes`]).
///
/// # Safety
/// `pool` is live and its caller's alone (`gpu_engine_pool_new`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_bytes(pool: *const Pool) -> u64 {
    // SAFETY: see the function's contract.
    let pool = unsafe { &*pool };
    pool.bytes()
}

/// The bytes of the page a pool made ahead of the store that needs it
/// ([`Pool::ahead_bytes`]).
///
/// # Safety
/// `pool` is live and its caller's alone (`gpu_engine_pool_new`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_ahead_bytes(pool: *const Pool) -> u64 {
    // SAFETY: see the function's contract.
    let pool = unsafe { &*pool };
    pool.ahead_bytes()
}
