//! Windows' answers: the compositor's timing (DWM), the screens under the
//! app's window, the wait, and the compositor kept composing.
//!
//! dwmapi and dcomp are loaded the first time they are asked for: the
//! compositor's per-target statistics are Windows 11's alone, and a
//! function imported at load time that the system lacks would keep the whole
//! library — the GPU engine's, which carries this — from loading on Windows
//! 10.

use std::ffi::c_void;
use std::mem::transmute;
use std::ptr::null_mut;
use std::sync::{Mutex, OnceLock, PoisonError};

use windows::Win32::Devices::Display::{
    DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME, DISPLAYCONFIG_MODE_INFO, DISPLAYCONFIG_PATH_INFO,
    DISPLAYCONFIG_SOURCE_DEVICE_NAME, DisplayConfigGetDeviceInfo, QDC_ONLY_ACTIVE_PATHS,
    QueryDisplayConfig,
};
use windows::Win32::Foundation::{
    ERROR_SUCCESS, FALSE, HANDLE, HWND, LPARAM, LUID, POINT, RECT, TRUE,
};
use windows::Win32::Graphics::DirectComposition::{
    COMPOSITION_FRAME_ID_COMPLETED, COMPOSITION_FRAME_ID_TYPE, COMPOSITION_FRAME_STATS,
    COMPOSITION_TARGET_ID, COMPOSITION_TARGET_STATS, IDCompositionAnimation,
    IDCompositionDesktopDevice, IDCompositionTarget, IDCompositionVisual2,
};
use windows::Win32::Graphics::Dwm::DWM_TIMING_INFO;
use windows::Win32::Graphics::Gdi::{
    ClientToScreen, EnumDisplayMonitors, GetMonitorInfoW, HDC, HMONITOR, MONITORINFO,
    MONITORINFOEXW, OffsetRect,
};
use windows::Win32::System::LibraryLoader::{GetProcAddress, LoadLibraryW};
use windows::Win32::System::Performance::{QueryPerformanceCounter, QueryPerformanceFrequency};
use windows::Win32::System::Threading::{
    CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, CreateWaitableTimerExW, GetCurrentProcessId,
    SetWaitableTimer, TIMER_ALL_ACCESS, WaitForSingleObject,
};
use windows::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetClassNameW, GetClientRect, GetWindowThreadProcessId, IsWindowVisible,
};
use windows::core::{BOOL, GUID, HRESULT, Interface, PCSTR, PCWSTR, s, w};

// Called with the whole size, as dwmapi.h declares it.
const _: () = assert!(size_of::<DWM_TIMING_INFO>() == 292);

/// The counter's ticks a second.
fn frequency() -> i64 {
    static FREQUENCY: OnceLock<i64> = OnceLock::new();
    *FREQUENCY.get_or_init(|| {
        let mut hz = 0;
        // SAFETY: a local to write.
        let _ = unsafe { QueryPerformanceFrequency(&mut hz) };
        hz
    })
}

/// Counter ticks to microseconds, the whole seconds and the remainder apart:
/// the product of the counter and a million overflows 64 bits within hours.
fn micros(ticks: i64) -> i64 {
    let hz = frequency();
    (ticks / hz) * 1_000_000 + (ticks % hz) * 1_000_000 / hz
}

pub(crate) fn now() -> i64 {
    let mut counter = 0;
    // SAFETY: a local to write.
    let _ = unsafe { QueryPerformanceCounter(&mut counter) };
    micros(counter)
}

/// `name` in the system library `dll`; None where the system has no such
/// function.
fn system_function(dll: PCWSTR, name: PCSTR) -> Option<unsafe extern "system" fn() -> isize> {
    // SAFETY: a system library by its name, and a name in it.
    let module = unsafe { LoadLibraryW(dll) }.ok()?;
    unsafe { GetProcAddress(module, name) }
}

type DwmTiming = unsafe extern "system" fn(HWND, *mut DWM_TIMING_INFO) -> HRESULT;

fn dwm_timing() -> Option<DwmTiming> {
    static TIMING: OnceLock<Option<DwmTiming>> = OnceLock::new();
    *TIMING.get_or_init(|| {
        let found = system_function(w!("dwmapi.dll"), s!("DwmGetCompositionTimingInfo"))?;
        // SAFETY: dwmapi.h's declaration.
        Some(unsafe { transmute::<unsafe extern "system" fn() -> isize, DwmTiming>(found) })
    })
}

pub(crate) fn vblank() -> Option<(i64, i64)> {
    let timing = dwm_timing()?;
    let mut info = DWM_TIMING_INFO { cbSize: size_of::<DWM_TIMING_INFO>() as u32, ..Default::default() };
    // SAFETY: the whole of a DWM_TIMING_INFO, its size in it.
    if unsafe { timing(HWND::default(), &mut info) }.is_err() {
        return None;
    }
    let (period, vblank) = (info.qpcRefreshPeriod, info.qpcVBlank);
    if period == 0 || vblank == 0 {
        return None;
    }
    Some((micros(vblank as i64), (period as f64 * 1e9 / frequency() as f64) as i64))
}

type FrameId = unsafe extern "system" fn(COMPOSITION_FRAME_ID_TYPE, *mut u64) -> HRESULT;
type Statistics = unsafe extern "system" fn(
    u64,
    *mut COMPOSITION_FRAME_STATS,
    u32,
    *mut COMPOSITION_TARGET_ID,
    *mut u32,
) -> HRESULT;
type TargetStatistics =
    unsafe extern "system" fn(u64, *const COMPOSITION_TARGET_ID, *mut COMPOSITION_TARGET_STATS) -> HRESULT;

/// dcomp's per-target statistics, all three or none — Windows 11's.
#[derive(Clone, Copy)]
struct Compositor {
    frame_id: FrameId,
    statistics: Statistics,
    target_statistics: TargetStatistics,
}

fn compositor() -> Option<Compositor> {
    static COMPOSITOR: OnceLock<Option<Compositor>> = OnceLock::new();
    *COMPOSITOR.get_or_init(|| {
        let frame_id = system_function(w!("dcomp.dll"), s!("DCompositionGetFrameId"))?;
        let statistics = system_function(w!("dcomp.dll"), s!("DCompositionGetStatistics"))?;
        let target = system_function(w!("dcomp.dll"), s!("DCompositionGetTargetStatistics"))?;
        // SAFETY: dcomp.h's declarations.
        unsafe {
            Some(Compositor {
                frame_id: transmute::<unsafe extern "system" fn() -> isize, FrameId>(frame_id),
                statistics: transmute::<unsafe extern "system" fn() -> isize, Statistics>(statistics),
                target_statistics: transmute::<unsafe extern "system" fn() -> isize, TargetStatistics>(
                    target,
                ),
            })
        }
    })
}

/// Whether this system keeps the per-target statistics a window's screens
/// are read from.
#[cfg(test)]
pub(crate) fn has_target_statistics() -> bool {
    compositor().is_some()
}

/// The app's window: the runner's (windows/runner/win32_window.cpp names its
/// class), shown, in this process.
const APP_WINDOW_CLASS: &str = "FLUTTER_RUNNER_WIN32_WINDOW";

unsafe extern "system" fn find_app_window(window: HWND, found: LPARAM) -> BOOL {
    let mut process = 0;
    let mut name = [0u16; 64];
    // SAFETY: a window the system enumerates, and locals to write.
    let length = unsafe {
        GetWindowThreadProcessId(window, Some(&mut process));
        if process != GetCurrentProcessId() || !IsWindowVisible(window).as_bool() {
            return TRUE;
        }
        GetClassNameW(window, &mut name)
    };
    if length <= 0 || !APP_WINDOW_CLASS.encode_utf16().eq(name[..length as usize].iter().copied()) {
        return TRUE;
    }
    // SAFETY: `found` is app_window's local.
    unsafe { *(found.0 as *mut HWND) = window };
    FALSE
}

/// The app's window, or None where this process shows none.
///
/// ⛔ONE FINDER FOR EVERY CRATE THAT ASKS (관제 2026-11-08 03:50,
/// connection-round-checklist H): the pen's Wintab context asks it too. The
/// pen had a finder of its own — this process's first shown window with no
/// owner, carried over from its C on 2026-07-20 with no word of who chose it
/// — which bound the context to another top-level window where one came
/// first; the runner's class is the question itself.
pub fn app_window() -> Option<HWND> {
    let mut window = HWND::default();
    // SAFETY: the callback writes `window` alone, before this returns.
    let _ = unsafe { EnumWindows(Some(find_app_window), LPARAM(&mut window as *mut HWND as isize)) };
    (!window.is_invalid()).then_some(window)
}

/// At most this many screens and the compositor's targets.
const MAX_TARGETS: usize = 16;

#[derive(Clone, Copy)]
struct Screen {
    adapter: LUID,
    target: u32,
    period_ns: i64,
}

/// A monitor's name as GetMonitorInfoW and the display configuration both
/// give it.
type DeviceName = [u16; 32];

unsafe extern "system" fn monitor_named(
    monitor: HMONITOR,
    _: HDC,
    _: *mut RECT,
    names: LPARAM,
) -> BOOL {
    // SAFETY: `names` is screens_under's local.
    let names = unsafe { &mut *(names.0 as *mut Vec<DeviceName>) };
    let mut info = MONITORINFOEXW::default();
    info.monitorInfo.cbSize = size_of::<MONITORINFOEXW>() as u32;
    // SAFETY: a monitor the system enumerates, and the whole of an info.
    if names.len() < MAX_TARGETS
        && unsafe { GetMonitorInfoW(monitor, &mut info as *mut MONITORINFOEXW as *mut MONITORINFO) }
            .as_bool()
    {
        names.push(info.szDevice);
    }
    TRUE
}

/// The name up to its terminating nul.
fn named(name: &DeviceName) -> &[u16] {
    &name[..name.iter().position(|&c| c == 0).unwrap_or(name.len())]
}

/// The screens under the window's CLIENT area: its outer rect stands 8 pixels
/// past a maximized window's screen, onto whatever lies beside it.
fn screens_under(window: HWND) -> Vec<Screen> {
    let mut client = RECT::default();
    let mut origin = POINT::default();
    // SAFETY: the app's window, and locals to write.
    unsafe {
        if GetClientRect(window, &mut client).is_err() || !ClientToScreen(window, &mut origin).as_bool() {
            return Vec::new();
        }
        let _ = OffsetRect(&mut client, origin.x, origin.y);
    }
    let mut names: Vec<DeviceName> = Vec::new();
    // SAFETY: the callback pushes to `names` alone, before this returns.
    let _ = unsafe {
        EnumDisplayMonitors(None, Some(&client), Some(monitor_named), LPARAM(&mut names as *mut _ as isize))
    };

    // SAFETY: plain data, all zero a valid value.
    let mut paths: [DISPLAYCONFIG_PATH_INFO; MAX_TARGETS] = unsafe { std::mem::zeroed() };
    let mut modes: [DISPLAYCONFIG_MODE_INFO; MAX_TARGETS * 2] = unsafe { std::mem::zeroed() };
    let mut path_count = MAX_TARGETS as u32;
    let mut mode_count = (MAX_TARGETS * 2) as u32;
    // SAFETY: the arrays and their lengths.
    let queried = unsafe {
        QueryDisplayConfig(
            QDC_ONLY_ACTIVE_PATHS,
            &mut path_count,
            paths.as_mut_ptr(),
            &mut mode_count,
            modes.as_mut_ptr(),
            None,
        )
    };
    if queried != ERROR_SUCCESS {
        return Vec::new();
    }
    let mut screens = Vec::new();
    for path in &paths[..path_count as usize] {
        let mut source = DISPLAYCONFIG_SOURCE_DEVICE_NAME::default();
        source.header.r#type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
        source.header.size = size_of::<DISPLAYCONFIG_SOURCE_DEVICE_NAME>() as u32;
        source.header.adapterId = path.sourceInfo.adapterId;
        source.header.id = path.sourceInfo.id;
        // SAFETY: the whole of a source name, its size in its header.
        if unsafe { DisplayConfigGetDeviceInfo(&mut source.header) } != ERROR_SUCCESS.0 as i32 {
            continue;
        }
        let rate = path.targetInfo.refreshRate;
        if rate.Numerator != 0
            && names.iter().any(|name| named(name) == named(&source.viewGdiDeviceName))
        {
            screens.push(Screen {
                adapter: path.targetInfo.adapterId,
                target: path.targetInfo.id,
                period_ns: (1e9 * rate.Denominator as f64 / rate.Numerator as f64) as i64,
            });
        }
    }
    screens
}

/// Where the window lies, read at most this often: a look asks every frame,
/// and a window moves far less often than that.
const SCREENS_FRESH_US: i64 = 250_000;

fn screens_now() -> Vec<Screen> {
    static HELD: Mutex<(i64, Vec<Screen>)> = Mutex::new((0, Vec::new()));
    let now = now();
    let mut held = HELD.lock().unwrap_or_else(PoisonError::into_inner);
    if held.0 == 0 || now - held.0 >= SCREENS_FRESH_US {
        held.0 = now;
        held.1 = app_window().map_or_else(Vec::new, screens_under);
    }
    held.1.clone()
}

pub(crate) fn window_screens(max: i32) -> Vec<(i64, i64)> {
    let Some(compositor) = compositor() else {
        return Vec::new();
    };
    let screens = screens_now();
    let mut frame = 0;
    let mut stats = COMPOSITION_FRAME_STATS::default();
    let mut ids = [COMPOSITION_TARGET_ID::default(); MAX_TARGETS];
    let mut id_count = 0;
    // SAFETY: locals to write, and the array with its length.
    if screens.is_empty()
        || unsafe { (compositor.frame_id)(COMPOSITION_FRAME_ID_COMPLETED, &mut frame) }.is_err()
        || unsafe {
            (compositor.statistics)(frame, &mut stats, MAX_TARGETS as u32, ids.as_mut_ptr(), &mut id_count)
        }
        .is_err()
    {
        return Vec::new();
    }
    let ids = &ids[..(id_count as usize).min(MAX_TARGETS)];
    let mut answered = Vec::new();
    for screen in &screens {
        if answered.len() as i64 >= i64::from(max) {
            break;
        }
        for id in ids {
            if id.vidPnTargetId != screen.target
                || id.displayAdapterLuid.LowPart != screen.adapter.LowPart
                || id.displayAdapterLuid.HighPart != screen.adapter.HighPart
            {
                continue;
            }
            let mut target = COMPOSITION_TARGET_STATS::default();
            // SAFETY: an id the compositor gave, and a local to write.
            if unsafe { (compositor.target_statistics)(frame, id, &mut target) }.is_err()
                || target.presentedStats.time == 0
            {
                continue;
            }
            // 🚨THE MODE'S PERIOD, NOT THE LAST REFRESH'S (2026-11-02): a screen
            // that stretches a refresh for a late picture says so in
            // vblankDuration — 16.68ms, then 18.6 — and a grid laid at 18.6 is
            // off by two milliseconds a refresh.
            answered.push((micros(target.presentedStats.time as i64), screen.period_ns));
            break;
        }
    }
    answered
}

/// The timer the wait sleeps on: high-resolution where the system has one
/// (Windows 10 1803 on), the plain one otherwise — it only wakes coarser,
/// and the spin at the end takes up the rest. Held as its address: a handle
/// is not shared between threads by type, and this one is the process's.
fn timer() -> Option<HANDLE> {
    static TIMER: OnceLock<usize> = OnceLock::new();
    let held = *TIMER.get_or_init(|| {
        let access = TIMER_ALL_ACCESS.0;
        // SAFETY: an unnamed timer with no attributes.
        unsafe {
            CreateWaitableTimerExW(None, PCWSTR::null(), CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, access)
                .or_else(|_| CreateWaitableTimerExW(None, PCWSTR::null(), 0, access))
        }
        .map_or(0, |timer| timer.0 as usize)
    });
    (held != 0).then_some(HANDLE(held as *mut c_void))
}

pub(crate) fn wait_until(deadline_us: i64) {
    const SPIN_US: i64 = 500;
    let sleep_us = deadline_us - SPIN_US - now();
    if sleep_us > 0
        && let Some(timer) = timer()
    {
        // Relative due times are negative, in 100ns units.
        let due = -sleep_us * 10;
        // SAFETY: the process's timer, and a local due time.
        unsafe {
            if SetWaitableTimer(timer, &due, 0, None, None, false).is_ok() {
                WaitForSingleObject(timer, (sleep_us / 1000 + 2) as u32);
            }
        }
    }
    while now() < deadline_us {
        std::hint::spin_loop();
    }
}

type CreateDevice = unsafe extern "system" fn(*mut c_void, *const GUID, *mut *mut c_void) -> HRESULT;

fn create_device() -> Option<CreateDevice> {
    static CREATE: OnceLock<Option<CreateDevice>> = OnceLock::new();
    *CREATE.get_or_init(|| {
        let found = system_function(w!("dcomp.dll"), s!("DCompositionCreateDevice2"))?;
        // SAFETY: dcomp.h's declaration.
        Some(unsafe { transmute::<unsafe extern "system" fn() -> isize, CreateDevice>(found) })
    })
}

/// The compositor kept composing on every vblank while a clock runs — what
/// lands a clock's frame on the glass on the same vblank after the one it
/// claimed, every time (the app's PresentPacing).
///
/// 🚨WINDOWS' COMPOSITOR COMPOSES ON DEMAND (measured 2026-10-13 on a 144Hz
/// screen, the compositor's own per-frame statistics against the vblank a
/// frame claimed): a composition frame reaches the glass on the second
/// vblank after it STARTS, and an idle compositor starts one the moment a
/// picture is handed to it, a busy one only at the next vblank. So the same
/// hand-off reached the glass two vblanks on or three, as the rest of the
/// desktop happened to keep the compositor idle or busy — 39-47 film frames
/// in a hundred a refresh off their neighbours. A compositor that is never
/// idle takes every picture at the vblank after it is handed over: one
/// visual with nothing in it, swaying forever on a composition target of the
/// app's own window, gives it a change to show at every vblank and nothing
/// to see.
/// 🔬A flip-model test window handed over 0.5-5.5ms past a vblank: on the
/// glass three vblanks on, 100 in a hundred, with a swaying visual of any
/// window of any process on the screen; 45-56 in a hundred off without.
///
/// Released in this order: the sway, the visual, the target, the device.
struct Composing {
    _sway: IDCompositionAnimation,
    _visual: IDCompositionVisual2,
    target: IDCompositionTarget,
    device: IDCompositionDesktopDevice,
}

// SAFETY: one process-wide set, asked from one thread at a time behind
// COMPOSING's lock.
unsafe impl Send for Composing {}

static COMPOSING: Mutex<Option<Composing>> = Mutex::new(None);

/// Takes the swaying visual off the target, so the compositor rests.
fn rest(target: &IDCompositionTarget, device: &IDCompositionDesktopDevice) {
    // SAFETY: a live target and its device.
    unsafe {
        let _ = target.SetRoot(None);
        let _ = device.Commit();
    }
}

fn start() -> Option<Composing> {
    let create = create_device()?;
    let window = app_window()?;
    let mut raw = null_mut();
    // No rendering device: the visual never has content to draw.
    // SAFETY: dcomp.h's contract — a device of the interface asked for.
    unsafe { create(null_mut(), &IDCompositionDesktopDevice::IID, &mut raw) }.ok().ok()?;
    // SAFETY: what the call above handed over, owned from here.
    let device = unsafe { IDCompositionDesktopDevice::from_raw(raw) };
    // SAFETY: the app's window, in this process.
    let target = unsafe { device.CreateTargetForHwnd(window, true) }.ok()?;
    // SAFETY: objects of this device, each live while it is called.
    let built = unsafe {
        (|| {
            let visual = device.CreateVisual()?;
            let sway = device.CreateAnimation()?;
            sway.AddSinusoidal(0.0, 0.0, 1.0, 31.0, 0.0)?;
            visual.SetOffsetX(&sway)?;
            target.SetRoot(&visual)?;
            device.Commit()?;
            windows::core::Result::Ok((visual, sway))
        })()
    };
    match built {
        Ok((visual, sway)) => Some(Composing { _sway: sway, _visual: visual, target, device }),
        Err(_) => {
            rest(&target, &device);
            None
        }
    }
}

pub(crate) fn compose(on: bool) -> bool {
    let mut composing = COMPOSING.lock().unwrap_or_else(PoisonError::into_inner);
    if !on {
        if let Some(stopped) = composing.take() {
            rest(&stopped.target, &stopped.device);
        }
        return false;
    }
    if composing.is_none() {
        *composing = start();
    }
    composing.is_some()
}
