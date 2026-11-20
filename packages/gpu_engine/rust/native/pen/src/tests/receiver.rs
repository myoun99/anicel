//! The one thread that receives (receiver.rs): when its timer wakes it —
//! the soonest work due, and none while no work lasts.

use std::time::{Duration, Instant};

use crate::receiver::{Schedule, Work};

const FOUR: Duration = Duration::from_millis(4);

#[test]
fn with_no_work_lasting_no_timer_wakes_it() {
    let at = Instant::now();
    let mut schedule = Schedule::default();
    assert_eq!(schedule.next(), None, "nothing yet");
    schedule.done(Work::Keep, FOUR, at, true);
    schedule.done(Work::Keep, FOUR, at + FOUR, false);
    assert_eq!(schedule.next(), None, "the button let go");
    assert!(schedule.due_by(at + FOUR * 10).is_empty());
}

#[test]
fn a_work_that_lasts_comes_round_every_so_often_from_when_it_was_done() {
    let at = Instant::now();
    let mut schedule = Schedule::default();
    schedule.done(Work::Drain, FOUR, at, true);
    assert_eq!(schedule.next(), Some(at + FOUR));
    assert!(schedule.due_by(at + FOUR - Duration::from_micros(1)).is_empty(), "not before");
    assert_eq!(schedule.due_by(at + FOUR), [(Work::Drain, FOUR)]);
    // Done late, it comes round from when it was done.
    let late = at + FOUR * 3;
    schedule.done(Work::Drain, FOUR, late, true);
    assert_eq!(schedule.next(), Some(late + FOUR));
}

#[test]
fn the_timer_wakes_it_for_the_soonest_and_only_what_is_due_is_done() {
    let at = Instant::now();
    let asleep = Duration::from_secs(10);
    let mut schedule = Schedule::default();
    schedule.done(Work::Drain, asleep, at, true);
    schedule.done(Work::Keep, FOUR, at, true);
    assert_eq!(schedule.next(), Some(at + FOUR), "the mouse's, before the drain's");
    assert_eq!(schedule.due_by(at + FOUR), [(Work::Keep, FOUR)], "each at its own turn");
    assert_eq!(schedule.due_by(at + asleep), [(Work::Drain, asleep), (Work::Keep, FOUR)]);
    schedule.done(Work::Keep, FOUR, at + FOUR, false);
    assert_eq!(schedule.next(), Some(at + asleep), "the drain's alone, the button let go");
}
