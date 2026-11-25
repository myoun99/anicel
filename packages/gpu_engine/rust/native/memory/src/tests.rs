//! The memory questions, through their exports, held to what each answer
//! must be on the platforms this runs on. ↩️Until the connection round
//! deleted the C (connection-round-checklist H, 2026-11-08), each was held
//! to the C's answer around it as well (native/oracle); what this process
//! holds is pinned against the bytes it touches by the app's own test of
//! the same export (test/native/the_process_number_is_the_one_the_os_shows_test.dart).

use std::time::{Duration, Instant};

use super::{
    fill, mappings, mappings_line, qa_app_memory_limit_bytes, qa_available_memory_bytes,
    qa_physical_memory_bytes, qa_process_footprint_bytes, said,
};

#[test]
fn the_ram_holds_still() {
    let ram = qa_physical_memory_bytes();
    assert!(ram > 0, "every platform here says how much RAM it has");
    assert_eq!(qa_physical_memory_bytes(), ram);
}

#[test]
fn what_this_process_holds_is_some_of_the_ram() {
    let held = qa_process_footprint_bytes();
    assert!(held > 0, "every platform here says what a process holds");
    assert!(held < qa_physical_memory_bytes());
}

#[test]
fn what_more_it_may_take_is_some_of_the_ram() {
    let free = qa_available_memory_bytes();
    if cfg!(target_os = "macos") {
        assert_eq!(free, 0, "a Mac gives a process no such number");
    } else {
        assert!(free > 0 && free < qa_physical_memory_bytes());
    }
}

#[test]
fn a_desktop_holds_an_app_to_no_limit_of_its_own() {
    if cfg!(any(windows, target_os = "macos", target_os = "linux")) {
        assert_eq!(qa_app_memory_limit_bytes(), 0);
    }
}

// The Linux kernel keeps an account of each mapping, and its line comes
// from a thread of its own; no other platform here keeps one.
#[test]
fn the_mappings_that_hold_the_most_are_said_where_the_kernel_keeps_them() {
    let until = Instant::now() + Duration::from_secs(5);
    let mut line = mappings();
    while line.is_none() && Instant::now() < until {
        std::thread::sleep(Duration::from_millis(20));
        line = mappings();
    }
    if cfg!(any(windows, target_vendor = "apple")) {
        assert_eq!(line, None);
    } else {
        let line = line.expect("Linux says its mappings");
        assert!(line.ends_with(" ms"), "{line}");
    }
}

#[test]
fn a_mappings_line_names_the_most_first_and_the_read_s_time() {
    let held = [
        ("kgsl-3d0".to_owned(), 256 << 20),
        ("[anon:scudo:primary]".to_owned(), 3 << 19),
        ("libc.so".to_owned(), 1 << 20),
        ("[anon]".to_owned(), 1 << 19),
        ("libflutter.so".to_owned(), 1 << 18),
    ];
    assert_eq!(
        mappings_line(&held, Duration::from_micros(23_900)),
        "kgsl-3d0 256.0  [anon:scudo:primary] 1.5  libc.so 1.0  [anon] 0.5  read 23 ms",
    );
}

#[test]
fn a_line_too_long_for_its_room_is_cut_at_a_character_s_end() {
    let mut out = [0u8; 6];
    assert_eq!(fill("ab", &mut out), 2);
    assert_eq!(&out[..2], b"ab");
    // 'é' is two bytes: the room's sixth byte would split it.
    assert_eq!(fill("abcdeé", &mut out), 5);
    assert_eq!(&out[..5], b"abcde");
    assert_eq!(fill("abcdefgh", &mut out), 6);
}

#[test]
fn an_answer_not_said_is_zero_and_one_too_large_is_the_most_there_is() {
    assert_eq!(said(None), 0);
    assert_eq!(said(Some(7)), 7);
    assert_eq!(said(Some(u64::MAX)), i64::MAX);
}
