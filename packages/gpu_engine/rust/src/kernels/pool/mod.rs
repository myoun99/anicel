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
//! gives this process, nor one the driver refuses: it is [`Full`], one
//! answer to all three, and its store cools a cel — reads its tiles back,
//! releases them — and asks again (gpu-canonical-store 11-07 09:00, 관제
//! 09:04: 「한 증상에 법 하나」).
//!
//! The app stores through the C ABI below (connection-round-checklist B,
//! screen-on-the-engine): tiles it holds on the CPU, each in a fresh slot
//! of a cel, and back to the pool when it lets one go. While the CPU's
//! tiles are the canonical ones (2단계), a full pool is answered by letting
//! tiles not shown go, as the app's tile pictures were: the app's ledger
//! (lib/src/native/engine_tile_ledger.dart) lets go what none of its calls
//! holds, and stores what one holds past the bytes it gives.

#[cfg(test)]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{TILE, TILE_BYTES, TileAt};
use crate::kernels::shared::room;
use crate::kernels::write::Write;
use crate::platform::{self, VideoMemory};

/// The most a page holds where a binding holds more (1a ④).
const MOST_PAGE_BYTES: u64 = 128 << 20;
/// The slots a page may have and the pages a pool may: a `TileAt` names
/// each by a u16.
const MOST_NAMED: usize = u16::MAX as usize + 1;

/// A cel the pool stores tiles for — what names the pages its tiles go to
/// first.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Cel(u32);

/// The pool makes no page more: past its bytes, past the OS's budget,
/// refused by the driver, or past what a `TileAt` names.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Full;

/// What a page's slots hold.
struct Page {
    /// Each slot's holds; a slot of none is free.
    holds: Vec<u32>,
    /// The free slots, the one released last at the end.
    free: Vec<u16>,
    /// The cel whose tiles go to it first; none while every slot is free.
    cel: Option<Cel>,
}

pub(crate) struct Pool {
    buffers: Vec<wgpu::Buffer>,
    /// Each page's slots; none where the page was given back and a tile's
    /// stand-in is its buffer, as a `TileAt` names a page by its place.
    pages: Vec<Option<Page>>,
    slots: usize,
    most_pages: usize,
    most_bytes: u64,
    cels: u32,
}

impl Pool {
    /// A pool of pages as large as a binding of this device holds, 128 MiB
    /// at most, that makes no more pages than `most_bytes` hold — 1a ③'s
    /// budget, its store's to give.
    pub(crate) fn new(engine: &Engine, most_bytes: u64) -> Option<Self> {
        let slots = (room(engine).min(MOST_PAGE_BYTES) / TILE_BYTES) as usize;
        // ⚠️No test reaches the pages' bound: 65,536 pages to make. It
        // stands so a page past what a TileAt names is refused, not named
        // as another.
        Self::sized(slots, MOST_NAMED, most_bytes)
    }

    /// A pool of pages of `slots` tiles, `most_pages` pages and
    /// `most_bytes` at most.
    fn sized(slots: usize, most_pages: usize, most_bytes: u64) -> Option<Self> {
        if !(1..=MOST_NAMED).contains(&slots) {
            return fail(format!("a page of {slots} tiles; one holds 1 to {MOST_NAMED}"));
        }
        let pages = Vec::new();
        Some(Self { buffers: Vec::new(), pages, slots, most_pages, most_bytes, cels: 0 })
    }

    /// The pages, as a plan and the write path take them.
    pub(crate) fn pages(&self) -> &[wgpu::Buffer] {
        &self.buffers
    }

    /// The bytes of the pages made — a page counts whole, its free slots
    /// too, as it stays made, and a page given back its stand-in.
    pub(crate) fn bytes(&self) -> u64 {
        self.buffers.iter().map(wgpu::Buffer::size).sum()
    }

    /// Makes no page more past `most_bytes`: the pages made stay (its store
    /// gives back what nobody holds, [`Pool::give_back`]), and the next is
    /// made only within it — the budget its store gives, again when the
    /// allowance moves.
    pub(crate) fn set_most_bytes(&mut self, most_bytes: u64) {
        self.most_bytes = most_bytes;
    }

    /// Gives back the pages nobody's — every slot free —, the last first,
    /// till the pages hold `most_bytes` or none is nobody's: those past the
    /// last held cut off, one before it kept a tile's stand-in in its
    /// place, made again there when a cel next needs a page. No plan binds
    /// one: none of its slots is held, so no tile set names it.
    pub(crate) fn give_back(&mut self, engine: &Engine, most_bytes: u64) {
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
    #[cfg(test)]
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
    /// on the first page with one free, else on a new page, its.
    pub(crate) fn fresh(&mut self, engine: &Engine, cel: Cel) -> Result<TileAt, Full> {
        let own = |page: &Option<Page>| {
            page.as_ref().is_some_and(|page| page.cel == Some(cel) && !page.free.is_empty())
        };
        let page = match self.pages.iter().position(own) {
            Some(page) => page,
            None => self.claimed(engine, cel)?,
        };
        let book = self.pages[page].as_mut().expect("a page found or made is made");
        let slot = book.free.pop().expect("a page found or made has a slot free");
        book.holds[usize::from(slot)] = 1;
        Ok(TileAt { page: page as u16, slot })
    }

    /// `tiles` — straight RGBA8, a tile's bytes each — each in a fresh slot
    /// of `cel`, copied there by the write path in one submit: as many of
    /// them, the first, as the pool has room for. A tile is never written
    /// where one is stored ([`Write::put`] where it is told).
    pub(crate) fn store(&mut self, engine: &Engine, cel: Cel, tiles: &[&[u8]]) -> Option<Vec<TileAt>> {
        if let Some(tile) = tiles.iter().find(|tile| tile.len() as u64 != TILE_BYTES) {
            return fail(format!("a tile of {} bytes; one holds {TILE_BYTES}", tile.len()));
        }
        let mut places = Vec::with_capacity(tiles.len());
        while places.len() < tiles.len() {
            match self.fresh(engine, cel) {
                Ok(at) => places.push(at),
                Err(Full) => break,
            }
        }
        if places.is_empty() {
            return Some(places);
        }
        let staging = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("tiles stored"),
            size: places.len() as u64 * TILE_BYTES,
            usage: wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: true,
        });
        let copied = match staging.get_mapped_range_mut(..) {
            Ok(mut mapped) => {
                let bytes = TILE_BYTES as usize;
                for (at, tile) in tiles[..places.len()].iter().enumerate() {
                    mapped.slice(at * bytes..(at + 1) * bytes).copy_from_slice(tile);
                }
                Some(())
            }
            Err(error) => fail(format!("get_mapped_range_mut: {error}")),
        };
        staging.unmap();
        let writes: Vec<(usize, TileAt)> = places.iter().copied().enumerate().collect();
        // ⚠️No test reaches the release below: `put` refuses only what this
        // store never hands it (a tile past the staging, a place past the
        // pages — a mutant of it lived, 11-07). It stands so a refusal the
        // write path learns later holds no slot for a tile that never landed.
        if copied.and_then(|()| Write::put(engine, &self.buffers, &staging, &writes)).is_none() {
            for &at in &places {
                self.release(at);
            }
            return None;
        }
        Some(places)
    }

    /// One more hold of the tile at `at`. Nothing where none holds it: a
    /// free slot is handed out by [`Pool::fresh`], not held.
    // ⏳An undo record's or a stroke result's hold: the flip lane's
    // (connection-round-checklist B ⓓ) — while the CPU's tiles are the
    // canonical ones, the app's map holds each slot once.
    #[cfg_attr(not(test), allow(dead_code))]
    pub(crate) fn hold(&mut self, at: TileAt) -> Option<()> {
        let holds = &mut self.held(at)?.holds[usize::from(at.slot)];
        *holds += 1;
        Some(())
    }

    /// One hold fewer of the tile at `at`: its slot free once none holds
    /// it, and its page nobody's once every slot of it is. Nothing where
    /// none holds it.
    pub(crate) fn release(&mut self, at: TileAt) -> Option<()> {
        let book = self.held(at)?;
        let holds = &mut book.holds[usize::from(at.slot)];
        *holds -= 1;
        if *holds > 0 {
            return Some(());
        }
        book.free.push(at.slot);
        if book.free.len() == book.holds.len() {
            book.cel = None;
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
        for &at in places {
            self.holding(at)?;
        }
        // ⚠️No test tells this from a read of nothing mapped: DX12 maps a
        // buffer of no bytes as one of some (mutant R03 lived, 11-09). It
        // stands so a read of no tile waits for no GPU and asks no driver
        // for a buffer of no bytes.
        if places.is_empty() {
            return Some(());
        }
        let readback = engine.readback(bytes);
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        for (to, at) in (0..).step_by(TILE_BYTES as usize).zip(places) {
            let from = u64::from(at.slot) * TILE_BYTES;
            encoder.copy_buffer_to_buffer(&self.buffers[usize::from(at.page)], from, &readback, to, TILE_BYTES);
        }
        engine.queue.submit([encoder.finish()]);
        engine.mapped_into(&readback, into)
    }

    /// The page of the tile at `at`, held; nothing where the pool has no
    /// such slot or none holds it.
    fn held(&mut self, at: TileAt) -> Option<&mut Page> {
        self.holding(at)?;
        self.pages[usize::from(at.page)].as_mut()
    }

    /// Whether a tile is held at `at`; nothing where the pool has no such
    /// slot or none holds it.
    fn holding(&self, at: TileAt) -> Option<()> {
        let pages = self.pages.len();
        let book = match self.pages.get(usize::from(at.page)) {
            Some(Some(book)) => book,
            Some(None) => return fail(format!("{at:?} on a page given back")),
            None => return fail(format!("{at:?} of a pool of {pages} pages")),
        };
        match book.holds.get(usize::from(at.slot)).copied() {
            Some(0) => fail(format!("{at:?} is free")),
            Some(_) => Some(()),
            None => fail(format!("{at:?} past a page of {} tiles", book.holds.len())),
        }
    }

    /// A page for `cel`'s tiles where it has none with a slot free: one of
    /// nobody's, its then; one of another cel's with a slot free; or a new
    /// one, its — where one was given back, made again in its place.
    fn claimed(&mut self, engine: &Engine, cel: Cel) -> Result<usize, Full> {
        if let Some(page) = self.pages.iter().position(nobody_s) {
            self.pages[page].as_mut().expect("a page nobody's is made").cel = Some(cel);
            return Ok(page);
        }
        let with_room = |page: &Option<Page>| page.as_ref().is_some_and(|page| !page.free.is_empty());
        if let Some(page) = self.pages.iter().position(with_room) {
            return Ok(page);
        }
        let given_back = self.pages.iter().position(Option::is_none);
        // ⚠️No test lowers the budget the OS gives: `fits` is tried on the
        // numbers instead.
        let memory = platform::video_memory(&engine.adapter);
        let grows = self.page_bytes() - given_back.map_or(0, |page| self.buffers[page].size());
        if (given_back.is_none() && self.pages.len() >= self.most_pages) || !self.fits(memory, grows) {
            return Err(Full);
        }
        // The OS's budget is asked here, not set on the instance as wgpu's
        // `memory_budget_thresholds`: a threshold refuses whatever the
        // engine makes, its other makes have no error scope, and wgpu's
        // default for an error none catches panics
        // (wgpu-30.0.1/src/backend/wgpu_core.rs:692) — past the FFI, the
        // app aborts. A pool refusing at the budget lets a pass's own
        // buffers go over it a while instead. Nor `for_device_loss`: the
        // canonical tiles are on the device (브러시/렌더링 11-07, 관제
        // 09:04).
        let buffer = made(engine, "pool page", self.page_bytes()).ok_or(Full)?;
        // The first slot first: the one handed out last is first in line.
        let free = (0..self.slots).rev().map(|slot| slot as u16).collect();
        let book = Some(Page { holds: vec![0; self.slots], free, cel: Some(cel) });
        match given_back {
            Some(page) => {
                self.buffers[page] = buffer;
                self.pages[page] = book;
                Ok(page)
            }
            None => {
                self.buffers.push(buffer);
                self.pages.push(book);
                Ok(self.pages.len() - 1)
            }
        }
    }

    /// Whether the pool's bytes grown by `grows` keep within them and,
    /// where the OS says one, the budget it gives this process.
    fn fits(&self, memory: Option<VideoMemory>, grows: u64) -> bool {
        let within_os = |memory: VideoMemory| match memory.budget {
            Some(budget) => memory.used.checked_add(grows).is_some_and(|sum| sum <= budget),
            None => true,
        };
        self.bytes() + grows <= self.most_bytes && memory.is_none_or(within_os)
    }

    fn page_bytes(&self) -> u64 {
        self.slots as u64 * TILE_BYTES
    }
}

/// Whether `page` is made and nobody's: every slot of it free.
fn nobody_s(page: &Option<Page>) -> bool {
    matches!(page, Some(Page { cel: None, .. }))
}

/// A page's buffer of `size` bytes — a page or a page given back's stand-in
/// —, or none where the device refuses it for want of memory.
fn made(engine: &Engine, label: &str, size: u64) -> Option<wgpu::Buffer> {
    let made = engine.device.push_error_scope(wgpu::ErrorFilter::OutOfMemory);
    let buffer = engine.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size,
        // Bound by the passes, copied to by the write path and copied
        // from where its bytes are read back (connection-round-checklist
        // B: saving, cooling, an undo record parked).
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    });
    // ⚠️No test reaches a driver's refusal: a 0% threshold opens no
    // device, wgpu's own zero buffer refused first
    // (wgpu-core-30.0.1/src/device/resource.rs:464), and wgpu makes no
    // D3D12 buffer past 2 GiB (wgpu-hal-30.0.1/src/dx12/adapter.rs:916),
    // too few bytes for a driver to refuse.
    match pollster::block_on(made.pop()) {
        Some(_) => None,
        None => Some(buffer),
    }
}

/// A pool that makes no page past `most_bytes` (1a ③ — its store gives
/// the budget). Null on failure; see the last error.
///
/// # Safety
/// `engine` is live; the pool is freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_new(engine: *const Engine, most_bytes: u64) -> *mut Pool {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    Pool::new(engine, most_bytes).map_or(std::ptr::null_mut(), |pool| Box::into_raw(Box::new(pool)))
}

/// # Safety
/// `pool` came from `gpu_engine_pool_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_free(pool: *mut Pool) {
    if !pool.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(pool) });
    }
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
/// `pool` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_cel(pool: *mut Pool) -> u32 {
    // SAFETY: see the function's contract.
    let pool = unsafe { &mut *pool };
    pool.cel().0
}

/// Stores the `count` tiles at `tiles` — straight RGBA8, a tile's bytes at
/// each — in fresh slots of the cel `cel` ([`Pool::store`]), and writes
/// each one stored's place to `pages` and `slots`. Returns how many it
/// stored, the first of them: all, or fewer where the pool is full at the
/// next; -1 on failure, nothing stored — see the last error.
///
/// # Safety
/// `pool` and `engine` are live and the pool was made on `engine`; `tiles`
/// holds `count` pointers to a tile's bytes each, alive for the call; and
/// `pages` and `slots` hold `count` each.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_store(
    pool: *mut Pool,
    engine: *const Engine,
    cel: u32,
    tiles: *const *const u8,
    count: usize,
    pages: *mut u16,
    slots: *mut u16,
) -> isize {
    // SAFETY: see the function's contract.
    let (pool, engine) = unsafe { (&mut *pool, &*engine) };
    let tiles: Vec<&[u8]> = (0..count)
        // SAFETY: a tile's bytes at each pointer, alive for the call.
        .map(|at| unsafe { std::slice::from_raw_parts(*tiles.add(at), TILE_BYTES as usize) })
        .collect();
    let Some(places) = pool.store(engine, Cel(cel), &tiles) else {
        return -1;
    };
    for (at, place) in places.iter().enumerate() {
        // SAFETY: `pages` and `slots` hold `count` each, and no more are stored.
        unsafe {
            *pages.add(at) = place.page;
            *slots.add(at) = place.slot;
        }
    }
    places.len() as isize
}

/// Lets the slot at (`page`, `slot`) go — the store let its tile go. False
/// where none holds it; see the last error.
///
/// # Safety
/// `pool` is live.
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
/// `pool` and `engine` are live and the pool was made on `engine`; `tiles`
/// holds `count` words and `into` the bytes of `count` tiles.
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
    // SAFETY: `tiles` holds `count` words, `into` the bytes of `count` tiles.
    let (words, into) = unsafe {
        (
            std::slice::from_raw_parts(tiles, count),
            std::slice::from_raw_parts_mut(into, count * TILE_BYTES as usize),
        )
    };
    let Some(places) = words.iter().copied().map(TileAt::of_word).collect::<Option<Vec<_>>>() else {
        return fail::<()>("a tile to read named by no tile's word").is_some();
    };
    pool.read(engine, &places, into).is_some()
}

/// Makes no page more past `most_bytes` ([`Pool::set_most_bytes`]) — the
/// store's budget as the allowance moves, and past it for the tiles one of
/// its calls holds.
///
/// # Safety
/// `pool` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_most_bytes(pool: *mut Pool, most_bytes: u64) {
    // SAFETY: see the function's contract.
    let pool = unsafe { &mut *pool };
    pool.set_most_bytes(most_bytes);
}

/// Gives back the pages nobody holds till the pages hold `most_bytes`
/// ([`Pool::give_back`]).
///
/// # Safety
/// `pool` and `engine` are live and the pool was made on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_give_back(pool: *mut Pool, engine: *const Engine, most_bytes: u64) {
    // SAFETY: see the function's contract.
    let (pool, engine) = unsafe { (&mut *pool, &*engine) };
    pool.give_back(engine, most_bytes);
}

/// The bytes of the pages a pool has made ([`Pool::bytes`]).
///
/// # Safety
/// `pool` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pool_bytes(pool: *const Pool) -> u64 {
    // SAFETY: see the function's contract.
    let pool = unsafe { &*pool };
    pool.bytes()
}
