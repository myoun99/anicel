//! What the OS says of memory (native-to-rust; the C was qa_engine.c's four
//! memory questions): the machine's RAM, what this process holds, what more
//! it may take, and what the OS lets this app hold all in — the numbers the
//! app's budgets scale from and its memory census shows.
//!
//! Each is None where the platform will not say. The exports answer 0 then,
//! as the C did, and the app's side reads 0 as "not said" (`QaMemory`,
//! which binds them in the engine's library).
//!
//! ↩️The rest of qa_engine.c did not come here: its pixel work was the GPU
//! engine's kernels already, and its premultiply a formula one of them
//! holds (native-to-rust 11-07 14:02 — the table of the file). Its tile
//! blocks' lists and its premultiplied copy came to crates of their own
//! (native/tile_blocks, 2026-11-12; native/premultiply, 2026-11-13), and
//! the file went with them.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, PoisonError};
use std::time::{Duration, Instant};

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

mod smaps;
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

/// The mappings that hold the most of [`footprint`], each name with its
/// MiB, and how long the read took — a line for the measurement readout
/// (card the-first-pen-down-adds-850-mb-on-the-galaxy-tab: the Galaxy Tab's
/// footprint grew 850 MB at the first pen-down, and only a per-mapping
/// account names whose). None where the platform keeps no such account,
/// and till the first read lands.
///
/// 🗣️브러시/렌더링 2026-11-24 19:25 (the readout's owner): the whole of
/// /proc/self/smaps is far dearer than the rollup — the kernel walks every
/// mapping's pages under the mmap lock — so it is read on a thread of its
/// own, never the caller's, and no oftener than [`MAPPINGS_EVERY`]: a
/// readout that measures jank must not make it. The caller gets the last
/// line read.
pub fn mappings() -> Option<String> {
    let told = MAPPINGS_TOLD.lock().unwrap_or_else(PoisonError::into_inner);
    let stale = told.as_ref().is_none_or(|(at, _)| at.elapsed() >= MAPPINGS_EVERY);
    let line = told.as_ref().and_then(|(_, line)| line.clone());
    drop(told);
    if stale && !MAPPINGS_READING.swap(true, Ordering::AcqRel) {
        let read = std::thread::Builder::new().name("smaps".into()).spawn(|| {
            let started = Instant::now();
            let line = os::mappings().map(|held| mappings_line(&held, started.elapsed()));
            *MAPPINGS_TOLD.lock().unwrap_or_else(PoisonError::into_inner) =
                Some((Instant::now(), line));
            MAPPINGS_READING.store(false, Ordering::Release);
        });
        if read.is_err() {
            MAPPINGS_READING.store(false, Ordering::Release);
        }
    }
    line
}

/// How seldom [`mappings`] reads: the readout publishes about once a
/// second, and this is a few of its windows.
const MAPPINGS_EVERY: Duration = Duration::from_secs(5);
/// The names a [`mappings`] line gives — what fits the readout's width.
const MAPPINGS_NAMED: usize = 4;

static MAPPINGS_TOLD: Mutex<Option<(Instant, Option<String>)>> = Mutex::new(None);
static MAPPINGS_READING: AtomicBool = AtomicBool::new(false);

/// The [`mappings`] line of an account, the most first, and the read's time.
fn mappings_line(held: &[(String, u64)], took: Duration) -> String {
    let named: Vec<String> = held
        .iter()
        .take(MAPPINGS_NAMED)
        .map(|(name, bytes)| format!("{name} {:.1}", *bytes as f64 / (1 << 20) as f64))
        .collect();
    format!("{}  read {} ms", named.join("  "), took.as_millis())
}

/// As much of `line` as `out` holds, cut at a character's end: the bytes
/// written.
fn fill(line: &str, out: &mut [u8]) -> usize {
    let mut end = line.len().min(out.len());
    while !line.is_char_boundary(end) {
        end -= 1;
    }
    out[..end].copy_from_slice(&line.as_bytes()[..end]);
    end
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

/// [`mappings`] as UTF-8 into the `room` bytes at `out`: the bytes
/// written, 0 for none.
///
/// # Safety
/// `out` is valid for writes of `room` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_process_mappings(out: *mut u8, room: usize) -> i64 {
    let Some(line) = mappings() else { return 0 };
    if out.is_null() {
        return 0;
    }
    // SAFETY: the caller hands `room` bytes at `out`.
    let out = unsafe { std::slice::from_raw_parts_mut(out, room) };
    fill(&line, out) as i64
}
