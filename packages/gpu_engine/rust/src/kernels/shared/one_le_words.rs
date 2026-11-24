//! One reading of a buffer's bytes as its words (공통 2026-11-24, card
//! the-ui-isolate-still-waits-for-the-gpu-in-places W3). `le_words` stood
//! in `dispatch.rs` while the cel pixel pass, the write test, the colour
//! key's run and the export's upload each spelled it again — and five
//! tests beside them. A test of behaviour passes copies that agree, so this
//! reads the source: four bytes of one slice, `[0]` to `[3]`, made a word
//! low byte first, is spelled in `dispatch.rs` alone. It reads that
//! spelling only — a copy spelled otherwise is still one (CLAUDE.md,
//! absolute rule 1).

use super::source_scan::{assert_home_and_ledger, files_where};

/// Where it is spelled.
const HOME: &str = "kernels/shared/dispatch.rs";

/// Whether `text`, its spaces taken out, makes a word of four bytes of one
/// slice in order.
fn reads_words(text: &str) -> bool {
    // In two halves, so a scan of this file would not find it.
    const OPENS: &str = concat!("u32::from_le_", "bytes([");
    let bare: String = text.chars().filter(|c| !c.is_whitespace()).collect();
    bare.match_indices(OPENS).any(|(at, _)| {
        let after = &bare[at + OPENS.len()..];
        let Some(first) = after.find("[0],") else {
            return false;
        };
        let slice = &after[..first];
        let named = !slice.is_empty() && slice.chars().all(|c| c.is_alphanumeric() || c == '_');
        named && after[first + "[0],".len()..].starts_with(&format!("{slice}[1],{slice}[2],{slice}[3]])"))
    })
}

#[test]
fn a_buffers_words_are_read_in_dispatch_rs_alone() {
    let found = files_where("rs", reads_words);
    assert_home_and_ledger(found, HOME, &[], &format!("read them with le_words ({HOME})"));
}

#[test]
fn the_scan_tells_a_word_read_from_another_making() {
    let opens = concat!("u32::from_le_", "bytes([");
    assert!(reads_words(&format!("{opens}four[0], four[1], four[2], four[3]])")));
    assert!(!reads_words(&format!("{opens}ground[0], ground[1], ground[2], 0])")));
    assert!(!reads_words(&format!("{opens}a[0], b[1], a[2], a[3]])")));
}
