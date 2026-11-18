//! 🚨THE ONE THREAD THAT RECEIVES THE PEN AND THE MOUSE OFF THE UI'S
//! (pen-receive-threads-are-one, 2026-11-19). H59 법 A (11-15) had it as
//! one: 「받는 스레드는 하나(사본 금지)」 — and three grew, each of its own:
//! raw.rs's (a message-only window, WM_INPUT, while the app runs), the
//! Wintab drain's (every 4 ms while a context is open) and the mouse
//! history's (every 4 ms while a button is down). The last two are the
//! same thing — wake every so often while there is work, else sleep — and
//! the third of a family is the one that is joined (관제 03:0x, CLAUDE.md
//! 절대명령 1).
//!
//! WHO WAKES IT, AND WHEN — the law this module is (관제 02:0x, approved):
//! - the OS: a pen's HID report, as WM_INPUT to its window ([`crate::raw`]);
//! - its timer: a high-resolution waitable timer, armed only while a work
//!   that comes round every so often lasts — a Wintab context open
//!   ([`Work::Drain`]), a mouse button down ([`Work::Keep`]) — and at the
//!   soonest of them ([`Schedule::next`]). With none, no timer: it wakes for
//!   messages alone;
//! - the UI: one posted message ([`now`]) — a press to keep from, a move
//!   whose packet is not heard yet, a context opened — done as it is
//!   taken, waited on by nobody. What the UI must hear the answer of (Raw
//!   Input listened to or not) is sent ([`ask`]) and waited on.
//!
//! 🚨IT NEVER WAITS ON THE UI. What it shares with the UI's thread it takes
//! only where it is free (`try_lock`), and what it heard while the UI held
//! it waits on its own side for the next turn. 🔬11-19: the UI's thread
//! stood holding the mouse's kept moves, and the reader stood 218 ms with
//! it — 1 of 20 stalls (pen-points-are-taken-off-the-ui-thread).
//!
//! 🔬Why a timer of its own: in the app's process a 4 ms `park_timeout`
//! took 4.47 ms at the median — flutter_windows.dll raises the system's
//! timer resolution — and 15.69 ms in a process that does not (Surface Pro
//! 11, 11-19). The high-resolution timer keeps 4 ms whoever raises it.
//! ⛔Not WM_TIMER (the system's tick), not timeBeginPeriod (the whole
//! machine's clock), not a timer per work (the three again) — the design's
//! own rejections.

use std::cell::RefCell;
use std::ffi::c_void;
use std::sync::mpsc::{self, Sender};
use std::sync::{Mutex, MutexGuard, PoisonError, TryLockError};
use std::time::{Duration, Instant};

use windows::Win32::Foundation::{
    ERROR_CLASS_ALREADY_EXISTS, GetLastError, HANDLE, HWND, LPARAM, LRESULT, WPARAM,
};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::System::Threading::{
    CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, CancelWaitableTimer, CreateWaitableTimerExW, INFINITE,
    SetWaitableTimer, TIMER_ALL_ACCESS,
};
use windows::Win32::UI::Input::HRAWINPUT;
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DispatchMessageW, HWND_MESSAGE, MSG, MWMO_INPUTAVAILABLE,
    MsgWaitForMultipleObjectsEx, PM_REMOVE, PeekMessageW, PostMessageW, QS_ALLINPUT,
    RegisterClassW, SendMessageW, TranslateMessage, WM_APP, WM_INPUT, WNDCLASSW,
};
use windows::core::{PCWSTR, w};

/// A work the receiver does every so often while it lasts.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Work {
    /// The Wintab context's queue drained ([`crate::wintab`]).
    Drain = 0,
    /// The mouse's history read while a button is down ([`crate::mouse_kept`]).
    Keep = 1,
}

const WORKS: [Work; 2] = [Work::Drain, Work::Keep];

/// When each work comes round next, and how often — the receiver's alone.
#[derive(Debug, Default, PartialEq)]
pub(crate) struct Schedule {
    due: [Option<(Duration, Instant)>; WORKS.len()],
}

impl Schedule {
    /// `work`, done at `at`: due again `every` on while it `lasts`, and off
    /// the schedule where it does not.
    pub(crate) fn done(&mut self, work: Work, every: Duration, at: Instant, lasts: bool) {
        self.due[work as usize] = lasts.then_some((every, at + every));
    }

    /// The works due by `at`, each with how often it comes round.
    pub(crate) fn due_by(&self, at: Instant) -> Vec<(Work, Duration)> {
        let due = |work: Work| self.due[work as usize].filter(|&(_, due)| due <= at).map(|(every, _)| (work, every));
        WORKS.iter().filter_map(|&work| due(work)).collect()
    }

    /// When the timer is to wake the receiver: when the soonest work is
    /// due. None — no timer — while no work lasts.
    pub(crate) fn next(&self) -> Option<Instant> {
        self.due.iter().flatten().map(|&(_, due)| due).min()
    }
}

/// What `lock` guards, where it is free; None while another holds it —
/// the receiver never waits on the UI's thread for it (the module's head).
pub(crate) fn if_free<T>(lock: &Mutex<T>) -> Option<MutexGuard<'_, T>> {
    match lock.try_lock() {
        Ok(guard) => Some(guard),
        Err(TryLockError::Poisoned(poisoned)) => Some(poisoned.into_inner()),
        Err(TryLockError::WouldBlock) => None,
    }
}

/// Does `work` now, on the receiver's thread: whether it lasts.
fn run(work: Work) -> bool {
    match work {
        Work::Drain => crate::wintab::drain_on_its_own(),
        Work::Keep => crate::mouse_kept::keep_on_its_own(),
    }
}

/// Does `work` (its WPARAM) now — it was asked for ([`now`]) — and from
/// then every LPARAM microseconds while it lasts.
const WM_NOW: u32 = WM_APP + 1;
/// Listens to the pen's HID reports with the `Hid` its LPARAM points at, or
/// stops with none ([`crate::raw::listen`]): 1 where it listens.
pub(crate) const WM_LISTEN: u32 = WM_APP + 2;

thread_local! {
    /// The works' turns, on the receiver's thread alone.
    static SCHEDULE: RefCell<Schedule> = RefCell::new(Schedule::default());
}

/// The receiver's window, as a number a static can hold: unmade till the
/// first ask; made — or not, None — for good from then.
static WINDOW: Mutex<Option<Option<isize>>> = Mutex::new(None);

/// The receiver's window, its thread made at the first ask; None where it
/// could not be.
fn window() -> Option<HWND> {
    let mut window = WINDOW.lock().unwrap_or_else(PoisonError::into_inner);
    let made = *window.get_or_insert_with(|| {
        let (made, heard) = mpsc::channel();
        let thread = std::thread::Builder::new().name("pen receiver".to_owned()).spawn(move || receive(&made));
        // Making a window answers at once; two seconds is a generous ceiling.
        thread.ok().and_then(|_| heard.recv_timeout(Duration::from_secs(2)).ok().flatten())
    });
    made.map(|window| HWND(window as *mut c_void))
}

/// Has the receiver do `work` now, and every `every` from then while it
/// lasts — waiting on nothing.
pub(crate) fn now(work: Work, every: Duration) {
    if let Some(window) = window() {
        let micros = LPARAM(isize::try_from(every.as_micros()).unwrap_or(isize::MAX));
        // SAFETY: the receiver's window; a post lost is the next turn's.
        let _ = unsafe { PostMessageW(Some(window), WM_NOW, WPARAM(work as usize), micros) };
    }
}

/// Asks the receiver `message` and waits for its answer: 0 with no
/// receiver.
pub(crate) fn ask(message: u32, w: WPARAM, l: LPARAM) -> isize {
    match window() {
        // SAFETY: the receiver's window, answering on its own thread.
        Some(window) => unsafe { SendMessageW(window, message, Some(w), Some(l)) }.0,
        None => 0,
    }
}

/// The receiver's thread: its window and timer made — `made` told the
/// window, or none —, every message answered and every work done as it
/// comes due, for as long as the app runs.
fn receive(made: &Sender<Option<isize>>) {
    let Some(window) = make_window() else {
        let _ = made.send(None);
        return;
    };
    let timer = make_timer();
    let _ = made.send(Some(window.0 as isize));
    loop {
        wait(timer, SCHEDULE.with(|schedule| schedule.borrow().next()));
        answer_all();
        for (work, every) in SCHEDULE.with(|schedule| schedule.borrow().due_by(Instant::now())) {
            let lasts = run(work);
            SCHEDULE.with(|schedule| schedule.borrow_mut().done(work, every, Instant::now(), lasts));
        }
    }
}

/// A message-only window of the receiver's class, on this thread.
fn make_window() -> Option<HWND> {
    // SAFETY: this module, a class of it, and a window of that class.
    unsafe {
        let module = GetModuleHandleW(None).ok()?;
        let class = w!("AnicelPenReceiver");
        let kind = WNDCLASSW {
            lpfnWndProc: Some(answer),
            hInstance: module.into(),
            lpszClassName: class,
            ..Default::default()
        };
        // A class already registered is this one's, from a thread before.
        if RegisterClassW(&kind) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS {
            return None;
        }
        let (parent, instance) = (Some(HWND_MESSAGE), Some(module.into()));
        CreateWindowExW(Default::default(), class, None, Default::default(), 0, 0, 0, 0, parent, None, instance, None)
            .ok()
    }
}

/// A high-resolution waitable timer — a plain one where the system has
/// none (before Windows 10 1803) —, or None where neither is made.
fn make_timer() -> Option<HANDLE> {
    let make = |flags| {
        // SAFETY: an unnamed timer of this process's.
        unsafe { CreateWaitableTimerExW(None, PCWSTR::null(), flags, TIMER_ALL_ACCESS.0) }.ok()
    };
    make(CREATE_WAITABLE_TIMER_HIGH_RESOLUTION).or_else(|| make(0))
}

/// Waits for a message, or for `next` where a work is due: the timer armed
/// for it, or cancelled where none is.
fn wait(timer: Option<HANDLE>, next: Option<Instant>) {
    let left = next.map(|next| next.saturating_duration_since(Instant::now()));
    let millis = match (timer, left) {
        (Some(timer), Some(left)) => {
            // Relative, in 100 ns: at least one, so a due already past fires.
            let due = -i64::try_from(left.as_nanos() / 100).unwrap_or(i64::MAX).max(1);
            // SAFETY: the receiver's timer, armed once more.
            let _ = unsafe { SetWaitableTimer(timer, &due, 0, None, None, false) };
            INFINITE
        }
        (Some(timer), None) => {
            // SAFETY: the receiver's timer.
            let _ = unsafe { CancelWaitableTimer(timer) };
            INFINITE
        }
        // No timer: the wait's own timeout, at the system's tick.
        (None, Some(left)) => u32::try_from(left.as_millis()).unwrap_or(INFINITE - 1),
        (None, None) => INFINITE,
    };
    // SAFETY: the timer, if any, open for the thread's life.
    unsafe { MsgWaitForMultipleObjectsEx(Some(timer.as_slice()), millis, QS_ALLINPUT, MWMO_INPUTAVAILABLE) };
}

/// Answers every message waiting for the receiver's thread.
fn answer_all() {
    let mut message = MSG::default();
    // SAFETY: the thread's own queue, and a local.
    unsafe {
        while PeekMessageW(&mut message, None, 0, 0, PM_REMOVE).as_bool() {
            let _ = TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
}

unsafe extern "system" fn answer(window: HWND, message: u32, w: WPARAM, l: LPARAM) -> LRESULT {
    match message {
        WM_NOW => {
            if let Some(&work) = WORKS.get(w.0) {
                let every = Duration::from_micros(l.0.unsigned_abs() as u64);
                let lasts = run(work);
                SCHEDULE.with(|schedule| schedule.borrow_mut().done(work, every, Instant::now(), lasts));
            }
            LRESULT(0)
        }
        WM_LISTEN => LRESULT(isize::from(crate::raw::listen(window, l))),
        _ => {
            if message == WM_INPUT {
                crate::raw::take(HRAWINPUT(l.0 as *mut c_void));
            }
            // The system still needs its cleanup pass for WM_INPUT.
            // SAFETY: what the system handed this window.
            unsafe { DefWindowProcW(window, message, w, l) }
        }
    }
}
