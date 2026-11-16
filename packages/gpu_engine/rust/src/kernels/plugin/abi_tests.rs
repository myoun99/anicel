//! The plugin's C ABI: what the app hands it reaches the plugin as the
//! words prelude.wgsl names, and what the plugin draws over a chain's
//! tiles comes back on them at the app's place. The device's run against
//! the CPU's is tests.rs's.

use super::Plugin;
use super::abi::{
    Asked, CHANNELS, FIXED, WHOLE, gpu_engine_plugin_free, gpu_engine_plugin_made_free, gpu_engine_plugin_made_land,
    gpu_engine_plugin_open, gpu_engine_plugin_reach, gpu_engine_plugin_reads_the_moment,
    gpu_engine_plugin_render_read,
};
use super::tests::hashed;
use crate::kernels::chain::tests::put_over;
use crate::kernels::chain::{ChainRead, Kept, each_pixel, picture_bytes};
use crate::kernels::composite::{TILE, TILE_BYTES, TileAt};
use crate::kernels::effects::blur::TileRect;
use crate::kernels::pool::Pool;
use crate::kernels::shared::{le_bytes, le_words};
use crate::testing::{first_engine, last_error, read_buffer};

const INVERT: &str = include_str!("../../../native/fx_wgsl/fixtures/invert.wgsl");
const BLUR: &str = include_str!("../../../native/fx_wgsl/fixtures/blur.wgsl");
const LAYER: &str = include_str!("../../../native/fx_wgsl/fixtures/layer.wgsl");
const ENDLESS: &str = include_str!("../../../native/fx_wgsl/fixtures/endless.wgsl");
const FLOAT: &str = include_str!("../../../native/fx_wgsl/fixtures/float.wgsl");

/// Writes what it is handed along its row from its left, a word in two
/// pixels — its low half, then its high, in red and green, opaque: a pixel
/// no alpha shows is laid clear — the moment's four, then each value's
/// four words.
const PROBE: &str = r"
@compute @workgroup_size(16, 1)
fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {
  let i = i32(at.x) / 2;
  var word = 0;
  switch i {
    case 0: { word = anicel_frame(); }
    case 1: { word = anicel_time(); }
    case 2: { word = anicel_rate(); }
    case 3: { word = anicel_scale(); }
    default: { word = anicel_value((i - 4) / 4, (i - 4) % 4); }
  }
  let bits = bitcast<u32>(word);
  let half = select(bits & 0xffffu, bits >> 16u, at.x % 2u == 1u);
  anicel_out(half | 0xff000000u);
}

fn anicel_reach() -> u32 {
  return 0u;
}
";

/// Writes every other pixel of its row, from its left, and leaves the rest.
const EVERY_OTHER: &str = r"
@compute @workgroup_size(16, 1)
fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {
  if (at.x % 2u == 0u) {
    anicel_out(0xffffffffu);
  }
}

fn anicel_reach() -> u32 {
  return 0u;
}
";

/// Reaches as far as value 0 says, a turn of its loop a pixel.
const COUNTED_REACH: &str = r"
@compute @workgroup_size(16, 16)
fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {
  anicel_out(0u);
}

fn anicel_reach() -> u32 {
  var reach = 0u;
  for (var turn = 0; turn < anicel_value(0, 0); turn++) {
    reach += 1u;
  }
  return reach;
}
";

/// A moment: frame 7, 1.25 s, 24 frames a second, half scale.
const MOMENT: [f64; 4] = [7.0, 1.25, 24.0, 0.5];

/// More than any of these plugins spends.
const PLENTY: u32 = 1 << 30;

/// A plugin opened through the ABI, freed when dropped.
struct Opened(*mut Plugin);

impl Opened {
    fn new(source: &[u8], cut: bool) -> Result<Self, String> {
        // SAFETY: the engine is live; `source` holds its length.
        let plugin = unsafe { gpu_engine_plugin_open(first_engine(), source.as_ptr(), source.len(), cut) };
        if plugin.is_null() { Err(last_error()) } else { Ok(Opened(plugin)) }
    }

    fn of(source: &str) -> Self {
        Opened::new(source.as_bytes(), true).expect("the fixture opens")
    }

    fn reach(&self, values: &[f64], kinds: &[u32], share: u32) -> Result<i64, String> {
        // SAFETY: each holds what its count says.
        let reach = unsafe {
            gpu_engine_plugin_reach(self.0, values.as_ptr(), kinds.as_ptr(), kinds.len(), MOMENT.as_ptr(), share)
        };
        if reach < 0 { Err(last_error()) } else { Ok(reach) }
    }

    /// [`Opened::render_from`], the paper at the origin of the tiles' grid.
    fn render(&self, pictures: &[([i32; 4], Vec<u32>)], values: &[f64], kinds: &[u32], share: u32) -> Result<Vec<u32>, String> {
        self.render_from([0, 0], pictures, values, kinds, share)
    }

    /// The plugin's picture of `pictures`' first over the rest as its
    /// layers, each its rect on the tiles' grid — laid on the tiles under
    /// them all as a chain keeps its read ([`ChainRead`]), the plug-in told
    /// the first's place on the paper, which lies `at` from the grid's —
    /// read back off the tiles it made at the first's place.
    fn render_from(
        &self,
        at: [i32; 2],
        pictures: &[([i32; 4], Vec<u32>)],
        values: &[f64],
        kinds: &[u32],
        share: u32,
    ) -> Result<Vec<u32>, String> {
        let engine = first_engine();
        let edges = |[left, top, width, height]: [i32; 4]| [left, top, left + width.max(0), top + height.max(0)];
        let rect = tiles_under(pictures.iter().map(|(at, _)| edges(*at)));
        let laid = |(at, pixels): &([i32; 4], Vec<u32>)| put_over(engine, rect, edges(*at), &le_bytes(pixels));
        let Some(tiles) = laid(&pictures[0]) else {
            return Err(last_error());
        };
        let rows = pictures[1..].iter().map(laid).collect::<Option<Vec<_>>>().ok_or_else(last_error)?;
        let [left, top, width, height] = pictures[0].0;
        let told = [left - at[0], top - at[1], width, height];
        let read = ChainRead::kept_as(Kept { tiles, rect, rows });
        let mut made_rect = [0; 4];
        // SAFETY: each holds what its count says, the engine is live and
        // the plugin was opened on it.
        let made = unsafe {
            gpu_engine_plugin_render_read(
                self.0,
                engine,
                &read,
                told.as_ptr(),
                at.as_ptr(),
                values.as_ptr(),
                kinds.as_ptr(),
                kinds.len(),
                MOMENT.as_ptr(),
                share,
                made_rect.as_mut_ptr(),
            )
        };
        if made.is_null() {
            return Err(last_error());
        }
        // SAFETY: made above, freed below.
        let (bytes, at) = unsafe { (read_buffer(engine, &(*made).tiles), (*made).rect) };
        // SAFETY: made above.
        unsafe { gpu_engine_plugin_made_free(made) };
        assert_eq!(made_rect, [at.x0, at.y0, at.columns as i32, at.rows as i32], "the rect it says is its own");
        assert_eq!(at, rect, "it made the chain's rectangle of tiles");
        let picture = edges(pictures[0].0);
        let mut drawn = vec![0u8; picture_bytes(picture)];
        each_pixel(picture, rect, |to, from| drawn[to..to + 4].copy_from_slice(&bytes[from..from + 4]));
        Ok(le_words(&drawn))
    }
}

/// The fewest tiles under every one of `pictures`' edges — one at the
/// origin's for none.
fn tiles_under(pictures: impl Iterator<Item = [i32; 4]>) -> TileRect {
    let side = TILE as i32;
    let ([left, top], [right, bottom]) = pictures.fold(([0, 0], [1, 1]), |([l, t], [r, b]), [left, top, right, bottom]| {
        ([l.min(left), t.min(top)], [r.max(right), b.max(bottom)])
    });
    let (x0, y0) = (left.div_euclid(side), top.div_euclid(side));
    let (x1, y1) = ((right - 1).div_euclid(side) + 1, (bottom - 1).div_euclid(side) + 1);
    TileRect { x0, y0, columns: (x1 - x0) as u32, rows: (y1 - y0) as u32 }
}

impl Drop for Opened {
    fn drop(&mut self) {
        // SAFETY: opened, let go of once.
        unsafe { gpu_engine_plugin_free(self.0) };
    }
}

/// The inverse of `pixel`'s colour, its alpha kept: invert.wgsl's.
fn inverted(pixel: u32) -> u32 {
    pixel & 0xFF00_0000 | !pixel & 0x00FF_FFFF
}

/// `pixel` as the run lays what a plug-in drew on the tiles: nothing where
/// no alpha shows it.
fn as_laid(pixel: u32) -> u32 {
    if pixel >> 24 == 0 { 0 } else { pixel }
}

#[test]
fn a_plugin_opens_from_its_wgsl_or_says_why() {
    assert!(Opened::new(INVERT.as_bytes(), true).is_ok(), "{}", last_error());
    assert_eq!(Opened::new(&[0x66, 0xFF, 0x6E], true).err().as_deref(), Some("the plugin's source is no UTF-8"));
    let refusal = fx_wgsl::open(FLOAT).err().expect("the check refuses a float").to_string();
    assert!(refusal.starts_with(|c: char| c.is_ascii_digit()), "the refusal names its line: {refusal}");
    assert_eq!(Opened::new(FLOAT.as_bytes(), true).err(), Some(refusal));
}

#[test]
fn the_open_says_whether_the_device_cuts_the_plugin() {
    // 🗣️-Q18 「끊지 않음」: compiled with no charge, its reach still cut on
    // the CPU by the share it is handed.
    for cut in [true, false] {
        let opened = Opened::new(ENDLESS.as_bytes(), cut).expect("opens");
        // SAFETY: opened just now, freed as `opened` drops.
        let kernel = unsafe { &(*opened.0).kernel };
        assert_eq!(kernel.cut(), cut);
        let plugin_part = kernel.source().split(fx_wgsl::PRELUDE).next().expect("the plugin comes first");
        assert_eq!(plugin_part.contains("anicel_host_spend("), cut, "{plugin_part}");
        assert!(opened.reach(&[], &[], 1_000).is_err(), "cut: {cut}");
    }
}

#[test]
fn the_open_says_whether_the_plugin_reads_the_moment() {
    // card a-plugin-step-is-keyed-by-a-moment-it-may-not-read: the app
    // signs a run of one that does not alike at every frame.
    let fixtures = [
        ("the invert", INVERT, false),
        ("the blur", BLUR, false),
        ("the probe", PROBE, true),
    ];
    for (what, source, reads) in fixtures {
        let opened = Opened::of(source);
        // SAFETY: opened just now, freed as `opened` drops.
        assert_eq!(unsafe { gpu_engine_plugin_reads_the_moment(opened.0) }, reads, "{what}");
    }
}

#[test]
fn the_moment_and_every_kind_of_value_reach_the_plugin_as_its_words() {
    let values = [-1.0, 2.0, 0.0, 1.0, 1.5, -0.25, 0.0, 100.0, 1.0, 0.5, 0.0, 128.0 / 255.0];
    let kinds = [WHOLE, FIXED, CHANNELS];
    let drawn = Opened::of(PROBE).render(&[([5, -3, 32, 1], vec![0; 32])], &values, &kinds, PLENTY);
    // A word in two pixels: its low half, then its high.
    let halves = drawn.expect("it draws");
    let words: Vec<i32> = halves.chunks_exact(2).map(|half| (half[0] & 0xFFFF | half[1] << 16) as i32).collect();
    #[rustfmt::skip]
    let handed = [
        7, 5 << 14, 24 << 16, 1 << 15,
        -1, 2, 0, 1,
        3 << 15, -(1 << 14), 0, 100 << 16,
        65535, 32768, 0, 32896,
    ];
    assert_eq!(words, handed);
}

#[test]
fn a_word_past_an_i32_is_refused_by_name() {
    let refused = |values: &[f64], kinds: &[u32], moment: [f64; 4]| {
        assert_eq!(Asked::new(values, kinds, moment), None);
        last_error()
    };
    assert!(Asked::new(&[32767.0, 0.0, 0.0, 0.0], &[FIXED], MOMENT).is_some());
    assert_eq!(refused(&[0.0, 0.0, 32768.0, 0.0], &[FIXED], MOMENT), "value 0 is 32768, past an i32 in Q.16");
    assert_eq!(
        refused(&[0.0, 0.0, 0.0, 0.0, 3e9, 0.0, 0.0, 0.0], &[WHOLE, WHOLE], MOMENT),
        "value 1 is 3000000000, past an i32 in Q.0"
    );
    assert_eq!(refused(&[f64::NAN, 0.0, 0.0, 0.0], &[WHOLE], MOMENT), "value 0 is NaN, past an i32 in Q.0");
    assert_eq!(refused(&[0.0; 4], &[3], MOMENT), "value 0 is of kind 3, none the host knows");
    assert_eq!(refused(&[], &[], [0.0, 40000.0, 24.0, 1.0]), "the time is 40000, past an i32 in Q.16");
    assert_eq!(refused(&[], &[], [3e9, 0.0, 24.0, 1.0]), "the frame's number is 3000000000, past an i32 in Q.0");
}

#[test]
fn the_reach_reads_its_value_as_its_kind_says() {
    let blur = Opened::of(BLUR);
    assert_eq!(blur.reach(&[3.4, 0.0, 0.0, 0.0], &[FIXED], PLENTY), Ok(3));
    assert_eq!(blur.reach(&[3.4, 0.0, 0.0, 0.0], &[WHOLE], PLENTY), Ok(0), "3 is 3 / 65536 pixels in Q.16");
    let cut = Opened::of(ENDLESS).reach(&[], &[], 100_000);
    assert_eq!(cut, Err("the plugin's reach spent its share of 100000 and was cut".into()));
}

/// The fewest share `yes` answers yes on — no on none, yes on 2^20.
fn fewest_that(yes: impl Fn(u32) -> bool) -> u32 {
    let (mut low, mut high) = (0, 1 << 20);
    assert!(yes(high) && !yes(low));
    while high - low > 1 {
        let mid = (low + high) / 2;
        if yes(mid) { high = mid } else { low = mid }
    }
    high
}

#[test]
fn each_pixel_spends_the_share_it_is_given_however_many_there_are() {
    // 🗣️an-endless-plugin-stalls-the-app-Q19: the same blur draws on the
    // same share at any size — none of it is the limit over the pixels.
    let blur = Opened::of(BLUR);
    let radius = [2.0, 0.0, 0.0, 0.0];
    let draws = |width: i32, share: u32| {
        let picture = ([0, 0, width, 1], vec![0xFF80_4020; width as usize]);
        blur.render(&[picture], &radius, &[FIXED], share).is_ok()
    };
    // The fewest a pixel of this blur spends: one pixel draws on it.
    let fewest = fewest_that(|share| draws(1, share));
    assert!(draws(300, fewest), "three hundred pixels, each the share one spent");
    assert!(!draws(300, fewest - 1), "three hundred pixels, a charge short");
}

#[test]
fn the_reach_spends_the_share_it_is_given() {
    let counted = Opened::of(COUNTED_REACH);
    let answers = |share: u32| counted.reach(&[40.0, 0.0, 0.0, 0.0], &[WHOLE], share);
    let fewest = fewest_that(|share| answers(share).is_ok());
    assert_eq!(answers(fewest), Ok(40));
    assert!(answers(fewest - 1).is_err(), "a charge short");
}

#[test]
fn a_render_lays_its_picture_and_layers_where_the_app_placed_them() {
    let (rect, input) = ([5, -3, 37, 23], hashed(37 * 23, 4));
    let drawn = Opened::of(INVERT).render(&[(rect, input.clone())], &[], &[], PLENTY);
    assert_eq!(drawn, Ok(input.iter().map(|&pixel| as_laid(inverted(pixel))).collect::<Vec<_>>()));

    // The input clear on every third pixel, a layer the value does not
    // name, and the one it names in slot 1: 4 by 4 at (5, 1), over part of
    // the input.
    let on = [2, 3, 6, 5];
    let input: Vec<u32> = hashed(30, 5)
        .iter()
        .enumerate()
        .map(|(at, &pixel)| if at % 3 == 0 { pixel & 0x00FF_FFFF } else { pixel | 0x0100_0000 })
        .collect();
    let (other, shown) = (([2, 3, 6, 5], hashed(30, 7)), ([5, 1, 4, 4], hashed(16, 6)));
    let pictures = [(on, input.clone()), other, shown.clone()];
    let drawn = Opened::of(LAYER).render(&pictures, &[1.0, 0.0, 0.0, 0.0], &[WHOLE], PLENTY).expect("it draws");
    for (at, (&own, &drew)) in input.iter().zip(&drawn).enumerate() {
        let (x, y) = (2 + at as i32 % 6, 3 + at as i32 / 6);
        let (column, row) = (x - 5, y - 1);
        let behind = if (0..4).contains(&column) && (0..4).contains(&row) { shown.1[(row * 4 + column) as usize] } else { 0 };
        assert_eq!(drew, if own >> 24 == 0 { as_laid(behind) } else { own }, "at ({x}, {y})");
    }
}

/// The plug-in is told its picture's place on the paper, which lies `at`
/// from the tiles' grid: it reads the tiles where they lie, and what it
/// made lies there.
#[test]
fn a_render_told_the_papers_place_reads_the_tiles_where_they_lie() {
    let (rect, input) = ([5, -3, 37, 23], hashed(37 * 23, 4));
    let drawn = Opened::of(INVERT).render_from([-6, 4], &[(rect, input.clone())], &[], &[], PLENTY);
    assert_eq!(drawn, Ok(input.iter().map(|&pixel| as_laid(inverted(pixel))).collect::<Vec<_>>()));
}

#[test]
fn a_pixel_the_render_writes_none_of_is_transparent() {
    let drawn = Opened::of(EVERY_OTHER).render(&[([0, 0, 16, 1], vec![0xFF00_00FF; 16])], &[], &[], PLENTY);
    let every_other: Vec<u32> = (0..16).map(|x| if x % 2 == 0 { u32::MAX } else { 0 }).collect();
    assert_eq!(drawn, Ok(every_other));
}

#[test]
fn an_endless_render_is_cut_and_says_so() {
    let drawn = Opened::of(ENDLESS).render(&[([0, 0, 4, 4], vec![0; 16])], &[], &[], 1_000_000);
    assert_eq!(drawn, Err("the plugin spent each pixel's share of 1000000 and was cut".into()));
}

#[test]
fn a_picture_of_a_negative_side_is_refused() {
    let invert = Opened::of(INVERT);
    let pictures = [([0, 0, -1, 4], vec![])];
    assert_eq!(invert.render(&pictures, &[], &[], PLENTY), Err("a picture -1 by 4".into()));
    let pictures = [([0, 0, 4, -1], vec![])];
    assert_eq!(invert.render(&pictures, &[], &[], PLENTY), Err("a picture 4 by -1".into()));
    assert_eq!(invert.render(&[([0, 0, 0, 0], vec![])], &[], &[], PLENTY), Ok(vec![]));
}

/// What a plug-in made lands in the pool as it lies: each tile asked, in
/// whatever order, in a fresh slot of the cel holding that tile's bytes —
/// and a tile off its rectangle is refused, by its place.
#[test]
fn what_it_made_lands_tile_by_tile_where_it_lies() {
    let engine = first_engine();
    let side = TILE as i32;
    // Across a seam of tiles both ways.
    let (rect, picture) = (TileRect { x0: 0, y0: 0, columns: 2, rows: 2 }, [side - 5, side - 3, 9, 7]);
    let [left, top, width, height] = picture;
    let edges = [left, top, left + width, top + height];
    let tiles = put_over(engine, rect, edges, &le_bytes(&hashed(63, 8))).expect("laid");
    let read = ChainRead::kept_as(Kept { tiles, rect, rows: Vec::new() });
    let invert = Opened::of(INVERT);
    let mut at = [0; 4];
    // SAFETY: each holds what its count says, the engine is live and the
    // plugin was opened on it.
    let made = unsafe {
        gpu_engine_plugin_render_read(
            invert.0,
            engine,
            &read,
            picture.as_ptr(),
            [0, 0].as_ptr(),
            [].as_ptr(),
            [].as_ptr(),
            0,
            MOMENT.as_ptr(),
            PLENTY,
            at.as_mut_ptr(),
        )
    };
    assert!(!made.is_null(), "{}", last_error());
    // SAFETY: made above, freed below.
    let whole = read_buffer(engine, unsafe { &(*made).tiles });
    let mut pool = Pool::new(engine, u64::MAX).expect("pool");
    let cel = pool.cel();
    let land = |pool: &mut Pool, asks: &[i32]| {
        let count = asks.len() / 2;
        let (mut places, mut changes) = (vec![0; count], vec![0; count]);
        // SAFETY: every pointer is live, `asks` holds `2 × count` and the
        // rest `count`.
        let landed = unsafe {
            gpu_engine_plugin_made_land(
                engine,
                made,
                pool,
                cel.0,
                asks.as_ptr(),
                count,
                places.as_mut_ptr(),
                changes.as_mut_ptr(),
            )
        };
        (landed, places, changes)
    };

    // Right to left, then up: a tile is found by its place, not its turn.
    let asks = [1, 1, 0, 1, 1, 0, 0, 0];
    let (landed, places, changes) = land(&mut pool, &asks);
    assert_eq!(landed, 4, "{}", last_error());
    assert!(changes.iter().all(|&change| change == 1), "each landed inked");
    let places: Vec<TileAt> = places.into_iter().map(|word| TileAt::of_word(word).expect("a slot")).collect();
    let tile = TILE_BYTES as usize;
    let mut bytes = vec![0; places.len() * tile];
    pool.read(engine, &places, &mut bytes).expect("read");
    for (turn, ask) in asks.chunks_exact(2).enumerate() {
        let index = rect.index_of(ask[0], ask[1]).expect("on the rectangle");
        let (landed, made) = (&bytes[turn * tile..][..tile], &whole[index * tile..][..tile]);
        assert!(landed == made, "tile {ask:?} landed as another");
    }

    assert_eq!(land(&mut pool, &[2, 0]).0, -1);
    assert_eq!(last_error(), "tile (2, 0) is off the 2 × 2 tiles at (0, 0)");
    // Off it down as well, and before its first tile.
    assert_eq!(land(&mut pool, &[0, 2]).0, -1);
    assert_eq!(last_error(), "tile (0, 2) is off the 2 × 2 tiles at (0, 0)");
    assert_eq!(land(&mut pool, &[-1, 1]).0, -1);
    assert_eq!(last_error(), "tile (-1, 1) is off the 2 × 2 tiles at (0, 0)");
    // SAFETY: made above.
    unsafe { gpu_engine_plugin_made_free(made) };
}
