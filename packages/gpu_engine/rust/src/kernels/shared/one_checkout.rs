//! A crate's test runs the checkout it is run in — its code and its files
//! (관제 2026-11-06, native-to-rust). The trunk and every lane build into
//! the trunk's one target folder (tool/lane.sh, refusal 8), so a build made
//! in one checkout sits there when another runs its tests:
//!
//! - THE CODE. Cargo builds a crate again when its files are newer than its
//!   build, and a lane's files are older than a build another checkout made
//!   after the lane's last edit — so the lane's gate ran THAT checkout's
//!   code (measured 2026-11-06: two checkouts on one target, the second's
//!   test changed to fail and dated earlier, ran the first's and passed).
//!   Cargo also builds a crate again when a variable it read has changed:
//!   each crate reads QA_CHECKOUT, this checkout's folder (.cargo/
//!   config.toml), so another checkout's build of it is never fresh here.
//!   Only the workspace's crates are built again; wgpu and the rest are not.
//! - THE FILES. A path made with the `env!` macro is the checkout the test
//!   was BUILT in: after the image-encode land the trunk ran the oracle's
//!   test against the C of the lane just deleted (exit 101). Read with
//!   `std::env::var` it is the checkout that RUNS the test — cargo sets the
//!   variable for the run as for the build.

use super::source_scan::files_under;

/// Read by every crate of the workspace, at the top of its `lib.rs`.
const BUILT_HERE: &str = "option_env!(\"QA_CHECKOUT\")";

/// The manifest's folder, fixed when the test is built. In two halves, so
/// this file is not one.
const FIXED: &str = concat!("env!(\"CARGO", "_MANIFEST_DIR\")");

/// The manifest's folder, read when the test runs.
const READ: &str = "std::env::var(\"CARGO_MANIFEST_DIR\")";

#[test]
fn this_build_was_made_in_the_checkout_it_runs_in() {
    let built = option_env!("QA_CHECKOUT").expect("LIVENESS — .cargo/config.toml sets QA_CHECKOUT");
    let runs = std::env::var("CARGO_MANIFEST_DIR").expect("cargo runs the test");
    let real = |dir: &str| std::fs::canonicalize(dir).unwrap_or_else(|e| panic!("{dir}: {e}"));
    assert_eq!(real(built), real(&runs), "a build another checkout made ran here");
}

#[test]
fn every_crate_is_built_from_the_checkout_it_runs_in() {
    let built_here = files_under(".", "rs", |text| text.contains(BUILT_HERE));
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").expect("cargo runs the test");
    let native = std::fs::read_dir(format!("{crate_dir}/native")).expect("native/");
    let mut roots = vec!["src/lib.rs".to_owned()];
    for entry in native {
        let name = entry.expect("a directory entry").file_name();
        roots.push(format!("native/{}/src/lib.rs", name.to_string_lossy()));
    }
    assert!(roots.contains(&"native/oracle/src/lib.rs".to_owned()), "LIVENESS — {roots:?}");
    let missing: Vec<_> = roots.iter().filter(|root| !built_here.contains(*root)).collect();
    assert!(missing.is_empty(), "read {BUILT_HERE} at the top, as src/lib.rs does: {missing:?}");
}

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
