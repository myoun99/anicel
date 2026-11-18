//! One place a cell is filled under its own lock
//! (the-ui-thread-never-enters-the-driver, 2026-11-14): `kept_or_made`
//! beside this file, which makes outside the cell what it then puts in it.
//! A cell filled by `OnceLock`'s own filler is held against every other
//! thread as long as the making takes, and where the making compiles a
//! kernel a verb's body that came for the cell meanwhile waits on the
//! engine's thread for the cell, every body behind it with it
//! (`EngineThread::stands_aside`, in `device.rs`). A test of behaviour
//! passes a cell no two came for at once, so this one reads the sources.

use super::source_scan::{assert_home_and_ledger, files_where};

/// `OnceLock`'s own filler. Spelled in two halves, so this file is not
/// one that calls it.
const CALL: &str = concat!("get_or", "_init(");

/// `kept_or_made`'s, and a kernel's own cell, filled on a thread of the
/// engine's for compiling (`Kernel::pipeline`).
const HOME: &str = "kernels/shared/mod.rs";

/// The files that call it where nothing is compiled under the cell, each
/// with why.
const LEDGER: [(&str, &str); 2] = [
    ("kernels/plugin/pace.rs", "a pace measured before it is kept: nothing is made under the cell"),
    ("testing.rs", "the tests' own engine, opened once for them all"),
];

#[test]
fn a_cell_is_filled_outside_its_lock_or_is_on_the_ledger() {
    let found = files_where("rs", |text| text.contains(CALL));
    // The tests' own cells are no verb's body's wait.
    let found = found.into_iter().filter(|file| !file.ends_with("tests.rs")).collect();
    assert_home_and_ledger(found, HOME, &LEDGER, "fill these with kernels::shared::kept_or_made");
}
