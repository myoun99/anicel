//! The dab kernel — 3단계 (gpu-canonical-store ⑥, 1a (3/3 보탬)): a
//! stroke's dabs piled on its 16-bit plane on the GPU, and the plane's bytes
//! beside it. `dab.wgsl` has the arithmetic and `pile.wgsl` the walk; this file turns
//! the app's numbers into the integers it reads — the one place a float
//! becomes one (1a 보탬 「넘겨받기」). Rust never fuses a multiply and an
//! add, and each number here is one rounding of one product, so every
//! device makes the same integers.
//!
//! It lays a square dab, a round tip — its profile along the radius, or a
//! small circle's square tables, turned and squeezed where it is an
//! ellipse — and a bitmap tip, turned and squeezed the same way; the edge,
//! the ceiling, the paper, the share and the level a dab settles at, over
//! and erase; and a second tip, whose dabs pile on a plane of their own,
//! alpha alone, the stroke's bytes then the view of the two planes. The
//! blur brush's dab (`blur`) reads its coverage off the same records. A
//! stamp dab — pixels laid 1:1, a fill's, an erase's, a moved or warped
//! selection's (`stamp`) — piles nothing: it is a stroke row of its own.
//!
//! A texture — a tip's or the paper's — goes to the GPU once and stays on
//! the plan while piles read it: a pile sends only its own words. (Sent
//! every frame, a 256-texel tip cost three times the dabs it was laid by,
//! 11-05.)
//!
//! A stroke's tiles are kept as the pool keeps a stored tile, a tile a slot
//! of a page (shared/pages.rs; 캔버스 베이스 11-06 04:18, (가)): its planes,
//! its view and its second plane each on a page of their own, at the same
//! page and slot. A binding holds 128 MB on some devices, and one dab of
//! 2000 reaches 1,089 tiles of 128 KB. A pass binds the pages of a run of
//! the tiles (shared `runs`).

// ⏳Nothing outside the tests calls it until the app's connection round,
// which 관제 opens (gpu-canonical-store 21:41).
#![cfg_attr(not(test), allow(dead_code))]

pub(crate) mod abi;
pub(crate) mod blur;
pub(crate) mod landing;
pub(crate) mod stamp;
pub(crate) mod stroke;
#[cfg(test)]
mod tests;

use std::cell::Cell;
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::{BLEND_WGSL, mode};
use crate::kernels::composite::TileAt;
use crate::kernels::shared::{
    Encoded, ISQRT_WGSL, Own, Pages, TILE_WGSL, encode, pipeline, range, runs, sixteen_bit, whole,
};

/// A tile's side in pixels (1a ①).
const TILE: i32 = 128;
const HEAD_WORDS: usize = 7;
const TILE_WORDS: usize = 7;
const DAB_WORDS: usize = 29;
const NO_TABLE: u32 = u32::MAX;
/// pile.wgsl's: the plan, the run, then the pages — of the planes, of their
/// view and of the second plane, as many of each.
const PILE_PAGES_AT: u32 = 2;

// A dab's flags, as dab.wgsl reads them (the numbers were the C dab
// kernel's QA_DAB_FLAG_* and outlived it).
const ERASE: u32 = 1;
const ROUND: u32 = 2;
const THRESHOLD: u32 = 32;
const EDGE_HELD: u32 = 128;
const SECOND: u32 = 256;

/// A scale is kept under this, so a distance under 2^15 times it stays in
/// u32 (1a 보탬 기하).
const SCALE_BOUND: f64 = 131072.0;

/// A round tip's two tables and how they are read — `RoundTipProfile`'s
/// numbers as the app builds them.
pub(crate) struct RoundProfile<'a> {
    /// What a pixel lays, entry by entry, on 0..=1.
    pub(crate) coverage: &'a [f64],
    /// What of it piles.
    pub(crate) pile: &'a [f64],
    /// Entries per canvas pixel.
    pub(crate) scale: f64,
    /// Nothing at or past this distance — along each axis where the tables
    /// are square.
    pub(crate) reach: f64,
    /// At or within it a pixel lays 1, all of it piling; under 0 for none.
    pub(crate) inner: f64,
    /// Entries a row holds where the tables are square, or 0.
    pub(crate) row_length: u32,
}

/// A bitmap the kernel reads — a tip's or the paper's: `side` texels a
/// side, row after row, on the 16-bit scale. Made once; every pile that
/// reads it after the first finds it on the GPU.
pub(crate) struct Texture {
    /// Which texture it is, for the plan to know it again.
    id: u64,
    side: u32,
    words: Vec<u32>,
}

impl Texture {
    /// `texels` on 0..=1, row after row — or nothing, where the texels
    /// don't fill the side or the side is past what the integers hold: a
    /// tip's t = 2(u + R)·side and the paper's 2^16 parts a texel stay in
    /// u32 to a side of 16384 (1a 보탬). The paper wraps by its side, so
    /// a texture has one.
    pub(crate) fn new(texels: &[f64], side: u32) -> Option<Texture> {
        if side == 0 || side > 16384 || texels.len() != side as usize * side as usize {
            return fail(format!("a texture of side {side} and {} texels", texels.len()));
        }
        static MADE: AtomicU64 = AtomicU64::new(0);
        Some(Texture {
            id: MADE.fetch_add(1, Ordering::Relaxed),
            side,
            words: texels.iter().map(|&texel| sixteen_bit(texel)).collect(),
        })
    }
}

/// What a dab covers before its edge.
#[derive(Clone, Copy)]
pub(crate) enum Shape<'a> {
    /// All of its region.
    Square,
    Round(&'a RoundProfile<'a>),
    /// A bitmap over [-radius, radius] each way of the tip's own frame.
    Tip { texture: &'a Texture, radius: f64 },
}

/// The paper a stroke is drawn on (`BrushDab.texture*`): its texture,
/// tiled from the canvas's origin at `scale` px a texel, and how a dab
/// meets it — 高さ, its height cutting the coverage (`paperHeightCoverage`),
/// or else multiplying it.
pub(crate) struct Paper<'a> {
    pub(crate) texture: &'a Texture,
    pub(crate) scale: f64,
    pub(crate) height: bool,
}

/// A stroke's second tip (`BrushSecondStroke`, `dualViewAlpha`): the
/// plane its dabs pile on — alpha alone, a word a pixel, on pages as the
/// planes, a tile at its page and slot —, and the view the stroke shows of
/// the two: the second's
/// level over the first's alpha by `mode`, the C engine's stroke blend id
/// (one that blends a channel alone), at `density` (`BrushDualView`).
pub(crate) struct Second<'a> {
    pub(crate) plane: &'a [wgpu::Buffer],
    pub(crate) mode: u32,
    pub(crate) density: f64,
}

/// The modes blend.wgsl's `blend_channel` reads as themselves: not behind,
/// nor the six that mix the three channels, which a level alone has none
/// of.
fn blends_a_channel(id: u32) -> bool {
    id <= mode::NORMAL && !matches!(id, mode::BEHIND | mode::DARKER_COLOR..=mode::LUMINOSITY)
}

/// How a round or bitmap tip turns and squeezes (`BrushDabTipGeometry`):
/// its frame's cosine and sine, and its minor axis over its major.
#[derive(Clone, Copy)]
pub(crate) struct Turn {
    pub(crate) cos: f64,
    pub(crate) sin: f64,
    pub(crate) roundness: f64,
}

impl Turn {
    /// A tip that does not turn or squeeze — a circle's.
    pub(crate) const STRAIGHT: Turn = Turn { cos: 1.0, sin: 0.0, roundness: 1.0 };
}

/// The brush's edge (`brushDabEdgeLaw`).
#[derive(Clone, Copy)]
pub(crate) enum Edge {
    /// 없음: a cut at half.
    Threshold,
    /// A contrast about half; 1 leaves the coverage as it is.
    Contrast(f64),
}

/// A dab as the app has it (`BrushDabPlan`).
#[derive(Clone, Copy)]
pub(crate) struct Dab<'a> {
    pub(crate) centre: [f64; 2],
    /// The pixels it may touch, [left, top, right, bottom).
    pub(crate) region: [i32; 4],
    /// Red, green, blue, and the colour's own alpha.
    pub(crate) colour: [u8; 4],
    pub(crate) opacity: f64,
    pub(crate) flow: f64,
    pub(crate) edge: Edge,
    /// Whether the tip holds an edge that does not pile (`tipHoldsAnEdge`).
    pub(crate) edge_held: bool,
    pub(crate) erase: bool,
    /// Whether it is the second tip's (`BrushDab.second`): it piles on the
    /// second plane, and never erases.
    pub(crate) second: bool,
    pub(crate) shape: Shape<'a>,
    pub(crate) turn: Turn,
    /// The table it lays its share through, 1026 entries, or none.
    pub(crate) evening: Option<&'a [f64]>,
    /// How much of the paper it takes (`textureDensity`), where the stroke
    /// has paper — or none, a dab with no texture: a second tip's
    /// (`BrushSecondStroke` gives it none).
    pub(crate) density: Option<f64>,
}

/// A tile of the stroke: its column and row on the canvas's grid, and where
/// it is kept — a page of the stroke's planes, a slot in it, as the pool
/// keeps a stored tile (캔버스 베이스 11-06 03:36). Its view, and its
/// second plane where the stroke has one, are at the same page and slot.
#[derive(Clone, Copy)]
pub(crate) struct StrokeTile {
    pub(crate) column: i32,
    pub(crate) row: i32,
    pub(crate) at: TileAt,
}

/// The dab kernel: its walk, compiled for the pages a pass binds, and the
/// plan the walk reads.
pub(crate) struct Dabs {
    /// The walk binding one page of each a pass, as a run of tiles on one
    /// goes — nearly every pile —, and binding as many as the device lets.
    /// The second of two such choices — the other is the blur brush's dab
    /// (blur.rs's `Blurs::one`): they stay apart until a third comes (rule
    /// of three, CLAUDE.md absolute rule 1).
    one: Piles,
    widest: Piles,
    plans: Plans,
}

/// The walk, compiled for the pages a pass of it binds: of the planes, of
/// their view and of the second plane, a page of each at the same k.
struct Piles {
    planes: Pages,
    view: Pages,
    levels: Pages,
    pipeline: wgpu::ComputePipeline,
}

impl Piles {
    /// Binding no more than `most` pages of each a pass — or nothing, where
    /// the device leaves it none: past the plan and the run's words, a
    /// third of what a stage binds goes to each. Each set counts the stage's
    /// other buffers as well, which a third leaves room for already, so no
    /// test tells its uniform from none (mutant c05, 11-06).
    fn new(engine: &Engine, most: usize) -> Option<Self> {
        let paged = |set: u32, each: usize, name| {
            let own = Own { storage: 1 + 2 * each as u32, uniform: 1 };
            let first = PILE_PAGES_AT + set * each as u32;
            Some(Pages::writable(engine, own, first, each)?.named(name))
        };
        let widest = Pages::room(engine, Own { storage: 1, uniform: 1 }) / 3;
        let planes = paged(0, widest.min(most), "planes")?;
        let each = planes.per_pass();
        let (view, levels) = (paged(1, each, "view")?, paged(2, each, "levels")?);
        let paged = [planes.source(), view.source(), levels.source()];
        let mut sources = vec![ISQRT_WGSL, BLEND_WGSL, TILE_WGSL, include_str!("dab.wgsl")];
        sources.extend(paged.iter().map(String::as_str));
        sources.push(include_str!("pile.wgsl"));
        Some(Self { pipeline: pipeline(engine, &sources, "walk"), planes, view, levels })
    }
}

/// A plan kept from use to use: its head and the last use's own words from
/// its start, and the textures on it at its top, each placed under the one
/// before. A plan made anew lays what a kept one lays, so no test here tells
/// keeping from starting over sooner or from placing again (mutants o07,
/// o08, 11-06): keeping is for the writes it saves (`write`).
struct Plans {
    buffer: Option<wgpu::Buffer>,
    /// The words it holds.
    capacity: usize,
    /// Each texture on it, by id, at its place.
    placed: HashMap<u64, u32>,
    /// Where the textures on it begin.
    floor: usize,
}

impl Plans {
    fn new() -> Self {
        // No room under a floor of 0: the first use makes the buffer.
        Self { buffer: None, capacity: 0, placed: HashMap::new(), floor: 0 }
    }

    /// Writes the plan of `dabs` on `tiles` over `paper`, with the stroke's
    /// `second` tip where it has one, and after it the words `more` makes
    /// of it; gives the buffer that holds it.
    fn write(
        &mut self,
        engine: &Engine,
        tiles: &[StrokeTile],
        dabs: &[Dab],
        paper: Option<&Paper>,
        second: Option<&Second>,
        more: impl Fn(&Plan) -> Option<Vec<u32>>,
    ) -> Option<&wgpu::Buffer> {
        // The head and the use's own words go from the plan's start, so one
        // write sends both: a second write cost a pile 8 µs of some 107 to
        // 129 (11-06, the main PC, by turns — wgpu makes a staging buffer a
        // write).
        // The textures the plan reads that are not on it go under the ones
        // that are; where they would meet the use's words, the plan starts
        // over with the use's own, at twice what it takes.
        let textures = textures_of(dabs, paper);
        let planned_with_more = |placed: &HashMap<u64, u32>| {
            let mut plan = planned(tiles, dabs, paper, second, HEAD_WORDS, placed)?;
            let words = more(&plan)?;
            plan.frame.extend(words);
            Some(plan)
        };
        let mut placed = self.placed.clone();
        let mut floor = self.floor;
        let kept = match placing(&textures, &mut placed, &mut floor) {
            Some(fresh) => {
                let plan = planned_with_more(&placed)?;
                (HEAD_WORDS + plan.frame.len() <= floor).then_some((fresh, plan))
            }
            _ => None,
        };
        let (fresh, plan) = match kept {
            Some(kept) => kept,
            None => {
                // The textures alone at the start, only to learn what the
                // use's own words take.
                let mut ids = HashSet::new();
                let held: usize = textures
                    .iter()
                    .filter(|texture| ids.insert(texture.id))
                    .map(|texture| texture.words.len())
                    .sum();
                (placed, floor) = (HashMap::new(), held);
                placing(&textures, &mut placed, &mut floor)?;
                let words = HEAD_WORDS + planned_with_more(&placed)?.frame.len() + held;
                let most = engine.device.limits().max_storage_buffer_binding_size as usize / 4;
                if words > most {
                    return fail(format!("a plan of {words} words exceeds a binding's {most}"));
                }
                self.capacity = (2 * words).min(most);
                self.buffer = Some(engine.device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some("dab plan"),
                    size: self.capacity as u64 * 4,
                    // A uniform too: a pile's passes' own words are on it.
                    usage: wgpu::BufferUsages::STORAGE
                        | wgpu::BufferUsages::UNIFORM
                        | wgpu::BufferUsages::COPY_DST,
                    mapped_at_creation: false,
                }));
                (placed, floor) = (HashMap::new(), self.capacity);
                let fresh = placing(&textures, &mut placed, &mut floor)?;
                (fresh, planned_with_more(&placed)?)
            }
        };
        let buffer = self.buffer.as_ref()?;
        for texture in fresh {
            let at = u64::from(placed[&texture.id]) * 4;
            engine.queue.write_buffer(buffer, at, &bytes(&texture.words));
        }
        let mut words = plan.head.to_vec();
        words.extend(&plan.frame);
        engine.queue.write_buffer(buffer, 0, &bytes(&words));
        self.placed = placed;
        self.floor = floor;
        Some(buffer)
    }
}

impl Dabs {
    /// The kernel — or nothing, where the device binds too few storage
    /// buffers a stage for a page of each.
    pub(crate) fn new(engine: &Engine) -> Option<Self> {
        Some(Self {
            one: Piles::new(engine, 1)?,
            widest: Piles::new(engine, usize::MAX)?,
            plans: Plans::new(),
        })
    }

    /// Piles `dabs`, in their order, on the stroke `tiles` over `paper`, with
    /// the stroke's `second` tip where it has one, and writes each tile's
    /// bytes: `planes` two words a pixel and `view` one, a tile at its page
    /// and slot of each. Submits the work, the caller waits. A dab's pixels
    /// on a tile not among `tiles` are the caller's to have given.
    pub(crate) fn pile(
        &mut self,
        engine: &Engine,
        tiles: &[StrokeTile],
        dabs: &[Dab],
        paper: Option<&Paper>,
        second: Option<&Second>,
        (planes, view): (&[wgpu::Buffer], &[wgpu::Buffer]),
    ) -> Option<()> {
        let pages_per_pass = self.widest.planes.per_pass();
        self.pile_by(engine, tiles, dabs, (paper, second), (planes, view), pages_per_pass)
    }

    /// `pile`, a pass binding no more than `pages_per_pass` pages of each —
    /// a test's fewer than the device's, to see the runs a smaller device
    /// cuts.
    fn pile_by(
        &mut self,
        engine: &Engine,
        tiles: &[StrokeTile],
        dabs: &[Dab],
        (paper, second): (Option<&Paper>, Option<&Second>),
        (planes, view): (&[wgpu::Buffer], &[wgpu::Buffer]),
        pages_per_pass: usize,
    ) -> Option<()> {
        if tiles.is_empty() {
            return Some(());
        }
        on_pages(tiles, planes)?;
        on_pages(tiles, view)?;
        if let Some(second) = second {
            if !blends_a_channel(second.mode) {
                return fail(format!("a second tip shown by mode {}", second.mode));
            }
            on_pages(tiles, second.plane)?;
        }
        // A pass a run of the tiles, in their order: on no more pages than it
        // binds, and no more tiles than a dispatch reaches.
        let most = engine.device.limits().max_compute_workgroups_per_dimension as usize;
        let runs = runs(tiles.iter().map(|tile| Some(tile.at.page)), None, pages_per_pass, most);
        // Each tile's k: its page's binding among its run's.
        let ks: Option<Vec<u32>> = runs
            .iter()
            .flat_map(|(run, pages)| {
                let k = |tile: &StrokeTile| pages.iter().position(|&page| page == tile.at.page);
                tiles[run.clone()].iter().map(move |tile| k(tile).map(|k| k as u32))
            })
            .collect();
        let ks = ks?;
        // Each pass's own words — where its run starts, and where the ks are
        // — on the plan past the ks, at an offset a binding may start at: on
        // a buffer of their own they cost a pile 5 to 7 µs more made anew,
        // and 3 to 8 kept; on the plan, 3 to 5 over a pile that binds one
        // page whole, of 106 to 121 (11-06, the main PC, by turns). The
        // second of two such uniforms, the other a blur dab's dispatches'
        // (blur.rs).
        let stride = engine.device.limits().min_uniform_buffer_offset_alignment as usize / 4;
        let runs_at = Cell::new(0);
        let plan = self.plans.write(engine, tiles, dabs, paper, second, |plan| {
            let ks_at = plan.end();
            let at = (ks_at + ks.len()).next_multiple_of(stride);
            runs_at.set(at);
            let mut words = ks.clone();
            words.resize(at - ks_at + stride * runs.len(), 0);
            for (index, (run, _)) in runs.iter().enumerate() {
                words[at - ks_at + index * stride..][..2]
                    .copy_from_slice(&[run.start as u32, ks_at as u32]);
            }
            Some(words)
        })?;
        let dispatches: Vec<Encoded> = runs
            .iter()
            .enumerate()
            .map(|(index, (run, pages))| {
                // A run on one page goes by the walk that binds one. The
                // widest binds it too, so no test tells the two apart — only
                // the time.
                let way = if pages.len() == 1 { &self.one } else { &self.widest };
                let mut bound = whole(&[(0, plan)]);
                let at = ((runs_at.get() + index * stride) * 4) as u64;
                bound.push(wgpu::BindGroupEntry { binding: 1, resource: range(plan, at..at + 16) });
                bound.extend(way.planes.entries(of_pages(planes, pages)));
                bound.extend(way.view.entries(of_pages(view, pages)));
                let levels = second.into_iter().flat_map(|second| of_pages(second.plane, pages));
                bound.extend(way.levels.entries(levels));
                let side = (TILE / 8) as u32;
                let groups = (side, side, run.len() as u32);
                Encoded { pipeline: &way.pipeline, bound, groups }
            })
            .collect();
        encode(engine, &dispatches);
        Some(())
    }
}

/// Whether every one of `tiles` is on one of `pages`.
fn on_pages(tiles: &[StrokeTile], pages: &[wgpu::Buffer]) -> Option<()> {
    match tiles.iter().find(|tile| usize::from(tile.at.page) >= pages.len()) {
        Some(tile) => fail(format!(
            "tile ({}, {}) is on page {}; there are {}",
            tile.column,
            tile.row,
            tile.at.page,
            pages.len()
        )),
        None => Some(()),
    }
}

/// The buffers of `pages` among `buffers`, in their order — what a pass
/// binds of them.
fn of_pages<'a>(
    buffers: &'a [wgpu::Buffer],
    pages: &'a [u16],
) -> impl Iterator<Item = &'a wgpu::Buffer> + 'a {
    pages.iter().map(|&page| &buffers[usize::from(page)])
}

/// The textures a pile reads.
fn textures_of<'a>(dabs: &[Dab<'a>], paper: Option<&Paper<'a>>) -> Vec<&'a Texture> {
    dabs.iter()
        .filter_map(|dab| match dab.shape {
            Shape::Tip { texture, .. } => Some(texture),
            _ => None,
        })
        .chain(paper.map(|paper| paper.texture))
        .collect()
}

/// Places each of `textures` not yet `placed` under `floor`, moving `floor`
/// to it; gives the ones it placed, or nothing where one would go under the
/// plan's start. A floor stopped at 0 does as well: the use's own words,
/// checked next, never fit under it (mutant o02, 11-06).
fn placing<'a>(
    textures: &[&'a Texture],
    placed: &mut HashMap<u64, u32>,
    floor: &mut usize,
) -> Option<Vec<&'a Texture>> {
    let mut fresh = Vec::new();
    for &texture in textures {
        if !placed.contains_key(&texture.id) {
            *floor = floor.checked_sub(texture.words.len())?;
            placed.insert(texture.id, *floor as u32);
            fresh.push(texture);
        }
    }
    Some(fresh)
}

fn bytes(words: &[u32]) -> Vec<u8> {
    words.iter().flat_map(|word| word.to_le_bytes()).collect()
}

/// What a pile sends: the plan's head, and its own words from `frame_at`.
struct Plan {
    head: [u32; HEAD_WORDS],
    frame: Vec<u32>,
    /// Where the dabs' records begin, a record a dab in their order.
    records_at: usize,
}

impl Plan {
    /// The place of the tile record of the `index`-th of the plan's tiles.
    fn tile_at(&self, index: usize) -> u32 {
        (self.head[0] as usize + index * TILE_WORDS) as u32
    }

    /// The place of the `index`-th dab's record.
    fn record_at(&self, index: usize) -> u32 {
        (self.records_at + index * DAB_WORDS) as u32
    }

    /// Where the words past the plan's own go.
    fn end(&self) -> usize {
        self.head[0] as usize + self.frame.len()
    }
}

/// The plan dab.wgsl reads past the textures: the tiles, each tile's list,
/// the records, the tables — each table once, however many dabs read it.
/// Every place is a word of the whole plan.
fn planned(
    tiles: &[StrokeTile],
    dabs: &[Dab],
    paper: Option<&Paper>,
    second: Option<&Second>,
    frame_at: usize,
    textures: &HashMap<u64, u32>,
) -> Option<Plan> {
    let at: HashMap<(i32, i32), usize> = tiles
        .iter()
        .enumerate()
        .map(|(index, tile)| ((tile.column, tile.row), index))
        .collect();
    // A dab's tiles are looked for within the stroke's, however far its
    // region runs.
    let columns = tiles.iter().map(|tile| tile.column);
    let rows = tiles.iter().map(|tile| tile.row);
    let (first_column, last_column) = (columns.clone().min()?, columns.max()?);
    let (first_row, last_row) = (rows.clone().min()?, rows.max()?);
    let mut lists = vec![Vec::new(); tiles.len()];
    for (index, dab) in dabs.iter().enumerate() {
        let [left, top, right, bottom] = dab.region;
        if right <= left || bottom <= top {
            continue;
        }
        let down = top.div_euclid(TILE).max(first_row)
            ..=(bottom - 1).div_euclid(TILE).min(last_row);
        for row in down {
            let across = left.div_euclid(TILE).max(first_column)
                ..=(right - 1).div_euclid(TILE).min(last_column);
            for column in across {
                if let Some(&tile) = at.get(&(column, row)) {
                    lists[tile].push(index);
                }
            }
        }
    }
    let paper = match paper {
        None => None,
        Some(paper) => Some((paper, paper_step(paper)?)),
    };
    let mut head = [frame_at as u32, NO_TABLE, 0, 0, 0, NO_TABLE, 0];
    if let Some((paper, step)) = paper {
        head[1..5].copy_from_slice(&[
            textures[&paper.texture.id],
            paper.texture.side,
            step,
            u32::from(paper.height),
        ]);
    }
    if let Some(second) = second {
        head[5..].copy_from_slice(&[second.mode, sixteen_bit(second.density)]);
    }
    let listed: usize = lists.iter().map(Vec::len).sum();
    let records_at = frame_at + tiles.len() * TILE_WORDS + listed;
    let tables_at = records_at + dabs.len() * DAB_WORDS;
    let mut words = Vec::with_capacity(tables_at - frame_at);
    let mut first = frame_at + tiles.len() * TILE_WORDS;
    for (tile, list) in tiles.iter().zip(&lists) {
        let (column, row) = (tile.column as u32, tile.row as u32);
        let (across, down) = match paper {
            None => (0, 0),
            Some((paper, step)) => {
                let side = paper.texture.side;
                (paper_at(tile.column * TILE, step, side), paper_at(tile.row * TILE, step, side))
            }
        };
        let slot = u32::from(tile.at.slot);
        words.extend([column, row, slot, first as u32, list.len() as u32, across, down]);
        first += list.len();
    }
    for list in &lists {
        words.extend(list.iter().map(|&dab| (records_at + dab * DAB_WORDS) as u32));
    }
    let mut tables = Tables { words: Vec::new(), at: tables_at, placed: HashMap::new() };
    for dab in dabs {
        words.extend(record(dab, &mut tables, textures)?);
    }
    words.extend(tables.words);
    Some(Plan { head, frame: words, records_at })
}

/// The paper's step, a pixel's worth of it in 1/65536 texel — or nothing,
/// for a scale whose step is no whole part or leaves u32.
fn paper_step(paper: &Paper) -> Option<u32> {
    let step = (65536.0 / paper.scale).round();
    if !(1.0..=f64::from(u32::MAX)).contains(&step) {
        return fail(format!("a paper at a scale of {}", paper.scale));
    }
    Some(step as u32)
}

/// Where the centre of pixel `x` lies on paper of `side` texels taken
/// `step` parts of 1/65536 texel a pixel: c(x) = ((2x + 1)·step >> 1)
/// mod side·2^16 — the law dab.wgsl carries on pixel by pixel from here.
fn paper_at(x: i32, step: u32, side: u32) -> u32 {
    let doubled = (2 * i128::from(x) + 1) * i128::from(step);
    doubled.div_euclid(2).rem_euclid(i128::from(side) << 16) as u32
}

// The tables the records point at, each placed once.
struct Tables {
    words: Vec<u32>,
    /// Where the plan's tables begin.
    at: usize,
    /// A table's place, by where the app keeps it.
    placed: HashMap<(usize, usize), u32>,
}

impl Tables {
    fn place(&mut self, table: &[f64]) -> u32 {
        let key = (table.as_ptr() as usize, table.len());
        if let Some(&place) = self.placed.get(&key) {
            return place;
        }
        let place = (self.at + self.words.len()) as u32;
        self.words.extend(table.iter().map(|&entry| sixteen_bit(entry)));
        self.placed.insert(key, place);
        place
    }
}

/// A scale as `per_unit` × 2^point in an integer under [`SCALE_BOUND`],
/// the point as far as it goes.
fn fixed(per_unit: f64) -> (u32, u32) {
    let mut point = 0;
    while point < 31 && (per_unit * f64::from(1u32 << (point + 1))).round() < SCALE_BOUND {
        point += 1;
    }
    ((per_unit * f64::from(1u32 << point)).round() as u32, point)
}

fn record(
    dab: &Dab,
    tables: &mut Tables,
    textures: &HashMap<u64, u32>,
) -> Option<[u32; DAB_WORDS]> {
    let [left, top, right, bottom] = dab.region;
    let [red, green, blue, alpha] = dab.colour.map(u32::from);
    let (threshold, contrast) = match dab.edge {
        Edge::Threshold => (THRESHOLD, 256),
        Edge::Contrast(contrast) => (0, (contrast * 256.0).round() as u32),
    };
    let flags = threshold
        | if dab.erase { ERASE } else { 0 }
        | if dab.edge_held { EDGE_HELD } else { 0 }
        | if dab.second { SECOND } else { 0 }
        | if matches!(dab.shape, Shape::Round(_)) { ROUND } else { 0 };
    let mut words = [0u32; DAB_WORDS];
    words[..13].copy_from_slice(&[
        (dab.centre[0] * 256.0).round() as i32 as u32,
        (dab.centre[1] * 256.0).round() as i32 as u32,
        left as u32,
        top as u32,
        right as u32,
        bottom as u32,
        flags,
        red | green << 8 | blue << 16,
        alpha * 257,
        sixteen_bit(dab.opacity),
        sixteen_bit(dab.flow),
        contrast,
        dab.evening.map_or(NO_TABLE, |table| tables.place(table)),
    ]);
    words[26] = NO_TABLE;
    words[28] = dab.density.map_or(NO_TABLE, sixteen_bit);
    // How far from the centre anything is laid, and the major axis's reach.
    let (extent, major) = match dab.shape {
        Shape::Square => return Some(words),
        Shape::Round(profile) => (profile.reach, profile.reach),
        Shape::Tip { radius, .. } => (radius * (1.0 + dab.turn.roundness), radius),
    };
    // 1a 보탬 기하: distances are taken shifted s bits off 1/256 px, s the
    // least that keeps one under 2^15 within the extent.
    let reach8 = (extent * 256.0).ceil() as u32 + 256;
    let shift = (32 - reach8.leading_zeros()).saturating_sub(15);
    let unit = 256.0 / f64::from(1u32 << shift);
    // A round tip lays nothing at its reach; a bitmap's texels reach its
    // radius itself.
    let (major, guard) = match dab.shape {
        Shape::Round(_) => ((major * unit).ceil() as u32, (major * unit).ceil() as u32),
        _ => ((major * unit).round() as u32, (extent * unit).floor() as u32 + 1),
    };
    // The minor axis is held to its reach before the stretch — past it the
    // stretch is past the major anyway; that keeps the product in u32.
    let minor = (f64::from(major) * dab.turn.roundness).ceil() as u32;
    let inverse = (65536.0 / dab.turn.roundness).round() as u32;
    if u64::from(minor) * u64::from(inverse) + 32768 > u64::from(u32::MAX) {
        return fail(format!("a roundness of {} stretches past u32", dab.turn.roundness));
    }
    words[13..20].copy_from_slice(&[
        shift,
        guard,
        (dab.turn.cos * 32768.0).round() as i32 as u32,
        (dab.turn.sin * 32768.0).round() as i32 as u32,
        inverse,
        major,
        minor,
    ]);
    if let Shape::Tip { texture, radius } = dab.shape {
        if major == 0 {
            return fail(format!("a tip of radius {radius} reaches no unit"));
        }
        words[26] = textures[&texture.id];
        words[27] = texture.side;
    }
    if let Shape::Round(profile) = dab.shape {
        let (scale, point) = fixed(profile.scale / unit);
        if point < 15 {
            // A unit of distance over four entries: no tip the app draws,
            // whose tables hold 16 entries a pixel at most and whose unit
            // is 1/32 px or finer to its size of 2000.
            return fail(format!("a tip of {} entries a pixel at shift {shift}", profile.scale));
        }
        words[20..26].copy_from_slice(&[
            (profile.inner * unit).floor() as i32 as u32,
            scale,
            point,
            profile.row_length,
            tables.place(profile.coverage),
            tables.place(profile.pile),
        ]);
    }
    Some(words)
}
