//! The memory questions, through their exports, held to what each answer
//! must be on the platforms this runs on. ↩️Until the connection round
//! deleted the C (connection-round-checklist H, 2026-11-08), each was held
//! to the C's answer around it as well (native/oracle); what this process
//! holds is pinned against the bytes it touches by the app's own test of
//! the same export (test/native/the_process_number_is_the_one_the_os_shows_test.dart).

use super::{
    qa_app_memory_limit_bytes, qa_available_memory_bytes, qa_physical_memory_bytes,
    qa_process_footprint_bytes, said,
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

#[test]
fn an_answer_not_said_is_zero_and_one_too_large_is_the_most_there_is() {
    assert_eq!(said(None), 0);
    assert_eq!(said(Some(7)), 7);
    assert_eq!(said(Some(u64::MAX)), i64::MAX);
}
