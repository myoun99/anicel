//! The waveform's C ABI (the-waveform-is-drawn-on-the-cpu-beside-its-kernel,
//! 관제 2026-11-14): a sound's peaks handed over once and kept on the GPU,
//! and a strip's stretch of them drawn into a frame grid's picture
//! (`GridPicture`) over what it holds — the row's own tile, which the
//! view's screen lays (`gpu_engine_grid_lay`): nothing comes back but
//! whether it drew. ↩️Over clear, a picture of the wave's own, till the
//! card's Q2 (유저 2026-11-14 「(가)」). A sound is drawn as a batch of the
//! grid's draws (`gpu_engine_grid_flush`). ↩️It was drawn alone
//! (`gpu_engine_wave_draw`), and submitted.

#[cfg(test)]
mod tests;

use crate::device::{Engine, let_go, let_go_unwaited};

use super::{WavePeaks, WaveTile};

/// The waveform pass, compiled here for the pictures it draws
/// ([`WaveTile::for_pictures`]): an app asks off the thread its frames are
/// built on.
///
/// # Safety
/// `engine` is live; the pass is freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_wave_new(engine: *const Engine) -> *mut WaveTile {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.on_thread(|| engine.hands(WaveTile::for_pictures(engine)))
}

/// # Safety
/// `wave` came from `gpu_engine_wave_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_wave_free(wave: *mut WaveTile) {
    // SAFETY: see the function's contract.
    unsafe { let_go(wave) };
}

/// A sound's peaks on the GPU: `lanes` lanes of `buckets` q16 peaks each,
/// one lane after another ([`WavePeaks::new`]). Null on failure; see the
/// last error.
///
/// # Safety
/// `engine` is live and `peaks` holds `lanes × buckets` values; the peaks
/// are freed before the engine.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_wave_peaks_new(
    engine: *const Engine,
    peaks: *const u16,
    lanes: usize,
    buckets: usize,
) -> *mut WavePeaks {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.on_thread(|| {
        let all = match lanes * buckets {
            // None: its pointer may be null, which no slice may be.
            0 => &[][..],
            // SAFETY: see the function's contract.
            count => unsafe { std::slice::from_raw_parts(peaks, count) },
        };
        let lanes: Vec<&[u16]> = (0..lanes).map(|lane| &all[lane * buckets..][..buckets]).collect();
        WavePeaks::new(engine, &lanes).map_or(std::ptr::null_mut(), |made| engine.hands(made))
    })
}

/// The GC lets go of a sound's peaks (`GpuWavePeaks`), so this waits for
/// none of it ([`let_go_unwaited`] has why); they count nothing.
///
/// # Safety
/// `peaks` came from `gpu_engine_wave_peaks_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_wave_peaks_free(peaks: *mut WavePeaks) {
    // SAFETY: see the function's contract.
    unsafe { let_go_unwaited(peaks) };
}
