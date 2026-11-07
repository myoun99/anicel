//! The tile pool — where a cel's tiles are stored on the engine
//! (gpu-canonical-store 1a ①, 브러시/렌더링 11-05 11:45; ④ 13:19): pages of
//! straight RGBA8 128² tiles, a tile a slot, named (page, slot) by a
//! [`TileAt`] — the pages every pass binds and the write path copies to. A
//! page holds what one binding does, 128 MiB at most (2048 tiles at
//! WebGPU's least binding), and a cel's tiles lie on pages of its own, so a
//! pass over a cel binds its page or few: on a device that binds few pages
//! a pass, the passes a composite takes.
//!
//! A held tile is never written over: a write takes a fresh slot (the write
//! path's `put` copies where it is told — no caller writes in place,
//! 캔버스 베이스 11-07 08:3x), and the slot it replaces is released. Holds
//! are counted here — a cel's map, an undo record, a stroke's result each
//! hold the slots they name — and a slot held by none is free. The slot
//! released last on a page is the next one it hands out, so a cel that
//! keeps replacing its tiles keeps to its pages. A page with every slot
//! free is the next one a cel needs; pages are not given back.
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
//! tiles not shown go, as the app's tile pictures were.

#[cfg(test)]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{TILE_BYTES, TileAt};
use crate::kernels::shared::room;
use crate::kernels::write::Write;
use crate::platform::{self, VideoMemory};

/// The most a page holds where a binding holds more (1a ④).
const MOST_PAGE_BYTES: u64 = 128 << 20;
/// The slots a page may have and the pages a pool may: a `TileAt` names
/// each by a u16.
const MOST_NAMED: usize = u16::MAX as usize + 1;

/// A cel the pool stores tiles for — what keeps its tiles to pages of its
/// own.
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
    /// The cel whose tiles it stores; none while every slot is free.
    cel: Option<Cel>,
}

pub(crate) struct Pool {
    buffers: Vec<wgpu::Buffer>,
    pages: Vec<Page>,
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
    // ⏳The executor's C ABI takes them (screen-on-the-engine, the next
    // commit).
    #[cfg_attr(not(test), allow(dead_code))]
    pub(crate) fn pages(&self) -> &[wgpu::Buffer] {
        &self.buffers
    }

    /// The tiles a page holds.
    #[cfg(test)]
    pub(crate) fn slots(&self) -> usize {
        self.slots
    }

    /// A cel of its own.
    pub(crate) fn cel(&mut self) -> Cel {
        self.cels += 1;
        Cel(self.cels)
    }

    /// A free slot for a tile of `cel`, held once: on the first of its
    /// pages with one free, else on a page of nobody's, else on a new page.
    pub(crate) fn fresh(&mut self, engine: &Engine, cel: Cel) -> Result<TileAt, Full> {
        let own = |page: &Page| page.cel == Some(cel) && !page.free.is_empty();
        let page = match self.pages.iter().position(own) {
            Some(page) => page,
            None => self.claimed(engine, cel)?,
        };
        let book = &mut self.pages[page];
        let slot = book.free.pop().expect("a cel's page or a fresh one has a slot free");
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
        let holds = self.holds(at)?;
        if *holds == 0 {
            return fail(format!("{at:?} is free"));
        }
        *holds += 1;
        Some(())
    }

    /// One hold fewer of the tile at `at`: its slot free once none holds
    /// it, and its page nobody's once every slot of it is. Nothing where
    /// none holds it.
    pub(crate) fn release(&mut self, at: TileAt) -> Option<()> {
        let holds = self.holds(at)?;
        if *holds == 0 {
            return fail(format!("{at:?} is free"));
        }
        *holds -= 1;
        if *holds > 0 {
            return Some(());
        }
        let book = &mut self.pages[usize::from(at.page)];
        book.free.push(at.slot);
        if book.free.len() == book.holds.len() {
            book.cel = None;
        }
        Some(())
    }

    /// The holds of the tile at `at`; nothing where the pool has no such
    /// slot.
    fn holds(&mut self, at: TileAt) -> Option<&mut u32> {
        let pages = self.pages.len();
        let Some(book) = self.pages.get_mut(usize::from(at.page)) else {
            return fail(format!("{at:?} of a pool of {pages} pages"));
        };
        let slots = book.holds.len();
        match book.holds.get_mut(usize::from(at.slot)) {
            Some(holds) => Some(holds),
            None => fail(format!("{at:?} past a page of {slots} tiles")),
        }
    }

    /// A page for `cel`'s tiles: one of nobody's, or a new one.
    fn claimed(&mut self, engine: &Engine, cel: Cel) -> Result<usize, Full> {
        if let Some(page) = self.pages.iter().position(|page| page.cel.is_none()) {
            self.pages[page].cel = Some(cel);
            return Ok(page);
        }
        // ⚠️No test lowers the budget the OS gives: `fits` is tried on the
        // numbers instead.
        let memory = platform::video_memory(&engine.adapter);
        if self.pages.len() >= self.most_pages || !self.fits(memory) {
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
        let made = engine.device.push_error_scope(wgpu::ErrorFilter::OutOfMemory);
        let buffer = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("pool page"),
            size: self.page_bytes(),
            // Bound by the passes, copied to by the write path and copied
            // from where its bytes are read back (connection-round-checklist
            // B: saving, cooling, an undo record parked).
            usage: wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_DST
                | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        // ⚠️No test reaches a driver's refusal: a 0% threshold opens no
        // device, wgpu's own zero buffer refused first
        // (wgpu-core-30.0.1/src/device/resource.rs:464), and wgpu makes no
        // D3D12 buffer past 2 GiB (wgpu-hal-30.0.1/src/dx12/adapter.rs:916),
        // too few bytes for a driver to refuse.
        if pollster::block_on(made.pop()).is_some() {
            return Err(Full);
        }
        self.buffers.push(buffer);
        // The first slot first: the one handed out last is first in line.
        let free = (0..self.slots).rev().map(|slot| slot as u16).collect();
        self.pages.push(Page { holds: vec![0; self.slots], free, cel: Some(cel) });
        Ok(self.pages.len() - 1)
    }

    /// Whether a page more keeps within the pool's bytes and, where the OS
    /// says one, the budget it gives this process.
    fn fits(&self, memory: Option<VideoMemory>) -> bool {
        let page = self.page_bytes();
        let made = self.pages.len() as u64 * page;
        let within_os = |memory: VideoMemory| match memory.budget {
            Some(budget) => memory.used.checked_add(page).is_some_and(|sum| sum <= budget),
            None => true,
        };
        made + page <= self.most_bytes && memory.is_none_or(within_os)
    }

    fn page_bytes(&self) -> u64 {
        self.slots as u64 * TILE_BYTES
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
