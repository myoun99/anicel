//! A frame's last picture on the engine (gpu-export-path ①⑵): a frame the
//! export makes, and what is laid over it, checked against what the law
//! gives by hand — never against a CPU copy of it (`kernels/mod.rs`).

use super::shown_tests::{shown, shown_on};
use super::tests::rig;
use super::{Clear, Cover, Lay, Picture, Shown, Source};
use crate::device::Engine;
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::composite::tests::{Pool, mix, pixel_at, rig as composite_rig, row};
use crate::kernels::composite::{NO_EDGE, Plan, WHOLE};
use crate::kernels::shared::tests::premultiplied;
use crate::kernels::shared::{gpu_engine_kernels_built_here, le_words, room};
use crate::testing::{a_device_of_its_own, last_error, read_buffer};

const WHITE: u32 = 0xffff_ffff;
const RED: u32 = 0xff00_00ff;

/// A frame of `width` x `height` the export made, laid with `ground`.
fn blank(width: u32, height: u32, ground: u32) -> Shown {
    let rig = rig();
    let frame = Shown::blank(rig.engine, Picture { width, height }).expect("blank");
    rig.lay.run(rig.engine, &frame, Source::Solid(ground), u16::MAX, None, None).expect("ground");
    frame
}

/// `width` x `height` of `word` — premultiplied, red the low byte — as the
/// app hands a picture it rastered.
fn uploaded(width: u32, height: u32, word: impl Fn(u32, u32) -> u32) -> Shown {
    let rgba: Vec<u8> = (0..height)
        .flat_map(|y| (0..width).map(move |x| (x, y)))
        .flat_map(|(x, y)| word(x, y).to_le_bytes())
        .collect();
    Shown::uploaded(rig().engine, &rgba, Picture { width, height }).expect("uploaded")
}

/// The words `frame` holds, row after row.
fn words(frame: &Shown) -> Vec<u32> {
    let bytes = read_buffer(rig().engine, &frame.rows);
    bytes.chunks_exact(4).map(|word| u32::from_le_bytes([word[0], word[1], word[2], word[3]])).collect()
}

/// Lays `source` at (`x`, `y`) over `onto` at `opacity`, under `cover`.
fn lay(onto: &Shown, source: &Shown, (x, y): (i32, i32), opacity: u16, cover: Option<&Cover>) {
    let rig = rig();
    rig.lay
        .run(rig.engine, onto, Source::Frame { frame: source, x, y }, opacity, cover, None)
        .expect("laid");
}

// A ground of straight 0x80 alpha, blue 0x40, green 0x80, red 0xff is kept
// premultiplied (premultiply.wgsl): red 255·128/255 = 128, green
// 128·128/255 = 64.25 → 64, blue 64·128/255 = 32.1 → 32.
#[test]
fn a_frame_the_export_makes_is_its_ground_premultiplied() {
    assert_eq!(words(&blank(5, 3, 0x8040_80ff)), vec![0x8020_4080; 15]);
}

#[test]
fn a_ground_of_no_alpha_leaves_the_frame_clear() {
    assert_eq!(words(&blank(5, 3, 0x00ff_ffff)), vec![0; 15]);
}

#[test]
fn an_opaque_picture_is_laid_where_it_stands_and_nothing_else_moves() {
    let frame = blank(6, 4, WHITE);
    lay(&frame, &uploaded(2, 2, |_, _| RED), (3, 1), u16::MAX, None);

    let inside = |at: usize| (3..5).contains(&(at % 6)) && (1..3).contains(&(at / 6));
    let expected: Vec<u32> = (0..24).map(|at| if inside(at) { RED } else { WHITE }).collect();
    assert_eq!(words(&frame), expected);
}

// Past the frame's left edge, only its column 1 meets it; past its right,
// nothing does.
#[test]
fn a_picture_past_the_frame_is_laid_where_they_meet() {
    let frame = blank(6, 4, WHITE);
    let picture = uploaded(2, 2, |x, y| [0xff00_ff00, RED][usize::from(x == 1 && y == 0)]);
    lay(&frame, &picture, (-1, 3), u16::MAX, None);
    lay(&frame, &picture, (6, 0), u16::MAX, None);

    let mut expected = vec![WHITE; 24];
    expected[18] = RED;
    assert_eq!(words(&frame), expected);
}

// Red over white at half — 32768 of 65535, as the composite lays a row at half
// (blend_laid): alpha out 1, and each colour the two weighed — green and blue
// 65535·(1 − 32768/65535) = 32767, a byte (32767 + 128) / 257 → 127; red 255.
#[test]
fn half_an_opacity_lays_half_the_picture() {
    let frame = blank(3, 1, WHITE);
    lay(&frame, &uploaded(3, 1, |_, _| RED), (0, 0), 32768, None);

    assert_eq!(words(&frame), vec![0xff7f_7fff; 3]);
}

// What a pixel takes is its cover's byte: none, half or all of the red.
#[test]
fn a_cover_lays_what_each_pixel_takes() {
    let rig = rig();
    let frame = blank(3, 1, WHITE);
    let cover = Cover::of(rig.engine, &[0, 128, 255], Picture { width: 3, height: 1 }).expect("cover");
    lay(&frame, &uploaded(3, 1, |_, _| RED), (0, 0), u16::MAX, Some(&cover));

    assert_eq!(words(&frame), vec![WHITE, 0xff7f_7fff, RED]);
}

// A picture under the frame thins what lies under it alone: half a red
// laid over nothing keeps its colour at half its alpha — 32768, a byte
// (32768 + 128) / 257 = 128 — premultiplied, red 255·128/255 = 128.
#[test]
fn half_a_picture_over_nothing_is_its_colour_at_half_its_alpha() {
    let frame = blank(2, 1, 0);
    lay(&frame, &uploaded(2, 1, |_, _| RED), (0, 0), 32768, None);

    assert_eq!(words(&frame), vec![0x8000_0080; 2]);
}

// A frame shown from a BGRA surface is laid in its own colours, as one
// shown from an RGBA surface.
#[test]
fn a_frame_shown_is_laid_in_its_colours_however_its_surface_lies() {
    let picture = |x: u32, y: u32| 0xff00_0000 | (x * 40) << 16 | (y * 60) << 8 | 200;
    let laid = |bgra: bool| {
        let frame = blank(4, 3, WHITE);
        lay(&frame, &shown(4, 3, bgra, picture), (0, 0), u16::MAX, None);
        words(&frame)
    };

    let expected: Vec<u32> = (0..12).map(|at| picture(at % 4, at / 4)).collect();
    assert_eq!(laid(false), expected);
    assert_eq!(laid(true), expected);
}

// The conversions read a frame the export laid as a frame shown: its
// pixels, opaque everywhere.
#[test]
fn a_frame_laid_is_read_by_the_conversions() {
    let rig = rig();
    let frame = blank(5, 2, WHITE);
    lay(&frame, &uploaded(2, 2, |_, _| RED), (1, 0), u16::MAX, None);
    let picture = Picture { width: 5, height: 2 };

    let opaque = rig.opaque.run(rig.engine, &frame, picture).expect("opaque");
    assert_eq!(read_buffer(rig.engine, &opaque)[..4], 255u32.to_le_bytes());
    let rgb = rig.over_ground.run(rig.engine, &frame, picture, [0, 0, 0], None);
    let rgb = read_buffer(rig.engine, &rgb.expect("over ground"));
    assert_eq!(rgb[..9], [255, 255, 255, 255, 0, 0, 255, 0, 0]);
}

#[test]
fn a_cover_not_the_frame_s_size_is_refused() {
    let rig = rig();
    let frame = blank(3, 2, WHITE);
    let cover = Cover::of(rig.engine, &[255; 3], Picture { width: 3, height: 1 }).expect("cover");
    let laid = rig.lay.run(rig.engine, &frame, Source::Solid(RED), u16::MAX, Some(&cover), None);

    assert!(laid.is_none());
    assert_eq!(last_error(), "a 3x1 cover is not a 3x2 frame's");
}

#[test]
fn a_frame_shown_from_a_bgra_surface_is_not_laid_onto() {
    let rig = rig();
    let laid = rig.lay.run(rig.engine, &shown(3, 2, true, |_, _| RED), Source::Solid(RED), u16::MAX, None, None);

    assert!(laid.is_none());
    assert_eq!(last_error(), "a frame is laid onto as the export lays one: RGBA, not BGRA");
}

#[test]
fn a_picture_or_a_cover_of_too_few_bytes_is_refused() {
    let engine = rig().engine;
    let picture = Picture { width: 2, height: 2 };

    assert!(Shown::uploaded(engine, &[0; 15], picture).is_none());
    assert_eq!(last_error(), "a 2x2 picture is 16 bytes, not 15");
    assert!(Cover::of(engine, &[0; 3], picture).is_none());
    assert_eq!(last_error(), "a 2x2 cover is 4 bytes, not 3");
}

// Within [1, 1, 4, 2) of a 5 x 3 frame: three pixels of its middle row
// take the picture, every other is as it was — a cut's whole pixels.
#[test]
fn a_picture_is_laid_only_within_the_pixels_named() {
    let rig = rig();
    let frame = blank(5, 3, WHITE);
    let picture = uploaded(5, 3, |_, _| RED);
    let source = Source::Frame { frame: &picture, x: 0, y: 0 };
    rig.lay.run(rig.engine, &frame, source, u16::MAX, None, Some([1, 1, 4, 2])).expect("laid");
    rig.lay.run(rig.engine, &frame, source, u16::MAX, None, Some([4, 0, 2, 3])).expect("laid");

    let inside = |at: usize| (1..4).contains(&(at % 5)) && at / 5 == 1;
    let expected: Vec<u32> = (0..15).map(|at| if inside(at) { RED } else { WHITE }).collect();
    assert_eq!(words(&frame), expected);
}

#[test]
fn a_colour_is_laid_only_within_the_pixels_named() {
    let rig = rig();
    let frame = blank(3, 2, WHITE);
    rig.lay.run(rig.engine, &frame, Source::Solid(RED), u16::MAX, None, Some([-4, 1, 2, 9])).expect("laid");

    assert_eq!(words(&frame), vec![WHITE, WHITE, WHITE, RED, RED, WHITE]);
}

#[test]
fn a_frame_the_export_made_reads_back_as_it_lies() {
    let frame = blank(3, 2, WHITE);
    lay(&frame, &uploaded(1, 1, |_, _| RED), (2, 1), u16::MAX, None);
    let (rows, bytes) = frame.laid_rows().expect("rows");

    assert_eq!(bytes, 3 * 2 * 4);
    let laid: Vec<u8> = [WHITE, WHITE, WHITE, WHITE, WHITE, RED].iter().flat_map(|w| w.to_le_bytes()).collect();
    assert_eq!(read_buffer(rig().engine, &rows), laid);
    assert!(uploaded(1, 1, |_, _| RED).laid_rows().is_none());
    assert_eq!(last_error(), "a frame is read back where the export made it");
}

// Warmed on another thread, a lay compiles nothing on the one it lays on:
// the app warms it off the thread its frames are built on (🗣️관제
// 2026-11-10 18:14 — no kernel compiled there).
#[test]
fn a_lay_warmed_on_another_thread_compiles_nothing_where_it_lays() {
    let engine = rig().engine;
    let lay = Lay::new();
    std::thread::scope(|scope| {
        scope.spawn(|| lay.pipelines.warm(engine, true));
    });
    let surface_laid = shown(2, 1, true, |_, _| RED);
    let before = gpu_engine_kernels_built_here();

    let frame = Shown::blank(engine, Picture { width: 2, height: 1 }).expect("blank");
    lay.run(engine, &frame, Source::Solid(WHITE), u16::MAX, None, None).expect("ground");
    lay.run(engine, &frame, Source::Frame { frame: &surface_laid, x: 0, y: 0 }, u16::MAX, None, None).expect("laid");

    assert_eq!(gpu_engine_kernels_built_here(), before);
    assert_eq!(words(&frame), vec![RED; 2]);
}

// ---- A frame past a binding (board the-engine-binds-a-plane-past-the-
// device-limit, 2026-11-17) ----

/// What a bake's lays leave on a 37 x 23 frame, each pass binding no more
/// than `room` bytes of a plane: a ground, a frame shown laid at (-4, 3)
/// under a cover at a strength — its rows 64 words for 30 pixels —, and a
/// colour within a box under it.
fn baked_in(room: u64) -> Vec<u32> {
    let rig = rig();
    let picture = Picture { width: 37, height: 23 };
    let frame = Shown::blank(rig.engine, picture).expect("blank");
    let alpha: Vec<u8> = (0..37 * 23).map(|at: u32| (at * 37 % 256) as u8).collect();
    let cover = Cover::of(rig.engine, &alpha, picture).expect("cover");
    let shown = shown(30, 20, false, |x, y| {
        0xff00_0000 | (x * 8) << 16 | (y * 12) << 8 | 90
    });
    let laid = |source: Source, opacity: u16, cover: Option<&Cover>, within| {
        rig.lay
            .laid_by(rig.engine, (&frame, source), (opacity, cover, within), room)
            .expect("laid");
    };
    laid(Source::Solid(WHITE), u16::MAX, None, None);
    let source = Source::Frame { frame: &shown, x: -4, y: 3 };
    laid(source, 40_000, Some(&cover), None);
    laid(Source::Solid(RED), 30_000, Some(&cover), Some([5, 2, 33, 21]));
    words(&frame)
}

// A binding of three of the source's rows lays the frame three rows a
// pass — the frame's, the source's and the cover's rows each bound from
// where the device lets a binding begin, at or before the band's first —
// and lays what passes binding them whole do.
#[test]
fn a_frame_past_a_binding_is_laid_a_band_of_rows_at_a_time() {
    let engine = rig().engine;
    let step = u64::from(engine.device().limits().min_storage_buffer_offset_alignment);

    assert!(baked_in(step + 3 * 256) == baked_in(room(engine)));
}

// Where a binding holds less than a row of the frame — counted from where
// the device lets the binding begin, at or before the row — the lay is
// refused, not bound past: rows of 37 words, 148 bytes, the second's
// binding begun at the first's.
#[test]
fn a_frame_whose_row_exceeds_a_binding_is_refused() {
    let rig = rig();
    let step = u64::from(rig.engine.device().limits().min_storage_buffer_offset_alignment);
    assert!(step > 148, "⛔premise: the second row begins inside the first step");
    let frame = Shown::blank(rig.engine, Picture { width: 37, height: 2 }).expect("blank");
    let ground = (&frame, Source::Solid(WHITE));

    assert!(rig.lay.laid_by(rig.engine, ground, (u16::MAX, None, None), 147).is_none());
    assert_eq!(last_error(), "a row of a pass binds 148 bytes, past a binding of 147");
    assert!(rig.lay.laid_by(rig.engine, ground, (u16::MAX, None, None), 200).is_none());
    assert_eq!(last_error(), "a row of a pass binds 296 bytes, past a binding of 200");
}

/// A frame of 330 x 200 a device binds 64 KiB of — less than the frame,
/// its cover or the picture laid over it, as lavapipe's 128 MiB holds less
/// than a bake's frame of 139,332,960 bytes.
const SMALL: (Picture, u64) = (Picture { width: 330, height: 200 }, 1 << 16);

/// A frame of [`SMALL`] made on `engine`, its ground laid.
fn on_a_small_binding(engine: &Engine, lay: &Lay) -> Shown {
    let frame = Shown::blank(engine, SMALL.0).expect("a frame past a binding");
    lay.run(engine, &frame, Source::Solid(WHITE), u16::MAX, None, None).expect("ground");
    frame
}

// A picture of 400 x 150 laid at (-30, 25) under a whole cover — its rows
// wider than the frame's, so they bound the band — and a surface's copy of
// 330 x 60 laid at (0, -35) are laid where they lie, and the device
// refuses no binding.
#[test]
fn a_frame_past_the_device_s_binding_is_made_and_laid() {
    let turn = a_device_of_its_own();
    let engine = turn.engine_binding(SMALL.1);
    let lay = Lay::new();
    let frame = on_a_small_binding(&engine, &lay);
    let word = |x: u32, y: u32| 0xff00_0000 | x << 8 | y;
    let rgba: Vec<u8> = (0..150)
        .flat_map(|y| (0..400).map(move |x| word(x, y)))
        .flat_map(u32::to_le_bytes)
        .collect();
    let picture = Shown::uploaded(&engine, &rgba, Picture { width: 400, height: 150 })
        .expect("a picture past a binding");
    let cover = Cover::of(&engine, &[255; 330 * 200], SMALL.0).expect("a cover past a binding");
    let source = Source::Frame { frame: &picture, x: -30, y: 25 };
    lay.run(&engine, &frame, source, u16::MAX, Some(&cover), None).expect("laid");
    let texel = |x: u32, y: u32| 0xff00_0000 | (y + 100) << 16 | x % 256;
    let surface = shown_on(&engine, (330, 60), false, texel);
    let source = Source::Frame { frame: &surface, x: 0, y: -35 };
    lay.run(&engine, &frame, source, u16::MAX, None, None).expect("laid");

    engine.wait().expect("the device refused no binding");
    let expected: Vec<u32> = (0..200)
        .flat_map(|y| (0..330).map(move |x| (x, y)))
        .map(|(x, y)| match y {
            ..25 => texel(x, y + 35),
            25..175 => word(x + 30, y - 25),
            _ => WHITE,
        })
        .collect();
    assert!(le_words(&read_buffer(&engine, &frame.rows)) == expected);
}

// On a device whose binding holds less than the frame, the frame is read
// for its clear bits: a picture laid over nothing, rows 25 to 175 of 200 —
// every pixel off them is clear — and the device refuses no binding.
#[test]
fn a_frame_past_the_device_s_binding_is_read_for_its_clear_bits() {
    let turn = a_device_of_its_own();
    let engine = turn.engine_binding(SMALL.1);
    let lay = Lay::new();
    let frame = Shown::blank(&engine, SMALL.0).expect("a frame past a binding");
    let rgba = vec![255; 400 * 150 * 4];
    let picture = Shown::uploaded(&engine, &rgba, Picture { width: 400, height: 150 })
        .expect("a picture past a binding");
    let source = Source::Frame { frame: &picture, x: -30, y: 25 };
    lay.run(&engine, &frame, source, u16::MAX, None, None).expect("laid");
    let bits = Clear::new().run(&engine, &frame, SMALL.0, 128).expect("clear bits");

    engine.wait().expect("the device refused no binding");
    let mut expected = vec![0u32; (330 * 200usize).div_ceil(32)];
    for at in 0..330 * 200 {
        if !(25..175).contains(&(at / 330)) {
            expected[at / 32] |= 1 << (at % 32);
        }
    }
    assert!(le_words(&read_buffer(&engine, &bits)) == expected);
}

/// Straight, at `alpha`, its channels each 0 or 255 as `seed` falls at
/// (`x`, `y`): a colour its premultiplied bytes hold whole — 255 · a / 255
/// is a, which divides back to 255.
fn whole_colour(seed: u32, (x, y): (u32, u32), alpha: u32) -> u32 {
    if alpha == 0 {
        return 0;
    }
    let h = mix(seed ^ (x << 8 | y).wrapping_mul(0x9e37_79b9));
    let rgb: u32 = (0..3).filter(|c| h >> c & 1 == 1).map(|c| 0xff << (c * 8)).sum();
    rgb | alpha << 24
}

// Every alpha laid over every alpha — the lower picture's x, the upper's
// y — in colours whose premultiplied bytes hold them whole: the export lays
// the two as the plan stacks two rows in NORMAL, shown premultiplied, on
// every pixel. 🔬Measured 11-17 on the Surface (board
// the-engine-lays-a-picture-over-by-two-laws): in colours of any byte the
// two part on 39,869 of the 65,536 pixels, by 2 at most — the bytes' round
// trip, which this leaves out (lay.wgsl `widened` has why).
#[test]
fn the_export_lays_a_picture_by_the_composite_s_law() {
    let side = 256;
    let lower = |x: u32, y: u32| whole_colour(1, (x, y), x);
    let upper = |x: u32, y: u32| whole_colour(2, (x, y), y);
    let pixels: Vec<(u32, u32)> =
        (0..side).flat_map(|y| (0..side).map(move |x| (x, y))).collect();

    let frame = blank(side, side, 0);
    for each in [&lower as &dyn Fn(u32, u32) -> u32, &upper] {
        let straight: Vec<u32> = pixels.iter().map(|&(x, y)| each(x, y)).collect();
        let premultiplied_words = premultiplied(&straight);
        let shown = uploaded(side, side, |x, y| premultiplied_words[(y * side + x) as usize]);
        lay(&frame, &shown, (0, 0), u16::MAX, None);
    }

    let stacked = composite_rig();
    let mut pool = Pool::default();
    let sets = vec![
        pool.drawn(|x, y| lower(x as u32, y as u32), (0, 0), (2, 2), |_, _| Some(0)),
        pool.drawn(|x, y| upper(x as u32, y as u32), (0, 0), (2, 2), |_, _| Some(1)),
    ];
    let pages = pool.upload(stacked.engine);
    let steps = [row(0, (0, 0), WHOLE, NORMAL), row(1, (0, 0), WHOLE, NORMAL)];
    let plan = Plan {
        pages: &pages,
        sets: &sets,
        keys: &[],
        matrices: &[],
        chains: &[],
        steps: &steps,
        mask: None,
    };
    let tiles = [(0, 0), (1, 0), (0, 1), (1, 1)];
    let done = stacked
        .composite
        .run(stacked.engine, &plan, &tiles, NO_EDGE, stacked.composite.widest())
        .expect("composite");
    let out = read_buffer(stacked.engine, &done.out);
    let shown: Vec<u32> = pixels
        .iter()
        .map(|&(x, y)| u32::from_le_bytes(pixel_at(&out, &tiles, x as i32, y as i32)))
        .collect();

    let laid = words(&frame);
    let screen = premultiplied(&shown);
    let parted = laid.iter().zip(&screen).filter(|(l, s)| l != s).count();
    assert_eq!(parted, 0, "pixels the export lays otherwise than the plan stacks");
}
