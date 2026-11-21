//! The buffers a walk makes for itself (spares.rs), on a real GPU: whose a
//! spare is, when it is taken again and when let go — on spares of a test's
//! own —, and a plan's buffers run first shown out of buffers taken again
//! as out of ones made new, on an engine of a test's own: the tests' one
//! runs every test's walks, and its spares are all of theirs.

use super::abi::{
    gpu_engine_pictures_give_back, gpu_engine_pictures_idle_bytes, gpu_engine_pictures_rest,
};
use crate::kernels::pool::folded_tests::{numbered, told};
use super::chained_tests::{
    Laying, OWN, RECT, TILES, across, close, closed_as_a_row, held_chain, lensed,
};
use super::held::HeldChains;
use super::kept::Kept;
use super::screen::Screen;
use super::spares::Spares;
use super::tests::{chained, matrixed, mixed, row, with_map};
use super::{Composite, NO_EDGE, Over, Step, TILE, TILE_BYTES, WHOLE};
use crate::device::{Engine, Sent, gpu_engine_stand_still};
use crate::kernels::blend::mode::{MULTIPLY, NORMAL, SCREEN};
use crate::kernels::chain::{ChainRead, Chained, MapTiles, Op, tiles_of};
use crate::kernels::pool::Pictures;
use crate::kernels::shared::ResampleMap;
use crate::testing::{a_device_of_its_own, first_engine};

// A spare is its holders' — handed to no other while one of them lives, a
// clone being one more — and, let go of by the last, taken again where it
// holds the tiles asked: asked more than any kept holds, a new one is
// made; and of the kept that hold them, the smallest is taken.
#[test]
fn a_spare_is_its_holders_and_the_next_taken_of_its_size_once_let_go() {
    let (engine, spares) = (first_engine(), Spares::default());
    let held = spares.out(engine, 3);
    let buffer = held.buffer().clone();
    let beside = spares.out(engine, 3);
    assert!(*beside.buffer() != buffer, "held, it is handed to no other");
    let other = held.clone();
    drop(held);
    assert_eq!(spares.bytes(), 0, "a clone holds it still");
    // One of more tiles, kept ahead of it.
    drop(spares.out(engine, 4));
    drop(other);
    assert_eq!(spares.bytes(), (4 + 3) * TILE_BYTES);
    assert!(*spares.out(engine, 2).buffer() == buffer, "the smallest that holds the tiles asked");
    assert!(*spares.out(engine, 3).buffer() == buffer, "of its size, the one let go of");
    assert_eq!(spares.made(), 3, "the premise: none made for those");
    let more = spares.out(engine, 5);
    assert_eq!(more.buffer().size(), 5 * TILE_BYTES, "asked more than any kept holds, a new one");
    assert_eq!(spares.made(), 4);
    drop(beside);
}

// A kept one past what a binding takes serves an ask of just its size
// alone — handed to a walk that asked for less, it would be refused
// where that walk's own would not; within a binding, the smallest that
// holds serves as ever.
#[test]
fn a_spare_past_a_binding_serves_only_an_ask_of_just_its_size() {
    let (engine, spares) = (first_engine(), Spares::default());
    let room = 3 * TILE_BYTES;
    let past = spares.of_in(engine, 4 * TILE_BYTES, room);
    let buffer = past.buffer().clone();
    drop(past);
    let less = spares.of_in(engine, 2 * TILE_BYTES, room);
    assert!(*less.buffer() != buffer, "asked less, it is not handed the one past a binding");
    assert_eq!(less.buffer().size(), 2 * TILE_BYTES);
    assert_eq!(spares.made(), 2);
    assert!(*spares.of_in(engine, 4 * TILE_BYTES, room).buffer() == buffer, "of just its size, it is taken");
    assert_eq!(spares.made(), 2);
    drop(less);
    assert_eq!(spares.of_in(engine, TILE_BYTES, room).buffer().size(), 2 * TILE_BYTES);
    assert_eq!(spares.made(), 2, "within a binding, the smallest that holds");
}

// A new spare is made a step up from the bytes asked — an eighth of the
// power of two under them —, so one asked a little more is the same one
// taken again; of just the bytes asked where they are a step themselves
// or a binding takes no more, and never under a word.
#[test]
fn a_new_spare_is_made_a_step_up_within_what_a_binding_takes() {
    let engine = first_engine();
    let room = 64 * TILE_BYTES;
    let made = |bytes: u64, room: u64| Spares::default().of_in(engine, bytes, room).buffer().size();
    assert_eq!(made(17 * TILE_BYTES, room), 18 * TILE_BYTES, "an eighth of sixteen tiles up");
    assert_eq!(made(33 * TILE_BYTES, room), 36 * TILE_BYTES, "of thirty-two");
    assert_eq!(made(16 * TILE_BYTES, room), 16 * TILE_BYTES, "a step itself");
    assert_eq!(made(100, room), 104);
    assert_eq!(made(4, room), 4, "a word");
    assert_eq!(made(17 * TILE_BYTES, 18 * TILE_BYTES), 18 * TILE_BYTES, "all a binding takes");
    assert_eq!(made(17 * TILE_BYTES, 18 * TILE_BYTES - 4), 17 * TILE_BYTES, "no more than it takes");
    let spares = Spares::default();
    let first = spares.of_in(engine, 17 * TILE_BYTES, room);
    let buffer = first.buffer().clone();
    drop(first);
    assert!(*spares.of_in(engine, 17 * TILE_BYTES + 4096, room).buffer() == buffer, "asked a little more");
    assert_eq!(spares.made(), 1);
}

// A take in no compose is no compose's: the next compose to end, having
// taken none itself, lets go of none for it.
#[test]
fn a_take_in_no_compose_lets_the_next_compose_let_go_of_none() {
    let (engine, spares) = (first_engine(), Spares::default());
    drop(spares.out(engine, 2));
    let held = spares.out(engine, 3);
    drop(spares.composing());
    assert_eq!(spares.bytes(), 2 * TILE_BYTES, "a compose that took none lets go of none");
    drop(held);
}

// As a compose that took any ends, the spares that did not come back
// within it are let go — one a holder let go of between two composes among
// them — and those that did are kept for the next; a compose that took
// none lets go of none; and a compose within another ends with it.
#[test]
fn a_compose_that_took_any_lets_go_of_what_it_did_not_take() {
    let (engine, spares) = (first_engine(), Spares::default());
    let held = {
        let _composing = spares.composing();
        drop((spares.out(engine, 2), spares.out(engine, 3)));
        spares.out(engine, 4)
    };
    assert_eq!(spares.bytes(), 5 * TILE_BYTES, "what a compose took is kept past it");
    drop(spares.composing());
    assert_eq!(spares.bytes(), 5 * TILE_BYTES, "a compose that took none lets go of none");
    drop(held);
    assert_eq!(spares.bytes(), 9 * TILE_BYTES);
    {
        let _composing = spares.composing();
        {
            let _within = spares.composing();
            drop(spares.out(engine, 3));
        }
        assert_eq!(spares.bytes(), 9 * TILE_BYTES, "one within another ends nothing");
    }
    assert_eq!(spares.bytes(), 3 * TILE_BYTES, "those it did not take are let go");
    assert_eq!(spares.made(), 3, "and the one it took was no new one");
    spares.let_go();
    assert_eq!(spares.bytes(), 0);
}

// 🗣️유저 2026-11-20 (the folder drag card's Q1 = b): 「손을 떼면 바로
// 놓는다」. The hand at rest keeps no spare: every one kept is let go of,
// and one that comes home after — a hold's, let go of as a cache is
// trimmed; within a compose that took none, too — is kept for no one. A
// take is a hand at work again, and what it took is kept as ever.
#[test]
fn a_rest_keeps_no_spare_nor_one_that_comes_home_till_one_is_taken() {
    let (engine, spares) = (first_engine(), Spares::default());
    let held = spares.out(engine, 3);
    drop(spares.out(engine, 2));
    assert_eq!(spares.bytes(), 2 * TILE_BYTES, "the premise: one kept");
    spares.rest();
    assert_eq!(spares.bytes(), 0, "every one kept is let go of");
    drop(held);
    assert_eq!(spares.bytes(), 0, "one that comes home at rest is kept for no one");
    let held = spares.out(engine, 3);
    spares.rest();
    {
        let _composing = spares.composing();
        drop(held);
    }
    assert_eq!(spares.bytes(), 0, "nor one that comes home within a compose that took none");
    let made = spares.made();
    drop(spares.out(engine, 2));
    assert_eq!(spares.made(), made + 1, "the premise: made again after a rest");
    assert_eq!(spares.bytes(), 2 * TILE_BYTES, "a take is a hand at work: what it took is kept");
    drop(spares.out(engine, 2));
    assert_eq!(spares.made(), made + 1, "and taken again");
}

// What is let go of with no one waiting for it is dropped in a job handed
// to the thread the spares were made with — at a rest, coming home at
// rest, and as a compose that took any ends —, and no job is handed where
// there is nothing to let go.
#[test]
fn what_is_let_go_of_unwaited_is_dropped_on_the_thread_the_spares_were_made_with() {
    let engine = first_engine();
    let handed = std::sync::Arc::new(std::sync::atomic::AtomicU32::new(0));
    let counted = std::sync::Arc::clone(&handed);
    let spares = Spares::dropping_on(move |work| {
        counted.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        work();
    });
    let jobs = || handed.load(std::sync::atomic::Ordering::Relaxed);
    let held = spares.out(engine, 3);
    spares.rest();
    assert_eq!(jobs(), 0, "nothing kept, nothing to drop");
    drop(held);
    assert_eq!((jobs(), spares.bytes()), (1, 0), "one that comes home at rest");
    drop(spares.out(engine, 2));
    spares.rest();
    assert_eq!((jobs(), spares.bytes()), (2, 0), "those kept, at a rest");
    drop(spares.out(engine, 2));
    {
        let _composing = spares.composing();
        drop(spares.out(engine, 4));
    }
    assert_eq!((jobs(), spares.bytes()), (3, 4 * TILE_BYTES), "what a compose did not take");
    drop(spares.composing());
    assert_eq!(jobs(), 3, "a compose with nothing to let go hands none");
}

// An engine's spares drop on its thread for pages: the driver's letting go
// of a buffer stands in no body's way there (spares.rs has what it took on
// the engine's thread).
#[test]
fn an_engines_spares_drop_on_its_thread_for_pages() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let (tell, told) = std::sync::mpsc::channel();
    engine.spares.unwaited(move || {
        let _ = tell.send(std::thread::current().id());
    });
    let pages = engine.on_pages_thread(|| std::thread::current().id());
    assert_eq!(told.recv_timeout(std::time::Duration::from_secs(20)), Ok(pages));
    assert_ne!(pages, engine.on_thread(|| std::thread::current().id()), "the premise: not the bodies' thread");
}

// A rest is taken on the engine's thread in turn: a compose handed over
// before it and not yet run takes its spares first, and the rest lets go
// of what that brought home — taken ahead of the turn, those would lie
// there through the rest.
#[test]
fn a_rest_is_taken_behind_the_composes_handed_over_before_it() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let handed = Sent(&raw const engine);
    // The engine's thread stands still: what is handed over now runs once
    // it goes on, in the order handed.
    // SAFETY: the engine is live through every call, and till what is
    // handed over has run — waited for below.
    unsafe { gpu_engine_stand_still(&engine, 300) };
    engine.posted(move || {
        // SAFETY: as above.
        let engine = unsafe { &*handed.taken() };
        let _composing = engine.spares.composing();
        drop(engine.spares.out(engine, 2));
        Some(())
    });
    // SAFETY: as above.
    unsafe { gpu_engine_pictures_rest(&engine, told, numbered()) };
    engine.on_thread(|| ());
    assert_eq!(engine.spares.made(), 1, "the premise: the compose ran, and took one");
    assert_eq!(engine.spares.bytes(), 0, "what it brought home is let go of at the rest behind it");
}

/// A base, and two rows each with what a hand holds over it: a picture
/// wider than [`OWN`] and a float.
fn two_held_over() -> [((i32, i32), (u32, u32)); 5] {
    let (picture, float) = (((-1, -1), (4, 4)), ((0, 0), (1, 1)));
    [((0, 0), (2, 2)), picture, float, picture, float]
}

/// A buffer of `rows` closed as a row over [`OWN`], unposed.
fn buffer(rows: &[Step]) -> Vec<Step> {
    let closing = closed_as_a_row(Over::Tiles(OWN), ResampleMap::moved(0, 0));
    [&[Step::Open][..], rows, &[closing]].concat()
}

/// What an engine of a test's own runs the plans here on.
struct Own<'a> {
    engine: &'a Engine,
    composite: &'a Composite,
}

impl Own<'_> {
    /// `steps` through `chains`, composited over [`TILES`].
    fn run(&self, laying: &Laying, chains: &[Chained], steps: &[Step]) -> Vec<u8> {
        let plan = laying.plan(chains, steps, None);
        let budget = self.composite.widest();
        let done = self.composite.run(self.engine, &plan, &TILES, NO_EDGE, budget).expect("run");
        self.engine.read_buffer(&done.out).expect("read back")
    }

    /// [`buffer`] of `rows`, by hand: `rows` composited alone over [`OWN`]
    /// into a buffer made for it, laid as a row of its own.
    fn by_hand(&self, laying: &mut Laying, rows: &[Step]) -> Step {
        let plan = laying.plan(&[], rows, None);
        let budget = self.composite.widest();
        let alone = self.composite.run(self.engine, &plan, &tiles_of(OWN), NO_EDGE, budget).expect("alone");
        let put = laying.laid(alone.out, OWN);
        matrixed(with_map(put, ResampleMap::moved(0, 0), 45000, SCREEN), 0)
    }
}

// Two buffers of a size run first in one plan are a buffer each — the
// second run does not take the first's, held till the plan is laid — and
// show as each composited alone into a buffer of its own. The plan walked
// again takes both and makes none; and other rows walked into them show as
// into buffers made new: nothing of what the walk before left there.
#[test]
fn a_plans_buffers_are_taken_again_and_show_as_ones_made_new() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let composite = Composite::new(&engine).expect("its executor");
    let own = Own { engine: &engine, composite: &composite };
    let mut laying = Laying::on(&engine, &two_held_over());
    let base = row(0, (0, 0), WHOLE, NORMAL);
    let held = |picture, float| [row(picture, (0, 0), WHOLE, NORMAL), row(float, (37, 21), 50000, MULTIPLY)];
    let both = [&[base][..], &buffer(&held(1, 2)), &buffer(&held(3, 4))].concat();
    assert_eq!(engine.spares.made(), 0);
    let got = own.run(&laying, &[], &both);
    assert_eq!(engine.spares.made(), 2, "a buffer each");
    assert_eq!(engine.spares.bytes(), 4 * TILE_BYTES, "kept past the walk");
    let by_hand = [base, own.by_hand(&mut laying, &held(1, 2)), own.by_hand(&mut laying, &held(3, 4))];
    assert!(got == own.run(&laying, &[], &by_hand));
    assert!(got != own.run(&laying, &[], &[base, by_hand[2], by_hand[2]]), "the premise: the first shows");
    assert!(own.run(&laying, &[], &both) == got, "out of the buffers the last walk left");
    assert_eq!(engine.spares.made(), 2, "none made again");
    // A float alone in each: most of each buffer nothing, where the walk
    // before left a picture.
    let floats = |first, second| [row(first, (5, 9), WHOLE, NORMAL), row(second, (90, 140), 30000, NORMAL)];
    let others = [&[base][..], &buffer(&floats(4, 2)[..1]), &buffer(&floats(4, 2)[1..])].concat();
    let got = own.run(&laying, &[], &others);
    assert_eq!(engine.spares.made(), 2, "the same two");
    let by_hand = [
        base,
        own.by_hand(&mut laying, &floats(4, 2)[..1]),
        own.by_hand(&mut laying, &floats(4, 2)[1..]),
    ];
    assert!(got == own.run(&laying, &[], &by_hand), "nothing of what the walk before left shows");
    // A walk in no picture's making is a compose of its own: one that
    // runs a single buffer first — of one tile, laid a tile and a half
    // down — takes one of the two, and lets go of the one it did not.
    let far = closed_as_a_row(Over::Tiles(OWN), ResampleMap::moved(0, 3 * TILE as i32 / 2));
    own.run(&laying, &[], &[base, Step::Open, row(1, (0, 0), WHOLE, NORMAL), far]);
    assert_eq!(engine.spares.made(), 2, "one kept holds its tile");
    assert_eq!(engine.spares.bytes(), 2 * TILE_BYTES, "the one it did not take is let go");
}

/// Two chains of a rectangle ([`held_chain`]), kept under 5 and 6 where
/// `held` keeps them.
fn two_chains(held: Option<&HeldChains>) -> Vec<Chained<'_>> {
    let (first, second) = (held.map(|held| (held, 5)), held.map(|held| (held, 6)));
    held_chain(first, false).into_iter().chain(held_chain(second, false)).collect()
}

// Two buffers of a size crossfaded at a mix in one plan are each
// crossfaded with its own tiles — the walk holds what the first's chain
// ran on while the second is run, a buffer each —, as the two show where
// a hold keeps each one's.
#[test]
fn two_buffers_at_a_mix_are_each_crossfaded_with_their_own_tiles() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let composite = Composite::new(&engine).expect("its executor");
    let own = Own { engine: &engine, composite: &composite };
    let laying = Laying::on(&engine, &[((0, 0), (2, 2)), ((0, 0), (2, 1)), ((-1, 1), (2, 1))]);
    let held = HeldChains::default();
    let crossfaded = |chain| mixed(close(45000, SCREEN, Some(0)), chain, 20000);
    let steps = [
        row(0, (0, 0), WHOLE, NORMAL),
        Step::Open,
        row(1, (3, -2), 50000, NORMAL),
        crossfaded(0),
        Step::Open,
        row(2, (-5, 4), WHOLE, NORMAL),
        crossfaded(1),
    ];
    let unheld = own.run(&laying, &two_chains(None), &steps);
    // Three of six tiles — what the first ran on, what its blur put, which
    // the second then ran on, and what the second's blur put — and three
    // planes of twelve: the blur's two, and one more for the second's
    // while what the first's matrix put is in one, the smallest idle that
    // held its tiles.
    assert_eq!(engine.spares.made(), 3 + 3, "the premise: each ran on a buffer of its own");
    assert_eq!(engine.spares.bytes(), (3 * 6 + 3 * 12) * TILE_BYTES);
    assert!(unheld == own.run(&laying, &two_chains(Some(&held)), &steps));
    assert_eq!(held.bytes_of(5), 2 * 6 * TILE_BYTES, "the premise: a hold keeps each one's");
}

// What a plug-in's read keeps of a chain — here the buffer the walk ran
// the chain on, the read its first op — is held by the read: no spare
// once the walk is through, and a walk after it, of a buffer of that
// size, writes nothing over the pixels the read gives.
#[test]
fn a_read_holds_the_buffer_it_keeps_from_the_walks_after_it() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let composite = Composite::new(&engine).expect("its executor");
    let own = Own { engine: &engine, composite: &composite };
    let laying = Laying::on(&engine, &[((0, 0), (2, 2)), ((0, 0), (2, 1)), ((-1, 1), (2, 1))]);
    let read = ChainRead::default();
    let op = Op::Read { read: read.clone(), rows: Vec::new() };
    let reading = [Chained { ops: vec![op], rect: RECT, held: None }];
    let base = row(0, (0, 0), WHOLE, NORMAL);
    let over = |set| [base, chained(row(set, (0, 0), WHOLE, NORMAL), 0)];
    own.run(&laying, &reading, &over(1));
    assert_eq!(engine.spares.made(), 1, "the premise: the chain ran on a buffer of the walk's");
    assert_eq!(engine.spares.bytes(), 0, "which the read holds, and is no spare");
    // Row 1's two tiles, where the chain's rectangle has them.
    let picture = [0, 0, 2 * TILE as i32, TILE as i32];
    let kept = read.pixels(&engine, picture, None).expect("kept");
    assert!(kept.iter().any(|&byte| byte != 0), "the premise: the row's pixels");
    // Another row, through a chain over the same rectangle.
    own.run(&laying, &held_chain(None, false), &over(2));
    // What it runs on, its blur's two planes and the tiles the blur puts.
    assert_eq!(engine.spares.made(), 1 + 4, "the walk after makes its own");
    assert!(read.pixels(&engine, picture, None).expect("kept still") == kept);
    let beside = engine.spares.bytes();
    drop(read);
    drop(reading);
    assert_eq!(engine.spares.bytes(), beside + 6 * TILE_BYTES, "let go of, it is a spare");
}

// A hold of a chain that ends at a read keeps the buffer the read handed
// on — the one the walk ran the chain on — as its own: no spare though the
// read is gone, taken by no walk after it, and laid as it was.
#[test]
fn a_hold_keeps_the_buffer_a_read_handed_on_once_the_read_is_gone() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let composite = Composite::new(&engine).expect("its executor");
    let own = Own { engine: &engine, composite: &composite };
    let laying = Laying::on(&engine, &[((0, 0), (2, 2)), ((0, 0), (2, 1)), ((-1, 1), (2, 1))]);
    let held = HeldChains::default();
    // A read of its own each walk: gone as the walk's chains are.
    let reading = || {
        let op = Op::Read { read: ChainRead::default(), rows: Vec::new() };
        [Chained { ops: vec![op], rect: RECT, held: Some((&held, 5)) }]
    };
    let base = row(0, (0, 0), WHOLE, NORMAL);
    let over = |set| [base, chained(row(set, (0, 0), WHOLE, NORMAL), 0)];
    let first = own.run(&laying, &reading(), &over(1));
    assert_eq!(held.bytes_of(5), 6 * TILE_BYTES, "the premise: it holds what the read handed on");
    assert_eq!(engine.spares.bytes(), 0, "which is the hold's, and no spare");
    // Another row, through a chain over the same rectangle.
    let other = own.run(&laying, &held_chain(None, false), &over(2));
    assert!(other != first, "the premise: row 2 shows otherwise");
    // What it runs on, its blur's two planes and the tiles the blur puts.
    assert_eq!(engine.spares.made(), 1 + 4, "the walk after makes its own");
    assert!(own.run(&laying, &reading(), &over(2)) == first, "and the hold lays as it did");
    let beside = engine.spares.bytes();
    held.let_go(5);
    assert_eq!(engine.spares.bytes(), beside + 6 * TILE_BYTES, "let go, it is a spare");
}

// A screen's compose keeps its buffers for its next, which makes none; a
// compose that runs none first — another screen's, between the two —
// lets go of none; they are counted among what the engine keeps for no
// picture, and given back past the pages nobody holds, before the work
// buffer.
#[test]
fn a_screens_next_compose_takes_the_buffers_its_last_made() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let composite = Composite::new(&engine).expect("its executor");
    let laying = Laying::on(&engine, &two_held_over());
    let base = row(0, (0, 0), WHOLE, NORMAL);
    let held = [row(1, (0, 0), WHOLE, NORMAL), row(2, (37, 21), 50000, MULTIPLY)];
    let over = [&[base][..], &buffer(&held)].concat();
    let page = [0, 0, 2 * TILE as i32, 2 * TILE as i32];
    let composed = |screen: &mut Screen, steps: &[Step]| {
        let plan = laying.plan(&[], steps, None);
        screen.compose(&engine, &composite, &plan, page, composite.widest()).expect("compose");
    };
    let mut screen = Screen::new(page, 1.0).expect("screen");
    composed(&mut screen, &over);
    let (made, kept) = (engine.spares.made(), engine.spares.bytes());
    assert!(made > 0 && kept > 0, "the premise: its buffers are kept past it");
    let mut other = Screen::new(page, 1.0).expect("another");
    composed(&mut other, &[base]);
    assert_eq!(engine.spares.bytes(), kept, "a compose that takes none lets go of none");
    composed(&mut screen, &over);
    assert_eq!(engine.spares.made(), made, "its next makes none");
    assert_eq!(engine.spares.bytes(), kept);
    // SAFETY: the engine is live through every call.
    let idle = || unsafe { gpu_engine_pictures_idle_bytes(&engine) };
    let (pages, work) = (engine.pictures.idle_bytes(), engine.work.bytes());
    assert!(work > 0, "the premise");
    assert_eq!(idle(), pages + work + kept);
    // SAFETY: as above.
    unsafe { gpu_engine_pictures_give_back(&engine, idle() - 1) };
    assert_eq!(engine.spares.bytes(), 0, "given back");
    assert_eq!(engine.work.bytes(), work, "before the work buffer");
    composed(&mut screen, &over);
    assert_eq!(engine.spares.bytes(), kept, "and made again by the next that runs one first");
}

// A picture kept in a pool of two tiles a page is made in a walk for each
// page, and the walks are one compose: the buffers of each are kept past
// it — the second walk's end lets go of none the first took —, and the
// picture made again, of other pixels, makes none.
#[test]
fn a_picture_made_in_several_walks_keeps_the_buffers_of_each() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let composite = Composite::new(&engine).expect("its executor");
    let laying = Laying::on(&engine, &[((0, 0), (2, 2)), ((0, 0), (1, 2))]);
    let base = row(0, (0, 0), WHOLE, NORMAL);
    // A column of two tiles laid half a tile down: one row of the output
    // reads one of them, the other both.
    let closing = closed_as_a_row(Over::Tiles(OWN), ResampleMap::moved(0, TILE as i32 / 2));
    let over = |opacity| [base, Step::Open, row(1, (0, 0), opacity, NORMAL), closing];
    let page = [0, 0, 2 * TILE as i32, 2 * TILE as i32];
    let pictures = Pictures::sized(2).expect("a pool");
    let made = |steps: &[Step]| {
        let plan = laying.plan(&[], steps, None);
        Kept::made_in(&engine, &composite, &plan, page, None, &pictures, composite.widest()).expect("kept")
    };
    let _first = made(&over(WHOLE));
    assert_eq!(engine.spares.made(), 2, "the premise: a walk a page, a buffer each");
    assert_eq!(engine.spares.bytes(), 3 * TILE_BYTES, "of one tile and of two, both kept");
    let _again = made(&over(40000));
    assert_eq!(engine.spares.made(), 2, "made again, none new");
    assert_eq!(engine.spares.bytes(), 3 * TILE_BYTES);
}

// A hold of a buffer closed at the whole mix keeps what its chain put
// alone — its matrix's, in a plane its blur had made, of twelve tiles:
// the smallest idle that held the six —, and what the chain ran on is a
// spare again as the walk ends: the next walk's.
#[test]
fn a_hold_at_the_whole_mix_keeps_what_its_chain_put_alone() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let composite = Composite::new(&engine).expect("its executor");
    let own = Own { engine: &engine, composite: &composite };
    let laying = Laying::on(&engine, &[((0, 0), (2, 2)), ((0, 0), (2, 1))]);
    let held = HeldChains::default();
    let whole = mixed(close(45000, SCREEN, Some(0)), 0, WHOLE);
    let buffer = [row(0, (0, 0), WHOLE, NORMAL), Step::Open, row(1, (3, -2), 50000, NORMAL), whole];
    own.run(&laying, &held_chain(Some((&held, 5)), false), &buffer);
    assert_eq!(held.bytes_of(5), 12 * TILE_BYTES, "what its chain put, and no more");
    let (made, kept) = (engine.spares.made(), engine.spares.bytes());
    // What it ran on, the tiles its blur put, and the other plane.
    assert_eq!(kept, (6 + 6 + 12) * TILE_BYTES, "what it ran on is a spare again");
    held.let_go(5);
    assert_eq!(engine.spares.bytes(), kept + 12 * TILE_BYTES, "let go, what it put is one too");
    own.run(&laying, &held_chain(None, false), &buffer);
    assert_eq!(engine.spares.made(), made, "and the walk after makes none");
}

// A plan of chains walked again makes no buffer — what its ops put, a
// blur's planes and a lens blur's map drawn from rows are all the
// engine's spares — and shows out of spares that hold another walk's
// leavings, scribbled over here, as out of ones made new.
#[test]
fn a_plan_of_chains_walked_again_makes_no_buffer_and_shows_the_same() {
    fn reading(rows: &[Step]) -> [Chained<'_>; 2] {
        [
            Chained { ops: lensed(MapTiles::Drawn(rows)), rect: RECT, held: None },
            Chained { ops: across(), rect: RECT, held: None },
        ]
    }
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let composite = Composite::new(&engine).expect("its executor");
    let own = Own { engine: &engine, composite: &composite };
    let laying = Laying::on(&engine, &[((0, 0), (2, 2)), ((-1, 0), (3, 1)), ((-1, 0), (3, 2))]);
    let steps = [row(0, (0, 0), WHOLE, NORMAL), chained(row(1, (0, 0), WHOLE, NORMAL), 0)];
    // A map of a chained row, and one of no rows: a walk of no steps, which
    // puts nothing over every tile all the same. Five buffers each, every
    // one a spare: what the reader runs on, its map and the lens blur's
    // sums — and what the map's row runs on and what its blur puts, which
    // the lens blur's totals and tiles then go in; or, of no rows, the
    // totals and the tiles themselves.
    let maps: [&[Step]; 2] = [&[chained(row(2, (4, -3), 50000, NORMAL), 1)], &[]];
    let shown = maps.map(|rows| {
        engine.spares.let_go();
        let before = engine.spares.made();
        let new = own.run(&laying, &reading(rows), &steps);
        let made = engine.spares.made();
        assert_eq!(made - before, 5, "each buffer the walk made is a spare");
        engine.spares.scribble(&engine);
        assert!(own.run(&laying, &reading(rows), &steps) == new, "nothing left in them shows");
        assert_eq!(engine.spares.made(), made, "walked again, none made");
        new
    });
    assert!(shown[0] != shown[1], "the premise: the map shows");
}

// A hold keeps the buffer its chain ran under for as long as it keeps what
// the chain put: no walk takes it meanwhile, and it is a spare once the
// hold lets go.
#[test]
fn a_hold_keeps_the_buffer_its_chain_ran_under_from_the_spares() {
    let turn = a_device_of_its_own();
    let engine = turn.engine();
    let composite = Composite::new(&engine).expect("its executor");
    let own = Own { engine: &engine, composite: &composite };
    let laying = Laying::on(&engine, &[((0, 0), (2, 2)), ((0, 0), (2, 1))]);
    let held = HeldChains::default();
    let holding = held_chain(Some((&held, 5)), false);
    let base = row(0, (0, 0), WHOLE, NORMAL);
    let crossfaded = mixed(close(45000, SCREEN, Some(0)), 0, 20000);
    let buffer = [base, Step::Open, row(1, (3, -2), 50000, NORMAL), crossfaded];
    let first = own.run(&laying, &holding, &buffer);
    // The chain's rectangle is six tiles: what it ran on, and what its
    // matrix put — in a plane its blur had made, of twelve: the smallest
    // idle that held the tiles.
    assert_eq!(held.bytes_of(5), (6 + 12) * TILE_BYTES, "the premise: it holds what its chain ran on");
    // The other plane and the tiles the blur put: the hold's are no spares.
    assert_eq!(engine.spares.made(), 4);
    assert_eq!(engine.spares.bytes(), (12 + 6) * TILE_BYTES, "which are the hold's, and no spares");
    assert!(own.run(&laying, &held_chain(None, false), &buffer) == first);
    assert_eq!(engine.spares.made(), 4 + 2, "a walk beside it makes its own: a plane, and tiles");
    assert!(own.run(&laying, &holding, &buffer) == first, "and the hold lays as it did");
    let beside = engine.spares.bytes();
    held.let_go(5);
    assert_eq!(engine.spares.bytes(), beside + (6 + 12) * TILE_BYTES, "let go, they are spares");
}
