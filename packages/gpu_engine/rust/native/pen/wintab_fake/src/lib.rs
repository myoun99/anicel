//! A tablet driver for the pen's tests (native/pen): the entry points of
//! wintab32.dll that the pen reads, answering from a script the test plays
//! to it and keeping what it was asked. The C the pen replaces and the pen
//! both load "wintab32.dll" by name, and a library of that name already
//! loaded is the one they get — so on the same packets their readings are
//! held to each other, and the machine's own driver is never touched.
//!
//! The Wintab layouts are declared here again, from the driver's side: this
//! library cannot take the pen's without exporting the pen's functions as
//! well. They are Wintab's documented, fixed ABI, and sized here as the C
//! sizes them.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

use std::ffi::c_void;
use std::sync::{Mutex, PoisonError};

/// AXIS: a device axis's range, unit and resolution.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Axis {
    pub min: i32,
    pub max: i32,
    pub units: i32,
    pub resolution: u32,
}

/// The packet the pen asks for (TIME | BUTTONS | X | Y | NORMAL_PRESSURE |
/// ORIENTATION), its fields in that order.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Packet {
    pub time: u32,
    pub buttons: u32,
    pub x: i32,
    pub y: i32,
    pub pressure: u32,
    pub azimuth: i32,
    pub altitude: i32,
    pub twist: i32,
}

/// LOGCONTEXTW as its words: the name's forty characters in the first
/// twenty, then [`OPTIONS`], …, [`PACKET_DATA`], [`PACKET_MODE`],
/// [`MOVE_MASK`] and the rest.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Context(pub [u32; 53]);

/// The words of [`Context`] the pen sets.
pub const OPTIONS: usize = 20;
pub const PACKET_DATA: usize = 26;
pub const PACKET_MODE: usize = 27;
pub const MOVE_MASK: usize = 28;

const _: () = assert!(size_of::<Axis>() == 16);
const _: () = assert!(size_of::<Packet>() == 32);
const _: () = assert!(size_of::<Context>() == 212);

/// What the driver answers.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct Script {
    /// Whether WTInfo answers at all — no device, no driver.
    pub installed: bool,
    /// The device's name, up to its NUL.
    pub name: [u16; 80],
    /// The default system context, and whether there is one.
    pub has_context: bool,
    pub context: Context,
    /// Whether WTOpen gives a context.
    pub opens: bool,
    /// The normal-pressure axis, and whether the device declares it.
    pub has_pressure: bool,
    pub pressure: Axis,
    /// The orientation axes (azimuth, altitude, twist), and whether the
    /// device declares them.
    pub has_orientation: bool,
    pub orientation: [Axis; 3],
    /// The queue: `packets[..queued]`, drained from the front.
    pub packets: [Packet; 80],
    pub queued: i32,
    /// How many more packets than it wrote WTPacketsGet says it wrote.
    pub claims_more: i32,
}

/// What the driver was asked.
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Seen {
    pub opens: i32,
    pub closes: i32,
    /// The window, the context and the enable WTOpen was last handed.
    pub window: isize,
    pub context: Context,
    pub enable: i32,
    pub queue_size: i32,
    /// How many packets each WTPacketsGet asked for, the first eight.
    pub asked: [i32; 8],
    pub asks: i32,
}

/// The one context this driver opens.
const HANDLE: isize = 0x7AB;

const WTI_DEFSYSCTX: u32 = 4;
const WTI_DEVICES: u32 = 100;
const DVC_NAME: u32 = 1;
const DVC_NPRESSURE: u32 = 15;
const DVC_ORIENTATION: u32 = 17;

impl Script {
    /// No driver: the script played before any other.
    pub const QUIET: Self = Self {
        installed: false,
        name: [0; 80],
        has_context: false,
        context: Context([0; 53]),
        opens: false,
        has_pressure: false,
        pressure: Axis { min: 0, max: 0, units: 0, resolution: 0 },
        has_orientation: false,
        orientation: [Axis { min: 0, max: 0, units: 0, resolution: 0 }; 3],
        packets: [Packet {
            time: 0,
            buttons: 0,
            x: 0,
            y: 0,
            pressure: 0,
            azimuth: 0,
            altitude: 0,
            twist: 0,
        }; 80],
        queued: 0,
        claims_more: 0,
    };
}

impl Seen {
    /// Asked nothing.
    pub const NOTHING: Self = Self {
        opens: 0,
        closes: 0,
        window: 0,
        context: Context([0; 53]),
        enable: 0,
        queue_size: 0,
        asked: [0; 8],
        asks: 0,
    };
}

struct Played {
    script: Script,
    seen: Seen,
    drained: usize,
}

static PLAYED: Mutex<Played> =
    Mutex::new(Played { script: Script::QUIET, seen: Seen::NOTHING, drained: 0 });

fn played<T>(with: impl FnOnce(&mut Played) -> T) -> T {
    with(&mut PLAYED.lock().unwrap_or_else(PoisonError::into_inner))
}

/// Answers from `script` from now on, having been asked nothing.
///
/// # Safety
/// `script` is a [`Script`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fake_wintab_play(script: *const Script) {
    // SAFETY: the caller's contract.
    let script = unsafe { *script };
    played(|played| *played = Played { script, seen: Seen::NOTHING, drained: 0 });
}
/// What the driver has been asked since the script was played.
///
/// # Safety
/// `out` is a writable [`Seen`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fake_wintab_seen(out: *mut Seen) {
    let seen = played(|played| played.seen);
    // SAFETY: the caller's contract.
    unsafe { out.write(seen) };
}

/// # Safety
/// `out` is null, or room for what `category` and `index` answer with.
#[allow(non_snake_case)]
#[unsafe(no_mangle)]
pub unsafe extern "system" fn WTInfoW(category: u32, index: u32, out: *mut c_void) -> u32 {
    let script = played(|played| played.script);
    if !script.installed {
        return 0;
    }
    // SAFETY: the caller's contract, for each answer.
    unsafe {
        match (category, index) {
            (0, 0) => 1,
            (WTI_DEVICES, DVC_NAME) => {
                let length = script.name.iter().position(|&c| c == 0).unwrap_or(79) + 1;
                if !out.is_null() {
                    out.cast::<u16>().copy_from_nonoverlapping(script.name.as_ptr(), length);
                }
                (2 * length) as u32
            }
            (WTI_DEFSYSCTX, 0) if script.has_context => answer(out, script.context),
            (WTI_DEVICES, DVC_NPRESSURE) if script.has_pressure => answer(out, script.pressure),
            (WTI_DEVICES, DVC_ORIENTATION) if script.has_orientation => {
                answer(out, script.orientation)
            }
            _ => 0,
        }
    }
}

/// # Safety
/// `out` is null or room for a `T`.
unsafe fn answer<T>(out: *mut c_void, value: T) -> u32 {
    if !out.is_null() {
        // SAFETY: the caller's contract.
        unsafe { out.cast::<T>().write_unaligned(value) };
    }
    size_of::<T>() as u32
}

/// # Safety
/// `context` is a [`Context`].
#[allow(non_snake_case)]
#[unsafe(no_mangle)]
pub unsafe extern "system" fn WTOpenW(window: isize, context: *mut Context, enable: i32) -> isize {
    played(|played| {
        played.seen.opens += 1;
        played.seen.window = window;
        // SAFETY: the caller's contract.
        played.seen.context = unsafe { context.read_unaligned() };
        played.seen.enable = enable;
        if played.script.opens { HANDLE } else { 0 }
    })
}

#[allow(non_snake_case)]
#[unsafe(no_mangle)]
pub extern "system" fn WTClose(handle: isize) -> i32 {
    played(|played| played.seen.closes += 1);
    i32::from(handle == HANDLE)
}

#[allow(non_snake_case)]
#[unsafe(no_mangle)]
pub extern "system" fn WTQueueSizeSet(_handle: isize, size: i32) -> i32 {
    played(|played| played.seen.queue_size = size);
    1
}

/// # Safety
/// `out` is room for `max` packets.
#[allow(non_snake_case)]
#[unsafe(no_mangle)]
pub unsafe extern "system" fn WTPacketsGet(_handle: isize, max: i32, out: *mut Packet) -> i32 {
    played(|played| {
        if let Some(asked) = played.seen.asked.get_mut(played.seen.asks as usize) {
            *asked = max;
        }
        played.seen.asks += 1;
        let queued = &played.script.packets[played.drained..played.script.queued as usize];
        let given = queued.len().min(max.max(0) as usize);
        // SAFETY: the caller's contract; `given` is at most `max`.
        unsafe { out.copy_from_nonoverlapping(queued.as_ptr(), given) };
        played.drained += given;
        given as i32 + played.script.claims_more
    })
}
