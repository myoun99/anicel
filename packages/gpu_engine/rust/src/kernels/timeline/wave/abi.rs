//! The waveform's C ABI (the-waveform-is-drawn-on-the-cpu-beside-its-kernel,
//! 관제 2026-11-14): a sound's peaks handed over once and kept on the GPU,
//! and a strip's stretch of them drawn into a frame grid's picture
//! (`GridPicture`) over clear — which the view's screen lays as it lays the
//! grid's tiles (`gpu_engine_grid_lay`): nothing comes back but whether it
//! drew.

#[cfg(test)]
mod tests;

use crate::device::{Engine, let_go};
use crate::kernels::timeline::grid::GridPicture;

use super::{WavePeaks, WaveTile, WaveView};

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

/// # Safety
/// `peaks` came from `gpu_engine_wave_peaks_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_wave_peaks_free(peaks: *mut WavePeaks) {
    // SAFETY: see the function's contract.
    unsafe { let_go(peaks) };
}

/// Draws `peaks` into `picture` over clear as the strip shows them
/// ([`WaveView`]'s fields, in its order) — submitted, not waited for
/// ([`WaveTile::run`]). False for a view the pass refuses, and on failure;
/// see the last error.
///
/// ⚠️Over clear, always, as a grid's tile is (`gpu_engine_grid_draw`): the
/// picture lays over what the strip stands on.
///
/// # Safety
/// Every pointer is live, made on `engine`.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_wave_draw(
    wave: *mut WaveTile,
    engine: *const Engine,
    picture: *const GridPicture,
    peaks: *const WavePeaks,
    along0: i32,
    vertical: bool,
    frame_q8: i32,
    fps_numerator: u32,
    fps_denominator: u32,
    buckets_per_second: u32,
    leading_frames: i32,
    across_q8: i32,
    gain_q16: i32,
    rgba: u32,
) -> bool {
    // SAFETY: see the function's contract.
    let (wave, engine, picture, peaks) = unsafe { (&mut *wave, &*engine, &*picture, &*peaks) };
    engine.on_thread(|| {
        let view = WaveView {
            along0,
            vertical,
            frame_q8,
            fps: (fps_numerator, fps_denominator),
            buckets_per_second,
            leading_frames,
            across_q8,
            gain_q16,
            rgba,
            background: 0,
        };
        wave.run(engine, &picture.texture, peaks, &view).is_some()
    })
}
