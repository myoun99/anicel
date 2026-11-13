//! What the crate's source scans share (관제 2026-11-06, gpu-engine-skeleton
//! — the rule of three: `one_builder.rs`, `one_premultiply.rs`,
//! `one_pass.rs`). A test of behaviour passes two copies that agree, so
//! each of them reads the source for one law's copies: the file that is the
//! law's home, and a ledger of the copies left, each with the area whose it
//! is to replace. A file that stops being a copy leaves the ledger in the
//! same change; a copy that is not on it is red.

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

/// Every `.rs` file under the crate's `src/`: its text — line ends as `\n`
/// — by its path there.
pub(super) fn sources() -> BTreeMap<String, String> {
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").expect("cargo runs the test");
    let src = Path::new(&crate_dir).join("src");
    let read = |file: String| {
        let text = std::fs::read_to_string(src.join(&file)).unwrap_or_else(|error| panic!("{file}: {error}"));
        (file, text.replace("\r\n", "\n"))
    };
    files_where("rs", |_| true).into_iter().map(read).collect()
}

/// A verb of the C ABI as a source defines it: an `extern "C"` function
/// named `gpu_engine_…`. ⛔ONE reader of them: `every_free.rs` read their
/// names, `every_verb.rs` their bodies, and `one_handing_out.rs` came for
/// their signatures as a third (2026-11-14).
pub(super) struct Verb {
    pub(super) name: String,
    /// From the `(` after its name to the brace that opens its body.
    pub(super) signature: String,
    /// From the line that opens it to the brace that closes it at the
    /// line's start.
    pub(super) body: String,
}

/// The verbs `text` defines.
pub(super) fn verbs_in(text: &str) -> Vec<Verb> {
    const EXPORTED: &str = "extern \"C\" fn ";
    let text = text.replace("\r\n", "\n");
    let verb = |at: usize| {
        let after = &text[at + EXPORTED.len()..];
        let name = &after[..after.find('(')?];
        let opens = after.find(" {\n")?;
        let closes = opens + after[opens..].find("\n}")?;
        // None where the words are no definition's: named in a comment.
        let signature = after.get(name.len()..opens)?.to_owned();
        let body = after[opens..closes].to_owned();
        name.starts_with("gpu_engine_").then(|| Verb { name: name.to_owned(), signature, body })
    };
    text.match_indices(EXPORTED).filter_map(|(at, _)| verb(at)).collect()
}

/// Every verb the crate's sources define, by its name.
pub(super) fn verbs() -> BTreeMap<String, Verb> {
    let defined = sources().into_values().flat_map(|text| verbs_in(&text));
    defined.map(|verb| (verb.name.clone(), verb)).collect()
}

/// Whether `body` hands a thing out by the bytes' door
/// (`device::hands_bytes`) — called, or handed on as the function it is
/// (`map_or(null, hands_bytes)`).
pub(super) fn hands_out_bytes(body: &str) -> bool {
    body.contains("hands_bytes")
}

/// Every `.{extension}` file under the crate's `src/` whose text `holds`,
/// as its path under `src/`.
pub(super) fn files_where(extension: &str, holds: impl Fn(&str) -> bool) -> BTreeSet<String> {
    files_under("src", extension, holds)
}

/// The same under the crate's folder `dir` — `.` is this crate with the
/// crates of its workspace (`native/*`) — as each file's path under `dir`.
/// A `target` folder is build output, and is passed over.
pub(super) fn files_under(
    dir: &str,
    extension: &str,
    holds: impl Fn(&str) -> bool,
) -> BTreeSet<String> {
    // Read when the test runs, never fixed when it is built (one_checkout.rs).
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").expect("cargo runs the test");
    let root = Path::new(&crate_dir).join(dir);
    let mut found = BTreeSet::new();
    walk(&root, &root, extension, &holds, &mut found);
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
            if !path.ends_with("target") {
                walk(&path, root, extension, holds, found);
            }
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
