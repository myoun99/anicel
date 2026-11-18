//! A picture kept in the pictures' pool: the canvas's composite a screen
//! reads (screen.rs), a frame's picture kept for playback.
//!
//! ↩️halvings.rs till 2026-11-19: the screen's halving stages lay here
//! beside the picture they were made of, kept as it is
//! ([`super::screen::Screen::show`] has what they were, and why they
//! went).

#[cfg(test)]
#[path = "kept_tests.rs"]
pub(crate) mod tests;

use std::collections::HashMap;

use crate::device::Engine;
use crate::fail;
use crate::kernels::pool::{Cel, Pictures};

use super::{Budget, Composite, MadeOf, Placed, Plan, Step, TILE_BYTES, TileAt, TileSet};

/// Tiles to lay as a row: the pages and the tile set on them.
#[derive(Clone, Copy)]
pub(crate) struct Tiles<'a> {
    pub(crate) pages: &'a [wgpu::Buffer],
    pub(crate) set: &'a TileSet,
}

/// A picture kept in the pictures' pool (`pool::Pictures`): its tiles over
/// the pixels `extent`, [left, top, right, bottom), that anything is laid
/// on, each in a slot held for it — the canvas's composite a screen reads
/// (screen.rs). A tile nothing is laid on is none ([`Plan::lays_on`]), and
/// shows as nothing. Dropped, it lets its slots go; the pages stay made for
/// the next picture.
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
    /// let go and kept as none; the rest kept as they are.
    ///
    /// ↩️It returned those tiles' pixels till 2026-11-19 — every one that
    /// may have changed —, read by the halving stage under the picture
    /// alone.
    pub(crate) fn made_again(
        &mut self,
        engine: &Engine,
        composite: &Composite,
        plan: &Plan,
        stale: impl Fn((i32, i32)) -> bool,
        budget: Budget,
    ) -> Option<()> {
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
        made
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
