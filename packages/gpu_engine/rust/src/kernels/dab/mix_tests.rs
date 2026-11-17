//! A mixing brush's steps on a real GPU: the colour each lays, worked by
//! hand from the app's law (`BrushGroundColorMixer`) over grounds whose
//! colour and cover are known.

use super::super::landing::{Asked, Laid};
use super::super::stroke::Stroke;
use super::super::{Dab, Edge, Shape, Turn};
use super::{Ground, Step, ground_of};
use crate::device::Engine;
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::composite::{Composite, TILE_BYTES, TileAt};
use crate::kernels::pool::{Cel, Pool};
use crate::testing::first_engine;

const RED: [u8; 4] = [255, 0, 0, 255];
const BLUE: [u8; 4] = [0, 0, 255, 255];
const GREEN: [u8; 4] = [0, 255, 0, 255];

/// A loaded brush's step at `centre`, of `radius`, drawing blue: the pickup,
/// refill and laid share of the app's fit (0.12, 0.12, 0.3), a whole stamp.
fn loaded(centre: [f64; 2], radius: f64, density: f64) -> Step {
    Step {
        centre,
        radius,
        colour: BLUE,
        refill: 0.12,
        laid: 0.3,
        density,
        take: 0.0,
        share: 1.0,
        pick: 0.12,
        dry: false,
    }
}

/// A dry brush's step at `centre`, picking `take` up a whole stamp.
fn dry(centre: [f64; 2], take: f64) -> Step {
    Step { take, dry: true, ..loaded(centre, 10.0, 0.0) }
}

/// A square dab of `colour`, whole, over `region`.
fn square(region: [i32; 4], colour: [u8; 4]) -> Dab<'static> {
    Dab {
        centre: [0.0, 0.0],
        region,
        colour,
        opacity: 1.0,
        flow: 1.0,
        edge: Edge::Contrast(1.0),
        edge_held: false,
        erase: false,
        second: false,
        shape: Shape::Square,
        turn: Turn::STRAIGHT,
        evening: None,
        density: None,
    }
}

struct Fixture {
    engine: &'static Engine,
    composite: Composite,
    pool: Pool,
    cel: Cel,
    stroke: Stroke,
}

fn fixture() -> Fixture {
    let engine = first_engine();
    let mut pool = Pool::new(engine, u64::MAX).expect("a pool");
    let cel = pool.cel();
    Fixture {
        engine,
        composite: Composite::new(engine).expect("a composite"),
        pool,
        cel,
        stroke: Stroke::new(engine).expect("a stroke"),
    }
}

impl Fixture {
    /// A tile of the cel, every pixel `pixel`.
    fn stored(&mut self, pixel: [u8; 4]) -> TileAt {
        let bytes = pixel.repeat(TILE_BYTES as usize / 4);
        self.pool.store(self.engine, self.cel, &[&bytes]).expect("a store")[0]
    }

    /// Hands `steps` from `first` and piles `dabs` with them, the cel's
    /// tile under each ground tile they read found in `cel` by its column
    /// and row; `colours` names the dabs that take a step's colour.
    fn pile(
        &mut self,
        steps: &[Step],
        first: u32,
        cel: &[((i32, i32), TileAt)],
        dabs: &[Dab],
        colours: &[(usize, u32)],
    ) {
        let ground = self.stroke.hand_steps(steps, first).expect("steps handed").to_vec();
        let under: Vec<Option<TileAt>> = ground
            .iter()
            .map(|tile| cel.iter().find(|(at, _)| at == tile).map(|&(_, under)| under))
            .collect();
        let ground = Ground { executor: &self.composite, pages: self.pool.pages(), under: &under };
        let mixed = Some((ground, colours));
        self.stroke.pile_mixed(self.engine, dabs, None, None, mixed).expect("a pile");
    }

    fn mixed(&self, count: usize) -> Vec<u32> {
        self.stroke.mixed(self.engine, count).expect("the steps' colours")
    }

    /// The stroke landed on tile (0, 0) over nothing, its pixel (x, y).
    fn landed(&mut self, x: usize, y: usize) -> [u8; 4] {
        let laid = Laid { opacity: 65535, mode: NORMAL, mask: None };
        let asked = [Asked { column: 0, row: 0, under: None }];
        let kit = (&self.composite, &mut self.pool, self.cel);
        let landed = self.stroke.land(self.engine, kit, &asked, &laid, false).expect("a landing");
        let mut bytes = vec![0; TILE_BYTES as usize];
        self.pool.read(self.engine, &[landed[0].1.expect("a slot")], &mut bytes).expect("a read");
        bytes[(y * 128 + x) * 4..][..4].try_into().unwrap()
    }
}

/// ARGB, as the app's dabs hold a colour.
fn argb([red, green, blue, alpha]: [u8; 4]) -> u32 {
    u32::from_be_bytes([alpha, red, green, blue])
}

#[test]
fn a_loaded_brush_over_a_red_ground_lifts_it_and_comes_back_to_its_own() {
    let mut f = fixture();
    let red = f.stored(RED);
    let cel = [((0, 0), red)];
    f.pile(&[loaded([64.0, 64.0], 10.0, 1.0)], 0, &cel, &[], &[]);
    f.pile(&[loaded([64.0, 64.0], 10.0, 1.0)], 1, &cel, &[], &[]);
    // Blue toward red by 0.12, back toward blue by 0.12 — what it carries
    // (26.928, 0, 228.072) —, and 0.3 of blue over it: 18.85, 236.15.
    // The second lifts from what it carries: 54.30, 200.70; 47.78, 207.22;
    // 33.45, 221.55.
    assert_eq!(f.mixed(2), [argb([19, 0, 236, 255]), argb([33, 0, 222, 255])]);
}

#[test]
fn bare_canvas_lends_a_loaded_brush_nothing() {
    let mut f = fixture();
    f.pile(&[loaded([64.0, 64.0], 10.0, 0.4)], 0, &[], &[], &[]);
    // Its own colour, as thick as its density: 255 × 0.4.
    assert_eq!(f.mixed(1), [argb([0, 0, 255, 102])]);
}

#[test]
fn a_ground_half_under_the_dab_is_lifted_half_as_far() {
    let mut f = fixture();
    let red = f.stored(RED);
    // On the edge of tile (0, 0): four columns of points on it, four on
    // tile (1, 0), which the cel has none of.
    f.pile(&[loaded([128.0, 64.0], 16.0, 1.0)], 0, &[((0, 0), red)], &[], &[]);
    // Blue toward red by 0.06, back by 0.12, 0.3 of blue: 9.42, 245.58.
    assert_eq!(f.mixed(1), [argb([9, 0, 246, 255])]);
}

#[test]
fn a_dry_brush_lays_what_it_picked_up_as_thick_as_it_holds_it() {
    let mut f = fixture();
    let red = f.stored(RED);
    let steps = [dry([64.0, 64.0], 0.4), dry([64.0, 300.0], 0.4)];
    f.pile(&steps, 0, &[((0, 0), red)], &[], &[]);
    // Red it holds 0.4 of; then over bare canvas it thins by the pickup's
    // rate, 0.4 + (0 − 0.4) × 0.4 = 0.24, and is red still.
    assert_eq!(f.mixed(2), [argb([255, 0, 0, 102]), argb([255, 0, 0, 61])]);
}

#[test]
fn a_dry_brush_on_bare_canvas_lays_nothing() {
    let mut f = fixture();
    f.pile(&[dry([64.0, 64.0], 0.4)], 0, &[], &[], &[]);
    assert_eq!(f.mixed(1), [argb([0, 0, 255, 0])]);
}

#[test]
fn a_dab_lays_the_colour_of_the_step_it_names_not_its_own() {
    let mut f = fixture();
    let red = f.stored(RED);
    let steps = [loaded([64.0, 64.0], 10.0, 1.0)];
    let dabs = [square([0, 0, 64, 128], GREEN), square([64, 0, 128, 128], GREEN)];
    f.pile(&steps, 0, &[((0, 0), red)], &dabs, &[(0, 0)]);
    assert_eq!(f.landed(10, 10), [19, 0, 236, 255]);
    assert_eq!(f.landed(100, 10), GREEN, "a dab that names no step lays its own");
}

#[test]
fn a_dab_lays_the_steps_alpha_too() {
    let mut f = fixture();
    // Bare canvas: its own blue, as thick as its density — 255 × 0.4.
    let steps = [loaded([64.0, 64.0], 10.0, 0.4)];
    f.pile(&steps, 0, &[], &[square([0, 0, 8, 8], GREEN)], &[(0, 0)]);
    assert_eq!(f.landed(4, 4), [0, 0, 255, 102]);
}

#[test]
fn a_step_whose_dabs_reach_no_tile_still_moves_the_reservoir() {
    let mut f = fixture();
    let red = f.stored(RED);
    let cel = [((0, 0), red)];
    let nowhere = [square([10, 10, 10, 10], GREEN)];
    f.pile(&[loaded([64.0, 64.0], 10.0, 1.0)], 0, &cel, &nowhere, &[(0, 0)]);
    f.pile(&[loaded([64.0, 64.0], 10.0, 1.0)], 1, &cel, &[], &[]);
    assert_eq!(f.mixed(2)[1], argb([33, 0, 222, 255]));
}

#[test]
fn a_cleared_stroke_starts_with_an_empty_brush() {
    let mut f = fixture();
    let red = f.stored(RED);
    f.pile(&[loaded([64.0, 64.0], 10.0, 1.0)], 0, &[((0, 0), red)], &[], &[]);
    f.stroke.clear(f.engine);
    f.pile(&[loaded([64.0, 300.0], 10.0, 1.0)], 0, &[], &[], &[]);
    assert_eq!(f.mixed(1), [argb(BLUE)], "nothing carried from the stroke before");
}

#[test]
fn steps_run_in_the_order_handed_and_only_with_their_ground() {
    let mut f = fixture();
    let step = loaded([64.0, 64.0], 10.0, 1.0);
    assert!(f.stroke.hand_steps(&[step], 1).is_none(), "the chain starts at 0");
    assert!(f.stroke.hand_steps(&[step], 0).is_some());
    let pile = f.stroke.pile(f.engine, &[square([0, 0, 8, 8], GREEN)], None, None);
    assert!(pile.is_none(), "steps handed run with their ground");
    assert!(f.stroke.mixed(f.engine, 1).is_none(), "none has run");
}

#[test]
fn a_step_that_ran_is_not_handed_again() {
    let mut f = fixture();
    let step = loaded([64.0, 64.0], 10.0, 1.0);
    f.pile(&[step], 0, &[], &[], &[]);
    assert!(f.stroke.hand_steps(&[step], 0).is_none(), "step 0 has run");
    assert!(f.stroke.hand_steps(&[step], 1).is_some());
}

#[test]
fn a_steps_ground_is_the_tiles_its_points_are_on() {
    let corner = loaded([128.0, 128.0], 20.0, 1.0);
    assert_eq!(ground_of(&[corner]), [(0, 0), (1, 0), (0, 1), (1, 1)]);
    let within = loaded([64.0, 64.0], 20.0, 1.0);
    assert_eq!(ground_of(&[within, corner]), [(0, 0), (1, 0), (0, 1), (1, 1)]);
    assert_eq!(ground_of(&[loaded([-1.0, 64.0], 0.5, 1.0)]), [(-1, 0)]);
    assert!(ground_of(&[loaded([64.0, 64.0], 0.0, 1.0)]).is_empty(), "no circle, no point");
}

#[test]
fn a_clear_ground_is_lifted_at_its_colour_as_far_as_it_covers() {
    let mut f = fixture();
    // White at alpha 128: its colour is white, however clear — clear
    // pixels hold no colour to darken it — and it covers 128/255.
    let half = f.stored([255, 255, 255, 128]);
    f.pile(&[dry([64.0, 64.0], 1.0)], 0, &[((0, 0), half)], &[], &[]);
    assert_eq!(f.mixed(1), [argb([255, 255, 255, 128])]);
}

#[test]
fn a_dab_names_a_step_an_earlier_pile_ran() {
    let mut f = fixture();
    let red = f.stored(RED);
    f.pile(&[loaded([64.0, 64.0], 10.0, 1.0)], 0, &[((0, 0), red)], &[], &[]);
    f.pile(&[], 1, &[], &[square([0, 0, 8, 8], GREEN)], &[(0, 0)]);
    assert_eq!(f.landed(4, 4), [19, 0, 236, 255]);
}

#[test]
fn a_step_reads_its_grid_whatever_its_size() {
    let huge = loaded([5000.0, 5000.0], 4000.0, 1.0);
    let read = ground_of(&[huge]);
    assert!(read.len() <= 64, "{} tiles: a point a lane", read.len());
    assert!(read.len() > 16, "the grid spans the dab, {} tiles", read.len());
}
