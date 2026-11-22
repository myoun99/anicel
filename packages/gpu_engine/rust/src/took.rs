//! HOW LONG EACH PLACE OF THE ENGINE TOOK, WHILE IT IS TIMED (H66 · H67,
//! 2026-11-22): the bodies handed to the engine's thread, each by where it
//! was handed over, and the submits, each by where it was made — a submit
//! waited out on that thread before the next thing is done, so what the
//! GPU took of it is its own and no other's.
//!
//! 🗣️유저 2026-11-22, a Galaxy Tab out of reach, build 1098 (card
//! the-galaxy-tab-canvas-went-slow-on-build-1095): 「팬줌똑같이느리고 …
//! 스트로크 첫부분 항상멈칫하고 긋는도중에도 한번씩 멈춤해 … 근본적으로
//! 해결하고있는거맞아?」 — a frame's 28 ms there were read off a photograph
//! as one number, `finish`, which said nothing of whose they were: the
//! kernels', the copy onto the window's image, or the wait for that image.
//! What was mended before it was what the sources suggested, and whether it
//! was the large part was known a build later.
//!
//! ⚠️TIMED, THE ENGINE IS NOT THE ENGINE THAT IS NOT: its thread stands
//! through each submit, where untimed it goes on encoding the next while
//! the GPU works — a frame is the sum of its parts and no shorter. So it is
//! a switch of its own ([`Took::times`]), off till asked for, and what the
//! places took is read beside a frame's whole time and not in its stead.
//!
//! ⛔NOT THE GPU's OWN CLOCK (timestamp queries): whether a tablet's driver
//! answers them is not known before the build is on it, and a build that
//! reads nothing there is a round lost — the rounds are two days apart
//! (유저 away 11-21~30). A wait on the engine's thread is what every read
//! already does.

use std::cell::Cell;
use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::panic::Location;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, PoisonError};
use std::time::{Duration, Instant};

/// Whose time a place's is.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum Whose {
    /// The engine's thread's, in a body: all of it but its waits for the
    /// GPU ([`Took::waited`]).
    Cpu,
    /// The GPU's, of one submit: from the driver having it till the GPU
    /// said it was done.
    Gpu,
}

impl Whose {
    fn name(self) -> &'static str {
        match self {
            Self::Cpu => "cpu",
            Self::Gpu => "gpu",
        }
    }
}

/// What one place took since it was last told.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct Sum {
    times: u64,
    micros: u64,
    /// The longest of its times.
    longest: u64,
    /// The workgroups of its submits in all — none, for a body.
    groups: u64,
}

/// What each place of one engine took ([`Whose`], its file, its line).
#[derive(Default)]
pub(crate) struct Took {
    timed: AtomicBool,
    places: Mutex<BTreeMap<(Whose, &'static str, u32), Sum>>,
}

thread_local! {
    /// How long this thread, an engine's, has waited for the GPU since a
    /// body began on it ([`Took::begun`], [`Took::waited`]) — a body's own
    /// time is the rest of it ([`Took::ended`]).
    static WAITED: Cell<u64> = const { Cell::new(0) };
}

fn micros(of: Duration) -> u64 {
    u64::try_from(of.as_micros()).unwrap_or(u64::MAX)
}

impl Took {
    fn places(&self) -> std::sync::MutexGuard<'_, BTreeMap<(Whose, &'static str, u32), Sum>> {
        self.places.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// Whether the engine is timed.
    pub(crate) fn timed(&self) -> bool {
        self.timed.load(Ordering::Relaxed)
    }

    /// Times the engine from here on, or no longer. Thrown, the switch
    /// forgets what was taken before: the two are not one engine's
    /// numbers (the head of this file). Asked for what it is already, it
    /// keeps what it has — whoever asks at each frame takes nothing away.
    pub(crate) fn times(&self, timed: bool) {
        if self.timed.swap(timed, Ordering::Relaxed) != timed {
            self.places().clear();
        }
    }

    fn add(&self, whose: Whose, by: &'static Location<'static>, took: u64, groups: u64) {
        let mut places = self.places();
        let sum = places.entry((whose, by.file(), by.line())).or_default();
        sum.times += 1;
        sum.micros = sum.micros.saturating_add(took);
        sum.longest = sum.longest.max(took);
        sum.groups = sum.groups.saturating_add(groups);
    }

    /// A body begins on this thread: when — none while nothing is timed.
    /// Its waits are counted from here: a submit handed to this thread from
    /// another, between two bodies, is waited out here too
    /// (`Queue::submit`), and is no part of the body after it.
    pub(crate) fn begun(&self) -> Option<Instant> {
        self.timed().then(|| {
            WAITED.set(0);
            Instant::now()
        })
    }

    /// The body [`Self::begun`] on this thread, handed over `by` there,
    /// ended: its own time is what it took less its waits for the GPU,
    /// which are their submits'.
    pub(crate) fn ended(&self, begun: Option<Instant>, by: &'static Location<'static>) {
        if let Some(begun) = begun {
            let own = micros(begun.elapsed()).saturating_sub(WAITED.get());
            self.add(Whose::Cpu, by, own, 0);
        }
    }

    /// This thread waited `long` for the GPU to finish the submit made `by`
    /// there, of `groups` workgroups in all.
    pub(crate) fn waited(&self, by: &'static Location<'static>, long: Duration, groups: u64) {
        let long = micros(long);
        WAITED.set(WAITED.get().saturating_add(long));
        self.add(Whose::Gpu, by, long, groups);
    }

    /// What each place took since this was last asked, a line each, the
    /// bodies' before the submits', by file and line:
    /// `cpu|gpu <file>:<line> times=<n> micros=<n> longest=<n> groups=<n>`
    /// — taken, so the next asked says what was taken after.
    pub(crate) fn told(&self) -> String {
        let places = std::mem::take(&mut *self.places());
        let mut told = String::new();
        for ((whose, file, line), Sum { times, micros, longest, groups }) in places {
            let _ = writeln!(
                told,
                "{} {file}:{line} times={times} micros={micros} longest={longest} groups={groups}",
                whose.name(),
            );
        }
        told
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn timed() -> Took {
        let took = Took::default();
        took.times(true);
        took
    }

    #[test]
    fn a_place_sums_its_times_and_keeps_its_longest() {
        let took = timed();
        let (here, line) = (Location::caller(), line!());
        took.waited(here, Duration::from_micros(300), 4);
        took.waited(here, Duration::from_micros(900), 6);
        took.waited(here, Duration::from_micros(500), 0);
        let place = format!("{}:{line}", file!());
        assert_eq!(took.told(), format!("gpu {place} times=3 micros=1700 longest=900 groups=10\n"));
    }

    #[test]
    fn told_takes_what_it_tells() {
        let took = timed();
        took.waited(Location::caller(), Duration::from_micros(1), 1);
        assert_ne!(took.told(), "");
        assert_eq!(took.told(), "", "told once, it is not told again");
    }

    #[test]
    fn a_body_s_own_time_is_what_it_took_less_its_waits_for_the_gpu() {
        let took = timed();
        let (body, submit) = (Location::caller(), Location::caller());
        let begun = took.begun();
        let since = Instant::now();
        std::thread::sleep(Duration::from_millis(12));
        took.waited(submit, Duration::from_millis(9), 1);
        took.ended(begun, body);
        let whole = micros(since.elapsed());
        let told = took.told();
        let own: u64 = told
            .lines()
            .find(|line| line.starts_with("cpu "))
            .and_then(|line| line.split(" micros=").nth(1))
            .and_then(|rest| rest.split(' ').next())
            .and_then(|micros| micros.parse().ok())
            .unwrap_or_else(|| panic!("no body's line: {told}"));
        // Slept twelve and said nine of them were the GPU's: three its own,
        // and no more than all of it less the nine.
        assert!((3_000..=whole - 9_000).contains(&own), "{own} of {whole}: {told}");
    }

    #[test]
    fn a_wait_before_a_body_began_is_not_taken_off_it() {
        let took = timed();
        let here = Location::caller();
        // In a body before it, and between the two.
        let first = took.begun();
        took.waited(here, Duration::from_secs(60), 0);
        took.ended(first, here);
        took.waited(here, Duration::from_secs(60), 0);
        let next = took.begun();
        std::thread::sleep(Duration::from_millis(5));
        took.ended(next, here);
        let told = took.told();
        let cpu = told.lines().find(|line| line.starts_with("cpu ")).expect("the bodies' line");
        let longest: u64 = cpu
            .split(" longest=")
            .nth(1)
            .and_then(|rest| rest.split(' ').next())
            .and_then(|micros| micros.parse().ok())
            .expect("its longest");
        assert!(longest >= 5_000, "the second body's five milliseconds are its own: {told}");
    }

    #[test]
    fn nothing_is_kept_while_nothing_is_timed() {
        let took = Took::default();
        let here = Location::caller();
        let begun = took.begun();
        assert_eq!(begun, None);
        took.ended(begun, here);
        assert_eq!(took.told(), "");
    }

    #[test]
    fn a_switch_thrown_forgets_what_was_taken_and_one_asked_as_it_is_keeps_it() {
        let took = timed();
        took.waited(Location::caller(), Duration::from_micros(1), 1);
        took.times(true);
        assert_ne!(took.told(), "", "timed and asked to be: nothing is taken away");
        took.waited(Location::caller(), Duration::from_micros(1), 1);
        took.times(false);
        took.times(true);
        assert_eq!(took.told(), "", "what it took before the switch went is forgotten");
    }

    #[test]
    fn bodies_are_told_before_submits_each_by_file_and_line() {
        let took = timed();
        let first = Location::caller();
        let second = Location::caller();
        took.waited(second, Duration::from_micros(2), 0);
        took.waited(first, Duration::from_micros(1), 0);
        took.ended(took.begun(), second);
        let told = took.told();
        let kinds: Vec<_> = told.lines().map(|line| &line[..3]).collect();
        assert_eq!(kinds, ["cpu", "gpu", "gpu"], "{told}");
        let lines: Vec<u32> = told
            .lines()
            .skip(1)
            .map(|line| line.split(' ').nth(1).and_then(|place| place.rsplit(':').next()).unwrap())
            .map(|line| line.parse().unwrap())
            .collect();
        assert_eq!(lines, [first.line(), second.line()]);
    }

    /// What `engine` says its places took since last asked, across the
    /// boundary as the app reads it.
    fn told_by(engine: &crate::device::Engine) -> String {
        let mut buffer = [0u8; 4096];
        // SAFETY: a live engine, and the buffer's room.
        let length = unsafe {
            crate::device::gpu_engine_took(std::ptr::from_ref(engine), buffer.as_mut_ptr(), buffer.len())
        };
        std::str::from_utf8(&buffer[..length]).expect("UTF-8").to_owned()
    }

    fn timed_engine(turn: &crate::testing::DeviceTurn) -> crate::device::Engine {
        let engine = turn.engine();
        // SAFETY: a live engine.
        unsafe { crate::device::gpu_engine_timed(&raw const engine, true) };
        engine
    }

    /// The figure `name` of the line of `told` that begins `place`.
    fn figure(told: &str, place: &str, name: &str) -> u64 {
        let line = told.lines().find(|line| line.starts_with(place));
        line.and_then(|line| line.split(&format!(" {name}=")).nth(1))
            .and_then(|rest| rest.split(' ').next())
            .and_then(|figure| figure.parse().ok())
            .unwrap_or_else(|| panic!("no {name} at {place}: {told}"))
    }

    #[test]
    fn a_timed_submit_is_waited_out_where_it_is_made_and_an_untimed_one_is_not() {
        let turn = crate::testing::a_device_of_its_own();
        let engine = timed_engine(&turn);
        let line = line!() + 1;
        engine.queue.submit([]);
        let done = |engine: &crate::device::Engine| engine.queue.submits.kept_now().last().map(|last| last.done);
        assert_eq!(done(&engine), Some(true), "back from a timed submit, the GPU has said it is done");
        let told = told_by(&engine);
        assert_eq!(figure(&told, &format!("gpu {}:{line} ", file!()), "times"), 1, "{told}");
        // SAFETY: a live engine.
        unsafe { crate::device::gpu_engine_timed(&raw const engine, false) };
        engine.queue.submit([]);
        assert_eq!(done(&engine), Some(false), "an untimed submit is waited for by no one");
        crate::testing::done_here(&engine).expect("the GPU done");
        assert_eq!(told_by(&engine), "", "and nothing is told of it");
    }

    #[test]
    fn a_timed_submit_says_the_workgroups_it_dispatched() {
        use crate::kernels::shared::{Encoded, encode, pipeline, whole};
        let turn = crate::testing::a_device_of_its_own();
        let engine = timed_engine(&turn);
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
            label: Some("took's dispatches"),
            size: 4,
            usage: wgpu::BufferUsages::STORAGE,
            mapped_at_creation: false,
        });
        let dispatch = |groups| Encoded { pipeline: &put, bound: whole(&[(0, &out)]), groups };
        let _ = told_by(&engine);
        let line = line!() + 1;
        encode(&engine, &[dispatch((2, 3, 1)), dispatch((4, 1, 1))]);
        let told = told_by(&engine);
        let place = format!("gpu {}:{line} ", file!());
        assert_eq!((figure(&told, &place, "times"), figure(&told, &place, "groups")), (1, 10), "{told}");
    }

    #[test]
    fn a_body_is_timed_by_where_it_was_handed_over_waited_for_or_not() {
        let turn = crate::testing::a_device_of_its_own();
        let engine = timed_engine(&turn);
        let nap = Duration::from_millis(8);
        let lent = line!() + 1;
        engine.on_thread(|| std::thread::sleep(nap));
        let posted = line!() + 1;
        engine.posted(move || {
            std::thread::sleep(nap);
            Some(())
        });
        crate::testing::done_here(&engine).expect("the GPU done");
        let told = told_by(&engine);
        for line in [lent, posted] {
            let place = format!("cpu {}:{line} ", file!());
            assert_eq!(figure(&told, &place, "times"), 1, "{told}");
            assert!(figure(&told, &place, "micros") >= 8_000, "{told}");
        }
    }

    #[test]
    fn a_body_handed_over_by_a_thing_is_timed_by_where_too() {
        use crate::device::{let_go, on_thread_of, posted_of};
        let turn = crate::testing::a_device_of_its_own();
        let engine = timed_engine(&turn);
        let thing = engine.hands(0u8);
        let nap = || std::thread::sleep(Duration::from_millis(2));
        let (lent, posted, let_go_of) = (line!() + 2, line!() + 4, line!() + 7);
        // SAFETY: a thing the engine handed out, and live.
        unsafe { on_thread_of(thing, nap) };
        // SAFETY: as above.
        unsafe { posted_of(thing, nap) };
        crate::testing::done_here(&engine).expect("the GPU done");
        // SAFETY: handed out by the engine, and let go of this once.
        unsafe { let_go(thing) };
        let told = told_by(&engine);
        for line in [lent, posted, let_go_of] {
            assert_eq!(figure(&told, &format!("cpu {}:{line} ", file!()), "times"), 1, "{told}");
        }
    }

    #[test]
    fn a_body_s_submits_are_the_gpu_s_time_and_not_the_body_s_too() {
        let turn = crate::testing::a_device_of_its_own();
        let engine = timed_engine(&turn);
        let since = Instant::now();
        let (body, submit) = (line!() + 1, line!() + 3);
        engine.on_thread(|| {
            for _ in 0..64 {
                engine.queue.submit([]);
            }
        });
        let whole = micros(since.elapsed());
        let told = told_by(&engine);
        let place = format!("gpu {}:{submit} ", file!());
        let own = figure(&told, &format!("cpu {}:{body} ", file!()), "micros");
        let waited = figure(&told, &place, "micros");
        assert_eq!(figure(&told, &place, "times"), 64, "{told}");
        // Sixty-four waits, counted once: with them in the body's own time
        // as well the two are more than all that passed.
        assert!(own + waited <= whole, "{own} + {waited} of {whole}: {told}");
    }
}
