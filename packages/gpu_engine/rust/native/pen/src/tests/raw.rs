//! The Raw Input half: its life held to the C's — started, polled,
//! stopped — and its reading of a report on a HID parser's answers made up
//! here, where the C's reading has no way in.

use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::c_void;
use std::mem::offset_of;
use std::sync::{Mutex, PoisonError};

use windows::Win32::Foundation::HANDLE;
use windows::Win32::UI::Input::{RAWHID, RAWINPUT};

use crate::raw::{Device, Hid, ValueCaps, hid_reports};
use crate::report::snapshot;

/// The `qpr_*` exports of one observer.
#[derive(Clone, Copy)]
struct Observer {
    abi_version: unsafe extern "C" fn() -> i32,
    start: unsafe extern "C" fn() -> i32,
    stop: unsafe extern "C" fn(),
    poll: unsafe extern "C" fn(*mut f32, i32) -> i32,
}

const RUST: Observer = Observer {
    abi_version: crate::qpr_abi_version,
    start: crate::qpr_start,
    stop: crate::qpr_stop,
    poll: crate::qpr_poll,
};

fn c() -> Observer {
    // SAFETY: qa_penraw_win.c's declarations of each.
    unsafe {
        Observer {
            abi_version: oracle::sidecar_export("qa_tablet", "qpr_abi_version"),
            start: oracle::sidecar_export("qa_tablet", "qpr_start"),
            stop: oracle::sidecar_export("qa_tablet", "qpr_stop"),
            poll: oracle::sidecar_export("qa_tablet", "qpr_poll"),
        }
    }
}

/// Room no observer wrote: a NaN no report holds.
const UNWRITTEN: u32 = 0x7FC0_DEAD;

/// What a poll of `cap` floats answers, and how many it wrote — always the
/// first of them. Their values are a pen's, when one is in reach.
fn polled(observer: Observer, cap: i32) -> (i32, usize) {
    let mut room = [f32::from_bits(UNWRITTEN); 9];
    // SAFETY: room for `cap` floats.
    let answer = unsafe { (observer.poll)(room.as_mut_ptr(), cap) };
    let written = room.iter().take_while(|value| value.to_bits() != UNWRITTEN).count();
    assert!(room[written..].iter().all(|value| value.to_bits() == UNWRITTEN), "{room:?}");
    (answer, written)
}

#[derive(Debug, PartialEq)]
struct Life {
    abi: i32,
    before: Vec<(i32, usize)>,
    started: [i32; 2],
    live: Vec<(i32, usize)>,
    into_nothing: i32,
    after: Vec<(i32, usize)>,
}

fn life(observer: Observer) -> Life {
    let caps = [-1, 0, 1, 2, 3, 4, 5, 6, 7, 9];
    let polls = || caps.iter().map(|&cap| polled(observer, cap)).collect();
    // SAFETY: each export of its declaration.
    unsafe {
        let abi = (observer.abi_version)();
        let before = polls();
        let started = [(observer.start)(), (observer.start)()];
        let live = polls();
        let into_nothing = (observer.poll)(std::ptr::null_mut(), 7);
        (observer.stop)();
        (observer.stop)();
        Life { abi, before, started, live, into_nothing, after: polls() }
    }
}

#[test]
fn the_observers_life_is_the_cs() {
    // A process registers one window per collection: one observer at a time.
    static ONE_AT_A_TIME: Mutex<()> = Mutex::new(());
    let _turn = ONE_AT_A_TIME.lock().unwrap_or_else(PoisonError::into_inner);
    let theirs = life(c());
    let ours = life(RUST);
    assert_eq!(ours, theirs);
    assert_eq!((theirs.abi, theirs.started), (3, [1, 1]), "LIVENESS — the C's observer started");
    let written: Vec<_> = theirs.live.iter().map(|(_, written)| *written).collect();
    assert_eq!(written, [0, 0, 0, 2, 2, 2, 5, 5, 7, 7], "answers worked out here");
}

/// What the HID parser answers, and what it was handed.
#[derive(Default)]
struct Parser {
    refuses: bool,
    usages: Vec<u16>,
    /// How many usages it says it wrote, when not as many as it did.
    claims: Option<u32>,
    caps: HashMap<u16, Vec<ValueCaps>>,
    values: HashMap<u16, u32>,
    /// The reports and the first word of the device's data it was handed.
    reports: Vec<Vec<u8>>,
    data: Vec<u64>,
}

thread_local! {
    static PARSER: RefCell<Parser> = RefCell::new(Parser::default());
}

const SUCCESS: i32 = 0x0011_0000;
const NOT_THERE: i32 = 0xC011_0004_u32 as i32;

/// # Safety
/// As HidP_GetUsages.
unsafe extern "system" fn get_usages(
    _kind: i32,
    _page: u16,
    _link: u16,
    usages: *mut u16,
    count: *mut u32,
    data: *const c_void,
    report: *const u8,
    length: u32,
) -> i32 {
    PARSER.with(|parser| {
        let mut parser = parser.borrow_mut();
        // SAFETY: the caller's contract.
        unsafe {
            parser.data.push(data.cast::<u64>().read());
            parser.reports.push(std::slice::from_raw_parts(report, length as usize).to_vec());
            if parser.refuses {
                return NOT_THERE;
            }
            let given = parser.usages.len().min(*count as usize);
            usages.copy_from_nonoverlapping(parser.usages.as_ptr(), given);
            *count = parser.claims.unwrap_or(given as u32);
        }
        SUCCESS
    })
}

/// # Safety
/// As HidP_GetSpecificValueCaps.
unsafe extern "system" fn get_specific_value_caps(
    _kind: i32,
    _page: u16,
    _link: u16,
    usage: u16,
    caps: *mut ValueCaps,
    length: *mut u16,
    _data: *const c_void,
) -> i32 {
    PARSER.with(|parser| {
        let parser = parser.borrow();
        let Some(declared) = parser.caps.get(&usage) else {
            return NOT_THERE;
        };
        // SAFETY: the caller's contract.
        unsafe {
            let given = declared.len().min(*length as usize);
            caps.copy_from_nonoverlapping(declared.as_ptr(), given);
            *length = given as u16;
        }
        SUCCESS
    })
}

/// # Safety
/// As HidP_GetUsageValue.
unsafe extern "system" fn get_usage_value(
    _kind: i32,
    _page: u16,
    _link: u16,
    usage: u16,
    value: *mut u32,
    _data: *const c_void,
    _report: *const u8,
    _length: u32,
) -> i32 {
    PARSER.with(|parser| match parser.borrow().values.get(&usage) {
        Some(&raw) => {
            // SAFETY: the caller's contract.
            unsafe { value.write(raw) };
            SUCCESS
        }
        None => NOT_THERE,
    })
}

const HID: Hid = Hid {
    get_usages,
    get_specific_value_caps: Some(get_specific_value_caps),
    get_usage_value: Some(get_usage_value),
};

/// A value declared over `logical`, `bit_size` bits wide, in degrees to
/// the power `units_exp`.
fn caps(bit_size: u16, logical: (i32, i32), units_exp: u32) -> ValueCaps {
    let mut caps = ValueCaps::default();
    caps.bit_size = bit_size;
    caps.logical_min = logical.0;
    caps.logical_max = logical.1;
    caps.physical_min = logical.0;
    caps.physical_max = logical.1;
    caps.units = 0x14;
    caps.units_exp = units_exp;
    caps
}

/// A pen whose X Tilt counts in hundredths of a degree, its Y Tilt in
/// degrees over a byte, and its twist in degrees.
fn pen() -> Parser {
    Parser {
        usages: vec![0x42, 0x45],
        caps: HashMap::from([
            (0x3D, vec![caps(16, (-9000, 9000), 0x0E)]),
            (0x3E, vec![caps(8, (-90, 90), 0)]),
            (0x41, vec![caps(9, (0, 359), 0)]),
        ]),
        values: HashMap::from([(0x3D, 4500), (0x3E, 0x100 - 30), (0x41, 270)]),
        ..Parser::default()
    }
}

/// What `hid` reads of `report` on a device of `parser`'s, as a snapshot of
/// seven floats.
fn read(parser: Parser, hid: Hid, report: &[u8]) -> Option<[f32; 7]> {
    PARSER.with(|kept| *kept.borrow_mut() = parser);
    let device = Device::declared(&hid, 7, vec![0xFEED, 0]);
    let (flags, pose) = device.read(&hid, report)?;
    let mut out = [f32::NAN; 7];
    snapshot(flags, 0, pose, &mut out);
    Some(out)
}

#[test]
fn a_report_reads_its_buttons_lean_and_twist() {
    let read = read(pen(), HID, &[9, 8, 7, 6, 5]);
    assert_eq!(read, Some([5.0, 0.0, 45.0, -30.0, 1.0, 270.0, 1.0]));
    PARSER.with(|parser| {
        let parser = parser.borrow();
        assert_eq!(parser.reports, [vec![9, 8, 7, 6, 5]], "the report, whole");
        assert_eq!(parser.data, [0xFEED], "the device's own data");
    });
}

#[test]
fn a_lean_is_two_tilts() {
    for alone in [0x3D, 0x3E] {
        let mut parser = pen();
        parser.caps.retain(|&usage, _| usage != alone);
        let read = read(parser, HID, &[1]).expect("a report");
        assert_eq!(&read[2..], &[0.0, 0.0, 0.0, 270.0, 1.0], "without {alone:#x}");
    }
    for missing in [0x3D, 0x3E] {
        let mut parser = pen();
        parser.values.remove(&missing);
        let read = read(parser, HID, &[1]).expect("a report");
        assert_eq!(&read[2..], &[0.0, 0.0, 0.0, 270.0, 1.0], "a report without {missing:#x}");
    }
}

#[test]
fn a_report_without_a_twist_carries_none() {
    let mut parser = pen();
    parser.values.remove(&0x41);
    assert_eq!(read(parser, HID, &[1]).map(|read| [read[5], read[6]]), Some([0.0, 0.0]));
    let mut parser = pen();
    parser.caps.remove(&0x41);
    assert_eq!(read(parser, HID, &[1]).map(|read| [read[5], read[6]]), Some([0.0, 0.0]));
}

#[test]
fn what_declares_no_angle_reads_none() {
    let mut parser = pen();
    for declared in parser.caps.values_mut() {
        declared[0].units = 0;
    }
    assert_eq!(read(parser, HID, &[1]), Some([5.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]));
}

#[test]
fn the_first_declaration_is_the_pens() {
    let mut parser = pen();
    let other = caps(16, (-90, 90), 0);
    parser.caps.get_mut(&0x3D).expect("X Tilt").push(other);
    assert_eq!(read(parser, HID, &[1]).map(|read| read[2]), Some(45.0));
    let mut parser = pen();
    parser.caps.insert(0x3D, vec![]);
    assert_eq!(read(parser, HID, &[1]).map(|read| read[4]), Some(0.0), "declared nowhere");
}

#[test]
fn without_the_parsers_value_entries_the_buttons_alone() {
    let hid = Hid { get_specific_value_caps: None, ..HID };
    assert_eq!(read(pen(), hid, &[1]), Some([5.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]));
    let hid = Hid { get_usage_value: None, ..HID };
    assert_eq!(read(pen(), hid, &[1]), Some([5.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]));
}

#[test]
fn a_report_the_parser_refuses_is_not_read() {
    let parser = Parser { refuses: true, ..pen() };
    assert_eq!(read(parser, HID, &[1]), None);
}

#[test]
fn a_parser_is_not_read_past_the_room_it_was_handed() {
    let mut usages = vec![0x30; 32];
    usages[0] = 0x44;
    usages[31] = 0x42;
    let parser = Parser { usages, claims: Some(40), ..pen() };
    assert_eq!(read(parser, HID, &[1]).map(|read| read[0]), Some(3.0));
}

/// A raw input of `kind` holding `count` reports of `stride` bytes, the
/// system's bytes for them `reports`, and how many bytes it says it wrote.
fn input(kind: u32, stride: u32, count: u32, reports: &[u8]) -> (Vec<u64>, usize) {
    let first = offset_of!(RAWINPUT, data) + offset_of!(RAWHID, bRawData);
    let size = first + reports.len();
    let mut words = vec![0u64; size.max(size_of::<RAWINPUT>()).div_ceil(8)];
    let mut raw = RAWINPUT::default();
    raw.header.dwType = kind;
    raw.header.hDevice = HANDLE(0x1234 as *mut c_void);
    raw.data.hid = RAWHID { dwSizeHid: stride, dwCount: count, bRawData: [0] };
    // SAFETY: room for a RAWINPUT and the reports after its first byte.
    unsafe {
        words.as_mut_ptr().cast::<RAWINPUT>().write(raw);
        let bytes = words.as_mut_ptr().cast::<u8>().add(first);
        bytes.copy_from_nonoverlapping(reports.as_ptr(), reports.len());
    }
    (words, size)
}

#[test]
fn a_hid_input_holds_its_reports() {
    let written: &[u8] = &[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
    let (words, size) = input(2, 4, 3, written);
    let (device, reports, stride) = hid_reports(&words, size).expect("a HID input");
    assert_eq!((device, reports, stride), (0x1234, written, 4));
}

#[test]
fn reports_are_read_only_where_the_system_wrote() {
    let (words, size) = input(2, 4, 3, &[0; 12]);
    assert!(hid_reports(&words, size - 1).is_none(), "one byte short");
    let (words, size) = input(2, 4, 4, &[0; 12]);
    assert!(hid_reports(&words, size).is_none(), "one report more than written");
    let (words, size) = input(2, u32::MAX, u32::MAX, &[0; 12]);
    assert!(hid_reports(&words, size).is_none(), "more than there could be");
    let (words, size) = input(2, 4, 3, &[0; 12]);
    assert!(hid_reports(&words[..2], size).is_none(), "less room than an input");
}

#[test]
fn only_a_hid_input_with_reports_is_read() {
    let (words, size) = input(0, 4, 3, &[0; 12]);
    assert!(hid_reports(&words, size).is_none(), "a mouse's");
    let (words, size) = input(2, 4, 0, &[0; 12]);
    assert!(hid_reports(&words, size).is_none(), "no report");
    let (words, size) = input(2, 0, 3, &[0; 12]);
    assert!(hid_reports(&words, size).is_none(), "reports of no length");
}
