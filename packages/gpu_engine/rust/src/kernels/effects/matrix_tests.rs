//! The colour matrix on a real GPU, checked against sums worked out by hand
//! from matrix.wgsl's head and against the ledger — never against a CPU
//! copy of the formula (`kernels/mod.rs` has why). The matrices are the
//! app's to make; these are made to put one question each, their
//! multipliers and translations exact in Q.16 so a hand sum is the sum.

use std::sync::OnceLock;

use super::tests::{rgba, run_cases};
use super::{MATRIX_WGSL, MATRIX_WORDS, matrix_words};
use crate::kernels::composite::tests::mix;
use crate::kernels::shared::pipeline;
use crate::testing::{assert_pinned, first_engine};

pub(crate) type Matrix = [f64; MATRIX_WORDS];

/// The matrix's cases, compiled once for the whole test process.
fn compiled() -> &'static wgpu::ComputePipeline {
    static PIPELINE: OnceLock<wgpu::ComputePipeline> = OnceLock::new();
    PIPELINE.get_or_init(|| {
        let sources = [MATRIX_WGSL, include_str!("matrix_cases.wgsl")];
        pipeline(first_engine(), &sources, "run_matrices")
    })
}

/// Each pixel through its matrix of `matrices` on the GPU — `(matrix,
/// texel)` a case — and the words that came out.
fn through(matrices: &[Matrix], cases: &[(usize, u32)]) -> Vec<u32> {
    let tables: Vec<u32> = matrices
        .iter()
        .flat_map(|matrix| matrix_words(matrix).expect("a matrix in range"))
        .collect();
    let words: Vec<u32> = cases
        .iter()
        .flat_map(|&(matrix, texel)| [(matrix * MATRIX_WORDS) as u32, texel])
        .collect();
    run_cases(compiled(), &tables, &words, cases.len())
}

/// Every pixel of `pixels` through `matrix`.
pub(crate) fn each(matrix: Matrix, pixels: &[u32]) -> Vec<u32> {
    let cases: Vec<_> = pixels.iter().map(|&texel| (0, texel)).collect();
    through(&[matrix], &cases)
}

/// Colour rows that scale their own channel by `scale` and add `offset`,
/// the alpha row the identity — Brightness & Contrast's shape.
pub(crate) fn graded(scale: f64, offset: f64) -> Matrix {
    let mut matrix = [0.0; MATRIX_WORDS];
    for row in 0..3 {
        matrix[row * 6] = scale;
        matrix[row * 5 + 4] = offset;
    }
    matrix[18] = 1.0;
    matrix
}

/// `matrix` with row `row` given as `values`.
fn with_row(mut matrix: Matrix, row: usize, values: [f64; 5]) -> Matrix {
    matrix[row * 5..row * 5 + 5].copy_from_slice(&values);
    matrix
}

fn identity() -> Matrix {
    graded(1.0, 0.0)
}

#[test]
fn the_identity_gives_every_pixel_back() {
    let pixels: Vec<u32> = (0..256)
        .map(|v| rgba(v, 255 - v, (v * 7) % 256, (v * 13 + 5) % 256))
        .collect();
    assert_eq!(each(identity(), &pixels), pixels);
}

/// 1.5·c − 63.75, and a half goes up on either side of zero.
#[test]
fn a_scale_and_a_translation_round_their_sum_half_up() {
    let contrast = each(graded(1.5, -63.75), &[rgba(100, 200, 42, 77), rgba(43, 255, 0, 0)]);
    assert_eq!(contrast, [rgba(86, 236, 0, 77), rgba(1, 255, 0, 0)]);
    let pixels = [rgba(0, 1, 254, 255), rgba(255, 0, 0, 9)];
    assert_eq!(each(graded(1.0, 0.5), &pixels), [rgba(1, 2, 255, 255), rgba(255, 1, 1, 9)]);
    assert_eq!(each(graded(1.0, -0.5), &pixels), pixels);
}

/// Red takes green, green blue, blue alpha and alpha red, each with its
/// own row's translation.
#[test]
fn each_channel_reads_its_own_row() {
    let mut turned = [0.0; MATRIX_WORDS];
    for (row, column) in [(0, 1), (1, 2), (2, 3), (3, 0)] {
        turned[row * 5 + column] = 1.0;
        turned[row * 5 + 4] = (row + 1) as f64;
    }
    assert_eq!(each(turned, &[rgba(10, 20, 30, 40)]), [rgba(21, 32, 43, 14)]);
}

/// 0.5·r − 0.25·g + 0.125·b + 0.0625·a − 3.5: a negative multiplier and a
/// negative translation take their low halves from below their whole.
#[test]
fn a_row_weighs_each_byte_by_its_own_multiplier() {
    let weighed = with_row(identity(), 0, [0.5, -0.25, 0.125, 0.0625, -3.5]);
    let pixels = [rgba(100, 40, 16, 32), rgba(255, 0, 255, 255)];
    assert_eq!(each(weighed, &pixels), [rgba(41, 40, 16, 32), rgba(172, 0, 255, 255)]);
}

/// −0.25·r + 100 for r of 2, 3, 6, 201 and 255: 99.5, 99.25, 98.5, 49.75
/// and 36.25.
#[test]
fn a_fraction_below_zero_rounds_as_its_sum_does() {
    let lowered = with_row(identity(), 0, [-0.25, 0.0, 0.0, 0.0, 100.0]);
    let reds = [2, 3, 6, 201, 255];
    let pixels: Vec<u32> = reds.iter().map(|&red| rgba(red, 7, 8, 9)).collect();
    let wanted: Vec<u32> = [100, 99, 99, 50, 36].iter().map(|&red| rgba(red, 7, 8, 9)).collect();
    assert_eq!(each(lowered, &pixels), wanted);
}

/// An onion skin's tint: the tint's colour, half the pixel's alpha. A
/// pixel left no alpha keeps the colour its rows give, as a key leaves one
/// (key.wgsl) — what lays it premultiplies.
#[test]
fn a_tint_takes_its_colour_and_scales_the_alpha() {
    let mut tint = [0.0; MATRIX_WORDS];
    tint[4] = 12.0;
    tint[9] = 34.0;
    tint[14] = 56.0;
    tint[18] = 0.5;
    let pixels = [rgba(9, 99, 199, 201), rgba(1, 1, 1, 1), rgba(200, 0, 0, 0)];
    let wanted = [rgba(12, 34, 56, 101), rgba(12, 34, 56, 1), rgba(12, 34, 56, 0)];
    assert_eq!(each(tint, &pixels), wanted);
}

#[test]
fn every_channel_clamps_to_a_byte_both_ways() {
    let steep = with_row(graded(4.0, -300.0), 3, [0.0, 0.0, 0.0, 4.0, -300.0]);
    assert_eq!(each(steep, &[rgba(0, 75, 76, 200)]), [rgba(0, 0, 4, 255)]);
}

/// Multipliers at the range's end sum exactly: 32767·2 is past a byte,
/// −32767·2 + 255 below nothing, and 32767.75 against −32767.75 cancels to
/// what the third column adds.
#[test]
fn the_largest_multipliers_sum_without_wrapping() {
    let mut wide = identity();
    wide = with_row(wide, 0, [32767.0, 0.0, 0.0, 0.0, 0.0]);
    wide = with_row(wide, 1, [0.0, -32767.0, 0.0, 0.0, 255.0]);
    wide = with_row(wide, 2, [32767.75, -32767.75, 1.0, 0.0, 0.0]);
    assert_eq!(each(wide, &[rgba(2, 2, 7, 9)]), [rgba(255, 0, 7, 9)]);
}

#[test]
fn each_case_reads_its_own_matrix() {
    let matrices = [graded(1.0, 10.0), graded(1.0, -10.0)];
    let pixel = rgba(50, 60, 70, 80);
    assert_eq!(
        through(&matrices, &[(0, pixel), (1, pixel)]),
        [rgba(60, 70, 80, 80), rgba(40, 50, 60, 80)]
    );
}

/// A matrix's words are its values in Q.16 as an i32's bits, below 2^15 in
/// magnitude and numbers.
#[test]
fn a_matrix_is_its_words_in_range_and_nothing_past_it() {
    let words = matrix_words(&with_row(identity(), 0, [1.0, -0.5, 0.0, 0.0, -32767.0]))
        .expect("in range");
    assert_eq!(&words[..6], [65536, 0xffff_8000, 0, 0, 0x8001_0000, 0]);
    for past in [32768.0, -32768.0, f64::NAN, f64::INFINITY] {
        assert!(matrix_words(&with_row(identity(), 3, [0.0, 0.0, 0.0, 1.0, past])).is_none());
    }
}

/// Four matrices with no exact sums — a turn of the colours, a contrast, a
/// tint and one that mixes every channel into every other — over a hashed
/// 64 × 64 picture: the ledger's.
#[test]
fn every_device_runs_the_pinned_matrices() {
    let turned = [
        0.7713, 0.5521, -0.3234, 0.0, 0.0, //
        -0.1782, 1.1004, 0.0778, 0.0, 0.0, //
        0.2161, -0.6539, 1.4378, 0.0, 0.0, //
        0.0, 0.0, 0.0, 1.0, 0.0,
    ];
    let mut tint = [0.0; MATRIX_WORDS];
    tint[4] = 231.0;
    tint[9] = 17.0;
    tint[14] = 88.0;
    tint[18] = 160.0 / 255.0;
    let mixed = [
        0.3, 0.3, 0.3, 0.1, 12.7, //
        0.2, 0.5, -0.1, 0.4, -7.3, //
        -0.4, 0.2, 0.9, 0.3, 3.3, //
        0.1, -0.2, 0.3, 0.8, 5.5,
    ];
    let matrices = [turned, graded(1.37, -41.2), tint, mixed];
    let cases: Vec<(usize, u32)> = (0..matrices.len())
        .flat_map(|matrix| (0..64 * 64).map(move |at| (matrix, mix(at ^ 0x2545_f491))))
        .collect();
    let words = through(&matrices, &cases);
    let tinted = &words[2 * 64 * 64..3 * 64 * 64];
    assert!(tinted.iter().all(|word| word & 0xff_ffff == rgba(231, 17, 88, 0)));
    let bytes: Vec<u8> = words.iter().flat_map(|word| word.to_le_bytes()).collect();
    assert_pinned("effects/colour-matrix", &bytes);
}
