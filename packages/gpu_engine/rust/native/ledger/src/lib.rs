//! The app's one ledger of fingerprints, `test/fixtures/fingerprints.json`,
//! as every crate of this workspace reads it in its tests: CRC-32 (IEEE,
//! the one zip and PNG use), written as eight lowercase hex digits — what
//! gpu_engine's `fingerprint::of` hands the app and the Dart side's
//! `anicelCrc32*` takes (gpu-engine-skeleton, 2026-11-05).
//!
//! One reader for every crate: gpu_engine read the ledger in its own tests,
//! audio's pins wrote the CRC again by hand and copied two of its rows, and
//! the native modules' answers move into the ledger before the C they are
//! held to is deleted (connection-round-checklist A, 관제 2026-11-07) — the
//! third reader, so the three became this one.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

fn hex(crc: u32) -> String {
    format!("{crc:08x}")
}

/// `bytes`' fingerprint, as the ledger writes it.
pub fn fingerprint(bytes: &[u8]) -> String {
    hex(crc32fast::hash(bytes))
}

/// The ledger's hash for `id`. Panics naming `id` when there is no such
/// row, or the ledger cannot be read.
pub fn pinned(id: &str) -> String {
    // Read when the test runs, never fixed when it is built: a lane that
    // changes the ledger alone is measured on its own rows. The checkout's
    // folder, not the manifest's: each crate calls this from its own depth,
    // and .cargo/config.toml hands every run its checkout's QA_CHECKOUT.
    let checkout = std::env::var("QA_CHECKOUT").expect("cargo runs the test, with .cargo/config.toml");
    let path = format!("{checkout}/../../../test/fixtures/fingerprints.json");
    let text = std::fs::read_to_string(&path).unwrap_or_else(|error| panic!("{path}: {error}"));
    let ledger: serde_json::Value =
        serde_json::from_str(&text).unwrap_or_else(|error| panic!("{path}: {error}"));
    ledger["rows"]
        .as_array()
        .and_then(|rows| rows.iter().find(|row| row["id"] == id))
        .and_then(|row| row["hash"].as_str())
        .unwrap_or_else(|| panic!("the ledger has no row {id}"))
        .to_owned()
}

/// Fails unless `bytes` are the ones the ledger pinned as `id`.
pub fn assert_pinned(id: &str, bytes: &[u8]) {
    assert_eq!(fingerprint(bytes), pinned(id), "{id}");
}

#[cfg(test)]
mod tests {
    use super::*;

    // The standard check value of CRC-32/ISO-HDLC — the same pin the
    // Dart side's helper carries, so both sides are the one CRC.
    #[test]
    fn the_check_string_has_the_published_crc() {
        assert_eq!(fingerprint(b"123456789"), "cbf43926");
    }

    #[test]
    fn a_small_fingerprint_keeps_its_leading_zeros() {
        assert_eq!(hex(0x0000_00ab), "000000ab");
    }

    #[test]
    #[should_panic(expected = "the ledger has no row no/such-row")]
    fn a_row_the_ledger_lacks_is_named() {
        pinned("no/such-row");
    }

    #[test]
    #[should_panic(expected = "failed: audio/tone.flac-samples")]
    fn bytes_other_than_the_pinned_ones_fail_naming_the_row() {
        assert_pinned("audio/tone.flac-samples", b"not the samples");
    }
}
