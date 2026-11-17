//! One place a kernel's code waits for threads of its own making
//! (the-ui-thread-never-enters-the-driver, 2026-11-14):
//! `Engine::side_by_side`, in `device.rs`. A verb's body runs on the
//! engine's thread, and one that waits there for a compile leaves that
//! thread to the bodies behind it (`EngineThread::stands_aside`) — where it
//! asks for the compile itself. A body that starts threads to compile on
//! and waits for them asks for none, and every other verb's body would
//! stand behind it as long: `side_by_side` leaves the thread first. A test
//! of behaviour passes a body no other was behind, so this one reads the
//! sources.

use super::source_scan::{assert_home_and_ledger, files_where};

/// What waits for the threads it starts. Spelled in two halves, so this
/// file is not one.
const CALL: &str = concat!("thread::", "scope(");

/// Where the engine does.
const HOME: &str = "device.rs";

/// The files that do and are no body's wait, each with why.
const LEDGER: [(&str, &str); 3] = [
    (
        "kernels/shared/mod.rs",
        "a plugin's compile, on a thread for its stack — inside a thread of the engine's for \
         compiling, which a body waits for through `Engine::compiling`",
    ),
    (
        "kernels/shared/one_device_turn.rs",
        "the devices' turn's own test: a second test's thread, which takes the turn the first \
         holds — a test's threads, no verb's body, in a file no `tests.rs`",
    ),
    (
        "platform/windows.rs",
        "the DXIL cache's tests: two engines that ask for one new kernel at once, and a compile \
         beside a turn another process holds — a test's threads, no verb's body, in a file no \
         `tests.rs`",
    ),
];

#[test]
fn a_kernels_code_waits_for_threads_of_its_own_through_the_engine_alone() {
    let found = files_where("rs", |text| text.contains(CALL));
    // The tests' own threads are no verb's body.
    let found = found.into_iter().filter(|file| !file.ends_with("tests.rs")).collect();
    assert_home_and_ledger(found, HOME, &LEDGER, "run these with `Engine::side_by_side`");
}
