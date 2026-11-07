//! The Wintab half played a driver (wintab_fake) and asked as the bridge
//! asks: what it answers and what it asks the driver, bit for bit, as the
//! C's were measured on the same packets (2026-11-07) and on answers worked
//! out here.

use std::sync::{Mutex, MutexGuard, OnceLock, PoisonError};

use windows::Win32::Foundation::{HMODULE, HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::System::LibraryLoader::{GetModuleHandleW, GetProcAddress, LoadLibraryW};
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, RegisterClassW, SW_SHOWNOACTIVATE,
    ShowWindow, WNDCLASSW, WS_EX_NOACTIVATE, WS_EX_NOREDIRECTIONBITMAP, WS_EX_TOOLWINDOW,
    WS_POPUP,
};
use windows::core::{HSTRING, PCWSTR, s, w};
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

/// The fake driver's own exports.
struct Driver {
    play: unsafe extern "C" fn(*const Script),
    seen: unsafe extern "C" fn(*mut Seen),
}

/// The fake driver, loaded before the reader looks for wintab32.dll — and
/// so the one it finds — with the tests that play it one at a time: the
/// driver, the reader's context and the app's window are the process's own.
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
        assert_eq!(found, fake, "LIVENESS — the reader would find another wintab32.dll");
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

/// A window the app's would be found as: of the runner's class, shown, of
/// this process (display's app_window). It draws nothing and stands one
/// pixel tall for the second it stands.
struct AppWindow(HWND);

unsafe extern "system" fn answer(window: HWND, message: u32, w: WPARAM, l: LPARAM) -> LRESULT {
    // SAFETY: what the system handed this window.
    unsafe { DefWindowProcW(window, message, w, l) }
}

/// The class the runner gives its window (windows/runner/win32_window.cpp).
const RUNNER: PCWSTR = w!("FLUTTER_RUNNER_WIN32_WINDOW");

impl AppWindow {
    fn show() -> Self {
        Self::make(RUNNER, true)
    }

    /// Two windows of this process the app's is not: one of the runner's
    /// class not shown, and one shown of another class.
    fn not_the_apps() -> [Self; 2] {
        [Self::make(RUNNER, false), Self::make(w!("AnicelPenTestWindow"), true)]
    }

    fn make(class: PCWSTR, shown: bool) -> Self {
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
                None,
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

/// A reading as it reads, step by step: each room as what was written and
/// how much after it was left as it was, each record as its eight values,
/// the context as the system's and the words it changed, and whether a
/// window was handed — not which: its handle is each run's.
fn told(reading: &Reading) -> Vec<String> {
    let mut told = vec![format!("available {}", reading.available)];
    for (length, room) in &reading.names {
        let untouched = room.iter().rev().take_while(|&&unit| unit == 0xFFFF).count();
        let written = String::from_utf16_lossy(&room[..room.len() - untouched]);
        told.push(format!("name {length} {written:?} +{untouched}"));
    }
    told.push(format!("opened {:?}", reading.opened));
    for (count, room) in &reading.polls {
        let unwritten = room.iter().rev().take_while(|&&bits| bits == UNWRITTEN).count();
        let records: Vec<Vec<f32>> = room[..room.len() - unwritten]
            .chunks(8)
            .map(|record| record.iter().map(|&bits| f32::from_bits(bits)).collect())
            .collect();
        told.push(format!("poll {count} {records:?} +{unwritten}"));
    }
    let seen = &reading.seen;
    let handed = if seen.window == 0 { "no window" } else { "a window" };
    let (opens, closes, queue, enable) = (seen.opens, seen.closes, seen.queue_size, seen.enable);
    told.push(format!("seen {opens} opens, {closes} closes, queue {queue}, enable {enable}, {handed}"));
    let system = system_context();
    let context = if seen.context.0 == [0; 53] {
        "none".to_owned()
    } else {
        let changed: Vec<_> = (0..53)
            .filter(|&at| seen.context.0[at] != system.0[at])
            .map(|at| format!("{at}={:#x}", seen.context.0[at]))
            .collect();
        format!("the system's but {}", changed.join(" "))
    };
    told.push(format!("context {context}"));
    told.push(format!("asked {:?}", &seen.asked[..seen.asks.clamp(0, 8) as usize]));
    told
}

/// The lines of a reading, in order.
fn tells(parts: &[&[&str]]) -> Vec<String> {
    parts.concat().into_iter().map(str::to_owned).collect()
}

// What the readers told of the fake driver, measured of the C 2026-11-07 —
// so held once it is gone (connection-round-checklist A); the driver is
// this crate's, and lives on after it.

/// An installed driver's, before anything opens: there, and its name into
/// each room — none at all, of nothing, one, five, 64 and 100.
const INSTALLED: [&str; 7] = [
    "available 1",
    r#"name 0 "" +0"#,
    r#"name 0 "" +101"#,
    r#"name 0 "\0" +100"#,
    r#"name 4 "Waco\0" +96"#,
    r#"name 19 "Wacom Cintiq 24 Pen\0" +81"#,
    r#"name 19 "Wacom Cintiq 24 Pen\0" +81"#,
];

/// A driver nothing was asked of.
const NOT_ASKED: [&str; 2] = ["seen 0 opens, 0 closes, queue 0, enable 0, no window", "context none"];

/// A driver whose context was opened once and closed once.
const OPENED_ONCE: [&str; 2] = [
    "seen 1 opens, 1 closes, queue 128, enable 1, a window",
    "context the system's but 20=0x5a15 26=0x15c4 27=0x0 28=0x15c4",
];

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
    let asks = super::bridge_asks("abiVersion");
    // SAFETY: an int out.
    assert_eq!(unsafe { (RUST.abi_version)() }, asks);
}

#[test]
fn without_a_driver_nothing_opens() {
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    let reading = read(driver, RUST, &Script::QUIET, &[64]);
    assert_eq!((reading.available, reading.opened, reading.polls[0].0), (0, [0, 0], 0));
    assert_eq!(reading.seen, Seen::NOTHING);
    let nameless = [r#"name 0 "" +101"#; 5];
    let nothing = ["opened [0, 0]", "poll 0 [] +520"];
    let none = ["available 0", r#"name 0 "" +0"#];
    assert_eq!(told(&reading), tells(&[&none, &nameless, &nothing, &NOT_ASKED, &["asked []"]]));
}

#[test]
fn without_the_apps_window_nothing_opens() {
    let (driver, _turn) = driver();
    let _others = AppWindow::not_the_apps();
    let reading = read(driver, RUST, &installed(&[packet(500, 0, 0, 0)]), &[64]);
    assert_eq!((reading.available, reading.opened), (1, [0, 0]));
    assert_eq!(reading.seen.opens, 0, "the driver is not asked without a window");
    let nothing = ["opened [0, 0]", "poll 0 [] +520"];
    assert_eq!(told(&reading), tells(&[&INSTALLED, &nothing, &NOT_ASKED, &["asked []"]]));
}

#[test]
fn a_driver_without_a_system_context_or_that_opens_none() {
    let (driver, _turn) = driver();
    let window = AppWindow::show();
    let nothing = ["opened [0, 0]", "poll 0 [] +520"];
    let script = Script { has_context: false, ..installed(&[packet(500, 0, 0, 0)]) };
    let reading = read(driver, RUST, &script, &[64]);
    assert_eq!(reading.opened, [0, 0]);
    assert_eq!(told(&reading), tells(&[&INSTALLED, &nothing, &NOT_ASKED, &["asked []"]]));
    let script = Script { opens: false, ..installed(&[packet(500, 0, 0, 0)]) };
    let reading = read(driver, RUST, &script, &[64]);
    assert_eq!((reading.opened, reading.polls[0].0), ([0, 0], 0));
    assert_eq!((reading.seen.opens, reading.seen.window), (2, window.0.0 as isize));
    let refused = [
        "seen 2 opens, 0 closes, queue 0, enable 1, a window",
        "context the system's but 20=0x5a15 26=0x15c4 27=0x0 28=0x15c4",
        "asked []",
    ];
    assert_eq!(told(&reading), tells(&[&INSTALLED, &nothing, &refused]));
}

#[test]
fn the_context_asked_for_is_the_systems_observing_alongside_it() {
    let (driver, _turn) = driver();
    let window = AppWindow::show();
    let reading = read(driver, RUST, &installed(&[]), &[]);
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
    assert_eq!(told(&reading), tells(&[&INSTALLED, &["opened [1, 1]"], &OPENED_ONCE, &["asked []"]]));
}

#[test]
fn the_name_is_what_room_there_is_for() {
    let (driver, _turn) = driver();
    let reading = read(driver, RUST, &installed(&[]), &[]);
    let lengths: Vec<_> = reading.names.iter().map(|(length, _)| *length).collect();
    assert_eq!(lengths, [0, 0, 0, 4, 19, 19], "no room, none, one, five, 64, 100");
    let closed = ["opened [0, 0]", NOT_ASKED[0], NOT_ASKED[1], "asked []"];
    assert_eq!(told(&reading), tells(&[&INSTALLED, &closed]));
    let long = "x".repeat(63);
    let script = Script { name: name(&long), ..installed(&[]) };
    let reading = read(driver, RUST, &script, &[]);
    assert_eq!(reading.names[5].0, 63);
    let named = [
        "available 1",
        r#"name 0 "" +0"#,
        r#"name 0 "" +101"#,
        r#"name 0 "\0" +100"#,
        r#"name 4 "xxxx\0" +96"#,
        r#"name 63 "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\0" +37"#,
        r#"name 63 "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\0" +37"#,
    ];
    assert_eq!(told(&reading), tells(&[&named, &closed]));
}

#[test]
fn a_name_longer_than_the_c_had_room_for_is_cut_where_it_cut() {
    // The C handed the driver 64 characters of room, and a longer name ran
    // past them: the C was never played one.
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
    let reading = read(driver, RUST, &script, &[0, 2, 100, 1]);
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
    let polled = [
        "opened [1, 1]",
        "poll 0 [] +8",
        "poll 2 [[0.50024426, 90.0, 0.5, 123456.0, 3.0, 1.0, 270.0, 1.0], \
         [0.0, 359.9, -0.33333334, 123456.0, 3.0, 1.0, 0.0, 1.0]] +8",
        "poll 3 [[1.0, 0.0, 1.0, 123456.0, 3.0, 1.0, 359.0, 1.0], \
         [1.0, 180.0, 0.0, 123456.0, 3.0, 1.0, 90.0, 1.0], \
         [0.0004885198, 0.2, 0.0033333334, 123456.0, 3.0, 1.0, 4.0, 1.0]] +784",
        "poll 0 [] +16",
    ];
    assert_eq!(told(&reading), tells(&[&INSTALLED, &polled, &OPENED_ONCE, &["asked [2, 64, 1]"]]));
}

#[test]
fn a_pen_with_no_lean_or_turn_reads_as_none() {
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    let packets = [packet(512, 900, 450, 270)];
    // No orientation axes; then an azimuth without an altitude, and a
    // twist of no span; then an altitude without an azimuth; then circles
    // so wide their count wraps; then no pressure axis at all, and one of no
    // span.
    let bare = Script { has_pressure: true, pressure: axis(0, 1023), ..installed(&packets) };
    let flat = Script {
        has_orientation: true,
        orientation: [axis(0, 3599), axis(-900, 0), axis(5, 5)],
        ..bare
    };
    let aimless = Script { orientation: [axis(5, 5), axis(-900, 900), axis(0, 0)], ..flat };
    let all = axis(i32::MIN, i32::MAX);
    let boundless = Script { orientation: [all, axis(-900, 900), all], ..flat };
    let unscaled = Script { has_pressure: false, ..flat };
    let narrow = Script { pressure: axis(7, 7), ..bare };
    let polled = ["opened [1, 1]", "poll 1 [[0.50048876, 0.0, 0.0, 123456.0, 3.0, 0.0, 0.0, 0.0]] +512"];
    for script in [bare, flat, aimless, boundless, unscaled, narrow] {
        let reading = read(driver, RUST, &script, &[64]);
        let want = [(512.0 * (1.0 / 1023.0)) as f32, 0.0, 0.0, 123_456.0, 3.0, 0.0, 0.0, 0.0];
        assert_eq!(reading.polls[0].1[..8], bits(want));
        assert_eq!(told(&reading), tells(&[&INSTALLED, &polled, &OPENED_ONCE, &["asked [64]"]]));
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
    let reading = read(driver, RUST, &script, &[64]);
    let record = &reading.polls[0].1;
    assert_eq!(record[0], 0.25f32.to_bits());
    assert_eq!(record[8], 1.0f32.to_bits(), "a count past i32 is still past the top");
    let polled = [
        "opened [1, 1]",
        "poll 2 [[0.25, 0.0, 0.0, 123456.0, 3.0, 0.0, 0.0, 0.0], [1.0, 0.0, 0.0, 123456.0, 3.0, 0.0, 0.0, 0.0]] +504",
    ];
    assert_eq!(told(&reading), tells(&[&INSTALLED, &polled, &OPENED_ONCE, &["asked [64]"]]));
}

#[test]
fn a_driver_is_not_read_past_what_it_was_asked_for() {
    // The C read on past its room for a count it was handed: it was never
    // played a driver that says it gave more.
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    let packets = [packet(100, 0, 0, 0), packet(200, 0, 0, 0), packet(300, 0, 0, 0)];
    let script = Script { claims_more: 70, ..installed(&packets) };
    let reading = read(driver, RUST, &script, &[2]);
    let (count, room) = &reading.polls[0];
    assert_eq!(*count, 2);
    assert!(room[16..].iter().all(|&value| value == UNWRITTEN), "two records, no more");
}

