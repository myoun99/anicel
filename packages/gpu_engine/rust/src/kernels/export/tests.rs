//! The export's conversions on a real GPU, checked against the ledger and
//! against what the law gives by hand — never against a CPU copy of it
//! (`kernels/mod.rs` has why).

use std::sync::OnceLock;

use super::shown_tests::shown;
use super::{Clear, Lay, Nv12, Nv12Shape, Opaque, OverGround, Picture, PngFilter, Shown, Straight};
use crate::device::Engine;
use crate::testing::{assert_pinned, first_engine, last_error, read_buffer};

pub(super) struct Rig {
    pub(super) engine: &'static Engine,
    pub(super) nv12: Nv12,
    pub(super) over_ground: OverGround,
    pub(super) opaque: Opaque,
    pub(super) clear: Clear,
    pub(super) png: PngFilter,
    pub(super) straight: Straight,
    pub(super) lay: Lay,
}

/// One device and one compiled pass each for every test here, as the app
/// opens one device (blend's tests have why).
pub(super) fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        Rig {
            engine,
            nv12: Nv12::new(),
            over_ground: OverGround::new(),
            opaque: Opaque::new(),
            clear: Clear::new(),
            png: PngFilter::new(),
            straight: Straight::new(),
            lay: Lay::new(),
        }
    })
}

// ---- Frames ----

const RED: u32 = 0xff00_00ff;
const BLUE: u32 = 0xffff_0000;
const BLACK: u32 = 0xff00_0000;
const WHITE: u32 = 0xffff_ffff;

/// A well-mixed u32 (lowbias32), for pictures no formula here can predict.
fn mix(mut h: u32) -> u32 {
    h ^= h >> 16;
    h = h.wrapping_mul(0x7feb_352d);
    h ^= h >> 15;
    h = h.wrapping_mul(0x846c_a68b);
    h ^ (h >> 16)
}

/// A `width` x `height` frame shown, laid RGBA, holding `pixel` — a
/// premultiplied word, red the low byte ([`shown`]).
pub(super) fn frame(width: u32, height: u32, pixel: impl Fn(u32, u32) -> u32) -> Shown {
    shown(width, height, false, pixel)
}

/// The picture in its smallest encoder frame: even sides, rows of whole
/// words.
fn shape(src_width: u32, src_height: u32) -> Nv12Shape {
    let (width, height) = (src_width.next_multiple_of(2), src_height.next_multiple_of(2));
    Nv12Shape {
        src_width,
        src_height,
        width,
        height,
        y_stride: width.next_multiple_of(4),
    }
}

fn nv12(frame: &Shown, shape: Nv12Shape) -> Vec<u8> {
    let Rig { engine, nv12, .. } = rig();
    let out = nv12.run(engine, frame, shape).expect("nv12");
    read_buffer(engine, &out)
}

/// The Y byte at (x, y) and the Cb, Cr bytes of the 2 x 2 block it is in.
fn sample(bytes: &[u8], shape: Nv12Shape, x: u32, y: u32) -> (u8, u8, u8) {
    let stride = shape.y_stride as usize;
    let chroma = shape.height as usize * stride + (y / 2) as usize * stride + (x / 2 * 2) as usize;
    (bytes[y as usize * stride + x as usize], bytes[chroma], bytes[chroma + 1])
}

// ---- By hand, from the law (nv12.wgsl has its numbers) ----

// White: Y = ((220·255 + 128) >> 8) + 16 = (56228 >> 8) + 16 = 219 + 16;
// both differences are 0·255 + 128 >> 8 = 0, + 128.
#[test]
fn white_is_235_and_no_colour() {
    let shape = shape(6, 4);
    let bytes = nv12(&frame(6, 4, |_, _| WHITE), shape);
    assert!(bytes[..8 * 4].iter().all(|&luma| luma == 235), "every Y of 4 rows of 8");
    for (x, y) in [(0, 0), (5, 3), (2, 1)] {
        assert_eq!(sample(&bytes, shape, x, y), (235, 128, 128), "({x}, {y})");
    }
}

// Black: Y = (128 >> 8) + 16 = 16; Cb = Cr = (128 >> 8) + 128 = 128.
#[test]
fn black_is_16_and_no_colour() {
    let shape = shape(4, 2);
    let bytes = nv12(&frame(4, 2, |_, _| BLACK), shape);
    assert_eq!(sample(&bytes, shape, 3, 1), (16, 128, 128));
}

// Red: Y = ((66·255 + 128) >> 8) + 16 = (16958 >> 8) + 16 = 82;
// Cb = ((−38·255 + 128) >> 8) + 128 = (−9562 >> 8) + 128 = −38 + 128 = 90,
// the shift flooring −37.35 as the law's does; Cr = (28688 >> 8) + 128 = 240.
// Blue: Y = (6503 >> 8) + 16 = 41; Cb = 240; Cr = (−4462 >> 8) + 128 = 110.
#[test]
fn red_and_blue_floor_their_negative_differences_as_the_law_does() {
    let shape = shape(4, 2);
    let bytes = nv12(&frame(4, 2, |x, _| if x < 2 { RED } else { BLUE }), shape);
    assert_eq!(sample(&bytes, shape, 0, 0), (82, 90, 240));
    assert_eq!(sample(&bytes, shape, 2, 0), (41, 240, 110));
}

// The rest of the colours the law was checked by on the CPU till its copy
// there went (2026-11-15), each worked as above. Green: Y = (33023 >> 8) +
// 16 = 144; Cb = (−18742 >> 8) + 128 = 54; Cr = (−23842 >> 8) + 128 = 34.
// (200, 100, 50): Y = (27478 >> 8) + 16 = 123; Cb = (−9272 >> 8) + 128 =
// 91; Cr = (12228 >> 8) + 128 = 175. Grey 32: Y = (7168 >> 8) + 16 = 44, no
// colour. And a channel's least, its difference under one: red 8, Y =
// (656 >> 8) + 16 = 18, Cb = (−176 >> 8) + 128 = 127, Cr = (1024 >> 8) +
// 128 = 132; blue 8, Y = (328 >> 8) + 16 = 17, Cb = 132, Cr = (−16 >> 8) +
// 128 = 127.
#[test]
fn the_law_s_other_worked_colours_come_as_worked() {
    let worked: [(u32, (u8, u8, u8)); 5] = [
        (0xff00_ff00, (144, 54, 34)),
        (0xff32_64c8, (123, 91, 175)),
        (0xff20_2020, (44, 128, 128)),
        (0xff00_0008, (18, 127, 132)),
        (0xff08_0000, (17, 132, 127)),
    ];
    let shape = shape(10, 2);
    let bytes = nv12(&frame(10, 2, |x, _| worked[x as usize / 2].0), shape);
    for (block, (pixel, ycc)) in worked.iter().enumerate() {
        assert_eq!(sample(&bytes, shape, block as u32 * 2, 0), *ycc, "{pixel:#010x}");
    }
}

// A 2 x 2 block takes its chroma from its top-left pixel, not an average.
#[test]
fn a_blocks_colour_is_its_top_left_pixels() {
    let shape = shape(2, 2);
    let bytes = nv12(&frame(2, 2, |x, y| if (x, y) == (0, 0) { RED } else { BLUE }), shape);
    assert_eq!(sample(&bytes, shape, 1, 1), (41, 90, 240));
}

// The law reads no alpha: red at half, premultiplied — straight, red
// whole — is red's numbers.
#[test]
fn alpha_is_not_read() {
    let shape = shape(2, 2);
    let bytes = nv12(&frame(2, 2, |_, _| 0x8000_0080), shape);
    assert_eq!(sample(&bytes, shape, 0, 0), (82, 90, 240));
}

// A 3 x 3 picture of a 4 x 4 red frame, in an encoder's frame of 4 x 4
// with rows of 8: the fourth column and row are white, as are the four
// bytes of each row past the width — never what the frame holds there.
// The block at (2, 2) has its top-left in the picture, so it keeps red's
// colour.
#[test]
fn past_the_picture_is_white_whatever_the_frame_holds() {
    let shape = Nv12Shape {
        y_stride: 8,
        ..shape(3, 3)
    };
    let bytes = nv12(&frame(4, 4, |_, _| RED), shape);
    assert_eq!(bytes.len(), 8 * 4 * 3 / 2);
    for y in 0..4 {
        for x in 0..8 {
            let inside = x < 3 && y < 3;
            assert_eq!(bytes[y * 8 + x], if inside { 82 } else { 235 }, "Y ({x}, {y})");
        }
    }
    assert_eq!(sample(&bytes, shape, 2, 2), (82, 90, 240));
    assert_eq!(sample(&bytes, shape, 4, 0), (235, 128, 128), "the stride's block");
}

// ---- The ledger ----

/// A picture of any colours and alphas.
pub(super) fn mixed(seed: u32) -> impl Fn(u32, u32) -> u32 {
    move |x, y| mix(seed ^ mix(x ^ mix(y)))
}

/// [`mixed`] premultiplied, as a frame shown holds its pixels: each colour
/// at most its alpha.
pub(super) fn premultiplied(seed: u32) -> impl Fn(u32, u32) -> u32 {
    let pixel = mixed(seed);
    move |x, y| {
        let [red, green, blue, alpha] = pixel(x, y).to_le_bytes();
        u32::from_le_bytes([red.min(alpha), green.min(alpha), blue.min(alpha), alpha])
    }
}

// 197 x 131: odd sides padded to 198 x 132, rows of 200; 256 x 128: no
// padding.
#[test]
fn every_device_writes_the_pinned_nv12() {
    for (width, height, y_stride) in [(197, 131, 200), (256, 128, 256)] {
        let shape = Nv12Shape {
            y_stride,
            ..shape(width, height)
        };
        let id = format!("export/nv12-{width}x{height}-stride{y_stride}");
        assert_pinned(&id, &nv12(&frame(width, height, premultiplied(7)), shape));
    }
}

// ---- The shape ----

#[test]
fn a_frame_the_encoder_cannot_take_is_refused() {
    let frame = frame(4, 4, |_, _| WHITE);
    let Rig { engine, nv12, .. } = rig();
    for bad in [
        Nv12Shape { width: 5, ..shape(4, 4) },
        Nv12Shape { height: 2, ..shape(4, 4) },
        Nv12Shape { y_stride: 6, ..shape(4, 4) },
        Nv12Shape { width: 6, y_stride: 4, ..shape(4, 4) },
    ] {
        assert!(nv12.run(engine, &frame, bad).is_none(), "{bad:?}");
    }
}

// ==== Over the ground ====

/// The bytes the pass writes for a `width` x `height` picture over
/// `ground`: its RGB, then zeros to the last whole word.
fn over_ground(frame: &Shown, width: u32, height: u32, ground: [u8; 3]) -> Vec<u8> {
    cut_over_ground(frame, width, height, ground, None)
}

/// [`over_ground`] with the alpha `cut`.
fn cut_over_ground(
    frame: &Shown,
    width: u32,
    height: u32,
    ground: [u8; 3],
    cut: Option<u8>,
) -> Vec<u8> {
    let Rig {
        engine,
        over_ground,
        ..
    } = rig();
    let out = over_ground
        .run(engine, frame, Picture { width, height }, ground, cut)
        .expect("over ground");
    read_buffer(engine, &out)
}

/// The three bytes of the picture's pixel (x, y), `width` a row.
fn rgb_at(bytes: &[u8], width: u32, x: u32, y: u32) -> [u8; 3] {
    let at = (y * width + x) as usize * 3;
    [bytes[at], bytes[at + 1], bytes[at + 2]]
}

// ---- By hand, from the law (`_overGround`) ----

// Opaque: p = c and nothing of the ground.
#[test]
fn an_opaque_pixel_is_its_own_colour() {
    let bytes = over_ground(&frame(1, 1, |_, _| 0xff1e_c80a), 1, 1, [1, 2, 3]);
    assert_eq!(bytes, [10, 200, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
}

// Clear: nothing of it, and the ground whole — g·255 / 255 = g.
#[test]
fn a_clear_pixel_is_the_ground() {
    let bytes = over_ground(&frame(1, 1, |_, _| 0), 1, 1, [12, 34, 56]);
    assert_eq!(rgb_at(&bytes, 1, 0, 0), [12, 34, 56]);
}

// White at 128, premultiplied: p = 128. Over black that is all; over
// white, + 255·127 / 255 = 127. Red at 128 over white: 128 + 127 for red,
// 0 + 127 for green and blue.
#[test]
fn half_a_colour_takes_half_the_ground() {
    let halves = frame(2, 1, |x, _| if x == 0 { 0x8080_8080 } else { 0x8000_0080 });
    assert_eq!(rgb_at(&over_ground(&halves, 2, 1, [0, 0, 0]), 2, 0, 0), [128, 128, 128]);
    let white = over_ground(&halves, 2, 1, [255, 255, 255]);
    assert_eq!(rgb_at(&white, 2, 0, 0), [255, 255, 255]);
    assert_eq!(rgb_at(&white, 2, 1, 0), [255, 127, 127]);
}

// Over a ground of red 100, the ground's part floors:
// - black at 1: 100·254 / 255 = 99.6, so 99;
// - 1 at 2: 1 + 100·253 / 255 = 1 + 99.2, so 100.
#[test]
fn the_ground_floors() {
    let pixels = [0x0100_0000, 0x0201_0101];
    let bytes = over_ground(&frame(2, 1, |x, _| pixels[x as usize]), 2, 1, [100, 0, 0]);
    assert_eq!(bytes[..6], [99, 0, 0, 100, 1, 1]);
}

// ---- The bytes' order ----

// 3 x 2: six pixels in two runs of four — the first crossing from the top
// row into the next —, eighteen bytes in their order, then six zeros to
// the second run's last word.
#[test]
fn runs_of_four_pixels_fill_whole_words_across_rows() {
    let colour = |x: u32, y: u32| {
        let r = (y * 3 + x) * 10 + 1;
        0xff00_0000 | r | (r + 1) << 8 | (r + 2) << 16
    };
    let bytes = over_ground(&frame(3, 2, colour), 3, 2, [255, 255, 255]);
    let mut wanted = Vec::new();
    for index in 0..6u8 {
        let r = index * 10 + 1;
        wanted.extend([r, r + 1, r + 2]);
    }
    wanted.extend([0; 6]);
    assert_eq!(bytes, wanted);
}

// ---- The ledger ----

// 197 x 131: 25,807 pixels — a last run of three; 256 x 128: exact runs.
#[test]
fn every_device_writes_the_pinned_over_ground() {
    for (width, height) in [(197, 131), (256, 128)] {
        let picture = Picture { width, height };
        let bytes = over_ground(&frame(width, height, premultiplied(11)), width, height, [0x12, 0x80, 0xed]);
        let id = format!("export/over-ground-{width}x{height}");
        assert_pinned(&id, &bytes[..picture.rgb_bytes() as usize]);
    }
}

// ---- The shape ----

#[test]
fn an_empty_picture_or_a_short_frame_is_refused() {
    let frame = frame(4, 4, |_, _| WHITE);
    let Rig {
        engine,
        over_ground,
        ..
    } = rig();
    for bad in [
        Picture { width: 0, height: 4 },
        Picture { width: 4, height: 0 },
        Picture { width: 129, height: 4 },
    ] {
        assert!(over_ground.run(engine, &frame, bad, [0, 0, 0], None).is_none(), "{bad:?}");
    }
}

// ==== Opaque ====

/// The pass's answer for the `width` x `height` picture in `frame`.
fn opaque(frame: &Shown, width: u32, height: u32) -> u32 {
    let Rig { engine, opaque, .. } = rig();
    let out = opaque
        .run(engine, frame, Picture { width, height })
        .expect("opaque");
    let bytes = read_buffer(engine, &out);
    u32::from_le_bytes(bytes[..4].try_into().unwrap())
}

/// Mixed colours, every one opaque.
fn opaque_mixed(x: u32, y: u32) -> u32 {
    mixed(11)(x, y) | 0xff00_0000
}

// 197 x 131: two tiles each way, so four groups answer. Past the picture
// the frame's rows are clear — and not read.
#[test]
fn a_picture_whose_every_pixel_is_opaque_is_opaque() {
    assert_eq!(opaque(&frame(197, 131, opaque_mixed), 197, 131), 255);
}

// One pixel at 254 in each tile, and at each end of a tile's texels: the
// group that holds it and the invocation that reads it, each, tell.
#[test]
fn one_pixel_short_of_opaque_anywhere_is_not_opaque() {
    for at in [(0, 0), (127, 127), (128, 0), (5, 129), (196, 130)] {
        let picture = |x, y| {
            let pixel = opaque_mixed(x, y);
            if (x, y) == at { pixel & 0xfeff_ffff } else { pixel }
        };
        assert!(opaque(&frame(197, 131, picture), 197, 131) < 255, "{at:?}");
    }
}

#[test]
fn a_clear_pixel_is_not_opaque() {
    assert!(opaque(&frame(1, 1, |_, _| 0), 1, 1) < 255);
}

#[test]
fn an_empty_picture_or_a_short_frame_is_not_asked() {
    let frame = frame(4, 4, |_, _| WHITE);
    let Rig { engine, opaque, .. } = rig();
    for bad in [
        Picture { width: 0, height: 4 },
        Picture { width: 4, height: 0 },
        Picture { width: 129, height: 4 },
    ] {
        assert!(opaque.run(engine, &frame, bad).is_none(), "{bad:?}");
    }
}

// ==== A GIF ====

// Cut at 128, the app's half: red at 128 is laid whole — its own red and
// none of the white ground, where its shades would take 127 of it; at 127
// it is clear, so the ground, whose place the GIF's clear colour takes.
#[test]
fn a_gif_lays_a_half_covered_pixel_whole_and_one_under_half_clear() {
    let pixels = [0x8000_0080, 0x7f00_007f];
    let frame = frame(2, 1, |x, _| pixels[x as usize]);
    let bytes = cut_over_ground(&frame, 2, 1, [255, 255, 255], Some(128));
    assert_eq!(bytes[..6], [255, 0, 0, 255, 255, 255]);
}

// Cut at 0, no pixel is under it: a GIF that keeps no clear colour takes
// each pixel's own colour — a clear one's, black, too, not the ground's.
#[test]
fn cut_at_nothing_every_pixel_is_its_own_colour() {
    let pixels = [0, 0x8000_0080];
    let frame = frame(2, 1, |x, _| pixels[x as usize]);
    let bytes = cut_over_ground(&frame, 2, 1, [99, 99, 99], Some(0));
    assert_eq!(bytes[..6], [0, 0, 0, 255, 0, 0]);
}

/// The clear bits the pass writes for a `width` x `height` picture cut at
/// `cut`, a word of 32 pixels each.
fn clear_bits(frame: &Shown, width: u32, height: u32, cut: u8) -> Vec<u32> {
    let Rig { engine, clear, .. } = rig();
    let out = clear
        .run(engine, frame, Picture { width, height }, cut)
        .expect("clear");
    read_buffer(engine, &out)
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
        .collect()
}

// Under the cut is clear: 127 is under 128 and 128 is not; 0 is, 255 is
// not — pixels 0 and 2. Cut at 1, only 0 is under it.
#[test]
fn a_pixel_under_the_cut_is_clear() {
    let alphas = [127, 128, 0, 255];
    let frame = frame(4, 1, |x, _| alphas[x as usize] * 0x0101_0101);
    assert_eq!(clear_bits(&frame, 4, 1, 128), [0b0101]);
    assert_eq!(clear_bits(&frame, 4, 1, 1), [0b0100]);
}

// 6 x 6: 36 pixels, clear where the count is a multiple of 3 — bits 0, 3,
// …, 30 of the first word, and of the second bit 1 (pixel 33) alone,
// though the frame's rows are clear past the picture's last pixel.
#[test]
fn clear_bits_run_in_the_picture_order_across_rows() {
    let picture = |x: u32, y: u32| if (y * 6 + x) % 3 == 0 { 0 } else { WHITE };
    let frame = frame(6, 6, picture);
    assert_eq!(clear_bits(&frame, 6, 6, 128), [0x4924_9249, 0b10]);
}

// 197 x 131, cut at 128: its colours and its clear bits — 25,807 pixels,
// so the last word of each is part filled.
#[test]
fn every_device_writes_the_pinned_gif() {
    let (width, height) = (197, 131);
    let picture = Picture { width, height };
    let frame = frame(width, height, premultiplied(11));
    let rgb = cut_over_ground(&frame, width, height, [0, 0, 0], Some(128));
    assert_pinned("export/gif-rgb-197x131", &rgb[..picture.rgb_bytes() as usize]);
    let words = clear_bits(&frame, width, height, 128);
    let bits: Vec<u8> = words.iter().flat_map(|word| word.to_le_bytes()).collect();
    assert_pinned("export/gif-clear-197x131", &bits);
}

#[test]
fn clear_refuses_an_empty_picture_or_a_short_frame() {
    let frame = frame(4, 4, |_, _| WHITE);
    let Rig { engine, clear, .. } = rig();
    for bad in [
        Picture { width: 0, height: 4 },
        Picture { width: 4, height: 0 },
        Picture { width: 129, height: 4 },
    ] {
        assert!(clear.run(engine, &frame, bad, 128).is_none(), "{bad:?}");
    }
}

// ==== A PNG's filters ====

/// Each row of the filtered `out` — its filter's byte, then its own —
/// without the zeros that fill it out to a word, which it checks are there.
fn png_rows(out: &[u8], picture: Picture, pixel_bytes: u32) -> Vec<Vec<u8>> {
    let used = (picture.width * pixel_bytes) as usize + 1;
    out.chunks_exact(picture.png_row_bytes(pixel_bytes) as usize)
        .map(|row| {
            assert!(row[used..].iter().all(|&byte| byte == 0), "filled out: {row:?}");
            row[..used].to_vec()
        })
        .collect()
}

/// The filtered out of a PNG of four channels, the `width` x `height`
/// picture in `frame`.
fn png_rgba(frame: &Shown, width: u32, height: u32) -> Vec<u8> {
    let Rig { engine, png, .. } = rig();
    let out = png
        .rgba(engine, frame, Picture { width, height })
        .expect("png rgba");
    read_buffer(engine, &out)
}

/// [`png_rgba`]'s rows, as [`png_rows`] has them.
fn png_rgba_rows(frame: &Shown, width: u32, height: u32) -> Vec<Vec<u8>> {
    png_rows(&png_rgba(frame, width, height), Picture { width, height }, 4)
}

/// The filtered out of a PNG of three channels: the picture in `frame`
/// over `ground`.
fn png_rgb(frame: &Shown, width: u32, height: u32, ground: [u8; 3]) -> Vec<u8> {
    let Rig {
        engine,
        over_ground,
        png,
        ..
    } = rig();
    let picture = Picture { width, height };
    let rgb = over_ground
        .run(engine, frame, picture, ground, None)
        .expect("over ground");
    let out = png.packed(engine, &rgb, picture, 3).expect("png rgb");
    read_buffer(engine, &out)
}

/// The words of a picture whose rows are `rows` of red: the other channels
/// 0, so their bytes are 0 under every filter, and its alpha `alpha`.
fn reds(rows: &'static [&'static [u32]], alpha: u32) -> impl Fn(u32, u32) -> u32 {
    move |x, y| alpha << 24 | rows[y as usize][x as usize]
}

/// The rows of a PNG of four channels of [`reds`] with no alpha — handed
/// over packed, as a frame shown holds no colour where it holds no alpha
/// (frame_shown.wgsl).
fn clear_reds(rows: &'static [&'static [u32]]) -> Vec<Vec<u8>> {
    let picture = Picture { width: rows[0].len() as u32, height: rows.len() as u32 };
    packed_rows(&packed_rgba(picture.width, picture.height, reds(rows, 0)), picture)
}

// ---- By hand, from the law (png.wgsl's head) ----

// One colour, (10, 200, 30, 255), three pixels by two. A pixel costs 10 +
// 56 + 30 + 1 = 97 as it is. The top row: None 3·97; Sub 97, the first
// pixel and then nothing; Up as None, nothing above; Avg 97 + 2·(5 + 100
// + 15 + 128); Paeth 97 — on the top row a is nearest a + 0 − 0 —, a tie
// to Sub, the lower. Below it Up leaves nothing.
#[test]
fn a_flat_picture_is_under_sub_and_then_up() {
    let rows = png_rgba_rows(&frame(3, 2, |_, _| 0xff1e_c80a), 3, 2);
    assert_eq!(rows[0], [1, 10, 200, 30, 255, 0, 0, 0, 0, 0, 0, 0, 0]);
    assert_eq!(rows[1], [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
}

// Red (0, 150) over (50, 100). The top row costs 106 under every filter —
// 150 is predicted from nothing by each —, so None, the lowest. Below, the
// first pixel is 50 under each (a, b, c all 0); the second, x = 100 with
// a = 50, b = 150, c = 0: None 100, Sub 50, Up 50, Avg (50 + 150) >> 1 =
// 100 so 0, Paeth 50 (p = 200: pa 150, pb 50, pc 200, so b). Avg, at 50.
#[test]
fn a_tie_of_all_five_is_none_and_avg_wins_between_two() {
    static ROWS: [&[u32]; 2] = [&[0, 150], &[50, 100]];
    let rows = clear_reds(&ROWS);
    assert_eq!(rows[0], [0, 0, 0, 0, 0, 150, 0, 0, 0]);
    assert_eq!(rows[1], [3, 50, 0, 0, 0, 0, 0, 0, 0]);
}

/// Red (50, 50, 128) over (10, 10, 50): Paeth takes each of b, a and c in
/// turn on the lower row.
static PAETH_ROWS: [&[u32]; 2] = [&[50, 50, 128], &[10, 10, 50]];

// The top row: None 50 + 50 + 128 = 228, Sub 50 + 0 + 78 = 128, Up 228,
// Avg 50 + 25 + 103 = 178, Paeth as Sub — Sub, the lower. Below:
// - x = 10, a = c = 0, b = 50: None 10, Sub 10, Up 40, Avg 15, Paeth b
//   (p = 50: pa 50, pb 0) 40;
// - x = 10, a = 10, b = c = 50: None 10, Sub 0, Up 40, Avg 20, Paeth a
//   (p = 10) 0;
// - x = 50, a = 10, b = 128, c = 50: None 50, Sub 40, Up 78, Avg 19,
//   Paeth c (p = 88: pa 78, pb 40, pc 38) 0.
// None 70, Sub 50, Up 158, Avg 54, Paeth 40 — and Paeth's 40 is 216, a
// byte read as signed: as it is, Sub would win.
#[test]
fn paeth_wins_where_it_takes_each_of_its_three() {
    let rows = clear_reds(&PAETH_ROWS);
    assert_eq!(rows[0], [1, 50, 0, 0, 0, 0, 0, 0, 0, 78, 0, 0, 0]);
    assert_eq!(rows[1], [4, 216, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
}

// Red (50, 60, 50, 30) over (30, 30, 60, 30): Paeth's two ties, each on
// the byte it decides. The top row: Sub 50 + 10 + 10 + 20 = 90, Paeth as
// Sub, None and Up 190, Avg 110 — Sub. Below:
// - x = 30, a = c = 0, b = 50: Paeth b (p = 50), 20; Avg 5;
// - x = 30, a = 30, b = 60, c = 50: p = 40, pa = pc = 10 — a, the earlier,
//   so 0 (c would be 20); Sub 0, Avg 15;
// - x = 60, a = 30, b = 50, c = 60: Paeth a (p = 20: pa 10), 30; Up 10,
//   Avg 20;
// - x = 30, a = 60, b = 30, c = 50: p = 40, pb = pc = 10 — b, the earlier,
//   so 0 (c would be 20); Up 0, Avg 15.
// None 150, Sub 90, Up 60, Avg 55, Paeth 50: either tie to the later
// costs Paeth 20 and the row goes to Avg.
#[test]
fn paeth_breaks_a_tie_to_the_earlier() {
    static ROWS: [&[u32]; 2] = [&[50, 60, 50, 30], &[30, 30, 60, 30]];
    let rows = clear_reds(&ROWS);
    assert_eq!(rows[0], [1, 50, 0, 0, 0, 10, 0, 0, 0, 246, 0, 0, 0, 236, 0, 0, 0]);
    assert_eq!(rows[1], [4, 236, 0, 0, 0, 0, 0, 0, 0, 30, 0, 0, 0, 0, 0, 0, 0]);
}

// The same rows opaque, over the ground three bytes a pixel: the same
// choices, a pixel three bytes to the left — and the lower row starts on
// the ninth byte, inside a word.
#[test]
fn three_channels_take_the_same_filters_a_pixel_three_bytes_on() {
    let rows = png_rows(
        &png_rgb(&frame(3, 2, reds(&PAETH_ROWS, 0xff)), 3, 2, [1, 2, 3]),
        Picture { width: 3, height: 2 },
        3,
    );
    assert_eq!(rows[0], [1, 50, 0, 0, 0, 0, 0, 78, 0, 0]);
    assert_eq!(rows[1], [4, 216, 0, 0, 0, 0, 0, 0, 0, 0]);
}

// ---- The ledger ----

// 197 x 131: a row of four channels is 788 bytes and its out 792, of three
// 591 and 592.
#[test]
fn every_device_writes_the_pinned_png_rows() {
    let (width, height) = (197, 131);
    let frame = frame(width, height, premultiplied(11));
    assert_pinned("export/png-rgba-197x131", &png_rgba(&frame, width, height));
    let rgb = png_rgb(&frame, width, height, [0x12, 0x80, 0xed]);
    assert_pinned("export/png-rgb-197x131", &rgb);
}

// ---- The shape ----

#[test]
fn png_refuses_an_empty_picture_or_a_short_source() {
    let frame = frame(4, 4, |_, _| WHITE);
    let Rig {
        engine,
        over_ground,
        png,
        ..
    } = rig();
    for bad in [
        Picture { width: 0, height: 4 },
        Picture { width: 4, height: 0 },
        Picture { width: 129, height: 4 },
    ] {
        assert!(png.rgba(engine, &frame, bad).is_none(), "{bad:?}");
    }
    let rgb = over_ground
        .run(engine, &frame, Picture { width: 4, height: 4 }, [0, 0, 0], None)
        .expect("over ground");
    for bad in [
        Picture { width: 0, height: 4 },
        Picture { width: 4, height: 5 },
    ] {
        assert!(png.packed(engine, &rgb, bad, 3).is_none(), "{bad:?}");
    }
}

// ---- Bytes that lie packed: straight RGBA, an animated PNG's frame ----

/// `pixel`'s words over `width` x `height`, row after row, as the bytes the
/// app hands over: four a pixel, red first.
fn packed_rgba(width: u32, height: u32, pixel: impl Fn(u32, u32) -> u32) -> Vec<u8> {
    (0..height)
        .flat_map(|y| (0..width).map(move |x| (x, y)))
        .flat_map(|(x, y)| pixel(x, y).to_le_bytes())
        .collect()
}

/// The rows of a PNG of four channels from `bytes`, packed.
fn packed_rows(bytes: &[u8], picture: Picture) -> Vec<Vec<u8>> {
    let Rig { engine, png, .. } = rig();
    let source = engine.filled("packed rgba", bytes, wgpu::BufferUsages::STORAGE);
    let out = png.packed(engine, &source, picture, 4).expect("png packed");
    png_rows(&read_buffer(engine, &out), picture, 4)
}

// The law reads a picture's bytes wherever they lie: straight RGBA handed
// over packed is filtered as the same picture shown is — any colours,
// every pixel opaque or clear, so straight and premultiplied are one word,
// and a side no word's.
#[test]
fn packed_rgba_is_filtered_as_the_same_picture_in_a_frame() {
    let (width, height) = (37, 21);
    let picture = Picture { width, height };
    let pixel = |x, y| {
        let word = mixed(5)(x, y);
        if word & 0x0100_0000 == 0 { 0 } else { word | 0xff00_0000 }
    };
    let bytes = packed_rgba(width, height, pixel);
    assert_eq!(packed_rows(&bytes, picture), png_rgba_rows(&frame(width, height, pixel), width, height));
}

// A pixel whose alpha is not whole keeps it: (10, 20, 30, 128) alone is
// under None — on a top row of one pixel every filter leaves its bytes as
// they are, 10 + 20 + 30 + 128 each, and a tie goes to the lowest.
#[test]
fn a_packed_pixel_keeps_an_alpha_that_is_not_whole() {
    let picture = Picture { width: 1, height: 1 };
    assert_eq!(packed_rows(&[10, 20, 30, 128], picture), [vec![0, 10, 20, 30, 128]]);
}

// A count of bytes a pixel it has no pass of is refused, and says so.
#[test]
fn a_packed_png_of_a_count_it_reads_none_of_is_refused() {
    let Rig { engine, png, .. } = rig();
    let source = engine.filled("packed", &[0; 64], wgpu::BufferUsages::STORAGE);
    for pixel_bytes in [0, 1, 2, 5] {
        let picture = Picture { width: 2, height: 2 };
        assert!(png.packed(engine, &source, picture, pixel_bytes).is_none(), "{pixel_bytes}");
        assert!(last_error().contains("bytes a pixel"), "{}", last_error());
    }
}

// ==== Every pass ====

// A row past the device's workgroups down: the passes that take a row a
// group are refused, not handed a dispatch the device cannot run (the
// shared `fits`).
#[test]
fn a_picture_taller_than_a_dispatch_reaches_is_refused() {
    let Rig {
        engine,
        over_ground,
        clear,
        png,
        ..
    } = rig();
    let height = engine.device().limits().max_compute_workgroups_per_dimension + 1;
    let tall = Picture { width: 1, height };
    let frame = Shown::uploaded(engine, &WHITE.to_le_bytes().repeat(height as usize), tall).expect("uploaded");
    assert!(over_ground.run(engine, &frame, tall, [0, 0, 0], None).is_none());
    assert!(clear.run(engine, &frame, tall, 128).is_none());
    assert!(png.rgba(engine, &frame, tall).is_none());
}
