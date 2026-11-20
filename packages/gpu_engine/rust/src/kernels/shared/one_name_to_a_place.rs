//! One reading of a tile's name (F-610, 2026-11-19): the app names a tile
//! by the slot it was handed out at, the pool's books say where it lies
//! (`pool/folded.rs`), and a pass is laid on the place. So a word the app
//! hands over is read to a name where the books are, and nowhere beside
//! them — read there, it is a pass laid on a slot, whose bytes are the
//! tile's no more once a folded tile's page is given back. And where a
//! tile lies is written in one place: a second that writes it and tells
//! no number leaves what was laid by the books before standing
//! (`Lying::as_of`). A test of behaviour passes both till a tile is
//! folded under the copy, so this one reads the source.

use super::source_scan::{assert_home_and_ledger, files_where, sources};

/// A word read to a tile's name — called, or handed on as the function it
/// is (`map(…)`). In two halves, so a scan of this file would not find it.
const READ: &str = concat!("TileAt::of_", "word");

/// Where a set the app names is read (`Named::from_words`).
const HOME: &str = "kernels/composite/mod.rs";

/// The books, whose own it is to read a name: why each does.
const THE_BOOKS: [(&str, &str); 2] = [
    ("kernels/pool/folded.rs", "where a tile lies is kept as a tile's word"),
    ("kernels/pool/mod.rs", "the pool's verbs take a tile by its name: held, let go and read by it"),
];

/// A slot's `lying` written: indexed through the `Arc` made its own. In
/// two halves, as above.
const WRITTEN: &str = concat!(".lying", ")[");

/// Where it is written (`Pool::lies_at`).
const WRITER: &str = "kernels/pool/folded.rs";

/// A taking of no pool's books, where every name is its own place: a
/// test's to make. In two halves, as above.
const NO_BOOKS: &str = concat!("Lying::def", "ault()");

#[test]
fn a_word_is_read_to_a_tile_s_name_where_the_books_are() {
    let mut found = files_where("rs", |text| text.contains(READ));
    // A test names the tiles it stored, and reads back the ones a verb put.
    found.retain(|file| !file.ends_with("tests.rs"));
    let fix = "read the word to where its tile lies (Lying::of_word, Named::lying)";
    assert_home_and_ledger(found, HOME, &THE_BOOKS, fix);
}

#[test]
fn where_a_tile_lies_is_written_in_one_place() {
    let found: Vec<String> = files_where("rs", |text| text.contains(WRITTEN)).into_iter().collect();
    assert_eq!(found, [WRITER], "say where a tile lies by Pool::lies_at");
    assert_eq!(sources()[WRITER].matches(WRITTEN).count(), 1, "say where a tile lies by Pool::lies_at");
}

// A test's build alone makes one, and a line of the crate that took it
// would be laid on names in every test and build nowhere else.
#[test]
fn no_pass_is_laid_by_the_books_of_no_pool() {
    let found = files_where("rs", |text| text.contains(NO_BOOKS));
    assert!(found.iter().any(|file| file.ends_with("tests.rs")), "LIVENESS — the scan finds a test's: {found:?}");
    let laid: Vec<&String> = found.iter().filter(|file| !file.ends_with("tests.rs")).collect();
    assert!(laid.is_empty(), "lay it by the pool's books (Pool::lying): {laid:?}");
}
