//! The dab kernel on a real GPU, checked against the ledger and against
//! what the formula gives by hand — never against a CPU copy of it
//! (`kernels/mod.rs` has why).

use super::{Dab, Dabs, Edge, RoundProfile, Shape, StrokeTile};
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

/// `dabs` piled on `tiles` (slots in their order) whose planes start as
/// `under`, every pixel of every tile.
fn piled(tiles: &[(i32, i32)], under: [u32; 4], dabs: &[Dab]) -> Piled {
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
    Dabs::new(engine)
        .pile(engine, &stroke, dabs, &planes, &view)
        .expect("pile");
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
    Piled { planes, view: words(&view) }
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
        evening: None,
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
// flow 1 leaves nothing, the colour with it.
#[test]
fn an_erase_takes_its_alpha_and_keeps_the_colour() {
    let opaque = widened(RED, ONE);
    let erase = |flow| Dab { erase: true, ..square([0, 0, 2, 2], [0, 0, 0, 255], flow) };
    let half = (widened(RED, 32767), word([200, 100, 50, 127]));
    assert_eq!(piled(&[(0, 0)], opaque, &[erase(0.5)]).at(0, 0, 0), half);
    assert_eq!(piled(&[(0, 0)], opaque, &[erase(1.0)]).at(0, 1, 1), ([0; 4], 0));
}

/// A round profile of `reach` 4 px, 16 entries a pixel: 1 to a distance
/// of 1, falling straight to 0 at 4 — entry 32, at 2 px, is ⅔. Its pile
/// is 1 throughout.
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

fn round<'a>(profile: &'a RoundProfile<'a>, centre: [f64; 2]) -> Dab<'a> {
    Dab {
        centre,
        region: [i32::MIN / 2, i32::MIN / 2, i32::MAX / 2, i32::MAX / 2],
        shape: Shape::Round(profile),
        ..square([0; 4], RED, 1.0)
    }
}

// Centred on pixel (10, 10)'s centre: the pixel itself is within the inner
// radius and lays 1; the one 2 px right reads entry 32 exactly — ⅔ is
// 43690 —; the one 4 px right is at the reach and is not touched. Under
// 없음 the ⅔ is cut to 1; under a contrast of 2 it is
// (43690 − 32768)·2 + 32768 = 54612.
#[test]
fn a_round_tip_reads_its_profile_along_the_radius() {
    let (coverage, pile) = ramp();
    let profile = radial(&coverage, &pile, 4.0, 1.0);
    let alpha = |edge, x| {
        let dab = Dab { edge, ..round(&profile, [10.5, 10.5]) };
        piled(&[(0, 0)], [0; 4], &[dab]).at(0, x, 10).0[3]
    };
    assert_eq!(alpha(Edge::Contrast(1.0), 10), ONE);
    assert_eq!(alpha(Edge::Contrast(1.0), 12), 43690);
    assert_eq!(alpha(Edge::Contrast(1.0), 14), 0);
    assert_eq!(alpha(Edge::Threshold, 12), ONE);
    assert_eq!(alpha(Edge::Contrast(2.0), 12), 54612);
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
// round(¼·65535) = 16384 whatever the dab would lay whole, and a table of
// (entry/1024)² reads its last entry, 1 exactly, at a whole of 1.
#[test]
fn a_dab_lays_its_share_through_its_table() {
    let quarter = vec![0.25; 1026];
    let squares: Vec<f64> = (0..1026)
        .map(|entry| (f64::from(entry.min(1024)) / 1024.0).powi(2))
        .collect();
    let through = |table: &[f64]| {
        let dab = Dab { evening: Some(table), ..square([0, 0, 1, 1], RED, 1.0) };
        piled(&[(0, 0)], [0; 4], &[dab]).at(0, 0, 0).0[3]
    };
    assert_eq!(through(&quarter), 16384);
    assert_eq!(through(&squares), ONE);
}

// A small circle is read by its square tables at (|dx|, |dy|), along the
// row and then down. A table of 1 − (column + row)/24 under a centre at
// (10.27, 10.5): pixel 10's centre is round(10.27·256) = 2629 off by 59/256
// px, 59/16 entries — between entry 3 (57343) and 4 (54613) by
// 22528/32768 — on row 0: 57343 + ⌊(−2730·22528 + 16384)/32768⌋ = 55466.
#[test]
fn a_small_circle_is_read_by_its_square_tables() {
    let count = 26;
    let table: Vec<f64> = (0..count * count)
        .map(|entry| (1.0 - f64::from(entry % count + entry / count) / 24.0).max(0.0))
        .collect();
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
    assert_eq!(piled.at(0, 12, 10).0[3], 0);
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

/// A soft round tip of radius `radius` under `hardness`, closed forms
/// filled the way `RoundTipProfile` fills its tables: 16 entries a pixel,
/// two past the reach; the pile is the hardness ramp.
fn soft(radius: f64, hardness: f64) -> (Vec<f64>, Vec<f64>, f64) {
    let reach = radius + 0.5;
    let count = (reach * 16.0).ceil() as usize + 2;
    let hard = radius * hardness;
    let at = |entry: usize, rim: f64| {
        let distance = entry as f64 / 16.0;
        if distance <= hard { 1.0 } else { ((rim - distance) / (rim - hard)).clamp(0.0, 1.0) }
    };
    let coverage = (0..count).map(|entry| at(entry, reach)).collect();
    let pile = (0..count).map(|entry| at(entry, radius)).collect();
    (coverage, pile, reach)
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
            let t = f64::from(k);
            let mut dab = round(profile, [20.0 + t * 9.37, 60.0 + t * t * 0.41 - t * 3.13]);
            edit(k, &mut dab);
            dab
        })
        .collect()
}

#[test]
fn every_device_piles_the_pinned_strokes() {
    let tiles = [(0, 0), (1, 0), (0, 1), (1, 1)];
    let (coverage, pile, reach) = soft(14.0, 0.3);
    let profile = radial(&coverage, &pile, reach, 14.0 * 0.3 - 0.5);
    let evening: Vec<f64> = (0..1026)
        .map(|entry| 1.0 - (1.0 - f64::from(entry.min(1024)) / 1024.0).sqrt())
        .collect();
    let blue = [30, 90, 220, 255];
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
    ];
    for (name, dabs) in &strokes {
        let piled = piled(&tiles, [0; 4], dabs);
        let planes: Vec<u8> = piled
            .planes
            .iter()
            .flatten()
            .flat_map(|channel| (*channel as u16).to_le_bytes())
            .collect();
        let view: Vec<u8> = piled.view.iter().flat_map(|word| word.to_le_bytes()).collect();
        assert_pinned(&format!("dab/{name}-planes"), &planes);
        assert_pinned(&format!("dab/{name}-view"), &view);
    }
    // An eraser along the same curve over planes of red at 50000.
    let erased = piled(&tiles, widened(RED, 50000), &along(&profile, 24, |_, dab| {
        dab.erase = true;
        dab.flow = 0.5;
    }));
    let view: Vec<u8> = erased.view.iter().flat_map(|word| word.to_le_bytes()).collect();
    assert_pinned("dab/erase-view", &view);
}
