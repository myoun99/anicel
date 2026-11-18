//! A movie's reads on a thread of its own, watched — so that a reader the
//! operating system never answers again costs one movie a stall, not every
//! movie in the app until it closes.
//!
//! 🔬Why (board a-seek-back-can-leave-the-movie-read-waiting-forever,
//! main PC, 2026-11-09): Media Foundation's first `ReadSample` after a seek
//! back now and then never comes back — about once in 2,000 runs of
//! `tests/decode.rs`'s read order, watched for ten minutes — and as often
//! says 「the end」 of a frame the movie holds (the landing gate's flake).
//! A fresh reader of the same file, opened while the first still stood,
//! answered in 8.5 ms: what breaks is one reader, not the decoder. Before
//! this the read was a plain call, and the app's one decode worker asks
//! every movie in a single line — one stall stopped them all.
//!
//! 🗣️유저 2026-11-09 (a-seek-back-can-leave-the-movie-read-waiting-forever-Q1):
//! 「조용히 새로 열어 그 프레임을 한 번 더 읽는다」 — a read that stands, or that
//! says 「the end」 inside the movie, is asked once more of a reader opened
//! afresh; when that one fails the same way, the movie answers 「could not
//! be read」 from then on.
//!
//! ⛔A standing call cannot be stopped. Its thread is let go: it keeps the
//! reader — and so the file, which Windows will not let anyone delete or
//! replace meanwhile — until the call comes back, if it ever does, and then
//! lets go of both itself. That is the cost Q1 accepted.
//! 🚨The thread reads into a picture of ITS OWN and the caller copies out of
//! it: a thread let go that wakes later must not write into memory its
//! caller has long since moved on from.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, PoisonError};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread::JoinHandle;
use std::time::Duration;

use super::{PAST_THE_END, Shape, Why, upright};

#[cfg(test)]
mod tests;

/// How long the reading thread may go without one call into the OS coming
/// back before the reader is called stuck.
///
/// 🚨**THE WATCH IS ON PROGRESS, NOT ON THE WHOLE READ.** A far seek walks up
/// to `WALK` pictures and may rightly take many seconds on a long GOP; each
/// picture pulled says so through `alive`, and only silence this long — one
/// call that does not return — is a stall. The stall is seen within twice
/// this: the watch looks once a window.
///
/// 🔬Three seconds, from the slowest WHOLE read measured (board card,
/// 2026-11-09; the rule set before measuring: under 1 s → 3 s, over → three
/// times it): 359 ms on the Surface (1080p, 200 runs, 25,600 reads — the
/// seek to the last frame, a walk of about 120 pictures) and 2.34 s on the
/// main PC under load (20 runs, the same walk). Both are walks of many
/// calls, so one call's slowest — what this measures — is well inside.
pub(super) const STALL: Duration = Duration::from_secs(3);

/// What a movie answers once a fresh reader has stood too.
pub(super) const STOPPED: &str = "the movie stopped answering";

/// Pictures between reads, shared by every movie rather than kept one a
/// movie: a read is in flight on at most one thread an isolate, and two
/// isolates read movies at once (the decode worker and a trimmed import's
/// own), so two pictures serve all [`super::DOCS`] slots — where one kept a
/// movie would hold eight 4K frames, 265 MB, for nothing.
static SPARE: Mutex<Vec<Vec<u8>>> = Mutex::new(Vec::new());
const SPARES: usize = 2;

/// A picture of `bytes`: a spare of that size, else a new one while there is
/// room for it to be kept, else a spare grown or cut to it.
///
/// ⚠️Two movies of two sizes read in turn each find their own: resizing one
/// picture back and forth would zero up to a whole 4K frame every read.
fn pooled(bytes: usize) -> Result<Vec<u8>, Why> {
    let mut picture = chosen(&mut SPARE.lock().unwrap_or_else(PoisonError::into_inner), bytes);
    if bytes > picture.len() {
        picture.try_reserve_exact(bytes - picture.len()).map_err(|_| "out of memory reading the frame")?;
    }
    picture.resize(bytes, 0);
    Ok(picture)
}

/// Which of `spares` a picture of `bytes` is read into — empty for a new one.
fn chosen(spares: &mut Vec<Vec<u8>>, bytes: usize) -> Vec<u8> {
    match spares.iter().position(|spare| spare.len() == bytes) {
        Some(at) => spares.swap_remove(at),
        None if spares.len() < SPARES => Vec::new(),
        None => spares.pop().unwrap_or_default(),
    }
}

/// `picture` kept for the next read, when there is room.
fn give_back(picture: Vec<u8>) {
    kept(&mut SPARE.lock().unwrap_or_else(PoisonError::into_inner), picture);
}

fn kept(spares: &mut Vec<Vec<u8>>, picture: Vec<u8>) {
    if spares.len() < SPARES {
        spares.push(picture);
    }
}

/// What the reading thread asks of a backend: the law's two calls, with a
/// way to say it is still getting somewhere.
pub(super) trait Pull: Send + 'static {
    fn reposition(&mut self, index: i64, rate: (i32, i32)) -> Result<(), Why>;

    /// Frame `index` at the stored size into `rgba`, calling `alive` each
    /// time a call into the OS comes back.
    fn read(&mut self, index: i64, rate: (i32, i32), rgba: &mut [u8], alive: &dyn Fn()) -> Result<(), Why>;
}

/// One request: the frame, whether the reader must be moved to it first,
/// and the picture to read it into — which travels to the thread and back.
struct Ask {
    index: i64,
    reposition: bool,
    picture: Vec<u8>,
}

/// The thread's answer, and the picture it was asked to fill.
type Answer = (Result<(), Why>, Vec<u8>);

/// How an ask went.
enum Asked {
    Answered(Result<(), Why>),
    /// Nothing came back for a whole [`STALL`] — or the thread is gone.
    Stood,
}

/// A movie's reading thread, which owns its backend's reader.
pub(super) struct Reading {
    /// Closed to end the thread: its loop ends and the reader drops ON it.
    asks: Option<mpsc::Sender<Ask>>,
    answers: mpsc::Receiver<Answer>,
    /// How many calls into the OS have come back on the thread.
    progress: Arc<AtomicU64>,
    /// Joined on close, so the reader is gone when a close returns; never
    /// joined once let go.
    thread: Option<JoinHandle<()>>,
}

impl Reading {
    /// Starts a thread reading through `pull`, a movie of `shape`.
    pub(super) fn spawn<P: Pull>(pull: P, shape: Shape) -> Result<Reading, Why> {
        let (asks, asked) = mpsc::channel::<Ask>();
        let (answer, answers) = mpsc::channel::<Answer>();
        let progress = Arc::new(AtomicU64::new(0));
        let ticks = Arc::clone(&progress);
        let thread = std::thread::Builder::new()
            .name("qa-video-read".into())
            .spawn(move || serve(pull, &shape, &asked, &answer, &ticks))
            .map_err(|_| "the movie's reading thread would not start")?;
        Ok(Reading { asks: Some(asks), answers, progress, thread: Some(thread) })
    }

    /// Frame `index` into `out` (the shown size), moved to first when
    /// `reposition`.
    fn ask(&mut self, index: i64, reposition: bool, out: &mut [u8], stall: Duration) -> Asked {
        let picture = match pooled(out.len()) {
            Ok(picture) => picture,
            Err(why) => return Asked::Answered(Err(why)),
        };
        let sent = self.asks.as_ref().is_some_and(|asks| asks.send(Ask { index, reposition, picture }).is_ok());
        if !sent {
            return Asked::Stood;
        }
        let mut heard = self.progress.load(Ordering::Relaxed);
        loop {
            match self.answers.recv_timeout(stall) {
                Ok((read, picture)) => {
                    if read.is_ok() {
                        out.copy_from_slice(&picture);
                    }
                    give_back(picture);
                    return Asked::Answered(read);
                }
                Err(RecvTimeoutError::Timeout) => {
                    let now = self.progress.load(Ordering::Relaxed);
                    if now == heard {
                        return Asked::Stood;
                    }
                    heard = now;
                }
                Err(RecvTimeoutError::Disconnected) => return Asked::Stood,
            }
        }
    }

    /// Lets a stood thread go without waiting for it: it ends, dropping its
    /// reader, if its call ever comes back.
    fn let_go(mut self) {
        self.thread = None;
    }
}

impl Drop for Reading {
    fn drop(&mut self) {
        self.asks = None;
        if let Some(thread) = self.thread.take() {
            // An idle thread: closing the asks ended its loop.
            let _ = thread.join();
        }
    }
}

/// The thread's body: each ask answered in turn, until the asks close.
fn serve<P: Pull>(
    mut pull: P,
    shape: &Shape,
    asked: &mpsc::Receiver<Ask>,
    answer: &mpsc::Sender<Answer>,
    ticks: &AtomicU64,
) {
    let alive = || {
        ticks.fetch_add(1, Ordering::Relaxed);
    };
    // Where a turned frame is decoded before it is turned upright: grown
    // once, kept across frames, and only for a movie with a turn.
    let mut scratch = Vec::new();
    for mut ask in asked {
        let read = answer_one(&mut pull, shape, &mut scratch, &mut ask, &alive);
        if answer.send((read, ask.picture)).is_err() {
            // Let go while it stood: nobody is waiting any more.
            break;
        }
    }
}

/// One ask, into its own picture: the reposition when it wants one, then the
/// read, the right way up.
fn answer_one<P: Pull>(
    pull: &mut P,
    shape: &Shape,
    scratch: &mut Vec<u8>,
    ask: &mut Ask,
    alive: &dyn Fn(),
) -> Result<(), Why> {
    if ask.reposition {
        pull.reposition(ask.index, shape.rate)?;
        alive();
    }
    let index = ask.index;
    upright(shape, scratch, &mut ask.picture, |into| pull.read(index, shape.rate, into, alive))
}

/// Which frame is wanted, and what the movie knows of it.
pub(super) struct Wanted {
    pub index: i64,
    /// Whether the reader must be moved to it first.
    pub reposition: bool,
    /// Whether the movie holds it — 「the end」 of a frame it holds is false.
    pub inside: bool,
}

/// Frame `wanted` of a movie into `out`, through `reading` — asked once more
/// of the reader `reopen` starts afresh when the first stood or said 「the
/// end」 inside the movie, and of none once that one failed the same way.
pub(super) fn read(
    reading: &mut Option<Reading>,
    wanted: &Wanted,
    out: &mut [u8],
    stall: Duration,
    reopen: impl FnOnce() -> Result<Reading, Why>,
) -> Result<(), Why> {
    let Some(first) = reading.as_mut() else {
        return Err(STOPPED.into());
    };
    match first.ask(wanted.index, wanted.reposition, out, stall) {
        Asked::Answered(read) if !falsely_ended(&read, wanted) => return read,
        // It answered, wrongly: idle, so it closes as any reader does.
        Asked::Answered(_) => *reading = None,
        Asked::Stood => {
            if let Some(stood) = reading.take() {
                stood.let_go();
            }
        }
    }
    let mut fresh = reopen()?;
    match fresh.ask(wanted.index, true, out, stall) {
        Asked::Answered(read) if !falsely_ended(&read, wanted) => {
            *reading = Some(fresh);
            read
        }
        Asked::Answered(_) => Err(STOPPED.into()),
        Asked::Stood => {
            fresh.let_go();
            Err(STOPPED.into())
        }
    }
}

/// Whether `read` said 「the end」 of a frame the movie holds.
fn falsely_ended(read: &Result<(), Why>, wanted: &Wanted) -> bool {
    wanted.inside && matches!(read, Err(why) if why == PAST_THE_END)
}
