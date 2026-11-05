//! What the crate's source scans share (관제 2026-11-06, gpu-engine-skeleton
//! — the rule of three: `one_builder.rs`, `one_premultiply.rs`,
//! `one_pass.rs`). A test of behaviour passes two copies that agree, so
//! each of them reads the source for one law's copies: the file that is the
//! law's home, and a ledger of the copies left, each with the area whose it
//! is to replace. A file that stops being a copy leaves the ledger in the
//! same change; a copy that is not on it is red.

use std::collections::BTreeSet;
use std::path::Path;

/// Every `.{extension}` file under the crate's `src/` whose text `holds`,
/// as its path under `src/`.
pub(super) fn files_where(extension: &str, holds: impl Fn(&str) -> bool) -> BTreeSet<String> {
    let root = Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/src"));
    let mut found = BTreeSet::new();
    walk(root, root, extension, &holds, &mut found);
    found
}

fn walk(
    dir: &Path,
    root: &Path,
    extension: &str,
    holds: &dyn Fn(&str) -> bool,
    found: &mut BTreeSet<String>,
) {
    let entries =
        std::fs::read_dir(dir).unwrap_or_else(|error| panic!("{}: {error}", dir.display()));
    for entry in entries {
        let path = entry.expect("a directory entry").path();
        if path.is_dir() {
            walk(&path, root, extension, holds, found);
        } else if path.extension().is_some_and(|own| own == extension) {
            let text = std::fs::read_to_string(&path)
                .unwrap_or_else(|error| panic!("{}: {error}", path.display()));
            if holds(&text) {
                let relative = path.strip_prefix(root).expect("a file under the root");
                found.insert(relative.to_string_lossy().replace('\\', "/"));
            }
        }
    }
}

/// That `found` is `home` and the ledger's files, no more and no fewer: a
/// copy off the ledger is told `fix`, and a ledger line whose file is no
/// longer a copy is told to leave.
pub(super) fn assert_home_and_ledger(
    mut found: BTreeSet<String>,
    home: &str,
    ledger: &[(&str, &str)],
    fix: &str,
) {
    assert!(found.remove(home), "LIVENESS — the scan finds {home}: {found:?}");
    let ledger: BTreeSet<String> = ledger.iter().map(|(file, _)| file.to_string()).collect();
    let new: Vec<_> = found.difference(&ledger).collect();
    assert!(new.is_empty(), "{fix}: {new:?}");
    let gone: Vec<_> = ledger.difference(&found).collect();
    assert!(gone.is_empty(), "no copy any more — take these off the ledger: {gone:?}");
}
