//! The waveform pass on a real GPU, checked against the ledger and against
//! what the formula gives by hand — never against a CPU copy of it
//! (`kernels/mod.rs` has why). Each hand case writes its sums out.
//!
//! Most cases draw on 4 pixels a bucket — a frame a second, a bucket a
//! second, 4 pixels a frame (`view`) — so strip pixel e stands at bucket
//! e / 4, and on a lane 8 pixels across: its middle at 4 pixels (1024 in
//! q8), its reach 4 − 1 = 3 pixels (768).

use super::{WavePeaks, WaveTile, WaveView, edge_of};
use crate::device::{Engine, storage_texture};
use crate::testing::{assert_pinned, first_engine};

const RGBA: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8Unorm;
const BGRA: wgpu::TextureFormat = wgpu::TextureFormat::Bgra8Unorm;

const FULL: u16 = 65535;
const WHITE: u32 = 0xffff_ffff;

/// An RGBA word.
fn rgba(r: u32, g: u32, b: u32, a: u32) -> u32 {
    r | g << 8 | b << 16 | a << 24
}

/// 4 pixels a bucket, one lane 8 pixels across, white over clear.
fn view() -> WaveView {
    WaveView {
        along0: 0,
        vertical: false,
        frame_q8: 4 * 256,
        fps: (1, 1),
        buckets_per_second: 1,
        leading_frames: 0,
        across_q8: 8 * 256,
        gain_q16: 65536,
        rgba: WHITE,
        background: 0,
    }
}

/// `lanes` drawn as `view` shows them on a `width` x `height` tile — None
/// where the pass refuses them.
fn drawn(
    engine: &Engine,
    (width, height): (u32, u32),
    format: wgpu::TextureFormat,
    lanes: &[&[u16]],
    view: &WaveView,
) -> Option<Vec<u8>> {
    let peaks = WavePeaks::new(engine, lanes)?;
    let texture = storage_texture(&engine.device, width, height, format);
    WaveTile::new(engine).run(engine, &texture, &peaks, view)?;
    engine.read_texture(&texture)
}

/// One lane on an RGBA tile.
fn lane(engine: &Engine, size: (u32, u32), peaks: &[u16], view: &WaveView) -> Vec<u8> {
    drawn(engine, size, RGBA, &[peaks], view).expect("the pass draws the lane")
}

/// The pixel at (x, y) of a tile `width` across.
fn at(bytes: &[u8], width: u32, x: u32, y: u32) -> [u8; 4] {
    let i = ((y * width + x) * 4) as usize;
    [bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]]
}

/// Column `x`, top to bottom, of a tile `width` x `height`.
fn column(bytes: &[u8], (width, height): (u32, u32), x: u32) -> Vec<[u8; 4]> {
    (0..height).map(|y| at(bytes, width, x, y)).collect()
}

/// White as it lands over clear at `alpha`, stored premultiplied: every
/// channel `alpha`, 255·a / 255. A q8 overlap o of a row gives it the
/// 16-bit alpha (o·65535 + 128) >> 8, stored as the byte (alpha + 128) /
/// 257.
fn white(alpha: u8) -> [u8; 4] {
    [alpha; 4]
}

const NONE: [u8; 4] = [0; 4];
const ALL: [u8; 4] = [255; 4];

// Full scale reaches 3 pixels: (65535·768 + 32768) >> 16 = 768, the band
// [256, 1792] in q8 — rows 1 to 6 whole, rows 0 and 7 untouched, and the
// rows below the strip untouched too.
#[test]
fn a_full_peak_reaches_a_pixel_short_of_its_share() {
    let engine = first_engine();
    let bytes = lane(engine, (8, 12), &[FULL; 4], &view());
    for x in 0..8 {
        let mut expected = vec![NONE, ALL, ALL, ALL, ALL, ALL, ALL, NONE];
        expected.extend([NONE; 4]);
        assert_eq!(column(&bytes, (8, 12), x), expected, "column {x}");
    }
}

// A lane 56 pixels across reaches 28 − 1 = 27 pixels, 6912 in q8 —
// 0x1b00, past 4096 and with its 11th bit set, so `scaled` takes it in its
// two parts: 65535 · (6912 >> 12) = 65535 high, 65535 · 2816 + 32768 =
// 184579328 low, and (65535 >> 4) + ((15 << 12) + 184579328) >> 16 = 4095
// + 2817 = 6912 — the band [256, 14080], rows 1 to 54. Half scale: 32768
// high, 92307456 low, 2048 + 1408 = 3456 — [3712, 10624], rows 14 and 41
// by 128.
#[test]
fn a_wide_lane_reaches_as_far_as_a_narrow_one_does_for_its_share() {
    let engine = first_engine();
    let view = WaveView {
        across_q8: 56 * 256,
        ..view()
    };
    let full = lane(engine, (2, 56), &[FULL; 4], &view);
    let rows: Vec<[u8; 4]> = (0..56).map(|y| at(&full, 2, 1, y)).collect();
    let expected: Vec<[u8; 4]> = (0..56)
        .map(|y| if (1..55).contains(&y) { ALL } else { NONE })
        .collect();
    assert_eq!(rows, expected);
    let half = lane(engine, (2, 56), &[32768; 4], &view);
    let rows: Vec<[u8; 4]> = (0..56).map(|y| at(&half, 2, 1, y)).collect();
    let expected: Vec<[u8; 4]> = (0..56)
        .map(|y| match y {
            14 | 41 => white(128),
            15..41 => ALL,
            _ => NONE,
        })
        .collect();
    assert_eq!(rows, expected);
}

// Half scale: (32768·768 + 32768) >> 16 = 384, the band [640, 1408]: row 2
// [512, 768] overlaps it by 128 → (128·65535 + 128) >> 8 = 32768, a byte of
// (32768 + 128) / 257 = 128; row 5 the same, rows 3 and 4 whole.
#[test]
fn a_row_is_covered_by_how_much_of_it_the_band_overlaps() {
    let engine = first_engine();
    let bytes = lane(engine, (8, 8), &[32768; 4], &view());
    let expected = [NONE, NONE, white(128), ALL, ALL, white(128), NONE, NONE];
    assert_eq!(column(&bytes, (8, 8), 3), expected);
}

// On a lane 9 pixels across the middle is row 4's own middle, 1152. Silence
// reaches nothing, and nothing overlaps a band of none — no line through
// the middle.
#[test]
fn silence_draws_nothing() {
    let engine = first_engine();
    let view = WaveView {
        across_q8: 9 * 256,
        ..view()
    };
    assert!(lane(engine, (8, 9), &[0; 4], &view).iter().all(|&byte| byte == 0));
}

// Peaks 0, full, 0, 0: the line rises over the first four pixels and falls
// over the next four. Column 0 runs from bucket 0 to 0.25 (q16 16384): its
// most is the right end, (65535·16384 + 32768) >> 16 = 16384, reaching
// (16384·768 + 32768) >> 16 = 192 — rows 3 and 4 overlap the band [832,
// 1216] by 192 → 49151, a byte of 191. Column 1, to 0.5: 32768, reaching
// 384, as half scale does. Column 3 reaches bucket 1 itself: full. Column
// 5, from 1.25: (65535·49152 + 32768) >> 16 = 49151, reaching 576 —
// [448, 1600], so rows 1 and 6 by 64 → 16384, a byte of 64.
#[test]
fn a_column_shows_the_most_of_the_line_through_the_peaks_over_it() {
    let engine = first_engine();
    let bytes = lane(engine, (8, 8), &[0, FULL, 0, 0], &view());
    let quarter = [NONE, NONE, NONE, white(191), white(191), NONE, NONE, NONE];
    assert_eq!(column(&bytes, (8, 8), 0), quarter);
    let half = [NONE, NONE, white(128), ALL, ALL, white(128), NONE, NONE];
    assert_eq!(column(&bytes, (8, 8), 1), half);
    assert_eq!(column(&bytes, (8, 8), 3), [NONE, ALL, ALL, ALL, ALL, ALL, ALL, NONE]);
    assert_eq!(column(&bytes, (8, 8), 4), [NONE, ALL, ALL, ALL, ALL, ALL, ALL, NONE]);
    let falling = [NONE, white(64), ALL, ALL, ALL, ALL, white(64), NONE];
    assert_eq!(column(&bytes, (8, 8), 5), falling);
}

// Four buckets are a line from pixel 0 to pixel 12: column 11 ends on the
// last bucket, column 12 stands past it and shows nothing.
#[test]
fn the_line_ends_at_the_last_bucket() {
    let engine = first_engine();
    let bytes = lane(engine, (16, 8), &[FULL; 4], &view());
    assert_eq!(column(&bytes, (16, 8), 11), [NONE, ALL, ALL, ALL, ALL, ALL, ALL, NONE]);
    for x in 12..16 {
        assert!(column(&bytes, (16, 8), x).iter().all(|&pixel| pixel == NONE), "{x}");
    }
}

// A frame of trim moves the line 4 pixels left — column 1 shows what
// column 5 did; a frame before the file moves it 4 right, and the strip
// before the file shows nothing.
#[test]
fn the_trim_moves_the_line_along_the_strip() {
    let engine = first_engine();
    let peaks = [0, FULL, 0, 0];
    let trimmed = lane(engine, (8, 8), &peaks, &WaveView { leading_frames: 1, ..view() });
    let falling = [NONE, white(64), ALL, ALL, ALL, ALL, white(64), NONE];
    assert_eq!(column(&trimmed, (8, 8), 1), falling);
    let early = lane(engine, (8, 8), &peaks, &WaveView { leading_frames: -1, ..view() });
    for x in 0..4 {
        assert!(column(&early, (8, 8), x).iter().all(|&pixel| pixel == NONE), "{x}");
    }
    let quarter = [NONE, NONE, NONE, white(191), white(191), NONE, NONE, NONE];
    assert_eq!(column(&early, (8, 8), 4), quarter);
}

// A tile further along the strip is the same columns: its column 0 is the
// strip's column 5.
#[test]
fn a_tile_along_the_strip_shows_the_strip_where_it_stands() {
    let engine = first_engine();
    let view = WaveView { along0: 5, ..view() };
    let bytes = lane(engine, (4, 8), &[0, FULL, 0, 0], &view);
    let falling = [NONE, white(64), ALL, ALL, ALL, ALL, white(64), NONE];
    assert_eq!(column(&bytes, (4, 8), 0), falling);
}

#[test]
fn one_bucket_is_no_line() {
    let engine = first_engine();
    assert!(lane(engine, (8, 8), &[FULL], &view()).iter().all(|&byte| byte == 0));
}

// A hundred buckets a pixel: column 1 runs from bucket 100 to 200 and its
// most of buckets 101 to 200 is read as two blocks of 64 — [101, 165) and
// [137, 201) —, column 2's of 201 to 300 as [201, 265) and [237, 301). A
// peak only the first block holds (105), one only the second does (290),
// and one on the edge two columns share (400) are each found.
#[test]
fn a_column_over_many_buckets_finds_the_most_of_them() {
    let engine = first_engine();
    let view = WaveView {
        frame_q8: 256,
        buckets_per_second: 100,
        ..view()
    };
    let mut peaks = [0u16; 501];
    peaks[105] = FULL;
    peaks[290] = 32768;
    peaks[400] = FULL;
    let bytes = lane(engine, (6, 8), &peaks, &view);
    let full = [NONE, ALL, ALL, ALL, ALL, ALL, ALL, NONE];
    let half = [NONE, NONE, white(128), ALL, ALL, white(128), NONE, NONE];
    assert!(column(&bytes, (6, 8), 0).iter().all(|&pixel| pixel == NONE));
    assert_eq!(column(&bytes, (6, 8), 1), full);
    assert_eq!(column(&bytes, (6, 8), 2), half);
    assert_eq!(column(&bytes, (6, 8), 3), full, "the edge at bucket 400");
    assert_eq!(column(&bytes, (6, 8), 4), full, "the edge at bucket 400");
    assert!(column(&bytes, (6, 8), 5).iter().all(|&pixel| pixel == NONE));
}

// Two lanes on 16 pixels: each a share of 8, middles 1024 and 3072, each
// reaching 768 at full scale. Full on top, half below: [2688, 3456] — rows
// 10 and 13 by 128.
#[test]
fn each_lane_has_its_own_share_across() {
    let engine = first_engine();
    let view = WaveView {
        across_q8: 16 * 256,
        ..view()
    };
    let bytes = drawn(engine, (4, 16), RGBA, &[&[FULL; 4], &[32768; 4]], &view).unwrap();
    let expected = [
        NONE, ALL, ALL, ALL, ALL, ALL, ALL, NONE,
        NONE, NONE, white(128), ALL, ALL, white(128), NONE, NONE,
    ];
    assert_eq!(column(&bytes, (4, 16), 2), expected);
}

// Half the gain is half the reach: (768·32768 + 32768) >> 16 = 384, so full
// scale draws as half scale does; a gain past 1 is held to 1.
#[test]
fn the_gain_is_drawn_into_the_band_and_held_to_one() {
    let engine = first_engine();
    let half = WaveView {
        gain_q16: 32768,
        ..view()
    };
    let bytes = lane(engine, (8, 8), &[FULL; 4], &half);
    let expected = [NONE, NONE, white(128), ALL, ALL, white(128), NONE, NONE];
    assert_eq!(column(&bytes, (8, 8), 3), expected);
    let loud = WaveView {
        gain_q16: 98304,
        ..view()
    };
    assert_eq!(
        lane(engine, (8, 8), &[FULL; 4], &loud),
        lane(engine, (8, 8), &[FULL; 4], &view()),
    );
}

// Running down, the strip is the tile turned: x across, y along.
#[test]
fn a_strip_running_down_is_the_same_band_turned() {
    let engine = first_engine();
    let peaks = [0, FULL, 0, 0, 32768, 0];
    let across = lane(engine, (12, 8), &peaks, &view());
    let down = lane(engine, (8, 12), &peaks, &WaveView { vertical: true, ..view() });
    for x in 0..12 {
        for y in 0..8 {
            assert_eq!(at(&across, 12, x, y), at(&down, 8, y, x), "({x}, {y})");
        }
    }
}

// The band is laid over the background word by the normal composite: half
// white over opaque black is opaque grey, 128·257 + 0 over 32896 of
// weight — (65535·32896 + 32767) / 65535 → 32896, a byte of 128.
#[test]
fn the_band_is_laid_over_the_background() {
    let engine = first_engine();
    let view = WaveView {
        rgba: rgba(255, 255, 255, 128),
        background: rgba(0, 0, 0, 255),
        ..view()
    };
    let bytes = lane(engine, (1, 8), &[FULL; 4], &view);
    assert_eq!(at(&bytes, 1, 0, 0), [0, 0, 0, 255]);
    assert_eq!(at(&bytes, 1, 0, 3), [128, 128, 128, 255]);
}

// 16 pixels a frame at 24000/1001 frames a second, 80 buckets a second:
// pixel 100 stands at 25600·80·1001 / (4096·24000) = 2050048000 /
// 98304000 = 20 and 83968000 over, (83968000 << 16) / 98304000 = 55978.
#[test]
fn an_edge_stands_where_the_frame_rate_puts_it_exactly() {
    let view = WaveView {
        frame_q8: 16 * 256,
        fps: (24000, 1001),
        buckets_per_second: 80,
        ..view()
    };
    assert_eq!(edge_of(&view, 1000, 100), [20, 55978]);
    assert_eq!(edge_of(&view, 1000, 0), [0, 0]);
    assert_eq!(edge_of(&view, 21, 100), [20, 0], "held to the last bucket");
    let early = WaveView {
        leading_frames: -1,
        ..view
    };
    assert_eq!(edge_of(&early, 1000, 15), [0, 0], "held to the first");
}

#[test]
fn a_sound_or_a_view_the_pass_cannot_draw_is_refused() {
    let engine = first_engine();
    let peaks: &[u16] = &[FULL; 4];
    let refused = |lanes: &[&[u16]], view: WaveView| {
        drawn(engine, (4, 4), RGBA, lanes, &view).is_none()
    };
    assert!(refused(&[], view()), "no lane");
    assert!(refused(&[&[]], view()), "an empty lane");
    assert!(refused(&[peaks, &[FULL; 3]], view()), "lanes of two lengths");
    assert!(refused(&[peaks; 65], view()), "65 lanes");
    assert!(!refused(&[peaks; 64], WaveView { across_q8: 64 * 512, ..view() }));
    let views = [
        WaveView { frame_q8: 0, ..view() },
        WaveView { fps: (0, 1), ..view() },
        WaveView { fps: (1, 0), ..view() },
        WaveView { buckets_per_second: 0, ..view() },
        WaveView { across_q8: 0, ..view() },
        WaveView { across_q8: 1 << 24, ..view() },
        WaveView { gain_q16: -1, ..view() },
    ];
    for view in views {
        assert!(refused(&[peaks], view), "{view:?}");
    }
    assert!(!refused(&[peaks], WaveView { across_q8: (1 << 24) - 1, ..view() }));
    assert!(!refused(&[peaks], WaveView { gain_q16: 0, ..view() }));
}

/// Two lanes of a sound's peaks at 23.976 frames a second with a trim, a
/// gain below 1 and a translucent colour over a grey row, on a 160 x 24
/// strip — or 24 x 160, running down.
fn mixed(engine: &Engine, format: wgpu::TextureFormat, vertical: bool) -> Vec<u8> {
    let left: Vec<u16> = (0..400u32).map(|i| ((i * 7919 + 13) % 65536) as u16).collect();
    let right: Vec<u16> = (0..400u32).map(|i| ((i * i * 31 + 5) % 65536) as u16).collect();
    let view = WaveView {
        along0: 37,
        vertical,
        frame_q8: 1536 + 77,
        fps: (24000, 1001),
        buckets_per_second: 80,
        leading_frames: 3,
        across_q8: 24 * 256 - 40,
        gain_q16: 52429,
        rgba: rgba(100, 180, 255, 200),
        background: rgba(30, 30, 34, 255),
    };
    let size = if vertical { (24, 160) } else { (160, 24) };
    drawn(engine, size, format, &[&left, &right], &view).unwrap()
}

#[test]
fn every_device_writes_the_pinned_bytes() {
    let engine = first_engine();
    assert_pinned("timeline/wave-160x24-mixed-rgba", &mixed(engine, RGBA, false));
    assert_pinned("timeline/wave-24x160-mixed-rgba", &mixed(engine, RGBA, true));
}

// The format moves where each channel sits, not what is stored.
#[test]
fn the_two_orders_differ_only_by_red_and_blue() {
    let engine = first_engine();
    let storable = engine
        .device
        .features()
        .contains(wgpu::Features::BGRA8UNORM_STORAGE);
    assert!(storable, "this adapter cannot store to bgra8unorm");
    let swapped: Vec<u8> = mixed(engine, BGRA, false)
        .chunks_exact(4)
        .flat_map(|texel| [texel[2], texel[1], texel[0], texel[3]])
        .collect();
    assert_eq!(swapped, mixed(engine, RGBA, false));
}
