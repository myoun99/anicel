//! The tile blocks, through their exports. ↩️Held from Dart while they
//! were the C's (test/services/qa_tile_allocator_test.dart, which skipped
//! wherever no C engine was built); here every host runs them.
//!
//! Each test asks at a size of its own: the books are the process's one,
//! and by size.

use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;
use std::ffi::c_void;
use std::thread;

use super::{Head, qa_tile_alloc, qa_tile_blocks_held, qa_tile_blocks_laid, qa_tile_free};

/// This test binary's allocator: the system's, counting the bytes each
/// thread holds of it at a block's alignment — what the blocks' doors ask
/// of the allocator and give back to it, read where no list can be.
struct Counting;

thread_local! {
    /// Bytes this thread asked for at a head's alignment and has not given
    /// back. Const-made and of no destructor: the allocator reads it.
    static HELD_HERE: Cell<i64> = const { Cell::new(0) };
}

fn counted(layout: Layout, by: i64) {
    if layout.align() == align_of::<Head>() {
        // A thread being torn down counts nothing: no test reads it then.
        let _ = HELD_HERE.try_with(|held| held.set(held.get() + by * layout.size() as i64));
    }
}

// SAFETY: the system's allocator, asked as it was asked.
unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        counted(layout, 1);
        // SAFETY: the caller's layout.
        unsafe { System.alloc(layout) }
    }

    unsafe fn dealloc(&self, block: *mut u8, layout: Layout) {
        counted(layout, -1);
        // SAFETY: the caller's block, at the layout it was made at.
        unsafe { System.dealloc(block, layout) }
    }
}

#[global_allocator]
static ALLOCATOR: Counting = Counting;

fn held_here() -> i64 {
    HELD_HERE.with(Cell::get)
}

fn free(block: *mut c_void) {
    // SAFETY: every block these tests free is one they were answered.
    unsafe { qa_tile_free(block) };
}

fn books_of(size: i64) -> (i64, i64) {
    (qa_tile_blocks_laid(size), qa_tile_blocks_held(size))
}

#[test]
fn a_block_is_its_holder_s_to_write_and_aligned_for_a_pixel() {
    const SIZE: i64 = 77_776;

    let block = qa_tile_alloc(SIZE);

    assert!(!block.is_null());
    assert_eq!(block as usize % 16, 0, "aligned for any read of a pixel");
    // SAFETY: SIZE bytes were asked for.
    unsafe {
        let bytes = block.cast::<u8>();
        bytes.write(0xAB);
        bytes.add(SIZE as usize - 1).write(0xCD);
        assert_eq!(bytes.read(), 0xAB);
        assert_eq!(bytes.add(SIZE as usize - 1).read(), 0xCD);
    }
    free(block);
}

// 유저 2026-11-21 (cel-originals Q7): 「타일풀은 아예 없애는걸로 가자」.
#[test]
fn a_freed_block_goes_back_to_the_allocator_and_waits_for_no_ask() {
    const SIZE: i64 = 77_780;
    let of_a_block = SIZE + size_of::<Head>() as i64;
    let before = held_here();

    let first = qa_tile_alloc(SIZE);
    let second = qa_tile_alloc(SIZE);
    assert_eq!(held_here() - before, 2 * of_a_block, "the premise: two laid");

    free(first);
    assert_eq!(held_here() - before, of_a_block, "given back as it is freed");
    free(second);
    assert_eq!(held_here(), before, "nothing of them is kept");

    // An ask after them is the allocator's to answer anew.
    let third = qa_tile_alloc(SIZE);
    assert_eq!(held_here() - before, of_a_block);
    free(third);
    assert_eq!(held_here(), before);
}

#[test]
fn the_books_count_each_size_s_blocks_laid_and_held() {
    const A: i64 = 55_552;
    const B: i64 = 66_664;
    assert_eq!((books_of(A), books_of(B)), ((0, 0), (0, 0)), "none laid yet");

    let a = qa_tile_alloc(A);
    let b = qa_tile_alloc(B);
    let b_too = qa_tile_alloc(B);
    assert_eq!((books_of(A), books_of(B)), ((1, 1), (2, 2)));

    free(b);
    assert_eq!((books_of(A), books_of(B)), ((1, 1), (2, 1)));
    free(a);
    free(b_too);
    assert_eq!((books_of(A), books_of(B)), ((1, 0), (2, 0)));

    // Laid is ever: a block asked for again is one more.
    free(qa_tile_alloc(A));
    assert_eq!(books_of(A), (2, 0));
}

#[test]
fn no_size_is_no_block() {
    let before = held_here();

    assert!(qa_tile_alloc(0).is_null());
    assert!(qa_tile_alloc(-1).is_null());
    free(std::ptr::null_mut());

    assert_eq!(held_here(), before);
    assert_eq!((books_of(0), books_of(-1)), ((0, 0), (0, 0)));
}

// A tile's finalizer frees on the collector's thread while the app's own
// asks and frees: the books are the process's whoever calls.
#[test]
fn threads_asking_and_freeing_at_once_leave_the_books_whole() {
    const SIZE: i64 = 65_536;
    const THREADS: usize = 8;
    const HELD: usize = 16;
    const ROUNDS: usize = 200;
    thread::scope(|scope| {
        for thread in 0..THREADS {
            scope.spawn(move || {
                for round in 0..ROUNDS {
                    let held: Vec<usize> = (0..HELD)
                        .map(|_| {
                            let block = qa_tile_alloc(SIZE);
                            assert!(!block.is_null());
                            // SAFETY: SIZE bytes were asked for.
                            unsafe {
                                block.cast::<u8>().write_bytes(thread as u8, SIZE as usize)
                            };
                            block as usize
                        })
                        .collect();
                    for block in held {
                        // SAFETY: as above — nobody else was answered it.
                        let seen = unsafe { (block as *const u8).add(round).read() };
                        assert_eq!(seen, thread as u8, "a block is one holder's");
                        free(block as *mut c_void);
                    }
                }
            });
        }
    });

    assert_eq!(books_of(SIZE), ((THREADS * HELD * ROUNDS) as i64, 0));
}
