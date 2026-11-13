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

use std::sync::atomic::{AtomicU64, Ordering};

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::pool::{Cel, Pictures};
use crate::kernels::shared::{RESAMPLE_CEILING, ResampleMap, ResampleMode};

use super::{Budget, Composite, Placed, Plan, Step, TILE, TILE_BYTES, TileAt, TileSet};

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

/// The bytes of every picture the engine keeps ([`Kept`]) — a screen's
/// canvas and its halvings —, counted where one is made and dropped: what
/// the memory census is to read of them ([`kept_bytes`]; ⏳once the screen
/// is the engine's, flip lane ⓑ).
static KEPT_BYTES: AtomicU64 = AtomicU64::new(0);

/// The bytes of every picture the engine keeps.
pub(crate) fn kept_bytes() -> u64 {
    KEPT_BYTES.load(Ordering::Relaxed)
}

/// A picture kept in the pictures' pool (`pool::Pictures`): its tiles over
/// the pixels `extent`, [left, top, right, bottom), each in a slot held for
/// it — a halving stage, and the canvas's composite the screen reads
/// (screen.rs). Dropped, it lets its slots go; the pages stay made for the
/// next picture.
///
/// ↩️On pages of its own till 2026-11-13, made with it and gone with it:
/// `Pictures` says what that cost.
pub(crate) struct Kept {
    pictures: Pictures,
    /// What names the pages its tiles go to first, as a cel's does.
    cel: Cel,
    /// The pool's pages its tiles are on, as a plan takes them
    /// (`Pictures::pages_of`): as its tiles were last placed.
    pages: Vec<wgpu::Buffer>,
    set: TileSet,
    extent: [i32; 4],
}

/// A picture another is laid over, and which of its tiles are fresh on it:
/// made, not shared ([`Kept::made_over`]).
pub(crate) type Film<'a> = (&'a Kept, &'a dyn Fn((i32, i32)) -> bool);

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
        Self::made_in(engine, composite, plan, extent, None, &engine.pictures, budget)
    }

    /// `made` on the tiles `fresh` names alone, every other tile `film`
    /// keeps held with it as it is — a frame laid over the frame its
    /// ghosts lie on (onion-ghosts-in-place ②, 유저 2026-10-26 「보통 합성이
    /// 아닌 경우라도 최대한 극한으로 개선해보자」), where the tiles its ghosts
    /// do not reach are that frame's. A tile `film` does not keep is made.
    ///
    /// ↩️Copied from the film, tile by tile, till 2026-11-13: a slot held
    /// twice is the same bytes with nothing copied, and neither picture
    /// writes over it ([`Kept::made_again`]).
    pub(crate) fn made_over(
        engine: &Engine,
        composite: &Composite,
        plan: &Plan,
        extent: [i32; 4],
        film: &Kept,
        fresh: impl Fn((i32, i32)) -> bool,
        budget: Budget,
    ) -> Option<Self> {
        let over: Film = (film, &fresh);
        Self::made_in(engine, composite, plan, extent, Some(over), &engine.pictures, budget)
    }

    /// `made_over` over `over` — `made` where none —, kept in `pictures`:
    /// the engine's, or a test's of fewer tiles a page.
    pub(crate) fn made_in(
        engine: &Engine,
        composite: &Composite,
        plan: &Plan,
        extent: [i32; 4],
        over: Option<Film>,
        pictures: &Pictures,
        budget: Budget,
    ) -> Option<Self> {
        let [left, top, right, bottom] = extent;
        let size = (right.abs_diff(left), bottom.abs_diff(top));
        let set = TileSet::unplaced((left, top), size)?;
        if over.is_some_and(|(film, _)| !film.pictures.is(pictures)) {
            return fail("a picture is laid over a film kept in another pool");
        }
        let cel = pictures.cel(engine)?;
        // Dropped where it is not made after all, it lets go the slots it
        // holds by then.
        let mut kept = Self { pictures: pictures.clone(), cel, pages: Vec::new(), set, extent };
        // The film's tile a tile is, where it is not made.
        let shared = |(column, row): (i32, i32)| {
            let (film, fresh) = over?;
            if fresh((column, row)) {
                return None;
            }
            film.set.at(column, row)
        };
        let (mut theirs, mut made) = (Vec::new(), Vec::new());
        for tile in kept.set.grid() {
            match shared(tile) {
                Some(at) => theirs.push((tile, at)),
                None => made.push(tile),
            }
        }
        let held: Vec<TileAt> = theirs.iter().map(|&(_, at)| at).collect();
        pictures.hold(engine, &held)?;
        for (tile, at) in theirs {
            kept.take(tile, at);
        }
        // A run puts no more than a page of the pool takes.
        for some in made.chunks(pictures.slots(engine)?) {
            let (places, pages) = pictures.fresh(engine, cel, some.len())?;
            for (&tile, &at) in some.iter().zip(&places) {
                kept.take(tile, at);
            }
            let onto = Placed { pages: &pages, at: &places };
            composite.run_onto(engine, plan, some, extent, onto, budget)?;
        }
        kept.pages = pictures.pages_of(kept.places());
        Some(kept)
    }

    /// `tile`, placed nowhere yet, held at `at`.
    fn take(&mut self, tile: (i32, i32), at: TileAt) {
        self.set.place(tile, at);
        KEPT_BYTES.fetch_add(TILE_BYTES, Ordering::Relaxed);
    }

    /// The slots its tiles are held in.
    fn places(&self) -> impl Iterator<Item = TileAt> + '_ {
        self.set.tiles.iter().flatten().copied()
    }

    /// `plan` composited again over the kept tiles `stale` names, each in a
    /// fresh slot and the slot it had let go — a held tile is never written
    /// over (pool/mod.rs): a picture laid over this one may hold it
    /// ([`Kept::made_over`]) —, the rest kept as they are; those tiles'
    /// pixels, where it names any.
    pub(crate) fn made_again(
        &mut self,
        engine: &Engine,
        composite: &Composite,
        plan: &Plan,
        stale: impl Fn((i32, i32)) -> bool,
        budget: Budget,
    ) -> Option<Option<[i64; 4]>> {
        let (tiles, had): (Vec<(i32, i32)>, Vec<TileAt>) =
            self.set.placed_under(None).filter(|&(tile, _)| stale(tile)).unzip();
        // A run puts no more than a page of the pool takes.
        let per_run = self.pictures.slots(engine)?;
        for (some, had) in tiles.chunks(per_run).zip(had.chunks(per_run)) {
            let (fresh, pages) = self.pictures.fresh(engine, self.cel, some.len())?;
            let onto = Placed { pages: &pages, at: &fresh };
            if composite.run_onto(engine, plan, some, self.extent, onto, budget).is_none() {
                self.pictures.release(fresh.into_iter());
                return None;
            }
            for (&tile, &at) in some.iter().zip(&fresh) {
                self.set.place(tile, at);
            }
            self.pictures.release(had.iter().copied());
            self.pages = self.pictures.pages_of(self.places());
        }
        let side = i64::from(TILE);
        Some(tiles.iter().fold(None, |sum, &(column, row)| {
            let (x, y) = (i64::from(column) * side, i64::from(row) * side);
            Some(joined(sum, [x, y, x + side, y + side]))
        }))
    }

    /// The bytes its tiles hold: what keeping it costs. ⚠️A tile it shares
    /// with the film it was laid over ([`Kept::made_over`]) counts in both,
    /// as it did while each kept a copy.
    pub(crate) fn bytes(&self) -> u64 {
        self.places().count() as u64 * TILE_BYTES
    }

    pub(crate) fn as_tiles(&self) -> Tiles<'_> {
        Tiles { pages: &self.pages, set: &self.set }
    }
}

impl Drop for Kept {
    fn drop(&mut self) {
        KEPT_BYTES.fetch_sub(self.bytes(), Ordering::Relaxed);
        self.pictures.release(self.places());
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

    /// The bytes its stages hold.
    pub(crate) fn bytes(&self) -> u64 {
        self.stages.iter().map(|stage| stage.kept.bytes()).sum()
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
            if at == self.stages.len() {
                let (above, extent) = match at {
                    0 => (canvas, self.extent),
                    _ => (self.stages[at - 1].kept.as_tiles(), self.stages[at - 1].kept.extent),
                };
                let made = self.made(engine, composite, above, extent, budget)?;
                self.stages.push(made);
                continue;
            }
            let Some(behind) = self.stages[at].behind else {
                continue;
            };
            let halving = self.halving();
            // The stage above is read while this one's tiles take fresh
            // slots ([`Kept::made_again`]).
            let (before, from) = self.stages.split_at_mut(at);
            let above = before.last().map_or(canvas, |stage| stage.kept.as_tiles());
            let stage = &mut from[0];
            let remade = remade(engine, composite, halving, above, stage, behind, budget)?;
            stage.behind = None;
            if let (Some(remade), Some(next)) = (remade, from.get_mut(1)) {
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

    /// ①'s map: stage k's pixel x about stage k − 1's 2x + 1, in Blend on
    /// the screen's floor.
    fn halving(&self) -> ResampleMap {
        let half = [2.0, 0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0, 1.0];
        ResampleMap::new(half, self.floor, ResampleMode::Blend, 1, 1)
            .expect("a half lands everywhere")
    }
}

/// `stage` made again through `halving` on its tiles that read `behind` of
/// `above`, and those tiles' pixels — what the stage under it reads that
/// changed — where there were any.
fn remade(
    engine: &Engine,
    composite: &Composite,
    halving: ResampleMap,
    above: Tiles,
    stage: &mut Stage,
    behind: [i64; 4],
    budget: Budget,
) -> Option<Option<[i64; 4]>> {
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
