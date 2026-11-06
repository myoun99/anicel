//! The Rust writer against the engine's C (native/oracle): both asked
//! through their exports, one export at a time — each keeps one writer for
//! the whole process, so two tests at once would be one job.

use std::ffi::{CString, c_char};
use std::path::PathBuf;
use std::sync::{Mutex, MutexGuard};

type Open = unsafe extern "C" fn(*const c_char, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32) -> i32;

#[derive(Clone, Copy)]
struct Encoder {
    error: unsafe extern "C" fn(*mut c_char, i32) -> i32,
    supported: unsafe extern "C" fn() -> i32,
    probe: unsafe extern "C" fn(i32, i32) -> i32,
    open: Open,
    write_frame: unsafe extern "C" fn(*const u8) -> i32,
    write_audio: unsafe extern "C" fn(*const i16, i32) -> i32,
    finish: unsafe extern "C" fn() -> i32,
    abort: unsafe extern "C" fn(),
}

fn c() -> Encoder {
    // SAFETY: qa_video_encode.c's declarations.
    unsafe {
        Encoder {
            error: oracle::export("qa_video_export_error"),
            supported: oracle::export("qa_video_export_supported"),
            probe: oracle::export("qa_video_export_probe"),
            open: oracle::export("qa_video_export_open"),
            write_frame: oracle::export("qa_video_export_write_frame"),
            write_audio: oracle::export("qa_video_export_write_audio"),
            finish: oracle::export("qa_video_export_finish"),
            abort: oracle::export("qa_video_export_abort"),
        }
    }
}

fn rust() -> Encoder {
    use super::*;
    Encoder {
        error: qa_video_export_error,
        supported: qa_video_export_supported,
        probe: qa_video_export_probe,
        open: qa_video_export_open,
        write_frame: qa_video_export_write_frame,
        write_audio: qa_video_export_write_audio,
        finish: qa_video_export_finish,
        abort: qa_video_export_abort,
    }
}

static ONE_AT_A_TIME: Mutex<()> = Mutex::new(());

fn one_at_a_time() -> MutexGuard<'static, ()> {
    ONE_AT_A_TIME.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// What an open asks for, as Dart passes it.
#[derive(Clone, Copy, Debug)]
struct Shape {
    width: i32,
    height: i32,
    fps: (i32, i32),
    sample_rate: i32,
    channels: i32,
    container: i32,
    codec: i32,
    bitrate_bps: i32,
}

/// The engine fixtures' movie: 64×48 at 24, stereo 48 kHz, MP4 H.264.
const MOVIE: Shape =
    Shape { width: 64, height: 48, fps: (24, 1), sample_rate: 48000, channels: 2, container: 0, codec: 0, bitrate_bps: 0 };

impl Encoder {
    fn error(&self, capacity: i32) -> (i32, String) {
        let mut out = [0u8; 256];
        // SAFETY: the buffer holds at least `capacity` bytes.
        let length = unsafe { (self.error)(out.as_mut_ptr().cast(), capacity) };
        (length, String::from_utf8_lossy(&out[..length.max(0) as usize]).into_owned())
    }

    fn last_error(&self) -> String {
        self.error(256).1
    }

    fn open(&self, path: Option<&str>, shape: Shape) -> i32 {
        let path = path.map(|path| CString::new(path).unwrap());
        let s = shape;
        // SAFETY: the path is null or NUL-terminated.
        unsafe {
            (self.open)(
                path.as_ref().map_or(std::ptr::null(), |path| path.as_ptr()),
                s.width,
                s.height,
                s.fps.0,
                s.fps.1,
                s.sample_rate,
                s.channels,
                s.container,
                s.codec,
                0,
                s.bitrate_bps,
            )
        }
    }

    /// The movie `shape` makes of `frames` moving frames (and their sound),
    /// read back whole; panics where a step is refused.
    fn movie(&self, file: &PathBuf, shape: Shape, frames: i32) -> Vec<u8> {
        assert_eq!(self.open(Some(file.to_str().unwrap()), shape), 1, "open {shape:?}: {}", self.last_error());
        let per_frame = if shape.channels > 0 { shape.sample_rate * shape.fps.1 / shape.fps.0 } else { 0 };
        for frame in 0..frames {
            let rgba = moving(shape.width as usize, shape.height as usize, frame as usize);
            // SAFETY: a whole frame of the opened size.
            assert_eq!(unsafe { (self.write_frame)(rgba.as_ptr()) }, 1, "frame {frame}: {}", self.last_error());
            if per_frame > 0 {
                let pcm = saw(per_frame as usize, shape.channels as usize, frame as usize);
                // SAFETY: `per_frame` frames of the opened channels.
                let wrote = unsafe { (self.write_audio)(pcm.as_ptr(), per_frame) };
                assert_eq!(wrote, 1, "sound {frame}: {}", self.last_error());
            }
        }
        // SAFETY: an open writer.
        assert_eq!(unsafe { (self.finish)() }, 1, "finish {shape:?}: {}", self.last_error());
        let bytes = std::fs::read(file).unwrap();
        std::fs::remove_file(file).unwrap();
        bytes
    }
}

/// A frame whose colour moves with `frame`, so the encode has real motion.
fn moving(width: usize, height: usize, frame: usize) -> Vec<u8> {
    let mut rgba = vec![0u8; width * height * 4];
    for (index, pixel) in rgba.chunks_exact_mut(4).enumerate() {
        pixel.copy_from_slice(&[((index + frame * 8) % 256) as u8, (index * 2 % 256) as u8, 255 - (frame * 8 % 256) as u8, 255]);
    }
    rgba
}

/// A saw, opposite in each channel of a pair.
fn saw(frames: usize, channels: usize, frame: usize) -> Vec<i16> {
    (0..frames * channels)
        .map(|i| {
            let value = (8000 * ((i / channels + frame) % 100) / 100) as i16;
            if i % 2 == 0 { value } else { -value }
        })
        .collect()
}

fn temp(name: &str) -> PathBuf {
    std::env::temp_dir().join(format!("video-export-{}-{name}.mp4", std::process::id()))
}

/// `movie` with the clock taken out: the creation and modification times
/// the muxer stamps into each `mvhd`, `tkhd` and `mdhd` — the seconds the
/// file was finished in, which two writers a second apart never share. How
/// many it found comes back too, so a mask that found none says so.
fn without_the_clock(mut movie: Vec<u8>) -> (Vec<u8>, usize) {
    let mut stamped = 0;
    let mut boxes = vec![(0, movie.len())];
    while let Some((mut at, end)) = boxes.pop() {
        while at + 8 <= end {
            let size = u32::from_be_bytes(movie[at..at + 4].try_into().unwrap()) as usize;
            if size < 8 || at + size > end {
                break;
            }
            match &movie[at + 4..at + 8] {
                b"moov" | b"trak" | b"mdia" => boxes.push((at + 8, at + size)),
                b"mvhd" | b"tkhd" | b"mdhd" => {
                    // Version 0 keeps the two times in 32 bits, 1 in 64.
                    let times = if movie[at + 8] == 1 { 16 } else { 8 };
                    movie[at + 12..at + 12 + times].fill(0);
                    stamped += 1;
                }
                _ => {}
            }
            at += size;
        }
    }
    (movie, stamped)
}

/// The C's movie and the Rust's of `shape`, the same but for the clock.
fn same_movie(name: &str, shape: Shape, frames: i32) {
    let (c, rust) = (c(), rust());
    let (theirs, stamped) = without_the_clock(c.movie(&temp(&format!("{name}-c")), shape, frames));
    let (ours, _) = without_the_clock(rust.movie(&temp(&format!("{name}-rust")), shape, frames));
    let tracks = if shape.channels > 0 { 2 } else { 1 };
    assert_eq!(stamped, 1 + 2 * tracks, "{name}: the clock is where the mask looks");
    let first = theirs.iter().zip(&ours).position(|(a, b)| a != b);
    assert!(
        ours.len() == theirs.len() && first.is_none(),
        "{name}: {} bytes against the C's {}, first apart at {first:?}",
        ours.len(),
        theirs.len()
    );
}

// The fixtures' movie, which the hardware law keeps in software; an odd,
// silent one the pad makes even; a film the hardware takes; the law's first
// side past the failed one — and the side that failed, held off hardware
// (on the Intel machine the law was measured on, asking there fails at
// Finalize); an exact NTSC fraction with mono sound at another rate and a
// bitrate named; a Korean name. Each byte for byte with the C's.
#[test]
fn the_movie_is_the_c_s_but_for_its_clock() {
    let _one = one_at_a_time();
    // SAFETY: no arguments.
    if unsafe { (c().supported)() } == 0 {
        return;
    }
    same_movie("fixture", MOVIE, 24);
    same_movie("odd-silent", Shape { width: 63, height: 47, channels: 0, ..MOVIE }, 6);
    same_movie("full-hd", Shape { width: 1920, height: 1080, ..MOVIE }, 6);
    same_movie("past-the-law", Shape { width: 49, height: 64, channels: 0, ..MOVIE }, 6);
    same_movie("the-failed-side", Shape { width: 48, height: 64, channels: 0, ..MOVIE }, 6);
    let ntsc = Shape { width: 96, height: 64, fps: (24000, 1001), sample_rate: 44100, channels: 1, bitrate_bps: 3_000_000, ..MOVIE };
    same_movie("ntsc-mono", ntsc, 12);
    same_movie("영상", MOVIE, 3);
    // SAFETY: no arguments.
    if unsafe { (c().probe)(0, 1) } == 1 {
        same_movie("hevc", Shape { width: 1280, height: 720, channels: 0, codec: 1, ..MOVIE }, 6);
    }
}

#[test]
fn what_this_machine_can_write_is_the_c_s_answer() {
    let _one = one_at_a_time();
    let (c, rust) = (c(), rust());
    // SAFETY: no arguments.
    assert_eq!(unsafe { (rust.supported)() }, unsafe { (c.supported)() });
    for container in -1..=2 {
        for codec in -1..=7 {
            // SAFETY: plain numbers.
            let (ours, theirs) = unsafe { ((rust.probe)(container, codec), (c.probe)(container, codec)) };
            assert_eq!(ours, theirs, "container {container}, codec {codec}");
        }
    }
}

/// `step` asked of both, with what each said after it: the answer and the
/// last error.
fn both_say(what: &str, step: impl Fn(&Encoder) -> i32) {
    let (c, rust) = (c(), rust());
    let theirs = (step(&c), c.last_error());
    let ours = (step(&rust), rust.last_error());
    assert_eq!(ours, theirs, "{what}");
}

// Every open the C turns away, turned away with the C's words: bad numbers,
// pairs this platform does not write, a path that does not convert or that
// leads nowhere, and a second job while one runs.
#[test]
fn an_open_is_refused_as_the_c_refuses_it() {
    let _one = one_at_a_time();
    let file = temp("refused");
    let path = file.to_str().unwrap();
    for (what, shape) in [
        ("no width", Shape { width: 0, ..MOVIE }),
        ("no height", Shape { height: 0, ..MOVIE }),
        ("a negative width", Shape { width: -1, ..MOVIE }),
        ("no frame rate", Shape { fps: (0, 1), ..MOVIE }),
        ("a rate over nothing", Shape { fps: (24, 0), ..MOVIE }),
        ("negative channels", Shape { channels: -1, ..MOVIE }),
        ("sound at no rate", Shape { sample_rate: 0, ..MOVIE }),
        ("a MOV", Shape { container: 1, ..MOVIE }),
        ("no such container", Shape { container: 2, ..MOVIE }),
        ("ProRes in an MP4", Shape { codec: 2, ..MOVIE }),
        ("ProRes 4444", Shape { codec: 6, ..MOVIE }),
        ("no such codec", Shape { codec: 7, ..MOVIE }),
    ] {
        both_say(what, |encoder| encoder.open(Some(path), shape));
    }
    both_say("no path", |encoder| encoder.open(None, MOVIE));
    let long = std::env::temp_dir().join("a".repeat(1100)).to_str().unwrap().to_owned();
    both_say("a path too long to convert", |encoder| encoder.open(Some(&long), MOVIE));
    let nowhere = std::env::temp_dir().join("no-such-folder-here").join("x.mp4").to_str().unwrap().to_owned();
    both_say("a path into no folder", |encoder| encoder.open(Some(&nowhere), MOVIE));
    both_say("a second job while one runs", |encoder| {
        if encoder.open(Some(path), MOVIE) == 0 {
            return -1;
        }
        let second = encoder.open(Some(path), MOVIE);
        // SAFETY: an open writer, let go of.
        unsafe { (encoder.abort)() };
        second
    });
    std::fs::remove_file(&file).ok();
}

// Nothing open: nothing written, nothing finished, an abort that does
// nothing — and an open job takes no null frame, no sound when silent, and
// opens again after an abort.
#[test]
fn a_call_out_of_turn_is_answered_as_the_c_answers_it() {
    let _one = one_at_a_time();
    let file = temp("out-of-turn");
    let path = file.to_str().unwrap();
    let frame = moving(64, 48, 0);
    let pcm = saw(10, 2, 0);
    // SAFETY: each pointer is null or holds what the call reads.
    both_say("nothing open", |encoder| unsafe {
        (encoder.abort)();
        (encoder.write_frame)(frame.as_ptr()) * 100 + (encoder.write_audio)(pcm.as_ptr(), 10) * 10 + (encoder.finish)()
    });
    both_say("an open job", |encoder| unsafe {
        if encoder.open(Some(path), Shape { channels: 0, ..MOVIE }) == 0 {
            return -1;
        }
        let answers = (encoder.write_frame)(std::ptr::null()) * 1000
            + (encoder.write_audio)(pcm.as_ptr(), 10) * 100
            + (encoder.write_frame)(frame.as_ptr()) * 10;
        (encoder.abort)();
        let again = encoder.open(Some(path), MOVIE);
        (encoder.abort)();
        answers + again
    });
    std::fs::remove_file(&file).ok();
}

// The message is handed out as the C hands it: cut to the room given, -1
// where there is none.
#[test]
fn the_last_error_is_handed_out_as_the_c_hands_it() {
    let _one = one_at_a_time();
    let (c, rust) = (c(), rust());
    for encoder in [c, rust] {
        encoder.open(None, MOVIE);
    }
    for capacity in [-1, 0, 1, 2, 5, 256] {
        assert_eq!(rust.error(capacity), c.error(capacity), "room for {capacity}");
    }
    // SAFETY: null is nowhere to put it.
    let nowhere = unsafe { ((rust.error)(std::ptr::null_mut(), 64), (c.error)(std::ptr::null_mut(), 64)) };
    assert_eq!(nowhere, (-1, -1));
}
