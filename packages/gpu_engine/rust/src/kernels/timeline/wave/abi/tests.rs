//! The waveform's C ABI on a real GPU: a sound drawn through it into a
//! frame grid's picture is the pass's own drawing of the same view — every
//! field handed in its place — over clear, and what it cannot keep or draw
//! is refused with why.

use super::*;
use crate::device::storage_texture;
use crate::kernels::timeline::grid::abi::{
    gpu_engine_grid_picture_free, gpu_engine_grid_picture_new, gpu_engine_grid_picture_read,
};
use crate::testing::{first_engine, last_error};

/// Two lanes of 24 buckets, no two alike.
fn lanes() -> Vec<u16> {
    (0..48u32).map(|i| ((i * 7919 + 13) % 65536) as u16 | 0x4000).collect()
}

/// A view whose every field moves the drawing: no two of them alike, so one
/// handed in another's place draws other pixels.
fn view(vertical: bool) -> WaveView {
    WaveView {
        along0: 3,
        vertical,
        frame_q8: 3 * 256 + 77,
        fps: (24000, 1001),
        buckets_per_second: 5,
        leading_frames: 2,
        across_q8: 20 * 256 + 31,
        gain_q16: 52429,
        rgba: 0xc8_30_a0_ff,
        background: 0,
    }
}

/// `view` drawn through the ABI into a fresh `width` × `height` picture:
/// whether it drew, and the picture's bytes.
fn through_the_abi(peaks: &[u16], lanes: usize, view: &WaveView, (width, height): (u32, u32)) -> (bool, Vec<u8>) {
    let engine = first_engine();
    // SAFETY: the engine is live, and `peaks` holds its lanes.
    let (wave, kept, picture) = unsafe {
        (
            gpu_engine_wave_new(engine),
            gpu_engine_wave_peaks_new(engine, peaks.as_ptr(), lanes, peaks.len() / lanes),
            gpu_engine_grid_picture_new(engine, width, height),
        )
    };
    assert!(!kept.is_null() && !picture.is_null(), "{}", last_error());
    // SAFETY: every pointer is live and made on the engine.
    let ok = unsafe {
        gpu_engine_wave_draw(
            wave,
            engine,
            picture,
            kept,
            view.along0,
            view.vertical,
            view.frame_q8,
            view.fps.0,
            view.fps.1,
            view.buckets_per_second,
            view.leading_frames,
            view.across_q8,
            view.gain_q16,
            view.rgba,
        )
    };
    let mut bytes = vec![0; (width * height * 4) as usize];
    // SAFETY: both came from their news, and `bytes` holds its length.
    let read = unsafe { gpu_engine_grid_picture_read(engine, picture, bytes.as_mut_ptr(), bytes.len()) };
    assert!(read, "{}", last_error());
    // SAFETY: each let go of once.
    unsafe {
        gpu_engine_grid_picture_free(picture);
        gpu_engine_wave_peaks_free(kept);
        gpu_engine_wave_free(wave);
    }
    (ok, bytes)
}

/// The same drawn by the pass itself, on a picture of the grid's format.
fn by_the_pass(peaks: &[u16], lanes: usize, view: &WaveView, (width, height): (u32, u32)) -> Vec<u8> {
    let engine = first_engine();
    let lanes: Vec<&[u16]> = peaks.chunks(peaks.len() / lanes).collect();
    let kept = WavePeaks::new(engine, &lanes).expect("the pass keeps the peaks");
    let texture = storage_texture(engine.device(), width, height, GridPicture::FORMAT);
    WaveTile::new(engine).run(engine, &texture, &kept, view).expect("the pass draws the view");
    engine.read_texture(&texture).expect("the picture reads back")
}

#[test]
fn a_sound_drawn_through_the_abi_is_the_pass_s_own_drawing_over_clear() {
    let peaks = lanes();
    for (vertical, size) in [(false, (40, 22)), (true, (22, 40))] {
        let (ok, bytes) = through_the_abi(&peaks, 2, &view(vertical), size);
        assert!(ok, "{}", last_error());
        assert_eq!(bytes, by_the_pass(&peaks, 2, &view(vertical), size), "vertical: {vertical}");
        assert!(bytes.chunks(4).any(|pixel| pixel == [0; 4]), "premise: some of it is clear");
        assert!(bytes.chunks(4).any(|pixel| pixel[3] > 0), "premise: some of it is drawn");
    }
}

#[test]
fn peaks_it_cannot_keep_are_refused_with_why() {
    let engine = first_engine();
    // SAFETY: the engine is live; nothing is read of a pointer handed no
    // value.
    let none = unsafe { gpu_engine_wave_peaks_new(engine, std::ptr::null(), 0, 4) };
    assert!(none.is_null());
    assert!(last_error().contains("no lane"), "{}", last_error());
    // SAFETY: as above.
    let empty = unsafe { gpu_engine_wave_peaks_new(engine, std::ptr::null(), 2, 0) };
    assert!(empty.is_null());
    assert!(last_error().contains("the same buckets, and some"), "{}", last_error());
}

#[test]
fn a_view_the_pass_refuses_is_not_drawn_and_says_why() {
    let mut paceless = view(false);
    paceless.frame_q8 = 0;
    let (ok, bytes) = through_the_abi(&lanes(), 2, &paceless, (8, 8));
    assert!(!ok);
    assert!(last_error().contains("has no pace"), "{}", last_error());
    assert!(bytes.iter().all(|&byte| byte == 0), "nothing is drawn of it");
}
