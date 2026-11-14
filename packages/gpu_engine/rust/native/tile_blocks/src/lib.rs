//! A tile's block of pixels, and where a freed one waits (connection round;
//! the C was qa_engine.c's tile allocator, R20-E1).
//!
//! A tile's pixels live in native memory (`BitmapTile`), one block a tile,
//! and tiles churn hard: a cel thawed from its file, the engine's tiles read
//! back, an undo's tiles let go. A freed block parks here on the list of its
//! exact size and is handed straight back to the next ask of that size.
//!
//! 🔬MEASURED 2026-11-12 (65,536-byte blocks, each written whole, MSVC, the
//! C's lists): 1024 laid and then freed, over and over — 9 µs a block from
//! the lists, 43 µs from malloc; one laid and freed at a time the two are
//! the same (1.2 µs). These lists the same day, the machine busy with a
//! landing: 11–18 µs against 45–51, and the same one at a time (1.4–2.2).
//! ↩️The C's first reason was the C brush's: every commit adopted its
//! scratch buffers as finished tiles (R19-Z), so a full-canvas 8K fill
//! paid ~1024 fresh mallocs. That commit went with the brush (C ABI 80);
//! the measure is what the lists buy without it.
//!
//! `qa_tile_free` is also the Dart `NativeFinalizer`'s callback, which runs
//! on the collector's threads: everything here is behind one lock.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

use std::alloc::{Layout, alloc, dealloc};
use std::ffi::c_void;
use std::ptr::null_mut;
use std::sync::{Mutex, MutexGuard};

#[cfg(test)]
mod tests;

/// What stands before a block's bytes: its link while it is parked, and the
/// byte length it was asked at. Sixteen bytes at sixteen, so the bytes after
/// it are aligned for any read of a pixel.
#[repr(C, align(16))]
struct Head {
    next: *mut Head,
    size: i64,
}

/// How many sizes park at once: a block of a ninth is freed, not parked.
const LISTS: usize = 8;

/// What may park before the app says otherwise
/// ([`qa_tile_pool_set_byte_cap`]): one full 8K frame of tiles (256 MB) and
/// room for the frame before it, still draining.
const CAP_AT_START: i64 = 512 * 1024 * 1024;

struct Parked {
    /// The size each list parks. An emptied list keeps the size it held
    /// till a block of another takes it ([`Parked::park`]).
    sizes: [i64; LISTS],
    heads: [*mut Head; LISTS],
    bytes: i64,
    cap: i64,
}

// SAFETY: a parked block is the lists' alone — whoever freed it holds it no
// longer — so the heads go wherever the lock goes.
unsafe impl Send for Parked {}

static PARKED: Mutex<Parked> = Mutex::new(Parked {
    sizes: [0; LISTS],
    heads: [null_mut(); LISTS],
    bytes: 0,
    cap: CAP_AT_START,
});

/// The lists, locked. No step under the lock can unwind — none allocates
/// through a fallible door or calls out — so a poisoned lock holds lists as
/// whole as any.
fn parked() -> MutexGuard<'static, Parked> {
    PARKED.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// A block of `size` bytes behind its head, as the allocator is asked for
/// it — None for a size no block has.
fn layout_of(size: i64) -> Option<Layout> {
    let bytes = usize::try_from(size).ok()?.checked_add(size_of::<Head>())?;
    Layout::from_size_align(bytes, align_of::<Head>()).ok()
}

/// Gives `head`'s block back to the allocator.
///
/// # Safety
/// `head` is a block [`qa_tile_alloc`] made that nothing holds, on no list.
unsafe fn release(head: *mut Head) {
    // SAFETY: the head was written when the block was made, at this layout.
    unsafe {
        let layout = layout_of((*head).size).expect("the layout it was made at");
        dealloc(head.cast(), layout);
    }
}

impl Parked {
    /// A parked block of exactly `size`, off its list.
    fn take(&mut self, size: i64) -> Option<*mut Head> {
        let list =
            (0..LISTS).find(|&at| self.sizes[at] == size && !self.heads[at].is_null())?;
        let head = self.heads[list];
        // SAFETY: a parked block is whole, and the lists' alone.
        self.heads[list] = unsafe { (*head).next };
        self.bytes -= size;
        Some(head)
    }

    /// Parks `head` — false where it would cross the cap, or every list
    /// holds blocks of another size.
    fn park(&mut self, head: *mut Head) -> bool {
        // SAFETY: the caller's block, whole.
        let size = unsafe { (*head).size };
        if self.bytes + size > self.cap {
            return false;
        }
        let Some(list) = (0..LISTS)
            .find(|&at| self.sizes[at] == size)
            // An empty list takes another size.
            .or_else(|| (0..LISTS).find(|&at| self.heads[at].is_null()))
        else {
            return false;
        };
        self.sizes[list] = size;
        // SAFETY: as above.
        unsafe { (*head).next = self.heads[list] };
        self.heads[list] = head;
        self.bytes += size;
        true
    }

    /// Frees parked blocks till `most` bytes are parked at the most.
    fn shed_to(&mut self, most: i64) {
        for list in 0..LISTS {
            while !self.heads[list].is_null() && self.bytes > most {
                let head = self.heads[list];
                // SAFETY: a parked block, taken off its list here.
                unsafe {
                    self.heads[list] = (*head).next;
                    self.bytes -= (*head).size;
                    release(head);
                }
            }
        }
    }
}

/// A block of `size` bytes: one parked at that size, or a fresh one — null
/// where `size` is none, or the allocator has no more. ⚠️Its bytes are
/// whatever its last holder left: whoever asks writes every one.
#[unsafe(no_mangle)]
pub extern "C" fn qa_tile_alloc(size: i64) -> *mut c_void {
    if size <= 0 {
        return null_mut();
    }
    let taken = parked().take(size);
    let head = match taken {
        Some(head) => head,
        None => {
            let Some(layout) = layout_of(size) else {
                return null_mut();
            };
            // SAFETY: the layout holds a head at the least, so it is not
            // zero-sized.
            let head = unsafe { alloc(layout) }.cast::<Head>();
            if head.is_null() {
                return null_mut();
            }
            // SAFETY: fresh, and big enough for a head.
            unsafe { head.write(Head { next: null_mut(), size }) };
            head
        }
    };
    // SAFETY: the block's bytes start where its head ends.
    unsafe { head.add(1).cast() }
}

/// Parks `pixels` for the next ask of its size, or frees it past the cap.
/// The signature is Dart's `NativeFinalizerFunction`: a tile's finalizer
/// calls this, on the collector's thread.
///
/// # Safety
/// `pixels` is null, or what [`qa_tile_alloc`] answered and nothing holds.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_tile_free(pixels: *mut c_void) {
    if pixels.is_null() {
        return;
    }
    // SAFETY: its head stands before it (the caller's promise).
    let head = unsafe { pixels.cast::<Head>().sub(1) };
    let kept = parked().park(head);
    if !kept {
        // SAFETY: on no list, and the caller's no longer.
        unsafe { release(head) };
    }
}

/// The bytes of the blocks parked now — resident, and nobody's picture. The
/// app's memory census reads it.
#[unsafe(no_mangle)]
pub extern "C" fn qa_tile_pool_cached_bytes() -> i64 {
    parked().bytes
}

/// Frees every parked block: the OS says memory is tight.
#[unsafe(no_mangle)]
pub extern "C" fn qa_tile_pool_trim() {
    parked().shed_to(0);
}

/// Sets what may park, and frees what is parked above it now — a lowered
/// cap does not wait for the next free. The app's memory allowance sets it.
#[unsafe(no_mangle)]
pub extern "C" fn qa_tile_pool_set_byte_cap(bytes: i64) {
    let mut parked = parked();
    parked.cap = bytes.max(0);
    let cap = parked.cap;
    parked.shed_to(cap);
}
