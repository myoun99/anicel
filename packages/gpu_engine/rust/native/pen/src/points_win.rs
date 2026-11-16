//! Windows' reader of the points the OS saw (points.rs): the Flutter view's
//! window, subclassed, so its messages come here first — on the thread
//! that owns the window, before the embedder's own handler reads them.
//!
//! A pen's or a finger's `WM_POINTER…` carries one point, and the ones
//! Windows merged into it are its history (`GetPointerInfoHistory`, the
//! newest first, each with its own `PerformanceCount`), which the embedder
//! never asks (flutter_window.cc: `GetPointerInfo` alone). A mouse's
//! `WM_MOUSEMOVE` the same: the moves before it are `GetMouseMovePointsEx`'s,
//! at most 64, each with its own time in milliseconds.
//!
//! Each batch is handed where the embedder hands Flutter the message's
//! point: the message's screen pixels put in the view (`ScreenToClient`)
//! for a pointer, the message's own client pixels for the mouse.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, PoisonError};

use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, POINT, WPARAM};
use windows::Win32::Graphics::Gdi::{ClientToScreen, ScreenToClient};
use windows::Win32::System::Performance::{QueryPerformanceCounter, QueryPerformanceFrequency};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    GMMP_USE_DISPLAY_POINTS, GetMouseMovePointsEx, MOUSEMOVEPOINT,
};
use windows::Win32::UI::Input::Pointer::{
    GetPointerInfo, GetPointerInfoHistory, GetPointerPenInfoHistory, POINTER_INFO,
    POINTER_PEN_INFO,
};
use windows::Win32::UI::Shell::{DefSubclassProc, RemoveWindowSubclass, SetWindowSubclass};
use windows::Win32::UI::WindowsAndMessaging::{
    FindWindowExW, GetMessageExtraInfo, GetMessageTime, PT_PEN, WM_MOUSEMOVE, WM_NCDESTROY,
    WM_POINTERDOWN, WM_POINTERUP, WM_POINTERUPDATE,
};
use windows::core::w;

use crate::points::{Batch, MOST_POINTS, Point, book};

/// The mouse's name among the contacts: past every pointer id, which is
/// a word.
const MOUSE: u64 = u64::MAX;

/// This reader's name among the view's subclasses.
const SUBCLASS: usize = 0x5155_5054; // "QUPT"

/// A pen's pressure, as `POINTER_PEN_INFO` gives it, at its most.
const MOST_PRESSURE: f64 = 1024.0;

/// `POINTER_PEN_INFO.penMask`'s word that the pressure is given.
const PEN_MASK_PRESSURE: u32 = 0x1;

/// What `GetMessageExtraInfo` says of a mouse message Windows made of a
/// pen's or a finger's — which the embedder leaves to the pointer's own
/// (flutter_window.cc's `GetFlutterPointerDeviceKind`), and so does this.
const PEN_OR_TOUCH: isize = 0xFF51_5700;
const SIGNATURE: isize = 0xFFFF_FF00;

static STARTED: AtomicBool = AtomicBool::new(false);

/// A mouse move as `GetMouseMovePointsEx` keeps it: where, in screen
/// pixels, and when, on the message clock (milliseconds, which wraps).
pub(crate) type Move = (i32, i32, u32);

/// The mouse's newest move written — where the next move's history stops.
static MOUSE_WRITTEN: Mutex<Option<Move>> = Mutex::new(None);

/// Subclasses the Flutter view of the app's window: true from then on.
/// False where there is no window shown yet, or this is not the thread
/// that owns it (the embedder runs Dart there — its platform and UI
/// threads are one by default since Flutter 3.32, and the Runner keeps the
/// default).
pub(crate) fn start() -> bool {
    if STARTED.load(Ordering::Acquire) {
        return true;
    }
    let Some(window) = display::app_window() else {
        return false;
    };
    // SAFETY: the app's window, asked for its child of Flutter's class.
    let Ok(view) = (unsafe { FindWindowExW(Some(window), None, w!("FLUTTERVIEW"), None) }) else {
        return false;
    };
    // SAFETY: the view lives till WM_NCDESTROY, where the subclass goes.
    let installed = unsafe { SetWindowSubclass(view, Some(heard), SUBCLASS, 0) }.as_bool();
    STARTED.store(installed, Ordering::Release);
    installed
}

unsafe extern "system" fn heard(
    view: HWND,
    message: u32,
    w: WPARAM,
    l: LPARAM,
    _: usize,
    _: usize,
) -> LRESULT {
    match message {
        WM_POINTERDOWN | WM_POINTERUPDATE | WM_POINTERUP => pointer(view, w, l),
        // SAFETY: asked while the message is handled, as the doc requires.
        WM_MOUSEMOVE if unsafe { GetMessageExtraInfo() }.0 & SIGNATURE != PEN_OR_TOUCH => {
            mouse(view, l)
        }
        WM_NCDESTROY => {
            // SAFETY: this subclass, on the window it was set on.
            let _ = unsafe { RemoveWindowSubclass(view, Some(heard), SUBCLASS) };
            STARTED.store(false, Ordering::Release);
        }
        _ => {}
    }
    // SAFETY: the message as it came, on to the embedder's handler.
    unsafe { DefSubclassProc(view, message, w, l) }
}

/// The message's own point, as `l` carries it: signed words.
fn of(l: LPARAM) -> POINT {
    POINT { x: i32::from(l.0 as u16 as i16), y: i32::from((l.0 >> 16) as u16 as i16) }
}

/// `screen` put in `view`.
fn in_view(view: HWND, screen: POINT) -> POINT {
    let mut client = screen;
    // SAFETY: a window this subclass is on, and a local.
    let _ = unsafe { ScreenToClient(view, &mut client) };
    client
}

/// Now, in the microseconds of the clock the embedder stamps its pointer
/// data by: `std::chrono::high_resolution_clock`, which MSVC reads off the
/// performance counter (flutter_windows_view.cc).
fn now_micros() -> i64 {
    let mut count = 0;
    // SAFETY: a local to write.
    let _ = unsafe { QueryPerformanceCounter(&mut count) };
    micros_of(count as u64)
}

/// A performance count in microseconds.
fn micros_of(count: u64) -> i64 {
    let mut frequency = 0;
    // SAFETY: a local to write.
    let _ = unsafe { QueryPerformanceFrequency(&mut frequency) };
    (count as i128 * 1_000_000 / i128::from(frequency.max(1))) as i64
}

/// A pointer message's points: its history, the oldest first, each with
/// the pen's readings where it is a pen.
fn pointer(view: HWND, w: WPARAM, l: LPARAM) {
    let id = (w.0 & 0xFFFF) as u32;
    let mut info = POINTER_INFO::default();
    // SAFETY: the message's pointer, asked while the message is handled.
    if unsafe { GetPointerInfo(id, &mut info) }.is_err() {
        return;
    }
    let mut count = info.historyCount.clamp(1, MOST_POINTS as u32);
    let mut history = vec![POINTER_INFO::default(); count as usize];
    // SAFETY: room for `count` entries.
    if unsafe { GetPointerInfoHistory(id, &mut count, Some(history.as_mut_ptr())) }.is_err() {
        history = vec![info];
        count = 1;
    }
    history.truncate(count as usize);
    let mut pens = vec![POINTER_PEN_INFO::default(); history.len()];
    let mut pen_count = history.len() as u32;
    let pen = info.pointerType == PT_PEN
        // SAFETY: room for `pen_count` entries.
        && unsafe { GetPointerPenInfoHistory(id, &mut pen_count, Some(pens.as_mut_ptr())) }.is_ok()
        && pen_count as usize == history.len();
    let now = now_micros();
    let points = history
        .iter()
        .zip(&pens)
        .rev()
        .map(|(entry, reading)| {
            let at = in_view(view, entry.ptPixelLocation);
            let micros = if entry.PerformanceCount == 0 {
                now - since_message(entry.dwTime)
            } else {
                micros_of(entry.PerformanceCount)
            };
            let point = Point::at(f64::from(at.x), f64::from(at.y), micros);
            if pen { read(point, reading) } else { point }
        })
        .collect();
    let handed = in_view(view, of(l));
    let handed = (f64::from(handed.x), f64::from(handed.y));
    book().write(Batch { contact: u64::from(id), handed, points });
}

/// `point` with the pressure the pen's `reading` gives — the one reading
/// the embedder hands Flutter of a pen (its tilt it drops, and the app
/// reads the lean off the pen's HID report: raw.rs).
fn read(mut point: Point, reading: &POINTER_PEN_INFO) -> Point {
    if reading.penMask & PEN_MASK_PRESSURE != 0 {
        point.pressure = f64::from(reading.pressure) / MOST_PRESSURE;
    }
    point
}

/// How long before the message being handled a message's `time` was, in
/// microseconds — both on the message clock, which wraps.
fn since_message(time: u32) -> i64 {
    // SAFETY: asked while the message is handled.
    let handled = unsafe { GetMessageTime() } as u32;
    i64::from(handled.wrapping_sub(time)) * 1000
}

/// A mouse move's points: the moves since the newest written, the oldest
/// first, each timed back from now by its milliseconds.
fn mouse(view: HWND, l: LPARAM) {
    let client = of(l);
    let mut screen = client;
    // SAFETY: a window this subclass is on, and a local.
    let _ = unsafe { ClientToScreen(view, &mut screen) };
    // SAFETY: asked while the message is handled.
    let time = unsafe { GetMessageTime() } as u32;
    let asked = MOUSEMOVEPOINT { x: screen.x & 0xFFFF, y: screen.y & 0xFFFF, time, dwExtraInfo: 0 };
    let mut moves = [MOUSEMOVEPOINT::default(); 64];
    let size = size_of::<MOUSEMOVEPOINT>() as u32;
    // SAFETY: the move asked and a buffer of 64.
    let found = unsafe { GetMouseMovePointsEx(size, &asked, &mut moves, GMMP_USE_DISPLAY_POINTS) };
    let mut written = MOUSE_WRITTEN.lock().unwrap_or_else(PoisonError::into_inner);
    let now = now_micros();
    let history: Vec<Move> = moves[..found.max(0) as usize]
        .iter()
        .map(|at| (signed(at.x), signed(at.y), at.time))
        .collect();
    let moves = moves_since((screen.x, screen.y, time), &history, *written);
    *written = Some((screen.x, screen.y, time));
    let points = moves
        .iter()
        .rev()
        .map(|&(x, y, at_time)| {
            let at = in_view(view, POINT { x, y });
            let micros = now - i64::from(time.wrapping_sub(at_time)) * 1000;
            Point::at(f64::from(at.x), f64::from(at.y), micros)
        })
        .collect();
    let handed = (f64::from(client.x), f64::from(client.y));
    book().write(Batch { contact: MOUSE, handed, points });
}

/// 🚨THE MOVES A MOUSE MESSAGE HANDS ON (I-110 · F-600): `history` — the
/// newest first, the message's `own` move the first of it — down to the
/// move `written` last, and none older than it. `own` alone where nothing
/// was written yet, where the mouse stood, or where the history keeps none.
///
/// ↩️Cut at the move written alone (H56), a history that does not keep it
/// — a move Windows makes as the window under the cursor changes or a
/// key goes, and the first move of all — went by whole: 64 moves with no
/// bound in time. 🔬Surface Pro 11, a lasso drawn with a mouse and held
/// with Alt or Shift: its shape reached two points off the canvas where
/// the cursor had rested seconds before, and the lasso's fill painted
/// them (캔버스 베이스, 11-16). A stroke takes its points the same way.
///
/// A move of the millisecond `written` was in is newer where it comes
/// before it: a mouse that reports faster than that keeps several there.
pub(crate) fn moves_since(own: Move, history: &[Move], written: Option<Move>) -> Vec<Move> {
    let newer = |at: &&Move| {
        written.is_some_and(|last| **at != last && at.2.wrapping_sub(last.2) as i32 >= 0)
    };
    let moves: Vec<Move> = history.iter().take_while(newer).copied().collect();
    if moves.is_empty() { vec![own] } else { moves }
}

/// A display point `GetMouseMovePointsEx` gives, as the screen's signed
/// coordinate: a screen left of or above the main one wraps past 32767.
fn signed(word: i32) -> i32 {
    if word > 32767 { word - 65536 } else { word }
}
