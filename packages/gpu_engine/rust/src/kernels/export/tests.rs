//! The export's conversions on a real GPU, checked against the ledger and
//! against what the law gives by hand — never against a CPU copy of it
//! (`kernels/mod.rs` has why).

use std::sync::OnceLock;

use wgpu::util::DeviceExt;

use super::{Nv12, Nv12Shape};
use crate::device::Engine;
use crate::kernels::composite::{TILE, TILE_TEXELS};
use crate::testing::{assert_pinned, first_engine, read_buffer};

struct Rig {
    engine: &'static Engine,
    nv12: Nv12,
}

/// One device and one compiled pass for every test here, as the app opens
/// one device (blend's tests have why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        Rig {
            engine,
            nv12: Nv12::new(engine),
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
    let (columns, rows) = (width.div_ceil(TILE), height.div_ceil(TILE));
    let mut words = vec![PAST; (u64::from(columns * rows) * TILE_TEXELS) as usize];
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
    let Rig { engine, nv12 } = rig();
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
    let Rig { engine, nv12 } = rig();
    for bad in [
        Nv12Shape { width: 5, ..shape(4, 4) },
        Nv12Shape { height: 2, ..shape(4, 4) },
        Nv12Shape { y_stride: 6, ..shape(4, 4) },
        Nv12Shape { width: 6, y_stride: 4, ..shape(4, 4) },
    ] {
        assert!(nv12.run(engine, &frame, bad).is_none(), "{bad:?}");
    }
}
