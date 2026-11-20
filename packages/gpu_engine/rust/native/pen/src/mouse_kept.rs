//! 🚨THE MOUSE'S HISTORY, KEPT OFF THE UI'S THREAD WHILE A BUTTON IS DOWN
//! (pen-points-are-taken-off-the-ui-thread, 2026-11-18). Windows keeps the
//! mouse's last 64 moves (`GetMouseMovePointsEx`), and the reader read them
//! as the UI's thread handled a move (points_win.rs `mouse`): a UI that
//! stood longer than 64 moves — 64 ms of a 1 kHz mouse — lost the moves
//! before them, and a stroke joined what was left with a long straight line
//! (H59, the input inspector's `lost=full`).
//!
//! The history is the system's, not a thread's or a window's: 🔬Surface Pro
//! 11, a process with no window at all read the cursor's 64 (11-18). So the
//! receiver ([`crate::receiver`]) reads it every [`KEEP_EVERY`] while a
//! mouse button is down in the view, and sends each read ([`SENT`]); the
//! UI's thread keeps every move they hold past the one it kept last, in
//! the order they were made ([`Kept::hear`]), takes a message's moves from
//! what was kept ([`Kept::take_through`]), and reads the OS's 64 as it did
//! where the message's own move was not kept.
//!
//! ⛔NO HOOK (H59-Q1, 유저 2026-11-15 「훅을 쓰지 않는다」 — an antivirus may
//! take a global mouse hook for a spy's): nothing is caught or registered;
//! the history is only read. ⛔Not Raw Input's mouse: its moves are the
//! device's counts before the cursor's acceleration, not where the cursor
//! went (H59 법 A).

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{LazyLock, Mutex, MutexGuard, PoisonError};
use std::time::Duration;

use windows::Win32::Foundation::{POINT, WPARAM};
use windows::Win32::UI::WindowsAndMessaging::{
    GetCursorPos, WM_CAPTURECHANGED, WM_LBUTTONDBLCLK, WM_LBUTTONDOWN, WM_LBUTTONUP,
    WM_MBUTTONDBLCLK, WM_MBUTTONDOWN, WM_MBUTTONUP, WM_RBUTTONDBLCLK, WM_RBUTTONDOWN,
    WM_RBUTTONUP, WM_XBUTTONDBLCLK, WM_XBUTTONDOWN, WM_XBUTTONUP,
};

use crate::points::{Lost, book};
use crate::points_win::{Move, mouse_history, mouse_lost, newer_than, now_micros, told_alike};
use crate::receiver::{self, Work};

/// How often the history is read while a button is down: well inside the
/// 64 moves Windows keeps — 64 ms of a 1 kHz mouse, 8 ms of an 8 kHz one —,
/// on the receiver's own high-resolution timer ([`crate::receiver`]).
pub(crate) const KEEP_EVERY: Duration = Duration::from_millis(4);

/// What was kept since a button went down: the moves past the press no
/// message has taken yet, the oldest first, each with when it was heard
/// ([`Kept::hear`]); the newest move read — where the next read goes on
/// from —; and when the history was last read, on the clock the points are
/// stamped by.
#[derive(Debug, PartialEq)]
pub(crate) struct Kept {
    pub(crate) moves: VecDeque<(Move, i64)>,
    pub(crate) newest: Move,
    pub(crate) read_at: i64,
}

impl Kept {
    /// What is kept from a press at `at`, made at `pressed_at`: nothing yet.
    pub(crate) fn from(at: Move, pressed_at: i64) -> Self {
        Self { moves: VecDeque::new(), newest: at, read_at: pressed_at }
    }

    /// Keeps the moves `history` — the newest first, its read having
    /// `found` at `read_at` — holds past the newest kept, each timed where
    /// it falls among them, evenly, since the read before. What was lost:
    /// where the history was full and every move of it newer, the moves
    /// before it went. ⛔Not a read refused: the next is a moment away, and
    /// the message's own read is still there — and it says nothing of when
    /// what it did not hear was made.
    ///
    /// 🚨EACH MOVE AT A TIME OF ITS OWN (pen-points-are-taken-off-the-ui-thread,
    /// 2026-11-19 — 🤖AI 검증 실패 of ②): the history times a move by the
    /// system's clock, which steps 15.6 ms (🔬Surface Pro 11: 58 of 63 steps
    /// between the 64 moves 0 ms), and the moves a stood UI's message
    /// handed on were each timed back from it by that clock — sixteen at a
    /// time on one time at 1 kHz. The steadied line closes on the pen only
    /// as the pen's time goes on (stroke_stabilizer.dart `_closeTo`), so it
    /// went to the first of each sixteen and straight on: 134 of 301 points
    /// of a stood circle more than 4 px off it — at times of their own, none
    /// (브러시 11-19: 「의도한 법이 아니라 모델의 귀결」 — a point's time is
    /// given where the point is heard, and it must go up through
    /// a stroke, spread evenly, and not past its read). A move read now and
    /// not before was made since the read before and by now: they are put
    /// there in order, the newest at now.
    ///
    /// ⛔A READ MADE BEFORE THE ONE HEARD LAST ADDS NOTHING
    /// (pen-receive-threads-are-one, 2026-11-19): the receiver's read and a
    /// message's own are sent as each is made ([`SENT`]), and one made
    /// first may be sent second; heard after the newer, the older's newest
    /// is not the newest kept, and every move of its 64 would be taken for
    /// new — kept twice, and counted lost.
    pub(crate) fn hear(&mut self, history: &[Move], found: i32, read_at: i64) -> Option<Lost> {
        if found < 0 || read_at < self.read_at {
            return None;
        }
        let newer = newer_than(history, Some(self.newest));
        let lost = mouse_lost(history, found, Some(self.newest)).filter(|why| *why == Lost::Full);
        let (since, count) = (read_at - self.read_at, newer.len() as i64);
        let heard = newer.iter().rev().zip(1..).map(|(&at, nth)| (at, self.read_at + since * nth / count));
        self.moves.extend(heard);
        if let Some(&newest) = newer.first() {
            self.newest = newest;
        }
        self.read_at = read_at;
        lost
    }

    /// The moves a message at `own` hands on — the newest first, `own` the
    /// first of them, each with when it was heard — taken out of what was
    /// kept, where `own` was kept; the moves after it wait for the messages
    /// that are theirs.
    pub(crate) fn take_through(&mut self, own: Move) -> Option<Vec<(Move, i64)>> {
        let at = self.moves.iter().position(|&(kept, _)| told_alike(kept, own))?;
        Some(self.moves.drain(..=at).rev().collect())
    }
}

/// The moves a mouse message hands on, the newest first, as they were told
/// it: taken from what was kept, each with when it was heard, or read off
/// the OS's 64 at the message, with how many that read found.
#[derive(Debug, PartialEq)]
pub(crate) enum Told {
    Kept(Vec<(Move, i64)>),
    Read(Vec<Move>, i32),
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

/// What a mouse message at `own` hands on ([`Told`]): the moves `kept`
/// took through `own`, else the OS's own read of it (`read`).
pub(crate) fn history_for(
    own: Move,
    kept: Option<&mut Kept>,
    read: impl FnOnce(Move) -> (Vec<Move>, i32),
) -> Told {
    match kept.and_then(|kept| kept.take_through(own)) {
        Some(taken) => Told::Kept(taken),
        None => {
            let (history, found) = read(own);
            Told::Read(history, found)
        }
    }
}

static KEPT: Mutex<Option<Kept>> = Mutex::new(None);

fn kept() -> MutexGuard<'static, Option<Kept>> {
    KEPT.lock().unwrap_or_else(PoisonError::into_inner)
}

/// Whether a button is down: what the receiver reads by, never waiting on
/// what is kept ([`keep_on_its_own`]).
static KEEPING: AtomicBool = AtomicBool::new(false);

/// A read of the history where the cursor was: the newest first, how many
/// the read found, and when it was made.
pub(crate) struct Read {
    history: Vec<Move>,
    found: i32,
    at: i64,
}

/// The reads made since the last were heard, in the order made — sent by
/// whoever made them, heard by whoever holds what is kept ([`hear_sent`]).
///
/// 🚨THE RECEIVER ONLY SENDS (pen-receive-threads-are-one, 2026-11-19):
/// it heard into what was kept itself, under the lock the UI's thread
/// takes a message's moves with — 🔬and stood 218 ms with a UI that stood
/// holding it (1 of 20 stalls). A send waits on nobody; the UI's thread,
/// which takes the moves, hears the reads before it does.
static SENT: LazyLock<(Sender<Read>, Mutex<Receiver<Read>>)> = LazyLock::new(|| {
    let (send, heard) = mpsc::channel();
    (send, Mutex::new(heard))
});

/// Hears into `kept` every read sent and not heard yet, in the order made —
/// their loss counted in the book —; with none kept, lets them go.
fn hear_sent(kept: &mut Option<Kept>) {
    let heard = SENT.1.lock().unwrap_or_else(PoisonError::into_inner);
    for read in heard.try_iter() {
        let lost = kept.as_mut().and_then(|kept| kept.hear(&read.history, read.found, read.at));
        if let Some(why) = lost {
            book().lose(why);
        }
    }
}

/// Starts keeping from a press at `at`: what was read before it let go of,
/// and the receiver reading from now on ([`Work::Keep`]).
pub(crate) fn press(at: Move) {
    let mut kept = kept();
    hear_sent(&mut None);
    *kept = Some(Kept::from(at, now_micros()));
    KEEPING.store(true, Ordering::SeqCst);
    drop(kept);
    receiver::now(Work::Keep, KEEP_EVERY);
}

/// Whether a button is down and its moves are kept.
#[cfg(test)]
pub(crate) fn keeping() -> bool {
    kept().is_some()
}

/// When the history was last read since the press — the press, till the
/// first read is heard; None while no button is down.
#[cfg(test)]
pub(crate) fn read_at() -> Option<i64> {
    kept().as_ref().map(|kept| kept.read_at)
}

/// Keeps `kept` as though read since a press, the receiver not reading.
#[cfg(test)]
pub(crate) fn keep_from(kept: Kept) {
    *self::kept() = Some(kept);
}

/// What is kept, held as the UI's thread holds it taking a message's moves
/// — for a test to stand on it.
#[cfg(test)]
pub(crate) fn hold() -> MutexGuard<'static, Option<Kept>> {
    kept()
}

/// Sends a read of `history` made `at`, as the receiver sends one — for a
/// test to hand the UI's thread what was read.
#[cfg(test)]
pub(crate) fn sent(history: Vec<Move>, found: i32, at: i64) {
    let _ = SENT.0.send(Read { history, found, at });
}

/// The receiver's reads so far, for a test to time its turns by.
#[cfg(test)]
pub(crate) static READS: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

/// Ends keeping: what was kept, and read since, let go of.
pub(crate) fn release() {
    let mut kept = kept();
    KEEPING.store(false, Ordering::SeqCst);
    *kept = None;
    hear_sent(&mut kept);
}

/// The receiver's turn ([`Work::Keep`]): the history read and sent while a
/// button is down — waiting on nothing. Whether one still is.
pub(crate) fn keep_on_its_own() -> bool {
    if !KEEPING.load(Ordering::SeqCst) {
        return false;
    }
    if let Some(read) = read() {
        let _ = SENT.0.send(read);
    }
    #[cfg(test)]
    READS.fetch_add(1, Ordering::Relaxed);
    true
}

/// The history where the cursor is now, read; None where the cursor's
/// place is not.
fn read() -> Option<Read> {
    let mut cursor = POINT::default();
    // SAFETY: a local to write.
    unsafe { GetCursorPos(&mut cursor) }.ok()?;
    // Of no millisecond: the newest move at the cursor's place.
    let (history, found) = mouse_history((cursor.x, cursor.y, 0));
    Some(Read { history, found, at: now_micros() })
}

/// The history a mouse message at `own` hands on ([`history_for`]): while
/// a button is down, read once more first for the moves up to `own`, and
/// every read sent heard before it.
pub(crate) fn history_of(own: Move) -> Told {
    let mut kept = kept();
    if kept.is_some()
        && let Some(read) = read()
    {
        let _ = SENT.0.send(read);
    }
    hear_sent(&mut kept);
    history_for(own, kept.as_mut(), mouse_history)
}
