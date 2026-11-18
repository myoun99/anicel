//! 🚨THE MOUSE'S HISTORY, KEPT OFF THE UI'S THREAD WHILE A BUTTON IS DOWN
//! (pen-points-are-taken-off-the-ui-thread, 2026-11-18). Windows keeps the
//! mouse's last 64 moves (`GetMouseMovePointsEx`), and the reader read them
//! as the UI's thread handled a move (points_win.rs `mouse`): a UI that
//! stood longer than 64 moves — 64 ms of a 1 kHz mouse — lost the moves
//! before them, and a stroke joined what was left with a long straight line
//! (H59, the input inspector's `lost=full`).
//!
//! The history is the system's, not a thread's or a window's: 🔬Surface Pro
//! 11, a process with no window at all read the cursor's 64 (11-18). So a
//! thread of its own reads it every [`KEEP_EVERY`] while a mouse button is
//! down in the view, and keeps every move past the one it kept last
//! ([`Kept::hear`]); the UI's thread takes a message's moves from what was
//! kept ([`Kept::take_through`]), and reads the OS's 64 as it did where
//! the message's own move was not kept.
//!
//! ⛔NO HOOK (H59-Q1, 유저 2026-11-15 「훅을 쓰지 않는다」 — an antivirus may
//! take a global mouse hook for a spy's): nothing is caught or registered;
//! the history is only read. ⛔Not Raw Input's mouse: its moves are the
//! device's counts before the cursor's acceleration, not where the cursor
//! went (H59 법 A).

use std::collections::VecDeque;
use std::sync::{Mutex, MutexGuard, PoisonError};
use std::thread::Thread;
use std::time::Duration;

use windows::Win32::Foundation::{POINT, WPARAM};
use windows::Win32::UI::WindowsAndMessaging::{
    GetCursorPos, WM_CAPTURECHANGED, WM_LBUTTONDBLCLK, WM_LBUTTONDOWN, WM_LBUTTONUP,
    WM_MBUTTONDBLCLK, WM_MBUTTONDOWN, WM_MBUTTONUP, WM_RBUTTONDBLCLK, WM_RBUTTONDOWN,
    WM_RBUTTONUP, WM_XBUTTONDBLCLK, WM_XBUTTONDOWN, WM_XBUTTONUP,
};

use crate::points::{Lost, book};
use crate::points_win::{Move, mouse_history, mouse_lost, newer_than, told_alike};

/// How often the history is read while a button is down: well inside the
/// 64 moves Windows keeps — 64 ms of a 1 kHz mouse, 8 ms of an 8 kHz one.
///
/// 🔬SLEPT, NOT PARKED (2026-11-19): `park_timeout` waits out the system's
/// clock tick — Surface Pro 11, 4 ms asked of it took 15.69 ms at the
/// median, past an 8 kHz mouse's 64 moves — where std's `sleep` waits on a
/// high-resolution timer: 4.51 ms.
pub(crate) const KEEP_EVERY: Duration = Duration::from_millis(4);

/// What was kept since a button went down: the moves past the press no
/// message has taken yet, the oldest first, and the newest move read —
/// where the next read goes on from.
#[derive(Debug, PartialEq)]
pub(crate) struct Kept {
    pub(crate) moves: VecDeque<Move>,
    pub(crate) newest: Move,
}

impl Kept {
    /// What is kept from a press at `at`: nothing yet.
    pub(crate) fn from(at: Move) -> Self {
        Self { moves: VecDeque::new(), newest: at }
    }

    /// Keeps the moves `history` — the newest first, its read having
    /// `found` — holds past the newest kept. What was lost: where the
    /// history was full and every move of it newer, the moves before it
    /// went. ⛔Not a read refused: the next is a moment away, and the
    /// message's own read is still there.
    pub(crate) fn hear(&mut self, history: &[Move], found: i32) -> Option<Lost> {
        let newer = newer_than(history, Some(self.newest));
        let lost = mouse_lost(found, newer.len(), Some(self.newest)).filter(|why| *why == Lost::Full);
        self.moves.extend(newer.iter().rev());
        if let Some(&newest) = newer.first() {
            self.newest = newest;
        }
        lost
    }

    /// The moves a message at `own` hands on — the newest first, `own` the
    /// first of them — taken out of what was kept, where `own` was kept;
    /// the moves after it wait for the messages that are theirs.
    pub(crate) fn take_through(&mut self, own: Move) -> Option<Vec<Move>> {
        let at = self.moves.iter().position(|&kept| told_alike(kept, own))?;
        Some(self.moves.drain(..=at).rev().collect())
    }
}

/// Whether `message` to the view starts keeping (true) or ends it (false)
/// — `w` its word, `pen` whether Windows made it of a pen's or a finger's
/// — or neither. A mouse button's press starts it; a button let go with
/// none left down, or the view losing the capture the embedder takes at a
/// press (flutter_window.cc `SetCapture`), ends it.
pub(crate) fn keeping_after(message: u32, w: WPARAM, pen: bool) -> Option<bool> {
    const BUTTONS: usize = 0x0001 | 0x0002 | 0x0010 | 0x0020 | 0x0040; // MK_L/R/M/X1/X2BUTTON
    match message {
        WM_LBUTTONDOWN | WM_LBUTTONDBLCLK | WM_RBUTTONDOWN | WM_RBUTTONDBLCLK | WM_MBUTTONDOWN
        | WM_MBUTTONDBLCLK | WM_XBUTTONDOWN | WM_XBUTTONDBLCLK => (!pen).then_some(true),
        WM_LBUTTONUP | WM_RBUTTONUP | WM_MBUTTONUP | WM_XBUTTONUP => (w.0 & BUTTONS == 0).then_some(false),
        WM_CAPTURECHANGED => Some(false),
        _ => None,
    }
}

/// The history a mouse message at `own` hands on, the newest first, and
/// what its read found where it was read here: the moves `kept` took
/// through `own`, else the OS's own read of it (`read`).
pub(crate) fn history_for(
    own: Move,
    kept: Option<&mut Kept>,
    read: impl FnOnce(Move) -> (Vec<Move>, i32),
) -> (Vec<Move>, Option<i32>) {
    match kept.and_then(|kept| kept.take_through(own)) {
        Some(taken) => (taken, None),
        None => {
            let (history, found) = read(own);
            (history, Some(found))
        }
    }
}

static KEPT: Mutex<Option<Kept>> = Mutex::new(None);

fn kept() -> MutexGuard<'static, Option<Kept>> {
    KEPT.lock().unwrap_or_else(PoisonError::into_inner)
}

/// The keeping thread, to wake: none till the first press.
static KEEPER: Mutex<Option<Thread>> = Mutex::new(None);

/// Starts keeping from a press at `at`, the thread made at the first.
pub(crate) fn press(at: Move) {
    *kept() = Some(Kept::from(at));
    let mut keeper = KEEPER.lock().unwrap_or_else(PoisonError::into_inner);
    if keeper.is_none() {
        let made = std::thread::Builder::new().name("mouse history".to_owned()).spawn(keep);
        *keeper = made.ok().map(|thread| thread.thread().clone());
    }
    if let Some(thread) = keeper.as_ref() {
        thread.unpark();
    }
}

/// Whether a button is down and its moves are kept.
#[cfg(test)]
pub(crate) fn keeping() -> bool {
    kept().is_some()
}

/// Keeps `kept` as though read since a press, the keeping thread left
/// asleep.
#[cfg(test)]
pub(crate) fn keep_from(kept: Kept) {
    *self::kept() = Some(kept);
}

/// The keeping thread's reads so far, for a test to time its turns by.
#[cfg(test)]
pub(crate) static READS: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

/// Ends keeping: what was kept let go of.
pub(crate) fn release() {
    *kept() = None;
}

/// The keeping thread: a read every [`KEEP_EVERY`] while a button is down —
/// slept, not parked, for the wait asked — asleep while none is.
fn keep() {
    loop {
        if kept().is_some() {
            read();
            #[cfg(test)]
            READS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            std::thread::sleep(KEEP_EVERY);
        } else {
            std::thread::park();
        }
    }
}

/// Reads the history where the cursor is now into what is kept — its loss
/// counted in the book — while a button is down.
fn read() {
    let mut cursor = POINT::default();
    // SAFETY: a local to write.
    if unsafe { GetCursorPos(&mut cursor) }.is_err() {
        return;
    }
    // Of no millisecond: the newest move at the cursor's place.
    let (history, found) = mouse_history((cursor.x, cursor.y, 0));
    let lost = kept().as_mut().and_then(|kept| kept.hear(&history, found));
    if let Some(why) = lost {
        book().lose(why);
    }
}

/// The history a mouse message at `own` hands on ([`history_for`]): read
/// once more first while a button is down, for the moves up to `own`.
pub(crate) fn history_of(own: Move) -> (Vec<Move>, Option<i32>) {
    if kept().is_some() {
        read();
    }
    history_for(own, kept().as_mut(), mouse_history)
}
