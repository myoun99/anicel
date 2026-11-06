//! The checkout a test reads is the one it runs in (관제 2026-11-06,
//! native-to-rust). The trunk and every lane build into the trunk's one
//! target folder (tool/lane.sh, refusal 8), and cargo does not build again
//! a test that is fresh — so a test built in one checkout runs in another.
//! A path made with the `env!` macro is the checkout the test was BUILT in:
//! after the image-encode land the trunk ran the oracle's test against the
//! C of the lane just deleted (exit 101), and a lane that changed the ledger
//! alone had its rows read from whichever checkout built the crate last.
//! Read with `std::env::var` it is the checkout that RUNS the test — cargo
//! sets the variable for the run as for the build (measured 2026-11-06: two
//! checkouts on one target, a fresh test's macro named the first and its
//! variable the second).

use super::source_scan::files_under;

/// The variable, fixed when the test is built. In two halves, so this file
/// is not one.
const FIXED: &str = concat!("env!(\"CARGO", "_MANIFEST_DIR\")");

/// The variable, read when the test runs.
const READ: &str = "std::env::var(\"CARGO_MANIFEST_DIR\")";

#[test]
fn every_crate_finds_its_files_in_the_checkout_it_runs_in() {
    let fixed = files_under(".", "rs", |text| text.contains(FIXED));
    assert!(fixed.is_empty(), "read it when the test runs, {READ}: {fixed:?}");
    // The scan reaches the workspace's other crates as well as this one.
    let read = files_under(".", "rs", |text| text.contains(READ));
    for file in ["native/oracle/src/lib.rs", "src/fingerprint.rs"] {
        assert!(read.contains(file), "LIVENESS — the scan reads {file}: {read:?}");
    }
}
