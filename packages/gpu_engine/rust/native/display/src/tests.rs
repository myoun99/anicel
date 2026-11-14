//! The display's exports, asked as the app asks them. What the compositor
//! says is held to what GDI's door says of the same screens (window), and
//! where there is no compositor to ask, to the answers the exports give.
//!
//! ↩️Until the connection round each answer was held to the C's
//! (qa_display.c, qa_display_compose.cpp) around it; the C was deleted
//! with the app's switch to these (connection-round-checklist H,
//! 2026-11-08), and what held without it stayed (관제 판정 ①㉠).

use std::ptr::null_mut;

use super::{
    qa_display_compose_every_vblank, qa_display_vblank, qa_display_wait_until_us,
    qa_display_window_screens,
};

fn vblank() -> (i32, [i64; 2]) {
    let mut out = [-1; 2];
    // SAFETY: two i64s to write.
    let said = unsafe { qa_display_vblank(out.as_mut_ptr()) };
    (said, out)
}

/// At most four screens: what is written, and what is left as it was.
fn screens() -> (i32, [i64; 10]) {
    let mut out = [-1; 10];
    // SAFETY: eight i64s to write for four, two past them that must stay.
    let said = unsafe { qa_display_window_screens(out.as_mut_ptr(), 4) };
    (said, out)
}

/// What each `on` answers, in order.
fn composing(ons: &[i32]) -> Vec<i32> {
    ons.iter().map(|&on| qa_display_compose_every_vblank(on)).collect()
}

#[test]
fn a_null_is_answered_0() {
    // SAFETY: a null the exports refuse.
    assert_eq!(unsafe { (qa_display_vblank(null_mut()), qa_display_window_screens(null_mut(), 4)) }, (0, 0));
}

// The compositor's vblank against GDI's door (connection-round-checklist A,
// 관제 판정 ①㉠): its period is a rate a screen runs at, and the vblank it
// names never runs back. When it lies is not held: idle, the compositor
// keeps the last one it had; composing, it names the one coming (measured
// 2026-11-07).
#[cfg(windows)]
#[test]
fn the_vblank_keeps_a_screen_s_rate_and_never_runs_back() {
    let rates = window::rates();
    if rates.is_empty() {
        // No screen here says its rate: nothing to hold the period to.
        return;
    }
    let (said, [from, period]) = vblank();
    assert_eq!(said, 1, "a desktop with a screen has the compositor's vblank");
    assert!(window::a_rate_of(period, &rates), "{period} ns against {rates:?} Hz");
    let mut last = from;
    for _ in 0..50 {
        std::thread::sleep(std::time::Duration::from_millis(1));
        let (_, [at, _]) = vblank();
        assert!(at >= last, "{last} then {at}");
        last = at;
    }
}

#[cfg(windows)]
#[test]
fn a_wait_ends_on_its_microsecond() {
    for wait in 0..20 {
        let deadline = super::win::now() + 1500 + wait * 100;
        qa_display_wait_until_us(deadline);
        assert!(super::win::now() >= deadline, "woke before {deadline}");
    }
}

#[cfg(not(windows))]
#[test]
fn with_no_display_a_wait_returns_at_once_and_nothing_is_composed() {
    qa_display_wait_until_us(i64::MAX);
    assert_eq!(composing(&[1, 0]), [0, 0], "nothing is composed");
    assert_eq!(vblank(), (0, [-1; 2]), "no vblank");
    assert_eq!(screens(), (0, [-1; 10]), "no screens");
}

#[cfg(windows)]
mod window {
    use windows::Win32::Foundation::{HINSTANCE, HWND, LPARAM, LRESULT, RECT, TRUE, WPARAM};
    use windows::Win32::Graphics::Gdi::{
        DEVMODEW, DISPLAY_DEVICE_ATTACHED_TO_DESKTOP, DISPLAY_DEVICEW, ENUM_CURRENT_SETTINGS,
        EnumDisplayDevicesW, EnumDisplayMonitors, EnumDisplaySettingsW, HDC, HMONITOR,
    };
    use windows::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows::Win32::UI::WindowsAndMessaging::{
        CreateWindowExW, DefWindowProcW, DestroyWindow, RegisterClassW, SW_SHOWNOACTIVATE,
        ShowWindow, WNDCLASSW, WS_EX_NOACTIVATE, WS_EX_NOREDIRECTIONBITMAP, WS_EX_TOOLWINDOW,
        WS_POPUP,
    };
    use windows::core::{BOOL, PCWSTR, w};

    /// The rates the screens on the desktop run at, in hertz, as GDI's
    /// display settings say — a door the crate does not open. A rate of 0
    /// or 1 is a driver's "its default", which says none.
    pub(super) fn rates() -> Vec<u32> {
        let mut rates = Vec::new();
        for index in 0.. {
            let mut device = DISPLAY_DEVICEW { cb: size_of::<DISPLAY_DEVICEW>() as u32, ..Default::default() };
            // SAFETY: a local to write, its size in it.
            if !unsafe { EnumDisplayDevicesW(PCWSTR::null(), index, &mut device, 0) }.as_bool() {
                return rates;
            }
            let mut mode = DEVMODEW { dmSize: size_of::<DEVMODEW>() as u16, ..Default::default() };
            // SAFETY: the device's own name, and a local to write, its size in it.
            let current = unsafe {
                EnumDisplaySettingsW(PCWSTR(device.DeviceName.as_ptr()), ENUM_CURRENT_SETTINGS, &mut mode)
            };
            if device.StateFlags.contains(DISPLAY_DEVICE_ATTACHED_TO_DESKTOP)
                && current.as_bool()
                && mode.dmDisplayFrequency > 1
            {
                rates.push(mode.dmDisplayFrequency);
            }
        }
        rates
    }

    /// Whether a refresh period of `period_ns` is one of `rates` — to the
    /// hertz, which GDI's settings are told in (59.94 says 59, 143.91 says
    /// 144).
    pub(super) fn a_rate_of(period_ns: i64, rates: &[u32]) -> bool {
        let hertz = 1e9 / period_ns as f64;
        rates.iter().any(|&rate| (hertz - f64::from(rate)).abs() < 1.0)
    }

    /// A window the app's would be found as: of the runner's class, shown,
    /// in this process. It draws nothing — the compositor has no picture of
    /// a window without a redirection bitmap — and stands one pixel tall, in
    /// nobody's way for the second it stands: across the edge two screens
    /// share where there are such, so it lies on both; otherwise on a screen
    /// away from the origin. Either way its client area is not where a
    /// reading in client coordinates would put it.
    pub(super) struct AppWindow {
        window: HWND,
        /// The screens it lies on.
        pub(super) crossing: i32,
    }

    unsafe extern "system" fn answer(window: HWND, message: u32, w: WPARAM, l: LPARAM) -> LRESULT {
        // SAFETY: what the system handed this window.
        unsafe { DefWindowProcW(window, message, w, l) }
    }

    unsafe extern "system" fn screen(_: HMONITOR, _: HDC, bounds: *mut RECT, all: LPARAM) -> BOOL {
        // SAFETY: `all` is screens' local, `bounds` the system's.
        unsafe { (*(all.0 as *mut Vec<RECT>)).push(*bounds) };
        TRUE
    }

    fn screens() -> Vec<RECT> {
        let mut all: Vec<RECT> = Vec::new();
        // SAFETY: the callback pushes to `all` alone, before this returns.
        let _ = unsafe { EnumDisplayMonitors(None, None, Some(screen), LPARAM(&mut all as *mut _ as isize)) };
        all
    }

    /// Left, top and width of the strip, and how many screens it crosses.
    fn strip() -> (i32, i32, i32, i32) {
        let all = screens();
        for a in &all {
            for b in &all {
                let (top, bottom) = (a.top.max(b.top), a.bottom.min(b.bottom));
                if a.right == b.left && top < bottom {
                    return (a.right - 60, top + 10, 120, 2);
                }
            }
        }
        let away = all.iter().find(|s| s.left != 0 || s.top != 0).or(all.first());
        away.map_or((10, 10, 100, 1), |s| (s.left + 10, s.top + 10, 100, 1))
    }

    impl AppWindow {
        pub(super) fn show() -> Self {
            let class = w!("FLUTTER_RUNNER_WIN32_WINDOW");
            let (left, top, width, crossing) = strip();
            // SAFETY: this process's module, a class of it, and a window of
            // that class, shown without taking the focus.
            unsafe {
                let instance = HINSTANCE(GetModuleHandleW(None).expect("this module").0);
                let kind = WNDCLASSW {
                    lpfnWndProc: Some(answer),
                    hInstance: instance,
                    lpszClassName: class,
                    ..Default::default()
                };
                // 0 when an earlier test registered it: the class is there.
                RegisterClassW(&kind);
                let window = CreateWindowExW(
                    WS_EX_NOREDIRECTIONBITMAP | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
                    class,
                    w!(""),
                    WS_POPUP,
                    left,
                    top,
                    width,
                    1,
                    None,
                    None,
                    Some(instance),
                    None,
                )
                .expect("a window of the runner's class");
                let _ = ShowWindow(window, SW_SHOWNOACTIVATE);
                Self { window, crossing }
            }
        }
    }

    impl Drop for AppWindow {
        fn drop(&mut self) {
            // SAFETY: the window this made, on the thread that made it.
            let _ = unsafe { DestroyWindow(self.window) };
        }
    }
}

/// Where the window lies is read at most every 250ms, by the C and the Rust
/// alike: a little past that, both read it again.
/// Where the window lies is read at most every 250ms: a little past that,
/// it is read again.
#[cfg(windows)]
const PAST_FRESH: std::time::Duration = std::time::Duration::from_millis(300);

/// One test, so no other sees the window: its screens and its composing,
/// with no app window and with one.
#[cfg(windows)]
#[test]
fn the_screens_and_the_composing_of_the_app_window() {
    assert_eq!(screens(), (0, [-1; 10]), "no app window, no screens");
    assert_eq!(composing(&[1, 0]), [0, 0], "no app window, nothing kept composing");

    let window = window::AppWindow::show();
    std::thread::sleep(PAST_FRESH);
    let (count, out) = screens();
    // Against the strip's own geometry and GDI's door (connection-round-
    // checklist A, 관제 판정 ①㉠): as many screens as the strip crosses,
    // each period a rate a screen runs at, the room past them as it was.
    if super::win::has_target_statistics() {
        assert_eq!(count, window.crossing, "the screens it lies on: {out:?}");
        let rates = window::rates();
        for screen in out[..2 * count as usize].chunks(2) {
            assert!(rates.is_empty() || window::a_rate_of(screen[1], &rates), "{screen:?} against {rates:?} Hz");
        }
        assert!(out[2 * count as usize..].iter().all(|&value| value == -1), "{out:?}");
    } else {
        assert_eq!((count, out), (0, [-1; 10]), "no per-target statistics before Windows 11");
    }
    assert_eq!(composing(&[1, 1, 0, 0]), [1, 1, 0, 0], "the compositor kept composing while asked");
}
