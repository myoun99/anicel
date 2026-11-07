//! The pen, beside the OS pointer (native-to-rust; the C was
//! qa_tablet_win.c, qa_penraw_win.c, qa_pen_hid_axis.h and
//! qa_pen_ledger_apple.m).
//!
//! On Windows: what the tablet DRIVER says of the pen (Wintab — `qat_*`)
//! and what its HID report says (Raw Input — `qpr_*`), which Dart's bridge
//! (lib/src/native/qa_tablet_bridge.dart) binds there alone, in the GPU
//! engine's library that carries this crate. Each half keeps the C's ABI —
//! `qat_abi_version` 2, `qpr_abi_version` 3 — the one the bridge reads
//! (tests.rs holds them to its).
//!
//! On Apple: the PEN LEDGER (`qa_pen_ledger_*`, H43) — what UIKit or AppKit
//! said of each pen sample, read by the sample's own timestamp
//! (lib/src/native/qa_pen_ledger.dart).

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

#[cfg(target_vendor = "apple")]
mod apple;
// The laws, the report's word and the ledger have no platform in them, and
// run their cases on every host; the readers that use them are Windows' and
// Apple's.
#[cfg_attr(not(windows), allow(dead_code))]
mod hid_axis;
#[cfg_attr(not(target_vendor = "apple"), allow(dead_code))]
mod ledger;
#[cfg_attr(not(windows), allow(dead_code))]
mod report;
#[cfg(windows)]
mod raw;
#[cfg(test)]
mod tests;
#[cfg(windows)]
mod wintab;

/// v2 (F-176-Q9): a packet's record carries the twist, so it is eight
/// floats where it was six.
#[cfg(windows)]
#[unsafe(no_mangle)]
pub extern "C" fn qat_abi_version() -> i32 {
    2
}

/// 1 when wintab32 loads AND it reports an installed driver and device.
#[cfg(windows)]
#[unsafe(no_mangle)]
pub extern "C" fn qat_available() -> i32 {
    i32::from(wintab::available())
}

/// The device's name, UTF-16, into `out` — at most `cap - 1` characters
/// and a NUL; its length. 0 with no driver.
///
/// # Safety
/// `out` is null or `cap` writable `u16`s.
#[cfg(windows)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qat_device_name(out: *mut u16, cap: i32) -> i32 {
    let room = (!out.is_null() && cap > 0).then(|| {
        // SAFETY: see the function's contract.
        unsafe { std::slice::from_raw_parts_mut(out, cap as usize) }
    });
    wintab::device_name(room).map_or(0, |length| length as i32)
}

/// Opens the observe-only polling context. 1 on success; idempotent. 0 with
/// no driver, or no app window yet.
#[cfg(windows)]
#[unsafe(no_mangle)]
pub extern "C" fn qat_open() -> i32 {
    i32::from(wintab::open())
}

/// Drains the queued packets into `out` as records of 8 floats — pressure
/// 0..1, bearing, altitude, time in ms, buttons, oriented, twist, twisted
/// (see `wintab::Scales::record`) — at most `cap` of them and at most 64.
/// The record count; 0 with nothing queued, or no context open.
///
/// # Safety
/// `out` is null or `8 * cap` writable `f32`s.
#[cfg(windows)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qat_poll(out: *mut f32, cap: i32) -> i32 {
    if out.is_null() || cap <= 0 {
        return 0;
    }
    // SAFETY: see the function's contract.
    let out = unsafe { std::slice::from_raw_parts_mut(out, 8 * cap as usize) };
    wintab::poll(out) as i32
}

#[cfg(windows)]
#[unsafe(no_mangle)]
pub extern "C" fn qat_close() {
    wintab::close();
}

/// v2 (desktop-pen-tilt): `qpr_poll` also hands over the report's tilt;
/// v3 (F-176-Q9) its twist.
#[cfg(windows)]
#[unsafe(no_mangle)]
pub extern "C" fn qpr_abi_version() -> i32 {
    3
}

/// Starts the HID observer thread. 1 when raw pen reports will flow;
/// idempotent. 0 without hid.dll, or with no digitizer registered.
#[cfg(windows)]
#[unsafe(no_mangle)]
pub extern "C" fn qpr_start() -> i32 {
    i32::from(raw::start())
}

#[cfg(windows)]
#[unsafe(no_mangle)]
pub extern "C" fn qpr_stop() {
    raw::stop();
}

/// Snapshots the newest decoded report into `out`, as many floats of it
/// as the caller's ABI reads: `cap` 2 the flag word and the report counter,
/// 5 its tilt as well, 7 its twist (see `report::snapshot`). 1 when the
/// observer is live, 0 otherwise.
///
/// # Safety
/// `out` is null or `cap` writable `f32`s.
#[cfg(windows)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qpr_poll(out: *mut f32, cap: i32) -> i32 {
    if out.is_null() || cap < 2 {
        return 0;
    }
    // SAFETY: see the function's contract; no more than 7 are written.
    let out = unsafe { std::slice::from_raw_parts_mut(out, cap.min(7) as usize) };
    i32::from(raw::poll(out))
}

/// Starts whatever the platform needs to keep the ledger: the event
/// monitor on macOS; nothing on iOS, where the Runner writes. Safe to call
/// again.
#[cfg(target_vendor = "apple")]
#[unsafe(no_mangle)]
pub extern "C" fn qa_pen_ledger_start() {
    apple::start();
}

/// The FORCE the ledger holds for the sample Flutter stamped `micros` (see
/// `ledger::Ledger::value`): the value, or -1 none, -2 an estimate, -3 no
/// pressure, -4 a final estimate.
#[cfg(target_vendor = "apple")]
#[unsafe(no_mangle)]
pub extern "C" fn qa_pen_ledger_value(micros: i64) -> f64 {
    ledger::ledger().value(micros)
}

/// The ALTITUDE the ledger holds for the sample Flutter stamped `micros`
/// (see `ledger::Ledger::altitude`): radians, or -1 none, -2 an estimate,
/// -4 a final estimate.
#[cfg(target_vendor = "apple")]
#[unsafe(no_mangle)]
pub extern "C" fn qa_pen_ledger_altitude(micros: i64) -> f64 {
    ledger::ledger().altitude(micros)
}

/// AppKit's TILT of the sample Flutter stamped `micros`, into `xy`: 1 when
/// the ledger holds one, 0 when it holds none.
///
/// # Safety
/// `xy` is two writable `f64`s.
#[cfg(target_vendor = "apple")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_pen_ledger_tilt(micros: i64, xy: *mut f64) -> i32 {
    let Some((x, y)) = ledger::ledger().tilt(micros) else {
        return 0;
    };
    // SAFETY: see the function's contract.
    unsafe {
        xy.write(x);
        xy.add(1).write(y);
    }
    1
}
