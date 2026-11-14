//! Media Foundation, started ONCE for the life of the process and never shut
//! down — the one place the engine starts it.
//!
//! 🗣️유저 2026-10-22, board the-trimmed-movie-test-can-hang-on-windows-ci-Q3:
//! 「MF 를 한 번 켜 두고 끄지 않는다」 — the engine starts MF the first time it
//! uses it, does not stop it when its objects close, and the places that
//! start it (video decode, video encode, audio decode, the HEVC probe) start
//! it through this one function.
//!
//! ↩️Each of those objects used to pair its own MFStartup with an MFShutdown
//! on close, so MF's count fell to zero whenever the last reader, writer or
//! probe closed, and rose again with the next. Both dumps of the Windows CI
//! hang (2026-10-17, 10-22) stood in the same place: the first ReadSample of
//! a reader opened right after a trim had closed every MF object, waiting
//! with no limit on an event that nothing anywhere was queued to signal. Why
//! MF loses that wake-up the dumps cannot say — the condition, down to zero
//! and straight back up, is ours to remove. MFStartup once when the
//! application starts is also how Media Foundation asks to be used.
//!
//! ⛔Nothing in the engine shuts it down. The answer's cost: MF's few threads
//! and a little memory stay until the process ends, and whether the hang is
//! gone is known only by the next sighting not coming — it never reproduced
//! (13,000 runs, 2026-10-16).
//!
//! 🔄**It came (2026-11-09, main PC):** with MF up the whole time, the first
//! ReadSample after a seek back still stood for good — about once in 2,000
//! runs of the decoder's read order (board
//! a-seek-back-can-leave-the-movie-read-waiting-forever). Down to zero and
//! back up was not the only way in. Starting once stays the rule — it is
//! still how MF asks to be used — and a reader that stands is now let go
//! and opened afresh (`video/src/decode/reading.rs`).

use std::sync::Mutex;

use windows::Win32::Media::MediaFoundation::{MF_VERSION, MFSTARTUP_LITE, MFStartup};

pub mod span_stream;

/// Held while a caller starts MF, so two threads opening their first medium
/// at once start it once between them; true once it is up.
static UP: Mutex<bool> = Mutex::new(false);

/// Whether Media Foundation is up, starting it the first time it is asked —
/// and again after a start that failed.
pub fn up() -> bool {
    let mut up = UP.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    if !*up {
        // SAFETY: MFStartup takes no pointers.
        *up = unsafe { MFStartup(MF_VERSION, MFSTARTUP_LITE) }.is_ok();
    }
    *up
}

#[cfg(test)]
mod tests;
