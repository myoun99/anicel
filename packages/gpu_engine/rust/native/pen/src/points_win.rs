//! Windows' reader of the points the OS saw (points.rs): the Flutter view's
//! window, subclassed, so its messages come here first — on the thread
//! that owns the window, before the embedder's own handler reads them.
//!
//! A pen's or a finger's `WM_POINTER…` carries one point, and the ones
//! Windows merged into it are its history (`GetPointerInfoHistory`, the
//! newest first, each with its own `PerformanceCount`), which the embedder
//! never asks (flutter_window.cc: `GetPointerInfo` alone). A mouse's
//! `WM_MOUSEMOVE` the same: the moves before it are `GetMouseMovePointsEx`'s,
//! at most 64, each with its own time in milliseconds — and every one while
//! a button is down, kept off the UI's thread (mouse_kept.rs).
//!
//! Each batch is handed where the embedder hands Flutter the message's
//! point: the message's screen pixels put in the view (`ScreenToClient`)
//! for a pointer, the message's own client pixels for the mouse. A pen's
//! points and a mouse's take the tablet driver's reading of the packet at
//! each one's own place — its pressure, lean and twist — where a Wintab
//! context is open, by one law ([`wintab::readings_at`]).

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
    FindWindowExW, GetMessageExtraInfo, GetMessageTime, PT_PEN, WM_LBUTTONDBLCLK, WM_LBUTTONDOWN,
    WM_MBUTTONDBLCLK, WM_MBUTTONDOWN, WM_MOUSEMOVE, WM_NCDESTROY, WM_POINTERDOWN, WM_POINTERUP,
    WM_POINTERUPDATE, WM_RBUTTONDBLCLK, WM_RBUTTONDOWN, WM_XBUTTONDBLCLK, WM_XBUTTONDOWN,
};
use windows::core::w;

use crate::mouse_kept::{self, Told};
use crate::points::{Batch, Kind, Lost, Point, book};
use crate::wintab;

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

/// The messages that press: a pen's or a finger's, and each of the mouse's
/// buttons — a double click's second press with them.
const PRESSES: [u32; 9] = [
    WM_POINTERDOWN,
    WM_LBUTTONDOWN,
    WM_LBUTTONDBLCLK,
    WM_RBUTTONDOWN,
    WM_RBUTTONDBLCLK,
    WM_MBUTTONDOWN,
    WM_MBUTTONDBLCLK,
    WM_XBUTTONDOWN,
    WM_XBUTTONDBLCLK,
];

/// How many moves `GetMouseMovePointsEx` keeps, the most it hands.
const MOUSE_HISTORY: i32 = 64;

/// A mouse move as `GetMouseMovePointsEx` keeps it: where, in screen
/// pixels, and when, on the message clock (milliseconds, which wraps).
pub(crate) type Move = (i32, i32, u32);

/// The mouse's newest move written — where the next move's history stops.
static MOUSE_WRITTEN: Mutex<Option<Move>> = Mutex::new(None);

/// Nothing written yet, as before the first mouse message of all — for a
/// test, whatever the tests before it in the process wrote.
#[cfg(test)]
pub(crate) fn forget_written() {
    *MOUSE_WRITTEN.lock().unwrap_or_else(PoisonError::into_inner) = None;
}

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
    hear(view, message, w, l);
    // SAFETY: the message as it came, on to the embedder's handler.
    unsafe { DefSubclassProc(view, message, w, l) }
}

/// What the view's `message` writes in the book — the tablet driver's
/// queue drained first where it presses ([`wintab::drain`]).
pub(crate) fn hear(view: HWND, message: u32, w: WPARAM, l: LPARAM) {
    if PRESSES.contains(&message) {
        wintab::drain();
    }
    // SAFETY: asked while the message is handled, as the doc requires.
    let pen = unsafe { GetMessageExtraInfo() }.0 & SIGNATURE == PEN_OR_TOUCH;
    match mouse_kept::keeping_after(message, w, pen) {
        Some(true) => mouse_kept::press(message_move(view, l)),
        Some(false) => mouse_kept::release(),
        None => {}
    }
    match message {
        WM_POINTERDOWN | WM_POINTERUPDATE | WM_POINTERUP => pointer(view, w, l),
        WM_MOUSEMOVE if !pen => mouse(view, l),
        WM_NCDESTROY => {
            // SAFETY: this subclass, on the window it was set on.
            let _ = unsafe { RemoveWindowSubclass(view, Some(heard), SUBCLASS) };
            STARTED.store(false, Ordering::Release);
        }
        _ => {}
    }
}

/// The message's own point, as `l` carries it: signed words.
fn of(l: LPARAM) -> POINT {
    POINT { x: i32::from(l.0 as u16 as i16), y: i32::from((l.0 >> 16) as u16 as i16) }
}

/// The move a mouse message at `l` stands for: its point on the screen, at
/// its millisecond.
fn message_move(view: HWND, l: LPARAM) -> Move {
    let mut screen = of(l);
    // SAFETY: a window this subclass is on, and a local.
    let _ = unsafe { ClientToScreen(view, &mut screen) };
    // SAFETY: asked while the message is handled.
    let time = unsafe { GetMessageTime() } as u32;
    (screen.x, screen.y, time)
}

/// The history Windows keeps of the mouse's move `at` — asked a pixel round
/// it where it is not found at its own ([`history_near`]) —, the newest
/// first, and how many it found, or its refusal. The system's, asked from
/// any thread (mouse_kept.rs).
pub(crate) fn mouse_history(at: Move) -> (Vec<Move>, i32) {
    let mut moves = [MOUSEMOVEPOINT::default(); MOUSE_HISTORY as usize];
    let size = size_of::<MOUSEMOVEPOINT>() as u32;
    let found = history_near(at, |(x, y, time)| {
        let asked = MOUSEMOVEPOINT { x: x & 0xFFFF, y: y & 0xFFFF, time, dwExtraInfo: 0 };
        // SAFETY: the move asked and a buffer of 64.
        unsafe { GetMouseMovePointsEx(size, &asked, &mut moves, GMMP_USE_DISPLAY_POINTS) }
    });
    let history = moves[..found.max(0) as usize].iter().map(|at| (signed(at.x), signed(at.y), at.time));
    (history.collect(), found)
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
pub(crate) fn now_micros() -> i64 {
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

/// A pointer message's points: its history, the oldest first
/// ([`points_of`]).
fn pointer(view: HWND, w: WPARAM, l: LPARAM) {
    let id = (w.0 & 0xFFFF) as u32;
    let mut info = POINTER_INFO::default();
    // SAFETY: the message's pointer, asked while the message is handled.
    if unsafe { GetPointerInfo(id, &mut info) }.is_err() {
        return;
    }
    // All the OS keeps: the book cuts a batch, and counts it (`Book::write`).
    let mut count = info.historyCount.max(1);
    let mut history = vec![POINTER_INFO::default(); count as usize];
    let mut unread = false;
    // SAFETY: room for `count` entries.
    if unsafe { GetPointerInfoHistory(id, &mut count, Some(history.as_mut_ptr())) }.is_err() {
        unread = info.historyCount > 1;
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
    let points = points_of(view, &history, pen.then_some(pens.as_slice()));
    let handed = in_view(view, of(l));
    let handed = (f64::from(handed.x), f64::from(handed.y));
    let mut book = book();
    if unread {
        book.lose(Lost::Unread);
    }
    let kind = Kind::of_windows_pointer(info.pointerType.0);
    book.write(Batch { contact: u64::from(id), kind, handed, points });
}

/// A pointer message's `history`, the newest first, as its points, the
/// oldest first: each with the pen's `readings` where it is a pen that gave
/// them, and each a pen's with the tablet driver's reading of the packet at
/// its own place where a Wintab context is open ([`wintab::readings_at`])
/// — as a mouse's are ([`mouse`]).
///
/// 🚨PAIRED AT ITS OWN POINT, AS A MOUSE'S IS (H61, 2026-11-18): a pen the OS
/// reads (Windows Ink on) took the pressure of the driver's NEWEST packet as
/// the app read each of its points, and so did every point of a message the
/// busy thread merged — the stroke's pressure went in steps.
/// ⛔Not a finger's: the driver's packets are the pen's.
pub(crate) fn points_of(view: HWND, history: &[POINTER_INFO], readings: Option<&[POINTER_PEN_INFO]>) -> Vec<Point> {
    let now = now_micros();
    let moves: Vec<Move> = history
        .iter()
        .filter(|entry| entry.pointerType == PT_PEN)
        .map(|entry| (entry.ptPixelLocation.x, entry.ptPixelLocation.y, entry.dwTime))
        .collect();
    // SAFETY: asked while the message is handled.
    let driven = wintab::readings_at(unsafe { GetMessageTime() } as u32, &moves);
    // The pen's, the oldest first, as the points are made.
    let mut pens = driven.into_iter().zip(moves).rev();
    history
        .iter()
        .enumerate()
        .rev()
        .map(|(at, entry)| {
            let place = in_view(view, entry.ptPixelLocation);
            let micros = if entry.PerformanceCount == 0 {
                now - since_message(entry.dwTime)
            } else {
                micros_of(entry.PerformanceCount)
            };
            let point = Point::at(f64::from(place.x), f64::from(place.y), micros);
            let point = readings.map_or(point, |readings| read(point, &readings[at]));
            match (entry.pointerType == PT_PEN).then(|| pens.next()).flatten() {
                Some((driven, asked)) => Point { driven, asked: Some(asked), ..point },
                None => point,
            }
        })
        .collect()
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

/// A mouse move's points: the moves since the newest written — taken from
/// what was kept off the UI's thread while a button is down, else from the
/// OS's 64 (mouse_kept.rs `history_of`) —, the oldest first, each at the
/// time it was heard where it was kept, else timed back from now by its
/// milliseconds — and each with the tablet driver's reading of the packet
/// at its place where a Wintab context is open ([`wintab::readings_at`]).
///
/// 🚨PAIRED HERE, AT THE MOVE'S OWN POINT: a pen the OS hands over as a
/// mouse (Windows Ink off) carries no pressure, and the driver's packet the
/// app read at the event was the NEWEST — after a stall, one taken long
/// after the move (pen-points-are-taken-off-the-ui-thread).
/// ↩️Paired by the move's own milliseconds till H61 (11-18): the message
/// clock steps 15.6 ms, and a step's moves took one packet
/// ([`wintab::Heard::at`]).
pub(crate) fn mouse(view: HWND, l: LPARAM) {
    let client = of(l);
    let own = message_move(view, l);
    let time = own.2;
    let (history, heard, found) = match mouse_kept::history_of(own) {
        Told::Kept(taken) => {
            let (history, heard): (Vec<Move>, Vec<i64>) = taken.into_iter().unzip();
            (history, heard, None)
        }
        Told::Read(history, found) => (history, Vec::new(), Some(found)),
    };
    let mut written = MOUSE_WRITTEN.lock().unwrap_or_else(PoisonError::into_inner);
    // What it lost is the history's, counted before the moves it hands on
    // are cut from it (`mouse_lost`).
    let lost = found.and_then(|found| mouse_lost(&history, found, *written));
    let now = now_micros();
    let moves = handed_on(own, &history, found, *written);
    *written = Some(own);
    // A move kept is at the time it was heard (mouse_kept.rs `Kept::hear`);
    // one read here is timed back from now by its milliseconds.
    let micros = |nth: usize, at_time: u32| match heard.get(nth) {
        Some(&heard) => heard,
        None => now - i64::from(time.wrapping_sub(at_time)) * 1000,
    };
    let readings = wintab::readings_at(time, &moves);
    let points = moves
        .iter()
        .zip(readings)
        .enumerate()
        .rev()
        .map(|(nth, (&(x, y, at_time), driven))| {
            let at = in_view(view, POINT { x, y });
            Point {
                driven,
                asked: Some((x, y, at_time)),
                ..Point::at(f64::from(at.x), f64::from(at.y), micros(nth, at_time))
            }
        })
        .collect();
    let handed = (f64::from(client.x), f64::from(client.y));
    let mut book = book();
    if let Some(why) = lost {
        book.lose(why);
    }
    book.write(Batch { contact: MOUSE, kind: Kind::Mouse, handed, points });
}

/// What a mouse message lost before the book ([`Lost`]): its `history` —
/// the `found` moves `GetMouseMovePointsEx` handed back from the one asked,
/// or its refusal — after `written`. The history ran past the move written
/// where every move found is newer than it: the moves between went, or
/// none was read. Nothing where nothing was written yet: the first move of
/// all has nothing before it to lose.
///
/// 🚨EVERY MOVE FOUND NEWER, HOWEVER MANY WERE FOUND (11-19, 관제 —
/// card pen-points-are-taken-off-the-ui-thread): the OS hands back the
/// moves from the one asked to the oldest it keeps, so fewer than its 64
/// are found where moves came after the one asked — not where it keeps
/// fewer. 🔬Surface Pro 11, 7 kHz: 67–73% of the reads at the cursor
/// found 62–63, and a read 218 ms after the one before found 63, every
/// one newer — some 1,800 moves gone, none counted.
/// ↩️Counted at 64 found alone till then (be2ef07bb, 11-17 — the history
/// taken to keep fewer only till it fills), off the moves a message hands
/// on. Counted off the history now: those are the message's own move alone
/// where none is newer, and one found would be one handed on.
pub(crate) fn mouse_lost(history: &[Move], found: i32, written: Option<Move>) -> Option<Lost> {
    written?;
    match found {
        ..0 => Some(Lost::Unread),
        _ if !history.is_empty() && newer_than(history, written).len() == history.len() => Some(Lost::Full),
        _ => None,
    }
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
/// The move written is met where it is [`told_alike`].
pub(crate) fn moves_since(own: Move, history: &[Move], written: Option<Move>) -> Vec<Move> {
    let moves = newer_than(history, written);
    if moves.is_empty() { vec![own] } else { moves.to_vec() }
}

/// The moves a mouse message hands on: its `history` cut as
/// [`moves_since`] cuts it — `found` moves read of the OS's — or, `found`
/// None, the moves it took of what was kept since the press
/// (mouse_kept.rs `Kept::take_through`), the newest first and its `own`
/// move the first of them, cut the same, and every one where nothing was
/// written yet: kept from the press on, they go back no further than it,
/// where a history read goes back its 64 moves with no bound in time.
///
/// 🔬Surface Pro 11, 11-19: cut as a history, the first message of all
/// handed on its own move alone and the moves kept before it went — 3 test
/// runs in 60 at release, where the kept-moves test was the first to write
/// a mouse message. ⚠️Not seen in the app: the reader starts at the first
/// datum Flutter hears, and its first message is a drag's only where no
/// hover came between.
pub(crate) fn handed_on(own: Move, history: &[Move], found: Option<i32>, written: Option<Move>) -> Vec<Move> {
    match (found, written) {
        (None, None) => history.to_vec(),
        _ => moves_since(own, history, written),
    }
}

/// The moves of `history` — the newest first — newer than `last`: down to
/// it, and none older; none where nothing is `last`. What a message hands
/// on past the move written ([`moves_since`]), and what is kept past the
/// move kept last (mouse_kept.rs `Kept::hear`).
pub(crate) fn newer_than(history: &[Move], last: Option<Move>) -> &[Move] {
    let newer = |at: &&Move| {
        last.is_some_and(|last| !told_alike(**at, last) && at.2.wrapping_sub(last.2) as i32 >= 0)
    };
    &history[..history.iter().take_while(newer).count()]
}

/// 🚨ONE MOVE, TOLD TWICE, IS ONE MOVE (H61, 2026-11-18): a pen the OS hands
/// over as a mouse (Windows Ink off) moves the cursor to a place finer than
/// a pixel, and the message's point and the history's are each that place
/// rounded its own way — the same move, a pixel apart. Met as two moves, a
/// history was cut at no move written: every move of the written one's
/// millisecond went on again, and the stroke went back over its last 15 ms
/// and drew it twice (유저 「정기적으로 일정구간에서 스트로크가 2개
/// 겹쳐지는거같은데」). And the history asked at the message's own point was
/// not found at all where the two rounded apart.
///
/// 🔬Main PC, a pen as a mouse, one stroke of 602 messages (k-h61, 11-18):
/// the history found 185 times, the move written in it at 0 px 79 times and
/// at 1 px 106 — never farther; 417 not found. The stroke drawn: 95 of its
/// 406 points went back over a point drawn already.
///
/// Two moves are told alike where they are of one millisecond and
/// [`a_pixel_apart`].
pub(crate) fn told_alike(a: Move, b: Move) -> bool {
    a.2 == b.2 && a_pixel_apart((a.0, a.1), (b.0, b.1))
}

/// Whether two places are one as two tellers round a pen's place: a pixel
/// apart at most on each axis — the places [`around`] gives. The history and
/// the message tell a move so ([`told_alike`]), and the driver's packet and
/// the cursor it put there (`wintab::Heard::at`).
pub(crate) fn a_pixel_apart((x, y): (i32, i32), b: (i32, i32)) -> bool {
    around((x, y, 0)).any(|(near_x, near_y, _)| (near_x, near_y) == b)
}

/// `at`'s place and the places a pixel from it, at its millisecond — its
/// own first.
fn around((x, y, time): Move) -> impl Iterator<Item = Move> {
    const STEPS: [i32; 3] = [0, 1, -1];
    STEPS.into_iter().flat_map(move |dy| STEPS.into_iter().map(move |dx| (x + dx, y + dy, time)))
}

/// The history `ask` keeps of `own`, asked at each place [`around`] it till
/// one is found: how many moves it handed, or its refusal of the last.
pub(crate) fn history_near(own: Move, mut ask: impl FnMut(Move) -> i32) -> i32 {
    let mut found = -1;
    for place in around(own) {
        found = ask(place);
        if found > 0 {
            break;
        }
    }
    found
}

/// A display point `GetMouseMovePointsEx` gives, as the screen's signed
/// coordinate: a screen left of or above the main one wraps past 32767.
fn signed(word: i32) -> i32 {
    if word > 32767 { word - 65536 } else { word }
}
