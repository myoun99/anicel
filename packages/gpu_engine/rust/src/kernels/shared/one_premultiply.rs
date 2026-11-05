//! One 8-bit premultiply (저장 2026-11-06, gpu-export-path ①e). The
//! export's over-the-ground pass spelled SkMulDiv255Round a second time,
//! under a name of its own beside `premultiply8`, so both compiled; it now
//! calls this one. A test of behaviour passes two copies that agree, so
//! this one reads the source: the rounding's last step, spaces aside, is
//! in `premultiply.wgsl` alone. It reads that spelling only — a copy
//! spelled otherwise is still one (CLAUDE.md, absolute rule 1).
//!
//! ⚠️The walk is `one_builder.rs`'s a second time, for `.wgsl` instead of
//! `.rs`: a third scan joins the two (rule of three, not before).

use std::collections::BTreeSet;
use std::path::Path;

/// `(t + (t >> 8)) >> 8` without its spaces, the tail any spelling of it
/// ends in. In two halves, so a scan of this file would not find it.
const STEP: &str = concat!(">>8u))", ">>8u");

/// Where it is spelled.
const HOME: &str = "kernels/shared/premultiply.wgsl";

/// Every `.wgsl` file under `dir` whose text, spaces aside, holds
/// [`STEP`], relative to `root`.
fn spellers(dir: &Path, root: &Path, found: &mut BTreeSet<String>) {
    let entries =
        std::fs::read_dir(dir).unwrap_or_else(|error| panic!("{}: {error}", dir.display()));
    for entry in entries {
        let path = entry.expect("a directory entry").path();
        if path.is_dir() {
            spellers(&path, root, found);
        } else if path.extension().is_some_and(|extension| extension == "wgsl") {
            let text = std::fs::read_to_string(&path)
                .unwrap_or_else(|error| panic!("{}: {error}", path.display()));
            let bare: String = text.chars().filter(|c| !c.is_whitespace()).collect();
            if bare.contains(STEP) {
                let relative = path.strip_prefix(root).expect("a file under the root");
                found.insert(relative.to_string_lossy().replace('\\', "/"));
            }
        }
    }
}

#[test]
fn the_8_bit_premultiply_is_spelled_in_premultiply_wgsl_alone() {
    let root = Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/src"));
    let mut found = BTreeSet::new();
    spellers(root, root, &mut found);
    assert!(found.remove(HOME), "LIVENESS — the scan finds {HOME}: {found:?}");
    assert!(found.is_empty(), "premultiply with premultiply8 ({HOME}): {found:?}");
}
