//! The whole camera lens blur on a real GPU — its sums, its iris's table
//! and the gather — checked against what its mean gives by hand and against
//! the ledger, never against a CPU copy of it (`kernels/mod.rs` has why).
//! Most cases blur with a square iris 1.5 out, which covers the 3 × 3
//! pixels about a pixel (its half side 1.06), or 3 out: 5 × 5, its core
//! (2.4 out) 3 × 3.

use std::ffi::OsStr;
use std::path::Path;
use std::sync::OnceLock;

use super::super::iris::{Focus, Iris};
use super::super::pictures::{Blurred, LEDGER_TILES, ONE_TILE, WHITE, pattern, tiles};
use super::super::{GROUP, TileRect};
use super::{BlurMap, Lens, LensBlur, Light, MOST_FRINGE, MapChannel, gather_share, sums_bytes};
use crate::device::Engine;
use crate::kernels::effects::tests::rgba;
use crate::kernels::plugin::{CHUNK_BUDGET, Pace};
use crate::kernels::shared::room;
use crate::testing::{a_device_of_its_own, assert_pinned, first_engine};

struct Rig {
    engine: &'static Engine,
    blur: LensBlur,
}

/// One device and one compiled pass for every test here (blend's tests
/// have why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        Rig {
            engine,
            blur: LensBlur::new(engine),
        }
    })
}

/// A square, standing square — its turns by square roots alone.
fn square() -> Iris {
    let half = 0.5f64.sqrt();
    Iris {
        sides: 4,
        roundness: 0.0,
        aspect: 1.0,
        turn: [1.0, 0.0],
        half_side: [half, half],
        side: [0.0, 1.0],
    }
}

fn lens(radius: f64) -> Lens {
    Lens {
        iris: square(),
        radius,
        fringe: 0.0,
        light: Light::STORED,
        paper: None,
    }
}

/// A blur map for `blurred`: its pixels, the channel read and its focus.
type Map<'a> = (&'a dyn Fn(i32, i32) -> u32, MapChannel, Focus);

/// `rect`'s tiles holding `pixel`, blurred by `lens` over `picture` — at
/// the levels `map` names, where given — or `None` where it refused them.
fn blurred(
    rect: TileRect,
    picture: [i32; 4],
    lens: &Lens,
    pixel: impl Fn(i32, i32) -> u32,
    map: Option<Map>,
) -> Option<Blurred> {
    blurred_in(rect, picture, (lens, map), pixel, (room(rig().engine), quick()))
}

/// `blurred`, its sums in bands a binding of `room` bytes holds and its
/// gather in the chunks `pace` cuts.
fn blurred_in(
    rect: TileRect,
    picture: [i32; 4],
    (lens, map): (&Lens, Option<Map>),
    pixel: impl Fn(i32, i32) -> u32,
    (room, pace): (u64, Pace),
) -> Option<Blurred> {
    let Rig { engine, blur } = rig();
    let map_tiles = map.map(|(pixel, _, _)| tiles(engine, rect, pixel));
    let map = map.zip(map_tiles.as_ref()).map(|((_, channel, focus), tiles)| BlurMap {
        tiles,
        channel,
        focus,
    });
    let tiles = tiles(engine, rect, pixel);
    let out = blur.run_in(engine, &tiles, rect, picture, (lens, map), (room, pace))?;
    Some(Blurred::read(engine, rect, &out))
}

/// A device so quick a band's gather is one chunk.
fn quick() -> Pace {
    Pace::new(0.0, 0.0)
}

/// A device whose pace cuts a gather by `lens` into chunks of `most`
/// workgroups, each invocation at its whole share: half a group more than
/// `most` take the budget, so the cut lands on it.
fn chunking(lens: &Lens, most: u64) -> Pace {
    let share = gather_share(lens.radius.floor() as u32, lens.fringe > 0.0);
    let group = f64::from(GROUP * GROUP);
    Pace::new(0.0, CHUNK_BUDGET.as_secs_f64() / (f64::from(share) * group * (most as f64 + 0.5)))
}

/// `rect`'s whole tiles blurred.
fn whole(lens: &Lens, pixel: impl Fn(i32, i32) -> u32) -> Blurred {
    blurred(ONE_TILE, ONE_TILE.pixels(), lens, pixel, None).expect("blur")
}

/// White at `at` alone, on nothing.
fn one_white(at: (i32, i32)) -> impl Fn(i32, i32) -> u32 {
    move |x, y| if (x, y) == at { WHITE } else { 0 }
}

fn grey(byte: u32) -> u32 {
    rgba(byte, byte, byte, 255)
}

/// White everywhere: a pixel whose iris lies on the picture is white; at
/// its edge the iris covers less of it — 4 of 9 at a corner, 6 on a side —
/// and past it there is nothing, so the mean is that share of white:
/// 29127 and 43690, alphas 113 and 170.
#[test]
fn past_the_picture_there_is_nothing() {
    let blur = whole(&lens(1.5), |_, _| WHITE);
    assert_eq!(blur.at(64, 64), WHITE);
    assert_eq!(blur.at(0, 0), rgba(255, 255, 255, 113));
    assert_eq!(blur.at(127, 127), rgba(255, 255, 255, 113));
    assert_eq!(blur.at(5, 0), rgba(255, 255, 255, 170));
    assert_eq!(blur.at(0, 70), rgba(255, 255, 255, 170));
}

/// One white pixel spreads over the 9 about it: each holds 65535 / 9 →
/// 7282, alpha 28, of white; past them nothing.
#[test]
fn a_pixel_spreads_over_its_iris() {
    let blur = whole(&lens(1.5), one_white((64, 64)));
    let spread = rgba(255, 255, 255, 28);
    assert_eq!(blur.row(63, 62..67), [0, spread, spread, spread, 0]);
    assert_eq!(blur.row(64, 62..67), [0, spread, spread, spread, 0]);
    assert_eq!(blur.row(66, 62..67), [0; 5]);
}

/// The fringe pushes the core's light out to the edge. At 3 out the
/// outline covers 25 and the core 9: at the most fringe the core weighs
/// nothing, so white is white still, and one white pixel shows only on the
/// ring the core does not reach — 65535 / 16 → 4096, alpha 16. At half the
/// fringe the core weighs half: the weight is 25 · 2^16 − 9 · 2^15, and
/// the pixel itself keeps half — 1598, alpha 6 — and the ring 3197, 12.
#[test]
fn the_fringe_pushes_the_core_light_to_the_edge() {
    let at = |fringe: f64| Lens {
        fringe,
        ..lens(3.0)
    };
    let most = at(MOST_FRINGE);
    assert_eq!(whole(&most, |_, _| WHITE).at(64, 64), WHITE);
    let ring = whole(&most, one_white((64, 64)));
    let edge = rgba(255, 255, 255, 16);
    assert_eq!(ring.row(64, 61..68), [0, edge, 0, 0, 0, edge, 0]);
    assert_eq!(ring.at(62, 62), edge);
    let half = whole(&at(MOST_FRINGE / 2.0), one_white((64, 64)));
    let (centre, edge) = (rgba(255, 255, 255, 6), rgba(255, 255, 255, 12));
    assert_eq!(half.row(64, 61..68), [0, edge, centre, centre, centre, edge, 0]);
}

/// Where the outline and the core cover the same pixels there is nowhere
/// to push the light to, so even the most fringe blurs as none: at half a
/// pixel out each covers the pixel alone, every pixel as it was; at 2 out
/// the same 3 × 3 (half sides 1.41 and 1.13), one white pixel spread over
/// it — alpha 28.
#[test]
fn a_fringe_with_nowhere_to_go_keeps_the_light() {
    let opaque = |x, y| pattern(x, y) | 0xff00_0000;
    let blur = whole(&Lens { fringe: MOST_FRINGE, ..lens(0.5) }, opaque);
    for (x, y) in [(0, 0), (17, 40), (64, 64), (127, 3)] {
        assert_eq!(blur.at(x, y), opaque(x, y), "({x}, {y})");
    }
    let spread = rgba(255, 255, 255, 28);
    let blur = whole(&Lens { fringe: MOST_FRINGE, ..lens(2.0) }, one_white((64, 64)));
    assert_eq!(blur.row(64, 62..67), [0, spread, spread, spread, 0]);
}

/// A blur map names each pixel's level: the radius times how far its value
/// lies from the focal distance, over 255. At 382.5 out a level one off the
/// focus is 1.5 out — 3 × 3 — and the focus itself the pixel alone. Each
/// channel names its own byte of the map's pixel, premultiplied (red 200 at
/// half alpha is 100), and its luma Rec. 709's by the app's weights (74 of
/// 40, 80, 120; 16 of 0, 5, 179 — 16.4998 — where weights summing to 2^16
/// made 17).
#[test]
fn a_blur_map_names_each_pixel_level() {
    let spread = rgba(255, 255, 255, 28);
    let cases = [
        (MapChannel::Red, rgba(40, 80, 120, 255), 40.0),
        (MapChannel::Green, rgba(40, 80, 120, 255), 80.0),
        (MapChannel::Blue, rgba(40, 80, 120, 255), 120.0),
        (MapChannel::Alpha, rgba(40, 80, 120, 255), 255.0),
        (MapChannel::Luminance, rgba(40, 80, 120, 255), 74.0),
        (MapChannel::Luminance, rgba(0, 5, 179, 255), 16.0),
        (MapChannel::Red, rgba(200, 0, 0, 128), 100.0),
    ];
    for (channel, word, level) in cases {
        let at = |focal: f64, inverts: bool| {
            let focus = Focus { focal, inverts };
            let map: Map = (&move |_, _| word, channel, focus);
            let picture = ONE_TILE.pixels();
            let white = one_white((64, 64));
            let blur = blurred(ONE_TILE, picture, &lens(382.5), white, Some(map));
            blur.expect("blur").at(65, 64)
        };
        let reason = format!("{channel:?} of {word:#x}");
        assert_eq!(at(level, false), 0, "{reason}");
        assert_eq!(at(level - 1.0, false), spread, "{reason}");
        if level < 255.0 {
            assert_eq!(at(level + 1.0, false), spread, "{reason}");
        }
        assert_eq!(at(255.0 - level, true), 0, "{reason}, inverted");
    }
}

/// Where the map is in focus each pixel is itself, its neighbours blurred
/// by theirs: the white pixel and those left of it in focus, the rest at
/// the most radius.
#[test]
fn a_pixel_in_focus_is_itself() {
    let edge: &dyn Fn(i32, i32) -> u32 = &|x, _| if x <= 64 { 0 } else { WHITE };
    let focus = Focus {
        focal: 0.0,
        inverts: false,
    };
    let map: Map = (edge, MapChannel::Red, focus);
    let blur = blurred(ONE_TILE, ONE_TILE.pixels(), &lens(1.5), one_white((64, 64)), Some(map));
    let spread = rgba(255, 255, 255, 28);
    assert_eq!(blur.expect("blur").row(64, 62..67), [0, 0, WHITE, spread, 0]);
}

/// AE's Repeat Edge Pixels: past the paper its edge pixels are read again —
/// never what lies outside it — and nothing is drawn off it. On black
/// paper a white corner covers 4 of a corner pixel's 9 (113 grey) and 1 of
/// its neighbour's across (28).
#[test]
fn past_the_paper_its_edge_repeats() {
    let paper = [10, 10, 20, 20];
    let pixel = |x: i32, y: i32| match (x, y) {
        (10, 10) | (19, 19) => WHITE,
        _ if (10..20).contains(&x) && (10..20).contains(&y) => grey(0),
        _ => rgba(255, 0, 0, 255),
    };
    let blur = whole(&Lens { paper: Some(paper), ..lens(1.5) }, pixel);
    assert_eq!(blur.at(10, 10), grey(113));
    assert_eq!(blur.at(11, 11), grey(28));
    assert_eq!(blur.at(19, 19), grey(113));
    assert_eq!(blur.at(18, 18), grey(28));
    assert_eq!(blur.at(15, 10), grey(0));
    for (x, y) in [(9, 9), (9, 15), (20, 15), (15, 20), (64, 64)] {
        assert_eq!(blur.at(x, y), 0, "({x}, {y}) off the paper");
    }
}

/// In linear light the mean is of light, not of its stored bytes: one
/// white among 9 black is 7282 of linear light, which sRGB's curve stores
/// as 94 — where as stored it is 28. A pixel alone comes back as itself,
/// every byte.
#[test]
fn in_linear_light_the_mean_is_of_light() {
    let linear = Light {
        linear: true,
        ..Light::STORED
    };
    let on_black = |x, y| if (x, y) == (64, 64) { WHITE } else { grey(0) };
    let blur = whole(&Lens { light: linear, ..lens(1.5) }, on_black);
    assert_eq!(blur.at(65, 65), grey(94));
    assert_eq!(whole(&lens(1.5), on_black).at(65, 65), grey(28));
    // The byte sRGB's curve rounds the light to is stored, as the app's
    // render target rounds it: black among eight grey 38 is 1129 of light,
    // the least that stores as 36 (35.507), and among grey 17 it is 326, one
    // under the least that stores as 16 (15.494) — so 15.
    for (shade, byte) in [(38, 36), (17, 15)] {
        let block = move |x, y| if (x, y) == (64, 64) { grey(0) } else { grey(shade) };
        let blur = whole(&Lens { light: linear, ..lens(1.5) }, block);
        assert_eq!(blur.at(64, 64), grey(byte), "among grey {shade}");
    }
    // A lone grey 42 lends a neighbour 169 (8.496): 8 — where the byte of
    // the nearest light was 9, 169 being 8's and 9's midpoint (159, 179).
    let lone = |x, y| if (x, y) == (64, 64) { grey(42) } else { grey(0) };
    assert_eq!(whole(&Lens { light: linear, ..lens(1.5) }, lone).at(65, 65), grey(8));
    let every = |x: i32, y: i32| {
        let (x, y) = (x as u32, y as u32);
        rgba(x & 255, 255 - (y & 255), (x + y) & 255, 255)
    };
    let alone = whole(&Lens { light: linear, ..lens(0.5) }, every);
    for y in [0, 50, 127] {
        for x in 0..128 {
            assert_eq!(alone.at(x, y), every(x, y), "({x}, {y})");
        }
    }
    // Spread under a byte's alpha it is clear: alpha 1 over 9 is 29 of 65535.
    let faint = one_white((64, 64));
    let faint = move |x, y| faint(x, y) & rgba(255, 255, 255, 1);
    assert_eq!(whole(&Lens { light: linear, ..lens(1.5) }, faint).at(65, 65), 0);
}

/// A row's sums run past 32 bits where boosted light lies along it: 649
/// white pixels at gain 100, 6619035 a channel each, pass 2^32 by the last.
/// 21 past it a square 30 out (43 × 43) covers that last alone, read across
/// the pass — 6619035 / 1849 → 3580, grey 14 — and 20 past it the last two.
#[test]
fn a_row_summed_past_32_bits_reads_whole() {
    let rect = TileRect {
        columns: 8,
        ..ONE_TILE
    };
    let lamp = Light {
        gain: 100.0,
        threshold: 0.0,
        ..Light::STORED
    };
    let row = |x, y| if y == 64 && x < 649 { WHITE } else { grey(0) };
    let blur = blurred(rect, rect.pixels(), &Lens { light: lamp, ..lens(30.0) }, row, None);
    assert_eq!(blur.expect("blur").row(64, 668..671), [grey(28), grey(14), grey(0)]);
}

/// A boosted light spread over what is clear covers it (🗣️I-132-Q20 a): a
/// white lamp at gain 1 is 131070 a channel, a ninth of it 14563 — past the
/// ninth of its alpha, 7282 — so its bokeh is stored at alpha 57, not 28.
/// Past white it is white: at gain 9 the lamp alone is 655350, in either
/// light.
#[test]
fn light_past_its_alpha_covers() {
    let gain = |gain: f64, linear: bool| Light {
        gain,
        threshold: 0.0,
        linear,
        ..Light::STORED
    };
    let blur = whole(&Lens { light: gain(1.0, false), ..lens(1.5) }, one_white((64, 64)));
    assert_eq!(blur.at(65, 64), rgba(255, 255, 255, 57));
    for linear in [false, true] {
        let lamp = Lens { light: gain(9.0, linear), ..lens(0.5) };
        assert_eq!(whole(&lamp, one_white((64, 64))).at(64, 64), WHITE, "linear {linear}");
    }
}

#[test]
fn a_lens_past_its_range_is_refused() {
    let picture = ONE_TILE.pixels();
    let refused = [
        Lens { fringe: -1.0, ..lens(1.5) },
        Lens { fringe: MOST_FRINGE + 0.5, ..lens(1.5) },
        Lens { fringe: f64::NAN, ..lens(1.5) },
        Lens { paper: Some([10, 10, 10, 20]), ..lens(1.5) },
        Lens { paper: Some([10, 20, 20, 10]), ..lens(1.5) },
        Lens { paper: Some([-1, 0, 20, 20]), ..lens(1.5) },
        Lens { paper: Some([0, 0, 129, 20]), ..lens(1.5) },
        Lens { radius: -1.0, ..lens(1.5) },
        Lens { light: Light { gain: -1.0, ..Light::STORED }, ..lens(1.5) },
    ];
    for lens in refused {
        assert!(blurred(ONE_TILE, picture, &lens, |_, _| WHITE, None).is_none(), "{lens:?}");
    }
}

/// A map's tiles short of the blur's rectangle are refused before a word
/// is read.
#[test]
fn a_map_short_of_its_rectangle_is_refused() {
    let Rig { engine, blur } = rig();
    let two = TileRect {
        columns: 2,
        ..ONE_TILE
    };
    let map = BlurMap {
        tiles: &tiles(engine, ONE_TILE, |_, _| WHITE),
        channel: MapChannel::Red,
        focus: Focus {
            focal: 0.0,
            inverts: false,
        },
    };
    let picture = two.pixels();
    let white = tiles(engine, two, |_, _| WHITE);
    assert!(blur.run(engine, &white, two, picture, &lens(1.5), Some(map)).is_none());
}

// ---- The ledger ----

/// A hexagon and a pentagon whose turns are worked out by square roots
/// alone, the same on every machine.
fn turned(sides: u32, roundness: f64, aspect: f64, turn: [f64; 2]) -> Iris {
    let (r3, r5) = (3f64.sqrt() / 2.0, 5f64.sqrt());
    let (half_side, side) = match sides {
        6 => ([r3, 0.5], [0.5, r3]),
        _ => (
            [(1.0 + r5) / 4.0, (10.0 - 2.0 * r5).sqrt() / 4.0],
            [(r5 - 1.0) / 4.0, (10.0 + 2.0 * r5).sqrt() / 4.0],
        ),
    };
    Iris {
        sides,
        roundness,
        aspect,
        turn,
        half_side,
        side,
    }
}

/// A square on the whole tiles; a rounded hexagon, fringed, in boosted
/// linear light on a paper it repeats; a pentagon at each of a blur map's
/// levels, its luma.
fn scenes() -> Vec<([i32; 4], Lens, Option<(MapChannel, Focus)>)> {
    let boosted = Light {
        gain: 2.0,
        threshold: 0.5,
        saturation: 0.6,
        linear: true,
    };
    let hexagon = Lens {
        iris: turned(6, 0.3, 1.6, [0.6, 0.8]),
        radius: 7.25,
        fringe: 250.0,
        light: boosted,
        paper: Some([-90, 20, 240, 190]),
    };
    let pentagon = Lens {
        iris: turned(5, 0.5, 0.4, [-0.8, 0.6]),
        radius: 12.0,
        ..lens(0.0)
    };
    let focus = Focus {
        focal: 100.5,
        inverts: true,
    };
    vec![
        (LEDGER_TILES.pixels(), lens(3.0), None),
        ([-100, 10, 250, 200], hexagon, None),
        ([-128, 3, 129, 256], pentagon, Some((MapChannel::Luminance, focus))),
    ]
}

#[test]
fn every_device_blurs_the_pinned_picture() {
    let bytes: Vec<u8> = scenes()
        .into_iter()
        .flat_map(|(picture, lens, map)| {
            let read: &dyn Fn(i32, i32) -> u32 = &|x, y| pattern(y, x);
            let map = map.map(|(channel, focus)| (read, channel, focus));
            blurred(LEDGER_TILES, picture, &lens, pattern, map).expect("blur").words
        })
        .flat_map(|word| word.to_le_bytes())
        .collect();
    assert_pinned("effects/lens-blur", &bytes);
}

// ---- Bands ----

/// The ledger's pictures blurred in bands, a binding holding a third of
/// their sums — so two bands at least —, are the pictures blurred whole,
/// byte for byte (connection-round-checklist ④): the rows past a band its
/// iris reaches are summed again as the whole sums them, on the picture
/// and on a paper whose edge repeats, at a blur map's levels too.
#[test]
fn a_picture_in_bands_is_blurred_as_it_is_whole() {
    let read: &dyn Fn(i32, i32) -> u32 = &|x, y| pattern(y, x);
    for (picture, lens, map) in scenes() {
        let map = map.map(|(channel, focus)| (read, channel, focus));
        let whole = blurred(LEDGER_TILES, picture, &lens, pattern, map).expect("whole");
        let room = sums_bytes(picture)[0] / 3;
        let banded = blurred_in(LEDGER_TILES, picture, (&lens, map), pattern, (room, quick()));
        assert!(
            banded.expect("bands").words == whole.words,
            "{picture:?}: the bands put the whole's bytes"
        );
    }
}

/// A blur map is bound whole, as the tiles are: a map larger than its
/// blur's tiles goes on a binding that holds it, the sums cut into bands to
/// fit, and is refused on one a byte short of it.
#[test]
fn a_map_past_a_binding_is_refused() {
    let Rig { engine, blur } = rig();
    let picture_tiles = tiles(engine, ONE_TILE, pattern);
    let map_tiles = tiles(engine, LEDGER_TILES, pattern);
    let map = BlurMap {
        tiles: &map_tiles,
        channel: MapChannel::Alpha,
        focus: Focus {
            focal: 100.5,
            inverts: false,
        },
    };
    let bytes = map_tiles.size();
    for (room, kept) in [(bytes, true), (bytes - 1, false)] {
        let lens = (&lens(1.5), Some(map));
        let out = blur.run_in(engine, &picture_tiles, ONE_TILE, ONE_TILE.pixels(), lens, (room, quick()));
        assert_eq!(out.is_some(), kept, "a binding of {room}");
    }
}

/// A binding that holds no band of one row's sums refuses the blur.
#[test]
fn a_picture_no_band_of_one_row_fits_is_refused() {
    let picture = ONE_TILE.pixels();
    assert!(blurred_in(ONE_TILE, picture, (&lens(1.5), None), pattern, (0, quick())).is_none());
}

// ---- Chunks ----

/// The ledger's pictures blurred a chunk of the gather at a time — rows of
/// groups where a chunk holds a row, runs along a row where it does not —
/// are the pictures blurred in one, byte for byte
/// (lens-blur-sends-every-band-in-one-submit): a chunk puts its own
/// groups' pixels, from its first column and row, and no other's.
#[test]
fn a_gather_in_chunks_puts_what_it_puts_in_one() {
    let read: &dyn Fn(i32, i32) -> u32 = &|x, y| pattern(y, x);
    for (picture, lens, map) in scenes() {
        let map = map.map(|(channel, focus)| (read, channel, focus));
        let one = blurred(LEDGER_TILES, picture, &lens, pattern, map).expect("one");
        let across = u64::from(((picture[2] - picture[0]) as u32).div_ceil(GROUP));
        for most in [across * 5, across - 7] {
            let room = room(rig().engine);
            let chunked = blurred_in(LEDGER_TILES, picture, (&lens, map), pattern, (room, chunking(&lens, most)));
            assert!(
                chunked.expect("chunks").words == one.words,
                "{picture:?} in chunks of {most} groups, {across} a row: the chunks put the one's bytes"
            );
        }
    }
}

/// Every submit of a gather holds no more groups than the device finishes
/// within the budget at their whole share — the plug-ins' law
/// (`Pace::chunk`) —, and the chunks put every group of the picture once:
/// counted from what the engine noted of its submits (submits.rs), on a
/// device of the test's own so no other test's are among them. No fringe:
/// what a chunk holds is cut by the same law with one (`gather_share`),
/// and 관제 kept new fringed runs off this machine's GPU during the user's
/// trip (lens-blur-sends-every-band-in-one-submit, 2026-11-22).
#[test]
fn a_gather_goes_in_submits_the_budget_holds() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let blur = LensBlur::new(&engine);
    let lens = lens(3.0);
    let picture = LEDGER_TILES.pixels();
    let pace = chunking(&lens, 500);
    let most = pace.chunk(gather_share(3, false), GROUP * GROUP);
    let tiles = tiles(&engine, LEDGER_TILES, pattern);
    let before = engine.queue.submits.kept_now().last().map_or(0, |submit| submit.number);
    let out = blur.run_in(&engine, &tiles, LEDGER_TILES, picture, (&lens, None), (room(&engine), pace));
    assert!(out.is_some(), "the blur ran");
    let gathers: Vec<u64> = engine
        .queue
        .submits
        .kept_now()
        .iter()
        .filter(|submit| submit.number > before && submit.dispatches == 1)
        .filter(|submit| Path::new(submit.by.file()).file_name() == Some(OsStr::new("lens.rs")))
        .map(|submit| submit.groups)
        .collect();
    let groups = |edge: i32| u64::from((edge as u32).div_ceil(GROUP));
    let all = groups(picture[2] - picture[0]) * groups(picture[3] - picture[1]);
    assert_eq!(most, 500, "⛔전제: the pace cuts chunks of 500");
    assert!(gathers.len() > 1, "a gather of {all} groups in chunks of {most}: {gathers:?}");
    assert!(gathers.iter().all(|&groups| groups <= most), "{gathers:?}");
    assert_eq!(gathers.iter().sum::<u64>(), all, "{gathers:?}");
}

/// 🔬What a row of the iris costs a gather on this device, in its pace's
/// charges ([`super::ROW_CHARGES`]) — run by hand:
/// `cargo test a_row_of_the_iris_charges -- --ignored --nocapture`. A new
/// project's canvas (2340 × 1654, the app's brush_canvas_defaults.dart) at
/// radii 75 and 150, each the quickest of three, its gather in one: what
/// the 150 rows more cost over its pixels, against the pace. ⛔No more
/// radius and no fringe on this machine's GPU during the user's trip
/// (관제 2026-11-22, lens-blur-sends-every-band-in-one-submit: a radius it
/// has drawn).
#[test]
#[ignore = "measures the device: run by hand"]
fn a_row_of_the_iris_charges() {
    let Rig { engine, blur } = rig();
    let pace = Pace::of(engine).expect("the pace");
    let picture = [0, 0, 2340, 1654];
    let tile = crate::kernels::composite::TILE;
    let rect = TileRect {
        x0: 0,
        y0: 0,
        columns: 2340u32.div_ceil(tile),
        rows: 1654u32.div_ceil(tile),
    };
    let tiles = tiles(engine, rect, pattern);
    let took = |radius: f64| {
        let run = || {
            let started = std::time::Instant::now();
            let lens = (&lens(radius), None);
            let out = blur.run_in(engine, &tiles, rect, picture, lens, (room(engine), quick()));
            let out = out.expect("blur");
            crate::testing::done_here(engine).expect("done");
            drop(out);
            started.elapsed().as_secs_f64()
        };
        (0..3).map(|_| run()).fold(f64::MAX, f64::min)
    };
    let (near, far) = (took(75.0), took(150.0));
    let per_row = (far - near) / (2340.0 * 1654.0 * 150.0);
    println!(
        "pace {pace:?} · radius 75 {near:.4} s · 150 {far:.4} s · a row {per_row:e} s a pixel · {:.2} charges",
        per_row / pace.pixel()
    );
}
