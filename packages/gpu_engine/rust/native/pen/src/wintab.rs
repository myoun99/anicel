//! The tablet DRIVER's word (PEN-2): pressure, lean and twist through
//! wintab32.dll, bypassing the OS pointer classification entirely. The app
//! keeps consuming Flutter's pointer events for position and gestures; this
//! supplies the driver's pressure and tilt stream, so a pen that the OS
//! misreports (as touch or mouse) still paints with full pressure.
//!
//! - wintab32.dll is loaded DYNAMICALLY; a machine without a driver is a
//!   normal, silent state (`qat_available` 0) — never a link error.
//! - Dart POLLS the packet queue (no window subclassing, no message pump
//!   dependency): WTPacketsGet drains without CXO_MESSAGES.
//! - The Wintab structs and constants are declared here (the vendor header
//!   set is not in the Windows SDK; the LOGCONTEXT layout and the PK_*
//!   serialization order are stable, documented ABI).

use std::ffi::c_void;
use std::sync::{Mutex, PoisonError};

use windows::Win32::Foundation::{FreeLibrary, HMODULE, HWND, LPARAM};
use windows::Win32::System::LibraryLoader::{GetProcAddress, LoadLibraryW};
use windows::Win32::System::Threading::GetCurrentProcessId;
use windows::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GW_OWNER, GetWindow, GetWindowThreadProcessId, IsWindowVisible,
};
use windows::core::{BOOL, PCSTR, s, w};

const WTI_DEFSYSCTX: u32 = 4;
const WTI_DEVICES: u32 = 100;
const DVC_NAME: u32 = 1;
const DVC_NPRESSURE: u32 = 15;
const DVC_ORIENTATION: u32 = 17;

const CXO_SYSTEM: u32 = 0x0001;

// WTPKT field bits — a packet serializes its fields in ASCENDING bit order,
// and [`Packet`] lists them in exactly that order.
const PK_TIME: u32 = 0x0004;
const PK_BUTTONS: u32 = 0x0040;
const PK_X: u32 = 0x0080;
const PK_Y: u32 = 0x0100;
const PK_NORMAL_PRESSURE: u32 = 0x0400;
const PK_ORIENTATION: u32 = 0x1000;
const PACKET_DATA: u32 =
    PK_TIME | PK_BUTTONS | PK_X | PK_Y | PK_NORMAL_PRESSURE | PK_ORIENTATION;

/// AXIS: a device axis's range, unit and resolution.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub(crate) struct Axis {
    pub(crate) min: i32,
    pub(crate) max: i32,
    units: i32,
    resolution: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub(crate) struct Orientation {
    pub(crate) azimuth: i32,
    pub(crate) altitude: i32,
    pub(crate) twist: i32,
}

/// The packet [`PACKET_DATA`] asks for, in its serialization order.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub(crate) struct Packet {
    pub(crate) time: u32,
    pub(crate) buttons: u32,
    x: i32,
    y: i32,
    pub(crate) normal_pressure: u32,
    pub(crate) orientation: Orientation,
}

/// LOGCONTEXTW: the documented, fixed Wintab context layout.
#[repr(C)]
struct LogContext {
    name: [u16; 40],
    options: u32,
    status: u32,
    locks: u32,
    message_base: u32,
    device: u32,
    packet_rate: u32,
    packet_data: u32,
    packet_mode: u32,
    move_mask: u32,
    button_down_mask: u32,
    button_up_mask: u32,
    in_origin: [i32; 3],
    in_extent: [i32; 3],
    out_origin: [i32; 3],
    out_extent: [i32; 3],
    sensitivity: [u32; 3],
    system_mode: i32,
    system_origin: [i32; 2],
    system_extent: [i32; 2],
    system_sensitivity: [u32; 2],
}

const _: () = assert!(size_of::<Axis>() == 16);
const _: () = assert!(size_of::<Packet>() == 32);
const _: () = assert!(size_of::<LogContext>() == 212);

type WtInfoW = unsafe extern "system" fn(u32, u32, *mut c_void) -> u32;
type WtOpenW = unsafe extern "system" fn(HWND, *mut LogContext, BOOL) -> *mut c_void;
type WtClose = unsafe extern "system" fn(*mut c_void) -> BOOL;
type WtPacketsGet = unsafe extern "system" fn(*mut c_void, i32, *mut Packet) -> i32;
type WtQueueSizeSet = unsafe extern "system" fn(*mut c_void, i32) -> i32;

/// wintab32.dll's entry points, once it has loaded with the four the pen
/// cannot go without.
#[derive(Clone, Copy)]
struct Driver {
    info: WtInfoW,
    open: WtOpenW,
    close: WtClose,
    packets_get: WtPacketsGet,
    queue_size_set: Option<WtQueueSizeSet>,
}

impl Driver {
    fn load() -> Option<Self> {
        // SAFETY: a library loaded by name; nothing runs but its entry.
        let library = unsafe { LoadLibraryW(w!("wintab32.dll")) }.ok()?;
        let find = |name: PCSTR| {
            // SAFETY: the library just loaded, which stays loaded.
            unsafe { GetProcAddress(library, name) }
        };
        let (Some(info), Some(open), Some(close), Some(packets_get)) = (
            find(s!("WTInfoW")),
            find(s!("WTOpenW")),
            find(s!("WTClose")),
            find(s!("WTPacketsGet")),
        ) else {
            free(library);
            return None;
        };
        // SAFETY: each is the entry point of its name, of Wintab's
        // declaration.
        unsafe {
            Some(Self {
                info: std::mem::transmute::<_, WtInfoW>(info),
                open: std::mem::transmute::<_, WtOpenW>(open),
                close: std::mem::transmute::<_, WtClose>(close),
                packets_get: std::mem::transmute::<_, WtPacketsGet>(packets_get),
                queue_size_set: find(s!("WTQueueSizeSet"))
                    .map(|entry| std::mem::transmute::<_, WtQueueSizeSet>(entry)),
            })
        }
    }

    /// `T`, the answer to `category` and `index`, when the driver gives one.
    fn info<T: Default>(&self, category: u32, index: u32) -> Option<T> {
        let mut answer = T::default();
        // SAFETY: room for the answer Wintab declares for each asked here.
        let size = unsafe { (self.info)(category, index, (&raw mut answer).cast()) };
        (size != 0).then_some(answer)
    }

    /// Whether WTInfo reports an installed driver and device.
    fn answers(&self) -> bool {
        // SAFETY: a size query, writing nothing.
        unsafe { (self.info)(0, 0, std::ptr::null_mut()) != 0 }
    }
}

fn free(library: HMODULE) {
    // SAFETY: a library this loaded, and nothing of it kept.
    let _ = unsafe { FreeLibrary(library) };
}

/// What `qat_poll` makes of a packet, read off the device's axes when the
/// context opened.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Scales {
    pressure: f64,
    /// How many units the azimuth's full circle counts — tenths of a degree
    /// on every driver seen, but the axis says so — and the altitude that is
    /// a right angle; None while the device declares no orientation.
    /// ⛔These defaulted to 900 once, and a pen with no tilt sensor then read
    /// altitude 0/900 on every packet: lying flat, a lean nobody measured
    /// (desktop-pen-tilt).
    lean: Option<(i32, i32)>,
    /// How many units the twist's full circle counts; None while the device
    /// declares no twist axis, which is most pens: an Art Pen's barrel turns.
    twist: Option<i32>,
}

/// How many units a full circle of `axis` counts, when it declares one. A
/// range so wide its count wraps declares none, as it did in the C.
fn circle(axis: Axis) -> Option<i32> {
    let units = axis.max.wrapping_sub(axis.min).wrapping_add(1);
    (axis.max > axis.min && units > 0).then_some(units)
}

impl Scales {
    pub(crate) fn of(pressure: Option<Axis>, orientation: Option<[Axis; 3]>) -> Self {
        let pressure = match pressure {
            Some(axis) if axis.max > axis.min => 1.0 / f64::from(axis.max.wrapping_sub(axis.min)),
            _ => 1.0 / 1023.0,
        };
        let lean = orientation.and_then(|[azimuth, altitude, _]| {
            circle(azimuth).filter(|_| altitude.max > 0).map(|span| (span, altitude.max))
        });
        let twist = orientation.and_then(|[_, _, twist]| circle(twist));
        Self { pressure, lean, twist }
    }

    /// A packet's record: pressure 0..1; the pen top's compass bearing in
    /// degrees (0 toward the top of the tablet, clockwise) and its altitude
    /// as a fraction of a right angle (1 upright; negative with the eraser
    /// end down); time in ms; buttons; 1 when the device is oriented at all
    /// (bearing and altitude are 0 when it is not — an older library wrote a
    /// reserved 0 there, so it reads as a device with no lean rather than a
    /// wrong one); the twist about the barrel in degrees 0..360, clockwise as
    /// Wintab's orTwist runs; and 1 when the device declares a twist.
    pub(crate) fn record(&self, packet: &Packet) -> [f32; 8] {
        let pressure = (f64::from(packet.normal_pressure) * self.pressure).clamp(0.0, 1.0);
        let turn = |units: i32, span: i32| (f64::from(units) * 360.0 / f64::from(span)) as f32;
        let pose = packet.orientation;
        let (bearing, altitude, oriented) = match self.lean {
            Some((span, right)) => {
                (turn(pose.azimuth, span), pose.altitude as f32 / right as f32, 1.0)
            }
            None => (0.0, 0.0, 0.0),
        };
        let (twist, twisted) = match self.twist {
            Some(span) => (turn(pose.twist, span), 1.0),
            None => (0.0, 0.0),
        };
        let time = packet.time as f32;
        [pressure as f32, bearing, altitude, time, packet.buttons as f32, oriented, twist, twisted]
    }
}

struct Opened {
    context: *mut c_void,
    scales: Scales,
}

struct Tablet {
    driver: Option<Driver>,
    opened: Option<Opened>,
}

// SAFETY: a context handle and the driver's entry points, only ever used
// under the lock.
unsafe impl Send for Tablet {}

static TABLET: Mutex<Tablet> = Mutex::new(Tablet { driver: None, opened: None });

fn tablet() -> std::sync::MutexGuard<'static, Tablet> {
    TABLET.lock().unwrap_or_else(PoisonError::into_inner)
}

impl Tablet {
    /// The driver, when wintab32 loads AND it reports an installed device.
    fn available(&mut self) -> Option<Driver> {
        if self.driver.is_none() {
            self.driver = Driver::load();
        }
        self.driver.filter(Driver::answers)
    }
}

/// The top-level window of THIS process (the Flutter runner window): Wintab
/// wants a window to scope the context to.
fn app_window() -> Option<HWND> {
    unsafe extern "system" fn visit(window: HWND, found: LPARAM) -> BOOL {
        let mut process = 0;
        // SAFETY: a window the system enumerates; `found` is app_window's.
        unsafe {
            GetWindowThreadProcessId(window, Some(&mut process));
            if process == GetCurrentProcessId()
                && IsWindowVisible(window).as_bool()
                && GetWindow(window, GW_OWNER).is_err()
            {
                *(found.0 as *mut Option<HWND>) = Some(window);
                return false.into();
            }
        }
        true.into()
    }
    let mut found: Option<HWND> = None;
    // SAFETY: `visit` writes to `found` alone, before this returns. It ends
    // the walk early, which EnumWindows reports as a failure.
    let _ = unsafe { EnumWindows(Some(visit), LPARAM(&raw mut found as isize)) };
    found
}

pub(crate) fn available() -> bool {
    tablet().available().is_some()
}

/// The device's name into `out`, at most `out.len() - 1` characters and
/// then a NUL; its length. None when there is no driver to ask, or no room.
pub(crate) fn device_name(out: Option<&mut [u16]>) -> Option<usize> {
    let driver = tablet().available()?;
    let out = out?;
    // ⛔ASKED ITS SIZE FIRST: the C handed the driver 64 characters of room
    // and the driver writes the whole name (native-memory-safety).
    // SAFETY: a size query, writing nothing.
    let bytes = unsafe { (driver.info)(WTI_DEVICES, DVC_NAME, std::ptr::null_mut()) };
    let mut name = vec![0u16; (bytes as usize).div_ceil(2)];
    if bytes != 0 {
        // SAFETY: room for the size the driver just gave.
        unsafe { (driver.info)(WTI_DEVICES, DVC_NAME, name.as_mut_ptr().cast()) };
    }
    let length = name.iter().take(63).take_while(|&&c| c != 0).count().min(out.len() - 1);
    out[..length].copy_from_slice(&name[..length]);
    out[length] = 0;
    Some(length)
}

/// Opens the polling context. Idempotent. False with no driver, or no app
/// window yet.
pub(crate) fn open() -> bool {
    let mut tablet = tablet();
    if tablet.opened.is_some() {
        return true;
    }
    let Some(driver) = tablet.available() else {
        return false;
    };
    let Some(window) = app_window() else {
        return false;
    };
    // A SYSTEM context is what "observe alongside the OS" actually MEANS in
    // Wintab, and the default to clone is WTI_DEFSYSCTX. The driver keeps
    // driving the system cursor - legacy mouse/Ink events go on flowing to
    // the window - while our queue fills in parallel.
    //
    // The opposite reading bricked the app: a NON-system (digitizing)
    // context is not a quiet observer, it DECLARES "this app takes the
    // tablet directly, no mouse emulation needed", so the driver stops
    // synthesizing pointer input for the window. Picking Wintab in Input
    // Settings killed the cursor outright (and the choice is persisted, so
    // a restart came up dead too).
    // SAFETY: LOGCONTEXTW is plain data; zero is how the C began it.
    let mut context: LogContext = unsafe { std::mem::zeroed() };
    // SAFETY: room for a LOGCONTEXTW, what WTI_DEFSYSCTX answers.
    if unsafe { (driver.info)(WTI_DEFSYSCTX, 0, (&raw mut context).cast()) } == 0 {
        return false;
    }
    context.options |= CXO_SYSTEM;
    context.packet_data = PACKET_DATA;
    context.packet_mode = 0; // absolute
    context.move_mask = PACKET_DATA;
    // SAFETY: the app's window and the context just filled in.
    let opened = unsafe { (driver.open)(window, &raw mut context, true.into()) };
    if opened.is_null() {
        return false;
    }
    if let Some(queue_size_set) = driver.queue_size_set {
        // SAFETY: the context just opened.
        unsafe { queue_size_set(opened, 128) };
    }
    let pressure = driver.info::<Axis>(WTI_DEVICES, DVC_NPRESSURE);
    let orientation = driver.info::<[Axis; 3]>(WTI_DEVICES, DVC_ORIENTATION);
    let scales = Scales::of(pressure, orientation);
    tablet.opened = Some(Opened { context: opened, scales });
    true
}

/// Drains the queued packets into `out`, a record of 8 floats each
/// ([`Scales::record`]) for as many whole records as it holds, at most 64.
/// The record count; 0 with nothing queued, or no context open.
pub(crate) fn poll(out: &mut [f32]) -> usize {
    let tablet = tablet();
    let (Some(driver), Some(opened)) = (tablet.driver, tablet.opened.as_ref()) else {
        return 0;
    };
    let mut packets = [Packet::default(); 64];
    let want = (out.len() / 8).min(packets.len());
    // SAFETY: the open context and room for `want` packets.
    let got = unsafe { (driver.packets_get)(opened.context, want as i32, packets.as_mut_ptr()) };
    // ⛔A DRIVER IS NOT TRUSTED PAST WHAT IT WAS ASKED FOR: the C read on
    // past its 64 for a count it was handed (native-memory-safety).
    let got = (got.max(0) as usize).min(want);
    for (packet, record) in packets[..got].iter().zip(out.chunks_exact_mut(8)) {
        record.copy_from_slice(&opened.scales.record(packet));
    }
    got
}

pub(crate) fn close() {
    let mut tablet = tablet();
    if let (Some(driver), Some(opened)) = (tablet.driver, tablet.opened.take()) {
        // SAFETY: the context this opened, closed once.
        let _ = unsafe { (driver.close)(opened.context) };
    }
}
