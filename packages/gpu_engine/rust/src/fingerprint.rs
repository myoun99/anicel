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

/// Reads the surface back into `out`, `length` bytes: its width × height
/// texels, row after row with nothing between. False on failure, a length
/// that is not the surface's among them; see the last error.
///
/// # Safety
/// `engine` and `surface` are live, `surface` was made on `engine`, and
/// `out` holds `length` writable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_surface_read(
    engine: *const Engine,
    surface: *const Surface,
    out: *mut u8,
    length: usize,
) -> bool {
    // SAFETY: see the function's contract.
    let (engine, surface) = unsafe { (&*engine, &*surface) };
    let Some(bytes) = engine.read_texture(&surface.texture) else {
        return false;
    };
    if bytes.len() != length {
        return crate::fail::<()>(format!(
            "a surface of {} bytes read into {length}",
            bytes.len()
        ))
        .is_some();
    }
    // SAFETY: `out` holds `length` writable bytes, and `bytes` as many.
    unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), out, length) };
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    // The standard check value of CRC-32/ISO-HDLC — the same pin the
    // Dart side's helper and the tests' ledger carry, so all three are the
    // one CRC.
    #[test]
    fn the_check_string_has_the_published_crc() {
        assert_eq!(of(b"123456789"), 0xcbf4_3926);
    }
}
