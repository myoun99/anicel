//! The span byte stream, driven for real — ↩️the C engine's
//! `qa_win_range_stream_test.c`, check for check, which went with what it
//! tested in the connection round (connection-round-checklist H,
//! 2026-11-08).
//!
//! 🚨★★★**THIS IS WHERE THE BYTE ARITHMETIC IS.** Everything else about
//! opening a medium inside the project file is one API call per platform;
//! the Windows half is a hand-written COM object whose whole job is 「a
//! position is the medium's」 and 「never read past the span」. Get either
//! wrong and the reader is handed the archive's own header, or half a
//! movie, and both look like a corrupt file rather than a bug in there.
//!
//! ⚠️Its own test process, apart from the crate's: Media Foundation is
//! started here, and the crate's test of its start needs a process in
//! which nothing has started it yet (media_foundation/tests.rs).

#![cfg(windows)]

use std::ffi::{CString, c_void};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

use media::media_foundation::{span_stream, up};
use media::span::Span;
use oracle::framed;
use windows::Win32::Foundation::E_NOTIMPL;
use windows::Win32::Media::MediaFoundation::{
    IMFAsyncCallback, IMFAsyncCallback_Impl, IMFAsyncResult, IMFByteStream, MFBYTESTREAM_IS_READABLE,
    MFBYTESTREAM_IS_SEEKABLE, msoBegin, msoCurrent,
};
use windows::core::{Interface, Ref, Result, implement};

/// The fixture's byte at `at` — a pattern with a long period, so an
/// off-by-a-few in the base cannot land on the same value by luck.
fn pattern_byte(at: i64) -> u8 {
    ((at * 7 + (at >> 8) * 31) & 0xFF) as u8
}

const FIXTURE_BYTES: i64 = 8192;
const SPAN_BASE: i64 = 1000;
const SPAN_LEN: i64 = 500;

/// A file of this test's own, under a Korean name — every path that crosses
/// into the library is UTF-8, widened once inside — deleted on drop.
struct Fixture(PathBuf);

impl Fixture {
    fn new(name: &str, bytes: &[u8]) -> Fixture {
        let path = std::env::temp_dir().join(format!("미디어-스트림-{}-{name}.bin", std::process::id()));
        std::fs::write(&path, bytes).expect("write the fixture");
        Fixture(path)
    }

    fn patterned(name: &str) -> Fixture {
        Fixture::new(name, &(0..FIXTURE_BYTES).map(pattern_byte).collect::<Vec<_>>())
    }

    fn span(&self, offset: i64, length: i64, framed: bool) -> Option<Span> {
        Span::open(&CString::new(self.0.to_str().expect("UTF-8")).expect("no NUL"), offset, length, framed)
    }

    fn stream(&self, offset: i64, length: i64, framed: bool) -> IMFByteStream {
        span_stream::open(self.span(offset, length, framed).expect("the span opens"))
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

fn read(stream: &IMFByteStream, into: &mut [u8]) -> (Result<()>, u32) {
    let mut got = 0;
    // SAFETY: a plain COM call on a live stream; `into` is its buffer.
    let result = unsafe { stream.Read(into, &mut got) };
    (result, got)
}

/// A gate a callback is held shut at until the test opens it.
#[derive(Default)]
struct Gate {
    open: Mutex<bool>,
    opened: Condvar,
}

impl Gate {
    fn open(&self) {
        *self.open.lock().expect("the gate") = true;
        self.opened.notify_all();
    }

    /// Bounded: a test that forgot to open the gate fails, it does not hang.
    fn wait(&self) {
        let open = self.open.lock().expect("the gate");
        let _ = self.opened.wait_timeout_while(open, Duration::from_secs(5), |open| !*open);
    }
}

/// What a real caller does in its callback: finishes the read it began, on
/// the stream it began it on, with the result it was handed — the smallest
/// callback that can be invoked, so BeginRead/EndRead can be exercised
/// rather than assumed.
#[implement(IMFAsyncCallback)]
struct Callback {
    /// The stream, NOT held: what holds it is what is checked.
    stream: *mut c_void,
    gate: Option<Arc<Gate>>,
    seen: Arc<Seen>,
}

#[derive(Default)]
struct Seen {
    invoked: AtomicU32,
    ended: AtomicU32,
}

impl Seen {
    /// ⚠️`MFInvokeCallback` QUEUES the callback; it does not call it — so
    /// what is waited for is the notification, bounded, never assumed. Ten
    /// seconds, as the race below: a deadline costs only when it fails, and
    /// the work queue is the process's — the other tests' callbacks, a gated
    /// one among them, may be ahead of this one on a loaded machine.
    fn wait_invoked(&self) {
        let until = Instant::now() + Duration::from_secs(10);
        while self.invoked.load(Ordering::SeqCst) == 0 && Instant::now() < until {
            std::thread::sleep(Duration::from_millis(1));
        }
    }
}

impl IMFAsyncCallback_Impl for Callback_Impl {
    fn GetParameters(&self, _flags: *mut u32, _queue: *mut u32) -> Result<()> {
        // 「Use the defaults」 — the documented answer.
        Err(E_NOTIMPL.into())
    }

    fn Invoke(&self, result: Ref<IMFAsyncResult>) -> Result<()> {
        if let Some(gate) = &self.gate {
            gate.wait();
        }
        // SAFETY: the stream outlives its reads in flight — the property the
        // test that releases it before this runs is checking.
        let stream = unsafe { IMFByteStream::from_raw_borrowed(&self.stream) }.expect("a stream");
        // SAFETY: a plain COM call.
        let ended = unsafe { stream.EndRead(result.as_ref()) }.unwrap_or(0);
        self.seen.ended.store(ended, Ordering::SeqCst);
        self.seen.invoked.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }
}

/// A callback for reads on `stream`, held at `gate` when there is one.
fn callback_on(stream: &IMFByteStream, gate: Option<Arc<Gate>>) -> (IMFAsyncCallback, Arc<Seen>) {
    let seen = Arc::new(Seen::default());
    (Callback { stream: stream.as_raw(), gate, seen: seen.clone() }.into(), seen)
}

fn begin_read(stream: &IMFByteStream, into: &mut [u8], callback: &IMFAsyncCallback) -> Result<()> {
    // SAFETY: a plain COM call; the buffer outlives the read, which happens
    // inside the call.
    unsafe { stream.BeginRead(into, callback, None::<&windows::core::IUnknown>) }
}

#[test]
fn a_span_reads_as_the_medium_it_holds() {
    let fixture = Fixture::patterned("plain");
    let stream = fixture.stream(SPAN_BASE, SPAN_LEN, false);

    // 🚨THE LENGTH IS THE SPAN'S, not the file's. Reporting the file's is how
    // a reader walks off the end of the movie into whatever follows it.
    // SAFETY (each call below): a plain COM call on a live stream.
    assert_eq!(unsafe { stream.GetLength() }.expect("a length"), SPAN_LEN as u64);
    let capabilities = unsafe { stream.GetCapabilities() }.expect("capabilities");
    assert_ne!(capabilities & MFBYTESTREAM_IS_READABLE, 0, "readable");
    assert_ne!(capabilities & MFBYTESTREAM_IS_SEEKABLE, 0, "seekable");

    // A read at the start must land on the SPAN's first byte.
    let mut got = [0u8; 64];
    let (result, count) = read(&stream, &mut got[..16]);
    assert!(result.is_ok());
    assert_eq!(count, 16, "a first read gets what was asked for");
    assert!((0..16).all(|i| got[i] == pattern_byte(SPAN_BASE + i as i64)), "the first bytes are the span's own");

    // ⚠️THE CLAMP. Asking for more than the span holds must hand back only
    // what is inside it — the bytes after are somebody else's file.
    unsafe { stream.SetCurrentPosition((SPAN_LEN - 10) as u64) }.expect("placed");
    let (_, count) = read(&stream, &mut got[..40]);
    assert_eq!(count, 10, "a read past the end stops at the end");
    assert!((0..10).all(|i| got[i] == pattern_byte(SPAN_BASE + SPAN_LEN - 10 + i as i64)));
    assert!(unsafe { stream.IsEndOfStream() }.expect("an answer").as_bool(), "and it says it is at the end");
    let (result, count) = read(&stream, &mut got[..8]);
    assert!(result.is_ok() && count == 0, "at the end, a read is nothing — not an error");

    // Placed past the end is at the end; a position never leaves the medium.
    unsafe { stream.SetCurrentPosition(u64::MAX) }.expect("placed");
    assert_eq!(unsafe { stream.GetCurrentPosition() }.expect("a position"), SPAN_LEN as u64);

    // Seeking is relative to the SPAN, both ways, and clamped into it.
    assert_eq!(unsafe { stream.Seek(msoBegin, 100, 0) }.expect("a seek"), 100);
    let (_, count) = read(&stream, &mut got[..4]);
    assert_eq!(count, 4, "and reads from there");
    assert_eq!(got[0], pattern_byte(SPAN_BASE + 100), "with the span's bytes");
    assert_eq!(unsafe { stream.Seek(msoCurrent, -4, 0) }.expect("a seek"), 100, "back from where it is");
    assert_eq!(unsafe { stream.Seek(msoCurrent, -1000, 0) }.expect("a seek"), 0, "not before the start");
    assert_eq!(unsafe { stream.Seek(msoBegin, i64::MAX, 0) }.expect("a seek"), SPAN_LEN as u64, "nor past the end");

    // A span does not grow, and nothing is written into it.
    assert_eq!(unsafe { stream.SetLength(1) }.map_err(|error| error.code()), Err(E_NOTIMPL));
    assert_eq!(unsafe { stream.Write(&[0u8; 4]) }.map_err(|error| error.code()), Err(E_NOTIMPL));
}

#[test]
fn a_read_after_close_is_refused() {
    let fixture = Fixture::patterned("closed");
    let closed = fixture.stream(SPAN_BASE, SPAN_LEN, false);
    // SAFETY: a plain COM call.
    unsafe { closed.Close() }.expect("closed");
    let (result, count) = read(&closed, &mut [0u8; 8]);
    assert!(result.is_err(), "a read after Close is refused");
    assert_eq!(count, 0, "and reads nothing");
}

#[test]
fn a_span_past_the_end_of_its_file_is_no_stream() {
    // ⛔Refused, not truncated: a stream promising bytes the file cannot
    // supply turns into a movie that looks corrupt instead of a span that
    // was wrong. The span reader says so before a stream is made.
    let fixture = Fixture::patterned("past");
    assert!(fixture.span(FIXTURE_BYTES - 10, 100, false).is_none(), "a span past the end is refused");
    assert!(fixture.span(FIXTURE_BYTES - 100, 100, false).is_some(), "one ending at the end is fine");
}

#[test]
fn a_framed_span_reads_as_its_medium() {
    // 🚨The stream serves the MEDIUM's bytes, decompressed — its length is
    // the medium's and a position is a position in the medium. This is what
    // lets Media Foundation play a movie the save compressed.
    const MEDIUM: i64 = 20_000;
    const BLOCK: i64 = 4096;
    let medium: Vec<u8> = (0..MEDIUM).map(pattern_byte).collect();
    let blob = framed(&medium, BLOCK as usize);
    let fixture = Fixture::new("framed", &[vec![0xEE; SPAN_BASE as usize], blob.clone()].concat());
    let stream = fixture.stream(SPAN_BASE, blob.len() as i64, true);
    // SAFETY (each): a plain COM call on a live stream.
    assert_eq!(unsafe { stream.GetLength() }.expect("a length"), MEDIUM as u64, "its length is the MEDIUM's");
    // Across a block boundary, where a wrong block index shows.
    unsafe { stream.SetCurrentPosition((BLOCK * 2 - 8) as u64) }.expect("placed");
    let mut got = [0u8; 16];
    let (_, count) = read(&stream, &mut got);
    assert_eq!(count, 16, "a read across a block boundary");
    assert!((0..16).all(|i| got[i] == pattern_byte(BLOCK * 2 - 8 + i as i64)), "the medium's bytes, decompressed");
}

#[test]
fn the_async_pair_reads_and_each_end_answers_for_its_own_read() {
    // 🚨BEGIN/END READ. A source reader is free to use the async pair, and
    // E_NOTIMPL there can fail to open a file the stream can plainly read —
    // so the pair is implemented, and therefore has to be checked. Media
    // Foundation is started the engine's one way.
    assert!(up(), "Media Foundation starts");
    let fixture = Fixture::patterned("async");
    let stream = fixture.stream(SPAN_BASE, SPAN_LEN, false);

    let (callback, seen) = callback_on(&stream, None);
    // SAFETY: a plain COM call.
    unsafe { stream.SetCurrentPosition(200) }.expect("placed");
    let mut got = [0u8; 8];
    assert!(begin_read(&stream, &mut got, &callback).is_ok(), "BeginRead succeeds");
    // ⚠️The bytes are in the buffer already (the read itself is
    // synchronous); what is waited for is the notification — a caller that
    // never gets it would hang forever.
    seen.wait_invoked();
    assert_eq!(seen.invoked.load(Ordering::SeqCst), 1, "and the callback is invoked");
    assert_eq!(seen.ended.load(Ordering::SeqCst), 8, "EndRead reports what was read");
    assert!((0..8).all(|i| got[i] == pattern_byte(SPAN_BASE + 200 + i as i64)), "the span's bytes");

    // 🚨TWO READS IN FLIGHT: each EndRead answers for ITS read. The C kept
    // the count in one field of the stream, so a read that finished after
    // the next one began reported the next one's bytes — and a short read
    // is the end of the file to a parser.
    let gate = Arc::new(Gate::default());
    let (first, first_seen) = callback_on(&stream, Some(gate.clone()));
    let (second, second_seen) = callback_on(&stream, None);
    let (mut eight, mut three) = ([0u8; 8], [0u8; 3]);
    // SAFETY: a plain COM call.
    unsafe { stream.SetCurrentPosition(0) }.expect("placed");
    begin_read(&stream, &mut eight, &first).expect("the first read");
    begin_read(&stream, &mut three, &second).expect("the second read");
    // Both have begun before either ends — all the C's one field needs to
    // answer wrong — so the gate opens here and each is then waited for.
    // ⛔Not the second's first with the first held shut: the work queue may
    // run the two one after the other, and then the second waits behind the
    // held first until its deadline — the landing gate's debug run, 2026-11-07
    // 15:41 (board native-to-rust), saw nothing of it in two seconds.
    gate.open();
    first_seen.wait_invoked();
    second_seen.wait_invoked();
    assert_eq!(first_seen.ended.load(Ordering::SeqCst), 8, "the first read's EndRead reports the first read");
    assert_eq!(second_seen.ended.load(Ordering::SeqCst), 3, "the second's, the second");

    // ⛔Only a result this stream made carries an answer it can read: an
    // EndRead handed nothing is refused.
    // SAFETY: a plain COM call.
    assert!(unsafe { stream.EndRead(None::<&IMFAsyncResult>) }.is_err());
}

#[test]
fn a_read_in_flight_holds_its_stream() {
    // 🚨Its callback finishes it on the stream it began on, so the stream
    // must outlive the owner's last reference — a reader torn down while the
    // work queue is behind lets go of a stream whose read is not finished.
    assert!(up(), "Media Foundation starts");
    let fixture = Fixture::patterned("held");
    let held = fixture.stream(SPAN_BASE, SPAN_LEN, false);
    let gate = Arc::new(Gate::default());
    let (late, seen) = callback_on(&held, Some(gate.clone()));
    let mut got = [0u8; 8];
    begin_read(&held, &mut got, &late).expect("a read");
    let raw = held.into_raw();
    // SAFETY: the reference this test owned, let go of once — through the
    // vtable, for the count Release answers.
    let left = unsafe { ((*(*(raw as *mut *const windows::core::IUnknown_Vtbl))).Release)(raw) };
    assert_eq!(left, 1, "a read in flight keeps its stream alive");
    gate.open();
    seen.wait_invoked();
    assert_eq!(seen.ended.load(Ordering::SeqCst), 8, "and finishes on it");
}

/// A stream handed to another thread, as Media Foundation's work queue holds
/// one: the test keeps it alive until the thread is done.
struct Shared(*mut c_void);

// SAFETY: the stream is built to be called from any thread (its lock).
unsafe impl Send for Shared {}

#[test]
fn a_close_waits_for_the_read_it_meets() {
    // 🚨CLOSE RACING A READ (framed-movie-parity-hangs-under-load): Media
    // Foundation reads on its own work-queue threads while the thread that
    // owns the reader tears it down, and the C's Close freed the file and
    // the block buffers under a read still using them. A read after Close is
    // refused; a read Close meets finishes first. Big blocks, so a read
    // spends its time decoding one — the window a Close has to land in.
    const MEDIUM: i64 = 1 << 20;
    const BLOCK: usize = 1 << 16;
    let medium: Vec<u8> = (0..MEDIUM).map(pattern_byte).collect();
    let blob = framed(&medium, BLOCK);
    let fixture = Fixture::new("race", &blob);
    let mut reads = 0;
    // One deadline for the whole test, not one a round: a reader that never
    // gets going — what LIVENESS is there to catch — would otherwise wait it
    // out three hundred times.
    let until = Instant::now() + Duration::from_secs(10);
    for _ in 0..300 {
        let racing = fixture.stream(0, blob.len() as i64, true);
        let stop = Arc::new(AtomicBool::new(false));
        let count = Arc::new(AtomicU32::new(0));
        let reader = {
            let (shared, stop, count) = (Shared(racing.as_raw()), stop.clone(), count.clone());
            std::thread::spawn(move || {
                let shared = shared;
                // SAFETY: the test holds the stream until this thread is joined.
                let stream = unsafe { IMFByteStream::from_raw_borrowed(&shared.0) }.expect("a stream");
                let mut sink = vec![0u8; BLOCK];
                let mut at = 0;
                while !stop.load(Ordering::SeqCst) {
                    // Two blocks in turn, so every read DECODES one: a read
                    // that only copies the block the span kept is over
                    // before a Close can meet it.
                    at = if at == 0 { BLOCK as u64 * 5 } else { 0 };
                    // SAFETY: plain COM calls on a live stream.
                    unsafe { stream.SetCurrentPosition(at) }.expect("placed");
                    let _ = read(stream, &mut sink);
                    count.fetch_add(1, Ordering::SeqCst);
                }
            })
        };
        // Let the reader get going, then close under it. ⚠️By the clock, not
        // by a count of yields (the C's 200 × `Sleep(0)`, ported as
        // `yield_now`): Windows hands a yield only to a thread ready on the
        // same core, and a new thread queued behind a busy core may not run
        // in two hundred of them — the landing gate's debug run read nothing
        // in all 300 rounds (2026-11-07, board native-to-rust 13:21). Yields,
        // not a sleep, inside it: a 1 ms sleep took the test from 0.14 s to
        // 4–7 s on the Surface, where the timer is coarser than that.
        while count.load(Ordering::SeqCst) < 2 && Instant::now() < until {
            std::thread::yield_now();
        }
        // SAFETY: a plain COM call.
        unsafe { racing.Close() }.expect("closed");
        stop.store(true, Ordering::SeqCst);
        reader.join().expect("the reader finished");
        reads += count.load(Ordering::SeqCst);
    }
    assert!(reads > 0, "LIVENESS: the race read");
}
