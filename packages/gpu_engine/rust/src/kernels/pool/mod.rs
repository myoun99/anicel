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

// ⏳Nothing outside the tests stores in it until the connection round
// (connection-round-checklist B).
#![cfg_attr(not(test), allow(dead_code))]

#[cfg(test)]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{TILE_BYTES, TileAt};
use crate::kernels::shared::room;
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
    pub(crate) fn pages(&self) -> &[wgpu::Buffer] {
        &self.buffers
    }

    /// The tiles a page holds.
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

    /// One more hold of the tile at `at`. Nothing where none holds it: a
    /// free slot is handed out by [`Pool::fresh`], not held.
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
