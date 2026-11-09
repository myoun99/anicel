//! The reading thread's watch and its one more ask (유저 11-09, Q1), on fake
//! backends that do as they are told: a picture, 「the end」, a refusal, a
//! call that stands until the test lets it go, and a long walk that keeps
//! saying it is alive.
//!
//! ⚠️Every test that can stand runs under [`within`]: a change that waited
//! on a stood thread would otherwise hang the test run instead of failing.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, mpsc};
use std::time::{Duration, Instant};

use super::super::{PAST_THE_END, Shape, Why};
use super::{Pull, Reading, SPARES, STOPPED, Wanted, chosen, kept, read};

/// The watch's window here — short, so a stall is seen in a tenth of a second.
const STALL: Duration = Duration::from_millis(100);

/// A 2 × 1 movie of ten frames: eight bytes a picture.
const SHAPE: Shape = Shape { stored: (2, 1), rotation: 0, shown: (2, 1), rate: (24, 1), frame_count: 10 };

/// What a fake reader does the next time it is asked to read.
enum Step {
    /// Answers at once, every byte this value.
    Paint(u8),
    /// Says 「the end」.
    End,
    /// Refuses with this sentence.
    Refuse(&'static str),
    /// Stands until the test says go — for ever, if it never does — and then
    /// paints this.
    Stand(mpsc::Receiver<()>, u8),
    /// Takes `calls` calls of `each` apiece, alive after every one, and then
    /// paints this.
    Walk { calls: u32, each: Duration, paint: u8 },
}

/// What a test can see of its fake once the thread owns it.
#[derive(Clone, Default)]
struct Probe {
    repositions: Arc<AtomicUsize>,
    dropped: Arc<AtomicBool>,
}

impl Probe {
    fn repositions(&self) -> usize {
        self.repositions.load(Ordering::SeqCst)
    }

    fn dropped(&self) -> bool {
        self.dropped.load(Ordering::SeqCst)
    }
}

struct Fake {
    steps: VecDeque<Step>,
    probe: Probe,
}

impl Pull for Fake {
    fn reposition(&mut self, _index: i64, _rate: (i32, i32)) -> Result<(), Why> {
        self.probe.repositions.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }

    fn read(&mut self, _index: i64, _rate: (i32, i32), rgba: &mut [u8], alive: &dyn Fn()) -> Result<(), Why> {
        let paint = match self.steps.pop_front().expect("a step for every read") {
            Step::Paint(value) => value,
            Step::End => return Err(PAST_THE_END.into()),
            Step::Refuse(why) => return Err(why.into()),
            Step::Stand(go, value) => {
                let _ = go.recv();
                value
            }
            Step::Walk { calls, each, paint } => {
                for _ in 0..calls {
                    std::thread::sleep(each);
                    alive();
                }
                paint
            }
        };
        rgba.fill(paint);
        Ok(())
    }
}

impl Drop for Fake {
    fn drop(&mut self) {
        self.probe.dropped.store(true, Ordering::SeqCst);
    }
}

/// A reading thread over a fake that takes `steps`, and what the test can
/// see of it.
fn reading_of(steps: Vec<Step>) -> (Reading, Probe) {
    let probe = Probe::default();
    let fake = Fake { steps: steps.into(), probe: probe.clone() };
    (Reading::spawn(fake, SHAPE).expect("the thread starts"), probe)
}

/// A call that stands until the returned sender says go — and for as long
/// as the test holds it without sending.
fn standing(paint: u8) -> (Step, mpsc::Sender<()>) {
    let (go, wait) = mpsc::channel();
    (Step::Stand(wait, paint), go)
}

/// Frame 3, already positioned, inside the movie.
fn frame_3() -> Wanted {
    Wanted { index: 3, reposition: false, inside: true }
}

/// The reopen of a test that must not reopen.
fn no_reopen() -> Result<Reading, Why> {
    panic!("asked a fresh reader when the first one answered")
}

/// `body`, failed rather than hung when it does not end within `limit`.
fn within(limit: Duration, body: impl FnOnce() + Send + 'static) {
    let (done, ended) = mpsc::channel();
    let ran = std::thread::spawn(move || {
        body();
        let _ = done.send(());
    });
    match ended.recv_timeout(limit) {
        Ok(()) => ran.join().expect("the body"),
        Err(mpsc::RecvTimeoutError::Disconnected) => std::panic::resume_unwind(ran.join().expect_err("it panicked")),
        Err(mpsc::RecvTimeoutError::Timeout) => {
            panic!("still waiting after {limit:?} — something waits on a stood thread")
        }
    }
}

#[test]
fn an_answer_is_copied_out_and_the_thread_is_kept() {
    let (reading, probe) = reading_of(vec![Step::Paint(7), Step::Paint(9)]);
    let mut reading = Some(reading);
    let mut out = [0u8; 8];
    let moved = Wanted { index: 3, reposition: true, inside: true };
    read(&mut reading, &moved, &mut out, STALL, no_reopen).expect("answered");
    assert_eq!(out, [7; 8]);
    read(&mut reading, &frame_3(), &mut out, STALL, no_reopen).expect("answered");
    assert_eq!((out, probe.repositions()), ([9; 8], 1), "positioned: no second reposition");
}

#[test]
fn a_read_that_stands_is_asked_again_of_a_fresh_reader() {
    within(Duration::from_secs(5), || {
        let (stand, _held) = standing(1);
        let mut reading = Some(reading_of(vec![stand]).0);
        let (fresh, fresh_probe) = reading_of(vec![Step::Paint(5), Step::Paint(6)]);
        let mut out = [0u8; 8];
        let began = Instant::now();
        read(&mut reading, &frame_3(), &mut out, STALL, || Ok(fresh)).expect("the fresh reader answered");
        let took = began.elapsed();
        assert_eq!(out, [5; 8]);
        assert!(took >= STALL && took < Duration::from_secs(2), "seen as stood, and not waited on: {took:?}");
        assert_eq!(fresh_probe.repositions(), 1, "a fresh reader is moved to the frame first");
        read(&mut reading, &frame_3(), &mut out, STALL, no_reopen).expect("the fresh reader is the movie's now");
        assert_eq!(out, [6; 8]);
    });
}

#[test]
fn a_fresh_reader_that_stands_too_stops_the_movie() {
    within(Duration::from_secs(5), || {
        let ((first, _held), (second, _held_too)) = (standing(1), standing(2));
        let mut reading = Some(reading_of(vec![first]).0);
        let fresh = reading_of(vec![second]).0;
        let mut out = [0u8; 8];
        let stopped = read(&mut reading, &frame_3(), &mut out, STALL, || Ok(fresh));
        assert_eq!(stopped.map_err(String::from), Err(STOPPED.to_string()));
        assert!(reading.is_none(), "no reader is left to ask");
        assert_eq!(out, [0; 8], "nothing was written");
        let began = Instant::now();
        let again = read(&mut reading, &frame_3(), &mut out, STALL, no_reopen);
        assert_eq!(again.map_err(String::from), Err(STOPPED.to_string()));
        assert!(began.elapsed() < STALL, "answered at once, without waiting or reopening");
    });
}

#[test]
fn the_end_said_inside_the_movie_is_asked_again_and_the_first_reader_closed() {
    within(Duration::from_secs(5), || {
        let (first, first_probe) = reading_of(vec![Step::End]);
        let mut reading = Some(first);
        let fresh = reading_of(vec![Step::Paint(4)]).0;
        let mut out = [0u8; 8];
        read(&mut reading, &frame_3(), &mut out, STALL, || Ok(fresh)).expect("the fresh reader answered");
        assert_eq!(out, [4; 8]);
        assert!(first_probe.dropped(), "the reader that answered wrongly is closed, not left on its thread");
    });
}

#[test]
fn the_end_said_past_the_movie_is_the_answer() {
    let (reading, _) = reading_of(vec![Step::End]);
    let mut reading = Some(reading);
    let past = Wanted { index: 10, reposition: false, inside: false };
    let ended = read(&mut reading, &past, &mut [0u8; 8], STALL, no_reopen);
    assert_eq!(ended.map_err(String::from), Err(PAST_THE_END.to_string()));
    assert!(reading.is_some(), "the reader stays: it told the truth");
}

#[test]
fn a_refusal_is_the_answer() {
    let (reading, _) = reading_of(vec![Step::Refuse("no picture reached that frame")]);
    let mut reading = Some(reading);
    let refused = read(&mut reading, &frame_3(), &mut [0u8; 8], STALL, no_reopen);
    assert_eq!(refused.map_err(String::from), Err("no picture reached that frame".to_string()));
    assert!(reading.is_some());
}

#[test]
fn a_long_walk_that_keeps_answering_is_not_a_stall() {
    // A window eight calls wide, so a busy machine's late sleep is not a
    // stall; the walk is two and a half windows long.
    let stall = Duration::from_millis(400);
    let walk = Step::Walk { calls: 20, each: stall / 8, paint: 3 };
    let (reading, _) = reading_of(vec![walk]);
    let mut reading = Some(reading);
    let mut out = [0u8; 8];
    let began = Instant::now();
    read(&mut reading, &frame_3(), &mut out, stall, no_reopen).expect("a slow read is still a read");
    assert!(began.elapsed() >= stall * 2, "it took more than one window: {:?}", began.elapsed());
    assert_eq!(out, [3; 8]);
}

#[test]
fn a_thread_let_go_never_writes_the_callers_picture_and_closes_its_reader_when_it_wakes() {
    within(Duration::from_secs(5), || {
        let (stand, go) = standing(0xEE);
        let (first, first_probe) = reading_of(vec![stand]);
        let mut reading = Some(first);
        let fresh = reading_of(vec![Step::Paint(5)]).0;
        let mut out = [0u8; 8];
        read(&mut reading, &frame_3(), &mut out, STALL, || Ok(fresh)).expect("answered");
        assert!(!first_probe.dropped(), "the stood reader is still held by its call");
        go.send(()).expect("the stood call is still waiting");
        let began = Instant::now();
        while !first_probe.dropped() && began.elapsed() < Duration::from_secs(2) {
            std::thread::sleep(Duration::from_millis(5));
        }
        assert!(first_probe.dropped(), "once its call came back it let go of the reader itself");
        assert_eq!(out, [5; 8], "the late picture went nowhere near the caller's");
    });
}

#[test]
fn a_close_lets_go_of_the_reader_before_it_returns() {
    let (reading, probe) = reading_of(vec![Step::Paint(1)]);
    let mut reading = Some(reading);
    read(&mut reading, &frame_3(), &mut [0u8; 8], STALL, no_reopen).expect("answered");
    drop(reading);
    assert!(probe.dropped(), "closed, not still closing — a file let go after the close returns stays locked");
}

#[test]
fn a_reopen_that_fails_says_why_and_the_movie_stops() {
    within(Duration::from_secs(5), || {
        let (stand, _held) = standing(1);
        let mut reading = Some(reading_of(vec![stand]).0);
        let mut out = [0u8; 8];
        let failed = read(&mut reading, &frame_3(), &mut out, STALL, || Err("that movie could not be read".into()));
        assert_eq!(failed.map_err(String::from), Err("that movie could not be read".to_string()));
        let again = read(&mut reading, &frame_3(), &mut out, STALL, no_reopen);
        assert_eq!(again.map_err(String::from), Err(STOPPED.to_string()));
    });
}

#[test]
fn the_end_said_again_by_the_fresh_reader_stops_the_movie() {
    let mut reading = Some(reading_of(vec![Step::End]).0);
    let fresh = reading_of(vec![Step::End]).0;
    let stopped = read(&mut reading, &frame_3(), &mut [0u8; 8], STALL, || Ok(fresh));
    assert_eq!(stopped.map_err(String::from), Err(STOPPED.to_string()));
    assert!(reading.is_none());
}

#[test]
fn a_picture_of_the_size_kept_is_the_one_reused() {
    let (small, large) = (vec![1u8; 8], vec![2u8; 32]);
    let large_at = large.as_ptr();
    let mut spares = vec![large, small];
    let picture = chosen(&mut spares, 32);
    assert_eq!(picture.as_ptr(), large_at, "the 32-byte spare, though it was not the last");
    assert_eq!(spares.len(), 1);
}

#[test]
fn a_new_size_gets_a_new_picture_while_there_is_room_to_keep_it() {
    let mut spares = vec![vec![1u8; 8]];
    assert!(chosen(&mut spares, 32).is_empty(), "a new picture, so the 8-byte movie keeps its own");
    assert_eq!(spares.len(), 1, "the other movie's spare is left where it was");
}

#[test]
fn with_no_room_a_spare_is_resized_rather_than_one_more_kept() {
    let mut spares: Vec<Vec<u8>> = (0..SPARES).map(|k| vec![0u8; 8 + k]).collect();
    assert!(!chosen(&mut spares, 100).is_empty(), "a spare reused");
    for k in 0..=SPARES {
        kept(&mut spares, vec![0u8; 200 + k]);
    }
    assert_eq!(spares.len(), SPARES, "never more than {SPARES} kept");
}

/// Every backend's walk says it is alive after each picture it pulls: the
/// watch is on progress, and a backend that never said so would have each
/// long walk — a far seek on a long GOP — called a stall and its movie
/// stopped.
///
/// ⚠️A scan of the source, not a run: each walk runs only on its own OS, and
/// a build runs one of them. Its body is the text from `pub fn read(` to the
/// method's closing brace.
#[test]
fn every_backend_says_it_is_alive_inside_its_walk() {
    let backends = [
        ("windows.rs", include_str!("../windows.rs")),
        ("apple.rs", include_str!("../apple.rs")),
        ("android.rs", include_str!("../android.rs")),
    ];
    for (name, source) in backends {
        let read = source.split("pub fn read(").nth(1).unwrap_or_else(|| panic!("{name} has a read"));
        let body = &read[..read.find("\n    }").unwrap_or_else(|| panic!("{name}'s read ends"))];
        let walk = body.find("for _ in 0..WALK").unwrap_or_else(|| panic!("{name}'s read walks"));
        assert!(body[walk..].contains("alive();"), "{name}'s walk never says it is alive");
    }
}
