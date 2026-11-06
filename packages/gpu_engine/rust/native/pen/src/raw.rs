//! The pen's BUTTON truth out of the HID digitizer report itself,
//! underneath Windows Ink and underneath Wintab. The HID usage tables
//! define each of these as its own usage on page 0x0D:
//!
//!   0x42 Tip Switch   0x44 Barrel Switch   0x45 Eraser
//!   0x3C Invert       0x5A Secondary Barrel Switch
//!
//! so "the barrel is down" and "this is the eraser end" arrive as bits the
//! hardware DECLARES, not as something inferred from pressure or from a
//! vendor-specific cursor index. That is the whole reason this exists:
//! Windows Ink rewrites a barrel press into a phantom pen tap before Flutter
//! ever sees it, and Wintab has no portable eraser test (CSR_TYPE is
//! manufacturer-defined, and Wacom's own docs warn it answers with garbage
//! on a freshly plugged tablet).
//!
//! And the pen's LEAN (desktop-pen-tilt): X Tilt 0x3D and Y Tilt 0x3E, read
//! in the unit the descriptor declares (hid_axis.rs). Flutter's Windows
//! embedder takes POINTER_PEN_INFO's pressure and rotation and drops its
//! tilt, so a brush that leans with the pen had nothing to read. And its
//! TWIST (F-176-Q9): Twist 0x41, the turn of the pen about its own barrel —
//! what a Wacom Art Pen reports as it rolls in the fingers — read the same
//! way. A pen that cannot turn reports none, or a constant 0 on a tablet
//! that declares the axis for the pens that can.
//!
//! WHERE A PEN REPORTS: page 0x0D names two top-level collections a pen's
//! report comes through — Pen 0x02, a Windows tablet's own pen, and
//! Digitizer 0x01, an external tablet's. A Wacom Cintiq 24 (DTH246, its own
//! driver, Windows Ink on; measured 2026-10-21) declares both and sends
//! every report, tilt included, through the Digitizer one alone. Listening
//! to Pen only, this reader heard nothing there, and the brush that leans
//! with the pen drew upright (F-176-Q8). So it listens to both.
//!
//! PURE OBSERVATION, by construction:
//! - A message-only window on its OWN thread receives WM_INPUT. Flutter's
//!   window and message loop are never touched, so nothing here can change
//!   how input is delivered to the app.
//! - RIDEV_INPUTSINK, and NEVER RIDEV_NOLEGACY: the legacy WM_MOUSE*
//!   messages are what the whole app actually runs on, and asking the
//!   system to stop sending them would brick it exactly the way the
//!   non-system Wintab context did.
//! - hid.dll is loaded DYNAMICALLY and its absence is a normal silent
//!   state, as wintab32.dll's is.

use std::cell::RefCell;
use std::ffi::c_void;
use std::mem::offset_of;
use std::os::windows::io::AsRawHandle;
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicI64, Ordering};
use std::sync::mpsc::{self, Sender};
use std::sync::{Mutex, PoisonError};
use std::thread::JoinHandle;
use std::time::Duration;

use windows::Win32::Foundation::{
    ERROR_CLASS_ALREADY_EXISTS, GetLastError, HANDLE, HWND, LPARAM, LRESULT, WPARAM,
};
use windows::Win32::System::LibraryLoader::{GetModuleHandleW, GetProcAddress, LoadLibraryW};
use windows::Win32::System::Threading::{GetThreadId, WaitForSingleObject};
use windows::Win32::UI::Input::{
    GetRawInputData, GetRawInputDeviceInfoW, HRAWINPUT, RAWHID, RAWINPUT, RAWINPUTDEVICE,
    RAWINPUTHEADER, RID_INPUT, RIDEV_INPUTSINK, RIDEV_REMOVE, RIDI_PREPARSEDDATA, RIM_TYPEHID,
    RegisterRawInputDevices,
};
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, DispatchMessageW, GetMessageW, HWND_MESSAGE,
    MSG, PostThreadMessageW, RegisterClassW, TranslateMessage, WM_INPUT, WM_QUIT, WNDCLASSW,
};
use windows::core::{PCSTR, s, w};

use crate::hid_axis::Axis;
use crate::report::{self, PAGE_DIGITIZER, USAGE_TWIST, USAGE_X_TILT, USAGE_Y_TILT};

const STATUS_SUCCESS: i32 = 0x0011_0000;
const REPORT_TYPE_INPUT: i32 = 0;

/// HIDP_VALUE_CAPS: the declaration of one value — its range, its unit.
/// Every field is at most four bytes wide and none is a pointer, so the
/// layout is the same 72 bytes in a 32-bit and a 64-bit process.
#[repr(C)]
#[derive(Clone, Copy, Default)]
pub(crate) struct ValueCaps {
    usage_page: u16,
    report_id: u8,
    is_alias: u8,
    bit_field: u16,
    link_collection: u16,
    link_usage: u16,
    link_usage_page: u16,
    is_range: u8,
    is_string_range: u8,
    is_designator_range: u8,
    is_absolute: u8,
    has_null: u8,
    reserved: u8,
    pub(crate) bit_size: u16,
    report_count: u16,
    reserved2: [u16; 5],
    pub(crate) units_exp: u32,
    pub(crate) units: u32,
    pub(crate) logical_min: i32,
    pub(crate) logical_max: i32,
    pub(crate) physical_min: i32,
    pub(crate) physical_max: i32,
    /// The NotRange / Range union; not read here.
    usage_or_range: [u16; 8],
}

const _: () = assert!(size_of::<ValueCaps>() == 72);

pub(crate) type GetUsages =
    unsafe extern "system" fn(i32, u16, u16, *mut u16, *mut u32, *const c_void, *const u8, u32)
        -> i32;
pub(crate) type GetSpecificValueCaps =
    unsafe extern "system" fn(i32, u16, u16, u16, *mut ValueCaps, *mut u16, *const c_void) -> i32;
pub(crate) type GetUsageValue = unsafe extern "system" fn(
    i32,
    u16,
    u16,
    u16,
    *mut u32,
    *const c_void,
    *const u8,
    u32,
) -> i32;

/// hid.dll's parsing entry points: the buttons need the first, the lean
/// and the twist the other two, which are allowed to be missing.
#[derive(Clone, Copy)]
pub(crate) struct Hid {
    pub(crate) get_usages: GetUsages,
    pub(crate) get_specific_value_caps: Option<GetSpecificValueCaps>,
    pub(crate) get_usage_value: Option<GetUsageValue>,
}

impl Hid {
    fn load() -> Option<Self> {
        // SAFETY: a library loaded by name; nothing runs but its entry.
        let library = unsafe { LoadLibraryW(w!("hid.dll")) }.ok()?;
        let find = |name: PCSTR| {
            // SAFETY: the library just loaded, which stays loaded.
            unsafe { GetProcAddress(library, name) }
        };
        let Some(get_usages) = find(s!("HidP_GetUsages")) else {
            // SAFETY: the library this loaded, and nothing of it kept.
            let _ = unsafe { windows::Win32::Foundation::FreeLibrary(library) };
            return None;
        };
        // SAFETY: each is the entry point of its name, of hidpi.h's
        // declaration.
        unsafe {
            Some(Self {
                get_usages: std::mem::transmute::<_, GetUsages>(get_usages),
                get_specific_value_caps: find(s!("HidP_GetSpecificValueCaps"))
                    .map(|entry| std::mem::transmute::<_, GetSpecificValueCaps>(entry)),
                get_usage_value: find(s!("HidP_GetUsageValue"))
                    .map(|entry| std::mem::transmute::<_, GetUsageValue>(entry)),
            })
        }
    }
}

/// One digitizer's preparsed data and the axes it declares. Preparsed data
/// is per DEVICE and immutable, so one is kept for the normal case (a
/// single pen digitizer): a different device simply replaces it.
pub(crate) struct Device {
    handle: isize,
    /// As the system hands it, in words: room aligned for what reads it.
    preparsed: Vec<u64>,
    /// A lean is two tilts: a device that declares one alone reports none.
    tilt: Option<(Axis, Axis)>,
    twist: Option<Axis>,
}

impl Device {
    pub(crate) fn declared(hid: &Hid, handle: isize, preparsed: Vec<u64>) -> Self {
        let data = preparsed.as_ptr().cast();
        let tilt = axis_of(hid, data, USAGE_X_TILT)
            .and_then(|x| axis_of(hid, data, USAGE_Y_TILT).map(|y| (x, y)));
        let twist = axis_of(hid, data, USAGE_TWIST);
        Self { handle, preparsed, tilt, twist }
    }

    /// The flag word and the pose of `report`; None when it is not one
    /// the device declares.
    pub(crate) fn read(&self, hid: &Hid, report: &[u8]) -> Option<(i32, i64)> {
        let data = self.preparsed.as_ptr().cast();
        let mut usages = [0u16; 32];
        let mut count = usages.len() as u32;
        // SAFETY: room for `count` usages, this device's data and a report
        // of its length.
        let status = unsafe {
            (hid.get_usages)(
                REPORT_TYPE_INPUT,
                PAGE_DIGITIZER,
                0,
                usages.as_mut_ptr(),
                &mut count,
                data,
                report.as_ptr(),
                report.len() as u32,
            )
        };
        if status != STATUS_SUCCESS {
            return None;
        }
        let flags = report::flags(&usages[..(count as usize).min(usages.len())]);
        let angle = |usage: u16, axis: &Axis| angle_in(hid, data, report, usage, axis);
        let tilt = self.tilt.and_then(|(x, y)| {
            angle(USAGE_X_TILT, &x).and_then(|x| angle(USAGE_Y_TILT, &y).map(|y| (x, y)))
        });
        let twist = self.twist.and_then(|axis| angle(USAGE_TWIST, &axis));
        Some((flags, report::pose(tilt, twist)))
    }
}

/// How `usage` is declared on `preparsed`; None when the device declares
/// no such value.
fn axis_of(hid: &Hid, preparsed: *const c_void, usage: u16) -> Option<Axis> {
    let get = hid.get_specific_value_caps?;
    // Room for a device that declares the usage in more than one report;
    // the pen's own is the first.
    let mut caps = [ValueCaps::default(); 8];
    let mut length = caps.len() as u16;
    // SAFETY: room for `length` declarations, and a device's data.
    let status = unsafe {
        get(REPORT_TYPE_INPUT, PAGE_DIGITIZER, 0, usage, caps.as_mut_ptr(), &mut length, preparsed)
    };
    if status != STATUS_SUCCESS || length == 0 {
        return None;
    }
    let caps = caps[0];
    Some(Axis {
        bit_size: u32::from(caps.bit_size),
        logical_min: caps.logical_min,
        logical_max: caps.logical_max,
        physical_min: caps.physical_min,
        physical_max: caps.physical_max,
        units: caps.units,
        units_exp: caps.units_exp,
    })
}

/// `usage`'s angle in `report`, in degrees; None when the report carries
/// none (another report ID) or its axis declares no angle.
fn angle_in(
    hid: &Hid,
    preparsed: *const c_void,
    report: &[u8],
    usage: u16,
    axis: &Axis,
) -> Option<f64> {
    let get = hid.get_usage_value?;
    let mut raw = 0u32;
    // SAFETY: a device's data and a report of its length.
    let status = unsafe {
        get(
            REPORT_TYPE_INPUT,
            PAGE_DIGITIZER,
            0,
            usage,
            &mut raw,
            preparsed,
            report.as_ptr(),
            report.len() as u32,
        )
    };
    if status != STATUS_SUCCESS {
        return None;
    }
    axis.degrees(raw)
}

pub(crate) static STARTED: AtomicBool = AtomicBool::new(false);
// The latest decoded report. The counter lets Dart tell "nothing new" from
// "a report that happens to repeat the previous flags".
pub(crate) static FLAGS: AtomicI32 = AtomicI32::new(0);
static SEQUENCE: AtomicI32 = AtomicI32::new(0);
pub(crate) static POSE: AtomicI64 = AtomicI64::new(0);

struct Observer {
    hid: Option<Hid>,
    thread: Option<JoinHandle<()>>,
}

static OBSERVER: Mutex<Observer> = Mutex::new(Observer { hid: None, thread: None });

thread_local! {
    /// What the observer thread reads reports with, and the device it last
    /// read — on that thread alone, so nothing else ever sees it.
    static READING: RefCell<Option<(Hid, Option<Device>)>> = const { RefCell::new(None) };
}

/// Starts the observer thread. True when raw pen reports will flow.
/// Idempotent; a machine without hid.dll or without a digitizer simply
/// answers false and stays silent.
pub(crate) fn start() -> bool {
    if STARTED.load(Ordering::SeqCst) {
        return true;
    }
    let mut observer = OBSERVER.lock().unwrap_or_else(PoisonError::into_inner);
    if observer.hid.is_none() {
        observer.hid = Hid::load();
    }
    let Some(hid) = observer.hid else {
        return false;
    };
    if observer.thread.is_some() {
        return false; // A previous thread is still winding down.
    }
    let (ready, registered) = mpsc::channel();
    let Ok(thread) = std::thread::Builder::new()
        .name("pen raw input".into())
        .spawn(move || observe(hid, ready))
    else {
        return false;
    };
    observer.thread = Some(thread);
    // The registration either succeeded or failed by the time the thread
    // signals; 2s is a generous ceiling for window creation.
    let _ = registered.recv_timeout(Duration::from_secs(2));
    STARTED.load(Ordering::SeqCst)
}

pub(crate) fn stop() {
    let mut observer = OBSERVER.lock().unwrap_or_else(PoisonError::into_inner);
    let Some(thread) = observer.thread.take() else {
        return;
    };
    let handle = HANDLE(thread.as_raw_handle());
    // SAFETY: the thread's own handle, open while `thread` is.
    unsafe {
        let _ = PostThreadMessageW(GetThreadId(handle), WM_QUIT, WPARAM(0), LPARAM(0));
        WaitForSingleObject(handle, 2000);
    }
    FLAGS.store(0, Ordering::SeqCst);
    POSE.store(0, Ordering::SeqCst);
}

/// Snapshots the newest decoded report into `out` ([`report::snapshot`]).
/// False when the observer is not live.
pub(crate) fn poll(out: &mut [f32]) -> bool {
    if !STARTED.load(Ordering::SeqCst) {
        return false;
    }
    let flags = FLAGS.load(Ordering::SeqCst);
    let sequence = SEQUENCE.load(Ordering::SeqCst);
    report::snapshot(flags, sequence, POSE.load(Ordering::SeqCst), out);
    true
}

/// The observer thread: a message-only window that both collections a pen
/// reports through are delivered to, until WM_QUIT.
fn observe(hid: Hid, ready: Sender<()>) {
    READING.with(|reading| *reading.borrow_mut() = Some((hid, None)));
    // SAFETY: this module, a class of it, and a message-only window of that
    // class on this thread, destroyed on it.
    unsafe {
        let Ok(module) = GetModuleHandleW(None) else {
            return;
        };
        let class = w!("AnicelPenRawSink");
        let kind = WNDCLASSW {
            lpfnWndProc: Some(answer),
            hInstance: module.into(),
            lpszClassName: class,
            ..Default::default()
        };
        // A duplicate class registration across restarts is fine; only a
        // real failure matters.
        if RegisterClassW(&kind) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS {
            return;
        }
        let Ok(window) = CreateWindowExW(
            Default::default(),
            class,
            None,
            Default::default(),
            0,
            0,
            0,
            0,
            Some(HWND_MESSAGE),
            None,
            Some(module.into()),
            None,
        ) else {
            return;
        };
        // INPUTSINK = deliver even when this (invisible) window is not in the
        // foreground. NOLEGACY is deliberately absent — see the module's head.
        let devices = [report::USAGE_PEN, report::USAGE_DIGITIZER].map(|usage| RAWINPUTDEVICE {
            usUsagePage: PAGE_DIGITIZER,
            usUsage: usage,
            dwFlags: RIDEV_INPUTSINK,
            hwndTarget: window,
        });
        let size = size_of::<RAWINPUTDEVICE>() as u32;
        if RegisterRawInputDevices(&devices, size).is_err() {
            let _ = DestroyWindow(window);
            return;
        }
        STARTED.store(true, Ordering::SeqCst);
        let _ = ready.send(());

        let mut message = MSG::default();
        while GetMessageW(&mut message, None, 0, 0).0 > 0 {
            let _ = TranslateMessage(&message);
            DispatchMessageW(&message);
        }

        // Unregister before the target window dies.
        let removed = devices.map(|device| RAWINPUTDEVICE {
            dwFlags: RIDEV_REMOVE,
            hwndTarget: HWND::default(),
            ..device
        });
        let _ = RegisterRawInputDevices(&removed, size);
        let _ = DestroyWindow(window);
    }
    STARTED.store(false, Ordering::SeqCst);
}

unsafe extern "system" fn answer(window: HWND, message: u32, w: WPARAM, l: LPARAM) -> LRESULT {
    if message == WM_INPUT {
        take(HRAWINPUT(l.0 as *mut c_void));
    }
    // The system still needs its cleanup pass for WM_INPUT.
    // SAFETY: what the system handed this window.
    unsafe { DefWindowProcW(window, message, w, l) }
}

/// Reads the reports of one WM_INPUT into the latest.
fn take(input: HRAWINPUT) {
    let header = size_of::<RAWINPUTHEADER>() as u32;
    let mut size = 0u32;
    // SAFETY: a size query, writing nothing.
    if unsafe { GetRawInputData(input, RID_INPUT, None, &mut size, header) } != 0 || size == 0 {
        return;
    }
    let mut words = vec![0u64; (size as usize).max(size_of::<RAWINPUT>()).div_ceil(8)];
    let room = words.as_mut_ptr().cast();
    // SAFETY: room for the size just given.
    if unsafe { GetRawInputData(input, RID_INPUT, Some(room), &mut size, header) } != size {
        return;
    }
    let Some((handle, reports, stride)) = hid_reports(&words, size as usize) else {
        return;
    };
    READING.with(|reading| {
        let mut reading = reading.borrow_mut();
        let Some((hid, kept)) = reading.as_mut() else {
            return;
        };
        let Some(device) = known(hid, kept, handle) else {
            return;
        };
        for report in reports.chunks_exact(stride) {
            let Some((flags, pose)) = device.read(hid, report) else {
                continue;
            };
            POSE.store(pose, Ordering::SeqCst);
            FLAGS.store(flags, Ordering::SeqCst);
            SEQUENCE.fetch_add(1, Ordering::SeqCst);
        }
    });
}

/// The device, the reports and their length of a HID input, as the system
/// wrote it: `size` bytes of `words`. None for any other input, or one
/// that holds no report.
pub(crate) fn hid_reports(words: &[u64], size: usize) -> Option<(isize, &[u8], usize)> {
    if words.len() * 8 < size.max(size_of::<RAWINPUT>()) {
        return None;
    }
    // SAFETY: room for a RAWINPUT, aligned for it.
    let raw = unsafe { &*words.as_ptr().cast::<RAWINPUT>() };
    if raw.header.dwType != RIM_TYPEHID.0 {
        return None;
    }
    // SAFETY: a HID input's data is its `hid`.
    let hid = unsafe { raw.data.hid };
    let (count, stride) = (hid.dwCount as usize, hid.dwSizeHid as usize);
    if count == 0 || stride == 0 {
        return None;
    }
    // SAFETY: the words' own bytes, `size` of them.
    let bytes = unsafe { std::slice::from_raw_parts(words.as_ptr().cast::<u8>(), size) };
    // ⛔THE REPORTS ARE READ ONLY WHERE THE SYSTEM WROTE: the C stepped
    // `count` strides on from the first without a look at the size it was
    // handed (native-memory-safety).
    let first = offset_of!(RAWINPUT, data) + offset_of!(RAWHID, bRawData);
    // Two 32-bit counts: their product and the offset fit a 64-bit size.
    let reports = bytes.get(first..first + count * stride)?;
    Some((raw.header.hDevice.0 as isize, reports, stride))
}

/// The device `handle` is, from what was kept or asked of the system; None
/// when the system gives no preparsed data for it.
fn known<'a>(hid: &Hid, kept: &'a mut Option<Device>, handle: isize) -> Option<&'a Device> {
    if kept.as_ref().is_some_and(|device| device.handle == handle) {
        return kept.as_ref();
    }
    let device = Some(HANDLE(handle as *mut c_void));
    let mut size = 0u32;
    // SAFETY: a size query, writing nothing.
    let asked = unsafe { GetRawInputDeviceInfoW(device, RIDI_PREPARSEDDATA, None, &mut size) };
    if asked != 0 || size == 0 {
        return None;
    }
    let mut preparsed = vec![0u64; (size as usize).div_ceil(8)];
    let room = preparsed.as_mut_ptr().cast();
    // SAFETY: room for the size just given.
    let got = unsafe { GetRawInputDeviceInfoW(device, RIDI_PREPARSEDDATA, Some(room), &mut size) };
    if got == u32::MAX {
        return None;
    }
    *kept = Some(Device::declared(hid, handle, preparsed));
    kept.as_ref()
}
