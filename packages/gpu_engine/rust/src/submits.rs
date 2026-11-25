//! WHAT THE GPU WAS HANDED AND HAS NOT SAID IT FINISHED (H63, 2026-11-18):
//! each submit's number, when it was made, where from and how much it
//! dispatched — and whether the GPU said it finished it. Kept in memory,
//! under a lock of its own: read after a device went, when nothing else of
//! the engine answers (`gpu_engine_unfinished`).
//!
//! 🗣️H63 (관제 · 타임라인/콘티 11-18): the GPU driver reset twice as the
//! conte panel's playback reached a third cut, and nothing said what the
//! engine had handed the GPU then — the next reset is to leave it in the
//! app's file (`gpu-loss-log.txt`) beside the cut, frame and canvas.

use std::cell::Cell;
use std::collections::VecDeque;
use std::fmt::Write as _;
use std::panic::Location;
use std::sync::{Mutex, PoisonError};
use std::time::{SystemTime, UNIX_EPOCH};

/// How many submits are kept, the newest.
pub(crate) const KEPT: usize = 64;

/// One submit.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Submitted {
    /// Its place among the engine's submits, from 1.
    pub(crate) number: u64,
    /// When it was made: microseconds since 1970 on the system's clock —
    /// the clock Dart's `DateTime.now().microsecondsSinceEpoch` reads.
    pub(crate) at_micros: i64,
    /// Where in the engine it was made.
    pub(crate) by: &'static Location<'static>,
    /// The dispatches encoded for it, and their workgroups in all
    /// ([`encoded`]).
    pub(crate) dispatches: u32,
    pub(crate) groups: u64,
    /// Whether the GPU said it finished it — as of the device's last poll,
    /// where the engine hears it (wgpu's `on_submitted_work_done`).
    pub(crate) done: bool,
}

/// The submits of one engine, the newest [`KEPT`].
#[derive(Default)]
pub(crate) struct Submits(Mutex<Kept>);

#[derive(Default)]
struct Kept {
    made: u64,
    /// The newest the GPU said it finished, by number — none, 0.
    done: u64,
    submits: VecDeque<Submitted>,
}

impl Submits {
    fn kept(&self) -> std::sync::MutexGuard<'_, Kept> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// Notes a submit made `by` there now, with what this thread encoded
    /// since its last ([`encoded`]): the submit, as it is kept.
    pub(crate) fn note(&self, by: &'static Location<'static>) -> Submitted {
        let (dispatches, groups) = ENCODED.take();
        let at_micros = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |since| i64::try_from(since.as_micros()).unwrap_or(i64::MAX));
        let mut kept = self.kept();
        kept.made += 1;
        let number = kept.made;
        if kept.submits.len() == KEPT {
            kept.submits.pop_front();
        }
        let noted = Submitted { number, at_micros, by, dispatches, groups, done: false };
        kept.submits.push_back(noted);
        noted
    }

    /// The GPU said it finished the submit `number` — and so every one
    /// before it, which went ahead of it.
    pub(crate) fn done(&self, number: u64) {
        let mut kept = self.kept();
        kept.done = kept.done.max(number);
        for submit in kept.submits.iter_mut().filter(|submit| submit.number <= number) {
            submit.done = true;
        }
    }

    /// How many submits the GPU has not said it finished — however many
    /// that is, past the newest kept: what the screen shows as the GPU's
    /// line (H66, 관제 2026-11-23 23:24 「쌓인 걸음(낸 것 − 끝난 것) 실시간」).
    /// ⚠️As of the device's last poll, where the engine hears it.
    pub(crate) fn behind(&self) -> u64 {
        let kept = self.kept();
        kept.made - kept.done
    }

    /// The submits kept, the oldest first.
    pub(crate) fn kept_now(&self) -> Vec<Submitted> {
        self.kept().submits.iter().copied().collect()
    }

    /// Each submit the GPU has not said it finished, the oldest first, and
    /// the newest it has, a line each:
    /// `submit #<number> at <µs> <file>:<line> dispatches=<n> groups=<n>
    /// unfinished|last-done` — what the app writes in its file as it is.
    pub(crate) fn told(&self) -> String {
        let kept = self.kept_now();
        let last_done = kept.iter().rev().find(|submit| submit.done);
        let mut told = String::new();
        for submit in last_done.into_iter().chain(kept.iter().filter(|submit| !submit.done)) {
            let Submitted { number, at_micros, by, dispatches, groups, done } = submit;
            let state = if *done { "last-done" } else { "unfinished" };
            let _ = writeln!(
                told,
                "submit #{number} at {at_micros} {}:{} dispatches={dispatches} groups={groups} {state}",
                by.file(),
                by.line(),
            );
        }
        told
    }
}

thread_local! {
    /// What this thread encoded since its last submit: dispatches, and
    /// their workgroups in all.
    static ENCODED: Cell<(u32, u64)> = const { Cell::new((0, 0)) };
}

/// Counts `groups` — a dispatch's (x, y, z) workgroups each — toward this
/// thread's next submit ([`Submits::note`]).
pub(crate) fn encoded(groups: impl IntoIterator<Item = (u32, u32, u32)>) {
    ENCODED.with(|encoded| {
        let (mut dispatches, mut all) = encoded.get();
        for (across, down, deep) in groups {
            dispatches = dispatches.saturating_add(1);
            all = all.saturating_add(u64::from(across) * u64::from(down) * u64::from(deep));
        }
        encoded.set((dispatches, all));
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_submit_is_numbered_timed_and_placed_where_it_was_made() {
        let submits = Submits::default();
        let before = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_micros() as i64;
        let here = Location::caller();
        let (first, second) = (submits.note(here).number, submits.note(here).number);
        let after = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_micros() as i64;
        let kept = submits.kept_now();
        assert_eq!((first, second), (1, 2));
        assert_eq!(kept.iter().map(|submit| submit.number).collect::<Vec<_>>(), [1, 2]);
        assert!(kept.iter().all(|submit| (before..=after).contains(&submit.at_micros)), "{kept:?}");
        assert!(kept.iter().all(|submit| submit.by == here && !submit.done));
    }

    #[test]
    fn what_a_thread_encoded_goes_with_its_next_submit_alone() {
        let submits = Submits::default();
        encoded([(2, 3, 4), (5, 1, 1)]);
        let by = Location::caller();
        submits.note(by);
        submits.note(by);
        let sizes: Vec<_> =
            submits.kept_now().iter().map(|submit| (submit.dispatches, submit.groups)).collect();
        assert_eq!(sizes, [(2, 2 * 3 * 4 + 5), (0, 0)]);
    }

    #[test]
    fn a_submit_said_finished_finishes_every_one_before_it() {
        let submits = Submits::default();
        let by = Location::caller();
        for _ in 0..4 {
            submits.note(by);
        }
        submits.done(2);
        let done: Vec<_> = submits.kept_now().iter().map(|submit| submit.done).collect();
        assert_eq!(done, [true, true, false, false]);
    }

    #[test]
    fn behind_are_the_submits_made_past_the_newest_finished_however_many() {
        let submits = Submits::default();
        let by = Location::caller();
        assert_eq!(submits.behind(), 0);
        for _ in 0..KEPT + 6 {
            submits.note(by);
        }
        assert_eq!(submits.behind(), KEPT as u64 + 6, "past the kept, too");
        submits.done(4);
        assert_eq!(submits.behind(), KEPT as u64 + 2);
        submits.done(3);
        assert_eq!(submits.behind(), KEPT as u64 + 2, "an older word takes nothing back");
        submits.done(KEPT as u64 + 6);
        assert_eq!(submits.behind(), 0);
    }

    #[test]
    fn the_newest_kept_are_the_last_sixty_four() {
        let submits = Submits::default();
        for _ in 0..KEPT + 3 {
            submits.note(Location::caller());
        }
        let numbers: Vec<_> = submits.kept_now().iter().map(|submit| submit.number).collect();
        assert_eq!(numbers, (4..=KEPT as u64 + 3).collect::<Vec<_>>());
    }

    #[test]
    fn told_is_the_newest_finished_then_every_unfinished_oldest_first() {
        let submits = Submits::default();
        let by = Location::caller();
        encoded([(8, 8, 1)]);
        for _ in 0..4 {
            submits.note(by);
        }
        submits.done(2);
        let told = submits.told();
        let lines: Vec<_> = told.lines().collect();
        let place = format!("{}:{}", by.file(), by.line());
        let at = |number: usize| submits.kept_now()[number - 1].at_micros;
        assert_eq!(
            lines,
            [
                format!("submit #2 at {} {place} dispatches=0 groups=0 last-done", at(2)),
                format!("submit #3 at {} {place} dispatches=0 groups=0 unfinished", at(3)),
                format!("submit #4 at {} {place} dispatches=0 groups=0 unfinished", at(4)),
            ]
        );
        assert_eq!(Submits::default().told(), "", "nothing submitted, nothing told");
    }

    #[test]
    fn a_submit_says_the_dispatches_encoded_for_it_and_their_workgroups() {
        use crate::kernels::shared::{Encoded, encode, pipeline, whole};
        let turn = crate::testing::a_device_of_its_own();
        let engine = turn.engine();
        let put = pipeline(
            &engine,
            &[
                "@group(0) @binding(0) var<storage, read_write> out: array<u32>;",
                "@compute @workgroup_size(1)",
                "fn put(@builtin(global_invocation_id) at: vec3<u32>) { out[0] = at.x; }",
            ],
            "put",
        );
        let out = engine.device().create_buffer(&wgpu::BufferDescriptor {
            label: Some("submits' dispatches"),
            size: 4,
            usage: wgpu::BufferUsages::STORAGE,
            mapped_at_creation: false,
        });
        let dispatch = |groups| Encoded { pipeline: &put, bound: whole(&[(0, &out)]), groups };
        let line = line!() + 1;
        encode(&engine, &[dispatch((2, 3, 1)), dispatch((4, 1, 1))]);
        crate::testing::done_here(&engine).expect("the GPU done");
        let told = engine.queue.submits.told();
        let made = format!("{}:{line} dispatches=2 groups=10 last-done", file!());
        assert!(told.lines().any(|told| told.ends_with(&made)), "{told}");
    }

    #[test]
    fn the_engine_notes_each_submit_where_it_was_made_and_hears_it_finished() {
        let turn = crate::testing::a_device_of_its_own();
        let engine = turn.engine();
        let line = line!() + 1;
        engine.queue.submit([]);
        crate::testing::done_here(&engine).expect("the GPU done");
        let mut buffer = [0u8; 1024];
        // SAFETY: a live engine, and the buffer's room.
        let length = unsafe { crate::device::gpu_engine_unfinished(&raw const engine, buffer.as_mut_ptr(), buffer.len()) };
        let told = std::str::from_utf8(&buffer[..length]).expect("UTF-8");
        let made = format!("{}:{line} dispatches=0 groups=0 last-done", file!());
        assert!(told.lines().any(|told| told.ends_with(&made)), "{told}");
    }
}
