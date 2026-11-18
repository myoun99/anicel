//! One writing of a framed span for every crate's tests (저장 2026-11-07,
//! native-to-rust — the video decoder): media's span and stream tests and
//! audio's each laid the save's blocks out themselves, three copies, and the
//! decoder's would have been a fourth. They call `oracle::framed`; this
//! reads the workspace for the layout's first word written anywhere else.
//! It reads that spelling only — a copy spelled otherwise is still one
//! (CLAUDE.md, absolute rule 1).

use super::source_scan::{assert_home_and_ledger, files_under};

/// The block size written as the layout's first word, as any writing of it
/// starts. In halves, so this file is not one.
const FIRST_WORD: &str = concat!("(block_bytes as u32)", ".to_le_bytes()");

/// Where it is written.
const HOME: &str = "native/oracle/src/lib.rs";

#[test]
fn a_framed_span_is_written_for_tests_in_oracle_alone() {
    let found = files_under(".", "rs", |text| text.contains(FIRST_WORD));
    assert_home_and_ledger(found, HOME, &[], "frame it with oracle::framed");
}
