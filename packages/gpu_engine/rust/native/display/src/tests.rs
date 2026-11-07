//! The Rust display against the engine's C (native/oracle), through their
//! exports. The compositor moves on at every refresh, so a Rust answer is
//! held to the C's around it: asked of the C, the Rust and the C again, until
//! the C says the same twice.

use std::fmt::Debug;
use std::ptr::null_mut;

use super::{
    qa_display_compose_every_vblank, qa_display_vblank, qa_display_wait_until_us,
    qa_display_window_screens,
};

type Vblank = unsafe extern "C" fn(*mut i64) -> i32;
type WindowScreens = unsafe extern "C" fn(*mut i64, i32) -> i32;
type Wait = unsafe extern "C" fn(i64);
type Compose = unsafe extern "C" fn(i32) -> i32;

struct C {
    vblank: Vblank,
    window_screens: WindowScreens,
    wait: Wait,
    compose: Compose,
}

fn c() -> C {
    // SAFETY: qa_display.c's declarations.
    unsafe {
        C {
            vblank: oracle::export("qa_display_vblank"),
            window_screens: oracle::export("qa_display_window_screens"),
            wait: oracle::export("qa_display_wait_until_us"),
            compose: oracle::export("qa_display_compose_every_vblank"),
        }
    }
}

const RUST_VBLANK: Vblank = qa_display_vblank;
const RUST_WINDOW_SCREENS: WindowScreens = qa_display_window_screens;
const RUST_WAIT: Wait = qa_display_wait_until_us;
const RUST_COMPOSE: Compose = qa_display_compose_every_vblank;

/// The C's answer and the Rust's, the Rust asked between two C answers that
/// agree.
fn between<T: PartialEq + Debug>(c: impl Fn() -> T, rust: impl Fn() -> T) -> (T, T) {
    for _ in 0..1000 {
        let before = c();
        let ours = rust();
        if c() == before {
            return (before, ours);
        }
    }
    panic!("LIVENESS — the compositor held still across three asks");
}

fn vblank(ask: Vblank) -> (i32, [i64; 2]) {
    let mut out = [-1; 2];
    // SAFETY: two i64s to write.
    let said = unsafe { ask(out.as_mut_ptr()) };
    (said, out)
}

/// At most four screens: what is written, and what is left as it was.
fn screens(ask: WindowScreens) -> (i32, [i64; 10]) {
    let mut out = [-1; 10];
    // SAFETY: eight i64s to write for four, two past them that must stay.
    let said = unsafe { ask(out.as_mut_ptr(), 4) };
    (said, out)
}

/// What each `on` answers, in order.
fn composing(ask: Compose, ons: &[i32]) -> Vec<i32> {
    // SAFETY: an int in, an int out.
    ons.iter().map(|&on| unsafe { ask(on) }).collect()
}

#[test]
fn the_vblank_is_the_cs() {
    let c = c();
    let (theirs, ours) = between(|| vblank(c.vblank), || vblank(RUST_VBLANK));
    assert_eq!(ours, theirs);
    // SAFETY: a null the exports refuse.
    assert_eq!(unsafe { (RUST_VBLANK(null_mut()), RUST_WINDOW_SCREENS(null_mut(), 4)) }, (0, 0));
}

// The compositor's vblank against GDI's door, so held once the C is gone
// (connection-round-checklist A, 관제 판정 ①㉠): its period is a rate a
// screen runs at, and the vblank it names never runs back. When it lies is
// not held: idle, the compositor keeps the last one it had; composing, it
// names the one coming (measured 2026-11-07).
#[cfg(windows)]
#[test]
fn the_vblank_keeps_a_screen_s_rate_and_never_runs_back() {
    let rates = window::rates();
    if rates.is_empty() {
        // No screen here says its rate: the C's answer holds it alone.
        return;
    }
    let (said, [from, period]) = vblank(RUST_VBLANK);
    assert_eq!(said, 1, "a desktop with a screen has the compositor's vblank");
    assert!(window::a_rate_of(period, &rates), "{period} ns against {rates:?} Hz");
    let mut last = from;
    for _ in 0..50 {
        std::thread::sleep(std::time::Duration::from_millis(1));
        let (_, [at, _]) = vblank(RUST_VBLANK);
        assert!(at >= last, "{last} then {at}");
        last = at;
    }
}

#[cfg(windows)]
#[test]
fn a_wait_ends_on_its_microsecond_on_the_cs_clock() {
    let c = c();
    for wait in 0..20 {
        for (who, ask) in [("the C", c.wait), ("the Rust", RUST_WAIT)] {
            let deadline = super::win::now() + 1500 + wait * 100;
            // SAFETY: an int in.
            unsafe { ask(deadline) };
            assert!(super::win::now() >= deadline, "{who} woke before {deadline}");
        }
    }
}

#[cfg(not(windows))]
#[test]
fn with_no_display_a_wait_returns_at_once_and_nothing_is_composed() {
    let c = c();
    for ask in [c.wait, RUST_WAIT] {
        // SAFETY: an int in.
        unsafe { ask(i64::MAX) };
    }
    let ours = composing(RUST_COMPOSE, &[1, 0]);
    assert_eq!(ours, composing(c.compose, &[1, 0]));
    assert_eq!(ours, [0, 0], "nothing is composed");
    assert_eq!(between(|| screens(c.window_screens), || screens(RUST_WINDOW_SCREENS)).1.0, 0);
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
#[cfg(windows)]
const PAST_FRESH: std::time::Duration = std::time::Duration::from_millis(300);

/// One test, so no other sees the window: its screens and its composing,
/// with no app window and with one.
#[cfg(windows)]
#[test]
fn the_screens_and_the_composing_of_the_app_window_are_the_cs() {
    let c = c();
    let none = between(|| screens(c.window_screens), || screens(RUST_WINDOW_SCREENS));
    assert_eq!(none, ((0, [-1; 10]), (0, [-1; 10])), "no app window, no screens");
    assert_eq!(
        (composing(c.compose, &[1, 0]), composing(RUST_COMPOSE, &[1, 0])),
        (vec![0, 0], vec![0, 0]),
        "no app window, nothing kept composing"
    );

    let window = window::AppWindow::show();
    std::thread::sleep(PAST_FRESH);
    let (theirs, ours) = between(|| screens(c.window_screens), || screens(RUST_WINDOW_SCREENS));
    assert_eq!(ours, theirs);
    // Against the strip's own geometry and GDI's door, so held once the C
    // is gone (connection-round-checklist A, 관제 판정 ①㉠): as many screens
    // as the strip crosses, each period a rate a screen runs at, the room
    // past them as it was.
    if super::win::has_target_statistics() {
        let (count, out) = ours;
        assert_eq!(count, window.crossing, "the screens it lies on: {ours:?}");
        let rates = window::rates();
        for screen in out[..2 * count as usize].chunks(2) {
            assert!(rates.is_empty() || window::a_rate_of(screen[1], &rates), "{screen:?} against {rates:?} Hz");
        }
        assert!(out[2 * count as usize..].iter().all(|&value| value == -1), "{out:?}");
    }
    let ons = [1, 1, 0, 0];
    let ours = composing(RUST_COMPOSE, &ons);
    assert_eq!(ours, composing(c.compose, &ons));
    assert_eq!(ours, [1, 1, 0, 0], "the compositor kept composing while asked");
}
