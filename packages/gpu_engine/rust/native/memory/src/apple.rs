//! Apple: the hardware's memory size, and the task's VM info. Only the
//! iPhone family (iOS and iPadOS — TARGET_OS_IPHONE) gives an app an
//! allowance of its own.

use std::mem::size_of;
use std::ptr::null_mut;

use mach2::kern_return::KERN_SUCCESS;
use mach2::message::mach_msg_type_number_t;
use mach2::task::task_info;
use mach2::task_info::{TASK_VM_INFO, task_vm_info};
use mach2::traps::mach_task_self;
use mach2::vm_types::natural_t;

pub(crate) fn physical() -> Option<u64> {
    let mut bytes: i64 = 0;
    let mut length = size_of::<i64>();
    let mut name = [libc::CTL_HW, libc::HW_MEMSIZE];
    // SAFETY: a two-level name, and an i64 to write that the length names.
    let said = unsafe {
        libc::sysctl(
            name.as_mut_ptr(),
            2,
            (&raw mut bytes).cast(),
            &mut length,
            null_mut(),
            0,
        )
    };
    (said == 0).then_some(bytes as u64)
}

/// The footprint the system's own tools and jetsam count: `phys_footprint`.
pub(crate) fn footprint() -> Option<u64> {
    let mut info = task_vm_info::default();
    // The header's TASK_VM_INFO_COUNT: the struct in natural_t words.
    let mut count = (size_of::<task_vm_info>() / size_of::<natural_t>()) as mach_msg_type_number_t;
    // SAFETY: this task's VM info, into a struct as long as the count says.
    let said = unsafe {
        task_info(mach_task_self(), TASK_VM_INFO, (&raw mut info).cast(), &mut count)
    };
    (said == KERN_SUCCESS).then_some(info.phys_footprint)
}

#[cfg(not(target_os = "macos"))]
unsafe extern "C" {
    /// <os/proc.h>: what is left of THIS APP's allowance — the only number
    /// that predicts a jetsam kill. Declared here: neither libc nor mach2
    /// binds it, and it is one function of no arguments.
    fn os_proc_available_memory() -> usize;
}

#[cfg(not(target_os = "macos"))]
pub(crate) fn available() -> Option<u64> {
    // SAFETY: no arguments; it only reads.
    Some(unsafe { os_proc_available_memory() } as u64)
}

#[cfg(target_os = "macos")]
pub(crate) fn available() -> Option<u64> {
    None
}

/// What it holds and what it may still take, as the C added them: with no
/// footprint, the allowance alone.
#[cfg(not(target_os = "macos"))]
pub(crate) fn app_limit() -> Option<u64> {
    Some(footprint().unwrap_or(0) + available().unwrap_or(0))
}

#[cfg(target_os = "macos")]
pub(crate) fn app_limit() -> Option<u64> {
    None
}
