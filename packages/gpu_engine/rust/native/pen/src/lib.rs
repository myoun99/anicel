//! The pen, beside the OS pointer (native-to-rust; the C was
//! qa_tablet_win.c, qa_penraw_win.c, qa_pen_hid_axis.h and
//! qa_pen_ledger_apple.m).
//!
//! On Windows: what the tablet DRIVER says of the pen (Wintab — `qat_*`)
//! and what its HID report says (Raw Input — `qpr_*`), which Dart's bridge
//! (lib/src/native/qa_tablet_bridge.dart) binds there alone, in the GPU
//! engine's library that carries this crate. Each half keeps the C's ABI —
//! `qat_abi_version` 3, `qpr_abi_version` 3 — the one the bridge reads
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
// And so has the book of the points the OS saw (H56): every platform's
// reader writes it but Linux's, where each motion is its own event
// (`linux/runner/my_application.cc` turns GTK's compression off).
mod points;
#[cfg(windows)]
mod points_win;
#[cfg_attr(not(windows), allow(dead_code))]
mod report;
#[cfg(windows)]
mod raw;
#[cfg(test)]
mod tests;
#[cfg(windows)]
mod wintab;

/// v2 (F-176-Q9): a packet's record carries the twist, so it is eight
/// floats where it was six; v3: `qat_open` takes the window a packet gives
/// a mouse move its pressure within, and the queue says how it went
/// (`qat_overflowed` · `qat_clock_gap`).
#[cfg(windows)]
#[unsafe(no_mangle)]
pub extern "C" fn qat_abi_version() -> i32 {
    3
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

/// Opens the observe-only polling context, a packet giving a mouse move its
/// pressure `within_ms` of it (none below 0). 1 on success; idempotent. 0
/// with no driver, or no app window yet.
#[cfg(windows)]
#[unsafe(no_mangle)]
pub extern "C" fn qat_open(within_ms: i32) -> i32 {
    i32::from(wintab::open(within_ms.max(0) as u32))
}

/// Hands `out` the newest packets heard and not handed yet — the reader's
/// own thread drains the driver's queue, and this asks it nothing — as
/// records of 8 floats — pressure 0..1, bearing, altitude, time in ms,
/// buttons, oriented, twist, twisted (see `wintab::Scales::record`) — at
/// most `cap` of them. The record count; 0 with nothing new, or no context
/// open.
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

/// How many packets said the driver's queue overflowed before them since
/// the context opened; 0 with none open.
#[cfg(windows)]
#[unsafe(no_mangle)]
pub extern "C" fn qat_overflowed() -> i32 {
    wintab::heard().map_or(0, |(overflowed, _)| overflowed.min(i32::MAX as u32) as i32)
}

/// How far the newest packet was behind the mouse message last handled, in
/// ms of the message clock, into `out`: 1 when it was written, 0 before a
/// mouse message met a packet or with no context open.
///
/// # Safety
/// `out` is null or a writable `i32`.
#[cfg(windows)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qat_clock_gap(out: *mut i32) -> i32 {
    match wintab::heard().and_then(|(_, gap)| gap) {
        Some(gap) if !out.is_null() => {
            // SAFETY: see the function's contract.
            unsafe { out.write(gap) };
            1
        }
        _ => 0,
    }
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

/// Starts the platform's reader of the points the OS saw (points.rs): the
/// Flutter view's subclass on Windows; AppKit's every event its own on
/// macOS (`apple::hand_every_point`). 1 once nothing is left to start —
/// and at once where a Runner writes the book (iOS, Android) or turns the
/// merging off itself (Linux); 0 on Windows till there is a window shown.
/// Safe to call again.
#[unsafe(no_mangle)]
pub extern "C" fn qa_pen_points_start() -> i32 {
    #[cfg(windows)]
    let started = points_win::start();
    #[cfg(not(windows))]
    let started = {
        #[cfg(target_vendor = "apple")]
        apple::hand_every_point();
        true
    };
    i32::from(started)
}

/// A point of the message Android's Runner is handing over
/// (`com.myoun.gpu_engine.PenPoints`) — in a datum's units
/// (`points::Point`); NaN where it gives none.
#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub extern "system" fn Java_com_myoun_gpu_1engine_PenPoints_point(
    _env: *mut std::ffi::c_void,
    _class: *mut std::ffi::c_void,
    x: f64,
    y: f64,
    micros: i64,
    pressure: f64,
    tilt: f64,
    orientation: f64,
) {
    let point = points::Point { pressure, tilt, orientation, ..points::Point::at(x, y, micros) };
    points::book().point(point);
}

/// The end of that message: its points as the batch of `contact`, the
/// pointer of `tool` (`MotionEvent.getToolType`), handed at (`x`, `y`).
#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_myoun_gpu_1engine_PenPoints_end(
    _env: *mut std::ffi::c_void,
    _class: *mut std::ffi::c_void,
    contact: i64,
    tool: i32,
    x: f64,
    y: f64,
) {
    points::book().end(contact as u64, points::Kind::of_android_tool(tool), (x, y));
}

/// The batch [`qa_pen_points_take`] took last, till the app reads it
/// ([`qa_pen_points_taken`]).
static TAKEN: std::sync::Mutex<Vec<points::Point>> = std::sync::Mutex::new(Vec::new());

fn taken() -> std::sync::MutexGuard<'static, Vec<points::Point>> {
    TAKEN.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// Takes the points of the datum of `kind` (`points::Kind`'s number)
/// Flutter was handed at (`x`, `y`), in the shape the embedder hands it
/// (`points::Batch::handed`) — every point the reader wrote of its
/// message —, and holds them for [`qa_pen_points_taken`]: their count; -1
/// where no batch of that kind ends there, or no kind has that number.
///
/// ↩️It wrote the newest `cap` into the app's buffer, which held 512 —
/// H56's guess at a stall of two seconds of a 240 Hz pen — and the book cut
/// every batch to as many: no one asked for the cut (H59 법 A, card
/// pen-points-are-taken-off-the-ui-thread, 11-17).
#[unsafe(no_mangle)]
pub extern "C" fn qa_pen_points_take(kind: i32, x: f64, y: f64) -> i32 {
    let Some(kind) = points::Kind::named(kind) else {
        return -1;
    };
    let Some(points) = points::book().take(kind, (x, y)) else {
        return -1;
    };
    let count = points.len() as i32;
    *taken() = points;
    count
}

/// The points [`qa_pen_points_take`] took last, into `out` — the oldest
/// first, `points::POINT_WORDS` numbers each (`points::Point::words`), at
/// most `room` of them —, let go of here: their count.
///
/// # Safety
/// `out` is null or `POINT_WORDS * room` writable `f64`s.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_pen_points_taken(out: *mut f64, room: usize) -> usize {
    let points = std::mem::take(&mut *taken());
    if out.is_null() {
        return 0;
    }
    let count = points.len().min(room);
    // SAFETY: see the function's contract.
    let out = unsafe { std::slice::from_raw_parts_mut(out, points::POINT_WORDS * count) };
    for (words, point) in out.chunks_exact_mut(points::POINT_WORDS).zip(&points) {
        words.copy_from_slice(&point.words());
    }
    count
}

/// How many messages' batches no datum was paired with
/// (`points::Book::passed`): each a message whose points no stroke got.
#[unsafe(no_mangle)]
pub extern "C" fn qa_pen_points_passed() -> u64 {
    points::book().passed()
}

/// How many messages' points did not all reach the book, by why
/// (`points::Lost`, in its order), into `out`: the count written, at
/// most `room`.
///
/// # Safety
/// `out` is null or `room` writable `u64`s.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_pen_points_lost(out: *mut u64, room: usize) -> usize {
    if out.is_null() {
        return 0;
    }
    let lost = points::book().lost();
    let count = lost.len().min(room);
    // SAFETY: see the function's contract.
    unsafe { std::slice::from_raw_parts_mut(out, count) }.copy_from_slice(&lost[..count]);
    count
}
