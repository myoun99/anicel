//! The canvas's composite halved, stage after stage, for the screen to read
//! under 1/16 (connection-round-checklist 11-07 02:04 (a), 캔버스 베이스
//! 패널's ① ②). One R1 read reaches no further than Blend's ceiling, 16 px
//! a side; past it a pixel's tent is cut short and the screen aliases. A
//! ceiling at what each map's pixels span instead ((c), backup
//! `work/gpu-shrink-ceiling`) left each output pixel walking its (2/s)² taps
//! on one thread while the threads shrank as s²: a pasteboard of nine S5
//! canvases took 118 ms at 1/160 and 456 ms at 1/320 on an RTX 4080
//! (11-07 01:52), so:
//!
//! ① Stage k ≥ 1 is stage k − 1 through R1 Blend at a half — its pixel x
//!   about 2x + 1, the edge between two of stage k − 1's — on the screen's
//!   floor, from ⌊left/2⌋ to ⌈right/2⌉ each way, nothing past that. Stage 0
//!   is the canvas's composite, over the pixels it covers: the page and what
//!   lies past it (screen.rs).
//! ② The screen reads stage 0 through the camera at 1/16 and over, as
//!   before; under it, the finest stage k whose scale · 2^k is 1/16 or over,
//!   so what is left to reduce lies in [1/16, 1/8) and a tent stays within
//!   16 px. Stage k's pixel x spans the canvas's 2^k·x..2^k·(x + 1) exactly
//!   — ⌊⌋ and ⌈⌉ only leave its first and last pixels partly past the
//!   composite, holding what lies inside — so the camera reaches it with
//!   its source rows divided by 2^k, not by the ratio of the sizes, which
//!   is short of 2^k on an odd side and would slide the far edge.
//!
//! The stages are kept, ⅓ of the composite's tiles at most, made the first
//! time the screen goes under 1/16. A change to the composite says where
//! ([`Halvings::changed`]), and a stage the screen reads is made again on
//! its tiles that read there — the executor's own question of which output
//! tiles a pose reads ([`ResampleMap::reads`]) — and so down the stages.

#[cfg(test)]
#[path = "halvings_tests.rs"]
pub(crate) mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::shared::{RESAMPLE_CEILING, ResampleMap, ResampleMode, tiles_a_page};

use super::{Budget, Composite, Plan, Step, TILE, TILE_BYTES, TileAt, TileSet};

/// Tiles to lay as a row: the pages and the tile set on them.
#[derive(Clone, Copy)]
pub(crate) struct Tiles<'a> {
    pub(crate) pages: &'a [wgpu::Buffer],
    pub(crate) set: &'a TileSet,
}

/// The camera the screen is shown through: `inverse`, screen pixel to
/// canvas pixel (pixel (x, y) spanning x..x+1) — `[a, b, c, d, e, f]`,
/// canvas x = a·x + b·y + c, y = d·x + e·y + f —, at display `scale` —
/// device pixels a canvas pixel, the app's one `displayScaleOf` — in
/// `mode`, Nearest at 100% and over and Blend under it (④). Affine: a
/// view pans, zooms, turns and flips, and leans no plane away, so no
/// screen's size bounds its w (M11, 관제 11-08 16:27).
#[derive(Clone, Copy)]
pub(crate) struct Camera {
    pub(crate) inverse: [f64; 6],
    pub(crate) scale: f64,
    pub(crate) mode: ResampleMode,
}

/// The stage the screen reads at display `scale` (②): 0 at 1/16 and over,
/// under it the least k with scale · 2^k at 1/16 or over. `None` where no
/// stage is that — a scale of nothing, or under 2^-34.
pub(crate) fn stage_at(scale: f64) -> Option<usize> {
    (0..31).find(|&k| scale * f64::from(1u32 << k) * RESAMPLE_CEILING >= 1.0)
}

/// `inverse` landing on stage `k`'s pixels instead of the canvas's (②):
/// divided by 2^k, exactly — a power of two.
pub(crate) fn onto_stage(inverse: [f64; 6], k: usize) -> [f64; 6] {
    let by = 1.0 / f64::from(1u32 << k);
    inverse.map(|entry| entry * by)
}

/// The affine map `[a, b, c, d, e, f]` as a full inverse, its homogeneous
/// row (0, 0, 1).
pub(crate) fn affine([a, b, c, d, e, f]: [f64; 6]) -> [f64; 9] {
    [a, b, c, d, e, f, 0.0, 0.0, 1.0]
}

/// Stage `k ≥ 1`'s pixels from stage k − 1's (①): ⌊⌋ of its left and top,
/// ⌈⌉ of its right and bottom.
fn halved([left, top, right, bottom]: [i32; 4]) -> [i32; 4] {
    [left.div_euclid(2), top.div_euclid(2), (right + 1).div_euclid(2), (bottom + 1).div_euclid(2)]
}

/// The smallest rectangle holding both.
fn joined(one: Option<[i64; 4]>, other: [i64; 4]) -> [i64; 4] {
    let Some([l, t, r, b]) = one else {
        return other;
    };
    [l.min(other[0]), t.min(other[1]), r.max(other[2]), b.max(other[3])]
}

/// A picture kept on pages of its own: its tiles over the pixels `extent`,
/// [left, top, right, bottom), row after row, as many to a page as one
/// takes — a halving stage, and the canvas's composite the screen reads
/// (screen.rs).
pub(crate) struct Kept {
    pages: Vec<wgpu::Buffer>,
    set: TileSet,
    extent: [i32; 4],
}

impl Kept {
    /// `plan` composited over the pixels `extent`, [left, top, right,
    /// bottom), nothing past it, and kept.
    pub(crate) fn made(
        engine: &Engine,
        composite: &Composite,
        plan: &Plan,
        extent: [i32; 4],
        budget: Budget,
    ) -> Option<Self> {
        Self::made_by(engine, composite, plan, extent, tiles_a_page(engine)?, budget)
    }

    /// `made`, a page holding no more than `per_page` tiles — a test's
    /// fewer than the device's, to see a picture go on to its next page.
    pub(crate) fn made_by(
        engine: &Engine,
        composite: &Composite,
        plan: &Plan,
        extent: [i32; 4],
        per_page: usize,
        budget: Budget,
    ) -> Option<Self> {
        let [left, top, right, bottom] = extent;
        let size = (right.abs_diff(left), bottom.abs_diff(top));
        let set = TileSet::paged((left, top), size, 0, per_page)?;
        let tiles: Vec<(i32, i32)> = set.placed_under(None).map(|(place, _)| place).collect();
        let mut pages = Vec::with_capacity(tiles.len().div_ceil(per_page));
        for page in tiles.chunks(per_page) {
            pages.push(composite.run(engine, plan, page, extent, budget)?.out);
        }
        Some(Self { pages, set, extent })
    }

    /// `plan` composited again over the kept tiles `stale` names, the rest
    /// kept as they are; those tiles' pixels, where it names any.
    pub(crate) fn made_again(
        &self,
        engine: &Engine,
        composite: &Composite,
        plan: &Plan,
        stale: impl Fn((i32, i32)) -> bool,
        budget: Budget,
    ) -> Option<Option<[i64; 4]>> {
        let (places, slots): (Vec<(i32, i32)>, Vec<TileAt>) =
            self.set.placed_under(None).filter(|&(place, _)| stale(place)).unzip();
        // A run puts no more than a page takes.
        let per_page = tiles_a_page(engine)?;
        for (some, slots) in places.chunks(per_page).zip(slots.chunks(per_page)) {
            let done = composite.run(engine, plan, some, self.extent, budget)?;
            let mut encoder = engine.device.create_command_encoder(&Default::default());
            for (from, at) in slots.iter().enumerate() {
                let (from, to) = (from as u64 * TILE_BYTES, u64::from(at.slot) * TILE_BYTES);
                let page = &self.pages[usize::from(at.page)];
                encoder.copy_buffer_to_buffer(&done.out, from, page, to, TILE_BYTES);
            }
            engine.queue.submit([encoder.finish()]);
        }
        let side = i64::from(TILE);
        Some(places.iter().fold(None, |sum, &(column, row)| {
            let (x, y) = (i64::from(column) * side, i64::from(row) * side);
            Some(joined(sum, [x, y, x + side, y + side]))
        }))
    }

    pub(crate) fn as_tiles(&self) -> Tiles<'_> {
        Tiles { pages: &self.pages, set: &self.set }
    }
}

/// One halving stage, and what changed of the stage above it since it was
/// made over that, in that stage's pixels.
struct Stage {
    kept: Kept,
    behind: Option<[i64; 4]>,
}

/// The canvas's composite's halving stages, kept for the screen. One is
/// made for a composite's pixels: a composite over others is another.
pub(crate) struct Halvings {
    /// The screen's radius floor, the stages' and the camera's.
    floor: f64,
    /// Stage 0's, the canvas's composite's: [left, top, right, bottom).
    extent: [i32; 4],
    /// Stage 1 first.
    stages: Vec<Stage>,
}

impl Halvings {
    /// None made yet, for the composite over the pixels `extent` — [left,
    /// top, right, bottom) — the screen shows on `floor`.
    pub(crate) fn new(extent: [i32; 4], floor: f64) -> Option<Self> {
        let [left, top, right, bottom] = extent;
        if left >= right || top >= bottom {
            return fail(format!("a composite over {extent:?} holds no pixel to halve"));
        }
        Some(Self { floor, extent, stages: Vec::new() })
    }
    /// The composite changed over its pixels `rect`, [left, top, right,
    /// bottom): the stages made over it are made again there when next
    /// read. An empty `rect` marks nothing — joined, its corner would
    /// widen the mark to reach it (canvas base, 11-07 04:17).
    pub(crate) fn changed(&mut self, rect: [i32; 4]) {
        let [left, top, right, bottom] = rect;
        if left >= right || top >= bottom {
            return;
        }
        if let Some(first) = self.stages.first_mut() {
            first.behind = Some(joined(first.behind, rect.map(i64::from)));
        }
    }

    /// Shows `canvas`, the composite, through `camera` onto the pixels
    /// `rect` of `surface` as [`Composite::show`] shows a plan: at 1/16 and
    /// over itself, under it its stage (②), first brought up to date.
    pub(crate) fn show(
        &mut self,
        engine: &Engine,
        composite: &Composite,
        canvas: Tiles,
        camera: Camera,
        surface: &wgpu::Texture,
        rect: [u32; 4],
        budget: Budget,
    ) -> Option<usize> {
        let Some(k) = stage_at(camera.scale) else {
            return fail(format!("no stage is read at a scale of {}", camera.scale));
        };
        self.bring_to(engine, composite, canvas, k, budget)?;
        let read = if k == 0 { canvas } else { self.stages[k - 1].kept.as_tiles() };
        let inverse = affine(onto_stage(camera.inverse, k));
        let Some(map) = ResampleMap::new(inverse, self.floor, camera.mode, 1, 1) else {
            return fail("the camera lands nothing on the screen");
        };
        let steps = [row(map)];
        let plan = plan(read, &steps);
        composite.show(engine, &plan, surface, rect, budget)
    }

    /// Stages 1 to `k` made, or made again where what is above them
    /// changed.
    fn bring_to(
        &mut self,
        engine: &Engine,
        composite: &Composite,
        canvas: Tiles,
        k: usize,
        budget: Budget,
    ) -> Option<()> {
        for at in 0..k {
            let (above, extent) = match at {
                0 => (canvas, self.extent),
                _ => (self.stages[at - 1].kept.as_tiles(), self.stages[at - 1].kept.extent),
            };
            if at == self.stages.len() {
                let made = self.made(engine, composite, above, extent, budget)?;
                self.stages.push(made);
                continue;
            }
            let Some(behind) = self.stages[at].behind else {
                continue;
            };
            let remade = self.remade(engine, composite, above, &self.stages[at], behind, budget)?;
            self.stages[at].behind = None;
            if let (Some(remade), Some(next)) = (remade, self.stages.get_mut(at + 1)) {
                next.behind = Some(joined(next.behind, remade));
            }
        }
        Some(())
    }

    /// The stage under `above`, a picture over the pixels `extent`, made
    /// whole.
    fn made(
        &self,
        engine: &Engine,
        composite: &Composite,
        above: Tiles,
        extent: [i32; 4],
        budget: Budget,
    ) -> Option<Stage> {
        let steps = [row(self.halving())];
        let kept = Kept::made(engine, composite, &plan(above, &steps), halved(extent), budget)?;
        Some(Stage { kept, behind: None })
    }

    /// `stage` made again on its tiles that read `behind` of `above`, and
    /// those tiles' pixels — what the stage under it reads that changed —
    /// where there were any.
    fn remade(
        &self,
        engine: &Engine,
        composite: &Composite,
        above: Tiles,
        stage: &Stage,
        behind: [i64; 4],
        budget: Budget,
    ) -> Option<Option<[i64; 4]>> {
        let halving = self.halving();
        let side = i64::from(TILE);
        let [left, top, right, bottom] = behind;
        let reads_behind = |(column, row): (i32, i32)| {
            let (x, y) = (i64::from(column) * side, i64::from(row) * side);
            halving
                .reads(x, y, x + side, y + side)
                .is_some_and(|[l, t, r, b]| l < right && left < r && t < bottom && top < b)
        };
        let steps = [row(halving)];
        stage.kept.made_again(engine, composite, &plan(above, &steps), reads_behind, budget)
    }

    /// ①'s map: stage k's pixel x about stage k − 1's 2x + 1, in Blend on
    /// the screen's floor.
    fn halving(&self) -> ResampleMap {
        let half = [2.0, 0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0, 1.0];
        ResampleMap::new(half, self.floor, ResampleMode::Blend, 1, 1)
            .expect("a half lands everywhere")
    }
}

/// Tiles laid whole in normal over nothing through `map` — the screen's
/// one row, and a stage's.
pub(crate) fn row(map: ResampleMap) -> Step {
    Step::Row {
        set: 0,
        keys: None,
        chain: None,
        map,
        matrix: None,
        opacity: 65535,
        mode: NORMAL,
        masked: false,
    }
}

/// The plan laying `steps` over `tiles`, the one tile set.
pub(crate) fn plan<'a>(tiles: Tiles<'a>, steps: &'a [Step]) -> Plan<'a> {
    Plan {
        pages: tiles.pages,
        sets: std::slice::from_ref(tiles.set),
        keys: &[],
        matrices: &[],
        chains: &[],
        steps,
        mask: None,
    }
}
