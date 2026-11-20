//! A tile's block of pixels (connection round; the C was qa_engine.c's tile
//! allocator, R20-E1).
//!
//! A tile's pixels live in native memory (`BitmapTile`), one block a tile:
//! asked of the allocator, and given back to it as its tile lets go. A
//! freed block waits NOWHERE.
//!
//! 🗣️유저 2026-11-21 05:02 (card cel-originals-are-held-twice-in-ram-and-
//! on-the-gpu, Q7 「none 풀을 아예 안 둔다」, 관제 채팅): 「타일풀은 아예
//! 없애는걸로 가자」 — and before it 「근본적으로 타일풀을 없애는건? …
//! 펜에만 안버벅이면 전혀 문제없지않나싶은데」.
//! ↩️Till then a freed block parked here on a list of its exact size, up
//! to a cap the app's memory allowance set, and was handed straight back
//! to the next ask of that size: the lists held 2,159.8 MB of nobody's
//! picture on the user's PC (the memory tab, 03:22 that day).
//!
//! 🔬WHAT THE LISTS BOUGHT, which is what an ask pays now (65,536-byte
//! blocks, each written whole). 2026-11-12, MSVC: 1024 laid and then
//! freed, over and over — 9 µs a block from the lists, 43 µs from malloc;
//! one laid and freed at a time the two were the same (1.2 µs).
//! 2026-11-21, the app's own blocks on the main PC, the machine busy:
//! laid right after the lists were emptied +3 µs a block (112: +0.3 ms ·
//! 2,240: +6 ms); after 0.7 s of rest 112: +0.6 ms · 290: +0.4 ms · 2,240
//! at once on one thread +48 ms; a parked cel thawed (152 blocks) 28.7 ms
//! with the lists full, 26.6 ms emptied — nothing to tell apart.
//! A pen's stroke asks for none: it is drawn on the engine's tiles.
//! ⚠️NOT MEASURED: whether the pages of a freed block go back to the OS
//! on Android and iOS as they do on Windows (기기 대기 — the card).
//! ↩️The C's first reason was the C brush's: every commit adopted its
//! scratch buffers as finished tiles (R19-Z), so a full-canvas 8K fill
//! paid ~1024 fresh mallocs. That commit went with the brush (C ABI 80).
//!
//! `qa_tile_free` is also the Dart `NativeFinalizer`'s callback, which runs
//! on the collector's threads: the allocator is asked from any thread, and
//! the books are behind one lock.

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

/// What stands before a block's bytes: the byte length it was asked at,
/// which the allocator is told again as the block goes back. Sixteen bytes
/// at sixteen, so the bytes after it are aligned for any read of a pixel.
#[repr(C, align(16))]
struct Head {
    size: i64,
}

/// What the books say of the blocks of one size.
struct Book {
    size: i64,
    /// How many were ever laid.
    laid: i64,
    /// How many of them are held now.
    held: i64,
}

/// THE BOOKS — each size's blocks laid and held, the process's one count
/// whichever thread asks. They are a test's eyes
/// ([`qa_tile_blocks_laid`], [`qa_tile_blocks_held`]): no list is left to
/// find a freed block on, and the allocator answers nobody what it holds.
/// By size, so that a test asks at a size no tile of its process wears and
/// reads its own blocks alone — a tile collected meanwhile frees at
/// another.
static BOOKS: Mutex<Vec<Book>> = Mutex::new(Vec::new());

/// The books, locked. No step under the lock can unwind — a book that
/// cannot be added aborts — so a poisoned lock holds books as whole as
/// any.
fn books() -> MutexGuard<'static, Vec<Book>> {
    BOOKS.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// The book of `size`, opened where no block of it was laid yet.
fn book_of(books: &mut Vec<Book>, size: i64) -> &mut Book {
    let at = match books.iter().position(|book| book.size == size) {
        Some(at) => at,
        None => {
            books.push(Book { size, laid: 0, held: 0 });
            books.len() - 1
        }
    };
    &mut books[at]
}

/// What the book of `size` says by `read` — nothing where none was laid.
fn read_of(size: i64, read: impl Fn(&Book) -> i64) -> i64 {
    books().iter().find(|book| book.size == size).map_or(0, read)
}

/// A block of `size` bytes behind its head, as the allocator is asked for
/// it — None for a size no block has.
fn layout_of(size: i64) -> Option<Layout> {
    let bytes = usize::try_from(size).ok()?.checked_add(size_of::<Head>())?;
    Layout::from_size_align(bytes, align_of::<Head>()).ok()
}

/// A block of `size` bytes, fresh from the allocator — null where `size`
/// is none, or the allocator has no more. ⚠️Its bytes are whatever the
/// allocator left there: whoever asks writes every one.
#[unsafe(no_mangle)]
pub extern "C" fn qa_tile_alloc(size: i64) -> *mut c_void {
    if size <= 0 {
        return null_mut();
    }
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
    unsafe { head.write(Head { size }) };
    {
        let mut books = books();
        let book = book_of(&mut books, size);
        book.laid += 1;
        book.held += 1;
    }
    // SAFETY: the block's bytes start where its head ends.
    unsafe { head.add(1).cast() }
}

/// Gives `pixels` back to the allocator. The signature is Dart's
/// `NativeFinalizerFunction`: a tile's finalizer calls this, on the
/// collector's thread.
///
/// # Safety
/// `pixels` is null, or what [`qa_tile_alloc`] answered and nothing holds.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_tile_free(pixels: *mut c_void) {
    if pixels.is_null() {
        return;
    }
    // SAFETY: its head stands before it (the caller's promise), written
    // when the block was made.
    let (head, size) = unsafe {
        let head = pixels.cast::<Head>().sub(1);
        (head, (*head).size)
    };
    book_of(&mut books(), size).held -= 1;
    let layout = layout_of(size).expect("the layout it was made at");
    // SAFETY: made at this layout, and the caller's no longer.
    unsafe { dealloc(head.cast(), layout) };
}

/// How many blocks of exactly `size` bytes this process ever laid.
#[unsafe(no_mangle)]
pub extern "C" fn qa_tile_blocks_laid(size: i64) -> i64 {
    read_of(size, |book| book.laid)
}

/// How many blocks of exactly `size` bytes are held now: laid, and not
/// given back.
#[unsafe(no_mangle)]
pub extern "C" fn qa_tile_blocks_held(size: i64) -> i64 {
    read_of(size, |book| book.held)
}
