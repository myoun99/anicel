//! The Rust memory questions against the engine's C (native/oracle), through
//! their exports. The machine's RAM holds still, so the two say the same;
//! what this process holds and what the machine has free move on all the
//! time, so a Rust answer is held to the C's around it: asked of the C, the
//! Rust and the C again, until the Rust lies between the two C answers.

use super::{
    qa_app_memory_limit_bytes, qa_available_memory_bytes, qa_physical_memory_bytes,
    qa_process_footprint_bytes,
};

type Ask = extern "C" fn() -> i64;

/// The C's export `name`.
fn c(name: &str) -> Ask {
    // SAFETY: qa_engine.c's declaration — no arguments, an int64 back.
    unsafe { oracle::export(name) }
}

/// The Rust's answer, asked between two of the C's that it lies between.
fn between(c: Ask, rust: Ask) -> i64 {
    for _ in 0..1000 {
        let before = c();
        let ours = rust();
        let after = c();
        if before.min(after) <= ours && ours <= before.max(after) {
            return ours;
        }
    }
    panic!("LIVENESS — the Rust never answered between two of the C's answers");
}

#[test]
fn the_ram_is_the_cs() {
    let ram = qa_physical_memory_bytes();
    assert_eq!(ram, c("qa_physical_memory_bytes")());
    assert!(ram > 0, "every platform here says how much RAM it has");
}

#[test]
fn what_this_process_holds_is_what_the_c_says_around_it() {
    let held = between(c("qa_process_footprint_bytes"), qa_process_footprint_bytes);
    assert!(held > 0, "every platform here says what a process holds");
    assert!(held < qa_physical_memory_bytes());
}

#[test]
fn what_more_it_may_take_is_what_the_c_says_around_it() {
    let free = between(c("qa_available_memory_bytes"), qa_available_memory_bytes);
    if cfg!(target_os = "macos") {
        assert_eq!(free, 0, "a Mac gives a process no such number");
    } else {
        assert!(free > 0 && free < qa_physical_memory_bytes());
    }
}

#[test]
fn a_desktop_holds_an_app_to_no_limit_of_its_own() {
    assert_eq!(qa_app_memory_limit_bytes(), c("qa_app_memory_limit_bytes")());
    if cfg!(any(windows, target_os = "macos", target_os = "linux")) {
        assert_eq!(qa_app_memory_limit_bytes(), 0);
    }
}
