//! One read of a stored tile (F-610, 2026-11-19): the composite's rows,
//! the walk over a cel's pixels and the write path's test each spelled
//! where the words of a tile lie in its slot, and they are read by
//! `stored_word` (stored.wgsl) now — the form a tile is stored in is one
//! function's to know. A test of behaviour passes two spellings that
//! agree, so this one reads the source: no shader but stored.wgsl reads a
//! word off the pages a pass binds unnamed.

use super::source_scan::{assert_home_and_ledger, files_where};

/// A read of a word off a page bound unnamed (`Pages::source`). In two
/// halves, so a scan of this file would not find it.
const READ: &str = concat!("page_", "word(");

/// Where the pages' reader itself is defined, which is no read of it.
const DEFINED: &str = concat!("fn page_", "word(");

/// Where a stored tile is read.
const HOME: &str = "kernels/shared/stored.wgsl";

/// The shaders that read their own words off pages bound unnamed, and no
/// stored tile: what each keeps there.
const NO_STORED_TILE: [(&str, &str); 2] = [
    ("kernels/dab/blur.wgsl", "a blur stroke's planes: two words a pixel, 16 bits a channel"),
    ("kernels/dab/blur_cel.wgsl", "a blur stroke's cel planes: two words a pixel, 16 bits a channel"),
];

#[test]
fn a_stored_tile_is_read_in_stored_wgsl_alone() {
    let found = files_where("wgsl", |text| text.contains(READ) && !text.contains(DEFINED));
    assert_home_and_ledger(found, HOME, &NO_STORED_TILE, &format!("read a stored tile with stored_word ({HOME})"));
}

/// 🚨A stored tile's read reads its page at ONE site (F-610, 2026-11-21):
/// the pages' reader is a switch with a case a page, which a device's
/// compiler lays out again at each call of it, and five sites of it cost
/// the composite's compile two and a half times its time (`stored_word`'s
/// note has what was measured). A test of what is read passes one site
/// and five alike, so this one counts them.
#[test]
fn a_stored_tile_reads_its_page_at_one_site() {
    let sites: usize = include_str!("stored.wgsl")
        .lines()
        .filter(|line| !line.trim_start().starts_with("//"))
        .map(|line| line.matches(READ).count())
        .sum();
    assert_eq!(
        sites, 1,
        "{HOME} reads its page at {sites} sites: work out where the next word lies and read it at the one"
    );
}
