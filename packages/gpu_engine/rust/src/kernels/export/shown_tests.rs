//! A frame as the screen shows it (gpu-export-path ①⑴): each pass reads
//! the rows [`Shown`] copies of a surface — premultiplied, RGBA or BGRA —
//! by the one law it reads a run's tiles by, and takes it straight where
//! it takes a run's tiles as they are.

use super::tests::{frame, mixed, rig};
use super::{Clear, Frame, Nv12, Nv12Shape, Opaque, OverGround, Picture, PngFilter, Shown, Straight};
use crate::device::Engine;
use crate::testing::{a_device_of_its_own, last_error, read_buffer};

/// 37 x 21: a row of 148 bytes, which the copy starts 256 apart — a read
/// that took the picture's width for its stride would read other pixels.
const WIDTH: u32 = 37;
const HEIGHT: u32 = 21;

/// What the texture holds past the picture: no pixel of these pictures.
const PAST: u32 = 0xff12_3456;

/// A texture three texels wider and taller than `width` x `height`, laid
/// RGBA or `bgra`, holding `pixel` — a premultiplied word, red the low
/// byte — and [`PAST`] beyond the picture; its picture copied.
pub(super) fn shown(width: u32, height: u32, bgra: bool, pixel: impl Fn(u32, u32) -> u32) -> Shown {
    shown_on(rig().engine, (width, height), bgra, pixel)
}

/// [`shown`], on `engine`.
pub(super) fn shown_on(
    engine: &Engine,
    (width, height): (u32, u32),
    bgra: bool,
    pixel: impl Fn(u32, u32) -> u32,
) -> Shown {
    let size = wgpu::Extent3d {
        width: width + 3,
        height: height + 3,
        depth_or_array_layers: 1,
    };
    let texture = engine.device().create_texture(&wgpu::TextureDescriptor {
        label: Some("test shown"),
        size,
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: if bgra { wgpu::TextureFormat::Bgra8Unorm } else { wgpu::TextureFormat::Rgba8Unorm },
        usage: wgpu::TextureUsages::COPY_SRC | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    });
    let mut bytes = Vec::new();
    for y in 0..size.height {
        for x in 0..size.width {
            let word = if x < width && y < height { pixel(x, y) } else { PAST };
            let [r, g, b, a] = word.to_le_bytes();
            bytes.extend_from_slice(&if bgra { [b, g, r, a] } else { [r, g, b, a] });
        }
    }
    engine.queue.write_texture(
        texture.as_image_copy(),
        &bytes,
        wgpu::TexelCopyBufferLayout {
            offset: 0,
            bytes_per_row: Some(size.width * 4),
            rows_per_image: Some(size.height),
        },
        size,
    );
    Shown::of(engine, &texture, Picture { width, height }).expect("shown")
}

/// Every pass, compiled on the device that runs it.
type Passes<'a> = (&'a Nv12, &'a OverGround, &'a Clear, &'a Opaque, &'a PngFilter, &'a Straight);

/// What each pass puts for `picture` in `frame`, in one list: NV12, the
/// picture over a ground and cut over it, its clear bits, whether it is
/// opaque, its PNG rows of four and of three bytes a pixel, its pixels
/// straight, and the PNG rows of those.
fn every_pass(frame: Frame, picture: Picture) -> Vec<Vec<u8>> {
    let rig = rig();
    let passes = (&rig.nv12, &rig.over_ground, &rig.clear, &rig.opaque, &rig.png, &rig.straight);
    every_pass_on(rig.engine, passes, frame, picture)
}

/// [`every_pass`] of `passes`, on `engine`.
fn every_pass_on(engine: &Engine, passes: Passes, frame: Frame, picture: Picture) -> Vec<Vec<u8>> {
    let (nv12, over_ground, clear, opaque, png, straight) = passes;
    let read = |out: Option<wgpu::Buffer>| {
        read_buffer(engine, &out.unwrap_or_else(|| panic!("the pass runs: {}", last_error())))
    };
    let (width, height) = (picture.width.next_multiple_of(2), picture.height.next_multiple_of(2));
    let shape = Nv12Shape {
        src_width: picture.width,
        src_height: picture.height,
        width,
        height,
        y_stride: width.next_multiple_of(4),
    };
    let rgb = over_ground.run(engine, frame, picture, [9, 99, 199], None).expect("over ground");
    let rgba = straight.run(engine, frame, picture).expect("straight");
    vec![
        read(nv12.run(engine, frame, shape)),
        read_buffer(engine, &rgb),
        read(over_ground.run(engine, frame, picture, [9, 99, 199], Some(128))),
        read(clear.run(engine, frame, picture, 128)),
        read(opaque.run(engine, frame, picture)),
        read(png.rgba(engine, frame, picture)),
        read(png.packed(engine, &rgb, picture, 3)),
        read_buffer(engine, &rgba),
        read(png.packed(engine, &rgba, picture, 4)),
    ]
}

/// A picture of 480 x 400 on a device that binds 512 KiB: less than its
/// frame shown (2,048 bytes a row) or uploaded (1,920), than a run's tiles
/// of it (four rows of four, 1 MiB), and than what the passes over the
/// ground, straight and of PNG rows put and read — so each binds them a
/// band of rows at a time. Two rows of tiles, 256 KiB each, it holds: a
/// PNG row's filters read the row above it, which lies on the row of tiles
/// above where it begins one.
const BANDED: (Picture, u64) = (Picture { width: 480, height: 400 }, 512 << 10);

// On a device whose binding holds less than a frame, every pass puts what
// one that binds the frame whole puts — a run's tiles, a frame shown from
// an RGBA surface and a BGRA one, and one uploaded, its rows its width
// apart — and the device refuses no binding (board
// conversions-bind-a-frame-past-the-device-limit, 2026-11-17).
#[test]
fn every_pass_puts_a_frame_past_a_binding_as_it_puts_one_bound_whole() {
    let (picture, rig) = (BANDED.0, rig());
    let (width, height) = (picture.width, picture.height);
    let pixel = mixed(9);
    let rgba: Vec<u8> = (0..height)
        .flat_map(|y| (0..width).map(move |x| (x, y)))
        .flat_map(|(x, y)| pixel(x, y).to_le_bytes())
        .collect();
    let frames = |engine: &Engine| {
        [
            FrameOf::Tiles(super::tests::frame_on(engine, (width, height), PAST, &pixel)),
            FrameOf::Shown(shown_on(engine, (width, height), false, &pixel)),
            FrameOf::Shown(shown_on(engine, (width, height), true, &pixel)),
            FrameOf::Shown(Shown::uploaded(engine, &rgba, picture).expect("uploaded")),
        ]
    };
    let whole: Vec<_> = frames(rig.engine).iter().map(|frame| every_pass(frame.frame(), picture)).collect();

    let turn = a_device_of_its_own();
    let engine = turn.engine_binding(BANDED.1);
    let own = (Nv12::new(), OverGround::new(), Clear::new(), Opaque::new(), PngFilter::new(), Straight::new());
    let passes = (&own.0, &own.1, &own.2, &own.3, &own.4, &own.5);
    for (at, frame) in frames(&engine).iter().enumerate() {
        assert!(every_pass_on(&engine, passes, frame.frame(), picture) == whole[at], "frame {at}");
    }
    engine.wait().expect("the device refused no binding");
}

/// A frame a test made, which a pass is handed as a [`Frame`].
enum FrameOf {
    Tiles(wgpu::Buffer),
    Shown(Shown),
}

impl FrameOf {
    fn frame(&self) -> Frame<'_> {
        match self {
            Self::Tiles(tiles) => Frame::Tiles(tiles),
            Self::Shown(shown) => Frame::Shown(shown),
        }
    }
}

// Where a binding holds less than a row a pass reads or puts, the pass is
// refused, with why — not bound past.
#[test]
fn a_pass_whose_row_exceeds_a_binding_is_refused() {
    let turn = a_device_of_its_own();
    let engine = turn.engine_binding(1 << 16);
    let picture = Picture { width: 20_000, height: 2 };
    let frame = Shown::blank(&engine, picture).expect("a frame past a binding");

    assert!(Straight::new().run(&engine, Frame::Shown(&frame), picture).is_none());
    assert_eq!(last_error(), "a row of a pass binds 80000 bytes, past a binding of 65536");
    engine.wait().expect("the device refused no binding");
}

// A picture whose every pixel is opaque or clear is the same word straight
// and premultiplied: so a shown frame's passes are a run's of the same
// picture, byte for byte — its rows read where they lie, its colours where
// a BGRA surface lays them.
#[test]
fn every_pass_reads_a_shown_frame_as_it_reads_a_run_of_its_picture() {
    let picture = Picture { width: WIDTH, height: HEIGHT };
    let pixel = |x, y| {
        let word = mixed(5)(x, y);
        if word & 0x0100_0000 == 0 { 0 } else { word | 0xff00_0000 }
    };
    let run = every_pass(Frame::Tiles(&frame(WIDTH, HEIGHT, pixel)), picture);
    for bgra in [false, true] {
        let shown = shown(WIDTH, HEIGHT, bgra, pixel);
        assert_eq!(every_pass(Frame::Shown(&shown), picture), run, "bgra {bgra}");
    }
}

/// The PNG row of four bytes a pixel of the one premultiplied `pixel`:
/// its filter's byte — 0, which every filter ties with on a lone pixel —
/// and the pixel straight.
fn straight(pixel: u32) -> Vec<u8> {
    let rig = rig();
    let picture = Picture { width: 1, height: 1 };
    let shown = shown(1, 1, false, |_, _| pixel);
    let out = rig.png.rgba(rig.engine, Frame::Shown(&shown), picture).expect("png rgba");
    read_buffer(rig.engine, &out)[..5].to_vec()
}

// ---- By hand, from the law (frame_shown.wgsl: c·255 / a, half up) ----

// 50·255 + 100 = 12,850, over 200 is 64; 100·255 + 100 = 25,600, over 200
// is 128. Opaque, a pixel is its own; clear, nothing — a colour left at
// alpha 0 too, which no premultiply leaves.
#[test]
fn a_shown_pixel_is_made_straight_by_its_alpha() {
    assert_eq!(straight(0xc864_0032), [0, 64, 0, 128, 200]);
    assert_eq!(straight(0xff1e_140a), [0, 10, 20, 30, 255]);
    assert_eq!(straight(0), [0, 0, 0, 0, 0]);
    assert_eq!(straight(0x0000_0010), [0, 0, 0, 0, 0]);
}

// Every alpha, each colour of it — none, half, all of it and one between
// — made straight as the law says, read through a GIF's cut at 1, which
// lays each pixel that is not clear whole, in its straight colour.
#[test]
fn every_alpha_makes_its_colours_straight_by_the_law() {
    let rig = rig();
    let picture = Picture { width: 255, height: 4 };
    let colours = |x: u32, y: u32| {
        let alpha = x + 1;
        [0, alpha / 2, alpha, (alpha * 7 + y) % (alpha + 1)][y as usize]
    };
    let shown = shown(255, 4, false, |x, y| {
        let c = colours(x, y);
        u32::from_le_bytes([c as u8, (x + 1 - c) as u8, (c / 3) as u8, (x + 1) as u8])
    });
    let out = rig.over_ground.run(rig.engine, Frame::Shown(&shown), picture, [7, 7, 7], Some(1));
    let rgb = read_buffer(rig.engine, &out.expect("over ground"));
    let law = |c: u32, a: u32| ((c * 255 + a / 2) / a).min(255) as u8;
    for y in 0..4 {
        for x in 0..255 {
            let (a, c) = (x + 1, colours(x, y));
            let at = ((y * 255 + x) * 3) as usize;
            assert_eq!(rgb[at..at + 3], [law(c, a), law(a - c, a), law(c / 3, a)], "({x}, {y})");
        }
    }
}

// The straight pass takes each pixel by the same law, its alpha kept:
// every alpha, each colour of it, as the test above lays them; and the
// pixel the PNG's row takes straight, the same four bytes.
#[test]
fn the_straight_pass_makes_every_pixel_straight_by_the_law() {
    let rig = rig();
    let picture = Picture { width: 255, height: 4 };
    let colours = |x: u32, y: u32| {
        let alpha = x + 1;
        [0, alpha / 2, alpha, (alpha * 7 + y) % (alpha + 1)][y as usize]
    };
    let shown = shown(255, 4, true, |x, y| {
        let c = colours(x, y);
        u32::from_le_bytes([c as u8, (x + 1 - c) as u8, (c / 3) as u8, (x + 1) as u8])
    });
    let out = rig.straight.run(rig.engine, Frame::Shown(&shown), picture);
    let rgba = read_buffer(rig.engine, &out.expect("straight"));
    assert_eq!(rgba.len() as u64, picture.rgba_bytes());
    let law = |c: u32, a: u32| ((c * 255 + a / 2) / a).min(255) as u8;
    for y in 0..4 {
        for x in 0..255 {
            let (a, c) = (x + 1, colours(x, y));
            let at = ((y * 255 + x) * 4) as usize;
            assert_eq!(rgba[at..at + 4], [law(c, a), law(a - c, a), law(c / 3, a), a as u8], "({x}, {y})");
        }
    }
    let one = self::shown(1, 1, false, |_, _| 0xc864_0032);
    let pixel = rig.straight.run(rig.engine, Frame::Shown(&one), Picture { width: 1, height: 1 });
    assert_eq!(read_buffer(rig.engine, &pixel.expect("straight"))[..4], straight(0xc864_0032)[1..]);
}

// A shown frame's alpha is the top byte of its words wherever it lies: a
// pixel of 100 is under a cut at 128, and a picture all opaque is opaque.
#[test]
fn a_shown_frame_reads_each_alpha_where_it_lies() {
    let rig = rig();
    let one = shown(1, 1, false, |_, _| 0x6432_0a05);
    let bits = rig.clear.run(rig.engine, Frame::Shown(&one), Picture { width: 1, height: 1 }, 128);
    assert_eq!(read_buffer(rig.engine, &bits.expect("clear"))[0] & 1, 1);
    let opaque = shown(WIDTH, HEIGHT, true, |x, y| mixed(3)(x, y) | 0xff00_0000);
    let picture = Picture { width: WIDTH, height: HEIGHT };
    let answer = read_buffer(rig.engine, &rig.opaque.run(rig.engine, Frame::Shown(&opaque), picture).expect("opaque"));
    assert_eq!(answer[..4], [255, 0, 0, 0]);
}

// 1·255 + 1 = 256, over 2 is 128: 127.5 goes up. A colour past its alpha
// — no premultiplied pixel — stops at 255: (200·255 + 50) / 100 is 510.
#[test]
fn half_rounds_up_and_a_colour_stops_at_255() {
    assert_eq!(straight(0x0200_0001), [0, 128, 0, 0, 2]);
    assert_eq!(straight(0x6400_00c8), [0, 255, 0, 0, 100]);
}

// Where a pass takes a pixel straight it takes the shown one straight: a
// movie's luma from (64, 0, 128) — ((66·64 + 25·128 + 128) >> 8) + 16 =
// 45, not 39 from (50, 0, 100) — and a GIF's cut pixel in the colour it
// was laid with, whole.
#[test]
fn a_pass_that_takes_a_pixel_straight_takes_the_shown_one_straight() {
    let rig = rig();
    let picture = Picture { width: 1, height: 1 };
    let shown = shown(1, 1, false, |_, _| 0xc864_0032);
    let shape = Nv12Shape { src_width: 1, src_height: 1, width: 2, height: 2, y_stride: 4 };
    let nv12 = read_buffer(rig.engine, &rig.nv12.run(rig.engine, Frame::Shown(&shown), shape).expect("nv12"));
    assert_eq!(nv12[0], 45);
    let cut = rig.over_ground.run(rig.engine, Frame::Shown(&shown), picture, [255, 255, 255], Some(128));
    assert_eq!(read_buffer(rig.engine, &cut.expect("over ground"))[..3], [64, 0, 128]);
}

// A pass over the shades lays the premultiplied pixel as it is: 50 + 255 ·
// 55 / 255, 0 + 55, 100 + 55.
#[test]
fn over_the_ground_a_shown_pixel_is_laid_as_it_is_premultiplied() {
    let rig = rig();
    let shown = shown(1, 1, false, |_, _| 0xc864_0032);
    let picture = Picture { width: 1, height: 1 };
    let out = rig.over_ground.run(rig.engine, Frame::Shown(&shown), picture, [255, 255, 255], None);
    assert_eq!(read_buffer(rig.engine, &out.expect("over ground"))[..3], [105, 55, 155]);
}

// What a shown frame cannot be is refused, and says why.
#[test]
fn a_picture_the_surface_does_not_hold_is_refused() {
    let rig = rig();
    let shown = shown(WIDTH, HEIGHT, false, |_, _| 0);
    let tall = Picture { width: WIDTH, height: HEIGHT + 1 };
    assert!(rig.opaque.run(rig.engine, Frame::Shown(&shown), tall).is_none());
    assert_eq!(crate::testing::last_error(), "a 37x22 picture is not in a 37x21 frame");
}
