//! One pipeline builder (관제 2026-11-05, gpu-engine-skeleton; 저장 found
//! the copies). `pipeline` beside this file joins a kernel's sources and
//! makes its module and its pipeline; a file of its own that calls
//! wgpu's `create_compute_pipeline` is a copy of that, however different
//! the text. A test of behaviour passes two copies that agree, so this one
//! reads the source.
//!
//! The ledger holds the copies that stood when it was written, each with
//! the area whose it is to replace. A file that stops being one leaves the
//! ledger in the same change; a file that is not on it is red.

use std::collections::BTreeSet;
use std::path::Path;

/// What a builder calls. Spelled in two halves, so this file is not one.
const CALL: &str = concat!("create_compute", "_pipeline(");

/// The one builder.
const BUILDER: &str = "kernels/shared/mod.rs";

/// The copies still standing, and whose they are.
const LEDGER: &[(&str, &str)] = &[
    ("kernels/blend/tests.rs", "브러시/렌더링"),
    ("kernels/composite/mod.rs", "브러시/렌더링"),
    ("kernels/dab/mod.rs", "브러시/렌더링"),
    ("kernels/shared/tests.rs", "브러시/렌더링"),
    ("kernels/effects/tests.rs", "캔버스 베이스 패널"),
];

/// Every `.rs` file under `dir` that calls [`CALL`], relative to `root`.
fn callers(dir: &Path, root: &Path, found: &mut BTreeSet<String>) {
    let entries =
        std::fs::read_dir(dir).unwrap_or_else(|error| panic!("{}: {error}", dir.display()));
    for entry in entries {
        let path = entry.expect("a directory entry").path();
        if path.is_dir() {
            callers(&path, root, found);
        } else if path.extension().is_some_and(|extension| extension == "rs") {
            let text = std::fs::read_to_string(&path)
                .unwrap_or_else(|error| panic!("{}: {error}", path.display()));
            if text.contains(CALL) {
                let relative = path.strip_prefix(root).expect("a file under the root");
                found.insert(relative.to_string_lossy().replace('\\', "/"));
            }
        }
    }
}

#[test]
fn a_compute_pipeline_is_built_by_the_one_builder_or_a_copy_on_the_ledger() {
    let root = Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/src"));
    let mut found = BTreeSet::new();
    callers(root, root, &mut found);
    assert!(found.remove(BUILDER), "LIVENESS — the scan finds the builder: {found:?}");
    let ledger: BTreeSet<String> = LEDGER.iter().map(|(file, _)| file.to_string()).collect();
    let new: Vec<_> = found.difference(&ledger).collect();
    assert!(new.is_empty(), "build these with kernels::shared::pipeline: {new:?}");
    let gone: Vec<_> = ledger.difference(&found).collect();
    assert!(gone.is_empty(), "no copy any more — take these off the ledger: {gone:?}");
}
