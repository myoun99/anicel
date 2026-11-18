//! A stroke's tiles on a real GPU: what it makes of a cel, by hand from
//! what a whole dab of a colour lays.

use super::super::blur::{Blurs, Cover, window_of};
use super::super::{Dab, Edge, Shape, Turn};
use super::{Asked, Laid, Stroke, TILES_A_PAGE};
use crate::device::Engine;
use crate::kernels::blend::mode::{ERASE, NORMAL};
use crate::kernels::composite::{Composite, TILE_BYTES, TileAt};
use crate::kernels::mask::{Mask, MaskBox};
use crate::kernels::pool::{Cel, Pool};
use crate::kernels::shared::words_buffer;
use crate::kernels::write::Change;
use crate::testing::first_engine;

const WHOLE: u32 = 65535;
const SIDE: i32 = 128;
const RED: [u8; 4] = [200, 100, 50, 255];
const CEL_PIXEL: [u8; 4] = [10, 20, 30, 255];

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

fn tile_region(column: i32, row: i32) -> [i32; 4] {
    [column * SIDE, row * SIDE, (column + 1) * SIDE, (row + 1) * SIDE]
}

struct Fixture {
    engine: &'static Engine,
    composite: Composite,
    pool: Pool,
    cel: Cel,
    stroke: Stroke,
    blurs: Option<Blurs>,
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
        blurs: None,
    }
}

impl Fixture {
    /// A tile of the cel, every pixel `pixel`.
    fn stored(&mut self, pixel: [u8; 4]) -> TileAt {
        let bytes = pixel.repeat(TILE_BYTES as usize / 4);
        let places = self.pool.store(self.engine, self.cel, &[&bytes]).expect("a store");
        places[0]
    }

    fn pile(&mut self, dabs: &[Dab]) {
        self.stroke.pile(self.engine, dabs, None, None).expect("a pile");
    }

    fn land(
        &mut self,
        asked: &[Asked],
        laid: &Laid,
        compared: bool,
    ) -> Vec<(Change, Option<TileAt>)> {
        let kit = (&self.composite, &mut self.pool, self.cel);
        self.stroke.land(self.engine, kit, asked, laid, compared).expect("a landing")
    }

    fn read(&self, at: TileAt) -> Vec<u8> {
        let mut bytes = vec![0; TILE_BYTES as usize];
        self.pool.read(self.engine, &[at], &mut bytes).expect("a read");
        bytes
    }
}

fn pixel(bytes: &[u8], x: usize, y: usize) -> [u8; 4] {
    bytes[(y * 128 + x) * 4..][..4].try_into().unwrap()
}

const NORMAL_WHOLE: Laid<'static> = Laid { opacity: WHOLE, mode: NORMAL, mask: None };

fn asked(column: i32, row: i32, under: Option<TileAt>) -> Asked {
    Asked { column, row, under }
}

#[test]
fn a_dab_lands_on_the_cel_under_it_in_a_slot_of_its_own() {
    let mut f = fixture();
    let under = f.stored(CEL_PIXEL);
    f.pile(&[square([10, 10, 20, 20], RED)]);
    let landed = f.land(&[asked(0, 0, Some(under))], &NORMAL_WHOLE, true);
    assert_eq!(landed.len(), 1);
    let (change, at) = landed[0];
    assert_eq!(change, Change::Inked);
    let at = at.expect("a slot");
    assert_ne!(at, under, "a stored tile is never written over");
    let bytes = f.read(at);
    assert_eq!(pixel(&bytes, 12, 12), RED);
    assert_eq!(pixel(&bytes, 5, 5), CEL_PIXEL);
    assert_eq!(pixel(&f.read(under), 12, 12), CEL_PIXEL);
}

#[test]
fn a_tile_where_the_cel_has_none_is_the_stroke_alone() {
    let mut f = fixture();
    f.pile(&[square([10, 10, 20, 20], RED)]);
    let landed = f.land(&[asked(0, 0, None)], &NORMAL_WHOLE, true);
    let bytes = f.read(landed[0].1.expect("a slot"));
    assert_eq!(pixel(&bytes, 12, 12), RED);
    assert_eq!(pixel(&bytes, 5, 5), [0, 0, 0, 0]);
}

#[test]
fn a_stroke_that_changes_nothing_takes_no_slot_when_compared() {
    let mut f = fixture();
    let under = f.stored(CEL_PIXEL);
    f.pile(&[square([10, 10, 20, 20], CEL_PIXEL)]);
    let landed = f.land(&[asked(0, 0, Some(under))], &NORMAL_WHOLE, true);
    assert_eq!(landed, vec![(Change::Same, None)]);
}

#[test]
fn a_stroke_on_its_way_lands_without_asking() {
    let mut f = fixture();
    let under = f.stored(CEL_PIXEL);
    f.pile(&[square([10, 10, 20, 20], CEL_PIXEL)]);
    let landed = f.land(&[asked(0, 0, Some(under))], &NORMAL_WHOLE, false);
    assert_eq!(landed[0].0, Change::Inked);
    assert_eq!(pixel(&f.read(landed[0].1.expect("a slot")), 12, 12), CEL_PIXEL);
}

#[test]
fn an_eraser_that_leaves_nothing_takes_no_slot_when_compared() {
    let mut f = fixture();
    let under = f.stored(CEL_PIXEL);
    f.pile(&[square(tile_region(0, 0), RED)]);
    let erase = Laid { opacity: WHOLE, mode: ERASE, mask: None };
    let landed = f.land(&[asked(0, 0, Some(under))], &erase, true);
    assert_eq!(landed, vec![(Change::Cleared, None)]);
}

#[test]
fn the_stroke_lays_at_its_opacity_in_its_mode() {
    let mut f = fixture();
    let under = f.stored(CEL_PIXEL);
    f.pile(&[square([10, 10, 20, 20], RED)]);
    let erase = Laid { opacity: WHOLE, mode: ERASE, mask: None };
    let erased = f.land(&[asked(0, 0, Some(under))], &erase, false);
    assert_eq!(pixel(&f.read(erased[0].1.unwrap()), 12, 12), [0, 0, 0, 0]);
    let half = Laid { opacity: 32768, mode: NORMAL, mask: None };
    let laid = f.land(&[asked(0, 0, Some(under))], &half, false);
    let [red, green, blue, alpha] = pixel(&f.read(laid[0].1.unwrap()), 12, 12);
    assert_eq!(alpha, 255);
    assert!((104..=106).contains(&red), "{red}");
    assert!((59..=61).contains(&green), "{green}");
    assert!((39..=41).contains(&blue), "{blue}");
}

#[test]
fn only_the_pixels_a_mask_covers_take_the_stroke() {
    let mut f = fixture();
    let under = f.stored(CEL_PIXEL);
    f.pile(&[square(tile_region(0, 0), RED)]);
    // The mask covers a box of 32 from (16, 16), every pixel whole.
    let size = MaskBox { width: 32, height: 32 };
    let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
    let plane = words_buffer(f.engine, "mask", &size.words_of(&[255; 32 * 32]), usage);
    let mask = Mask { plane: &plane, at: (16, 16), size };
    let laid = Laid { opacity: WHOLE, mode: NORMAL, mask: Some(&mask) };
    let landed = f.land(&[asked(0, 0, Some(under))], &laid, true);
    let bytes = f.read(landed[0].1.expect("a slot"));
    assert_eq!(pixel(&bytes, 20, 20), RED);
    assert_eq!(pixel(&bytes, 5, 5), CEL_PIXEL);
}

#[test]
fn a_tile_asked_that_no_dab_reached_is_the_cels() {
    let mut f = fixture();
    let under = f.stored(CEL_PIXEL);
    f.pile(&[square([10, 10, 20, 20], RED)]);
    let landed = f.land(&[asked(1, 0, Some(under))], &NORMAL_WHOLE, true);
    assert_eq!(landed, vec![(Change::Same, None)]);
}

#[test]
fn the_tiles_asked_answer_in_their_order_wherever_they_lie() {
    let mut f = fixture();
    f.pile(&[
        square(tile_region(-2, 3), RED),
        square(tile_region(1, -1), CEL_PIXEL),
    ]);
    let asks = [asked(1, -1, None), asked(-2, 3, None)];
    let landed = f.land(&asks, &NORMAL_WHOLE, true);
    assert_eq!(pixel(&f.read(landed[0].1.unwrap()), 64, 64), CEL_PIXEL);
    assert_eq!(pixel(&f.read(landed[1].1.unwrap()), 64, 64), RED);
}

#[test]
fn tiles_past_a_page_land_from_the_next_and_do_not_read_as_the_pools() {
    let mut f = fixture();
    // Every tile of a page and one more: the last is slot 0 of page 1.
    let wide = TILES_A_PAGE as i32;
    let last = wide;
    let mut dabs: Vec<Dab> = (0..wide).map(|column| square(tile_region(column, 0), RED)).collect();
    dabs.push(square(tile_region(last, 0), CEL_PIXEL));
    f.pile(&dabs);
    assert_eq!(f.stroke.planes.len(), 2);
    // The pool holds a page of its own the stroke's would be read as, were
    // a plan's places not told apart.
    let under = f.stored([1, 2, 3, 255]);
    let asks = [asked(last, 0, Some(under)), asked(0, 0, None)];
    let landed = f.land(&asks, &NORMAL_WHOLE, true);
    assert_eq!(pixel(&f.read(landed[0].1.unwrap()), 64, 64), CEL_PIXEL);
    assert_eq!(pixel(&f.read(landed[1].1.unwrap()), 64, 64), RED);
}

#[test]
fn a_cleared_stroke_starts_from_nothing_and_keeps_its_pages() {
    let mut f = fixture();
    f.pile(&[square(tile_region(0, 0), RED), square(tile_region(1, 0), RED)]);
    f.land(&[asked(0, 0, None), asked(1, 0, None)], &NORMAL_WHOLE, true);
    let bytes = f.stroke.bytes();
    f.stroke.clear(f.engine);
    assert_eq!(f.stroke.bytes(), bytes);
    // A dab elsewhere on the same slot: nothing of the last stroke is left.
    f.pile(&[square([200, 200, 210, 210], CEL_PIXEL)]);
    assert_eq!(f.stroke.tiles[&(1, 1)], TileAt { page: 0, slot: 0 });
    let landed = f.land(&[asked(1, 1, None)], &NORMAL_WHOLE, true);
    let result = f.read(landed[0].1.unwrap());
    assert_eq!(pixel(&result, 10, 10), [0, 0, 0, 0]);
    assert_eq!(pixel(&result, 75, 75), CEL_PIXEL);
    // The slot after it, too: every slot the stroke wrote is cleared.
    f.pile(&[square([520, 200, 530, 210], CEL_PIXEL)]);
    assert_eq!(f.stroke.tiles[&(4, 1)], TileAt { page: 0, slot: 1 });
    let landed = f.land(&[asked(4, 1, None)], &NORMAL_WHOLE, true);
    assert_eq!(pixel(&f.read(landed[0].1.unwrap()), 10, 10), [0, 0, 0, 0]);
}

#[test]
fn a_cleared_second_plane_starts_from_nothing() {
    let mut f = fixture();
    let screen = crate::kernels::blend::mode::SCREEN;
    let first = Dab { second: true, ..square(tile_region(0, 0), RED) };
    f.stroke.pile(f.engine, &[first], None, Some((screen, 1.0))).expect("a pile");
    f.stroke.clear(f.engine);
    // Screen of the second's level over the first's alpha: a level left from
    // the last stroke would raise this dab's alpha past what it lays.
    let mut dab = square(tile_region(0, 0), RED);
    dab.opacity = 0.5;
    f.stroke.pile(f.engine, &[dab], None, Some((screen, 1.0))).expect("a pile");
    let landed = f.land(&[asked(0, 0, None)], &NORMAL_WHOLE, false);
    let alpha = pixel(&f.read(landed[0].1.unwrap()), 64, 64)[3];
    assert!((127..=128).contains(&alpha), "{alpha}");
}

#[test]
fn a_second_tip_piles_on_a_plane_that_starts_at_nothing() {
    let mut f = fixture();
    // Multiply of the second's level over the first's alpha: with no dab on
    // the second plane its level is 0, so the view shows nothing.
    let multiply = crate::kernels::blend::mode::MULTIPLY;
    let dab = square([10, 10, 20, 20], RED);
    f.stroke.pile(f.engine, &[dab], None, Some((multiply, 1.0))).expect("a pile");
    assert_eq!(f.stroke.levels.len(), 1);
    let landed = f.land(&[asked(0, 0, None)], &NORMAL_WHOLE, true);
    assert_eq!(landed, vec![(Change::Same, None)]);
}

#[test]
fn an_empty_region_reaches_no_tile() {
    let mut f = fixture();
    f.pile(&[square([20, 20, 20, 40], RED), square([20, 20, 40, 20], RED)]);
    assert!(f.stroke.tiles.is_empty());
    assert_eq!(f.stroke.bytes(), 0);
}

#[test]
fn a_full_pool_lands_the_first_it_has_room_for() {
    let mut f = fixture();
    f.pile(&[square(tile_region(0, 0), RED), square(tile_region(1, 0), RED)]);
    f.pool.set_most_bytes(0);
    let asks = [asked(0, 0, None), asked(1, 0, None)];
    let landed = f.land(&asks, &NORMAL_WHOLE, false);
    assert!(landed.is_empty());
}

#[test]
fn a_stroke_asked_nothing_lands_nothing() {
    let mut f = fixture();
    f.pile(&[square([10, 10, 20, 20], RED)]);
    assert!(f.land(&[], &NORMAL_WHOLE, true).is_empty());
}

// --- a blur stroke ----------------------------------------------------------

/// A blur dab, whole, over `region`, at a box radius of 2: three boxes of
/// five, which read six pixels each way, by 1, 3, 6, 10, 15, 18, 19, 18, 15,
/// 10, 6, 3, 1 of 125.
fn rubbing(region: [i32; 4]) -> (Dab<'static>, u32) {
    (square(region, RED), 2)
}

const WHOLE_COVER: Cover<'static> = Cover { opacity: WHOLE, mask: None };

impl Fixture {
    /// Rubs `dabs` over the cel, `under` its tile at a coordinate: the
    /// coordinates the rub met.
    fn rub(
        &mut self,
        dabs: &[(Dab, u32)],
        under: impl Fn((i32, i32)) -> Option<TileAt>,
    ) -> Vec<(i32, i32)> {
        let count = self.stroke.reach_blur(self.engine, dabs).expect("a reach");
        let met: Vec<(i32, i32)> =
            self.stroke.met().iter().map(|tile| (tile.column, tile.row)).collect();
        assert_eq!(met.len(), count);
        let cel: Vec<Option<TileAt>> = met.iter().map(|&coordinate| under(coordinate)).collect();
        let engine = self.engine;
        let blurs = self.blurs.get_or_insert_with(|| {
            // By strips, as a stroke goes once the app has compiled them.
            Blurs::compile_strips(engine).expect("the strips' kernels");
            Blurs::new(engine).expect("blurs")
        });
        let tools = (blurs, &self.composite, self.pool.pages());
        self.stroke.rub(self.engine, tools, &cel, dabs, None).expect("a rub");
        met
    }

    fn land_blur(
        &mut self,
        asked: &[Asked],
        cover: Cover,
        compared: bool,
    ) -> Vec<(Change, Option<TileAt>)> {
        let blurs = self.blurs.as_ref().expect("a rub first");
        let kit = (blurs, &self.composite, &mut self.pool, self.cel);
        self.stroke.land_blur(self.engine, kit, asked, cover, compared).expect("a landing")
    }

    /// The tile the blur makes at (`column`, `row`), `under` the cel's.
    fn finished(&mut self, column: i32, row: i32, under: Option<TileAt>) -> Vec<u8> {
        let landed = self.land_blur(&[asked(column, row, under)], WHOLE_COVER, false);
        self.read(landed[0].1.expect("a slot"))
    }
}

/// `tiles`, sorted: a rub meets them in the order its windows walk.
fn sorted(mut tiles: Vec<(i32, i32)>) -> Vec<(i32, i32)> {
    tiles.sort_unstable();
    tiles
}

const INK: [u8; 4] = [255, 255, 255, 255];

#[test]
fn a_blur_reads_three_radii_past_its_dab() {
    assert_eq!(window_of([10, 20, 30, 40], 3), Some([1, 11, 39, 49]));
    assert_eq!(window_of([10, 20, 30, 40], 0), None);
}

#[test]
fn a_rub_meets_every_tile_its_window_reads() {
    let mut f = fixture();
    // Its window is on (0, 0) alone.
    assert_eq!(f.rub(&[rubbing([60, 60, 68, 68])], |_| None), vec![(0, 0)]);
    // Six pixels past its right edge is past the tile's, and six above
    // its top edge past the row's.
    let met = f.rub(&[rubbing([124, 2, 128, 8])], |_| None);
    assert_eq!(sorted(met), vec![(0, -1), (1, -1), (1, 0)]);
}

#[test]
fn a_dab_of_no_area_meets_no_tile() {
    let mut f = fixture();
    assert!(f.rub(&[rubbing([60, 60, 68, 60])], |_| None).is_empty());
    assert!(f.rub(&[rubbing([60, 60, 60, 68])], |_| None).is_empty());
}

#[test]
fn a_tile_met_is_not_met_again() {
    let mut f = fixture();
    let dab = rubbing([60, 60, 68, 68]);
    assert_eq!(f.rub(&[dab], |_| None), vec![(0, 0)]);
    assert!(f.rub(&[dab], |_| None).is_empty());
}

#[test]
fn a_dab_that_blurs_nothing_meets_nothing() {
    let mut f = fixture();
    let second = (Dab { second: true, ..square([60, 60, 68, 68], RED) }, 2);
    let nowhere = rubbing([60, 60, 60, 68]);
    assert!(f.rub(&[second, nowhere], |_| None).is_empty());
}

#[test]
fn a_blur_of_no_radius_is_refused() {
    let mut f = fixture();
    let dab = (square([60, 60, 68, 68], RED), 0);
    assert!(f.stroke.reach_blur(f.engine, &[dab]).is_none());
}

#[test]
fn a_rub_reads_the_cel_it_met_across_a_tile_edge() {
    let mut f = fixture();
    let ink = f.stored(INK);
    f.rub(&[rubbing([124, 10, 128, 20])], |tile| (tile == (1, 0)).then_some(ink));
    let tile = f.finished(0, 0, None);
    // (127, 15) reads the ink of its six to the right: 18 + 15 + 10 + 6 +
    // 3 + 1 of 125 is 108.1 of 255; (124, 15) its last three: 10 of 125,
    // 20.4; and (123, 15) was not rubbed.
    assert!(pixel(&tile, 127, 15)[3].abs_diff(108) <= 1, "{:?}", pixel(&tile, 127, 15));
    assert!(pixel(&tile, 124, 15)[3].abs_diff(20) <= 1, "{:?}", pixel(&tile, 124, 15));
    assert_eq!(pixel(&tile, 123, 15), [0; 4]);
}

#[test]
fn rubs_apart_are_the_rubs_together() {
    let dabs = [rubbing([124, 10, 128, 20]), rubbing([120, 10, 128, 20])];
    let tile_of = |calls: &[&[(Dab, u32)]]| {
        let mut f = fixture();
        let ink = f.stored(INK);
        for dabs in calls {
            f.rub(dabs, |tile| (tile == (1, 0)).then_some(ink));
        }
        f.finished(0, 0, None)
    };
    let together = tile_of(&[&dabs]);
    assert_eq!(tile_of(&[&dabs[..1], &dabs[1..]]), together);
    // The second reads what the first moved: alone it leaves another.
    assert_ne!(tile_of(&[&dabs[1..]]), together);
}

#[test]
fn a_tile_the_blur_moved_nothing_on_takes_no_slot() {
    let mut f = fixture();
    let plain = f.stored(CEL_PIXEL);
    f.rub(&[rubbing([60, 60, 68, 68])], |_| Some(plain));
    let landed = f.land_blur(&[asked(0, 0, Some(plain))], WHOLE_COVER, true);
    assert_eq!(landed, vec![(Change::Same, None)]);
}

#[test]
fn a_tile_the_blur_moved_takes_a_slot_of_its_own() {
    let mut f = fixture();
    let ink = f.stored(INK);
    f.rub(&[rubbing([124, 10, 128, 20])], |tile| (tile == (1, 0)).then_some(ink));
    let landed = f.land_blur(&[asked(0, 0, None)], WHOLE_COVER, true);
    assert_eq!(landed[0].0, Change::Inked);
    assert!(landed[0].1.is_some());
}

#[test]
fn a_tile_uncompared_takes_a_slot_whatever_it_shows() {
    let mut f = fixture();
    let plain = f.stored(CEL_PIXEL);
    f.rub(&[rubbing([60, 60, 68, 68])], |_| Some(plain));
    let landed = f.land_blur(&[asked(0, 0, Some(plain))], WHOLE_COVER, false);
    assert_eq!(landed[0].0, Change::Inked);
    assert_eq!(pixel(&f.read(landed[0].1.expect("a slot")), 64, 64), CEL_PIXEL);
}

#[test]
fn the_cover_is_how_far_a_pixel_moves() {
    let mut f = fixture();
    let ink = f.stored(INK);
    f.rub(&[rubbing([124, 10, 128, 20])], |tile| (tile == (1, 0)).then_some(ink));
    let half = Cover { opacity: WHOLE / 2, mask: None };
    let landed = f.land_blur(&[asked(0, 0, None)], half, false);
    let alpha = pixel(&f.read(landed[0].1.expect("a slot")), 127, 15)[3];
    assert!(alpha.abs_diff(54) <= 1, "{alpha}");
}

#[test]
fn a_landing_asked_nothing_lands_nothing() {
    let mut f = fixture();
    f.rub(&[rubbing([60, 60, 68, 68])], |_| None);
    assert!(f.land_blur(&[], WHOLE_COVER, true).is_empty());
}

#[test]
fn a_tile_the_blur_never_read_is_refused() {
    let mut f = fixture();
    f.rub(&[rubbing([60, 60, 68, 68])], |_| None);
    let kit = (f.blurs.as_ref().unwrap(), &f.composite, &mut f.pool, f.cel);
    assert!(f.stroke.land_blur(f.engine, kit, &[asked(9, 9, None)], WHOLE_COVER, true).is_none());
}

#[test]
fn a_rub_told_of_too_few_tiles_is_refused() {
    let mut f = fixture();
    let dab = rubbing([60, 60, 68, 68]);
    assert_eq!(f.stroke.reach_blur(f.engine, &[dab]), Some(1));
    let mut blurs = Blurs::new(f.engine).expect("blurs");
    let tools = (&mut blurs, &f.composite, f.pool.pages());
    assert!(f.stroke.rub(f.engine, tools, &[], &[dab], None).is_none());
}

#[test]
fn what_the_blurs_keep_between_strokes_can_be_let_go() {
    let mut f = fixture();
    let ink = f.stored(INK);
    let dab = rubbing([124, 10, 128, 20]);
    f.rub(&[dab], |tile| (tile == (1, 0)).then_some(ink));
    let once = f.finished(0, 0, None);
    assert!(f.blurs.as_ref().unwrap().bytes() > 0);
    f.blurs.as_mut().unwrap().let_go();
    assert_eq!(f.blurs.as_ref().unwrap().bytes(), 0);
    f.rub(&[dab], |_| None);
    assert_ne!(f.finished(0, 0, None), once, "it rubs on");
}

#[test]
fn a_cleared_stroke_reads_the_cel_anew() {
    let mut f = fixture();
    let (one, other) = (f.stored(CEL_PIXEL), f.stored(RED));
    let dab = rubbing([60, 60, 68, 68]);
    f.rub(&[dab], |_| Some(one));
    let before = f.stroke.bytes();
    f.stroke.clear(f.engine);
    assert_eq!(f.stroke.bytes(), before, "its pages stay");
    assert_eq!(f.rub(&[dab], |_| Some(other)), vec![(0, 0)]);
    assert_eq!(pixel(&f.finished(0, 0, Some(other)), 64, 64), RED);
}

#[test]
fn a_stroke_that_rubbed_leaves_a_painting_one_clean_planes() {
    let mut f = fixture();
    let ink = f.stored(INK);
    f.rub(&[rubbing([60, 60, 68, 68])], |_| Some(ink));
    f.stroke.clear(f.engine);
    f.pile(&[square([10, 10, 20, 20], RED)]);
    let landed = f.land(&[asked(0, 0, None)], &NORMAL_WHOLE, false);
    let tile = f.read(landed[0].1.expect("a slot"));
    assert_eq!(pixel(&tile, 15, 15), RED);
    assert_eq!(pixel(&tile, 64, 64), [0; 4]);
}
