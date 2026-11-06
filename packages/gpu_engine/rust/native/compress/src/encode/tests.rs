//! The Rust compressor against the engine's C (native/oracle): every frame
//! held to the bytes `qa_zstd_compress(…, 9)` writes, and decoded back by
//! the Rust decoder.

use oracle::export;

use super::compress;
use crate::tests::{Noise, compressed, kinds};

type Compress = unsafe extern "C" fn(*mut u8, i64, *const u8, i64, i32) -> i64;
type Bound = extern "C" fn(i64) -> i64;

/// The C's answer for `data` into `capacity` bytes: its frame, or None
/// where it answers 0.
fn c_compress(data: &[u8], capacity: usize) -> Option<Vec<u8>> {
    // SAFETY: qa_compress.c — `int64_t qa_zstd_compress(uint8_t*, int64_t, const uint8_t*, int64_t, int32_t)`.
    let compress = unsafe { export::<Compress>("qa_zstd_compress") };
    let mut frame = vec![0u8; capacity.max(1)];
    // SAFETY: both buffers hold the sizes passed.
    let written = unsafe { compress(frame.as_mut_ptr(), capacity as i64, data.as_ptr(), data.len() as i64, 9) };
    (written > 0).then(|| {
        frame.truncate(written as usize);
        frame
    })
}

/// The Rust's answer for `data` into `capacity` bytes.
fn ours(data: &[u8], capacity: usize) -> Option<Vec<u8>> {
    let mut frame = vec![0u8; capacity];
    compress(&mut frame, data).map(|written| {
        frame.truncate(written);
        frame
    })
}

fn bound(size: usize) -> usize {
    // SAFETY: qa_compress.c — `int64_t qa_zstd_compress_bound(int64_t)`.
    let bound = unsafe { export::<Bound>("qa_zstd_compress_bound") };
    bound(size as i64) as usize
}

/// The Rust's frame of `data` is the C's, and decodes to `data`.
fn same_frame(data: &[u8], what: &str) {
    let theirs = compressed(data, 9);
    let mine = ours(data, bound(data.len())).unwrap_or_else(|| panic!("{what}: the Rust compresses it"));
    let first = mine.iter().zip(&theirs).position(|(a, b)| a != b);
    assert!(
        first.is_none() && mine.len() == theirs.len(),
        "{what}: {} bytes where the C writes {}, first apart at {first:?}",
        mine.len(),
        theirs.len(),
    );
    let mut back = vec![0u8; data.len()];
    assert_eq!(crate::frame::decompress(&mut back, &mine), Ok(data.len()), "{what}: decoded whole");
    assert!(back == data, "{what}: the input back");
}

// Sizes at each turn of level 9: the window shrunk to small inputs, the
// tree up to 16 KiB and the rows past it, the parameter rows at 128 KiB
// and 256 KiB, the content size's forms, stored blocks under 7 bytes, and
// blocks of 128 KiB in a row behind a window of 4 MiB.
const SIZES: [usize; 30] = [
    1, 2, 6, 7, 8, 63, 64, 65, 100, 255, 256, 1000, 1024, 1025, 4095, 16383, 16384, 16385, 65535, 65791, 65792,
    131_071, 131_072, 131_073, 131_075, 131_078, 262_144, 262_145, 300_000, 1_000_000,
];

#[test]
fn every_input_compresses_to_the_c_s_frame() {
    for &size in &SIZES {
        for (kind, data) in kinds(size, size as u64) {
            same_frame(&data, &format!("{kind} × {size}"));
        }
    }
}

// Inputs cut from every kind at random lengths, and runs of one byte after
// coded blocks — the later blocks sent as the byte repeated, the first
// never.
#[test]
fn mixed_inputs_compress_to_the_c_s_frame() {
    let mut noise = Noise(0x9E37_79B9_7F4A_7C15);
    for round in 0..40 {
        let size = noise.below(400_000) + 1;
        let pieces = kinds(size, noise.next());
        let mut data = Vec::with_capacity(size);
        while data.len() < size {
            let (_, source) = &pieces[noise.below(pieces.len())];
            let take = (noise.below(70_000) + 1).min(size - data.len());
            let start = noise.below(size - take + 1);
            data.extend_from_slice(&source[start..start + take]);
        }
        same_frame(&data, &format!("round {round}, {size} bytes"));
    }
    for &(head, tail) in &[(131_072, 131_072), (131_072, 5), (131_072, 30), (16_384, 1), (200_000, 300_000)] {
        let mut data = kinds(head, head as u64).swap_remove(2).1;
        data.extend(std::iter::repeat_n(7u8, tail));
        same_frame(&data, &format!("text × {head}, then 7 × {tail}"));
    }
}

// Too small a destination: the Rust refuses where the C answers 0, and
// writes what the C writes where it does not — a block stored, say, that
// the room did not take coded.
#[test]
fn a_short_destination_is_answered_as_the_c_answers_it() {
    for &size in &[1, 7, 100, 5000, 16_385, 140_000] {
        for (kind, data) in kinds(size, size as u64 + 1) {
            let whole = compressed(&data, 9).len();
            let mut capacities: Vec<usize> = (0..24).collect();
            capacities.extend([whole / 2, whole - 4, whole - 3, whole - 1, whole, whole + 1]);
            capacities.extend((0..8).map(|k| whole * (k + 1) / 9));
            for capacity in capacities {
                let what = format!("{kind} × {size} into {capacity}");
                assert!(ours(&data, capacity) == c_compress(&data, capacity), "{what}: the Rust's answer is the C's");
            }
        }
    }
}

#[test]
fn nothing_to_compress_is_refused() {
    assert_eq!(compress(&mut [0u8; 64], &[]), None);
    assert_eq!(compress(&mut [], b"cel"), None);
}
