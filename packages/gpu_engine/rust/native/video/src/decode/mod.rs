//! The OS video decoder: a movie file in, one RGBA frame out, in Rust
//! (native-to-rust, 저장; ↩️the engine's `qa_video_decode.c` until the
//! connection round deleted it). Every media surface is built on 「the
//! picture at index N」, and this is how a movie answers it: through each
//! operating system's own codec stack, the encoder's mirror.
//!
//! 🚨★★★**THE LAW IS WRITTEN ONCE; THE PLATFORMS ONLY SAY HOW.** The C held
//! three whole decoders first, and the rules were spelled in each — measured
//! 2026-08-31: the index clamp, the capacity check, 「at least one frame」,
//! 「no declared rate means 24」 three times; 「already positioned」 twice
//! (Apple had none); the display turn and the rate as a FRACTION once each,
//! which is how upright phone video lay on its side on Windows and Android
//! and 29.97 became 30 on Android. A rule that exists in one backend is an
//! accident of who wrote it. Here each `os` opens a container, repositions,
//! and pulls one picture at its STORED size, and answers nothing else.
//!
//! MANY DOCUMENTS (2026-09-12): a movie decodes where it is shown, the
//! playback warmer fills ahead of the playhead and export walks a cut — with
//! one document those interleave by re-opening, ~111 ms apiece. So a
//! document is a handle into a few slots; each backend still holds exactly
//! one document per `Reader`.
//!
//! A READ THAT NEVER COMES BACK (2026-11-09): each document's reader lives
//! on a thread of its own, watched; one that stops answering is let go and
//! the frame asked of a reader opened afresh — `reading.rs` says why.
//!
//! Absence is an ANSWER, never a crash: a build whose `os` is `none.rs`
//! says so, and the app says 「no video decoder in this build」 instead of
//! failing as a corrupt file.

// A build without a reader (none.rs) makes nothing a backend answers and
// walks no movie, so most of the law goes uncalled there — and is still the
// law its tests run.
#![cfg_attr(not(any(windows, target_os = "android", target_vendor = "apple")), allow(dead_code))]

use std::borrow::Cow;
use std::ffi::{CStr, CString, c_char};
use std::sync::{Mutex, PoisonError};

use reading::{Reading, Wanted};

use crate::colour::{self, Colours};

mod reading;

#[cfg(target_os = "android")]
#[path = "android.rs"]
mod os;
#[cfg(target_vendor = "apple")]
#[path = "apple.rs"]
mod os;
#[cfg(not(any(windows, target_os = "android", target_vendor = "apple")))]
#[path = "none.rs"]
mod os;
#[cfg(windows)]
#[path = "windows.rs"]
mod os;

#[cfg(test)]
mod tests;

/// Why a backend could not: most are fixed sentences, and Apple's carry the
/// framework's own description or a pixel format's code.
type Why = Cow<'static, str>;

/// A movie's rate as its container says it.
enum Rate {
    /// An exact ratio — Media Foundation's.
    #[cfg_attr(not(windows), allow(dead_code))]
    Fraction(i32, i32),
    /// Frames a second, as a number — made exact by [`rate_to_fraction`]:
    /// MediaCodec's and AVFoundation's.
    #[cfg_attr(windows, allow(dead_code))]
    Nominal(f64),
}

/// What a document hands for a frame: straight RGBA — what every surface
/// shows — or the movie's own 4:2:0 as NV12, as the decoder made it, for a
/// piece written of it with no sum (`colour`: 유저 2026-11-14,
/// trimmed-movie-decodes-to-nv12-Q1). A document is opened for one; the
/// backend asks its decoder for that, and a reader opened afresh asks the
/// same ([`Doc::source`]).
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) enum Pixels {
    Rgba,
    Nv12,
}

impl Pixels {
    /// The bytes of one `width`×`height` frame.
    fn bytes(self, (width, height): (usize, usize)) -> usize {
        match self {
            Pixels::Rgba => width * height * 4,
            Pixels::Nv12 => colour::nv12_bytes(width, height),
        }
    }
}

/// What a backend learns opening a movie, for the law to read back.
struct Opened {
    stored_width: i32,
    stored_height: i32,
    /// What the movie says its pictures are — [`Colours::NONE`] where it
    /// says nothing.
    colours: Colours,
    /// The clockwise turn the container asks for, in degrees, as it says it.
    ///
    /// 🚨★★★**A PHONE HOLDS ITS SENSOR SIDEWAYS AND WRITES THE TURN DOWN.**
    /// Video shot upright is stored 1920x1080 with a 90° turn; a decoder that
    /// ignores it hands back a picture lying on its side.
    rotation: i32,
    rate: Rate,
    /// The picture's length: ticks, and ticks a second — never seconds
    /// ([`frame_count_for`] says why).
    length: (i64, i64),
}

/// How many movies may be open at once: the canvas shows one, the warmer
/// fills ahead on it, export walks a cut's rows, and the media viewer and
/// the placement window hold their own. A slot costs the backend's handle —
/// the PICTURES are the caller's, copied out on every read.
const DOCS: usize = 8;

/// What a backend says when its stream has no more pictures. ⚠️One
/// sentence for every backend that can tell: the reading thread asks a fresh
/// reader again when it is said of a frame the movie holds.
const PAST_THE_END: &str = "past the end of the stream";

/// What the law makes of a backend's [`Opened`].
#[derive(Clone, Copy, Debug, PartialEq)]
struct Shape {
    stored: (i32, i32),
    /// 0, 90, 180 or 270.
    rotation: i32,
    /// The size a caller sees — the picture the right way up.
    shown: (i32, i32),
    rate: (i32, i32),
    frame_count: i64,
    pixels: Pixels,
    colours: Colours,
}

/// What one movie is opened from, and for: to open it again when its reader
/// stops answering ([`reading`]).
struct Source {
    path: CString,
    span: Option<(i64, i64, bool)>,
    pixels: Pixels,
}

/// One open movie: the thread that reads it and what the law made of it.
struct Doc {
    source: Source,
    /// None once a reader opened afresh stopped answering too: 「could not
    /// be read」 from then on.
    reading: Option<Reading>,
    shape: Shape,
    /// The frame the reader is positioned to deliver next, when known.
    next: Option<i64>,
}

/// The backend's reader, as the reading thread asks it.
impl reading::Pull for os::Reader {
    fn reposition(&mut self, index: i64, rate: (i32, i32)) -> Result<(), Why> {
        os::Reader::reposition(self, index, rate)
    }

    fn read(&mut self, index: i64, rate: (i32, i32), rgba: &mut [u8], alive: &dyn Fn()) -> Result<(), Why> {
        os::Reader::read(self, index, rate, rgba, alive)
    }
}

/// 🚨**A LOCK A SLOT, not one for the decoder.** The C picked a global
/// 「selected slot」 and then called the hooks, so two threads on two
/// handles could cross documents; the app calls from two isolates at once —
/// the decode worker (`video_decode_worker.dart`: view, warm, export, import
/// preview) and a trimmed import's `writeMovieSpan` on a worker of its own.
/// A read holds only its own movie, so one movie's slow seek does not stall
/// another's play. What a caller sees is the C's.
static SLOTS: [Mutex<Option<Doc>>; DOCS] = [const { Mutex::new(None) }; DOCS];

/// Which slots are spoken for — an open still in progress included — so two
/// opens never pick the same one. Held only while choosing.
static TAKEN: Mutex<[bool; DOCS]> = Mutex::new([false; DOCS]);

/// The last failure, as the C kept it: one buffer for every document, 255
/// bytes and the terminator. ⚠️One, not one a thread — an isolate is not
/// tied to an OS thread, so a thread's own would answer a different call.
static ERROR: Mutex<[u8; 256]> = Mutex::new([0; 256]);

fn set_error(message: &str) {
    let mut error = ERROR.lock().unwrap_or_else(PoisonError::into_inner);
    let length = message.len().min(error.len() - 1);
    error[..length].copy_from_slice(&message.as_bytes()[..length]);
    error[length] = 0;
}

/// A rate as an exact fraction. 🚨**30000/1001 IS NOT 29.97** — rounding it
/// is how a frame index drifts a second out over a long take.
fn rate_to_fraction(rate: f64) -> (i32, i32) {
    // `!(rate > 0.0)` is NaN's answer too.
    if !(rate > 0.0) || rate > 1000.0 {
        // No usable rate: 24 is the honest guess for what this app takes in.
        return (24, 1);
    }
    let rounded = f64::from((rate + 0.5) as i32);
    if (rate - rounded).abs() < 0.001 {
        return (rounded as i32, 1);
    }
    // The NTSC family: every non-integer rate this app meets is n/1.001.
    ((rate * 1001.0 + 0.5) as i32, 1001)
}

/// How many frames `length` holds at `rate` — to the nearest frame, and at
/// least one, because a movie that opened has a picture in it.
///
/// 🚨**TICKS AND THEIR RATE, NOT SECONDS.** 1.001 s at 30000/1001 is exactly
/// thirty frames, and 29.999… in floating point. 🚨★★★**TO THE NEAREST, FOR
/// EVERY BACKEND**: Media Foundation rounds its times to 100 ns, so twelve
/// frames at 24 end at 4999999, and `tone_with_video.mp4`'s track says
/// 11999/24000 for twelve pictures — truncated, both are eleven (Windows had
/// this alone first, and the Apple build counted eleven the next day, 검증
/// 2026-10-23 · 24). ⚠️In 128 bits: a container may claim any length, and
/// an overflow here would abort the app across the FFI.
fn frame_count_for((ticks, per_second): (i64, i64), (num, den): (i32, i32)) -> i64 {
    if ticks <= 0 || per_second <= 0 || num <= 0 || den <= 0 {
        return 1;
    }
    let per_frame = i128::from(per_second) * i128::from(den);
    let count = (i128::from(ticks) * i128::from(num) + per_frame / 2) / per_frame;
    i64::try_from(count).unwrap_or(i64::MAX).max(1)
}

/// Frame `index`'s time in a backend's ticks.
///
/// 🚨**ONE FORMULA FOR EVERY BACKEND.** The C spelled it three times and two
/// ways: Android multiplied first (`index · tps · den / num`, exact), Windows
/// cut a frame's length to whole ticks and THEN multiplied, which at 29.97
/// drifts 0.67 × 100 ns a frame — half a frame by fourteen minutes. Exact,
/// here, for all of them.
fn ticks_at(index: i64, per_second: i64, (num, den): (i32, i32)) -> i64 {
    let ticks = i128::from(index) * i128::from(per_second) * i128::from(den) / i128::from(num.max(1));
    i64::try_from(ticks).unwrap_or(i64::MAX)
}

/// One frame's length in a backend's ticks, cut to whole ticks.
fn frame_ticks(per_second: i64, (num, den): (i32, i32)) -> i64 {
    per_second * i64::from(den) / i64::from(num.max(1))
}

/// Whether a sample at `stamp` has reached `target`, with **half a frame of
/// slack**: a stamp lands ON its frame, and exact equality misses on every
/// source whose rate is not an integer. Ticks of the backend's own.
fn sample_reaches(stamp: i64, target: i64, frame: i64) -> bool {
    stamp.saturating_add(frame / 2) >= target
}

/// A turn in degrees, folded into the four a container can mean. Negatives
/// are how Android spells counter-clockwise.
fn rotation_quarter(degrees: i32) -> i32 {
    (degrees / 90).rem_euclid(4) * 90
}

/// `stored` (`width` x `height` samples of `bytes` each, packed) into `out`
/// turned clockwise by `rotation`: an RGBA picture's pixels are 4 bytes, an
/// NV12 frame's luma 1 and its chroma pairs 2 — the same turn, so a piece
/// lies as its movie is shown. ⚠️`out` is the DISPLAY size; ⛔never in
/// place — a quarter turn changes the shape, and a half turn would
/// overwrite rows still to be read.
fn rotate(stored: &[u8], (width, height): (usize, usize), bytes: usize, rotation: i32, out: &mut [u8]) {
    for y in 0..height {
        for x in 0..width {
            let (dx, dy, row) = match rotation {
                // The stored picture's top-left becomes the top-RIGHT.
                90 => (height - 1 - y, x, height),
                180 => (width - 1 - x, height - 1 - y, width),
                270 => (y, width - 1 - x, height),
                _ => (x, y, width),
            };
            let from = (y * width + x) * bytes;
            let to = (dy * row + dx) * bytes;
            out[to..to + bytes].copy_from_slice(&stored[from..from + bytes]);
        }
    }
}

/// `stored`, a frame of `pixels` at `size`, turned by `rotation` into
/// `out`: RGBA as one picture, NV12 as its luma and its chroma pairs, each
/// plane at its own size ([`colour::nv12_of`] pads the frame even, so a
/// quarter turn lands on the even size of the shown picture).
fn turn(stored: &[u8], pixels: Pixels, size: (usize, usize), rotation: i32, out: &mut [u8]) {
    let Pixels::Nv12 = pixels else {
        return rotate(stored, size, 4, rotation, out);
    };
    let (width, height) = (size.0 + (size.0 & 1), size.1 + (size.1 & 1));
    let ((luma, chroma), (luma_out, chroma_out)) = (stored.split_at(width * height), out.split_at_mut(width * height));
    rotate(luma, (width, height), 1, rotation, luma_out);
    rotate(chroma, (width / 2, height / 2), 2, rotation, chroma_out);
}

/// What both opens make of a backend's answer — one copy, so 「a file」 and
/// 「a span of a file」 cannot drift apart on rotation, rate or length.
fn settle(opened: Opened, pixels: Pixels) -> Result<Shape, Why> {
    if opened.stored_width <= 0 || opened.stored_height <= 0 {
        return Err("the video stream has no frame size".into());
    }
    let stored = (opened.stored_width, opened.stored_height);
    let rotation = rotation_quarter(opened.rotation);
    let shown = if rotation == 90 || rotation == 270 { (stored.1, stored.0) } else { stored };
    let rate = match opened.rate {
        Rate::Fraction(num, den) if num > 0 && den > 0 => (num, den),
        Rate::Fraction(..) => (24, 1),
        Rate::Nominal(rate) => rate_to_fraction(rate),
    };
    // ⚠️Counted at the rate the law settled on, 24 included. The C's Windows
    // backend counted before the law's 24 and so said one frame for a movie
    // that declared no rate — while it then sought at 24; Android and Apple
    // made the 24 first. The law's order, for every backend.
    let frame_count = frame_count_for(opened.length, rate);
    Ok(Shape { stored, rotation, shown, rate, frame_count, pixels, colours: opened.colours })
}

/// The slot `handle` names, locked, while it holds a movie. Handles are
/// one-based so that 0 is 「no document」, the way every answer here spells
/// failure.
fn slot_of(handle: i32) -> Option<std::sync::MutexGuard<'static, Option<Doc>>> {
    let index = usize::try_from(handle).ok()?.checked_sub(1)?;
    let slot = SLOTS.get(index)?.lock().unwrap_or_else(PoisonError::into_inner);
    slot.is_some().then_some(slot)
}

/// The first slot holding nothing, spoken for — or none when all are.
fn take() -> Option<usize> {
    let mut taken = TAKEN.lock().unwrap_or_else(PoisonError::into_inner);
    let free = taken.iter().position(|held| !held)?;
    taken[free] = true;
    Some(free)
}

/// Slot `index` is no longer spoken for. ⚠️Only once it holds nothing: a
/// slot is emptied under its own lock first, so no open can take it while a
/// close is still letting go.
fn release(index: usize) {
    TAKEN.lock().unwrap_or_else(PoisonError::into_inner)[index] = false;
}

/// # Safety
/// `path` is null or a NUL-terminated string.
unsafe fn open(path: *const c_char, span: Option<(i64, i64, bool)>, pixels: Pixels) -> i32 {
    set_error("");
    // SAFETY: the caller's contract.
    let path = (!path.is_null()).then(|| unsafe { CStr::from_ptr(path) });
    let Some(path) = path.filter(|path| !path.is_empty()) else {
        set_error("no path");
        return 0;
    };
    if span.is_some_and(|(offset, length, _)| offset < 0 || length <= 0) {
        set_error("that span is not inside the file");
        return 0;
    }
    let Some(index) = take() else {
        set_error("too many movies are open at once");
        return 0;
    };
    let opened = os::Reader::open(path, span, pixels).and_then(|(reader, opened)| {
        let shape = settle(opened, pixels)?;
        let reading = Reading::spawn(reader, shape)?;
        let source = Source { path: path.to_owned(), span, pixels };
        Ok(Doc { source, reading: Some(reading), shape, next: None })
    });
    match opened {
        Ok(doc) => {
            *SLOTS[index].lock().unwrap_or_else(PoisonError::into_inner) = Some(doc);
            index as i32 + 1
        }
        Err(why) => {
            set_error(&why);
            release(index);
            0
        }
    }
}

/// Whether this build has a reader at all.
#[unsafe(no_mangle)]
pub extern "C" fn qa_video_decode_supported() -> i32 {
    i32::from(os::SUPPORTED)
}

/// The last failure, for the app to show verbatim.
///
/// ⚠️The C's answer, kept (`qa_video_decoder.dart` binds it): a pointer
/// into the one buffer, which the next failure anywhere rewrites.
#[unsafe(no_mangle)]
pub extern "C" fn qa_video_decode_last_error() -> *const c_char {
    ERROR.lock().unwrap_or_else(PoisonError::into_inner).as_ptr().cast()
}

/// Opens the movie at `path`: its handle, or 0 with the reason in
/// [`qa_video_decode_last_error`].
///
/// # Safety
/// `path` is null or a NUL-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_video_decode_open(path: *const c_char) -> i32 {
    // SAFETY: the caller's contract.
    unsafe { open(path, None, Pixels::Rgba) }
}

/// Opens the movie at `path` as [`qa_video_decode_open`] does, for its own
/// 4:2:0 as NV12 ([`Pixels::Nv12`]): [`qa_video_decode_frame`] then hands
/// each frame the right way up, padded even — the Y rows, then the CbCr
/// pairs side by side, every row the padded width apart — and
/// [`qa_video_decode_colours`] says what the movie calls them. A trimmed
/// piece is written of these with no sum (`colour`).
///
/// # Safety
/// `path` is null or a NUL-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_video_decode_open_nv12(path: *const c_char) -> i32 {
    // SAFETY: the caller's contract.
    unsafe { open(path, None, Pixels::Nv12) }
}

/// 🚨★★★**A MOVIE INSIDE THE PROJECT FILE IS A RANGE, NOT A PATH** — a
/// carried video's bytes live in the `.anicel`, and unpacking it to a temp
/// file would leave a COPY (유저 2026-08-27). `framed`: the span holds it
/// compressed in blocks, as a save keeps most movies; every backend reads
/// one through the library's one span reader.
///
/// # Safety
/// `path` is null or a NUL-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_video_decode_open_span(
    path: *const c_char,
    offset: i64,
    length: i64,
    framed: i32,
) -> i32 {
    // SAFETY: the caller's contract.
    unsafe { open(path, Some((offset, length, framed != 0)), Pixels::Rgba) }
}

/// The movie's shown size, frame count and rate, into whichever of the
/// out-parameters are not null.
///
/// # Safety
/// Each pointer is null or writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_video_decode_info(
    handle: i32,
    width: *mut i32,
    height: *mut i32,
    frame_count: *mut i64,
    fps_num: *mut i32,
    fps_den: *mut i32,
) -> i32 {
    let Some(slot) = slot_of(handle) else {
        set_error("no document is open");
        return 0;
    };
    let Some(doc) = slot.as_ref() else { return 0 };
    // SAFETY: the caller's contract, each pointer on its own.
    unsafe {
        put(width, doc.shape.shown.0);
        put(height, doc.shape.shown.1);
        put(frame_count, doc.shape.frame_count);
        put(fps_num, doc.shape.rate.0);
        put(fps_den, doc.shape.rate.1);
    }
    1
}

/// What the movie says its pictures are ([`Colours`]): its primaries,
/// transfer, matrix and range into `out`, in that order, as H.273 code
/// points — 2 for each it does not name.
///
/// # Safety
/// `out` is null or holds four.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_video_decode_colours(handle: i32, out: *mut i32) -> i32 {
    let Some(slot) = slot_of(handle) else {
        set_error("no document is open");
        return 0;
    };
    let Some(doc) = slot.as_ref().filter(|_| !out.is_null()) else { return 0 };
    let Colours { primaries, transfer, matrix, range } = doc.shape.colours;
    for (at, code) in [primaries, transfer, matrix, range].into_iter().enumerate() {
        // SAFETY: the caller's contract; `at` < 4.
        unsafe { out.add(at).write(i32::from(code)) };
    }
    1
}

/// # Safety
/// `into` is null or writable.
unsafe fn put<T>(into: *mut T, value: T) {
    if !into.is_null() {
        // SAFETY: the caller's contract.
        unsafe { into.write(value) };
    }
}

/// Frame `index` at the shown size, into `pixels`: straight RGBA, or the
/// NV12 a document opened for it hands ([`qa_video_decode_open_nv12`]).
///
/// # Safety
/// `pixels` is null or holds `capacity` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_video_decode_frame(handle: i32, index: i64, pixels: *mut u8, capacity: i32) -> i32 {
    let Some(mut slot) = slot_of(handle) else {
        set_error("no document is open");
        return 0;
    };
    let Some(doc) = slot.as_mut() else { return 0 };
    let (width, height) = doc.shape.shown;
    let needed = doc.shape.pixels.bytes((width as usize, height as usize));
    if pixels.is_null() || usize::try_from(capacity).map_or(true, |capacity| capacity < needed) {
        set_error("frame buffer too small");
        return 0;
    }
    // SAFETY: the caller's contract; `needed` ≤ `capacity`.
    let out = unsafe { std::slice::from_raw_parts_mut(pixels, needed) };
    match frame(doc, index.max(0), out) {
        Ok(()) => 1,
        Err(why) => {
            set_error(&why);
            0
        }
    }
}

fn frame(doc: &mut Doc, index: i64, out: &mut [u8]) -> Result<(), Why> {
    // 🚨★★★**PLAYING FORWARD DOES NOT SEEK.** A reposition lands on the
    // keyframe at or before the target and the read walks forward; doing it
    // for every frame made play quadratic in the GOP — 유저 2026-08-31's
    // white flicker on a first play, and a picture that never left frame 0.
    let positioned = doc.next == Some(index);
    // ⛔Forgotten BEFORE the read, not after a success: a failed read leaves
    // the reader somewhere this cannot name, and a stale 「next」 would skip
    // the reposition that recovers it.
    doc.next = None;
    let wanted = Wanted { index, reposition: !positioned, inside: index < doc.shape.frame_count };
    let (source, shape) = (&doc.source, doc.shape);
    reading::read(&mut doc.reading, &wanted, out, reading::STALL, || {
        let (reader, _) = os::Reader::open(&source.path, source.span, source.pixels)?;
        Reading::spawn(reader, shape)
    })?;
    // Positioned on the frame AFTER this one: asking for it next needs no
    // reposition at all.
    doc.next = Some(index + 1);
    Ok(())
}

/// One frame the right way up into `out`, which `read` fills at the
/// STORED size, in the document's [`Pixels`]: straight into `out` with no
/// turn, into `scratch` and then turned with one.
///
/// ⛔The turn is applied HERE, once, for every backend — not by whichever
/// backend's author happened to know about it (until 2026-08-31 Apple's
/// alone did, and upright phone video lay on its side elsewhere).
fn upright(
    shape: &Shape,
    scratch: &mut Vec<u8>,
    out: &mut [u8],
    read: impl FnOnce(&mut [u8]) -> Result<(), Why>,
) -> Result<(), Why> {
    if shape.rotation == 0 {
        return read(out);
    }
    let stored = (shape.stored.0 as usize, shape.stored.1 as usize);
    let needed = shape.pixels.bytes(stored);
    if scratch.len() < needed {
        scratch.try_reserve_exact(needed - scratch.len()).map_err(|_| "out of memory turning the frame upright")?;
        scratch.resize(needed, 0);
    }
    read(&mut scratch[..needed])?;
    turn(scratch, shape.pixels, stored, shape.rotation, out);
    Ok(())
}

/// Closes `handle`'s movie; a handle holding nothing is left alone — an
/// open still in progress on that slot included.
#[unsafe(no_mangle)]
pub extern "C" fn qa_video_decode_close(handle: i32) {
    let Some(mut slot) = slot_of(handle) else { return };
    // The reader closes as it drops — on its reading thread, which is joined
    // under the slot's lock, so a read on it finishes first, the file is let
    // go before this returns, and no other close lets go of what replaces it.
    slot.take();
    drop(slot);
    release(handle as usize - 1);
}

/// Every movie at once — what a teardown wants, and the only close a caller
/// holding no handle can make.
#[unsafe(no_mangle)]
pub extern "C" fn qa_video_decode_close_all() {
    for handle in 1..=DOCS as i32 {
        qa_video_decode_close(handle);
    }
}
