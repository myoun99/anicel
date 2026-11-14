//! The NDK's media API is `ndk-sys`'s — bindings made from the NDK's own
//! headers, never a table written by hand (관제 2026-11-07, native-to-rust:
//! 「손 사본 대신 ndk-sys」; media's `served_span.rs` says why: three hand
//! tables of 2026-09-24 disagreed on an offset's width and on two status
//! values). The video crate's own copy, `ndk.rs`, went the same day; this
//! reads the workspace for a declaration of the library or of one of its
//! functions, which is a table again however it is spelled.

use super::source_scan::files_under;

/// What only a table of the library's own says: its name to link, or a
/// function of it declared rather than called. In halves, so this file is
/// not one.
const BY_HAND: [&str; 2] = [concat!("\"media", "ndk\""), concat!("fn ", "AMedia")];

/// Whether `text` declares any of the NDK media API itself.
fn declares_it(text: &str) -> bool {
    BY_HAND.iter().any(|mark| text.contains(mark))
}

#[test]
fn no_crate_declares_the_ndk_media_api_by_hand() {
    assert!(declares_it(concat!("#[link(name = \"media", "ndk\")]")), "LIVENESS — a link");
    assert!(declares_it(concat!("pub fn ", "AMediaCodec_delete(codec: *mut AMediaCodec)")), "LIVENESS — a function");
    assert!(!declares_it("unsafe { AMediaCodec_delete(codec) };"), "a call is ndk-sys's");
    let reached = files_under(".", "rs", |text| text.contains(concat!("ndk", "_sys::")));
    assert!(
        reached.contains("native/media/src/served_span.rs"),
        "LIVENESS — the scan reads the crates that call it: {reached:?}"
    );
    let tables = files_under(".", "rs", declares_it);
    assert!(tables.is_empty(), "call ndk-sys there, as native/media does: {tables:?}");
}
