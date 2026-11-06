//! The Wintab half held to the C's: both are played the same driver
//! (wintab_fake) and asked the same, and what they answer and what they ask
//! the driver are the same, bit for bit.

use std::sync::{Mutex, MutexGuard, OnceLock, PoisonError};

use windows::Win32::Foundation::{HMODULE, HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::System::LibraryLoader::{GetModuleHandleW, GetProcAddress, LoadLibraryW};
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, RegisterClassW, SW_SHOWNOACTIVATE,
    ShowWindow, WNDCLASSW, WS_EX_NOACTIVATE, WS_EX_NOREDIRECTIONBITMAP, WS_EX_TOOLWINDOW,
    WS_POPUP,
};
use windows::core::{HSTRING, s, w};
use wintab32::{
    Axis, Context, MOVE_MASK, OPTIONS, PACKET_DATA, PACKET_MODE, Packet, Script, Seen,
};

/// The `qat_*` exports of one reader.
#[derive(Clone, Copy)]
struct Reader {
    abi_version: unsafe extern "C" fn() -> i32,
    available: unsafe extern "C" fn() -> i32,
    device_name: unsafe extern "C" fn(*mut u16, i32) -> i32,
    open: unsafe extern "C" fn() -> i32,
    poll: unsafe extern "C" fn(*mut f32, i32) -> i32,
    close: unsafe extern "C" fn(),
}

const RUST: Reader = Reader {
    abi_version: crate::qat_abi_version,
    available: crate::qat_available,
    device_name: crate::qat_device_name,
    open: crate::qat_open,
    poll: crate::qat_poll,
    close: crate::qat_close,
};

fn c() -> Reader {
    // SAFETY: qa_tablet_win.c's declarations of each.
    unsafe {
        Reader {
            abi_version: oracle::sidecar_export("qa_tablet", "qat_abi_version"),
            available: oracle::sidecar_export("qa_tablet", "qat_available"),
            device_name: oracle::sidecar_export("qa_tablet", "qat_device_name"),
            open: oracle::sidecar_export("qa_tablet", "qat_open"),
            poll: oracle::sidecar_export("qa_tablet", "qat_poll"),
            close: oracle::sidecar_export("qa_tablet", "qat_close"),
        }
    }
}

/// The fake driver's own exports.
struct Driver {
    play: unsafe extern "C" fn(*const Script),
    seen: unsafe extern "C" fn(*mut Seen),
}

/// The fake driver, loaded before either reader looks for wintab32.dll —
/// and so the one they find — with the tests that play it one at a time:
/// the driver, both readers' contexts and the app's window are the
/// process's own.
fn driver() -> (&'static Driver, MutexGuard<'static, ()>) {
    static DRIVER: OnceLock<Driver> = OnceLock::new();
    static ONE_AT_A_TIME: Mutex<()> = Mutex::new(());
    let turn = ONE_AT_A_TIME.lock().unwrap_or_else(PoisonError::into_inner);
    let driver = DRIVER.get_or_init(|| {
        let exe = std::env::current_exe().expect("the test binary");
        let path = exe.with_file_name("wintab32.dll");
        assert!(path.is_file(), "no fake driver beside the test — {}", path.display());
        // SAFETY: the fake driver, which runs nothing as it loads.
        let fake = unsafe { LoadLibraryW(&HSTRING::from(path.as_os_str())) }.expect("the fake");
        // SAFETY: a query of a loaded module, by its name.
        let found = unsafe { GetModuleHandleW(w!("wintab32.dll")) }.expect("a wintab32");
        assert_eq!(found, fake, "LIVENESS — the readers would find another wintab32.dll");
        let entry = |name| {
            // SAFETY: the fake's own export of that name.
            unsafe { GetProcAddress(fake, name) }.unwrap_or_else(|| panic!("the fake's {name:?}"))
        };
        // SAFETY: the fake's declarations of each.
        unsafe {
            Driver {
                play: std::mem::transmute::<_, unsafe extern "C" fn(*const Script)>(entry(s!(
                    "fake_wintab_play"
                ))),
                seen: std::mem::transmute::<_, unsafe extern "C" fn(*mut Seen)>(entry(s!(
                    "fake_wintab_seen"
                ))),
            }
        }
    });
    (driver, turn)
}

impl Driver {
    fn play(&self, script: &Script) {
        // SAFETY: a script.
        unsafe { (self.play)(script) };
    }

    fn seen(&self) -> Seen {
        let mut seen = Seen::NOTHING;
        // SAFETY: room for what was seen.
        unsafe { (self.seen)(&mut seen) };
        seen
    }
}

/// A window the app's would be found as: shown, without an owner, of this
/// process. It draws nothing and stands one pixel tall for the second it
/// stands.
struct AppWindow(HWND);

unsafe extern "system" fn answer(window: HWND, message: u32, w: WPARAM, l: LPARAM) -> LRESULT {
    // SAFETY: what the system handed this window.
    unsafe { DefWindowProcW(window, message, w, l) }
}

impl AppWindow {
    fn show() -> Self {
        Self::make(None, true)
    }

    /// Two windows of this process the app's is not: one not shown, and one
    /// shown but owned by it.
    fn not_the_apps() -> [Self; 2] {
        let owner = Self::make(None, false);
        [Self::make(Some(owner.0), true), owner]
    }

    fn make(owner: Option<HWND>, shown: bool) -> Self {
        let class = w!("AnicelPenTestWindow");
        // SAFETY: this process's module, a class of it, and a window of that
        // class, shown without taking the focus.
        unsafe {
            let module: HMODULE = GetModuleHandleW(None).expect("this module");
            let kind = WNDCLASSW {
                lpfnWndProc: Some(answer),
                hInstance: module.into(),
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
                0,
                0,
                1,
                1,
                owner,
                None,
                Some(module.into()),
                None,
            )
            .expect("a window");
            if shown {
                let _ = ShowWindow(window, SW_SHOWNOACTIVATE);
            }
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

/// The floats a poll of `cap` records was handed, as bits, and its count.
type Polled = (i32, Vec<u32>);

/// Room no reader wrote: a NaN no record holds.
const UNWRITTEN: u32 = 0x7FC0_DEAD;

#[derive(Debug, PartialEq)]
struct Reading {
    available: i32,
    names: Vec<(i32, Vec<u16>)>,
    opened: [i32; 2],
    polls: Vec<Polled>,
    seen: Seen,
}

/// What `reader` answers and asks the driver as `script` plays: its name
/// into rooms of none to a hundred characters, opened twice, polled for
/// records `polls` at a time, closed twice.
fn read(driver: &Driver, reader: Reader, script: &Script, polls: &[i32]) -> Reading {
    driver.play(script);
    // SAFETY: each export of its declaration, with the room it is told of.
    unsafe {
        let available = (reader.available)();
        let mut names = vec![((reader.device_name)(std::ptr::null_mut(), 64), vec![])];
        for cap in [0, 1, 5, 64, 100] {
            let mut room = vec![0xFFFF_u16; 101];
            let length = (reader.device_name)(room.as_mut_ptr(), cap);
            names.push((length, room));
        }
        let opened = [(reader.open)(), (reader.open)()];
        let polls = polls
            .iter()
            .map(|&cap| {
                let mut room = vec![f32::from_bits(UNWRITTEN); 8 * (cap.max(0) as usize + 1)];
                let count = (reader.poll)(room.as_mut_ptr(), cap);
                (count, room.iter().map(|value| value.to_bits()).collect())
            })
            .collect();
        (reader.close)();
        (reader.close)();
        Reading { available, names, opened, polls, seen: driver.seen() }
    }
}

/// Both readers' readings of `script`, the same.
fn held(driver: &Driver, script: &Script, polls: &[i32]) -> Reading {
    let theirs = read(driver, c(), script, polls);
    let ours = read(driver, RUST, script, polls);
    assert_eq!(ours, theirs);
    ours
}

fn name(text: &str) -> [u16; 80] {
    let mut name = [0; 80];
    for (at, unit) in text.encode_utf16().enumerate() {
        name[at] = unit;
    }
    name
}

fn axis(min: i32, max: i32) -> Axis {
    Axis { min, max, units: 0, resolution: 0 }
}

fn packet(pressure: u32, azimuth: i32, altitude: i32, twist: i32) -> Packet {
    Packet { time: 123_456, buttons: 3, x: 40, y: 50, pressure, azimuth, altitude, twist }
}

/// The default system context, every word told apart.
fn system_context() -> Context {
    let mut words = [0; 53];
    for (at, word) in words.iter_mut().enumerate() {
        *word = 0x5A00 + at as u32;
    }
    Context(words)
}

/// A driver with a device, its context and the queue `packets`.
fn installed(packets: &[Packet]) -> Script {
    let mut script = Script {
        installed: true,
        name: name("Wacom Cintiq 24 Pen"),
        has_context: true,
        context: system_context(),
        opens: true,
        queued: packets.len() as i32,
        ..Script::QUIET
    };
    script.packets[..packets.len()].copy_from_slice(packets);
    script
}

/// The record a reader makes of a packet, as bits.
fn bits(record: [f32; 8]) -> Vec<u32> {
    record.iter().map(|value| value.to_bits()).collect()
}

#[test]
fn both_halves_keep_the_abi_their_bridge_asks_for() {
    // SAFETY: qa_tablet_win.c's declaration.
    assert_eq!(unsafe { (c().abi_version)() }, 2);
    // SAFETY: the same.
    assert_eq!(unsafe { (RUST.abi_version)() }, 2);
}

#[test]
fn without_a_driver_nothing_opens() {
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    let reading = held(driver, &Script::QUIET, &[64]);
    assert_eq!((reading.available, reading.opened, reading.polls[0].0), (0, [0, 0], 0));
    assert_eq!(reading.seen, Seen::NOTHING);
}

#[test]
fn without_the_apps_window_nothing_opens() {
    let (driver, _turn) = driver();
    let _others = AppWindow::not_the_apps();
    let reading = held(driver, &installed(&[packet(500, 0, 0, 0)]), &[64]);
    assert_eq!((reading.available, reading.opened), (1, [0, 0]));
    assert_eq!(reading.seen.opens, 0, "the driver is not asked without a window");
}

#[test]
fn a_driver_without_a_system_context_or_that_opens_none() {
    let (driver, _turn) = driver();
    let window = AppWindow::show();
    let script = Script { has_context: false, ..installed(&[packet(500, 0, 0, 0)]) };
    assert_eq!(held(driver, &script, &[64]).opened, [0, 0]);
    let script = Script { opens: false, ..installed(&[packet(500, 0, 0, 0)]) };
    let reading = held(driver, &script, &[64]);
    assert_eq!((reading.opened, reading.polls[0].0), ([0, 0], 0));
    assert_eq!((reading.seen.opens, reading.seen.window), (2, window.0.0 as isize));
}

#[test]
fn the_context_asked_for_is_the_systems_observing_alongside_it() {
    let (driver, _turn) = driver();
    let window = AppWindow::show();
    let reading = held(driver, &installed(&[]), &[]);
    assert_eq!(reading.opened, [1, 1]);
    let seen = reading.seen;
    assert_eq!((seen.opens, seen.closes, seen.queue_size), (1, 1, 128), "once each");
    assert_eq!((seen.window, seen.enable), (window.0.0 as isize, 1));
    let mut asked = system_context();
    asked.0[OPTIONS] |= 0x0001; // CXO_SYSTEM
    asked.0[PACKET_DATA] = 0x15C4; // TIME | BUTTONS | X | Y | NORMAL_PRESSURE | ORIENTATION
    asked.0[PACKET_MODE] = 0; // absolute
    asked.0[MOVE_MASK] = 0x15C4;
    assert_eq!(seen.context, asked);
}

#[test]
fn the_name_is_what_room_there_is_for() {
    let (driver, _turn) = driver();
    let reading = held(driver, &installed(&[]), &[]);
    let lengths: Vec<_> = reading.names.iter().map(|(length, _)| *length).collect();
    assert_eq!(lengths, [0, 0, 0, 4, 19, 19], "no room, none, one, five, 64, 100");
    let long = "x".repeat(63);
    let script = Script { name: name(&long), ..installed(&[]) };
    assert_eq!(held(driver, &script, &[]).names[5].0, 63);
}

#[test]
fn a_name_longer_than_the_c_had_room_for_is_cut_where_it_cut() {
    // The C hands the driver 64 characters of room, and a longer name runs
    // past them: only the Rust is played one.
    let (driver, _turn) = driver();
    let script = Script { name: name(&"y".repeat(79)), ..installed(&[]) };
    let reading = read(driver, RUST, &script, &[]);
    assert_eq!(reading.names[5].0, 63);
    assert_eq!(reading.names[5].1[63], 0, "and a NUL after");
}

#[test]
fn a_pen_that_leans_and_turns() {
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    let packets = [
        packet(1024, 900, 450, 270),
        packet(0, 3599, -300, 0),
        packet(2047, 0, 900, 359),
        packet(9000, 1800, 0, 90),
        packet(1, 2, 3, 4),
    ];
    let script = Script {
        has_pressure: true,
        pressure: axis(0, 2047),
        has_orientation: true,
        orientation: [axis(0, 3599), axis(-900, 900), axis(0, 359)],
        ..installed(&packets)
    };
    let reading = held(driver, &script, &[0, 2, 100, 1]);
    let counts: Vec<_> = reading.polls.iter().map(|(count, _)| *count).collect();
    assert_eq!(counts, [0, 2, 3, 0], "none asked, two, the rest, none left");
    let asked = &reading.seen.asked[..reading.seen.asks as usize];
    assert_eq!(asked, &[2, 64, 1], "a hundred asked for is its room of 64");
    let first = &reading.polls[1].1;
    let want = [(1024.0 * (1.0 / 2047.0)) as f32, 90.0, 0.5, 123_456.0, 3.0, 1.0, 270.0, 1.0];
    assert_eq!(first[..8], bits(want), "answers worked out here");
    let second = [0.0, 359.9, -300.0 / 900.0, 123_456.0, 3.0, 1.0, 0.0, 1.0];
    assert_eq!(first[8..16], bits(second));
    assert!(first[16..].iter().all(|&value| value == UNWRITTEN), "two records, no more");
    let past = &reading.polls[2].1;
    assert_eq!(past[8], 1.0f32.to_bits(), "pressure past the axis is whole, not more");
}

#[test]
fn a_pen_with_no_lean_or_turn_reads_as_none() {
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    let packets = [packet(512, 900, 450, 270)];
    // No orientation axes; then an azimuth without an altitude, and a
    // twist of no span; then no pressure axis at all.
    let bare = Script { has_pressure: true, pressure: axis(0, 1023), ..installed(&packets) };
    let flat = Script {
        has_orientation: true,
        orientation: [axis(0, 3599), axis(-900, 0), axis(5, 5)],
        ..bare
    };
    let unscaled = Script { has_pressure: false, ..flat };
    let narrow = Script { pressure: axis(7, 7), ..bare };
    for script in [bare, flat, unscaled, narrow] {
        let record = &held(driver, &script, &[64]).polls[0].1[..8];
        let want = [(512.0 * (1.0 / 1023.0)) as f32, 0.0, 0.0, 123_456.0, 3.0, 0.0, 0.0, 0.0];
        assert_eq!(record, bits(want));
    }
}

#[test]
fn a_pressure_axis_below_zero_counts_from_its_bottom() {
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    let script = Script {
        has_pressure: true,
        pressure: axis(-100, 100),
        ..installed(&[packet(50, 0, 0, 0), packet(u32::MAX, 0, 0, 0)])
    };
    let record = held(driver, &script, &[64]).polls[0].1.clone();
    assert_eq!(record[0], 0.25f32.to_bits());
    assert_eq!(record[8], 1.0f32.to_bits(), "a count past i32 is still past the top");
}

#[test]
fn a_driver_is_not_read_past_what_it_was_asked_for() {
    // The C reads on past its room for a count it is handed: only the Rust
    // is played a driver that says it gave more.
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    let packets = [packet(100, 0, 0, 0), packet(200, 0, 0, 0), packet(300, 0, 0, 0)];
    let script = Script { claims_more: 70, ..installed(&packets) };
    let reading = read(driver, RUST, &script, &[2]);
    let (count, room) = &reading.polls[0];
    assert_eq!(*count, 2);
    assert!(room[16..].iter().all(|&value| value == UNWRITTEN), "two records, no more");
}

