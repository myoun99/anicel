//! The premultiplied copy, through its export. ↩️Held from Dart while it was
//! the C's (test/services/qa_native_engine_parity_test.dart, which skipped
//! wherever no C engine was built); here every host runs it, and so each
//! build's four-pixel step is held where that build runs.

use super::qa_premultiply_rgba_copy;

/// `value * alpha / 255` to the nearest whole, by division: what the
/// formula's shifts must come to. No product of two bytes stands halfway
/// between two 255ths, so nearest is one answer.
fn nearest(value: u8, alpha: u8) -> u8 {
    ((2 * u32::from(value) * u32::from(alpha) + 255) / 510) as u8
}

/// What every pixel of `straight` must come to.
fn to_the_nearest(straight: &[u8]) -> Vec<u8> {
    straight
        .chunks_exact(4)
        .flat_map(|pixel| {
            let scaled = |colour: usize| nearest(pixel[colour], pixel[3]);
            [scaled(0), scaled(1), scaled(2), pixel[3]]
        })
        .collect()
}

fn copied(straight: &[u8]) -> Vec<u8> {
    // Not the bytes a pixel could be premultiplied to: one left unwritten
    // shows.
    let mut out = vec![0xA5; straight.len()];
    let count = (straight.len() / 4) as i32;
    // SAFETY: both hold the pixels counted.
    unsafe { qa_premultiply_rgba_copy(out.as_mut_ptr(), straight.as_ptr(), count) };
    out
}

/// Every colour at every alpha, once over: pixel `i` holds colour
/// `i & 0xFF` in red, its inverse in green and its half in blue, at alpha
/// `i >> 8`.
fn every_pair() -> Vec<u8> {
    (0..=u16::MAX)
        .flat_map(|i| {
            let colour = (i & 0xFF) as u8;
            [colour, 255 - colour, colour >> 1, (i >> 8) as u8]
        })
        .collect()
}

/// A run of `pixels` of them where the alpha is neither end and the
/// colours change from one to the next — pixels a wrong step shows on.
fn a_run_of(pixels: usize) -> Vec<u8> {
    let from = (200 * 256 + 77) * 4;
    every_pair()[from..from + pixels * 4].to_vec()
}

#[test]
fn every_colour_at_every_alpha_is_scaled_to_the_nearest_255th() {
    let straight = every_pair();
    let want = to_the_nearest(&straight);

    // 65,536 pixels are whole steps of four where the build takes four.
    assert_eq!(copied(&straight), want, "the block whole");

    // And each asked alone, as the pixels past the last four are taken.
    let mut alone = vec![0xA5_u8; straight.len()];
    for at in (0..straight.len()).step_by(4) {
        // SAFETY: one pixel at `at` is inside both.
        unsafe { qa_premultiply_rgba_copy(alone[at..].as_mut_ptr(), straight[at..].as_ptr(), 1) };
    }
    assert_eq!(alone, want, "each pixel alone");
}

#[test]
fn a_clear_pixel_loses_its_colour_and_an_opaque_one_keeps_it() {
    let straight = [200, 100, 50, 0, 200, 100, 50, 255, 255, 255, 255, 128, 1, 2, 3, 1, 9, 8, 7, 0];
    assert_eq!(
        copied(&straight),
        [0, 0, 0, 0, 200, 100, 50, 255, 128, 128, 128, 128, 0, 0, 0, 1, 0, 0, 0, 0],
    );
}

#[test]
fn every_count_writes_its_own_pixels_and_no_other() {
    let straight = a_run_of(10);
    let want = to_the_nearest(&straight);
    for count in 0..=9_usize {
        let mut out = vec![0xA5_u8; 10 * 4];
        // SAFETY: both hold ten pixels, and no more than nine are counted.
        unsafe { qa_premultiply_rgba_copy(out.as_mut_ptr(), straight.as_ptr(), count as i32) };
        assert_eq!(out[..count * 4], want[..count * 4], "{count} pixel(s)");
        assert!(out[count * 4..].iter().all(|&byte| byte == 0xA5), "past {count} pixel(s)");
    }
}

#[test]
fn a_count_below_none_writes_nothing() {
    let straight = a_run_of(4);
    let mut out = vec![0xA5_u8; straight.len()];
    // SAFETY: nothing is to be read or written.
    unsafe { qa_premultiply_rgba_copy(out.as_mut_ptr(), straight.as_ptr(), -4) };
    assert!(out.iter().all(|&byte| byte == 0xA5));
}

#[test]
fn a_block_premultiplied_onto_itself_is_its_copy() {
    for pixels in [16, 15] {
        let straight = a_run_of(pixels);
        let mut block = straight.clone();
        let count = (block.len() / 4) as i32;
        // SAFETY: the one block holds the pixels counted, read and written.
        unsafe { qa_premultiply_rgba_copy(block.as_mut_ptr(), block.as_ptr(), count) };
        assert_eq!(block, to_the_nearest(&straight), "{pixels} pixels");
    }
}
