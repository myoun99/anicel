//! The Rust encoder against the engine's C (native/oracle), byte for byte:
//! both are asked through their exports, so the handing out and giving
//! back are held too.

use std::ptr::null_mut;

use super::{qa_image_encode_free, qa_image_encode_jpg};

type Encode = unsafe extern "C" fn(*const u8, i32, i32, i32, *mut *mut u8, *mut i32) -> i32;
type Free = unsafe extern "C" fn(*mut u8);

/// What `encode` answers for the picture, its bytes copied out and the
/// buffer given back with `free`; None when it refuses.
fn ask(encode: Encode, free: Free, rgb: *const u8, width: i32, height: i32, quality: i32) -> Option<Vec<u8>> {
    let mut data = null_mut();
    let mut size = -1;
    // SAFETY: `rgb` is null or holds the picture; the outs are locals.
    let ok = unsafe { encode(rgb, width, height, quality, &mut data, &mut size) };
    if ok == 0 {
        assert!(data.is_null() || size == 0, "a refusal hands nothing out");
        return None;
    }
    // SAFETY: what the encoder handed out, given back once.
    let bytes = unsafe { std::slice::from_raw_parts(data, size as usize) }.to_vec();
    unsafe { free(data) };
    Some(bytes)
}

fn c(rgb: *const u8, width: i32, height: i32, quality: i32) -> Option<Vec<u8>> {
    // SAFETY: qa_image_encode.c's declarations.
    let (encode, free) = unsafe {
        (
            oracle::export::<Encode>("qa_image_encode_jpg"),
            oracle::export::<Free>("qa_image_encode_free"),
        )
    };
    ask(encode, free, rgb, width, height, quality)
}

fn rust(rgb: *const u8, width: i32, height: i32, quality: i32) -> Option<Vec<u8>> {
    ask(qa_image_encode_jpg, qa_image_encode_free, rgb, width, height, quality)
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

fn same(rgb: &[u8], width: usize, height: usize, quality: i32) {
    let (w, h) = (width as i32, height as i32);
    let ours = rust(rgb.as_ptr(), w, h, quality).expect("the Rust encodes");
    let theirs = c(rgb.as_ptr(), w, h, quality).expect("the C encodes");
    assert!(ours == theirs, "{width}x{height} at {quality}: {} bytes against the C's {}", ours.len(), theirs.len());
}

// Sides on, off and across the 8 and 16 pixel blocks — the edge repeated
// past them —, each quality the chroma's two ways meet at (90 subsampled,
// 91 not), the table's halves (49, 50) and its ends, on three pictures.
#[test]
fn every_byte_is_the_c_s() {
    let sides = [(1, 1), (7, 5), (8, 8), (16, 16), (17, 9), (33, 47), (64, 48)];
    for (width, height) in sides {
        for picture in [noise(width, height), gradient(width, height), flat(width, height)] {
            for quality in [1, 10, 49, 50, 75, 90, 91, 100] {
                same(&picture, width, height, quality);
            }
        }
    }
}

// Past 1..=100 both clamp, to the same bytes as the end they clamp to.
#[test]
fn a_quality_past_its_ends_clamps_as_the_c_does() {
    let picture = gradient(20, 12);
    for quality in [i32::MIN, -5, 0, 101, 1000, i32::MAX] {
        same(&picture, 20, 12, quality);
    }
}

// A whole frame: thousands of blocks, the byte stuffing after 0xFF.
#[test]
fn a_full_hd_frame_is_the_c_s() {
    let mut picture = gradient(1920, 1080);
    picture.iter_mut().zip(noise(1920, 1080)).step_by(7).for_each(|(byte, n)| *byte ^= n);
    for quality in [90, 95] {
        same(&picture, 1920, 1080, quality);
    }
}

#[test]
fn what_the_c_refuses_is_refused() {
    let picture = flat(4, 4);
    for (rgb, width, height) in [
        (std::ptr::null(), 4, 4),
        (picture.as_ptr(), 0, 4),
        (picture.as_ptr(), 4, 0),
        (picture.as_ptr(), -1, 4),
    ] {
        assert_eq!(rust(rgb, width, height, 90), None);
        assert_eq!(c(rgb, width, height, 90), None);
    }
}

#[test]
fn giving_back_nothing_is_nothing() {
    // SAFETY: null is nothing to give back.
    unsafe { qa_image_encode_free(null_mut()) };
}
