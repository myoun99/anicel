//! The Wintab half played a driver (wintab_fake) and asked as the bridge
//! asks: what it answers and what it asks the driver, bit for bit, as the
//! C's were measured on the same packets (2026-11-07) and on answers worked
//! out here.

use std::sync::{Mutex, MutexGuard, OnceLock, PoisonError};

use windows::Win32::Foundation::{HMODULE, HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::System::LibraryLoader::{GetModuleHandleW, GetProcAddress, LoadLibraryW};
use windows::Win32::Foundation::POINT;
use windows::Win32::Graphics::Gdi::ClientToScreen;
use windows::Win32::UI::Input::Pointer::POINTER_INFO;
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, GetMessageTime, PT_PEN, PT_TOUCH,
    RegisterClassW, SW_SHOWNOACTIVATE, ShowWindow, WM_LBUTTONDOWN, WNDCLASSW, WS_EX_NOACTIVATE,
    WS_EX_NOREDIRECTIONBITMAP, WS_EX_TOOLWINDOW, WS_POPUP,
};
use windows::core::{HSTRING, PCWSTR, s, w};
use wintab32::{
    Axis, Context, MOVE_MASK, OPTIONS, OUT_EXTENT, OUT_ORIGIN, PACKET_DATA, PACKET_MODE, Packet, Script,
    Seen,
};

use crate::points::Driven;
use crate::points_win::Move;
use crate::wintab::{self, Heard, Output, QUEUE, Scales};

/// The `qat_*` exports of one reader.
#[derive(Clone, Copy)]
struct Reader {
    abi_version: unsafe extern "C" fn() -> i32,
    available: unsafe extern "C" fn() -> i32,
    device_name: unsafe extern "C" fn(*mut u16, i32) -> i32,
    open: unsafe extern "C" fn(i32) -> i32,
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
/// into rooms of none to a hundred characters, opened twice, the queue
/// drained as a press drains it ([`wintab::drain`]) — so what was queued is
/// heard whenever the reader's own thread drains —, polled for records
/// `polls` at a time, closed twice.
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
        let opened = [(reader.open)(150), (reader.open)(150)];
        wintab::drain();
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
    // How many times it was asked is the reader's own thread's to say: what
    // each drain asked for, told once.
    let mut asked = seen.asked[..seen.asks.clamp(0, 8) as usize].to_vec();
    asked.dedup();
    told.push(format!("asked {asked:?}"));
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
    "seen 1 opens, 1 closes, queue 1024, enable 1, a window",
    "context the system's but 20=0x5a15 26=0x15c6 27=0x0 28=0x15c6",
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
    Packet { status: 0, time: 123_456, buttons: 3, x: 40, y: 50, pressure, azimuth, altitude, twist }
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
        "context the system's but 20=0x5a15 26=0x15c6 27=0x0 28=0x15c6",
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
    assert_eq!((seen.opens, seen.closes, seen.queue_size), (1, 1, QUEUE as i32), "once each");
    assert_eq!((seen.window, seen.enable), (window.0.0 as isize, 1));
    let mut asked = system_context();
    asked.0[OPTIONS] |= 0x0001; // CXO_SYSTEM
    // STATUS | TIME | BUTTONS | X | Y | NORMAL_PRESSURE | ORIENTATION
    asked.0[PACKET_DATA] = 0x15C6;
    asked.0[PACKET_MODE] = 0; // absolute
    asked.0[MOVE_MASK] = 0x15C6;
    assert_eq!(seen.context, asked);
    assert_eq!(told(&reading), tells(&[&INSTALLED, &["opened [1, 1]"], &OPENED_ONCE, &["asked [1024]"]]));
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
    let reading = read(driver, RUST, &script, &[0, 100, 1]);
    let counts: Vec<_> = reading.polls.iter().map(|(count, _)| *count).collect();
    assert_eq!(counts, [0, 5, 0], "none asked, all five, none new");
    let asked = &reading.seen.asked[..reading.seen.asks.clamp(0, 8) as usize];
    assert!(!asked.is_empty() && asked.iter().all(|&size| size == 1024), "each drain asks for the whole queue");
    let records = &reading.polls[1].1;
    let want = [(1024.0 * (1.0 / 2047.0)) as f32, 90.0, 0.5, 123_456.0, 3.0, 1.0, 270.0, 1.0];
    assert_eq!(records[..8], bits(want), "answers worked out here");
    let second = [0.0, 359.9, -300.0 / 900.0, 123_456.0, 3.0, 1.0, 0.0, 1.0];
    assert_eq!(records[8..16], bits(second));
    assert_eq!(records[24], 1.0f32.to_bits(), "pressure past the axis is whole, not more");
    assert!(records[40..].iter().all(|&value| value == UNWRITTEN), "five records, no more");
    let polled = [
        "opened [1, 1]",
        "poll 0 [] +8",
        "poll 5 [[0.50024426, 90.0, 0.5, 123456.0, 3.0, 1.0, 270.0, 1.0], \
         [0.0, 359.9, -0.33333334, 123456.0, 3.0, 1.0, 0.0, 1.0], \
         [1.0, 0.0, 1.0, 123456.0, 3.0, 1.0, 359.0, 1.0], \
         [1.0, 180.0, 0.0, 123456.0, 3.0, 1.0, 90.0, 1.0], \
         [0.0004885198, 0.2, 0.0033333334, 123456.0, 3.0, 1.0, 4.0, 1.0]] +768",
        "poll 0 [] +16",
    ];
    let asked = ["asked [1024]"];
    assert_eq!(told(&reading), tells(&[&INSTALLED, &polled, &OPENED_ONCE, &asked]));
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
        assert_eq!(told(&reading), tells(&[&INSTALLED, &polled, &OPENED_ONCE, &["asked [1024]"]]));
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
    assert_eq!(told(&reading), tells(&[&INSTALLED, &polled, &OPENED_ONCE, &["asked [1024]"]]));
}

#[test]
fn a_driver_is_not_read_past_what_it_was_asked_for() {
    // The C read on past its room for a count it was handed: it was never
    // played a driver that says it gave more than the room it was asked to
    // fill — the whole queue's.
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    let packets = [packet(100, 0, 0, 0), packet(200, 0, 0, 0), packet(300, 0, 0, 0)];
    let script = Script { claims_more: QUEUE as i32, ..installed(&packets) };
    let reading = read(driver, RUST, &script, &[2]);
    let (count, room) = &reading.polls[0];
    assert_eq!(*count, 2);
    assert!(room[16..].iter().all(|&value| value == UNWRITTEN), "two records, no more");
}

#[test]
fn a_poll_is_handed_the_newest_of_the_packets_it_was_not_handed() {
    // ↩️A poll took the OLDEST 64 queued and left the rest to the next: after
    // a stall, the packet the app read as the pen now was the 64th oldest.
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    let packets: Vec<Packet> =
        (1..=70).map(|at| Packet { time: at, ..packet(at, 0, 0, 0) }).collect();
    let script = Script { has_pressure: true, pressure: axis(0, 100), ..installed(&packets) };
    let reading = read(driver, RUST, &script, &[2, 64]);
    let counts: Vec<_> = reading.polls.iter().map(|(count, _)| *count).collect();
    assert_eq!(counts, [2, 0], "the newest two, then none new");
    let records = &reading.polls[0].1;
    let newest = |at: u32| bits([(f64::from(at) * (1.0 / 100.0)) as f32, 0.0, 0.0, at as f32, 3.0, 0.0, 0.0, 0.0]);
    assert_eq!(records[..8], newest(69));
    assert_eq!(records[8..16], newest(70));
}

#[test]
fn the_queue_asked_for_halves_till_the_driver_takes_one() {
    // A size refused leaves no queue at all (Wintab 1.4): the next is asked.
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    for (most, taken) in [(i32::MAX, 1024), (1023, 512), (300, 256), (1, 1), (0, 1)] {
        let script = Script { queue_most: most, ..installed(&[]) };
        let reading = read(driver, RUST, &script, &[]);
        assert_eq!(reading.seen.queue_size, taken, "a driver taking {most} at most");
    }
}

/// A packet heard at `time` on the message clock, of `pressure`, at the
/// output's (0, 0) — [`HERE`] on [`SCREEN`].
fn heard_at(time: u32, pressure: u32) -> wintab::Packet {
    wintab::Packet { time, normal_pressure: pressure, ..Default::default() }
}

/// A system context's output over a screen 100 pixels on a side.
const SCREEN: Output = Output { origin: [0, 0], extent: [100, 100] };

/// The screen pixel the output's (0, 0) is: its bottom row's first.
const HERE: (i32, i32) = (0, 99);

/// The pressure of the packet that put the cursor at [`HERE`] at `time`.
fn here(heard: &Heard, time: u32, within: u32) -> Option<u32> {
    heard.at((HERE.0, HERE.1, time), within, SCREEN).map(|packet| packet.normal_pressure)
}

/// What was heard of `packets`, in their order.
fn hearing(packets: &[wintab::Packet]) -> Heard {
    let mut heard = Heard::default();
    heard.hear(packets);
    heard
}

/// The times of the packets handed to a poll of `room`.
fn handed(heard: &mut Heard, room: usize) -> Vec<u32> {
    heard.hand(room).map(|packet| packet.time).collect()
}

#[test]
fn what_was_heard_is_handed_the_newest_first_and_once() {
    let mut heard = hearing(&(1..=5).map(|at| heard_at(at, 0)).collect::<Vec<_>>());
    assert_eq!(handed(&mut heard, 2), [4, 5]);
    assert_eq!(handed(&mut heard, 10), [] as [u32; 0], "and the older ones not after");
    heard.hear(&[heard_at(6, 0), heard_at(7, 0)]);
    assert_eq!(handed(&mut heard, 10), [6, 7], "what came since");
    assert_eq!(handed(&mut heard, 0), [] as [u32; 0]);
}

#[test]
fn the_most_heard_is_a_queue_s_worth_the_oldest_going_first() {
    let mut heard = hearing(&(1..=QUEUE as u32 + 5).map(|at| heard_at(at, at)).collect::<Vec<_>>());
    assert_eq!(here(&heard, 5, 0), None, "the five oldest went");
    assert_eq!(here(&heard, 6, 0), Some(6));
    let all = handed(&mut heard, usize::MAX);
    assert_eq!((all.len(), all[0]), (QUEUE, 6), "a queue's worth handed, and no more");
}

#[test]
fn a_packet_that_says_the_queue_overflowed_is_counted() {
    let statuses = [0, 0x2, 0x3, 0x1, 0x12, 0x4];
    let packets: Vec<_> = statuses.iter().map(|&status| wintab::Packet { status, ..heard_at(1, 0) }).collect();
    assert_eq!(hearing(&packets).overflowed, 3, "TPS_QUEUE_ERR, whatever else beside it");
}

#[test]
fn a_move_is_given_the_packet_at_its_place_nearest_it_within_the_window() {
    let heard = hearing(&[heard_at(100, 1), heard_at(110, 2), heard_at(120, 3), heard_at(500, 4)]);
    let near = |time, within| here(&heard, time, within);
    assert_eq!(near(104, 150), Some(1));
    assert_eq!(near(106, 150), Some(2));
    assert_eq!(near(105, 150), Some(2), "of two as near, the newer");
    assert_eq!(near(270, 150), Some(3), "at the window's edge");
    assert_eq!(near(271, 150), None, "past it");
    assert_eq!(near(0, 150), Some(1), "a move before every packet");
    assert_eq!(near(500, 0), Some(4));
    assert_eq!(near(499, 0), None, "a window of nothing is the same millisecond");
}

#[test]
fn a_packet_elsewhere_gives_a_move_nothing_however_near_in_time() {
    let away = |time, (x, y), pressure| wintab::Packet { x, y, ..heard_at(time, pressure) };
    let heard = hearing(&[heard_at(100, 1), away(104, (2, 0), 2), away(105, (1, 1), 3)]);
    assert_eq!(here(&heard, 104, 150), Some(3), "a pixel round its place is its place");
    assert_eq!(heard.at((0, 97, 104), 150, SCREEN).map(|packet| packet.normal_pressure), Some(3));
    assert_eq!(heard.at((50, 50, 104), 150, SCREEN), None, "no packet put it there");
}

#[test]
fn a_move_of_a_step_of_the_message_clock_takes_the_packet_at_its_own_place() {
    // 🔬H61, main PC, a pen as a mouse (k-h61, 11-18): moves the history
    // told at two steps of the message clock (…843 · …859), and the packets
    // the driver put them with, one every 4 ms — over a virtual screen
    // −2,560, 0 · 6,200 × 2,880, where a packet's y is 2,879 less the move's.
    let screen = Output { origin: [-2560, 0], extent: [6200, 2880] };
    let put = |time, x, y, pressure| wintab::Packet { x, y, ..heard_at(time, pressure) };
    let heard = hearing(&[
        put(841, 1174, 713, 8652),
        put(845, 1165, 711, 8660),
        put(849, 1157, 709, 8676),
        put(853, 1149, 707, 8684),
        put(858, 1142, 705, 8685),
        put(862, 1134, 704, 8653),
    ]);
    let moves = [
        (1174, 2167, 843),
        (1166, 2168, 843),
        (1158, 2170, 843),
        (1150, 2172, 843),
        (1142, 2174, 859),
        (1134, 2176, 859),
    ];
    let pressures: Vec<_> =
        moves.iter().map(|&at| heard.at(at, 150, screen).map(|packet| packet.normal_pressure)).collect();
    assert_eq!(pressures, [8652, 8660, 8676, 8684, 8685, 8653].map(Some), "each its own packet's");
}

#[test]
fn the_message_clock_wraps_for_a_packet_as_for_a_move() {
    let heard = hearing(&[heard_at(u32::MAX - 5, 1), heard_at(4, 2)]);
    let near = |time| here(&heard, time, 150);
    assert_eq!(near(u32::MAX), Some(2), "five either side of the wrap: the newer");
    assert_eq!(near(u32::MAX - 6), Some(1));
    assert_eq!(near(3), Some(2));
}

#[test]
fn a_packet_older_than_the_window_ends_the_search() {
    // The packets run in time: one older than the window has none newer
    // before it.
    let heard = hearing(&[heard_at(300, 1), heard_at(100, 2), heard_at(200, 3)]);
    assert_eq!(here(&heard, 300, 50), None);
}

#[test]
fn a_system_context_s_y_runs_up_and_a_negative_extent_s_down() {
    let packet = wintab::Packet { x: 40, y: 50, ..Default::default() };
    assert_eq!(SCREEN.place_of(&packet), (40, 49));
    let below = Output { origin: [-2560, 100], extent: [6200, 2880] };
    assert_eq!(below.place_of(&wintab::Packet { y: 100, ..packet }), (40, 2979), "its bottom row");
    let down = Output { origin: [0, 0], extent: [100, -100] };
    assert_eq!(down.place_of(&packet), (40, 50));
}

#[test]
fn how_far_the_newest_packet_is_behind_a_message_is_noted() {
    let mut heard = Heard::default();
    heard.behind(100);
    assert_eq!(heard.gap, None, "nothing heard");
    heard.hear(&[heard_at(100, 0), heard_at(120, 0)]);
    heard.behind(130);
    assert_eq!(heard.gap, Some(10));
    heard.behind(110);
    assert_eq!(heard.gap, Some(-10), "a packet newer than the message");
}

/// A system context whose output's y runs down: a packet's place is the
/// screen's own pixel.
fn running_down() -> Context {
    let mut context = system_context();
    context.0[OUT_EXTENT + 1] = (-1i32) as u32;
    context
}

/// A packet of the fake driver's, at `time` on the message clock, of
/// `pressure`.
fn queued(time: u32, pressure: u32) -> Packet {
    Packet { time, ..packet(pressure, 0, 0, 0) }
}

/// The pressure `reading` gives: NaN where no packet gave one.
fn pressure_of(reading: &Option<Driven>) -> f64 {
    reading.map_or(f64::NAN, |reading| reading.pressure)
}

/// The pressure the packet at each of `moves` gives ([`wintab::readings_at`]).
fn pressures_at(message: u32, moves: &[Move]) -> Vec<f64> {
    wintab::readings_at(message, moves).iter().map(pressure_of).collect()
}

/// A device axis from `min` to `max`, as the reader keeps it.
fn kept_axis(min: i32, max: i32) -> wintab::Axis {
    let mut axis = wintab::Axis::default();
    (axis.min, axis.max) = (min, max);
    axis
}

#[test]
fn a_reading_leans_and_turns_only_where_the_device_declares_it() {
    let orientation = wintab::Orientation { azimuth: 900, altitude: 450, twist: 270 };
    let pen = wintab::Packet { orientation, ..heard_at(0, 512) };
    let pressure = 512.0 * (1.0 / 1023.0);
    let scales = |twist| Scales::of(Some(kept_axis(0, 1023)), Some([kept_axis(0, 3599), kept_axis(-900, 900), twist]));
    let bare = Scales::of(Some(kept_axis(0, 1023)), None);
    assert_eq!(bare.reading(&pen), Driven { pressure, lean: None, twist: None });
    let leaning = scales(kept_axis(5, 5)).reading(&pen);
    assert_eq!(leaning, Driven { pressure, lean: Some((90.0, 0.5)), twist: None });
    assert_eq!(scales(kept_axis(0, 359)).reading(&pen).twist, Some(270.0));
}

// The packet that gives a move its pressure gives it its lean and its twist
// — the newest is another place's.
#[test]
fn a_move_is_given_the_lean_and_twist_of_the_packet_at_its_place_as_its_pressure() {
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    let at_place = Packet { time: 1000, ..packet(500, 900, 450, 90) };
    let newest = Packet { x: 60, time: 1004, ..packet(800, 2700, -300, 180) };
    // An output 100 high: the fake's packets, at its (40, 50), are the
    // screen's (40, 49).
    let mut context = system_context();
    (context.0[OUT_ORIGIN + 1], context.0[OUT_EXTENT + 1]) = (0, 100);
    let script = Script {
        has_pressure: true,
        pressure: axis(0, 1000),
        has_orientation: true,
        orientation: [axis(0, 3599), axis(-900, 900), axis(0, 359)],
        context,
        ..installed(&[at_place, newest])
    };
    driver.play(&script);
    assert_eq!(crate::qat_open(20), 1);
    wintab::drain();
    let readings = wintab::readings_at(1005, &[(40, 49, 1004), (60, 49, 1004)]);
    crate::qat_close();
    let read = |pressure: f64, bearing, altitude, twist| Driven {
        pressure: pressure * (1.0 / 1000.0),
        lean: Some((bearing, altitude)),
        twist: Some(twist),
    };
    let want = [Some(read(500.0, 90.0, 0.5, 90.0)), Some(read(800.0, 270.0, -300.0 / 900.0, 180.0))];
    assert_eq!(readings, want);
}

#[test]
fn a_mouse_move_is_given_the_pressure_of_the_packet_at_its_place() {
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    let packets = [queued(1000, 100), queued(1010, 200), queued(1020, 300)];
    // An output 100 high: the fake's packets, at its (40, 50), are the
    // screen's (40, 49).
    let mut context = system_context();
    (context.0[OUT_ORIGIN + 1], context.0[OUT_EXTENT + 1]) = (0, 100);
    let script = Script { has_pressure: true, pressure: axis(0, 1000), context, ..installed(&packets) };
    driver.play(&script);
    let mut gap = 0;
    // SAFETY: room for an int.
    let gapped = unsafe { crate::qat_clock_gap(&mut gap) };
    assert_eq!((crate::qat_open(20), gapped), (1, 0), "no gap before a message");
    wintab::drain();
    let at = |time| (40, 49, time);
    let moves = [at(1004), at(1016), at(1040), at(1041), at(980), at(979), (40, 47, 1010)];
    let pressures = pressures_at(1030, &moves);
    let scale = |pressure: f64| pressure * (1.0 / 1000.0);
    let want = [scale(100.0), scale(300.0), scale(300.0), f64::NAN, scale(100.0), f64::NAN, f64::NAN];
    let bits = |values: &[f64]| values.iter().map(|value| value.to_bits()).collect::<Vec<_>>();
    assert_eq!(bits(&pressures), bits(&want), "at its place, within the 20 ms the app opened with");
    // SAFETY: room for an int.
    let gapped = unsafe { crate::qat_clock_gap(&mut gap) };
    assert_eq!((gapped, gap, crate::qat_overflowed()), (1, 10, 0));
    crate::qat_close();
    let closed = pressures_at(1030, &[at(1020)]);
    assert!(closed[0].is_nan(), "no context, no pressure");
    // SAFETY: room for an int.
    assert_eq!(unsafe { crate::qat_clock_gap(&mut gap) }, 0);
}

#[test]
fn the_overflows_the_driver_said_are_counted_from_the_opening() {
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    let overflowed = Packet { status: 0x2, ..queued(1000, 100) };
    driver.play(&installed(&[overflowed, queued(1001, 100), overflowed]));
    assert_eq!(crate::qat_open(150), 1);
    wintab::drain();
    assert_eq!(crate::qat_overflowed(), 2);
    crate::qat_close();
    assert_eq!(crate::qat_overflowed(), 0, "none open");
}

#[test]
fn a_mouse_message_gives_its_point_the_driver_s_pressure() {
    let (driver, _turn) = driver();
    let window = AppWindow::show();
    // SAFETY: the time of the last message this thread took.
    let time = unsafe { GetMessageTime() } as u32;
    // A place no mouse is: no history of it kept, the message's own move
    // alone — and the packet that put the cursor there.
    let far: i16 = -20_000;
    let mut there = POINT { x: far.into(), y: far.into() };
    // SAFETY: the window shown, and a local.
    let _ = unsafe { ClientToScreen(window.0, &mut there) };
    let put = Packet { x: there.x, y: there.y, ..queued(time.wrapping_sub(3), 250) };
    let script = Script { has_pressure: true, pressure: axis(0, 1000), context: running_down(), ..installed(&[put]) };
    driver.play(&script);
    assert_eq!(crate::qat_open(150), 1);
    wintab::drain();
    let word = (far as u16) as isize;
    let words = word | (word << 16);
    crate::points_win::mouse(window.0, LPARAM(words));
    crate::qat_close();
    let at = (f64::from(far), f64::from(far));
    let pen = crate::points::book().take(crate::points::Kind::Pen, at);
    assert_eq!(pen, None, "a mouse's batch is a mouse's datum's alone (H61)");
    let points = crate::points::book().take(crate::points::Kind::Mouse, at);
    let points = points.expect("the message's");
    let driven: Vec<f64> = points.iter().map(|point| pressure_of(&point.driven)).collect();
    assert_eq!(driven, [250.0 * (1.0 / 1000.0)]);
    assert!(points[0].pressure.is_nan(), "a mouse says no pressure of its own");
}

/// Polls of up to eight records until one is handed, for two seconds at
/// most: their count.
fn handed_soon() -> i32 {
    handed_within(std::time::Duration::from_secs(2))
}

/// Polls of up to eight records until one is handed, for `most` at most:
/// their count.
fn handed_within(most: std::time::Duration) -> i32 {
    let mut room = [0.0f32; 64];
    let deadline = std::time::Instant::now() + most;
    loop {
        // SAFETY: room for eight records.
        let count = unsafe { crate::qat_poll(room.as_mut_ptr(), 8) };
        if count > 0 || std::time::Instant::now() > deadline {
            return count;
        }
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
}

#[test]
fn the_reader_s_own_thread_hears_the_queue_unasked() {
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    driver.play(&installed(&[queued(1000, 100), queued(1004, 200)]));
    assert_eq!(crate::qat_open(150), 1);
    let count = handed_soon();
    crate::qat_close();
    assert_eq!(count, 2, "heard with no poll, no move and no press draining it");
}

/// Longer than any test runs: the reader's own thread, past its first
/// drain, drains again only where it is woken.
const ASLEEP: std::time::Duration = std::time::Duration::from_secs(10);

/// A driver of `packets` whose output is 100 high: the fake's packets, at
/// its (40, 50), are the screen's (40, 49).
fn a_hundred_high(packets: &[Packet]) -> Script {
    let mut context = system_context();
    (context.0[OUT_ORIGIN + 1], context.0[OUT_EXTENT + 1]) = (0, 100);
    Script { has_pressure: true, pressure: axis(0, 1000), context, ..installed(packets) }
}

#[test]
fn a_poll_and_a_point_ask_the_driver_nothing() {
    // 🔬A call into the driver is a quarter of a millisecond (F-600): the
    // app's thread reads what was heard.
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    driver.play(&a_hundred_high(&[queued(1000, 100)]));
    assert!(wintab::open_drained_every(150, ASLEEP));
    wintab::drain();
    let before = driver.seen().asks;
    let mut room = [0.0f32; 64];
    for _ in 0..1000 {
        // SAFETY: room for eight records.
        let _ = unsafe { crate::qat_poll(room.as_mut_ptr(), 8) };
        let _ = pressures_at(1001, &[(40, 49, 1000), (40, 49, 1001)]);
    }
    let asks = driver.seen().asks - before;
    crate::qat_close();
    assert!(asks <= 1, "{asks} asks in a thousand polls and points — the reader's first drain at most");
}

#[test]
fn a_move_whose_packet_is_not_heard_yet_wakes_the_reader() {
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    // The pen at hand: a packet a moment before the move.
    driver.play(&a_hundred_high(&[queued(1000, 100)]));
    assert!(wintab::open_drained_every(150, ASLEEP));
    // The reader's own first drain hears it, and it sleeps from then.
    assert_eq!(handed_soon(), 1);
    // The packet that put the cursor at the move, queued as it moved.
    driver.play(&a_hundred_high(&[Packet { x: 60, ..queued(1004, 200) }]));
    // A message of two moves, the one before it heard: the other wakes it.
    let pressures = pressures_at(1005, &[(40, 49, 1000), (60, 49, 1004)]);
    let count = handed_soon();
    crate::qat_close();
    assert_eq!(pressures[0], 100.0 * (1.0 / 1000.0), "heard at the move before");
    assert!(pressures[1].is_nan(), "not heard at the move");
    assert_eq!(count, 1, "heard with the reader asleep for the test's length");
}

#[test]
fn a_move_with_no_pen_at_hand_wakes_no_reader() {
    let (driver, _turn) = driver();
    let _window = AppWindow::show();
    // The pen last heard two seconds before: a mouse's move is a mouse's.
    driver.play(&a_hundred_high(&[queued(1000, 100)]));
    assert!(wintab::open_drained_every(150, ASLEEP));
    // The reader's own first drain hears it, and it sleeps from then.
    assert_eq!(handed_soon(), 1);
    driver.play(&a_hundred_high(&[Packet { x: 60, ..queued(3004, 200) }]));
    let pressures = pressures_at(3005, &[(70, 49, 3004)]);
    let count = handed_within(std::time::Duration::from_millis(200));
    crate::qat_close();
    assert!(pressures[0].is_nan());
    assert_eq!(count, 0, "no drain but the reader's own, asleep");
}

#[test]
fn a_move_s_packet_heard_after_its_message_is_its_reading_as_the_app_reads_it() {
    let (driver, _turn) = driver();
    let window = AppWindow::show();
    // SAFETY: the time of the last message this thread took.
    let time = unsafe { GetMessageTime() } as u32;
    // A place no mouse is: the message's own move alone.
    let far: i16 = -20_000;
    let mut there = POINT { x: far.into(), y: far.into() };
    // SAFETY: the window shown, and a local.
    let _ = unsafe { ClientToScreen(window.0, &mut there) };
    let script = |packets: &[Packet]| Script {
        has_pressure: true,
        pressure: axis(0, 1000),
        has_orientation: true,
        orientation: [axis(0, 3599), axis(-900, 900), axis(0, 359)],
        context: running_down(),
        ..installed(packets)
    };
    // The pen at hand elsewhere: nothing heard at the move's place.
    driver.play(&script(&[queued(time.wrapping_sub(5), 100)]));
    assert!(wintab::open_drained_every(150, ASLEEP));
    wintab::drain();
    let word = (far as u16) as isize;
    crate::points_win::mouse(window.0, LPARAM(word | (word << 16)));
    // The packet that put the cursor there, heard after the message.
    let leaning = Packet { azimuth: 900, altitude: 450, twist: 90, ..queued(time.wrapping_sub(1), 250) };
    driver.play(&script(&[Packet { x: there.x, y: there.y, ..leaning }]));
    wintab::drain();
    let count = crate::qa_pen_points_take(crate::points::Kind::Mouse as i32, f64::from(far), f64::from(far));
    let mut words = [0.0; crate::points::POINT_WORDS];
    // SAFETY: room for one point.
    let read = unsafe { crate::qa_pen_points_taken(words.as_mut_ptr(), 1) };
    crate::qat_close();
    assert_eq!((count, read), (1, 1));
    let read_of_pen = [250.0 * (1.0 / 1000.0), 90.0, 0.5, 90.0];
    assert_eq!(words[6..], read_of_pen, "what the driver's packet says of the pen, as the point is read");
}

#[test]
fn a_press_drains_the_queue_before_its_point_is_read() {
    let (driver, _turn) = driver();
    let window = AppWindow::show();
    let script = installed(&[]);
    driver.play(&script);
    assert_eq!(crate::qat_open(150), 1);
    wintab::drain();
    // The pen touches down: its packet is queued as the press comes.
    driver.play(&installed(&[queued(1000, 900)]));
    crate::points_win::hear(window.0, WM_LBUTTONDOWN, WPARAM(0), LPARAM(0));
    let mut room = [0.0f32; 64];
    // SAFETY: room for eight records.
    let count = unsafe { crate::qat_poll(room.as_mut_ptr(), 8) };
    crate::qat_close();
    assert_eq!(count, 1, "the contact heard at the press, not a drain later");
}

#[test]
fn a_pen_s_points_are_given_the_driver_s_pressure_as_a_mouse_s_are() {
    let (driver, _turn) = driver();
    let window = AppWindow::show();
    // Each packet where the pen's points are, as the screen counts.
    let put = |time, pressure| Packet { x: -20_000, y: -20_000, ..queued(time, pressure) };
    let script = Script {
        has_pressure: true,
        pressure: axis(0, 1000),
        context: running_down(),
        ..installed(&[put(1000, 100), put(1010, 200), put(1020, 300)])
    };
    driver.play(&script);
    assert_eq!(crate::qat_open(20), 1);
    wintab::drain();
    let entry = |kind, time| POINTER_INFO {
        pointerType: kind,
        dwTime: time,
        ptPixelLocation: POINT { x: -20_000, y: -20_000 },
        PerformanceCount: 1,
        ..POINTER_INFO::default()
    };
    // The newest first, as the OS keeps a pointer's history.
    let history = [entry(PT_PEN, 1019), entry(PT_PEN, 1004), entry(PT_PEN, 900)];
    let points = crate::points_win::points_of(window.0, &history, None);
    let finger = crate::points_win::points_of(window.0, &[entry(PT_TOUCH, 1019)], None);
    crate::qat_close();
    let driven: Vec<u64> = points.iter().map(|point| pressure_of(&point.driven).to_bits()).collect();
    let want = [f64::NAN, 100.0 * (1.0 / 1000.0), 300.0 * (1.0 / 1000.0)];
    assert_eq!(driven, want.map(f64::to_bits), "the oldest first, each the packet at its place within 20 ms");
    assert!(finger[0].driven.is_none(), "a finger is not the pen");
    let asked: Vec<_> = points.iter().map(|point| point.asked).collect();
    let at = |time| Some((-20_000, -20_000, time));
    assert_eq!(asked, [at(900), at(1004), at(1019)], "asked again as the app reads them");
    assert_eq!(finger[0].asked, None);
}
