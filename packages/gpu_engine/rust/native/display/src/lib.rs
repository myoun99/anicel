//! The display's own timing (native-to-rust; the C was qa_display.c and
//! qa_display_compose.cpp): where its vblanks are, and a wait that ends on
//! a given microsecond — what a clock's frame needs to be handed to the GPU
//! so it lands on the vblank it was made for (the app's PresentPacing).
//!
//! Only Windows says: there the engine begins its frames on a vsync grid of
//! its own and presents without waiting for a vblank, so the compositor's
//! timing (DWM) is the only word on where the real vblanks are. Everywhere
//! else the engine's vsync IS the display's, and nothing here is asked for:
//! `qa_display_vblank` answers 0 and the wait returns at once.
//!
//! 🚨THE COMPOSITOR HAS ONE CLOCK AND EVERY SCREEN ITS OWN VBLANKS (measured
//! 2026-10-15, four screens of 144, 59.94, 59.95 and 60Hz): DWM's timing is
//! that clock, so a window on a slower screen is on a grid its pictures do
//! not land on. `qa_display_window_screens` names the vblanks of the screens
//! the window lies on; the compositor's per-target statistics are the only
//! word on those (Windows 11 on — without them there is no such answer, and
//! the app stays on the compositor's clock as it always was).
//!
//! Times are in microseconds of the performance counter — the clock Dart's
//! timeline reads on Windows, and so the clock the engine's frame times are
//! on. The compositor stamps its vblanks with the same counter.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

#[cfg(test)]
mod tests;
#[cfg(windows)]
mod win;

/// A real vblank and the refresh period: `out2[0]` the vblank, in
/// microseconds; `out2[1]` the period, in NANOseconds (a period is a
/// fraction of a microsecond off a whole one, and a run counts thousands of
/// them). 1 when the compositor said, 0 when there is none to ask or it
/// refused.
///
/// # Safety
/// `out2` is null or two writable `i64`s.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_display_vblank(out2: *mut i64) -> i32 {
    if out2.is_null() {
        return 0;
    }
    #[cfg(windows)]
    if let Some((vblank, period)) = win::vblank() {
        // SAFETY: see the function's contract.
        unsafe {
            out2.write(vblank);
            out2.add(1).write(period);
        }
        return 1;
    }
    0
}

/// The screens the app's window lies on, at most `max`: `out[2n]` a real
/// vblank of the n-th, in microseconds, `out[2n + 1]` its refresh period, in
/// NANOseconds, as `qa_display_vblank` has them. The count; 0 with no app
/// window to ask about, where the compositor keeps no such statistics
/// (before Windows 11), and everywhere but Windows.
///
/// # Safety
/// `out` is null or `2 * max` writable `i64`s.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_display_window_screens(out: *mut i64, max: i32) -> i32 {
    if out.is_null() {
        return 0;
    }
    #[cfg(windows)]
    {
        let screens = win::window_screens(max);
        for (n, (vblank, period)) in screens.iter().enumerate() {
            // SAFETY: see the function's contract; there are at most `max`.
            unsafe {
                out.add(2 * n).write(*vblank);
                out.add(2 * n + 1).write(*period);
            }
        }
        screens.len() as i32
    }
    #[cfg(not(windows))]
    {
        let _ = max;
        0
    }
}

/// Blocks the calling thread until `deadline_us` on `qa_display_vblank`'s
/// clock: the timer sleeps to within half a millisecond of it (its
/// resolution), a spin takes the rest. Gives up a little after the timer was
/// due, whatever the timer does. Returns at once where there is no display
/// to wait for.
#[unsafe(no_mangle)]
pub extern "C" fn qa_display_wait_until_us(deadline_us: i64) {
    #[cfg(windows)]
    win::wait_until(deadline_us);
    #[cfg(not(windows))]
    let _ = deadline_us;
}

/// Keeps the compositor composing on every vblank (`on` != 0), or lets it
/// rest again (0) — so a picture handed over between two vblanks is taken at
/// the second of them, however idle the rest of the desktop leaves it
/// (`win::compose` has the measurement). 1 while it is kept composing, 0
/// when it rests or cannot be kept: where there is no app window to compose
/// on, and everywhere but Windows, whose compositors take their frames on
/// the display's own vsync.
#[unsafe(no_mangle)]
pub extern "C" fn qa_display_compose_every_vblank(on: i32) -> i32 {
    #[cfg(windows)]
    {
        win::compose(on != 0) as i32
    }
    #[cfg(not(windows))]
    {
        let _ = on;
        0
    }
}
