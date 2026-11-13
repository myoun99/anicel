//! One place the crate polls a device till the GPU is done, and with no
//! limit of wgpu's own (the-ui-thread-never-enters-the-driver, 1c,
//! 2026-11-14): `polled`, in `device.rs`, which the engine's thread for
//! polls alone runs. A poll that gives up by a limit, beside a submit on
//! another thread, finds the queue empty behind a submission it read as
//! unfinished, and wgpu panics there — with the limit inside the poll 620
//! of the crate's 919 tests failed behind the tests' engine, its thread
//! for polls gone (`polled` has the reading of wgpu-core). That is a race
//! between two reads inside wgpu, which no test of behaviour holds open,
//! so this one reads the sources (🗣️관제 2026-11-14 08:14: what a test
//! could not pin, a scan pins).

use super::source_scan::{assert_home_and_ledger, sources};

/// What every poll of a device names: how it waits. Spelled in two
/// halves, so this file is not one.
const POLL: &str = concat!("Poll", "Type::");

/// Where the engine polls.
const HOME: &str = "device.rs";

/// The one poll there, whole: till the GPU has finished all that was
/// submitted, for as long as that takes.
const THE_WAIT: &str = concat!("Poll", "Type::Wait { submission_index: None, timeout: None }");

/// A poll that waits for nothing, as the ledger's are.
const NO_WAIT: &str = concat!("Poll", "Type::Poll)");

/// The files that poll a device and are not the engine's wait, each with
/// why.
const LEDGER: [(&str, &str); 1] = [(
    "kernels/composite/screen_tests.rs",
    "a test that asks, once it was told the GPU is done, whether the queue is empty: a poll \
     that waits for nothing, and so names wgpu no submission to hold the queue against",
)];

const FIX: &str = "a device is polled by `polled` in device.rs alone, on the engine's thread \
                   for polls, till the GPU is done and with no limit of wgpu's own — one that \
                   gives up beside a submit panics inside wgpu (620 of the crate's 919 tests \
                   failed by it, 2026-11-14: the reason is at `polled`). Wait through \
                   `Engine::wait` or `Engine::done_then`, which keep the limit outside the driver";

#[test]
fn a_device_is_polled_in_one_place_and_with_no_limit() {
    let sources = sources();
    let polls = |file: &str| sources[file].matches(POLL).count();
    let found = sources.keys().filter(|file| polls(file.as_str()) > 0).cloned().collect();
    assert_home_and_ledger(found, HOME, &LEDGER, FIX);
    assert_eq!((polls(HOME), sources[HOME].matches(THE_WAIT).count()), (1, 1), "{HOME}: {FIX}");
    for (file, _) in LEDGER {
        let waits_for_nothing = sources[file].matches(NO_WAIT).count();
        assert_eq!(polls(file), waits_for_nothing, "{file} waits in a poll of its own: {FIX}");
    }
}
