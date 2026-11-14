//! The encoder asked through its exports, so the handing out and giving
//! back are held too — each test's pictures held to the ledger in a row,
//! the bytes the C engine's `qa_image_encode_jpg` wrote. ↩️Until the
//! connection round (connection-round-checklist H, 2026-11-08) they were
//! held to the C itself (native/oracle), byte for byte; the C was pinned
//! before it went (connection-round-checklist A, 관제 2026-11-07).

use std::ptr::null_mut;

use ledger::Running;

use super::{qa_image_encode_free, qa_image_encode_jpg};

/// What the encoder answers for the picture, its bytes copied out and the
/// buffer given back; None when it refuses.
fn ask(rgb: *const u8, width: i32, height: i32, quality: i32) -> Option<Vec<u8>> {
    let mut data = null_mut();
    let mut size = -1;
    // SAFETY: `rgb` is null or holds the picture; the outs are locals.
    let ok = unsafe { qa_image_encode_jpg(rgb, width, height, quality, &mut data, &mut size) };
    if ok == 0 {
        assert!(data.is_null() || size == 0, "a refusal hands nothing out");
        return None;
    }
    // SAFETY: what the encoder handed out, given back once.
    let bytes = unsafe { std::slice::from_raw_parts(data, size as usize) }.to_vec();
    unsafe { qa_image_encode_free(data) };
    Some(bytes)
}

/// A well-mixed u32 (lowbias32), for pictures no formula here predicts.
fn mix(mut h: u32) -> u32 {
    h ^= h >> 16;
    h = h.wrapping_mul(0x7feb_352d);
    h ^= h >> 15;
    h = h.wrapping_mul(0x846c_a68b);
    h ^ (h >> 16)
}

/// Noise: every byte its own.
fn noise(width: usize, height: usize) -> Vec<u8> {
    (0..width * height * 3).map(|i| mix(i as u32) as u8).collect()
}

/// A smooth picture with a little noise: long zero runs between few
/// coefficients, the codes noise never reaches.
fn gradient(width: usize, height: usize) -> Vec<u8> {
    let mut rgb = Vec::with_capacity(width * height * 3);
    for y in 0..height {
        for x in 0..width {
            let grain = (mix((y * width + x) as u32) % 5) as usize;
            rgb.push(((x * 255) / width.max(2) + grain).min(255) as u8);
            rgb.push(((y * 255) / height.max(2)) as u8);
            rgb.push((((x + y) * 127) / (width + height)) as u8);
        }
    }
    rgb
}

/// One colour, so most blocks are their DC alone.
fn flat(width: usize, height: usize) -> Vec<u8> {
    [200, 30, 90].repeat(width * height)
}

/// The JPEG of the picture. Each JPEG ends at its EOI, which no stuffed
/// byte inside repeats, so the pictures added to a row one after another
/// are told apart without their lengths.
fn jpeg(rgb: &[u8], width: usize, height: usize, quality: i32) -> Vec<u8> {
    ask(rgb.as_ptr(), width as i32, height as i32, quality).expect("it encodes")
}

// Sides on, off and across the 8 and 16 pixel blocks — the edge repeated
// past them —, each quality the chroma's two ways meet at (90 subsampled,
// 91 not), the table's halves (49, 50) and its ends, on three pictures.
#[test]
fn every_byte_is_the_c_s() {
    let mut pins = Running::new();
    let sides = [(1, 1), (7, 5), (8, 8), (16, 16), (17, 9), (33, 47), (64, 48)];
    for (width, height) in sides {
        for picture in [noise(width, height), gradient(width, height), flat(width, height)] {
            for quality in [1, 10, 49, 50, 75, 90, 91, 100] {
                pins.add(&jpeg(&picture, width, height, quality));
            }
        }
    }
    pins.assert_pinned("image_encode/jpg-every-side");
}

// Past 1..=100 it clamps, to the same bytes as the end it clamps to — as
// the C did — and those are the ends: a step inside either is other bytes.
#[test]
fn a_quality_past_its_ends_clamps_as_the_c_does() {
    let picture = gradient(20, 12);
    for (quality, end) in [(i32::MIN, 1), (-5, 1), (0, 1), (101, 100), (1000, 100), (i32::MAX, 100)] {
        assert!(jpeg(&picture, 20, 12, quality) == jpeg(&picture, 20, 12, end), "{quality}: the bytes of {end}");
    }
    for (end, inside) in [(1, 2), (100, 99)] {
        assert!(jpeg(&picture, 20, 12, end) != jpeg(&picture, 20, 12, inside), "{end} against {inside}");
    }
}

// A whole frame: thousands of blocks, the byte stuffing after 0xFF.
#[test]
fn a_full_hd_frame_is_the_c_s() {
    let mut pins = Running::new();
    let mut picture = gradient(1920, 1080);
    picture.iter_mut().zip(noise(1920, 1080)).step_by(7).for_each(|(byte, n)| *byte ^= n);
    for quality in [90, 95] {
        pins.add(&jpeg(&picture, 1920, 1080, quality));
    }
    pins.assert_pinned("image_encode/jpg-full-hd");
}

// What the C refused: no picture, and a side of none or less.
#[test]
fn what_the_c_refuses_is_refused() {
    let picture = flat(4, 4);
    for (rgb, width, height) in [
        (std::ptr::null(), 4, 4),
        (picture.as_ptr(), 0, 4),
        (picture.as_ptr(), 4, 0),
        (picture.as_ptr(), -1, 4),
    ] {
        assert_eq!(ask(rgb, width, height, 90), None);
    }
}

#[test]
fn giving_back_nothing_is_nothing() {
    // SAFETY: null is nothing to give back.
    unsafe { qa_image_encode_free(null_mut()) };
}
