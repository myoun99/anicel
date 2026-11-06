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
//!   floor, ⌈w/2⌉ × ⌈h/2⌉ of them, nothing past that. Stage 0 is the
//!   canvas's composite.
//! ② The screen reads stage 0 through the camera at 1/16 and over, as
//!   before; under it, the finest stage k whose scale · 2^k is 1/16 or over,
//!   so what is left to reduce lies in [1/16, 1/8) and a tent stays within
//!   16 px. Stage k's pixel x spans the canvas's 2^k·x..2^k·(x + 1) exactly
//!   — ⌈⌉ only leaves its last pixel partly past the canvas, holding what
//!   lies inside — so the camera reaches it with its source rows divided by
//!   2^k, not by the ratio of the sizes, which is short of 2^k on an odd
//!   side and would slide the far edge.
//!
//! The stages are kept, ⅓ of the composite's tiles at most, made the first
//! time the screen goes under 1/16. A change to the composite says where
//! ([`Halvings::changed`]), and a stage the screen reads is made again on
//! its tiles that read there — the executor's own question of which output
//! tiles a pose reads ([`ResampleMap::reads`]) — and so down the stages.

#[cfg(test)]
#[path = "halvings_tests.rs"]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::shared::{RESAMPLE_CEILING, ResampleMap, ResampleMode};

use super::{Budget, Composite, Plan, Step, TILE, TILE_BYTES, TileSet, placed_on};

/// Tiles to lay as a row: the pages and the tile set on them.
#[derive(Clone, Copy)]
pub(crate) struct Tiles<'a> {
    pub(crate) pages: &'a [wgpu::Buffer],
    pub(crate) set: &'a TileSet,
}

/// The camera the screen is shown through: `inverse`, screen pixel to
/// canvas pixel (pixel (x, y) spanning x..x+1), over a screen of `size`,
/// at display `scale` — device pixels a canvas pixel, the app's one
/// `displayScaleOf` — in `mode`, Nearest at 100% and over and Blend under
/// it (④).
#[derive(Clone, Copy)]
pub(crate) struct Camera {
    pub(crate) inverse: [f64; 9],
    pub(crate) scale: f64,
    pub(crate) mode: ResampleMode,
    pub(crate) size: (u32, u32),
}

/// The stage the screen reads at display `scale` (②): 0 at 1/16 and over,
/// under it the least k with scale · 2^k at 1/16 or over. `None` where no
/// stage is that — a scale of nothing, or under 2^-34.
pub(crate) fn stage_at(scale: f64) -> Option<usize> {
    (0..31).find(|&k| scale * f64::from(1u32 << k) * RESAMPLE_CEILING >= 1.0)
}

/// `inverse` landing on stage `k`'s pixels instead of the canvas's (②):
/// its source rows divided by 2^k, exactly — a power of two.
pub(crate) fn onto_stage(inverse: [f64; 9], k: usize) -> [f64; 9] {
    let by = 1.0 / f64::from(1u32 << k);
    let [a, b, c, d, e, f, g, h, i] = inverse;
    [a * by, b * by, c * by, d * by, e * by, f * by, g, h, i]
}

/// Stage `k ≥ 1`'s size from stage k − 1's (①): ⌈⌉ of it.
fn halved((width, height): (u32, u32)) -> (u32, u32) {
    (width.div_ceil(2), height.div_ceil(2))
}

/// A picture's pixels from the canvas's origin, as the executor bounds an
/// output: [left, top, right, bottom).
fn extent_of((width, height): (u32, u32)) -> [i32; 4] {
    [0, 0, width as i32, height as i32]
}

/// The output tiles over a picture of `size` from the canvas's origin, row
/// after row.
fn tiles_over((width, height): (u32, u32)) -> Vec<(i32, i32)> {
    let (columns, rows) = (width.div_ceil(TILE) as i32, height.div_ceil(TILE) as i32);
    (0..rows).flat_map(|row| (0..columns).map(move |column| (column, row))).collect()
}

/// The smallest rectangle holding both.
fn joined(one: Option<[i64; 4]>, other: [i64; 4]) -> [i64; 4] {
    let Some([l, t, r, b]) = one else {
        return other;
    };
    [l.min(other[0]), t.min(other[1]), r.max(other[2]), b.max(other[3])]
}

/// One halving stage: its tiles on a page of its own, slot i the i-th of
/// `tiles`, over a picture of `size` from the canvas's origin.
struct Stage {
    page: wgpu::Buffer,
    set: TileSet,
    tiles: Vec<(i32, i32)>,
    size: (u32, u32),
    /// What changed of the stage above it since it was made over that, in
    /// that stage's pixels.
    behind: Option<[i64; 4]>,
}

impl Stage {
    fn as_tiles(&self) -> Tiles<'_> {
        Tiles { pages: std::slice::from_ref(&self.page), set: &self.set }
    }
}

/// The canvas's composite's halving stages, kept for the screen. One is
/// made for a composite's size: a canvas of another size is another.
pub(crate) struct Halvings {
    /// The screen's radius floor, the stages' and the camera's.
    floor: f64,
    /// Stage 0's, the canvas's: its pixels from its origin.
    size: (u32, u32),
    /// Stage 1 first.
    stages: Vec<Stage>,
}

impl Halvings {
    /// None made yet, for the composite of a canvas of `size` the screen
    /// shows on `floor`.
    pub(crate) fn new(size: (u32, u32), floor: f64) -> Option<Self> {
        if size.0 == 0 || size.1 == 0 || size.0 > i32::MAX as u32 || size.1 > i32::MAX as u32 {
            return fail(format!("a canvas of {size:?} holds no pixel to halve"));
        }
        Some(Self { floor, size, stages: Vec::new() })
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
        let read = if k == 0 { canvas } else { self.stages[k - 1].as_tiles() };
        let (columns, rows) = camera.size;
        let inverse = onto_stage(camera.inverse, k);
        let Some(map) = ResampleMap::new(inverse, self.floor, camera.mode, columns, rows) else {
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
            let (above, size) = match at {
                0 => (canvas, self.size),
                _ => (self.stages[at - 1].as_tiles(), self.stages[at - 1].size),
            };
            if at == self.stages.len() {
                let made = self.made(engine, composite, above, size, budget)?;
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

    /// The stage under `above`, a picture of `size`, made whole.
    fn made(
        &self,
        engine: &Engine,
        composite: &Composite,
        above: Tiles,
        size: (u32, u32),
        budget: Budget,
    ) -> Option<Stage> {
        let size = halved(size);
        let tiles = tiles_over(size);
        if u16::try_from(tiles.len()).is_err() {
            return fail(format!("a stage of {} tiles is past a page's slots", tiles.len()));
        }
        let steps = [row(self.halving())];
        let done = composite.run(engine, &plan(above, &steps), &tiles, extent_of(size), budget)?;
        Some(Stage { page: done.out, set: placed_on(0, &tiles), tiles, size, behind: None })
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
        let reads_behind = |&(column, row): &(i32, i32)| {
            let (x, y) = (i64::from(column) * side, i64::from(row) * side);
            halving
                .reads(x, y, x + side, y + side)
                .is_some_and(|[l, t, r, b]| l < right && left < r && t < bottom && top < b)
        };
        let (slots, stale): (Vec<usize>, Vec<(i32, i32)>) = stage
            .tiles
            .iter()
            .enumerate()
            .filter(|(_, tile)| reads_behind(tile))
            .map(|(slot, &tile)| (slot, tile))
            .unzip();
        if stale.is_empty() {
            return Some(None);
        }
        let steps = [row(halving)];
        let extent = extent_of(stage.size);
        let done = composite.run(engine, &plan(above, &steps), &stale, extent, budget)?;
        let mut encoder = engine.device.create_command_encoder(&Default::default());
        for (from, &slot) in slots.iter().enumerate() {
            let (from, to) = (from as u64 * TILE_BYTES, slot as u64 * TILE_BYTES);
            encoder.copy_buffer_to_buffer(&done.out, from, &stage.page, to, TILE_BYTES);
        }
        engine.queue.submit([encoder.finish()]);
        let pixels = stale.iter().fold(None, |sum, &(column, row)| {
            let (x, y) = (i64::from(column) * side, i64::from(row) * side);
            Some(joined(sum, [x, y, x + side, y + side]))
        });
        Some(pixels)
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
fn row(map: ResampleMap) -> Step {
    Step::Row {
        set: 0,
        keys: None,
        map,
        matrix: None,
        opacity: 65535,
        mode: NORMAL,
        masked: false,
    }
}

/// The plan laying `steps` over `tiles`, the one tile set.
fn plan<'a>(tiles: Tiles<'a>, steps: &'a [Step]) -> Plan<'a> {
    Plan {
        pages: tiles.pages,
        sets: std::slice::from_ref(tiles.set),
        keys: &[],
        matrices: &[],
        steps,
        mask: None,
    }
}
