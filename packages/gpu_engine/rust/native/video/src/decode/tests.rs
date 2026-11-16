//! The decode law, run — the C test's checks (↩️`qa_video_decode_law_test.c`,
//! until the connection round deleted it), here where the law is (the colour
//! half is `colour/tests.rs`'s). The arithmetic below is exactly where the
//! C's three decoders disagreed.

use std::ffi::CStr;
use std::sync::{Mutex, MutexGuard, PoisonError};

use super::*;
use crate::colour::tests::by_hand;
use crate::colour::{BT601, BT709, UNSPECIFIED};

/// The error buffer and the slots are the process's: a test that reads
/// either holds this, so another's failure does not answer for its own.
fn one_at_a_time() -> MutexGuard<'static, ()> {
    static ONE_AT_A_TIME: Mutex<()> = Mutex::new(());
    ONE_AT_A_TIME.lock().unwrap_or_else(PoisonError::into_inner)
}

fn last_error() -> String {
    // SAFETY: the buffer is NUL-terminated, and this test's own lock keeps
    // the next failure from rewriting it under the read.
    unsafe { CStr::from_ptr(qa_video_decode_last_error()) }.to_string_lossy().into_owned()
}

#[test]
fn a_rate_is_an_exact_fraction() {
    // 🚨THE ONE THAT WAS WRONG ON ANDROID: `frame-rate` read as an int with
    // the denominator pinned to 1, so these became 30/1 and 24/1.
    assert_eq!(rate_to_fraction(29.97), (30000, 1001));
    assert_eq!(rate_to_fraction(23.976), (24000, 1001));
    assert_eq!(rate_to_fraction(59.94), (60000, 1001));
    // Integers stay integers — 24 must not become 24024/1001.
    assert_eq!(rate_to_fraction(24.0), (24, 1));
    assert_eq!(rate_to_fraction(30.0), (30, 1));
    assert_eq!(rate_to_fraction(25.0), (25, 1));
    // ⛔No declared rate still has frames: 24, made here for every backend.
    assert_eq!(rate_to_fraction(0.0), (24, 1));
    assert_eq!(rate_to_fraction(-12.0), (24, 1));
    assert_eq!(rate_to_fraction(100000.0), (24, 1));
    assert_eq!(rate_to_fraction(f64::NAN), (24, 1));
}

#[test]
fn a_movie_counts_to_the_nearest_frame_and_at_least_one() {
    assert_eq!(frame_count_for((2_000_000, 1_000_000), (24, 1)), 48, "two seconds at 24");
    assert_eq!(frame_count_for((1_001_000, 1_000_000), (30000, 1001)), 30, "1001 counts in real time");
    assert_eq!(frame_count_for((0, 1_000_000), (24, 1)), 1, "nothing long is one frame");
    assert_eq!(frame_count_for((1000, 1_000_000), (24, 1)), 1, "a sliver is one frame");
    assert_eq!(frame_count_for((5_000_000, 1_000_000), (0, 0)), 1, "no rate is one frame");
    // 🚨A TICK SHORT OF WHOLE FRAMES IS WHOLE FRAMES, for every backend.
    assert_eq!(frame_count_for((11999, 24000), (24, 1)), 12, "the track a tick short of twelve");
    assert_eq!(frame_count_for((499_958, 1_000_000), (24, 1)), 12, "AVFoundation's µs of it");
    assert_eq!(frame_count_for((4_999_999, 10_000_000), (24, 1)), 12, "Media Foundation's rounded end");
    // To the nearest, not up.
    assert_eq!(frame_count_for((516_667, 1_000_000), (24, 1)), 12, "12.4 frames");
    assert_eq!(frame_count_for((525_000, 1_000_000), (24, 1)), 13, "12.6 frames");
    // ⚠️What a container may claim does not overflow into an abort.
    assert_eq!(frame_count_for((i64::MAX, 1), (1000, 1)), i64::MAX, "an absurd length saturates");
}

#[test]
fn a_frame_has_one_time_for_every_backend() {
    // Exact at 29.97: frame 30000 is 1001 seconds, which a frame length cut
    // to whole 100 ns first (the C's Windows) puts 0.67 × 30000 ticks early.
    assert_eq!(ticks_at(30000, 10_000_000, (30000, 1001)), 10_010_000_000);
    assert_eq!(ticks_at(48, 1_000_000, (24, 1)), 2_000_000);
    assert_eq!(ticks_at(0, 1_000_000, (30000, 1001)), 0);
    assert_eq!(frame_ticks(10_000_000, (30000, 1001)), 333_666, "a frame, cut to whole ticks");
    assert_eq!(frame_ticks(1_000_000, (24, 1)), 41_666);
}

#[test]
fn a_sample_reaches_its_target_with_half_a_frame_of_slack() {
    assert!(sample_reaches(1000, 900, 100), "past it");
    assert!(sample_reaches(900, 900, 100), "on it");
    assert!(sample_reaches(860, 900, 100), "within half a frame");
    assert!(!sample_reaches(840, 900, 100), "more than half a frame early");
}

#[test]
fn a_turn_folds_into_four() {
    // 🚨THE ONE ONLY APPLE KNEW. Negatives are Android's counter-clockwise.
    assert_eq!(rotation_quarter(0), 0);
    assert_eq!(rotation_quarter(90), 90);
    assert_eq!(rotation_quarter(-90), 270);
    assert_eq!(rotation_quarter(360), 0);
    assert_eq!(rotation_quarter(450), 90);
    assert_eq!(rotation_quarter(-270), 90);
    assert_eq!(rotation_quarter(-45), 0, "less than a quarter is none");
}

#[test]
fn a_turn_changes_the_picture_and_its_shape() {
    // 3x2, so a quarter turn is visibly a DIFFERENT SHAPE. Red = the index:
    //   0 1 2
    //   3 4 5
    let stored: Vec<u8> = (0..6u8).flat_map(|i| [i, 0, 0, 255]).collect();
    let turned = |rotation| {
        let mut out = vec![0u8; 24];
        rotate(&stored, (3, 2), 4, rotation, &mut out);
        out
    };
    let reds = |out: &[u8]| out.chunks(4).map(|pixel| pixel[0]).collect::<Vec<_>>();
    // 90° clockwise: the top-left goes to the top-right.
    assert_eq!(reds(&turned(90)), [3, 0, 4, 1, 5, 2]);
    assert_eq!(reds(&turned(180)), [5, 4, 3, 2, 1, 0]);
    assert_eq!(reds(&turned(270)), [2, 5, 1, 4, 0, 3]);
    assert_eq!(reds(&turned(0)), [0, 1, 2, 3, 4, 5]);
    // ⚠️And the alpha rides along — RGB alone would hand back a clear frame.
    assert!(turned(90).chunks(4).all(|pixel| pixel[3] == 255));
}

#[test]
fn an_nv12_frame_turns_as_its_picture_does() {
    // 4x2 NV12: luma = the index, each 2x2 block's pair (10+block, 20+block).
    //   Y: 0 1 2 3     CbCr: (10,20) (11,21)
    //      4 5 6 7
    let stored: Vec<u8> = (0..8u8).chain([10, 20, 11, 21]).collect();
    let mut out = vec![0u8; stored.len()];
    turn(&stored, Pixels::Nv12, (4, 2), 90, &mut out);
    // Shown 2x4: the luma turned as RGBA's pixels are, and the left block's
    // pair on top — each pair whole, Cb before Cr.
    assert_eq!(&out[..8], [4, 0, 5, 1, 6, 2, 7, 3]);
    assert_eq!(&out[8..], [10, 20, 11, 21]);
    turn(&stored, Pixels::Nv12, (4, 2), 180, &mut out);
    assert_eq!(out, [7, 6, 5, 4, 3, 2, 1, 0, 11, 21, 10, 20]);
    // An odd frame is turned at the even size it is handed at.
    let odd: Vec<u8> = (0..4u8).chain([10, 20]).collect();
    let mut out = vec![0u8; odd.len()];
    turn(&odd, Pixels::Nv12, (1, 1), 270, &mut out);
    assert_eq!(out, [1, 3, 0, 2, 10, 20]);
}

#[test]
fn a_frame_is_turned_upright_where_it_is_read() {
    // The stored 3x2 of the test above, as a backend hands it over.
    let stored: Vec<u8> = (0..6u8).flat_map(|i| [i, 0, 0, 255]).collect();
    let read = |into: &mut [u8]| -> Result<(), Why> {
        assert_eq!(into.len(), stored.len(), "a backend is handed the STORED size");
        into.copy_from_slice(&stored);
        Ok(())
    };
    let shape = |rotation, shown| Shape {
        stored: (3, 2),
        rotation,
        shown,
        rate: (24, 1),
        frame_count: 1,
        pixels: Pixels::Rgba,
        // A reader of RGBA — Apple's, of a movie with alpha: no sum here.
        decodes: Pixels::Rgba,
        colours: Colours::NONE,
    };
    let (mut scratch, mut out) = (Vec::new(), vec![0u8; 24]);
    upright(&shape(90, (2, 3)), &mut scratch, &mut out, read).expect("read");
    assert_eq!(out.chunks(4).map(|pixel| pixel[0]).collect::<Vec<_>>(), [3, 0, 4, 1, 5, 2], "turned");
    assert_eq!(scratch.len(), 24, "through the scratch, which is kept");
    let mut direct = vec![0u8; 24];
    upright(&shape(0, (3, 2)), &mut Vec::new(), &mut direct, read).expect("read");
    assert_eq!(direct, stored, "an upright movie is read straight into the caller's buffer");
    let mut untouched = vec![9u8; 24];
    let failed = upright(&shape(270, (2, 3)), &mut scratch, &mut untouched, |_| Err("no".into()));
    assert_eq!(failed.err().as_deref(), Some("no"), "a read's failure is the frame's");
    assert!(untouched.iter().all(|&byte| byte == 9), "and turns nothing into the caller's buffer");
}

// 🚨A document of RGBA is made of the decoder's NV12 by the law, after its
// turn: each pixel turned with its own 2×2 block's chroma, by the sums the
// movie names — the size's where it names none (유저 11-16, movie-frames-
// come-as-their-yuv-to-the-engine-Q1: this 4×2 is BT.601's).
#[test]
fn a_document_of_rgba_is_made_of_its_nv12_after_its_turn() {
    // Stored 4x2: luma 16 + 20·i, the left block's chroma red, the right's grey.
    let stored: Vec<u8> = (0..8u8).map(|i| 16 + 20 * i).chain([90, 240, 128, 128]).collect();
    let read = |into: &mut [u8]| -> Result<(), Why> {
        assert_eq!(into.len(), stored.len(), "the reader is handed the stored NV12");
        into.copy_from_slice(&stored);
        Ok(())
    };
    let shape = |matrix| Shape {
        stored: (4, 2),
        rotation: 90,
        shown: (2, 4),
        rate: (24, 1),
        frame_count: 1,
        pixels: Pixels::Rgba,
        decodes: Pixels::Nv12,
        colours: Colours { matrix, ..Colours::NONE },
    };
    for (matrix, sums) in [(UNSPECIFIED, BT601[0]), (1, BT709[0])] {
        let mut out = vec![0u8; 4 * 2 * 4];
        upright(&shape(matrix), &mut Vec::new(), &mut out, read).expect("read");
        for (x, y) in (0..4).flat_map(|x| (0..2).map(move |y| (x, y))) {
            let (cb, cr) = if x < 2 { (90, 240) } else { (128, 128) };
            let want = by_hand(stored[y * 4 + x], cb, cr, sums);
            // A quarter turn puts the stored top-left at the shown top-right.
            let at = (x * 2 + (1 - y)) * 4;
            assert_eq!(out[at..at + 4], want, "matrix {matrix}: stored ({x}, {y})");
        }
    }
}

// ⚠️The size a movie that names no matrix is read by is the STORED one —
// the picture as its encoder wrote it, before its turn — so an SD movie
// held sideways is SD stood up too. 578×2 is SD as stored and more than
// 576 tall as shown.
#[test]
fn a_movie_that_names_no_matrix_is_sized_as_stored() {
    let (width, height) = (578usize, 2usize);
    let stored = [vec![100u8; width * height], [90u8, 240].repeat(width / 2)].concat();
    let shape = Shape {
        stored: (578, 2),
        rotation: 90,
        shown: (2, 578),
        rate: (24, 1),
        frame_count: 1,
        pixels: Pixels::Rgba,
        decodes: Pixels::Nv12,
        colours: Colours::NONE,
    };
    let mut out = vec![0u8; width * height * 4];
    let read = |into: &mut [u8]| -> Result<(), Why> {
        into.copy_from_slice(&stored);
        Ok(())
    };
    upright(&shape, &mut Vec::new(), &mut out, read).expect("read");
    let (sd, hd) = (by_hand(100, 90, 240, BT601[0]), by_hand(100, 90, 240, BT709[0]));
    assert_ne!(sd, hd, "the two matrices tell this pixel apart");
    assert!(out.chunks(4).all(|pixel| pixel == sd), "BT.601, as stored");
}

#[test]
fn the_law_settles_size_rate_and_length_once() {
    let colours = Colours { primaries: 1, transfer: 1, matrix: 1, range: 0 };
    let opened = |rotation, rate, length| Opened {
        stored_width: 1920,
        stored_height: 1080,
        colours,
        decodes: Pixels::Nv12,
        rotation,
        rate,
        length,
    };
    let shape = |opened| settle(opened, Pixels::Nv12).unwrap_or_else(|why| panic!("{why}"));
    let upright = shape(opened(-270, Rate::Fraction(30000, 1001), (10_010_000, 10_000_000)));
    let want = Shape {
        stored: (1920, 1080),
        rotation: 90,
        shown: (1080, 1920),
        rate: (30000, 1001),
        frame_count: 30,
        pixels: Pixels::Nv12,
        decodes: Pixels::Nv12,
        colours,
    };
    let said = "a quarter turn swaps the sides; 1.001 s at 29.97 is thirty; the colours and the pixels ride along";
    assert_eq!(upright, want, "{said}");
    let half = shape(opened(180, Rate::Nominal(23.976), (1_001_000, 1_000_000)));
    assert_eq!((half.shown, half.rate, half.frame_count), ((1920, 1080), (24000, 1001), 24), "a half turn does not");
    // ⚠️No declared rate is 24 BEFORE counting, for every backend.
    let unrated = shape(opened(0, Rate::Fraction(0, 0), (2_000_000, 1_000_000)));
    assert_eq!((unrated.rate, unrated.frame_count), ((24, 1), 48));
    let sizeless = Opened { stored_height: 0, ..opened(0, Rate::Nominal(24.0), (1, 1)) };
    assert_eq!(settle(sizeless, Pixels::Rgba).err().as_deref(), Some("the video stream has no frame size"));
}

#[test]
fn the_first_free_slot_is_taken_and_none_past_the_last() {
    let _turn = one_at_a_time();
    let held: Vec<usize> = std::iter::from_fn(take).collect();
    assert!(!held.is_empty(), "LIVENESS: a slot was free");
    assert_eq!(take(), None, "all spoken for");
    let lent = held[held.len() / 2];
    release(lent);
    assert_eq!(take(), Some(lent), "the one let go is the first free again");
    for index in held {
        release(index);
    }
}

#[test]
fn a_span_is_checked_before_any_backend_sees_it() {
    // 🚨Two refusals, two sentences: 「the range is wrong」 is not 「no
    // decoder」 — the distinction the viewer once got wrong in Dart.
    let _turn = one_at_a_time();
    let path = c"movie.anicel";
    // SAFETY (each): a NUL-terminated path.
    assert_eq!(unsafe { qa_video_decode_open_span(path.as_ptr(), -1, 10, 0) }, 0);
    assert_eq!(last_error(), "that span is not inside the file", "a negative offset");
    assert_eq!(unsafe { qa_video_decode_open_span(path.as_ptr(), 0, 0, 0) }, 0);
    assert_eq!(last_error(), "that span is not inside the file", "a zero length");
    // A well-formed span reaches the backend, framed or not, and is refused
    // for the backend's own reason — there is no such file.
    for framed in [0, 1] {
        assert_eq!(unsafe { qa_video_decode_open_span(path.as_ptr(), 4096, 10, framed) }, 0);
        let why = last_error();
        assert!(!why.is_empty() && why != "that span is not inside the file", "framed {framed}: {why}");
    }
    assert_eq!(unsafe { qa_video_decode_open(std::ptr::null()) }, 0);
    assert_eq!(last_error(), "no path");
    assert_eq!(unsafe { qa_video_decode_open(c"".as_ptr()) }, 0);
    assert_eq!(last_error(), "no path", "an empty one is none");
}

#[test]
fn a_handle_that_names_nothing_is_refused() {
    let _turn = one_at_a_time();
    for handle in [0, -1, DOCS as i32 + 1, i32::MAX] {
        // SAFETY (each): null out-parameters and buffer, which are refused.
        assert_eq!(unsafe { qa_video_decode_info(handle, null(), null(), null(), null(), null()) }, 0);
        assert_eq!(last_error(), "no document is open", "info on {handle}");
        assert_eq!(unsafe { qa_video_decode_frame(handle, 0, null(), 0) }, 0);
        assert_eq!(last_error(), "no document is open", "a frame of {handle}");
        qa_video_decode_close(handle);
    }
}

fn null<T>() -> *mut T {
    std::ptr::null_mut()
}
