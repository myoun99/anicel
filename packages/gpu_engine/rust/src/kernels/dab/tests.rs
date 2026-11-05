//! The dab kernel on a real GPU, checked against the ledger and against
//! what the formula gives by hand — never against a CPU copy of it
//! (`kernels/mod.rs` has why).

use super::{Dab, Dabs, Edge, Paper, RoundProfile, Shape, StrokeTile, Texture, Turn};
use crate::kernels::composite::TILE_TEXELS;
use crate::testing::{assert_pinned, first_engine, read_buffer};

const ONE: u32 = 65535;
const RED: [u8; 4] = [200, 100, 50, 255];

/// What a stroke's tiles hold after a pile: each pixel's plane as four
/// channels, and its byte word.
struct Piled {
    planes: Vec<[u32; 4]>,
    view: Vec<u32>,
}

impl Piled {
    /// Pixel (x, y) of the tile in slot `slot`.
    fn at(&self, slot: usize, x: usize, y: usize) -> ([u32; 4], u32) {
        let texel = slot * TILE_TEXELS as usize + y * 128 + x;
        (self.planes[texel], self.view[texel])
    }
}

/// `dabs` piled by `kernel` over `paper` on `tiles` (slots in their order)
/// whose planes start as `under`, every pixel of every tile — or nothing,
/// where the kernel refuses them.
fn laid(
    kernel: &mut Dabs,
    tiles: &[(i32, i32)],
    under: [u32; 4],
    paper: Option<&Paper>,
    dabs: &[Dab],
) -> Option<Piled> {
    let engine = first_engine();
    let texels = tiles.len() * TILE_TEXELS as usize;
    let words: Vec<u8> = (0..texels)
        .flat_map(|_| [under[0] | under[1] << 16, under[2] | under[3] << 16])
        .flat_map(u32::to_le_bytes)
        .collect();
    let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
    let planes = wgpu::util::DeviceExt::create_buffer_init(
        &engine.device,
        &wgpu::util::BufferInitDescriptor {
            label: Some("test planes"),
            contents: &words,
            usage,
        },
    );
    let view = engine.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("test view"),
        size: texels as u64 * 4,
        usage,
        mapped_at_creation: false,
    });
    let stroke: Vec<StrokeTile> = tiles
        .iter()
        .enumerate()
        .map(|(slot, &(column, row))| StrokeTile { column, row, slot: slot as u32 })
        .collect();
    kernel.pile(engine, &stroke, dabs, paper, &planes, &view)?;
    let words = |buffer: &wgpu::Buffer| -> Vec<u32> {
        read_buffer(engine, buffer)
            .chunks_exact(4)
            .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
            .collect()
    };
    let planes = words(&planes)
        .chunks_exact(2)
        .map(|pair| [pair[0] & 0xffff, pair[0] >> 16, pair[1] & 0xffff, pair[1] >> 16])
        .collect();
    Some(Piled { planes, view: words(&view) })
}

fn tried(tiles: &[(i32, i32)], under: [u32; 4], dabs: &[Dab]) -> Option<Piled> {
    laid(&mut Dabs::new(first_engine()), tiles, under, None, dabs)
}

fn piled(tiles: &[(i32, i32)], under: [u32; 4], dabs: &[Dab]) -> Piled {
    tried(tiles, under, dabs).expect("pile")
}

/// A square dab of `colour` over `region` at full opacity and `flow`.
fn square(region: [i32; 4], colour: [u8; 4], flow: f64) -> Dab<'static> {
    Dab {
        centre: [0.0, 0.0],
        region,
        colour,
        opacity: 1.0,
        flow,
        edge: Edge::Contrast(1.0),
        edge_held: false,
        erase: false,
        shape: Shape::Square,
        turn: Turn::STRAIGHT,
        evening: None,
        density: 1.0,
    }
}

fn word([red, green, blue, alpha]: [u32; 4]) -> u32 {
    red | green << 8 | blue << 16 | alpha << 24
}

/// `colour`'s channels on the 16-bit scale, under `alpha`.
fn widened(colour: [u8; 4], alpha: u32) -> [u32; 4] {
    [u32::from(colour[0]) * 257, u32::from(colour[1]) * 257, u32::from(colour[2]) * 257, alpha]
}

// The first dab over nothing lands its own bytes — the colour's alpha
// 128 as 128·257, its byte 128 again — and nothing past its region.
#[test]
fn a_first_dab_over_nothing_lands_its_own_bytes() {
    let half = [200, 100, 50, 128];
    let piled = piled(&[(0, 0)], [0; 4], &[square([3, 5, 20, 9], half, 1.0)]);
    assert_eq!(piled.at(0, 3, 5), (widened(half, 128 * 257), word([200, 100, 50, 128])));
    assert_eq!(piled.at(0, 19, 8), (widened(half, 128 * 257), word([200, 100, 50, 128])));
    for (x, y) in [(2, 5), (20, 5), (3, 4), (3, 9)] {
        assert_eq!(piled.at(0, x, y), ([0; 4], 0), "({x}, {y})");
    }
}

// Over its own colour a dab moves only the alpha: flow ½ is 32768, and
// the second lays 32768 + round(32768·32767/65535) = 49152, a byte of
// round(49152/257) = 191. The colour stays 200·257 exactly.
#[test]
fn a_dab_over_its_own_colour_keeps_the_colour_exactly() {
    let dab = || square([0, 0, 4, 4], RED, 0.5);
    let piled = piled(&[(0, 0)], [0; 4], &[dab(), dab()]);
    assert_eq!(piled.at(0, 1, 1), (widened(RED, 49152), word([200, 100, 50, 191])));
}

// 🚨A dab's opacity is the level it settles at: at ½ the first dab over
// nothing lays round(65535·div(32768, 65535)) = 32768 and every one after
// finds the stroke there and lays nothing. Under the level, a lighter flow
// creeps up to it and never past.
#[test]
fn a_light_press_settles_at_its_opacity() {
    let at = |flow| Dab { opacity: 0.5, ..square([0, 0, 2, 2], RED, flow) };
    let full: Vec<Dab> = (0..5).map(|_| at(1.0)).collect();
    let settled = (widened(RED, 32768), word([200, 100, 50, 128]));
    assert_eq!(piled(&[(0, 0)], [0; 4], &full).at(0, 0, 0), settled);
    let light: Vec<Dab> = (0..40).map(|_| at(0.25)).collect();
    let (plane, _) = piled(&[(0, 0)], [0; 4], &light).at(0, 1, 1);
    assert!(plane[3] > 32000 && plane[3] <= 32768, "{}", plane[3]);
}

// An erase takes its alpha off and keeps the colour: flow ½ leaves
// round(65535·32767/65535) = 32767 of an opaque pixel, a byte of 127;
// flow 1 leaves nothing, the colour with it. An eraser does not settle:
// at opacity ½ it takes as much as at flow ½, from an opaque pixel too.
#[test]
fn an_erase_takes_its_alpha_and_keeps_the_colour() {
    let opaque = widened(RED, ONE);
    let erase = |flow| Dab { erase: true, ..square([0, 0, 2, 2], [0, 0, 0, 255], flow) };
    let half = (widened(RED, 32767), word([200, 100, 50, 127]));
    assert_eq!(piled(&[(0, 0)], opaque, &[erase(0.5)]).at(0, 0, 0), half);
    assert_eq!(piled(&[(0, 0)], opaque, &[erase(1.0)]).at(0, 1, 1), ([0; 4], 0));
    let light = Dab { opacity: 0.5, ..erase(1.0) };
    assert_eq!(piled(&[(0, 0)], opaque, &[light]).at(0, 0, 0), half);
}

/// A round profile of `reach` 4 px, 16 entries a pixel: 1 to a distance
/// of 1, falling straight to 0 at 4 — entry 17, at 1.0625 px, is
/// 0.979…, entry 32, at 2 px, ⅔ and entry 40, at 2.5, ½. Its pile is 1
/// throughout.
fn ramp() -> (Vec<f64>, Vec<f64>) {
    let coverage = (0..66)
        .map(|entry| (4.0 - f64::from(entry) / 16.0).clamp(0.0, 3.0) / 3.0)
        .collect();
    (coverage, vec![1.0; 66])
}

/// A profile along the radius, 16 entries a pixel.
fn radial<'a>(coverage: &'a [f64], pile: &'a [f64], reach: f64, inner: f64) -> RoundProfile<'a> {
    RoundProfile { coverage, pile, scale: 16.0, reach, inner, row_length: 0 }
}

/// A round dab at `centre` over its radius's box, as the app gives it
/// (`dirtyRegionForBrushDab`) — the radius half a pixel inside the reach.
fn round<'a>(profile: &'a RoundProfile<'a>, centre: [f64; 2]) -> Dab<'a> {
    let radius = profile.reach - 0.5;
    let [cx, cy] = centre;
    Dab {
        centre,
        region: [
            (cx - radius).floor() as i32,
            (cy - radius).floor() as i32,
            (cx + radius).ceil() as i32,
            (cy + radius).ceil() as i32,
        ],
        shape: Shape::Round(profile),
        ..square([0; 4], RED, 1.0)
    }
}

// Centred on pixel (10, 10)'s centre: the pixel itself is within the inner
// radius and lays 1; the one 2 px right reads entry 32 exactly — ⅔ is
// 43690 —; the one 4 px right is past its region and is not touched. Under
// 없음 the ⅔ is cut to 1; under a contrast of 2 it is
// (43690 − 32768)·2 + 32768 = 54612. Centred on (10, 10.5), pixel 12 is
// 2.5 px off and reads ½, 32768 — which 없음 cuts to 1: half is kept.
#[test]
fn a_round_tip_reads_its_profile_along_the_radius() {
    let (coverage, pile) = ramp();
    let profile = radial(&coverage, &pile, 4.0, 1.0);
    let alpha = |edge, centre, x| {
        let dab = Dab { edge, ..round(&profile, centre) };
        piled(&[(0, 0)], [0; 4], &[dab]).at(0, x, 10).0[3]
    };
    assert_eq!(alpha(Edge::Contrast(1.0), [10.5, 10.5], 10), ONE);
    assert_eq!(alpha(Edge::Contrast(1.0), [10.5, 10.5], 12), 43690);
    assert_eq!(alpha(Edge::Contrast(1.0), [10.5, 10.5], 14), 0);
    assert_eq!(alpha(Edge::Threshold, [10.5, 10.5], 12), ONE);
    assert_eq!(alpha(Edge::Contrast(2.0), [10.5, 10.5], 12), 54612);
    assert_eq!(alpha(Edge::Contrast(1.0), [10.0, 10.5], 12), 32768);
    assert_eq!(alpha(Edge::Threshold, [10.0, 10.5], 12), ONE);
}

// At or within the inner radius a pixel lays 1 though the table between
// its entries would read less: inner 1.03 is 263/256 px. Pixel 11 from a
// centre of 2681/256 is 263/256 off and lays 1; from 2680/256 it is
// 264/256 off, 16.5 entries, and reads 65535 + ⌊(−1365·16384 + 16384)/32768⌋
// = 64853 — entry 17 is round(0.979…·65535) = 64170.
#[test]
fn within_the_inner_radius_a_round_tip_lays_one() {
    let (coverage, pile) = ramp();
    let profile = radial(&coverage, &pile, 4.0, 1.03);
    let alpha = |cx| piled(&[(0, 0)], [0; 4], &[round(&profile, [cx, 10.5])]).at(0, 11, 10).0[3];
    assert_eq!(alpha(2681.0 / 256.0), ONE);
    assert_eq!(alpha(2680.0 / 256.0), 64853);
}

// However far a round dab's region runs, nothing past its reach is laid:
// pixel 266 is 65536/256 px from a centre of 10.5, right or down, whose
// square would overflow u32 to nothing; pixel 522 is 131072/256 px, whose
// turn, times 2^15, would wrap i32 back to the centre.
#[test]
fn a_round_dab_lays_nothing_past_its_reach_however_far_its_region_runs() {
    let (coverage, pile) = ramp();
    let profile = radial(&coverage, &pile, 4.0, 1.0);
    let dab = Dab { region: [-1000, -1000, 1000, 1000], ..round(&profile, [10.5, 10.5]) };
    let piled = piled(&[(0, 0), (2, 0), (0, 2), (4, 0), (0, 4)], [0; 4], &[dab]);
    assert_eq!(piled.at(0, 10, 10).0[3], ONE);
    for slot in 1..5 {
        assert_eq!(piled.at(slot, 10, 10), ([0; 4], 0));
    }
}

// A tip whose distances would read more than four entries a unit is
// refused, not read wrong: a reach of 20000 px takes its distances in
// whole pixels, sixteen entries each.
#[test]
fn a_tip_too_fine_for_its_distances_is_refused() {
    let table = [1.0; 4];
    let profile = radial(&table, &table, 20000.0, -1.0);
    assert!(tried(&[(0, 0)], [0; 4], &[round(&profile, [10.5, 10.5])]).is_none());
}

// 🚨The edge does not pile: where the tip holds an edge and the pile reads
// over the coverage, the ceiling is cover/pile — 43690 at 2 px — and the
// stroke settles there; a second dab adds nothing. Not held, the second
// piles 43690 + round(43690·21845/65535) = 58253.
#[test]
fn an_edge_the_tip_holds_does_not_pile() {
    let (coverage, pile) = ramp();
    let profile = radial(&coverage, &pile, 4.0, 1.0);
    let twice = |edge_held| {
        let dab = || Dab { edge_held, ..round(&profile, [10.5, 10.5]) };
        piled(&[(0, 0)], [0; 4], &[dab(), dab()]).at(0, 12, 10).0[3]
    };
    assert_eq!(twice(true), 43690);
    assert_eq!(twice(false), 58253);
}

// A share table is read between its entries: a table of ¼ throughout lays
// round(¼·65535) = 16384 whatever the dab would lay whole. A table of
// (entry/1024)² reads its last entry, 1 exactly, at a whole of 1, and at
// flow ½ — 32768, entry 512 and 512/65535 of the way on, ⌊512·32768/65535⌋
// = 256 — 16384 + ⌊(64·256 + 16384)/32768⌋ = 16385.
#[test]
fn a_dab_lays_its_share_through_its_table() {
    let quarter = vec![0.25; 1026];
    let squares: Vec<f64> = (0..1026)
        .map(|entry| (f64::from(entry.min(1024)) / 1024.0).powi(2))
        .collect();
    let through = |table: &[f64], flow| {
        let dab = Dab { evening: Some(table), ..square([0, 0, 1, 1], RED, flow) };
        piled(&[(0, 0)], [0; 4], &[dab]).at(0, 0, 0).0[3]
    };
    assert_eq!(through(&quarter, 1.0), 16384);
    assert_eq!(through(&squares, 1.0), ONE);
    assert_eq!(through(&squares, 0.5), 16385);
}

/// A table of 1 − (column + row)/24, 26 entries a row.
fn falling(count: u32) -> Vec<f64> {
    (0..count * count)
        .map(|entry| (1.0 - f64::from(entry % count + entry / count) / 24.0).max(0.0))
        .collect()
}

// A small circle is read by its square tables at (|dx|, |dy|), along the
// row and then down. Under a centre at (10.27, 10.5), pixel 10's centre
// is round(10.27·256) = 2629 off by 59/256 px, 59/16 entries — between
// entry 3 (57343) and 4 (54613) by 22528/32768 — on row 0:
// 57343 + ⌊(−2730·22528 + 16384)/32768⌋ = 55466. Pixel (10, 11) is a
// pixel down, row 16: 1 − 19/24 is 13653, and 1 − 20/24 is a hair under ⅙
// in doubles, 10922, so 13653 + ⌊(−2731·22528 + 16384)/32768⌋ = 11775.
#[test]
fn a_small_circle_is_read_by_its_square_tables() {
    let count = 26;
    let table = falling(count);
    let pile = vec![1.0; table.len()];
    let profile = RoundProfile {
        coverage: &table,
        pile: &pile,
        scale: 16.0,
        reach: 1.5,
        inner: -1.0,
        row_length: count,
    };
    let piled = piled(&[(0, 0)], [0; 4], &[round(&profile, [10.27, 10.5])]);
    assert_eq!(piled.at(0, 10, 10).0[3], 55466);
    assert_eq!(piled.at(0, 10, 11).0[3], 11775);
    assert_eq!(piled.at(0, 12, 10).0[3], 0);
}

/// A bitmap tip of `radius` over `texels`, `side` a side, turned by `turn`,
/// at `centre`, over the box the app gives it (`dirtyRegionForBrushDab`):
/// the turned rectangle's half extents.
fn tipped<'a>(texture: &'a Texture, radius: f64, turn: Turn, centre: [f64; 2]) -> Dab<'a> {
    let minor = radius * turn.roundness;
    let half = [
        radius * turn.cos.abs() + minor * turn.sin.abs(),
        radius * turn.sin.abs() + minor * turn.cos.abs(),
    ];
    let [cx, cy] = centre;
    Dab {
        centre,
        region: [
            (cx - half[0]).floor() as i32,
            (cy - half[1]).floor() as i32,
            (cx + half[0]).ceil() as i32,
            (cy + half[1]).ceil() as i32,
        ],
        shape: Shape::Tip { texture, radius },
        turn,
        ..square([0; 4], RED, 1.0)
    }
}

/// A 2 × 2 tip, row after row: 255, 128 over 64, 0.
const CORNERS: [f64; 4] = [1.0, 128.0 / 255.0, 64.0 / 255.0, 0.0];

fn texture(texels: &[f64], side: u32) -> Texture {
    Texture::new(texels, side).expect("texture")
}

/// The alphas a dab of [`CORNERS`] leaves on pixels (9, 9), (10, 9),
/// (9, 10) and (10, 10).
fn corners(turn: Turn, centre: [f64; 2]) -> [u32; 4] {
    let tip = texture(&CORNERS, 2);
    let piled = piled(&[(0, 0)], [0; 4], &[tipped(&tip, 1.0, turn, centre)]);
    [(9, 9), (10, 9), (9, 10), (10, 10)].map(|(x, y)| piled.at(0, x, y).0[3])
}

// A tip two texels a side over a 2 px dab centred on a pixel corner: each
// pixel's centre is a texel's centre, t = 2(u + R)·side − 2R lands on whole
// texels, and the pixels take the texels as they are — 255·257, 128·257,
// 64·257 and nothing.
#[test]
fn a_bitmap_tip_lays_its_texels_on_the_pixels_they_fall_on() {
    assert_eq!(corners(Turn::STRAIGHT, [10.0, 10.0]), [ONE, 32896, 16448, 0]);
}

// An eighth of a pixel right, pixel 9's centre is 7/8 of the way from
// texel −1 (nothing) to texel 0: ⌊(65535·28672 + 16384)/32768⌋ = 57343;
// pixel 10's, 7/8 from 255·257 to 128·257:
// 65535 + ⌊(−32639·28672 + 16384)/32768⌋ = 36976.
#[test]
fn a_bitmap_tip_is_read_between_its_texels() {
    let alphas = corners(Turn::STRAIGHT, [10.125, 10.0]);
    assert_eq!(alphas[..2], [57343, 36976]);
}

// Half a pixel left, pixel 9 is halfway between texels 0 and 1 —
// 65535 + ⌊(−32639·16384 + 16384)/32768⌋ = 49216 — and pixel 10's centre
// is the tip's very edge, u = R: it is kept, as the C engine keeps it, and
// lays half its last texel, 16448. Past the edge nothing is laid, though
// the read would still give some of the last texel: from a centre of
// 10.25, pixel 11's is 1¼ px out, a quarter of 128·257 by the read.
#[test]
fn a_bitmap_tip_lays_up_to_its_very_edge() {
    let alphas = corners(Turn::STRAIGHT, [9.5, 10.0]);
    assert_eq!(alphas[..2], [49216, 16448]);
    let tip = texture(&CORNERS, 2);
    let past = tipped(&tip, 1.0, Turn::STRAIGHT, [10.25, 10.0]);
    assert_eq!(piled(&[(0, 0)], [0; 4], &[past]).at(0, 11, 9), ([0; 4], 0));
}

// A tip 1/64 as thin as it is long lays nothing 4 px off its major axis:
// that pixel's 1024 times the stretch, 2^22, is 2^32 — which in u32 is
// nothing, the tip's very middle — so the minor axis is held to its own
// reach before it is stretched. A tip thinner than a unit keeps its
// outermost column: at 1/512 a radius of 1 px reaches 256.5 units, so the
// guard is one past 256, and pixel 11, whose centre is the edge, lays half
// of half the top-right texel, 8224.
#[test]
fn a_thin_tip_lays_nothing_off_its_minor_axis() {
    let thin = Turn { cos: 1.0, sin: 0.0, roundness: 1.0 / 64.0 };
    let tip = texture(&CORNERS, 2);
    let dab = Dab { region: [0, 0, 20, 20], ..tipped(&tip, 8.0, thin, [10.5, 10.5]) };
    let piled_thin = piled(&[(0, 0)], [0; 4], &[dab]);
    assert_ne!(piled_thin.at(0, 10, 10).0[3], 0);
    assert_eq!(piled_thin.at(0, 10, 14), ([0; 4], 0));
    let thinner = Turn { cos: 1.0, sin: 0.0, roundness: 1.0 / 512.0 };
    let dab = tipped(&tip, 1.0, thinner, [10.5, 10.5]);
    assert_eq!(piled(&[(0, 0)], [0; 4], &[dab]).at(0, 11, 10).0[3], 8224);
}

// A quarter turn (cos 0, sin 1): u = −dy and v = dx, so the texel under
// pixel (9, 10) is the one a straight tip lays on (9, 9), and so round.
#[test]
fn a_bitmap_tip_turns_with_its_frame() {
    let quarter = Turn { cos: 0.0, sin: 1.0, roundness: 1.0 };
    assert_eq!(corners(quarter, [10.0, 10.0]), [32896, 0, ONE, 16448]);
}

// At a roundness of ½ the minor axis stretches twice: half a pixel up is a
// whole radius up, halfway between texel row −1 and row 0, so the top
// pixels lay half their texels — 32768 and 16448 — and the bottom ones the
// lower row's half.
#[test]
fn a_bitmap_tip_squeezes_along_its_minor_axis() {
    let squeezed = Turn { cos: 1.0, sin: 0.0, roundness: 0.5 };
    assert_eq!(corners(squeezed, [10.0, 10.0]), [32768, 16448, 8224, 0]);
}

// An ellipse reads its profile at the stretched distance: at a roundness
// of ½ the pixel 1 px under the centre is 2 px out — entry 32, 43690 —
// where a circle's would be within its inner radius, and the pixel 2 px
// under is at the reach.
#[test]
fn an_ellipse_reads_its_profile_at_the_stretched_distance() {
    let (coverage, pile) = ramp();
    let profile = radial(&coverage, &pile, 4.0, 1.0);
    let squeezed = Turn { cos: 1.0, sin: 0.0, roundness: 0.5 };
    let dab = Dab { turn: squeezed, ..round(&profile, [10.5, 10.5]) };
    let piled = piled(&[(0, 0)], [0; 4], &[dab]);
    assert_eq!(piled.at(0, 10, 11).0[3], 43690);
    assert_eq!(piled.at(0, 10, 12).0[3], 0);
    assert_eq!(piled.at(0, 12, 10).0[3], 43690);
}

// A texture whose texels don't fill its side, or of no side, a tip too
// small to reach a unit of distance, or one squeezed so thin its stretch
// would leave u32 is refused rather than read wrong. (Past 16384 texels a
// side a texture is refused too; it is 2 GiB of texels and doesn't fit a
// test.)
#[test]
fn a_tip_past_what_the_integers_hold_is_refused() {
    assert!(Texture::new(&CORNERS, 3).is_none());
    assert!(Texture::new(&[], 0).is_none());
    let refused = |dab: Dab| tried(&[(0, 0)], [0; 4], &[dab]).is_none();
    let tip = texture(&CORNERS, 2);
    assert!(refused(tipped(&tip, 0.001, Turn::STRAIGHT, [10.0, 10.0])));
    let thin = Turn { cos: 1.0, sin: 0.0, roundness: 1e-6 };
    assert!(refused(tipped(&tip, 1.0, thin, [10.0, 10.0])));
}

/// A square dab of red at full flow over [-4, 0) to [4, 4), taking `density`
/// of the paper.
fn on_paper(density: f64) -> Dab<'static> {
    Dab { density, ..square([-4, 0, 4, 4], RED, 1.0) }
}

/// The alphas `dab` leaves over `paper` on pixels (0, 0), (1, 0), (0, 1)
/// and (1, 1).
fn papered(paper: &Paper, dab: Dab) -> [u32; 4] {
    let piled = laid(&mut Dabs::new(first_engine()), &[(0, 0)], [0; 4], Some(paper), &[dab]);
    let piled = piled.expect("pile");
    [(0, 0), (1, 0), (0, 1), (1, 1)].map(|(x, y)| piled.at(0, x, y).0[3])
}

// At a texel a pixel, pixel (x, y)'s centre is texel (x mod 2, y mod 2)'s
// own: the paper tiles from the canvas's origin, and a dab taking all of
// it lays it — 255, 128 over 64, and nothing where it is 0. Left of the
// origin it tiles on: pixel −1 is texel 1.
#[test]
fn the_paper_tiles_from_the_canvas_origin() {
    let grain = texture(&CORNERS, 2);
    let paper = Paper { texture: &grain, scale: 1.0, height: false };
    assert_eq!(papered(&paper, on_paper(1.0)), [ONE, 32896, 16448, 0]);
    let piled = laid(&mut Dabs::new(first_engine()), &[(0, 0), (-1, 0)], [0; 4], Some(&paper), &[
        on_paper(1.0),
    ]);
    let piled = piled.expect("pile");
    assert_eq!(piled.at(0, 2, 2).0[3], ONE);
    assert_eq!(piled.at(0, 1, 1), ([0; 4], 0));
    assert_eq!(piled.at(1, 127, 0).0[3], 32896);
    assert_eq!(piled.at(1, 126, 0).0[3], ONE);
}

// A dab takes the paper by its density: at ½ it keeps half of what the
// paper takes away — 32767 + round(32768·t/65535), 49215 over 128·257,
// 40991 over 64·257, 32767 over nothing.
#[test]
fn a_dab_takes_the_paper_by_its_density() {
    let grain = texture(&CORNERS, 2);
    let paper = Paper { texture: &grain, scale: 1.0, height: false };
    assert_eq!(papered(&paper, on_paper(0.5)), [ONE, 49215, 40991, 32767]);
}

// 高さ: a dab reaches density × its coverage into the paper and touches it
// where it stands above that floor, fully a quarter above: at ½ that is
// (t − 32767)·4 — all of 255, 129·4 = 516 of 128·257, nothing below.
#[test]
fn the_papers_height_cuts_where_it_stands_below_the_dab() {
    let grain = texture(&CORNERS, 2);
    let paper = Paper { texture: &grain, scale: 1.0, height: true };
    assert_eq!(papered(&paper, on_paper(0.5)), [ONE, 516, 0, 0]);
}

/// A 2 × 2 paper of stripes down: 255 then nothing along each row.
const STRIPES: [f64; 4] = [1.0, 0.0, 1.0, 0.0];

// At two pixels a texel the paper is read between its texels, wrapping.
// Pixel 0's centre is ¾ of the way from texel −1, that is texel 1, to
// texel 0: ⌊(65535·24576 + 16384)/32768⌋ = 49151. Pixel 1's is ¼ past
// texel 0: 65535 + ⌊(−65535·8192 + 16384)/32768⌋ = 49151. Pixel 2's is ¾
// past texel 0: 65535 + ⌊(−65535·24576 + 16384)/32768⌋ = 16384. Pixel 3's
// is ¼ past texel 1: ⌊(65535·8192 + 16384)/32768⌋ = 16384. It runs on
// across the tiles: pixel 128 is pixel 0, pixel −1 is pixel 3.
#[test]
fn the_paper_runs_on_between_its_texels_and_across_the_tiles() {
    let grain = texture(&STRIPES, 2);
    let paper = Paper { texture: &grain, scale: 2.0, height: false };
    let dab = Dab { region: [-4, 0, 132, 4], ..on_paper(1.0) };
    let tiles = [(0, 0), (1, 0), (-1, 0)];
    let piled = laid(&mut Dabs::new(first_engine()), &tiles, [0; 4], Some(&paper), &[dab]);
    let piled = piled.expect("pile");
    let row = [0, 1, 2, 3].map(|x| piled.at(0, x, 0).0[3]);
    assert_eq!(row, [49151, 49151, 16384, 16384]);
    assert_eq!(piled.at(1, 0, 0).0[3], 49151);
    assert_eq!(piled.at(2, 127, 0).0[3], 16384);
}

// A paper at no whole part of a texel a pixel, or past u32 of them, is
// refused.
#[test]
fn a_paper_past_what_the_integers_hold_is_refused() {
    let grain = texture(&CORNERS, 2);
    for scale in [0.0, 1e-6, 200000.0] {
        let paper = Paper { texture: &grain, scale, height: false };
        let kernel = &mut Dabs::new(first_engine());
        assert!(laid(kernel, &[(0, 0)], [0; 4], Some(&paper), &[on_paper(1.0)]).is_none());
    }
}

// A texture goes to the GPU once and is read from there by every pile
// after; where the plan has no room for a pile, it starts over with what
// that pile reads. Each pile by one kernel lays what a new kernel lays.
#[test]
fn textures_stay_on_the_plan_from_pile_to_pile() {
    let small = texture(&CORNERS, 2);
    let large = texture(&bristles(), 32);
    let paper = Paper { texture: &small, scale: 1.0, height: false };
    let kept = &mut Dabs::new(first_engine());
    for (texture, on) in [(&small, None), (&large, None), (&small, None), (&large, Some(&paper))] {
        let tip = [tipped(texture, 9.0, turn_of(1), [20.0, 20.0])];
        let by_kept = laid(kept, &[(0, 0)], [0; 4], on, &tip).expect("pile");
        let fresh = &mut Dabs::new(first_engine());
        let by_fresh = laid(fresh, &[(0, 0)], [0; 4], on, &tip).expect("pile");
        assert_eq!(by_kept.planes, by_fresh.planes);
        assert_eq!(by_kept.view, by_fresh.view);
    }
}

// A dab across a seam lays each tile its own part, and a tile on the
// pasteboard's side of the origin is laid like any other.
#[test]
fn a_dab_across_tiles_lays_each_its_part() {
    let tiles = [(-1, 0), (0, 0)];
    let piled = piled(&tiles, [0; 4], &[square([-3, 0, 3, 1], RED, 1.0)]);
    let red = (widened(RED, ONE), word([200, 100, 50, 255]));
    assert_eq!(piled.at(0, 125, 0), red);
    assert_eq!(piled.at(0, 124, 0), ([0; 4], 0));
    assert_eq!(piled.at(1, 2, 0), red);
    assert_eq!(piled.at(1, 3, 0), ([0; 4], 0));
}

/// A soft round tip of `radius` under `hardness`, filled the way
/// `RoundTipProfile` fills its tables: 16 entries a pixel, two past the
/// reach; 1 to the inner radius and falling from there to nothing at the
/// reach; the pile, the hardness ramp. Its tables and inner radius.
fn soft(radius: f64, hardness: f64) -> (Vec<f64>, Vec<f64>, f64) {
    let reach = radius + 0.5;
    let count = (reach * 16.0).ceil() as usize + 2;
    let hard = radius * hardness;
    let inner = hard - 0.5;
    let ramp = |distance: f64, top: f64, rim: f64| {
        if distance <= top { 1.0 } else { ((rim - distance) / (rim - top)).clamp(0.0, 1.0) }
    };
    let coverage = (0..count).map(|entry| ramp(entry as f64 / 16.0, inner, reach)).collect();
    let pile = (0..count).map(|entry| ramp(entry as f64 / 16.0, hard, radius)).collect();
    (coverage, pile, inner)
}

/// A small circle's square tables under `radius`: what a ramp from the
/// centre to the reach lays at each entry's (column, row), and what piles —
/// above it, as the app's tables hold their hardness above the edge.
fn small(radius: f64) -> (Vec<f64>, Vec<f64>, u32) {
    let reach = radius + 0.5;
    let count = (reach * 16.0).ceil() as u32 + 2;
    let at = |entry: u32, rim: f64| {
        let (x, y) = (f64::from(entry % count) / 16.0, f64::from(entry / count) / 16.0);
        ((rim - (x * x + y * y).sqrt()) / rim).clamp(0.0, 1.0)
    };
    let coverage = (0..count * count).map(|entry| at(entry, reach)).collect();
    let pile = (0..count * count).map(|entry| at(entry, reach + 1.0)).collect();
    (coverage, pile, count)
}

/// A stroke's dabs along a curve, `edit` making each its own: centres in
/// no step of a whole pixel, so every one lands between pixels its own way.
fn along<'a>(
    profile: &'a RoundProfile<'a>,
    count: u32,
    edit: impl Fn(u32, &mut Dab<'a>),
) -> Vec<Dab<'a>> {
    (0..count)
        .map(|k| {
            let mut dab = round(profile, on_curve(k));
            edit(k, &mut dab);
            dab
        })
        .collect()
}

/// The curve the ledger's strokes follow, dab `k`'s centre on it.
fn on_curve(k: u32) -> [f64; 2] {
    let t = f64::from(k);
    [20.0 + t * 9.37, 60.0 + t * t * 0.41 - t * 3.13]
}

/// Dab `k`'s turn: seven frames whose cosines and sines are exact ratios
/// (Pythagorean triples), so no device's sine table enters the ledger, and
/// four roundnesses.
fn turn_of(k: u32) -> Turn {
    let frames = [
        (1.0, 0.0),
        (0.6, 0.8),
        (5.0 / 13.0, 12.0 / 13.0),
        (0.0, 1.0),
        (-8.0 / 17.0, 15.0 / 17.0),
        (-0.8, -0.6),
        (12.0 / 13.0, -5.0 / 13.0),
    ];
    let (cos, sin) = frames[k as usize % frames.len()];
    Turn { cos, sin, roundness: [1.0, 0.75, 0.5, 0.53][k as usize % 4] }
}

/// A 32 × 32 bitmap tip of hashed greys inside a circle, nothing outside.
fn bristles() -> Vec<f64> {
    (0..32 * 32)
        .map(|texel: u32| {
            let (x, y) = (texel % 32, texel / 32);
            let (dx, dy) = (f64::from(x) - 15.5, f64::from(y) - 15.5);
            if dx * dx + dy * dy > 225.0 {
                return 0.0;
            }
            f64::from(((x * 73 + y * 151) ^ (x * y * 29)) % 256) / 255.0
        })
        .collect()
}

/// A 32 × 32 paper grain of hashed greys.
fn grain() -> Vec<f64> {
    (0..32 * 32u32)
        .map(|texel| f64::from((texel.wrapping_mul(2654435761) >> 24) & 0xff) / 255.0)
        .collect()
}

fn bytes(piled: &Piled) -> (Vec<u8>, Vec<u8>) {
    let planes = piled
        .planes
        .iter()
        .flatten()
        .flat_map(|channel| (*channel as u16).to_le_bytes())
        .collect();
    (planes, piled.view.iter().flat_map(|word| word.to_le_bytes()).collect())
}

#[test]
fn every_device_piles_the_pinned_strokes() {
    let tiles = [(0, 0), (1, 0), (0, 1), (1, 1)];
    let (coverage, pile, inner) = soft(13.77, 0.3);
    let profile = radial(&coverage, &pile, 14.27, inner);
    let (wide_coverage, wide_pile, wide_inner) = soft(150.0, 0.3);
    let wide = radial(&wide_coverage, &wide_pile, 150.5, wide_inner);
    let (dot_coverage, dot_pile, count) = small(2.0);
    let dot = RoundProfile {
        coverage: &dot_coverage,
        pile: &dot_pile,
        scale: 16.0,
        reach: 2.5,
        inner: -1.0,
        row_length: count,
    };
    let evening: Vec<f64> = (0..1026)
        .map(|entry| 1.0 - (1.0 - f64::from(entry.min(1024)) / 1024.0).sqrt())
        .collect();
    let blue = [30, 90, 220, 255];
    let bristle = texture(&bristles(), 32);
    let held = |_, dab: &mut Dab| {
        dab.edge_held = true;
        dab.opacity = 0.7;
    };
    let strokes: Vec<(&str, Vec<Dab>)> = vec![
        ("soft", along(&profile, 24, |k, dab| {
            dab.flow = 0.35;
            dab.colour = if k % 2 == 0 { RED } else { blue };
        })),
        ("held", along(&profile, 24, |k, dab| {
            dab.edge_held = true;
            dab.opacity = 0.4 + f64::from(k % 5) * 0.15;
        })),
        ("shared", along(&profile, 24, |_, dab| {
            dab.flow = 0.6;
            dab.evening = Some(&evening);
            dab.edge = Edge::Contrast(2.0);
        })),
        // Distances shifted a bit: a reach past 127 px.
        ("wide", along(&wide, 6, |_, dab| dab.flow = 0.3)),
        // Each dot laid twice, so its edge meets the ceiling.
        ("small", (0..2).flat_map(|_| along(&dot, 24, held)).collect()),
        ("ellipse", along(&profile, 24, |k, dab| {
            dab.flow = 0.5;
            dab.turn = turn_of(k);
        })),
        ("tip", (0..24)
            .map(|k| Dab { flow: 0.5, ..tipped(&bristle, 12.3, turn_of(k), on_curve(k)) })
            .collect()),
    ];
    for (name, dabs) in &strokes {
        let (planes, view) = bytes(&piled(&tiles, [0; 4], dabs));
        assert_pinned(&format!("dab/{name}-planes"), &planes);
        assert_pinned(&format!("dab/{name}-view"), &view);
    }
    // An eraser along the same curve over planes of red at 50000.
    let erased = piled(&tiles, widened(RED, 50000), &along(&profile, 24, |_, dab| {
        dab.erase = true;
        dab.flow = 0.5;
    }));
    assert_pinned("dab/erase-view", &bytes(&erased).1);
    // The held stroke on a grain tiled at 0.7 px a texel — a step of a
    // texel and a fraction, rounded up — its dabs taking the grain by turns:
    // multiplied, and by its height. It is drawn a tile up and left, across
    // the canvas's origin, where the paper's phase is taken below 0.
    let grain = texture(&grain(), 32);
    let across = [(-1, -1), (0, -1), (-1, 0), (0, 0)];
    for (name, height) in [("paper", false), ("paper-height", true)] {
        let paper = Paper { texture: &grain, scale: 0.7, height };
        let dabs = along(&profile, 24, |k, dab| {
            dab.flow = 0.5;
            dab.edge_held = true;
            dab.opacity = 0.8;
            dab.density = 0.3 + f64::from(k % 4) * 0.2;
            dab.centre = dab.centre.map(|c| c - 128.0);
            dab.region = dab.region.map(|edge| edge - 128);
        });
        let kernel = &mut Dabs::new(first_engine());
        let piled = laid(kernel, &across, [0; 4], Some(&paper), &dabs).expect("pile");
        let (planes, view) = bytes(&piled);
        assert_pinned(&format!("dab/{name}-planes"), &planes);
        assert_pinned(&format!("dab/{name}-view"), &view);
    }
}
