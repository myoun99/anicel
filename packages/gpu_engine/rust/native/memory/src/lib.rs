//! What the OS says of memory (native-to-rust; the C was qa_engine.c's four
//! memory questions): the machine's RAM, what this process holds, what more
//! it may take, and what the OS lets this app hold all in — the numbers the
//! app's budgets scale from and its memory census shows.
//!
//! Each is None where the platform will not say. The exports answer 0 then,
//! as the C did, and the app's side reads 0 as "not said" (`QaMemory`,
//! which binds them in the engine's library).
//!
//! The rest of qa_engine.c does not come here: its pixel work is the GPU
//! engine's kernels already, and its premultiply is a formula one of them
//! holds (native-to-rust 11-07 14:02 — the table of the file).

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

#[cfg(target_vendor = "apple")]
mod apple;
#[cfg(not(any(windows, target_vendor = "apple")))]
mod linux;
#[cfg(windows)]
mod windows;

#[cfg(target_vendor = "apple")]
use self::apple as os;
#[cfg(not(any(windows, target_vendor = "apple")))]
use self::linux as os;
#[cfg(windows)]
use self::windows as os;

#[cfg(test)]
mod tests;

/// The machine's physical RAM. The hot cel budget scales from it instead of
/// assuming a desktop-class machine (a 3 GB tablet was being asked to hold
/// 1.5 GB of hot cels).
pub fn physical() -> Option<u64> {
    os::physical()
}

/// What THIS PROCESS holds right now: the bytes that belong to it alone and
/// come back when it exits.
///
/// ONE QUESTION, ANSWERED BY EVERY PLATFORM IN ITS OWN WORDS — the number
/// each OS puts next to the app in its own task manager: Task Manager's
/// "Memory" column, Activity Monitor's "Memory", the one a jetsam report
/// calls `rpages × pageSize`. The user asked for the panel to show that same
/// number (2026-09-10). [`physical`] answers a different question, and had
/// been standing in for this one.
pub fn footprint() -> Option<u64> {
    os::footprint()
}

/// How much more this process may take before the OS stops it. On iOS that
/// is the real ceiling — what is left of the app's own allowance, which is
/// neither the device's free RAM nor a fraction of its total; elsewhere the
/// closest honest answer is the machine's free memory, and a Mac gives none.
pub fn available() -> Option<u64> {
    os::available()
}

/// What the OS lets THIS APP hold all in — what it holds now and what it may
/// still take: the ceiling a jetsam decision is made against. None where the
/// OS gives an app no limit of its own: a desktop's free memory is the
/// machine's, not this app's. C-ipad-crash (ABI 36): the automatic allowance
/// is half of this where it exists and half the RAM where it does not.
pub fn app_limit() -> Option<u64> {
    os::app_limit()
}

/// An answer as the exports give it: 0 for none.
fn said(bytes: Option<u64>) -> i64 {
    bytes.map_or(0, |bytes| i64::try_from(bytes).unwrap_or(i64::MAX))
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_physical_memory_bytes() -> i64 {
    said(physical())
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_process_footprint_bytes() -> i64 {
    said(footprint())
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_available_memory_bytes() -> i64 {
    said(available())
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_app_memory_limit_bytes() -> i64 {
    said(app_limit())
}
