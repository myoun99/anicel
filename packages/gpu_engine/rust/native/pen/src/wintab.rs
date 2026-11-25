//! The tablet DRIVER's word (PEN-2): pressure, lean and twist through
//! wintab32.dll, bypassing the OS pointer classification entirely. The app
//! keeps consuming Flutter's pointer events for position and gestures; this
//! supplies the driver's pressure and tilt stream, so a pen that the OS
//! misreports (as touch or mouse) still paints with full pressure.
//!
//! - wintab32.dll is loaded DYNAMICALLY; a machine without a driver is a
//!   normal, silent state (`qat_available` 0) — never a link error.
//! - The packet queue is drained without CXO_MESSAGES (no message pump
//!   dependency) into the packets heard ([`Heard`]) by the receiver's
//!   thread ([`crate::receiver`] — [`DRAIN_EVERY`], and sooner where a
//!   move's packet is not heard yet: [`readings_at`]), which sends what it
//!   takes ([`SENT`]), and by a message
//!   that presses (points_win.rs). Dart's poll reads what was heard, and so do the
//!   points' readers (points_win.rs), which give each point the pen or a
//!   mouse made what the packet that put it there says of the pen — its
//!   pressure, lean and twist ([`Heard::at`]) — at its message, else as the
//!   app reads it ([`pair`]).
//! - The Wintab structs and constants are declared here (the vendor header
//!   set is not in the Windows SDK; the LOGCONTEXT layout and the PK_*
//!   serialization order are stable, documented ABI).

use std::collections::VecDeque;
use std::ffi::c_void;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{LazyLock, Mutex, MutexGuard, PoisonError};
use std::time::Duration;

use crate::points::{Driven, Point};
use crate::points_win::{Move, a_pixel_apart};
use crate::receiver::{self, Work};

use windows::Win32::Foundation::{FreeLibrary, HMODULE, HWND};
use windows::Win32::System::LibraryLoader::{GetProcAddress, LoadLibraryW};
use windows::core::{BOOL, PCSTR, s, w};

const WTI_DEFSYSCTX: u32 = 4;
const WTI_DEVICES: u32 = 100;
const DVC_NAME: u32 = 1;
const DVC_NPRESSURE: u32 = 15;
const DVC_ORIENTATION: u32 = 17;

const CXO_SYSTEM: u32 = 0x0001;

// WTPKT field bits — a packet serializes its fields in ASCENDING bit order,
// and [`Packet`] lists them in exactly that order.
const PK_STATUS: u32 = 0x0002;
const PK_TIME: u32 = 0x0004;
const PK_BUTTONS: u32 = 0x0040;
const PK_X: u32 = 0x0080;
const PK_Y: u32 = 0x0100;
const PK_NORMAL_PRESSURE: u32 = 0x0400;
const PK_ORIENTATION: u32 = 0x1000;
const PACKET_DATA: u32 =
    PK_STATUS | PK_TIME | PK_BUTTONS | PK_X | PK_Y | PK_NORMAL_PRESSURE | PK_ORIENTATION;

/// A packet's status word: the context's queue overflowed before it.
const TPS_QUEUE_ERR: u32 = 0x0002;

/// The longest queue the driver is asked for, and the most packets heard.
///
/// ↩️It was 128: at a pen's 200 Hz, 0.64 s — and a UI thread held longer
/// than that (a plugin's frames held it over a second, 11-17) lost every
/// packet between. 1024 is five seconds of them. 🔬The main PC's Wacom
/// driver refuses 1024 and took 128 (11-18) — its queue is the receiver's
/// to drain, never held up by the UI's ([`DRAIN_EVERY`]).
pub(crate) const QUEUE: usize = 1024;

/// How long the receiver waits between drains of the queue.
///
/// 🚨THE APP'S THREAD NEVER WAITS ON THE DRIVER (F-600 · H61, 2026-11-18): a
/// call into Wacom's wintab32 goes to its service and back — 🔬main PC, a
/// context opened on a window never shown: WTPacketsGet took 246–251 µs at
/// the median whatever it was asked for, 117 µs of it the calling thread's
/// CPU, and as long from another thread. Drained at each ask, a mouse's
/// sample under Wintab spent 1.5–1.75 ms of the UI thread — six or seven
/// asks of it: its pressure, lean and twist, and whether the pen is down —
/// where the standard service spends nothing, and a mouse hands on 16–64
/// samples a frame. Every 4 ms a pen's packet of every 5 ms (200 Hz) is
/// heard before the message drawn at it is read, for ~3% of one core.
const DRAIN_EVERY: Duration = Duration::from_millis(4);

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
    pub(crate) status: u32,
    pub(crate) time: u32,
    pub(crate) buttons: u32,
    pub(crate) x: i32,
    pub(crate) y: i32,
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
const _: () = assert!(size_of::<Packet>() == 36);
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

    /// What a packet says of the pen ([`Driven`]): its pressure, its lean
    /// where the device declares an orientation, and its twist where it
    /// declares one — read once here for the app's poll ([`Scales::record`])
    /// and for a point ([`pair`]) alike.
    pub(crate) fn reading(&self, packet: &Packet) -> Driven {
        let turn = |units: i32, span: i32| f64::from(units) * 360.0 / f64::from(span);
        let pose = packet.orientation;
        Driven {
            pressure: self.pressure_of(packet),
            lean: self.lean.map(|(span, right)| {
                (turn(pose.azimuth, span), f64::from(pose.altitude) / f64::from(right))
            }),
            twist: self.twist.map(|span| turn(pose.twist, span)),
        }
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
        let reading = self.reading(packet);
        let (bearing, altitude, oriented) =
            reading.lean.map_or((0.0, 0.0, 0.0), |(bearing, altitude)| (bearing as f32, altitude as f32, 1.0));
        let (twist, twisted) = reading.twist.map_or((0.0, 0.0), |twist| (twist as f32, 1.0));
        let time = packet.time as f32;
        [reading.pressure as f32, bearing, altitude, time, packet.buttons as f32, oriented, twist, twisted]
    }

    /// A packet's pressure, 0..1 of the device's axis.
    pub(crate) fn pressure_of(&self, packet: &Packet) -> f64 {
        (f64::from(packet.normal_pressure) * self.pressure).clamp(0.0, 1.0)
    }
}

/// What the driver said of the pen, kept past the drain that took it: the
/// newest [`QUEUE`] packets, the oldest first.
#[derive(Debug, Default)]
pub(crate) struct Heard {
    packets: VecDeque<Packet>,
    /// How many of the newest the app has not been handed ([`Heard::hand`]).
    unhanded: usize,
    /// How many packets said the queue overflowed before them.
    pub(crate) overflowed: u32,
    /// How far the newest packet was behind the mouse message last handled,
    /// in ms of the message clock ([`Heard::behind`]).
    pub(crate) gap: Option<i32>,
}

impl Heard {
    /// Keeps `packets`, newer than every one kept, past the oldest kept.
    pub(crate) fn hear(&mut self, packets: &[Packet]) {
        for packet in packets {
            if packet.status & TPS_QUEUE_ERR != 0 {
                self.overflowed += 1;
            }
            if self.packets.len() == QUEUE {
                self.packets.pop_front();
            }
            self.packets.push_back(*packet);
        }
        self.unhanded = (self.unhanded + packets.len()).min(self.packets.len());
    }

    /// The newest `room` of the packets the app was not handed yet, the
    /// oldest first — and none of them again: what the app reads off a poll
    /// is the pen now, and the newest is that.
    pub(crate) fn hand(&mut self, room: usize) -> impl Iterator<Item = &Packet> {
        let handed = self.unhanded.min(room);
        self.unhanded = 0;
        self.packets.iter().skip(self.packets.len() - handed)
    }

    /// The packet that put the cursor where `place` is: of the packets at
    /// its place as `output` lays them on the screen — a pixel round it at
    /// most ([`a_pixel_apart`]) — the nearest its time on the message clock,
    /// `within` ms of it at most; of two as near, the newer.
    ///
    /// 🚨BY ITS PLACE, NOT ITS TIME (H61, 2026-11-18): a move's time is the
    /// message clock's, which steps 15.6 ms — the four moves of a step are
    /// of one millisecond — and the driver's packets are a millisecond's
    /// own, one every 4 ms. Paired by time, the moves of a step took one
    /// packet between them, and the stroke's pressure went in steps (유저
    /// 「중간중간 필압이 이상한 구간」). The cursor is where a packet put it:
    /// 🔬main PC, a pen as a mouse, 1,470 moves of three strokes (k-h61):
    /// 1,466 had a packet at their place, a pixel round at most — 706 at the
    /// very pixel —, and the packet nearest in time was that one for 544.
    ///
    /// ⚠️Wintab's `pkTime` is read as the message clock's own milliseconds,
    /// as Qt reads it; the input inspector shows how far apart the two run
    /// ([`Heard::behind`]).
    pub(crate) fn at(&self, (x, y, time): Move, within: u32, output: Output) -> Option<&Packet> {
        let mut nearest: Option<(u32, &Packet)> = None;
        for packet in self.packets.iter().rev() {
            let after = packet.time.wrapping_sub(time) as i32;
            if i64::from(after) < -i64::from(within) {
                break; // and every packet before it, older still
            }
            let off = after.unsigned_abs();
            let here = a_pixel_apart(output.place_of(packet), (x, y));
            if here && off <= within && nearest.is_none_or(|(best, _)| off < best) {
                nearest = Some((off, packet));
            }
        }
        nearest.map(|(_, packet)| packet)
    }

    /// Notes how far the newest packet is behind a message at `time`.
    pub(crate) fn behind(&mut self, time: u32) {
        self.gap = self.packets.back().map(|packet| time.wrapping_sub(packet.time) as i32);
    }
}

/// Where an open context lays its packets: its output's origin and extent —
/// the screen's pixels, for a system context.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Output {
    pub(crate) origin: [i32; 2],
    pub(crate) extent: [i32; 2],
}

impl Output {
    /// The screen pixel `packet` is at. Wintab's y runs up its output from
    /// the bottom row where the extent is positive, as a system context's
    /// is, and down from the top where it is negative.
    ///
    /// 🔬Main PC, a system context over a virtual screen 2,880 high (k-h61,
    /// 11-18): a move at (x, y) had its packet at x and 2,879 − y.
    pub(crate) fn place_of(&self, packet: &Packet) -> (i32, i32) {
        let ([_, top], [_, high]) = (self.origin, self.extent);
        let y = if high < 0 { packet.y } else { top + (high - 1) - (packet.y - top) };
        (packet.x, y)
    }
}

struct Opened {
    context: *mut c_void,
    scales: Scales,
    /// How far from a point a packet may be to give it its pressure: the
    /// app's own window for a fresh packet.
    within: u32,
    output: Output,
    heard: Heard,
}

impl Opened {
    /// What the packet heard that put the cursor at `at` says of the pen
    /// ([`Heard::at`]); None where none did.
    fn reading_at(&self, at: Move) -> Option<Driven> {
        self.heard.at(at, self.within, self.output).map(|packet| self.scales.reading(packet))
    }
}

/// The open context's queue, and room for the whole of it: what drains it
/// — the receiver's thread, a press ([`drain`]) — takes it in turn, and
/// sends or hears what it took before the next takes any, so the packets
/// heard keep the driver's order.
struct Drain {
    driver: Driver,
    context: *mut c_void,
    room: Vec<Packet>,
}

// SAFETY: a context handle and the driver's entry points, only ever used
// under the lock — 🔬the driver answers a context's drain from a thread
// that did not open it as it answers the one that did (11-18).
unsafe impl Send for Drain {}

/// 🚨EVERY CALL INTO THE DRIVER ON A CONTEXT IS MADE UNDER THIS LOCK, and
/// [`close`] takes the drain away under it: once the drain is gone, no
/// call is left on its context — what the drain thread's join kept before
/// it was the receiver's (pen-receive-threads-are-one).
static DRAIN: Mutex<Option<Drain>> = Mutex::new(None);

fn drain_lock() -> MutexGuard<'static, Option<Drain>> {
    DRAIN.lock().unwrap_or_else(PoisonError::into_inner)
}

/// How often the receiver drains the open context, in microseconds: what
/// it was opened with ([`open_drained_every`]), for a move that wakes it
/// ([`hear_now`]) to keep it.
static EVERY: AtomicU64 = AtomicU64::new(0);

/// Takes every packet the driver has queued into `drain`'s room: how many.
fn take_queued(drain: &mut Drain) -> usize {
    // SAFETY: the open context and room for QUEUE packets.
    let got = unsafe { (drain.driver.packets_get)(drain.context, QUEUE as i32, drain.room.as_mut_ptr()) };
    // ⛔A DRIVER IS NOT TRUSTED PAST WHAT IT WAS ASKED FOR: the C read on
    // past its 64 for a count it was handed (native-memory-safety).
    (got.max(0) as usize).min(QUEUE)
}

/// What the receiver's drains took, in the order taken — sent by the drain
/// that took it, heard by whoever takes what was heard, before it reads
/// ([`tablet`]).
///
/// 🚨THE RECEIVER ONLY SENDS (pen-receive-threads-are-one, 2026-11-23), as
/// it does the mouse's reads ([`crate::mouse_kept`]'s `SENT`): it heard
/// what it took itself where the UI's thread did not hold what was heard
/// (`try_lock`), and held the rest back for its next drain. 🔬공통 11-23,
/// the crate's gate in debug: a move's packet, taken by the drain it woke
/// while a poll held what was heard, waited ten seconds for the drain after
/// (`a_move_whose_packet_is_not_heard_yet_wakes_the_reader`) — in the app
/// 4 ms, past the pairing of the move that woke it ([`readings_at`]). A
/// send waits on nobody, and the next read hears it.
static SENT: LazyLock<(Sender<Vec<Packet>>, Mutex<Receiver<Vec<Packet>>>)> = LazyLock::new(|| {
    let (send, heard) = mpsc::channel();
    (send, Mutex::new(heard))
});

/// The receiver's turn ([`crate::receiver::Work::Drain`]): every packet
/// the driver has queued taken and sent ([`SENT`]). Whether a context is
/// still open.
///
/// 🚨IT NEVER WAITS ON THE UI'S THREAD: what was heard is the UI's to read
/// (`poll` · `readings_at` · `pair`), and the packets taken are sent to it;
/// where the UI drains itself (a press), this turn is the UI's.
pub(crate) fn drain_on_its_own() -> bool {
    // The UI's press is draining it: the queue is heard all the same.
    let Some(mut drain) = receiver::if_free(&DRAIN) else {
        return true;
    };
    let Some(drain) = drain.as_mut() else {
        return false;
    };
    let got = take_queued(drain);
    if got > 0 {
        let _ = SENT.0.send(drain.room[..got].to_vec());
    }
    true
}

/// Drains the queue now: a message that presses, whose point and buttons
/// are read before the receiver drains again.
///
/// 🚨THE PEN'S CONTACT IS HEARD AT ITS PRESS (H43, 2026-09-26): read off a
/// drain a whole wait behind, the packet the app took was, as often as
/// not, the pen still HOVERING — pressure 0, tip up. The first dab was
/// stamped with that, and a press whose buttons were read off it did not
/// draw at all; the contact packet was already in the driver's queue.
pub(crate) fn drain() {
    let mut drain = drain_lock();
    let Some(drain) = drain.as_mut() else {
        return;
    };
    let got = take_queued(drain);
    if let Some(opened) = tablet().opened.as_mut() {
        opened.heard.hear(&drain.room[..got]);
    }
}

struct Tablet {
    driver: Option<Driver>,
    opened: Option<Opened>,
}

// SAFETY: a context handle and the driver's entry points, only ever used
// under the lock.
unsafe impl Send for Tablet {}

static TABLET: Mutex<Tablet> = Mutex::new(Tablet { driver: None, opened: None });

/// The tablet, what the receiver sent ([`SENT`]) heard first by its open
/// context — let go of where none is open.
fn tablet() -> std::sync::MutexGuard<'static, Tablet> {
    let mut tablet = TABLET.lock().unwrap_or_else(PoisonError::into_inner);
    let sent = SENT.1.lock().unwrap_or_else(PoisonError::into_inner);
    for taken in sent.try_iter() {
        if let Some(opened) = tablet.opened.as_mut() {
            opened.heard.hear(&taken);
        }
    }
    drop(sent);
    tablet
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

/// Why a context did not open — what `qat_open` answers in its place
/// (h61-wintab-sometimes-not-engaged-at-launch: a run whose pen never came
/// in through Wintab is read off the input inspector by this).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Refusal {
    /// wintab32 did not load, or no driver answered.
    NoDriver = 0,
    /// This process shows no app window yet ([`display::app_window`]).
    NoWindow = -1,
    /// The driver gave no default system context.
    NoSystemContext = -2,
    /// The driver gave no context for the one asked.
    NotOpened = -3,
}

/// Opens the polling context, a packet giving a mouse move its pressure
/// `within` ms of it. Idempotent.
pub(crate) fn open(within: u32) -> Result<(), Refusal> {
    open_drained_every(within, DRAIN_EVERY)
}

/// [`open`], the receiver draining the queue `every` so long
/// when nothing wakes it sooner ([`readings_at`]).
pub(crate) fn open_drained_every(within: u32, every: Duration) -> Result<(), Refusal> {
    let mut tablet = tablet();
    if tablet.opened.is_some() {
        return Ok(());
    }
    let Some(driver) = tablet.available() else {
        return Err(Refusal::NoDriver);
    };
    // Wintab wants a window to scope the context to: the app's.
    let Some(window) = display::app_window() else {
        return Err(Refusal::NoWindow);
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
        return Err(Refusal::NoSystemContext);
    }
    context.options |= CXO_SYSTEM;
    context.packet_data = PACKET_DATA;
    context.packet_mode = 0; // absolute
    context.move_mask = PACKET_DATA;
    // SAFETY: the app's window and the context just filled in.
    let opened = unsafe { (driver.open)(window, &raw mut context, true.into()) };
    if opened.is_null() {
        return Err(Refusal::NotOpened);
    }
    if let Some(queue_size_set) = driver.queue_size_set {
        // 🚨A REFUSED SIZE LEAVES NO QUEUE AT ALL: WTQueueSizeSet deletes the
        // old queue before it tries the new one, and the app is to ask again,
        // smaller, until one is taken (Wintab 1.4) — so down to one packet.
        let mut size = QUEUE as i32;
        // SAFETY: the context just opened.
        while size > 0 && unsafe { queue_size_set(opened, size) } == 0 {
            size /= 2;
        }
    }
    let pressure = driver.info::<Axis>(WTI_DEVICES, DVC_NPRESSURE);
    let orientation = driver.info::<[Axis; 3]>(WTI_DEVICES, DVC_ORIENTATION);
    let scales = Scales::of(pressure, orientation);
    // As the driver took it: it may have changed what it was asked.
    let output = Output {
        origin: [context.out_origin[0], context.out_origin[1]],
        extent: [context.out_extent[0], context.out_extent[1]],
    };
    tablet.opened = Some(Opened { context: opened, scales, within, output, heard: Heard::default() });
    drop(tablet);
    let room = vec![Packet::default(); QUEUE];
    *drain_lock() = Some(Drain { driver, context: opened, room });
    EVERY.store(u64::try_from(every.as_micros()).unwrap_or(u64::MAX), Ordering::Relaxed);
    receiver::now(Work::Drain, every);
    Ok(())
}

/// Hands `out` the newest of the packets heard and not handed yet
/// ([`Heard::hand`]), a record of 8 floats each ([`Scales::record`]) for as
/// many whole records as it holds — asking the driver nothing. The record
/// count; 0 with nothing new, or no context open.
pub(crate) fn poll(out: &mut [f32]) -> usize {
    let mut tablet = tablet();
    let Some(opened) = tablet.opened.as_mut() else {
        return 0;
    };
    let scales = opened.scales;
    let mut handed = 0;
    for (packet, record) in opened.heard.hand(out.len() / 8).zip(out.chunks_exact_mut(8)) {
        record.copy_from_slice(&scales.record(packet));
        handed += 1;
    }
    handed
}

/// What the driver's packet that put the cursor at each of `moves` — screen
/// pixels, and the message clock — says of the pen ([`Driven`]), within the
/// window the context opened with ([`Heard::at`]); None where no packet
/// did, and all None while no context is open. Asks the driver nothing;
/// notes how far the newest packet heard is behind the message being
/// handled, at `message` — and has the receiver drain where a move's
/// packet is not heard yet while the pen is at hand, for [`pair`] to find
/// it there.
///
/// ⛔Not where the pen was last heard further back than the context's own
/// window: a mouse's moves, with no packet ever to be heard of them — a
/// mouse of 1,000 Hz would have the receiver ask the driver as often.
pub(crate) fn readings_at(message: u32, moves: &[Move]) -> Vec<Option<Driven>> {
    let mut tablet = tablet();
    let Some(opened) = tablet.opened.as_mut() else {
        return vec![None; moves.len()];
    };
    opened.heard.behind(message);
    let readings: Vec<Option<Driven>> = moves.iter().map(|&at| opened.reading_at(at)).collect();
    let at_hand = opened.heard.gap.is_some_and(|gap| gap.unsigned_abs() <= opened.within);
    drop(tablet);
    if at_hand && readings.iter().any(Option::is_none) {
        hear_now();
    }
    readings
}

/// Gives each of `points` what the driver's packet at its place, heard
/// since its message, says of the pen, where it had nothing then
/// ([`readings_at`]). Asks the driver nothing.
///
/// 🚨A MOVE IS PAIRED AS THE APP READS IT TOO (H61, 2026-11-18): the receiver
/// drains every [`DRAIN_EVERY`], and the packet that put the
/// cursor at a move is made as the move is — so its message was handled,
/// as often as not, before the packet was heard, and the app took the
/// driver's newest packet in its place. 🔬main PC, a pen as a mouse, two
/// strokes (H61-Q2 5판): 297 of 572 moves in contact, 287 of them heard by
/// the very next message; the newest stood off by 0.12% of the stroke's
/// most pressure at the median, 2.4% at the 99th. The app reads a point
/// after its message (1.7 ms at the median over the fastest), and the
/// message woke the receiver for it ([`hear_now`]) — no thread of the app's
/// waits on the driver for it.
pub(crate) fn pair(points: &mut [Point]) {
    let tablet = tablet();
    let Some(opened) = tablet.opened.as_ref() else {
        return;
    };
    for point in points.iter_mut().filter(|point| point.driven.is_none()) {
        if let Some(at) = point.asked {
            point.driven = opened.reading_at(at);
        }
    }
}

/// What was heard, held as the UI's thread holds it reading a message's
/// points — for a test to stand on it.
#[cfg(test)]
pub(crate) fn hold() -> impl Sized {
    tablet()
}

/// Has the receiver drain the queue now, waiting on nothing.
fn hear_now() {
    receiver::now(Work::Drain, Duration::from_micros(EVERY.load(Ordering::Relaxed)));
}

/// How many packets said the queue overflowed before them since the
/// context opened, and how far the newest was behind the mouse message last
/// handled ([`Heard`]); None while no context is open.
pub(crate) fn heard() -> Option<(u32, Option<i32>)> {
    let tablet = tablet();
    let heard = &tablet.opened.as_ref()?.heard;
    Some((heard.overflowed, heard.gap))
}

/// Closes the context: what was heard let go of and the drain taken away —
/// under its lock, so a drain the receiver is in has ended and none is
/// left on the context — before the driver is told.
pub(crate) fn close() {
    let opened = tablet().opened.take();
    drop(drain_lock().take());
    let driver = tablet().driver;
    if let (Some(driver), Some(opened)) = (driver, opened) {
        // SAFETY: the context this opened, closed once.
        let _ = unsafe { (driver.close)(opened.context) };
    }
}
