//! What a screen drawn whole under 100 % costs (card
//! the-galaxy-tab-canvas-went-slow-on-build-1095, 2026-11-23): a
//! measurement, no test — it asserts nothing, prints what it timed, and no
//! run of the suite takes it. By name, in release, on the machine asked
//! about:
//!
//! `cargo test --release -p gpu_engine --lib -- --ignored --nocapture what_a_screen_drawn_whole_costs`
//!
//! A Galaxy Tab's screen (3584 × 2560) drawn whole through a camera at
//! × 0.63 in Blend — what a frame of a zoom under 100 % draws
//! ([`Composite::show`](super::Composite::show)) —, over the paper alone,
//! under a row the camera finds no tile of, and under a row of each kind
//! of picture fold/cost.rs counted, every tile its own.
//!
//! 🔬What it said on the RTX 4080, the machine's measurement window open
//! (2026-11-23, three turns about, the middle of each): the paper alone
//! 0.5 ms, a row of no tile 0.5 — a step that has no tile on an output
//! tile is not walked —, a row of any kind 3.2–4.3 ms. A Galaxy Tab took
//! 43 ms for the frame of a zoom (its photographs), some twelve times the
//! 4080's for a row of one colour: what a frame under 100 % pays is a
//! row's taps themselves, some 21 a texel at × 0.63.
//!
//! ↩️TRIED AND NOT KEPT (2026-11-23): the composite's `resample_texel`
//! keeping the tile it found last between a texel's taps (a `var<private>`
//! — the plan read again only where a tap crosses into another tile).
//! Here it was within the noise: one colour +4 %, sixteen a block −11 %,
//! forty in a hundred −24 %, line art −13 %, painted +3 %. No byte
//! changed; what it saved did not pay for the state it added. Weigh it
//! again on a device whose reads of the plan cost more — by this test.

use crate::kernels::blend::mode::NORMAL;
use crate::kernels::composite::tests::{Rig, rig, surface_on, with_map};
use crate::kernels::composite::{Plan, Step, TILE, TileAt, TileSet, WHOLE};
use crate::kernels::fold::cost::{KINDS, timed};
use crate::kernels::fold::tests::tile_of;
use crate::kernels::shared::{ResampleMap, ResampleMode, words_buffer};

/// The screen's sides: the Galaxy Tab's of the photographs (its panel and
/// the room to pan, rounded up a step — the app's `EngineScreenTexture`).
const SCREEN: (u32, u32) = (3584, 2560);
/// The zoom of the photographs' frames drawn whole.
const ZOOM: f64 = 0.63;
/// The tiles a page holds.
const PAGE_TILES: u32 = 256;
const PAPER: u32 = 0xffff_ffff;

/// The canvas's tiles the screen reads at [`ZOOM`], across and down.
fn canvas_tiles() -> (u32, u32) {
    let side = |screen: u32| (f64::from(screen) / ZOOM / f64::from(TILE)).ceil() as u32;
    (side(SCREEN.0), side(SCREEN.1))
}

/// A row of every one of the canvas's tiles, tile `at`'s words
/// `words(at)` — on pages of [`PAGE_TILES`]; none where `words` is None.
fn row_of(words: impl Fn(u32) -> Option<Vec<u32>>) -> (Vec<wgpu::Buffer>, TileSet) {
    let engine = rig().engine;
    let (columns, rows) = canvas_tiles();
    let mut pages: Vec<Vec<u32>> = Vec::new();
    let tiles = (0..columns * rows)
        .map(|at| {
            let words = words(at)?;
            let (page, slot) = (at / PAGE_TILES, at % PAGE_TILES);
            if pages.len() <= page as usize {
                pages.push(Vec::new());
            }
            pages[page as usize].extend(words);
            Some(TileAt { page: page as u16, slot: slot as u16 })
        })
        .collect();
    let usage = wgpu::BufferUsages::STORAGE;
    let pages = pages.iter().map(|words| words_buffer(engine, "a row's page", words, usage)).collect();
    (pages, TileSet { x0: 0, y0: 0, columns, rows, tiles })
}

#[test]
#[ignore = "a measurement: by name, in release, with --ignored --nocapture"]
fn what_a_screen_drawn_whole_costs() {
    let Rig { engine, composite } = rig();
    let info = engine.adapter.get_info();
    let (width, height) = SCREEN;
    println!("screen cost: {} ({:?}), {width} × {height} at × {ZOOM}, Blend", info.name, info.backend);
    let scale = 1.0 / ZOOM;
    let camera = ResampleMap::new([scale, 0.0, 0.0, 0.0, scale, 0.0, 0.0, 0.0, 1.0], 1.0, ResampleMode::Blend, width, height)
        .expect("a camera lands");
    let surface = surface_on(engine, SCREEN, wgpu::TextureFormat::Rgba8Unorm);
    let whole = [0, 0, width, height];
    let paper = Step::Solid { colour: PAPER, rect: [0, 0, width as i32, height as i32] };
    let over = [paper, with_map(0, camera, WHOLE, NORMAL)];
    // Every scene once before anything is said: the device's clock comes up
    // over its first seconds of work, past what a scene's own warming is —
    // the paper alone, first, took 15.5 ms so and 3.4 once the rest had run
    // (2026-11-23, this device).
    for said in [false, true] {
        let shown = |name: &str, pages: &[wgpu::Buffer], sets: &[TileSet], steps: &[Step]| {
            let plan = Plan { pages, sets, keys: &[], matrices: &[], chains: &[], steps, mask: None, stamps: None };
            let [ms] = timed([&mut || {
                composite.show(engine, &plan, &surface, whole, composite.widest()).expect("show");
            }]);
            if said {
                println!("screen cost: {name:<24} {ms:6.2} ms");
            }
        };
        shown("the paper alone", &[], &[], std::slice::from_ref(&paper));
        let (pages, set) = row_of(|_| None);
        shown("a row of no tile", &pages, &[set], &over);
        for kind in &KINDS {
            let (pages, set) = row_of(|at| Some(tile_of(at, |block| kind.count(at, block))));
            shown(kind.name, &pages, &[set], &over);
        }
    }
}
