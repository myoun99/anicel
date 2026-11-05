//! The export's conversions on a real GPU, checked against the ledger and
//! against what the law gives by hand — never against a CPU copy of it
//! (`kernels/mod.rs` has why).

use std::sync::OnceLock;

use wgpu::util::DeviceExt;

use super::{Clear, Nv12, Nv12Shape, Opaque, OverGround, Picture};
use crate::device::Engine;
use crate::kernels::composite::{TILE, TILE_TEXELS};
use crate::testing::{assert_pinned, first_engine, read_buffer};

struct Rig {
    engine: &'static Engine,
    nv12: Nv12,
    over_ground: OverGround,
    opaque: Opaque,
    clear: Clear,
}

/// One device and one compiled pass each for every test here, as the app
/// opens one device (blend's tests have why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        Rig {
            engine,
            nv12: Nv12::new(engine),
            over_ground: OverGround::new(engine),
            opaque: Opaque::new(engine),
            clear: Clear::new(engine),
        }
    })
}

// ---- Frames ----

const RED: u32 = 0xff00_00ff;
const BLUE: u32 = 0xffff_0000;
const BLACK: u32 = 0xff00_0000;
const WHITE: u32 = 0xffff_ffff;
/// What a tile holds past the picture: a pixel no picture of these tests
/// has, so a read of it shows.
const PAST: u32 = 0xff12_3456;

/// A well-mixed u32 (lowbias32), for pictures no formula here can predict.
fn mix(mut h: u32) -> u32 {
    h ^= h >> 16;
    h = h.wrapping_mul(0x7feb_352d);
    h ^= h >> 15;
    h = h.wrapping_mul(0x846c_a68b);
    h ^ (h >> 16)
}

/// The composite's output tiles for a `width` x `height` picture, asked
/// row by row from its top-left tile; [`PAST`] where a tile runs past it.
fn frame(width: u32, height: u32, pixel: impl Fn(u32, u32) -> u32) -> wgpu::Buffer {
    frame_past(width, height, PAST, pixel)
}

/// [`frame`] with `past` where a tile runs past the picture.
fn frame_past(
    width: u32,
    height: u32,
    past: u32,
    pixel: impl Fn(u32, u32) -> u32,
) -> wgpu::Buffer {
    let (columns, rows) = (width.div_ceil(TILE), height.div_ceil(TILE));
    let mut words = vec![past; (u64::from(columns * rows) * TILE_TEXELS) as usize];
    for y in 0..height {
        for x in 0..width {
            let tile = (y / TILE) * columns + x / TILE;
            let at = u64::from(tile) * TILE_TEXELS + u64::from((y % TILE) * TILE + x % TILE);
            words[at as usize] = pixel(x, y);
        }
    }
    rig()
        .engine
        .device
        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("test frame"),
            contents: &words.iter().flat_map(|word| word.to_le_bytes()).collect::<Vec<_>>(),
            usage: wgpu::BufferUsages::STORAGE,
        })
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

fn nv12(frame: &wgpu::Buffer, shape: Nv12Shape) -> Vec<u8> {
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

// ---- By hand, from the law (qa_yuv601.h) ----

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
// the shift flooring −37.35 as C's does; Cr = (28688 >> 8) + 128 = 240.
// Blue: Y = (6503 >> 8) + 16 = 41; Cb = 240; Cr = (−4462 >> 8) + 128 = 110.
#[test]
fn red_and_blue_floor_their_negative_differences_as_the_law_does() {
    let shape = shape(4, 2);
    let bytes = nv12(&frame(4, 2, |x, _| if x < 2 { RED } else { BLUE }), shape);
    assert_eq!(sample(&bytes, shape, 0, 0), (82, 90, 240));
    assert_eq!(sample(&bytes, shape, 2, 0), (41, 240, 110));
}

// A 2 x 2 block takes its chroma from its top-left pixel, not an average.
#[test]
fn a_blocks_colour_is_its_top_left_pixels() {
    let shape = shape(2, 2);
    let bytes = nv12(&frame(2, 2, |x, y| if (x, y) == (0, 0) { RED } else { BLUE }), shape);
    assert_eq!(sample(&bytes, shape, 1, 1), (41, 90, 240));
}

// The law reads no alpha: a clear red is red's numbers.
#[test]
fn alpha_is_not_read() {
    let shape = shape(2, 2);
    let bytes = nv12(&frame(2, 2, |_, _| RED & 0x00ff_ffff), shape);
    assert_eq!(sample(&bytes, shape, 0, 0), (82, 90, 240));
}

// A 3 x 3 picture in a 4 x 4 frame with rows of 8: the fourth column and
// row are white, as are the four bytes of each row past the width — never
// what the tile holds there. The block at (2, 2) has its top-left in the
// picture, so it keeps red's colour.
#[test]
fn past_the_picture_is_white_whatever_the_tile_holds() {
    let shape = Nv12Shape {
        y_stride: 8,
        ..shape(3, 3)
    };
    let bytes = nv12(&frame(3, 3, |_, _| RED), shape);
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

// Pixels on either side of a tile's edge, in both directions, land where
// the picture has them: a red column at x = 128 and a red row at y = 128.
#[test]
fn the_frame_is_read_across_its_tiles() {
    let shape = shape(130, 130);
    let cross = |x, y| if x == 128 || y == 128 { RED } else { WHITE };
    let bytes = nv12(&frame(130, 130, cross), shape);
    for (x, y, luma) in [
        (127, 5, 235),
        (128, 5, 82),
        (129, 5, 235),
        (5, 127, 235),
        (5, 128, 82),
        (129, 129, 235),
    ] {
        assert_eq!(sample(&bytes, shape, x, y).0, luma, "({x}, {y})");
    }
}

// ---- The ledger ----

/// A picture of any colours and alphas.
fn mixed(seed: u32) -> impl Fn(u32, u32) -> u32 {
    move |x, y| mix(seed ^ mix(x ^ mix(y)))
}

// 197 x 131: odd sides padded to 198 x 132, rows of 200, two tiles each
// way; 256 x 128: exact tiles, no padding.
#[test]
fn every_device_writes_the_pinned_nv12() {
    for (width, height, y_stride) in [(197, 131, 200), (256, 128, 256)] {
        let shape = Nv12Shape {
            y_stride,
            ..shape(width, height)
        };
        let id = format!("export/nv12-{width}x{height}-stride{y_stride}");
        assert_pinned(&id, &nv12(&frame(width, height, mixed(7)), shape));
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
fn over_ground(frame: &wgpu::Buffer, width: u32, height: u32, ground: [u8; 3]) -> Vec<u8> {
    cut_over_ground(frame, width, height, ground, None)
}

/// [`over_ground`] with the alpha `cut`.
fn cut_over_ground(
    frame: &wgpu::Buffer,
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

// ---- By hand, from the law (`_overGround` after the engine's premultiply) ----

// Opaque: p = round(c·255 / 255) = c and nothing of the ground. 200 is one
// the premultiply's second term carries: t = 51128, t >> 8 = 199, and
// (51128 + 199) >> 8 = 200.
#[test]
fn an_opaque_pixel_is_its_own_colour() {
    let bytes = over_ground(&frame(1, 1, |_, _| 0xff1e_c80a), 1, 1, [1, 2, 3]);
    assert_eq!(bytes, [10, 200, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
}

// Clear: p = (0 + 128) >> 8 = 0, and the ground whole — g·255 / 255 = g —,
// whatever colour the clear pixel keeps.
#[test]
fn a_clear_pixel_is_the_ground() {
    let bytes = over_ground(&frame(1, 1, |_, _| 0x00ff_ffff), 1, 1, [12, 34, 56]);
    assert_eq!(rgb_at(&bytes, 1, 0, 0), [12, 34, 56]);
}

// White at 128: t = 255·128 + 128 = 32768, p = (32768 + 128) >> 8 = 128.
// Over black that is all; over white, + 255·127 / 255 = 127. Red at 128
// over white: 128 + 127 for red, 0 + 127 for green and blue.
#[test]
fn half_a_colour_takes_half_the_ground() {
    let halves = frame(2, 1, |x, _| if x == 0 { 0x80ff_ffff } else { 0x8000_00ff });
    assert_eq!(rgb_at(&over_ground(&halves, 2, 1, [0, 0, 0]), 2, 0, 0), [128, 128, 128]);
    let white = over_ground(&halves, 2, 1, [255, 255, 255]);
    assert_eq!(rgb_at(&white, 2, 0, 0), [255, 255, 255]);
    assert_eq!(rgb_at(&white, 2, 1, 0), [255, 127, 127]);
}

// Over a ground of red 100:
// - black at 1: p = 0, and 100·254 / 255 = 99.6 floors to 99;
// - 127 at 2: p = round(254 / 255) = 1 (t = 382, (382 + 1) >> 8), and
//   100·253 / 255 = 99.2 floors to 99;
// - 127 at 1: p = round(127 / 255) = 0 (t = 255, 255 >> 8).
#[test]
fn the_premultiply_rounds_and_the_ground_floors() {
    let pixels = [0x0100_0000, 0x027f_7f7f, 0x017f_7f7f];
    let bytes = over_ground(&frame(3, 1, |x, _| pixels[x as usize]), 3, 1, [100, 0, 0]);
    assert_eq!(bytes[..9], [99, 0, 0, 100, 1, 1, 99, 0, 0]);
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

// Pixels on either side of a tile's edge, in both directions, land where
// the picture has them: a red column at x = 128 and a red row at y = 128.
// 130 is no multiple of 4, so most runs here cross a row.
#[test]
fn over_the_ground_reads_the_frame_across_its_tiles() {
    let cross = |x, y| if x == 128 || y == 128 { RED } else { WHITE };
    let bytes = over_ground(&frame(130, 130, cross), 130, 130, [0, 0, 0]);
    for (x, y, rgb) in [
        (127, 5, [255, 255, 255]),
        (128, 5, [255, 0, 0]),
        (129, 5, [255, 255, 255]),
        (5, 127, [255, 255, 255]),
        (5, 128, [255, 0, 0]),
        (129, 129, [255, 255, 255]),
    ] {
        assert_eq!(rgb_at(&bytes, 130, x, y), rgb, "({x}, {y})");
    }
}

// ---- The ledger ----

// 197 x 131: two tiles each way, and 25,807 pixels — a last run of three;
// 256 x 128: exact tiles and runs.
#[test]
fn every_device_writes_the_pinned_over_ground() {
    for (width, height) in [(197, 131), (256, 128)] {
        let picture = Picture { width, height };
        let bytes = over_ground(&frame(width, height, mixed(11)), width, height, [0x12, 0x80, 0xed]);
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
fn opaque(frame: &wgpu::Buffer, width: u32, height: u32) -> u32 {
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
// the tiles are clear, as the composite leaves them — and not read.
#[test]
fn a_picture_whose_every_pixel_is_opaque_is_opaque() {
    assert_eq!(opaque(&frame_past(197, 131, 0, opaque_mixed), 197, 131), 255);
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
        assert!(opaque(&frame_past(197, 131, 0, picture), 197, 131) < 255, "{at:?}");
    }
}

#[test]
fn a_clear_pixel_is_not_opaque() {
    assert!(opaque(&frame(1, 1, |_, _| 0x00ff_ffff), 1, 1) < 255);
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
    let pixels = [0x8000_00ff, 0x7f00_00ff];
    let frame = frame(2, 1, |x, _| pixels[x as usize]);
    let bytes = cut_over_ground(&frame, 2, 1, [255, 255, 255], Some(128));
    assert_eq!(bytes[..6], [255, 0, 0, 255, 255, 255]);
}

// Cut at 0, no pixel is under it: a GIF that keeps no clear colour takes
// each pixel's own colour — a clear one's (30, 10, 20) too.
#[test]
fn cut_at_nothing_every_pixel_is_its_own_colour() {
    let pixels = [0x0014_0a1e, 0x8000_00ff];
    let frame = frame(2, 1, |x, _| pixels[x as usize]);
    let bytes = cut_over_ground(&frame, 2, 1, [99, 99, 99], Some(0));
    assert_eq!(bytes[..6], [30, 10, 20, 255, 0, 0]);
}

/// The clear bits the pass writes for a `width` x `height` picture cut at
/// `cut`, a word of 32 pixels each.
fn clear_bits(frame: &wgpu::Buffer, width: u32, height: u32, cut: u8) -> Vec<u32> {
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
// not. Pixels 0 and 2.
#[test]
fn a_pixel_under_the_cut_is_clear() {
    let alphas = [127, 128, 0, 255];
    let frame = frame(4, 1, |x, _| alphas[x as usize] << 24 | 0x00ff_ffff);
    assert_eq!(clear_bits(&frame, 4, 1, 128), [0b0101]);
}

// 6 x 6: 36 pixels, clear where the count is a multiple of 3 — bits 0, 3,
// …, 30 of the first word, and of the second bit 1 (pixel 33) alone,
// though the tile is clear past the picture's last pixel.
#[test]
fn clear_bits_run_in_the_picture_order_across_rows() {
    let picture = |x: u32, y: u32| if (y * 6 + x) % 3 == 0 { 0 } else { WHITE };
    let frame = frame_past(6, 6, 0, picture);
    assert_eq!(clear_bits(&frame, 6, 6, 128), [0x4924_9249, 0b10]);
}

// A clear column at x = 128 and a clear row at y = 128, read where the
// picture has them, on either side of a tile's edge.
#[test]
fn clear_bits_read_the_frame_across_its_tiles() {
    let cross = |x, y| if x == 128 || y == 128 { 0 } else { WHITE };
    let words = clear_bits(&frame(130, 130, cross), 130, 130, 128);
    let clear = |x: u32, y: u32| {
        let index = y * 130 + x;
        words[(index / 32) as usize] >> (index % 32) & 1 == 1
    };
    for (x, y, wanted) in [
        (127, 5, false),
        (128, 5, true),
        (129, 5, false),
        (5, 127, false),
        (5, 128, true),
        (128, 129, true),
        (129, 129, false),
    ] {
        assert_eq!(clear(x, y), wanted, "({x}, {y})");
    }
}

// 197 x 131, cut at 128: its colours and its clear bits — 25,807 pixels,
// so the last word of each is part filled.
#[test]
fn every_device_writes_the_pinned_gif() {
    let (width, height) = (197, 131);
    let picture = Picture { width, height };
    let frame = frame(width, height, mixed(11));
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
