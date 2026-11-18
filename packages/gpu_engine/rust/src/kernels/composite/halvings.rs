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

use std::collections::HashMap;

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::pool::{Cel, Pictures};
use crate::kernels::shared::{RESAMPLE_CEILING, ResampleMap, ResampleMode};

use super::{Budget, Composite, MadeOf, Placed, Plan, Step, TILE, TILE_BYTES, TileAt, TileSet};

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

/// A picture kept in the pictures' pool (`pool::Pictures`): its tiles over
/// the pixels `extent`, [left, top, right, bottom), that anything is laid
/// on, each in a slot held for it — a halving stage, and the canvas's
/// composite the screen reads (screen.rs). A tile nothing is laid on is
/// none ([`Plan::lays_on`]), and shows as nothing. Dropped, it lets its
/// slots go; the pages stay made for the next picture.
///
/// ONE TILE FOR THE SAME INPUT (F-610, 유저 2026-11-18 「같은 타일은 한 벌만」):
/// a tile the pool keeps one made of the same for is that one, held once
/// more and not made ([`Kept::make`]) — a frame's paper and the rows no
/// frame of its cut changes are kept once for every frame's picture
/// (pool/mod.rs's `Told` has what was measured).
///
/// ↩️On pages of its own till 2026-11-13, made with it and gone with it:
/// `Pictures` says what that cost. ↩️Every tile of `extent` till 2026-11-18
/// (the-screen-premultiplies-ram-tiles-to-show-them (A)): a sheet's ink
/// window on a screen of its own kept its whole cel — a page at 300 dpi,
/// tens of MB — for the few tiles a pen wrote on.
pub(crate) struct Kept {
    pictures: Pictures,
    /// What names the pages its tiles go to first, as a cel's does.
    cel: Cel,
    /// The pool's pages its tiles are on, as a plan takes them
    /// (`Pictures::pages_of`): as its tiles were last placed.
    pages: Vec<wgpu::Buffer>,
    set: TileSet,
    extent: [i32; 4],
    /// The tiles it made, of those it holds — what it weighs
    /// ([`Kept::bytes`]) —, and how many of its tiles each is: a solid's
    /// is held once for every tile of the picture that is it, and its own
    /// till the last of them is another. One it holds that another picture
    /// made — the film's it was laid over, or one the pool kept of the same
    /// input — is none of them.
    ///
    /// ⚠️Counted, not asked of the set each time a tile is let go: a pen's
    /// stroke makes a tile or two again a hundred times a second, and each
    /// would walk every tile of the canvas for it.
    own: HashMap<TileAt, usize>,
}

/// A picture another is laid over, and which of its tiles are fresh on it:
/// made, not shared ([`Kept::made_over`]).
pub(crate) type Film<'a> = (&'a Kept, &'a dyn Fn((i32, i32)) -> bool);

/// The grid of the tiles the pixels `extent`, [left, top, right, bottom),
/// meet, none of them placed yet ([`TileSet::unplaced`]).
fn unplaced_over([left, top, right, bottom]: [i32; 4]) -> Option<TileSet> {
    TileSet::unplaced((left, top), (right.abs_diff(left), bottom.abs_diff(top)))
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

    /// The tiles [`Self::made`] keeps of `plan` over the pixels `extent`:
    /// each it lays anything on ([`Plan::lays_on`]) — what a picture weighs
    /// before it is made (the playback's room is asked for it). ⚠️The most
    /// it comes to weigh: a tile the pool keeps one of the same input for
    /// is held and weighs nothing more ([`Kept::bytes`]), and which those
    /// are is told where it is made, by the stamps taken then.
    pub(crate) fn tiles_made(plan: &Plan, extent: [i32; 4]) -> Option<usize> {
        let set = unplaced_over(extent)?;
        Some(set.grid().into_iter().filter(|&tile| plan.lays_on(tile)).count())
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
        let set = unplaced_over(extent)?;
        if over.is_some_and(|(film, _)| !film.pictures.is(pictures)) {
            return fail("a picture is laid over a film kept in another pool");
        }
        let cel = pictures.cel(engine)?;
        // Dropped where it is not made after all, it lets go the slots it
        // holds by then.
        let (pictures, pages, own) = (pictures.clone(), Vec::new(), HashMap::new());
        let mut kept = Self { pictures, cel, pages, set, extent, own };
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
                // A tile nothing lays on is none: kept as nothing, shown as
                // nothing.
                None if plan.lays_on(tile) => made.push(tile),
                None => {}
            }
        }
        let held: Vec<TileAt> = theirs.iter().map(|&(_, at)| at).collect();
        kept.pictures.hold(engine, &held)?;
        kept.place(theirs.into_iter());
        let made = kept.make(engine, composite, plan, &made, budget);
        kept.pages = kept.pictures.pages_of(kept.places());
        made.map(|()| kept)
    }

    /// `tiles` — each one `plan` lays something on — made of it and held
    /// in their places, the slots they had let go: a tile the pool keeps
    /// one made of the same for holds that one ([`Pictures::held_as`]) and
    /// nothing is run for it; of the rest, the first here of each telling
    /// — and every tile told by nothing ([`Plan::made_of`]) — is run onto
    /// a fresh slot, its own from there on, and told
    /// ([`Pictures::kept_as`]), and the others of its telling hold it. A
    /// held tile is never written over (pool/mod.rs), so a tile made again
    /// takes a slot of its own.
    ///
    /// Nothing where a run fails or the pool makes no page more: the tiles
    /// placed by then stay placed, each slot held once a tile.
    fn make(
        &mut self,
        engine: &Engine,
        composite: &Composite,
        plan: &Plan,
        tiles: &[(i32, i32)],
        budget: Budget,
    ) -> Option<()> {
        let made_of: Vec<Option<MadeOf>> =
            tiles.iter().map(|&tile| plan.made_of(tile, self.extent)).collect();
        let kept = self.pictures.held_as(engine, &made_of)?;
        self.place(tiles.iter().zip(&kept).filter_map(|(&tile, &at)| Some((tile, at?))));
        // Each tile left, by the first here of its telling: itself where it
        // is that one, or is told by nothing.
        let mut firsts: HashMap<&MadeOf, usize> = HashMap::new();
        let mut first_of =
            |tile: usize| made_of[tile].as_ref().map_or(tile, |of| *firsts.entry(of).or_insert(tile));
        let left: Vec<(usize, usize)> = (0..tiles.len())
            .filter(|&tile| kept[tile].is_none())
            .map(|tile| (tile, first_of(tile)))
            .collect();
        let (fresh, same): (Vec<_>, Vec<_>) = left.into_iter().partition(|&(tile, first)| tile == first);
        // A run puts no more than a page of the pool takes.
        for some in fresh.chunks(self.pictures.slots(engine)?) {
            let these: Vec<(i32, i32)> = some.iter().map(|&(tile, _)| tiles[tile]).collect();
            let (places, pages) = self.pictures.fresh(engine, self.cel, these.len())?;
            let onto = Placed { pages: &pages, at: &places };
            if composite.run_onto(engine, plan, &these, self.extent, onto, budget).is_none() {
                self.pictures.release(places.into_iter(), std::iter::empty());
                return None;
            }
            // Its own from here on: none of its tiles yet, each one's as
            // it is placed.
            self.own.extend(places.iter().map(|&at| (at, 0)));
            self.place(these.into_iter().zip(places.iter().copied()));
            let told = some.iter().zip(&places);
            self.pictures.kept_as(told.filter_map(|(&(tile, _), &at)| Some((made_of[tile].clone()?, at))));
        }
        let at_first = |&(tile, first): &(usize, usize)| {
            let (column, row) = tiles[first];
            Some((tiles[tile], self.set.at(column, row)?))
        };
        let same: Vec<((i32, i32), TileAt)> = same.iter().filter_map(at_first).collect();
        let held: Vec<TileAt> = same.iter().map(|&(_, at)| at).collect();
        self.pictures.hold(engine, &held)?;
        self.place(same.into_iter());
        Some(())
    }

    /// Each tile of `placed` held at the place given with it from here on
    /// — a hold taken for it already —, and the slot it had let go
    /// ([`Self::let_go`]).
    fn place(&mut self, placed: impl Iterator<Item = ((i32, i32), TileAt)>) {
        let mut had = Vec::new();
        for ((column, row), at) in placed {
            had.extend(self.set.at(column, row));
            self.set.place((column, row), at);
            if let Some(tiles) = self.own.get_mut(&at) {
                *tiles += 1;
            }
        }
        self.let_go(had);
    }

    /// One hold fewer of each of `had`, the slots of tiles placed there no
    /// more: one it made is its own no more once none of its tiles is it
    /// ([`Pictures::release`]).
    fn let_go(&mut self, had: Vec<TileAt>) {
        let own = &mut self.own;
        let last_of_its_own = |at: &TileAt| {
            let Some(tiles) = own.get_mut(at) else {
                return false;
            };
            *tiles -= 1;
            *tiles == 0 && own.remove(at).is_some()
        };
        let left: Vec<TileAt> = had.iter().copied().filter(last_of_its_own).collect();
        self.pictures.release(had.into_iter(), left.into_iter());
    }

    /// The slots its tiles are held in, one for each tile placed.
    fn places(&self) -> impl Iterator<Item = TileAt> + '_ {
        self.set.tiles.iter().flatten().copied()
    }

    /// `plan` composited again over its tiles `stale` names: each the plan
    /// lays anything on made of it as a new picture's is ([`Self::make`]) —
    /// one made of what it was made of holds the slot it had, and nothing
    /// is run for it — and the slot it had let go; each it lays nothing on
    /// let go and kept as none; the rest kept as they are. Those tiles'
    /// pixels — every one that may have changed —, where it names any.
    pub(crate) fn made_again(
        &mut self,
        engine: &Engine,
        composite: &Composite,
        plan: &Plan,
        stale: impl Fn((i32, i32)) -> bool,
        budget: Budget,
    ) -> Option<Option<[i64; 4]>> {
        let stale: Vec<(i32, i32)> =
            self.set.grid().into_iter().filter(|&tile| stale(tile)).collect();
        let (laid, bare): (Vec<_>, Vec<_>) =
            stale.into_iter().partition(|&tile| plan.lays_on(tile));
        // A tile kept that nothing lays on now is let go; one not kept stays
        // none, as it was.
        let kept_at = |(column, row): (i32, i32)| Some(((column, row), self.set.at(column, row)?));
        let emptied: Vec<((i32, i32), TileAt)> = bare.into_iter().filter_map(kept_at).collect();
        for &(tile, _) in &emptied {
            self.set.unplace(tile);
        }
        self.let_go(emptied.iter().map(|&(_, at)| at).collect());
        let made = self.make(engine, composite, plan, &laid, budget);
        self.pages = self.pictures.pages_of(self.places());
        made?;
        let side = i64::from(TILE);
        let changed = laid.iter().chain(emptied.iter().map(|(tile, _)| tile));
        Some(changed.fold(None, |sum, &(column, row)| {
            let (x, y) = (i64::from(column) * side, i64::from(row) * side);
            Some(joined(sum, [x, y, x + side, y + side]))
        }))
    }

    /// The bytes of the tiles it made, of those it holds: what keeping it
    /// costs past what the other pictures cost.
    ///
    /// ↩️Every tile it held till 2026-11-18 — one shared with the film it
    /// was laid over ([`Kept::made_over`]) counted in both, 「as it did
    /// while each kept a copy」. A TILE IS WEIGHED ONCE (F-610): pictures of
    /// one cut hold most of their tiles together ([`Kept::make`]), and
    /// each weighing all it holds, the playback's budget let go of pictures
    /// that cost next to nothing and the memory tab read many times what
    /// the GPU held. The picture that made a tile weighs it; one its maker
    /// let go while others hold it is weighed by none of them, and counted
    /// beside them (`Pictures::unowned_bytes`).
    pub(crate) fn bytes(&self) -> u64 {
        self.own.len() as u64 * TILE_BYTES
    }

    pub(crate) fn as_tiles(&self) -> Tiles<'_> {
        Tiles { pages: &self.pages, set: &self.set }
    }
}

impl Drop for Kept {
    fn drop(&mut self) {
        self.pictures.release(self.places(), self.own.keys().copied());
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
        stamps: None,
    }
}
