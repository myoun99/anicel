//! Windows: the system's memory status, and the process's counters.

use std::mem::size_of;

use windows::Win32::System::ProcessStatus::{
    K32GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS, PROCESS_MEMORY_COUNTERS_EX2,
};
use windows::Win32::System::SystemInformation::{GlobalMemoryStatusEx, MEMORYSTATUSEX};
use windows::Win32::System::Threading::GetCurrentProcess;

fn status() -> Option<MEMORYSTATUSEX> {
    let mut status = MEMORYSTATUSEX {
        dwLength: size_of::<MEMORYSTATUSEX>() as u32,
        ..Default::default()
    };
    // SAFETY: a status to fill, its length set.
    unsafe { GlobalMemoryStatusEx(&mut status) }.ok()?;
    Some(status)
}

pub(crate) fn physical() -> Option<u64> {
    status().map(|status| status.ullTotalPhys)
}

/// PROCESS_MEMORY_COUNTERS_EX2 (Windows 10 1809 on) carries
/// PrivateWorkingSetSize: the RESIDENT bytes no other process shares, which
/// is what Task Manager's "Memory" column shows.
///
/// NOT PrivateUsage from the smaller EX struct: that is private COMMIT,
/// which on this app reads 237 MB where the working set reads 139 MB
/// (measured 2026-09-10). They are two different questions, so an older
/// Windows, which refuses a struct this long, says nothing — "not measured
/// here" — rather than a number that quietly means something else.
pub(crate) fn footprint() -> Option<u64> {
    let mut counters = PROCESS_MEMORY_COUNTERS_EX2 {
        cb: size_of::<PROCESS_MEMORY_COUNTERS_EX2>() as u32,
        ..Default::default()
    };
    // SAFETY: counters to fill, as long as `cb` says; EX2 begins as the
    // plain counters do.
    let said = unsafe {
        K32GetProcessMemoryInfo(
            GetCurrentProcess(),
            (&raw mut counters).cast::<PROCESS_MEMORY_COUNTERS>(),
            counters.cb,
        )
    };
    said.as_bool().then_some(counters.PrivateWorkingSetSize as u64)
}

pub(crate) fn available() -> Option<u64> {
    status().map(|status| status.ullAvailPhys)
}

pub(crate) fn app_limit() -> Option<u64> {
    None
}
