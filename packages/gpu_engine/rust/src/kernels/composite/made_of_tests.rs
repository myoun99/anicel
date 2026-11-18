//! One tile for the same input (F-610) on a real GPU: pictures made of the
//! same hold one tile and show what each made whole shows, a tile is told
//! apart by every word that changes its pixels and by none that does not —
//! what a held chain put by the number it is kept under —, a slot handed
//! out again is another tile, and a tile is weighed once — never against a
//! CPU copy of a formula (`kernels/mod.rs` has why).

use crate::kernels::blend::mode::{MULTIPLY, NORMAL};
use crate::kernels::chain::{Chained, Op};
use crate::kernels::composite::held::HeldChains;
use crate::kernels::composite::kept::Kept;
use crate::kernels::composite::kept::tests::kept_bytes;
use crate::kernels::composite::tests::{Rig, contrast, rig, texel};
use crate::kernels::composite::{
    BufferChain, KeyChain, MadeOf, Over, Plan, Step, TILE, TILE_BYTES, TILE_TEXELS, TileAt, TileSet, WHOLE,
};
use crate::kernels::effects::blur::TileRect;
use crate::kernels::effects::{MATRIX_WORDS, matrix_words};
use crate::kernels::pool::{Pictures, Pool, Stamps};
use crate::kernels::shared::{ResampleMap, ResampleMode, le_bytes};
use crate::testing::stored;

/// The page: 4 × 2 tiles.
const PAGE: [i32; 4] = [0, 0, 4 * TILE as i32, 2 * TILE as i32];
/// The page's tiles the paper alone is laid on, as a picture's set places
/// them, row after row: (3, 0) and the second row.
const PAPER_ALONE: [usize; 5] = [3, 4, 5, 6, 7];
const PAPER: u32 = 0xffff_ffff;
/// The slots a page of a test's pictures' pool has: more than twice what
/// any test here holds, so no page is asked for ahead
/// (`Pool::make_a_page_ahead`) and the slots free are the ones not held.
const SLOTS: usize = 64;

/// A stored tile of pixels of its own, `seed`'s.
fn tile(seed: u32) -> Vec<u8> {
    let side = TILE as i32;
    let words: Vec<u32> = (0..TILE_TEXELS as i32).map(|at| texel(seed, at % side, at / side)).collect();
    le_bytes(&words)
}

/// Tile set `set` laid whole, unposed, in normal.
fn row(set: usize) -> Step {
    Step::Row {
        set,
        keys: None,
        chain: None,
        map: ResampleMap::moved(0, 0),
        matrix: None,
        opacity: WHOLE,
        mode: NORMAL,
        masked: false,
    }
}

/// A cut's frame as a plan lays it: the paper over the page, a row no frame
/// of the cut changes on tiles (0, 0) and (1, 0) — set 0 —, and the frame's
/// own row on tile (2, 0) — set 1.
struct Frame {
    sets: [TileSet; 2],
    keys: Vec<KeyChain>,
    matrices: Vec<[u32; MATRIX_WORDS]>,
    chains: Vec<Chained<'static>>,
    steps: Vec<Step>,
}

impl Frame {
    fn of(held: [TileAt; 2], own: TileAt) -> Self {
        let sets = [
            TileSet::from_words(0, 0, 2, 1, &[held[0].word(), held[1].word()]),
            TileSet::from_words(2, 0, 1, 1, &[own.word()]),
        ];
        let steps = vec![Step::Solid { colour: PAPER, rect: PAGE }, row(0), row(1)];
        Self { sets, keys: Vec::new(), matrices: Vec::new(), chains: Vec::new(), steps }
    }

    /// It, changed by `change`.
    fn with(mut self, change: impl FnOnce(&mut Self)) -> Self {
        change(&mut self);
        self
    }

    fn plan<'a>(&'a self, pool: &'a Pool, stamps: Option<&'a Stamps>) -> Plan<'a> {
        Plan {
            pages: pool.pages(),
            sets: &self.sets,
            keys: &self.keys,
            matrices: &self.matrices,
            chains: &self.chains,
            steps: &self.steps,
            mask: None,
            stamps,
        }
    }

    /// Its picture over the page kept in `pictures`: told by the pool's
    /// stamps as they stand where `told`, by nothing else.
    fn kept(&self, pool: &Pool, pictures: &Pictures, told: bool) -> Kept {
        let Rig { engine, composite } = rig();
        let stamps = pool.stamps();
        let plan = self.plan(pool, told.then_some(&stamps));
        Kept::made_in(engine, composite, &plan, PAGE, None, pictures, composite.widest()).expect("kept")
    }

    /// Its picture's pixels made whole, told by nothing: what a picture of
    /// it holding tiles others made is held to.
    fn whole(&self, pool: &Pool) -> Vec<u8> {
        let apart = Pictures::sized(SLOTS).expect("a pool");
        let whole = self.kept(pool, &apart, false);
        assert_eq!(whole.bytes(), 8 * TILE_BYTES, "premise: told by nothing, every tile is made");
        kept_bytes(&whole)
    }
}

/// Where `kept` holds each tile of the page, row after row.
fn slots(kept: &Kept) -> Vec<TileAt> {
    kept.as_tiles().set.tiles.iter().map(|at| at.expect("the paper lies on every tile")).collect()
}

/// The slots of `pictures` its pictures hold.
fn held(pictures: &Pictures) -> u64 {
    SLOTS as u64 - pictures.idle_bytes() / TILE_BYTES
}

// Two frames of a cut — the paper, a row neither changes, a row of its own
// each — kept one after the other: the tiles the paper alone lies on are
// one slot, wherever they lie and in both; the unchanged row's are the
// first's in the second; each frame's own is its own. Each weighs the
// tiles it made, and shows what it shows made whole and told by nothing.
#[test]
fn pictures_made_of_the_same_hold_one_tile() {
    let (pool, at) = stored(&[tile(1), tile(2), tile(3), tile(4)]);
    let (one, other) = (Frame::of([at[0], at[1]], at[2]), Frame::of([at[0], at[1]], at[3]));
    let pictures = Pictures::sized(SLOTS).expect("a pool");
    let (first, second) = (one.kept(&pool, &pictures, true), other.kept(&pool, &pictures, true));
    let (a, b) = (slots(&first), slots(&second));
    for tile in PAPER_ALONE {
        assert_eq!((a[tile], b[tile]), (a[3], a[3]), "the paper alone on tile {tile}: one slot for every such tile");
    }
    assert_eq!(a[..2], b[..2], "the row neither frame changes");
    assert_ne!(a[2], b[2], "each frame's own row");
    assert!(a[..3].iter().all(|&at| at != a[3]), "a tile a row is laid on is not the paper's");
    assert_eq!(held(&pictures), 5, "the paper, the row of two, and a tile of each frame's own");
    assert_eq!(first.bytes(), 4 * TILE_BYTES, "the first made the paper, the row and its own");
    assert_eq!(second.bytes(), TILE_BYTES, "the second made its own alone");
    assert_eq!(pictures.unowned_bytes(), 0, "each tile's maker holds it");
    assert!(kept_bytes(&first) == one.whole(&pool), "the first, against it made whole");
    assert!(kept_bytes(&second) == other.whole(&pool), "the second, against it made whole");
}

// A slot let go and handed out again holds another tile under the same
// place: a picture laid on it is told apart from the one laid on what the
// slot held before, and shows the new tile's pixels.
#[test]
fn a_tile_stored_where_another_was_let_go_is_told_apart() {
    let (mut pool, at) = stored(&[tile(1), tile(2), tile(3)]);
    let frame = Frame::of([at[0], at[1]], at[2]);
    let pictures = Pictures::sized(SLOTS).expect("a pool");
    let before = frame.kept(&pool, &pictures, true);
    pool.release(at[2]).expect("held");
    let cel = pool.cel();
    let again = pool.store(rig().engine, cel, &[&tile(9)]).expect("store");
    assert_eq!(again, [at[2]], "premise: the slot let go is the one handed out");
    let after = frame.kept(&pool, &pictures, true);
    let (had, has) = (slots(&before), slots(&after));
    assert_ne!(had[2], has[2], "the same place, another tile");
    assert_eq!((&had[..2], &had[3..]), (&has[..2], &has[3..]), "the rest are the first's");
    assert!(kept_bytes(&after) == frame.whole(&pool), "against it made whole");
    assert!(kept_bytes(&after) != kept_bytes(&before), "premise: the tiles differ");
}

// A stamp is told whole: a slot handed out again a word's count of
// hand-outs later holds another tile, its stamp's low word the one it had.
#[test]
fn a_tile_handed_out_a_word_s_count_later_is_told_apart() {
    let (mut pool, at) = stored(&[tile(1), tile(2), tile(3)]);
    let frame = Frame::of([at[0], at[1]], at[2]);
    let before = told(&frame, &pool, (2, 0), PAGE).expect("told");
    let had = pool.stamps().of(at[2]).expect("stamped");
    pool.release(at[2]).expect("held");
    pool.handed_already(had + (1 << 32) - 1);
    let cel = pool.cel();
    let again = pool.store(rig().engine, cel, &[&tile(9)]).expect("store");
    assert_eq!(again, [at[2]], "premise: the slot let go is the one handed out");
    let has = pool.stamps().of(at[2]).expect("stamped");
    assert_eq!((has as u32, has >> 32), (had as u32, 1), "premise: the low word it had, a word's count on");
    assert_ne!(told(&frame, &pool, (2, 0), PAGE), Some(before), "another tile");
}

// A picture made again where nothing it is made of changed holds every
// slot it had, and takes none; made again over a row's tile that changed,
// that tile alone is another slot, the one it had is free, and it weighs
// what it did.
#[test]
fn a_tile_made_again_of_what_it_was_made_of_keeps_its_slot() {
    let Rig { engine, composite } = rig();
    let (pool, at) = stored(&[tile(1), tile(2), tile(3), tile(4)]);
    let stamps = pool.stamps();
    let (frame, next) = (Frame::of([at[0], at[1]], at[2]), Frame::of([at[0], at[1]], at[3]));
    let pictures = Pictures::sized(SLOTS).expect("a pool");
    let mut kept = frame.kept(&pool, &pictures, true);
    let had = slots(&kept);
    let plan = frame.plan(&pool, Some(&stamps));
    kept.made_again(engine, composite, &plan, |_| true, composite.widest()).expect("made again");
    assert_eq!(slots(&kept), had, "nothing under it changed: every tile holds the slot it had");
    assert_eq!((held(&pictures), kept.bytes()), (4, 4 * TILE_BYTES));
    let plan = next.plan(&pool, Some(&stamps));
    kept.made_again(engine, composite, &plan, |_| true, composite.widest()).expect("made again");
    let has = slots(&kept);
    let moved: Vec<usize> = (0..8).filter(|&tile| had[tile] != has[tile]).collect();
    assert_eq!(moved, [2], "the row's tile that changed, alone");
    assert_eq!((held(&pictures), kept.bytes()), (4, 4 * TILE_BYTES), "the slot it had is free");
    assert_eq!(pictures.unowned_bytes(), 0);
    assert!(kept_bytes(&kept) == next.whole(&pool), "against it made whole");
}

// The picture that made a tile let go, the tile is weighed by none of the
// pictures that hold it and counted beside them — and by nothing once the
// last of them lets it go: its slot is free, and its telling forgotten, so
// a picture made of the same after other pictures took the slots is made
// anew, not of what lies there now.
#[test]
fn a_tile_whose_maker_is_let_go_is_weighed_beside_the_pictures_that_hold_it() {
    let (pool, at) = stored(&[tile(1), tile(2), tile(3), tile(4)]);
    let (one, other) = (Frame::of([at[0], at[1]], at[2]), Frame::of([at[0], at[1]], at[3]));
    let pictures = Pictures::sized(SLOTS).expect("a pool");
    let (first, second) = (one.kept(&pool, &pictures, true), other.kept(&pool, &pictures, true));
    drop(first);
    assert_eq!(pictures.unowned_bytes(), 3 * TILE_BYTES, "the paper and the row of two, the second's to hold");
    assert_eq!((held(&pictures), second.bytes()), (4, TILE_BYTES), "the first's own row alone is free");
    let third = one.kept(&pool, &pictures, true);
    assert_eq!(third.bytes(), TILE_BYTES, "its own row made anew; the rest held as the second holds them");
    assert_eq!((held(&pictures), pictures.unowned_bytes()), (5, 3 * TILE_BYTES));
    drop(second);
    assert_eq!(pictures.unowned_bytes(), 3 * TILE_BYTES, "the third holds them still");
    drop(third);
    assert_eq!((held(&pictures), pictures.unowned_bytes()), (0, 0), "nobody holds a tile: none is anybody's");
    // The slots let go last are handed out first: a frame of other tiles
    // takes them.
    let stranger = Frame::of([at[3], at[2]], at[0]).kept(&pool, &pictures, true);
    let back = one.kept(&pool, &pictures, true);
    assert!(kept_bytes(&back) == one.whole(&pool), "made of what it names, not of what took its slots");
    assert_eq!(stranger.bytes(), 4 * TILE_BYTES, "the paper anew, and its three");
    assert_eq!(back.bytes(), 3 * TILE_BYTES, "the paper the stranger's; its three anew");
}

/// What tile `tile` of `frame`'s picture over `extent` is made of, told by
/// `pool`'s stamps.
fn told(frame: &Frame, pool: &Pool, tile: (i32, i32), extent: [i32; 4]) -> Option<MadeOf> {
    frame.plan(pool, Some(&pool.stamps())).made_of(tile, extent)
}

// A telling names all a tile's pixels come of: every word of a step laid on
// the tile, the stored tile a row reads there, the part of a solid and of
// the picture's extent on it, the pool its tiles are stored in — and its
// place where a row is laid on it.
#[test]
fn a_telling_differs_by_every_word_a_tile_s_pixels_come_of() {
    let (pool, at) = stored(&[tile(1), tile(2), tile(3), tile(4)]);
    let frame = || Frame::of([at[0], at[1]], at[2]);
    let base = told(&frame(), &pool, (0, 0), PAGE).expect("told");
    assert_eq!(told(&frame(), &pool, (0, 0), PAGE), Some(base.clone()), "premise: the same, told again");
    let turned = ResampleMap::new([0.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0], 1.0, ResampleMode::Blend, TILE, TILE);
    let turned = turned.expect("a pose that lands");
    let row_as = |change: fn(&mut Step)| frame().with(|frame| change(&mut frame.steps[1]));
    let changed = [
        ("its opacity", row_as(|step| if let Step::Row { opacity, .. } = step { *opacity = WHOLE / 2 })),
        ("its mode", row_as(|step| if let Step::Row { mode, .. } = step { *mode = MULTIPLY })),
        ("the stored tile it reads", Frame::of([at[3], at[1]], at[2])),
        ("the paper's colour", frame().with(|frame| frame.steps[0] = Step::Solid { colour: 0xff00_00ff, rect: PAGE })),
        ("the paper's part on it", frame().with(|frame| frame.steps[0] = Step::Solid { colour: PAPER, rect: [5, 0, 512, 256] })),
        ("a solid more on it", frame().with(|frame| frame.steps.push(Step::Solid { colour: 0x8000_0000, rect: [0, 0, 9, 9] }))),
        ("a buffer opened and closed", frame().with(|frame| {
            frame.steps.insert(1, Step::Open);
            frame.steps.push(Step::Close { opacity: WHOLE, mode: NORMAL, matrix: None, chain: None });
        })),
    ];
    for (what, frame) in &changed {
        assert_ne!(told(frame, &pool, (0, 0), PAGE), Some(base.clone()), "{what}");
        assert!(told(frame, &pool, (0, 0), PAGE).is_some(), "{what}: told all the same");
    }
    let posed = frame().with(|frame| {
        if let Step::Row { map, .. } = &mut frame.steps[1] {
            *map = turned;
        }
    });
    assert_ne!(told(&posed, &pool, (0, 0), PAGE), Some(base.clone()), "its pose");
    // Two poses that read the same stored tiles for the tile: the pose
    // alone tells them apart.
    let moved = |by: i32| {
        frame().with(|frame| {
            if let Step::Row { map, .. } = &mut frame.steps[1] {
                *map = ResampleMap::moved(by, 0);
            }
        })
    };
    let (one, other) = (told(&moved(1), &pool, (0, 0), PAGE), told(&moved(2), &pool, (0, 0), PAGE));
    assert!(one.is_some() && one != other, "its pose, where what it reads is the same");
    // One stored tile, a column to either side in its row's grid, under a
    // pose that reads two columns for the tile: where it lies in the grid
    // is where its pixels land, and a telling's own word.
    let lying_at = |column: i32| {
        let frame = moved(TILE as i32 / 2).with(|frame| {
            frame.sets[0] = TileSet::from_words(column, 0, 1, 1, &[at[0].word()]);
        });
        told(&frame, &pool, (0, 0), PAGE).expect("told")
    };
    let (left, here, right) = (lying_at(-1), lying_at(0), lying_at(1));
    assert!(left != here && here != right && left != right, "the place of the stored tile it reads");
    let matrix = [7; MATRIX_WORDS];
    let through = |words| {
        frame().with(|frame| {
            frame.matrices.push(words);
            if let Step::Row { matrix, .. } = &mut frame.steps[1] {
                *matrix = Some(0);
            }
        })
    };
    let (one, other) = (told(&through(matrix), &pool, (0, 0), PAGE), told(&through([8; MATRIX_WORDS]), &pool, (0, 0), PAGE));
    assert!(one.is_some() && one != Some(base.clone()), "a matrix it runs through");
    assert_ne!(one, other, "the matrix's words");
    let keyed = |runs: Vec<Vec<u32>>| {
        frame().with(|frame| {
            frame.keys.push(KeyChain { runs });
            if let Step::Row { keys, .. } = &mut frame.steps[1] {
                *keys = Some(0);
            }
        })
    };
    let (one, other) = (told(&keyed(vec![vec![1, 2]]), &pool, (0, 0), PAGE), told(&keyed(vec![vec![1], vec![2]]), &pool, (0, 0), PAGE));
    assert!(one.is_some() && one != Some(base.clone()), "a key chain it is keyed by");
    assert_ne!(one, other, "the chain's runs, each its own words");
    assert_ne!(one, told(&keyed(vec![vec![1, 3]]), &pool, (0, 0), PAGE), "a run's words");
    // A buffer's steps, each by its own words: the rows it holds blend by
    // how it was opened and how it closes.
    let buffered = |open: Step, close: Step, matrix: Option<[u32; MATRIX_WORDS]>| {
        let frame = frame().with(|frame| {
            frame.matrices.extend(matrix);
            frame.steps.insert(1, open);
            frame.steps.push(close);
        });
        told(&frame, &pool, (0, 0), PAGE)
    };
    let close = |opacity, mode, matrix| Step::Close { opacity, mode, matrix, chain: None };
    let plain = buffered(Step::Open, close(WHOLE, NORMAL, None), None);
    let others = [
        ("opened on the one under it made whole", buffered(Step::OpenOpaque, close(WHOLE, NORMAL, None), None)),
        ("closed atop", buffered(Step::Open, Step::CloseAtop, None)),
        ("its close's opacity", buffered(Step::Open, close(WHOLE / 2, NORMAL, None), None)),
        ("its close's mode", buffered(Step::Open, close(WHOLE, MULTIPLY, None), None)),
        ("a matrix it closes through", buffered(Step::Open, close(WHOLE, NORMAL, Some(0)), Some(matrix))),
    ];
    for (what, other) in &others {
        assert!(other.is_some() && *other != plain, "a buffer {what}");
    }
    let through_another = buffered(Step::Open, close(WHOLE, NORMAL, Some(0)), Some([8; MATRIX_WORDS]));
    assert!(through_another.is_some() && through_another != others[4].1, "the words of the matrix a buffer closes through");
    assert_ne!(told(&frame(), &pool, (0, 0), [0, 0, 512, 100]), Some(base.clone()), "the extent's part on it");
    assert_ne!(told(&frame(), &pool, (1, 0), PAGE), Some(base.clone()), "premise: another tile of the row");
    // A quarter pixel aside, the row's two tiles are both read for each
    // of the two tiles under them — by the same pose, under the same
    // paper: all that tells the two apart is where each lies.
    let aside = ResampleMap::new([1.0, 0.0, 0.25, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0], 1.0, ResampleMode::Blend, 2 * TILE, TILE);
    let aside = aside.expect("a pose that lands");
    let sampled = frame().with(|frame| {
        frame.steps.truncate(2);
        if let Step::Row { map, .. } = &mut frame.steps[1] {
            *map = aside;
        }
    });
    let (here, there) = (told(&sampled, &pool, (0, 0), PAGE), told(&sampled, &pool, (1, 0), PAGE));
    assert!(here.is_some() && here != there, "where the tile lies, a row laid on it");
    let (elsewhere, places) = stored(&[tile(1), tile(2), tile(3), tile(4)]);
    assert_eq!(places, at, "premise: the same places of another pool, each stamped alike");
    assert_ne!(told(&frame(), &elsewhere, (0, 0), PAGE), Some(base), "the pool its tiles are stored in");
}

// And by nothing else: a row or a solid that lies elsewhere, the paper's
// rectangle and the picture's extent past the tile, and — under the paper
// alone — where the tile lies.
#[test]
fn a_telling_is_the_same_whatever_lies_off_the_tile() {
    let (pool, at) = stored(&[tile(1), tile(2), tile(3), tile(4)]);
    let frame = || Frame::of([at[0], at[1]], at[2]);
    let base = told(&frame(), &pool, (0, 0), PAGE).expect("told");
    let same = [
        ("the frame's own row, on another tile", Frame::of([at[0], at[1]], at[3])),
        ("the row's other tile", Frame::of([at[0], at[3]], at[2])),
        ("the paper past the tile", frame().with(|frame| frame.steps[0] = Step::Solid { colour: PAPER, rect: [0, 0, 300, 128] })),
        ("a solid on another tile", frame().with(|frame| frame.steps.push(Step::Solid { colour: 9, rect: [128, 0, 256, 9] }))),
    ];
    for (what, frame) in &same {
        assert_eq!(told(frame, &pool, (0, 0), PAGE), Some(base.clone()), "{what}");
    }
    assert_eq!(told(&frame(), &pool, (0, 0), [0, 0, 128, 128]), Some(base), "the extent past the tile");
    let paper = told(&frame(), &pool, (3, 0), PAGE).expect("told");
    assert_eq!(told(&frame(), &pool, (1, 1), PAGE), Some(paper.clone()), "the paper alone, wherever it lies");
    assert_ne!(told(&frame(), &pool, (3, 1), [0, 0, 500, 250]), Some(paper), "but for the extent's part on it");
}

// A tile is told by nothing where its plan cannot name all it is made of:
// no stamps handed with it, a step that reads past the stored tiles — an
// effect chain no hold names, the mask, a buffer closed as a row over its
// own tiles, a range mark —, a row posed by a homography, a set, a matrix
// or a chain the plan does not hold, a tile its pool never handed out.
#[test]
fn a_tile_whose_plan_cannot_name_its_pixels_is_told_by_nothing() {
    let (pool, at) = stored(&[tile(1), tile(2), tile(3)]);
    let frame = || Frame::of([at[0], at[1]], at[2]).with(|frame| frame.chains.push(chain(OVER_PAGE, None)));
    assert!(frame().plan(&pool, None).made_of((0, 0), PAGE).is_none(), "no stamps");
    let leaned = ResampleMap::new([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0005, 0.0, 1.0], 1.0, ResampleMode::Blend, TILE, TILE);
    let leaned = leaned.expect("a pose that lands");
    let row_as = |change: fn(&mut Step)| frame().with(|frame| change(&mut frame.steps[1]));
    let close = |chain| Step::Close { opacity: WHOLE, mode: NORMAL, matrix: None, chain };
    let unposed = ResampleMap::moved(0, 0);
    let untold = [
        ("a row through a chain no hold names", row_as(|step| if let Step::Row { chain, .. } = step { *chain = Some(0) })),
        ("a row through a chain the plan holds none of", row_as(|step| if let Step::Row { chain, .. } = step { *chain = Some(9) })),
        ("a row under the mask", row_as(|step| if let Step::Row { masked, .. } = step { *masked = true })),
        ("a row of a set the plan holds none of", row_as(|step| if let Step::Row { set, .. } = step { *set = 9 })),
        ("a row through a matrix the plan holds none of", row_as(|step| if let Step::Row { matrix, .. } = step { *matrix = Some(0) })),
        ("a row keyed by a chain the plan holds none of", row_as(|step| if let Step::Row { keys, .. } = step { *keys = Some(0) })),
        ("a buffer closed through a chain no hold names", frame().with(|frame| {
            frame.steps.push(close(Some(BufferChain { chain: 0, mix: WHOLE })));
        })),
        ("a buffer closed as a row through a chain no hold names", frame().with(|frame| {
            frame.steps.push(Step::CloseRow { over: Over::Chain(0), map: unposed, matrix: None, opacity: WHOLE, mode: NORMAL });
        })),
        ("a buffer closed as a row over its own tiles", frame().with(|frame| {
            frame.steps.push(Step::CloseRow { over: Over::Tiles(OVER_ROW), map: unposed, matrix: None, opacity: WHOLE, mode: NORMAL });
        })),
        ("a range mark", frame().with(|frame| frame.steps.push(Step::Mark { map: unposed, shift: [0, 0] }))),
    ];
    for (what, frame) in &untold {
        assert!(told(frame, &pool, (0, 0), PAGE).is_none(), "{what}");
    }
    let posed = frame().with(|frame| {
        if let Step::Row { map, .. } = &mut frame.steps[1] {
            *map = leaned;
        }
    });
    assert!(told(&posed, &pool, (0, 0), PAGE).is_none(), "a row posed by a homography");
    let never = TileAt { page: 0, slot: 40 };
    assert!(pool.stamps().of(never).is_none() && pool.slots() > 40, "premise: a slot of its page, never handed out");
    let unstored = Frame::of([never, at[1]], at[2]);
    assert!(told(&unstored, &pool, (0, 0), PAGE).is_none(), "a row of a tile the pool never handed out");
    let told_buffers = frame().with(|frame| {
        frame.steps.extend([Step::Open, Step::OpenOpaque, Step::CloseAtop, close(None)]);
    });
    assert!(told(&told_buffers, &pool, (0, 0), PAGE).is_some(), "premise: buffers opened and closed plainly are told");
}

// The first picture kept of a page with nothing on it but the paper makes
// one tile, held once for every tile of the page — and that one its own
// for as long as a tile of it is the paper's: made again where a row comes
// to lie, it lets one hold go and weighs the paper still.
#[test]
fn a_picture_holds_the_paper_once_for_every_tile_it_is() {
    let Rig { engine, composite } = rig();
    let (pool, at) = stored(&[tile(1), tile(2), tile(3)]);
    let stamps = pool.stamps();
    let bare = Frame::of([at[0], at[1]], at[2]).with(|frame| frame.steps.truncate(1));
    let pictures = Pictures::sized(SLOTS).expect("a pool");
    let mut kept = bare.kept(&pool, &pictures, true);
    let had = slots(&kept);
    assert!(had.iter().all(|&at| at == had[0]), "one slot for the eight");
    assert_eq!((held(&pictures), kept.bytes()), (1, TILE_BYTES));
    let frame = Frame::of([at[0], at[1]], at[2]);
    let plan = frame.plan(&pool, Some(&stamps));
    kept.made_again(engine, composite, &plan, |tile| tile == (0, 0), composite.widest()).expect("made again");
    let has = slots(&kept);
    assert_ne!(has[0], had[0], "the row's tile, made");
    assert_eq!(has[1..], had[1..], "the paper's, held as they were");
    assert_eq!((held(&pictures), kept.bytes()), (2, 2 * TILE_BYTES), "the paper its own still");
    assert_eq!(pictures.unowned_bytes(), 0, "let go of once, held seven times: its maker's");
    drop(kept);
    assert_eq!((held(&pictures), pictures.unowned_bytes()), (0, 0));
}

/// The page's tiles: where a test's chain runs, unless it says otherwise.
const OVER_PAGE: TileRect = TileRect { x0: 0, y0: 0, columns: 4, rows: 2 };
/// The tiles of the row no frame changes ([`Frame`]): (0, 0) and (1, 0).
const OVER_ROW: TileRect = TileRect { x0: 0, y0: 0, columns: 2, rows: 1 };

/// A hold of a test's own, kept for the process's life: a frame's chains
/// borrow it.
fn hold() -> &'static HeldChains {
    Box::leak(Box::default())
}

/// A chain over `rect` — a contrast — held as `held` names, if it names.
fn chain(rect: TileRect, held: Option<(&'static HeldChains, u32)>) -> Chained<'static> {
    let contrast = matrix_words(&contrast()).expect("a matrix in range");
    Chained { ops: vec![Op::Matrix(contrast)], rect, held }
}

/// A buffer's close through chain 0 at `mix`, whole in normal.
fn closing(mix: u32) -> Step {
    Step::Close { opacity: WHOLE, mode: NORMAL, matrix: None, chain: Some(BufferChain { chain: 0, mix }) }
}

impl Frame {
    /// It, its two rows in a buffer closed by `close` through `chain` — the
    /// plan's chain 0: the paper, the open, the rows, the close.
    fn buffered(self, chain: Chained<'static>, close: Step) -> Self {
        self.with(|frame| {
            frame.chains.push(chain);
            frame.steps.insert(1, Step::Open);
            frame.steps.push(close);
        })
    }
}

// A buffer closed through a chain a hold names is told by what names what
// the chain put — the hold, the number it is kept under, the rectangle it
// runs over — and by every word its close lays that with; by nothing where
// no hold names it.
#[test]
fn a_buffer_closed_through_a_held_chain_is_told_by_the_number_it_is_kept_under() {
    let (pool, at) = stored(&[tile(1), tile(2), tile(3), tile(4)]);
    let (ours, theirs) = (hold(), hold());
    let far: &'static HeldChains = Box::leak(Box::new(HeldChains::named(ours.id() + (1 << 32))));
    let framed = |chain, close| Frame::of([at[0], at[1]], at[2]).buffered(chain, close);
    let held_as = |held, rect| told(&framed(chain(rect, Some(held)), closing(WHOLE)), &pool, (0, 0), PAGE);
    let close = |opacity, mode, mix| Step::Close { opacity, mode, matrix: None, chain: Some(BufferChain { chain: 0, mix }) };
    let closed_as = |close| told(&framed(chain(OVER_PAGE, Some((ours, 7))), close), &pool, (0, 0), PAGE);
    let base = held_as((ours, 7), OVER_PAGE).expect("told");
    assert_eq!(held_as((ours, 7), OVER_PAGE), Some(base.clone()), "premise: the same, told again");
    assert_eq!(closed_as(close(WHOLE, NORMAL, WHOLE)), Some(base.clone()), "premise: the same close");
    let unheld = framed(chain(OVER_PAGE, None), closing(WHOLE));
    assert!(told(&unheld, &pool, (0, 0), PAGE).is_none(), "a chain no hold names runs each time");
    let changed = [
        ("its number", held_as((ours, 8), OVER_PAGE)),
        ("its hold", held_as((theirs, 7), OVER_PAGE)),
        ("its hold, a word's count on", held_as((far, 7), OVER_PAGE)),
        ("where its rectangle starts across", held_as((ours, 7), TileRect { x0: -1, ..OVER_PAGE })),
        ("where its rectangle starts down", held_as((ours, 7), TileRect { y0: -1, ..OVER_PAGE })),
        ("how far across its rectangle runs", held_as((ours, 7), TileRect { columns: 5, ..OVER_PAGE })),
        ("how far down its rectangle runs", held_as((ours, 7), TileRect { rows: 3, ..OVER_PAGE })),
        ("its mix", closed_as(close(WHOLE, NORMAL, WHOLE / 2))),
        ("its close's opacity", closed_as(close(WHOLE / 2, NORMAL, WHOLE))),
        ("its close's mode", closed_as(close(WHOLE, MULTIPLY, WHOLE))),
    ];
    for (what, other) in &changed {
        assert!(other.is_some() && *other != Some(base.clone()), "{what}");
    }
    let through = |words| {
        let close = Step::Close { opacity: WHOLE, mode: NORMAL, matrix: Some(0), chain: Some(BufferChain { chain: 0, mix: WHOLE }) };
        let frame = framed(chain(OVER_PAGE, Some((ours, 7))), close).with(|frame| frame.matrices.push(words));
        told(&frame, &pool, (0, 0), PAGE)
    };
    let (one, other) = (through([7; MATRIX_WORDS]), through([8; MATRIX_WORDS]));
    assert!(one.is_some() && one != Some(base.clone()), "a matrix it closes through");
    assert_ne!(one, other, "the matrix's words");
    let beside = told(&framed(chain(OVER_PAGE, Some((ours, 7))), closing(WHOLE)), &pool, (1, 0), PAGE);
    assert!(beside.is_some() && beside != Some(base), "where the tile lies: what the chain put there");
}

// A held buffer is told from its close alone, whatever its steps are — a
// row of other tiles, a row or a mark no telling names, a buffer in it: the
// walk lays what the hold keeps and walks none of them. The steps under its
// open and over its close are told as ever, and so are a plain buffer's
// that a held one lies in.
#[test]
fn a_held_buffer_is_told_whatever_its_steps_are() {
    let (pool, at) = stored(&[tile(1), tile(2), tile(3), tile(4)]);
    let ours = hold();
    let framed = |tiles: [TileAt; 2]| Frame::of(tiles, at[2]).buffered(chain(OVER_PAGE, Some((ours, 7))), closing(WHOLE));
    let frame = || framed([at[0], at[1]]);
    let on = |frame: &Frame, tile| told(frame, &pool, tile, PAGE);
    let base = on(&frame(), (0, 0)).expect("told");
    let unposed = ResampleMap::moved(0, 0);
    let plain = Step::Close { opacity: WHOLE, mode: NORMAL, matrix: None, chain: None };
    let same = [
        ("a row of other tiles", framed([at[3], at[1]])),
        ("a row under the mask", frame().with(|frame| {
            if let Step::Row { masked, .. } = &mut frame.steps[2] {
                *masked = true;
            }
        })),
        ("a range mark", frame().with(|frame| frame.steps.insert(2, Step::Mark { map: unposed, shift: [0, 0] }))),
        ("a buffer", frame().with(|frame| {
            frame.steps.insert(2, Step::Open);
            frame.steps.insert(4, plain);
        })),
    ];
    for (what, frame) in &same {
        assert_eq!(on(frame, (0, 0)), Some(base.clone()), "{what} in it");
    }
    let under = frame().with(|frame| frame.steps[0] = Step::Solid { colour: 0xff00_00ff, rect: PAGE });
    assert!(on(&under, (0, 0)).is_some() && on(&under, (0, 0)) != Some(base.clone()), "the paper under it");
    let over = frame().with(|frame| frame.steps.push(Step::Solid { colour: 0x8000_0000, rect: [0, 0, 9, 9] }));
    assert!(on(&over, (0, 0)).is_some() && on(&over, (0, 0)) != Some(base), "a solid over it");
    let marked = frame().with(|frame| frame.steps.push(Step::Mark { map: unposed, shift: [0, 0] }));
    assert!(on(&marked, (0, 0)).is_none(), "a range mark over it: told by nothing");
    // The paper; a plain buffer of the held one — the unchanged row's — and
    // the frame's own row.
    let nested = |inner: [TileAt; 2], own: TileAt| {
        Frame::of(inner, own).with(|frame| {
            frame.chains.push(chain(OVER_PAGE, Some((ours, 7))));
            let (paper, unchanged, own) = (frame.steps[0], frame.steps[1], frame.steps[2]);
            frame.steps = vec![paper, Step::Open, Step::Open, unchanged, closing(WHOLE), own, plain];
        })
    };
    let first = nested([at[0], at[1]], at[2]);
    assert!(on(&first, (0, 0)).is_some() && on(&first, (2, 0)).is_some(), "told");
    assert_eq!(on(&nested([at[3], at[1]], at[2]), (0, 0)), on(&first, (0, 0)), "the held buffer's row, in a plain one");
    assert_ne!(on(&nested([at[0], at[1]], at[3]), (2, 0)), on(&first, (2, 0)), "the plain buffer's own row");
}

// What a chain put is told on the tiles its row is laid on and on no other:
// off the chain's rectangle a tile is told as if the buffer were not in the
// plan — the paper alone, one tile wherever it lies —, and a row through
// the chain a tile aside is told where its pose reads a tile of what the
// chain put.
#[test]
fn what_a_chain_put_is_told_where_it_is_laid_and_nowhere_else() {
    let (pool, at) = stored(&[tile(1), tile(2), tile(3)]);
    let ours = hold();
    let frame = Frame::of([at[0], at[1]], at[2]).buffered(chain(OVER_ROW, Some((ours, 7))), closing(WHOLE));
    let bare = Frame::of([at[0], at[1]], at[2]).with(|frame| frame.steps.truncate(1));
    let on = |frame: &Frame, tile| told(frame, &pool, tile, PAGE);
    for tile in [(2, 0), (0, 1), (3, 1)] {
        assert!(on(&frame, tile).is_some(), "told, at {tile:?}");
        assert_eq!(on(&frame, tile), on(&bare, tile), "off the rectangle, at {tile:?}: the paper alone");
    }
    for tile in [(0, 0), (1, 0)] {
        assert!(on(&frame, tile).is_some() && on(&frame, tile) != on(&bare, tile), "on it, at {tile:?}");
    }
    assert_ne!(on(&frame, (0, 0)), on(&frame, (1, 0)), "each tile of it its own");
    let aside = Frame::of([at[0], at[1]], at[2]).with(|frame| {
        frame.chains.push(chain(OVER_ROW, Some((ours, 7))));
        frame.steps.truncate(2);
        if let Step::Row { chain, map, .. } = &mut frame.steps[1] {
            (*chain, *map) = (Some(0), ResampleMap::moved(TILE as i32, 0));
        }
    });
    assert_eq!(on(&aside, (0, 0)), on(&bare, (0, 0)), "moved a tile across, it leaves the first");
    assert!(on(&aside, (2, 0)).is_some() && on(&aside, (2, 0)) != on(&bare, (2, 0)), "and lies on the third");
}

// A row through a held chain, and a buffer closed as a row through one, are
// told by the number and by all the walk lays what the chain put with — its
// pose among it —, not by the row's own tiles: the walk reads none of them.
// Under the mask it is told by nothing, as any row is.
#[test]
fn a_row_through_a_held_chain_is_told_by_the_number_and_how_it_is_laid() {
    let (pool, at) = stored(&[tile(1), tile(2), tile(3), tile(4)]);
    let ours = hold();
    let chained = |tiles: [TileAt; 2], change: fn(&mut Frame)| {
        Frame::of(tiles, at[2]).with(|frame| {
            frame.chains.push(chain(OVER_PAGE, Some((ours, 7))));
            if let Step::Row { chain, .. } = &mut frame.steps[1] {
                *chain = Some(0);
            }
            change(frame);
        })
    };
    let row_as = |change: fn(&mut Frame)| chained([at[0], at[1]], change);
    let on = |frame: &Frame| told(frame, &pool, (0, 0), PAGE);
    let base = on(&row_as(|_| {})).expect("told");
    assert_eq!(on(&chained([at[3], at[1]], |_| {})), Some(base.clone()), "whatever tiles the row stores");
    let changed = [
        ("its number", row_as(|frame| frame.chains[0].held = frame.chains[0].held.map(|(hold, _)| (hold, 8)))),
        ("its opacity", row_as(|frame| if let Step::Row { opacity, .. } = &mut frame.steps[1] { *opacity = WHOLE / 2 })),
        ("its mode", row_as(|frame| if let Step::Row { mode, .. } = &mut frame.steps[1] { *mode = MULTIPLY })),
        ("its pose", row_as(|frame| if let Step::Row { map, .. } = &mut frame.steps[1] { *map = ResampleMap::moved(1, 0) })),
        ("a matrix it runs through", row_as(|frame| {
            frame.matrices.push([7; MATRIX_WORDS]);
            if let Step::Row { matrix, .. } = &mut frame.steps[1] {
                *matrix = Some(0);
            }
        })),
        ("a key chain what it put is keyed by", row_as(|frame| {
            frame.keys.push(KeyChain { runs: vec![vec![1, 2]] });
            if let Step::Row { keys, .. } = &mut frame.steps[1] {
                *keys = Some(0);
            }
        })),
    ];
    for (what, frame) in &changed {
        assert!(on(frame).is_some() && on(frame) != Some(base.clone()), "{what}");
    }
    let masked = row_as(|frame| if let Step::Row { masked, .. } = &mut frame.steps[1] { *masked = true });
    assert!(on(&masked).is_none(), "under the mask");
    let closed_as_a_row = |tiles: [TileAt; 2], map| {
        let close = Step::CloseRow { over: Over::Chain(0), map, matrix: None, opacity: WHOLE, mode: NORMAL };
        Frame::of(tiles, at[2]).buffered(chain(OVER_PAGE, Some((ours, 7))), close)
    };
    let unposed = ResampleMap::moved(0, 0);
    let as_a_row = on(&closed_as_a_row([at[0], at[1]], unposed));
    assert!(as_a_row.is_some(), "a buffer closed as a row through it: told");
    assert_eq!(on(&closed_as_a_row([at[3], at[1]], unposed)), as_a_row, "whatever its steps are");
    assert_ne!(on(&closed_as_a_row([at[0], at[1]], ResampleMap::moved(1, 0))), as_a_row, "its pose");
}

// Two frames of a cut whose unchanged row lies in a folder under an effect
// — a buffer closed through a chain held under one number, one picture in
// both — each with a row of its own over it: the folder's tiles are the
// first's in the second, which makes its own alone; the tiles off the
// folder are the paper's one slot; and each shows what it shows with the
// chain run for it, told by nothing. Under another number the folder is
// another picture's, and its tiles are made.
#[test]
fn pictures_of_one_held_chain_hold_one_tile() {
    let (pool, at) = stored(&[tile(1), tile(2), tile(3), tile(4)]);
    let ours = hold();
    // The paper; the folder — its open, the unchanged row, its close —; the
    // frame's own row.
    let framed = |own: TileAt, held| {
        Frame::of([at[0], at[1]], own).with(|frame| {
            frame.chains.push(chain(OVER_ROW, held));
            frame.steps.insert(1, Step::Open);
            frame.steps.insert(3, closing(WHOLE));
        })
    };
    let (one, other) = (framed(at[2], Some((ours, 3))), framed(at[3], Some((ours, 3))));
    let pictures = Pictures::sized(SLOTS).expect("a pool");
    let (first, second) = (one.kept(&pool, &pictures, true), other.kept(&pool, &pictures, true));
    let (a, b) = (slots(&first), slots(&second));
    assert_eq!(a[..2], b[..2], "the folder's tiles");
    assert_ne!(a[2], b[2], "each frame's own row");
    for tile in PAPER_ALONE {
        assert_eq!((a[tile], b[tile]), (a[3], a[3]), "off the folder, tile {tile}: the paper's one slot");
    }
    assert_eq!(held(&pictures), 5, "the paper, the folder's two, and a tile of each frame's own");
    assert_eq!((first.bytes(), second.bytes()), (4 * TILE_BYTES, TILE_BYTES), "the second made its own alone");
    assert!(kept_bytes(&first) == framed(at[2], None).whole(&pool), "the first, against its chain run for it");
    assert!(kept_bytes(&second) == framed(at[3], None).whole(&pool), "the second, against its chain run for it");
    let unchained = Frame::of([at[0], at[1]], at[2]).whole(&pool);
    assert!(kept_bytes(&first) != unchained, "premise: the chain changes the folder's pixels");
    let third = framed(at[2], Some((ours, 4))).kept(&pool, &pictures, true);
    let c = slots(&third);
    assert!(c[0] != a[0] && c[1] != a[1], "under another number, another picture's tiles");
    assert_eq!((c[2], third.bytes()), (a[2], 2 * TILE_BYTES), "its own row the first's; the folder's two made");
    ours.let_go(3);
    ours.let_go(4);
}
