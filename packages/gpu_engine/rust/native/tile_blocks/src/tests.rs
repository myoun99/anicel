//! The tile blocks' lists, through their exports. ↩️Held from Dart while the
//! lists were the C's (test/services/qa_tile_allocator_test.dart, which
//! skipped wherever no C engine was built); here every host runs them.

use std::ffi::c_void;
use std::sync::{Mutex, MutexGuard};
use std::thread;

use super::{
    CAP_AT_START, LISTS, qa_tile_alloc, qa_tile_free, qa_tile_pool_cached_bytes,
    qa_tile_pool_set_byte_cap, qa_tile_pool_trim,
};

/// The lists are the process's one: a test holds this while it reads their
/// count, and starts from none parked under the cap a launch starts at.
static ONE_AT_A_TIME: Mutex<()> = Mutex::new(());

fn alone() -> MutexGuard<'static, ()> {
    let held = ONE_AT_A_TIME
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    qa_tile_pool_set_byte_cap(CAP_AT_START);
    qa_tile_pool_trim();
    held
}

fn free(block: *mut c_void) {
    // SAFETY: every block these tests free is one they were answered.
    unsafe { qa_tile_free(block) };
}

#[test]
fn a_freed_block_parks_and_the_next_ask_of_its_size_takes_it() {
    let _alone = alone();
    const SIZE: i64 = 77_776;

    let first = qa_tile_alloc(SIZE);
    assert!(!first.is_null());
    assert_eq!(first as usize % 16, 0, "aligned for any read of a pixel");
    // SAFETY: SIZE bytes were asked for.
    unsafe {
        let bytes = first.cast::<u8>();
        bytes.write(0xAB);
        bytes.add(SIZE as usize - 1).write(0xCD);
        assert_eq!(bytes.read(), 0xAB);
        assert_eq!(bytes.add(SIZE as usize - 1).read(), 0xCD);
    }

    free(first);
    assert_eq!(qa_tile_pool_cached_bytes(), SIZE, "parked, not freed");

    let second = qa_tile_alloc(SIZE);
    assert_eq!(second, first, "the parked block, handed back");
    assert_eq!(qa_tile_pool_cached_bytes(), 0);
    free(second);
}

#[test]
fn each_size_parks_on_a_list_of_its_own() {
    let _alone = alone();
    const A: i64 = 55_552;
    const B: i64 = 66_664;
    let a = qa_tile_alloc(A);
    let b = qa_tile_alloc(B);
    free(a);
    free(b);

    // By size, not by the order they were freed in.
    let b_again = qa_tile_alloc(B);
    let a_again = qa_tile_alloc(A);
    assert_eq!(b_again, b);
    assert_eq!(a_again, a);
    free(a_again);
    free(b_again);
}

#[test]
fn a_trim_frees_every_parked_block() {
    let _alone = alone();
    const SIZE: i64 = 77_780;
    free(qa_tile_alloc(SIZE));
    assert_eq!(qa_tile_pool_cached_bytes(), SIZE, "the premise: one parked");

    qa_tile_pool_trim();

    assert_eq!(qa_tile_pool_cached_bytes(), 0);
}

// 유저 2026-09-16 (memory-allowance-Q2): the pool was a compile-time 512 MB,
// the one line of the allowance the engine held outside it.
#[test]
fn a_lowered_cap_frees_what_is_parked_above_it_and_nothing_parks_past_it() {
    let _alone = alone();
    const SIZE: i64 = 88_880;
    // Two held, then both parked: a block freed and asked for again would
    // be the one block twice.
    let first = qa_tile_alloc(SIZE);
    let second = qa_tile_alloc(SIZE);
    free(first);
    free(second);
    assert_eq!(qa_tile_pool_cached_bytes(), 2 * SIZE);

    qa_tile_pool_set_byte_cap(SIZE);
    assert_eq!(qa_tile_pool_cached_bytes(), SIZE, "the excess, freed now");

    free(qa_tile_alloc(SIZE + 16));
    assert_eq!(
        qa_tile_pool_cached_bytes(),
        SIZE,
        "a free that would cross the cap does not park",
    );
}

#[test]
fn a_size_past_the_lists_is_freed_and_an_emptied_list_takes_another() {
    let _alone = alone();
    let size = |list: usize| 4_096 + 16 * list as i64;
    for list in 0..LISTS {
        free(qa_tile_alloc(size(list)));
    }
    let parked = qa_tile_pool_cached_bytes();
    assert_eq!(parked, (0..LISTS).map(size).sum::<i64>());

    free(qa_tile_alloc(size(LISTS)));
    assert_eq!(qa_tile_pool_cached_bytes(), parked, "no list for a ninth");

    // The first list's one block leaves, and the ninth size parks there.
    let taken = qa_tile_alloc(size(0));
    free(qa_tile_alloc(size(LISTS)));
    assert_eq!(qa_tile_pool_cached_bytes(), parked - size(0) + size(LISTS));
    qa_tile_pool_set_byte_cap(0);
    free(taken);
    assert_eq!(qa_tile_pool_cached_bytes(), 0);
}

#[test]
fn no_size_is_no_block() {
    let _alone = alone();
    assert!(qa_tile_alloc(0).is_null());
    assert!(qa_tile_alloc(-1).is_null());
    free(std::ptr::null_mut());
    assert_eq!(qa_tile_pool_cached_bytes(), 0);
}

// A tile's finalizer frees on the collector's thread while the app's own
// asks and frees: the count is the lists' whoever calls.
#[test]
fn threads_asking_and_freeing_at_once_leave_the_count_whole() {
    let _alone = alone();
    const SIZE: i64 = 65_536;
    const THREADS: usize = 8;
    const HELD: usize = 16;
    thread::scope(|scope| {
        for thread in 0..THREADS {
            scope.spawn(move || {
                for round in 0..200 {
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
    let parked = qa_tile_pool_cached_bytes();
    assert_eq!(parked % SIZE, 0);
    assert!(parked > 0 && parked <= (THREADS * HELD) as i64 * SIZE);
    qa_tile_pool_trim();
    assert_eq!(qa_tile_pool_cached_bytes(), 0);
}
