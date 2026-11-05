//! The fingerprint pinned bytes are compared by: CRC-32 (IEEE, the one zip
//! and PNG use), written as eight lowercase hex digits. The app's Dart side
//! takes the same with `anicelCrc32*` (anicel_incremental_writer.dart), so
//! one ledger, `test/fixtures/fingerprints.json`, serves both — and no hash
//! of our own is written (gpu-engine-skeleton, 2026-11-05).

use crate::device::Engine;
use crate::platform::Surface;

pub fn of(bytes: &[u8]) -> u32 {
    crc32fast::hash(bytes)
}

/// As the ledger writes it.
#[cfg(test)]
pub fn hex(fingerprint: u32) -> String {
    format!("{fingerprint:08x}")
}

/// The ledger's hash for `id`. Panics naming `id` when there is no such
/// row, or the ledger cannot be read.
#[cfg(test)]
pub fn pinned(id: &str) -> String {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../test/fixtures/fingerprints.json");
    let text = std::fs::read_to_string(path).unwrap_or_else(|error| panic!("{path}: {error}"));
    let ledger: serde_json::Value =
        serde_json::from_str(&text).unwrap_or_else(|error| panic!("{path}: {error}"));
    ledger["rows"]
        .as_array()
        .and_then(|rows| rows.iter().find(|row| row["id"] == id))
        .and_then(|row| row["hash"].as_str())
        .unwrap_or_else(|| panic!("the ledger has no row {id}"))
        .to_owned()
}

/// The fingerprint of `length` bytes — for bytes read off Flutter's screen,
/// so they are fingerprinted by the same code as the GPU's.
///
/// # Safety
/// `bytes` holds `length` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_fingerprint_bytes(bytes: *const u8, length: usize) -> u32 {
    if bytes.is_null() {
        return of(&[]);
    }
    // SAFETY: see the function's contract.
    of(unsafe { std::slice::from_raw_parts(bytes, length) })
}

/// Reads the surface back and writes its fingerprint to `fingerprint`.
/// False on failure; see the last error.
///
/// # Safety
/// `engine` and `surface` are live, `surface` was made on `engine`, and
/// `fingerprint` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_surface_fingerprint(
    engine: *const Engine,
    surface: *const Surface,
    fingerprint: *mut u32,
) -> bool {
    // SAFETY: see the function's contract.
    let (engine, surface) = unsafe { (&*engine, &*surface) };
    match engine.read_texture(&surface.texture) {
        Some(bytes) => {
            // SAFETY: see the function's contract.
            unsafe { *fingerprint = of(&bytes) };
            true
        }
        None => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // The standard check value of CRC-32/ISO-HDLC — the same pin the
    // Dart side's helper carries, so both sides are the one CRC.
    #[test]
    fn the_check_string_has_the_published_crc() {
        assert_eq!(hex(of(b"123456789")), "cbf43926");
    }

    #[test]
    fn a_small_fingerprint_keeps_its_leading_zeros() {
        assert_eq!(hex(0x0000_00ab), "000000ab");
    }
}
