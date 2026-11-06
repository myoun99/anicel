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
    assert_eq!(composing(RUST_COMPOSE, &[1, 0]), composing(c.compose, &[1, 0]));
    assert_eq!(between(|| screens(c.window_screens), || screens(RUST_WINDOW_SCREENS)).1.0, 0);
}

#[cfg(windows)]
mod window {
    use windows::Win32::Foundation::{HINSTANCE, HWND, LPARAM, LRESULT, WPARAM};
    use windows::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows::Win32::UI::WindowsAndMessaging::{
        CreateWindowExW, DefWindowProcW, DestroyWindow, GetSystemMetrics, RegisterClassW,
        SM_CXVIRTUALSCREEN, SM_XVIRTUALSCREEN, SW_SHOWNOACTIVATE, ShowWindow, WNDCLASSW,
        WS_EX_NOACTIVATE, WS_EX_NOREDIRECTIONBITMAP, WS_EX_TOOLWINDOW, WS_POPUP,
    };
    use windows::core::w;

    /// A window the app's would be found as: of the runner's class, shown,
    /// in this process. It draws nothing — the compositor has no picture of
    /// a window without a redirection bitmap — and stands one pixel tall
    /// across the virtual screen at the primary's top, under every screen
    /// that row crosses, in nobody's way for the second it stands.
    pub(super) struct AppWindow(HWND);

    unsafe extern "system" fn answer(window: HWND, message: u32, w: WPARAM, l: LPARAM) -> LRESULT {
        // SAFETY: what the system handed this window.
        unsafe { DefWindowProcW(window, message, w, l) }
    }

    impl AppWindow {
        pub(super) fn show() -> Self {
            let class = w!("FLUTTER_RUNNER_WIN32_WINDOW");
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
                    GetSystemMetrics(SM_XVIRTUALSCREEN),
                    0,
                    GetSystemMetrics(SM_CXVIRTUALSCREEN),
                    1,
                    None,
                    None,
                    Some(instance),
                    None,
                )
                .expect("a window of the runner's class");
                let _ = ShowWindow(window, SW_SHOWNOACTIVATE);
                Self(window)
            }
        }
    }

    impl Drop for AppWindow {
        fn drop(&mut self) {
            // SAFETY: the window this made, on the thread that made it.
            let _ = unsafe { DestroyWindow(self.0) };
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

    let _window = window::AppWindow::show();
    std::thread::sleep(PAST_FRESH);
    let (theirs, ours) = between(|| screens(c.window_screens), || screens(RUST_WINDOW_SCREENS));
    assert_eq!(ours, theirs);
    if super::win::has_target_statistics() {
        assert!(theirs.0 >= 1, "LIVENESS — the window lies on a screen: {theirs:?}");
    }
    let ons = [1, 1, 0, 0];
    let theirs = composing(c.compose, &ons);
    assert_eq!(theirs, vec![1, 1, 0, 0], "LIVENESS — the C keeps the compositor composing");
    assert_eq!(composing(RUST_COMPOSE, &ons), theirs);
}
