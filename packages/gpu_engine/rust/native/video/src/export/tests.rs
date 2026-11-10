//! The writer through its exports, one export at a time — it keeps one
//! writer for the whole process, so two tests at once would be one job.
//!
//! ↩️It was held to the engine's C (native/oracle) — byte for byte where the
//! C wrote a movie the same twice — until the connection round deleted the
//! C's writer (connection-round-checklist H, 2026-11-08). What stays is what
//! this code decides (유저 connection-round-checklist-Q14, 2026-11-07: what
//! the OS encoder makes is not frozen): the one law, the pairs and the
//! bitrate, how the last error is handed out, the platform's own words where
//! [`HELD`], and a movie's streams — each movie the export writes read back
//! as it was asked in `tests/decode.rs`.

use std::ffi::CString;
use std::path::PathBuf;
use std::sync::{Mutex, MutexGuard};

use media::iso_box::{self, Atom};

use super::{
    qa_video_export_abort, qa_video_export_error, qa_video_export_finish, qa_video_export_open, qa_video_export_probe,
    qa_video_export_supported, qa_video_export_write_audio, qa_video_export_write_frame,
};

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
    alpha: i32,
    bitrate_bps: i32,
}

/// The engine fixtures' movie: 64×48 at 24, stereo 48 kHz, MP4 H.264.
const MOVIE: Shape = Shape {
    width: 64,
    height: 48,
    fps: (24, 1),
    sample_rate: 48000,
    channels: 2,
    container: 0,
    codec: 0,
    alpha: 0,
    bitrate_bps: 0,
};

/// The last error handed out into `capacity` bytes: what the export
/// answers, and the words it put there.
fn error(capacity: i32) -> (i32, String) {
    let mut out = [0u8; 256];
    // SAFETY: the buffer holds at least `capacity` bytes.
    let length = unsafe { qa_video_export_error(out.as_mut_ptr().cast(), capacity) };
    (length, String::from_utf8_lossy(&out[..length.max(0) as usize]).into_owned())
}

fn last_error() -> String {
    error(256).1
}

fn open(path: Option<&str>, shape: Shape) -> i32 {
    let path = path.map(|path| CString::new(path).unwrap());
    let s = shape;
    // SAFETY: the path is null or NUL-terminated.
    unsafe {
        qa_video_export_open(
            path.as_ref().map_or(std::ptr::null(), |path| path.as_ptr()),
            s.width,
            s.height,
            s.fps.0,
            s.fps.1,
            s.sample_rate,
            s.channels,
            s.container,
            s.codec,
            s.alpha,
            s.bitrate_bps,
        )
    }
}

/// What an open of `shape` at `path` answers, the job let go of again
/// if it was taken — a pair one platform turns away, another writes.
fn tried(path: Option<&str>, shape: Shape) -> i32 {
    let opened = open(path, shape);
    if opened == 1 {
        qa_video_export_abort();
    }
    opened
}

/// The movie `shape` makes of `frames` moving frames (and their sound),
/// read back whole; panics where a step is refused.
fn movie(file: &PathBuf, shape: Shape, frames: i32) -> Vec<u8> {
    assert_eq!(open(Some(file.to_str().unwrap()), shape), 1, "open {shape:?}: {}", last_error());
    let per_frame = if shape.channels > 0 { shape.sample_rate * shape.fps.1 / shape.fps.0 } else { 0 };
    for frame in 0..frames {
        let rgba = moving(shape.width as usize, shape.height as usize, frame as usize);
        // SAFETY: a whole frame of the opened size.
        assert_eq!(unsafe { qa_video_export_write_frame(rgba.as_ptr()) }, 1, "frame {frame}: {}", last_error());
        if per_frame > 0 {
            let pcm = saw(per_frame as usize, shape.channels as usize, frame as usize);
            // SAFETY: `per_frame` frames of the opened channels.
            let wrote = unsafe { qa_video_export_write_audio(pcm.as_ptr(), per_frame) };
            assert_eq!(wrote, 1, "sound {frame}: {}", last_error());
        }
    }
    assert_eq!(qa_video_export_finish(), 1, "finish {shape:?}: {}", last_error());
    let bytes = std::fs::read(file).unwrap();
    std::fs::remove_file(file).unwrap();
    bytes
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

/// A file for `name` named as `container` names its files.
fn temp(name: &str, container: i32) -> PathBuf {
    let extension = if container == 1 { "mov" } else { "mp4" };
    std::env::temp_dir().join(format!("video-export-{}-{name}.{extension}", std::process::id()))
}

fn be32(movie: &[u8], at: usize) -> usize {
    u32::from_be_bytes(movie[at..at + 4].try_into().unwrap()) as usize
}

/// Bytes in hex, a space apart.
fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect::<Vec<_>>().join(" ")
}

/// The boxes directly in `movie[start..end]`, each head read where every
/// walker of this engine reads one (`media::iso_box`). A box that does not
/// fit says where it is and what its head holds.
///
/// ↩️2026-11-07: it read the 32 bits alone, and a MOV the Mac wrote stopped
/// the whole comparison at its first box past `ftyp` — 「a box at 28 runs
/// past its parent」 (bundle GPU CI 42353590096), with no movie named and
/// none of the rest asked.
/// ↩️2026-11-10: it read the head for itself, as the sound decoder did; the
/// export's edit list was the third to walk a movie (`edit_list`), and the
/// three read one.
fn children(movie: &[u8], start: usize, end: usize) -> Result<Vec<Atom>, String> {
    let mut atoms = Vec::new();
    let mut at = start;
    while at + 8 <= end {
        let Some(atom) = iso_box::atom(movie, at, end) else {
            return Err(format!("the box at {at} does not fit what holds it (to {end}), its head {}", hex(&movie[at..end.min(at + 16)])));
        };
        at = atom.end;
        atoms.push(atom);
    }
    Ok(atoms)
}

/// The box `path` leads to under `movie[start..end]`, if there is one.
fn find(movie: &[u8], start: usize, end: usize, path: &[&[u8; 4]]) -> Result<Option<Atom>, String> {
    let Some((first, rest)) = path.split_first() else {
        return Ok(None);
    };
    let Some(atom) = children(movie, start, end)?.into_iter().find(|atom| atom.kind == **first) else {
        return Ok(None);
    };
    if rest.is_empty() { Ok(Some(atom)) } else { find(movie, atom.body, atom.end, rest) }
}

/// A track as its writer laid it: the four letters its sample entry names
/// (`avc1`, `mp4a`, `apcn` …), how many samples it has, and what its edit
/// list holds — its version and flags, its count and its edits — if it has
/// one.
///
/// ↩️A track carried its samples too, laid along its chunks with
/// VideoToolbox's notes taken out, and a movie each of its boxes with the
/// clock taken out, for the comparison with the C's movies, which went with
/// the C (connection-round-checklist H, 2026-11-08): what the OS encoder and
/// muxer lay is not held (유저 connection-round-checklist-Q14).
struct Track {
    format: String,
    count: usize,
    list: Option<Vec<u8>>,
}

fn track(movie: &[u8], trak: Atom) -> Result<Track, String> {
    let table = find(movie, trak.body, trak.end, &[b"mdia", b"minf", b"stbl"])?.ok_or("a track with no sample table")?;
    // The first entry, past the version, the flags and the count of entries.
    let stsd = find(movie, table.body, table.end, &[b"stsd"])?.ok_or("a sample table with no stsd")?;
    let entry = *children(movie, stsd.body + 8, stsd.end)?.first().ok_or("a sample table with no entry")?;
    // The count, past the version, the flags and the one size for all.
    let stsz = find(movie, table.body, table.end, &[b"stsz"])?.ok_or("a sample table with no stsz")?;
    let list = find(movie, trak.body, trak.end, &[b"edts", b"elst"])?.map(|list| movie[list.body..list.end].to_vec());
    Ok(Track { format: String::from_utf8_lossy(&entry.kind).into_owned(), count: be32(movie, stsz.body + 8), list })
}

/// The tracks a movie's `moov` holds, in its order.
fn tracks(movie: &[u8]) -> Result<Vec<Track>, String> {
    let moov = find(movie, 0, movie.len(), &[b"moov"])?.ok_or("a movie with no moov")?;
    children(movie, moov.body, moov.end)?.into_iter().filter(|atom| &atom.kind == b"trak").map(|trak| track(movie, trak)).collect()
}

// A box that does not fit — longer than what holds it, shorter than its own
// header — says where it is and what its head holds.
// ↩️It walked a box of each size by hand too, since no movie this machine
// writes has one sized in 64 bits or one that runs to the end: that half
// went with the head to native/media (`iso_box`, 2026-11-10).
#[test]
fn a_box_that_does_not_fit_says_where_it_is_and_what_its_head_holds() {
    for (size, why) in [
        (40, "the box at 0 does not fit what holds it (to 12), its head 00 00 00 28 6d 6f 6f 76 00 00 00 00"),
        (5, "the box at 0 does not fit what holds it (to 12), its head 00 00 00 05 6d 6f 6f 76 00 00 00 00"),
    ] {
        let unfit = [0, 0, 0, size, b'm', b'o', b'o', b'v', 0, 0, 0, 0];
        assert_eq!(children(&unfit, 0, unfit.len()).err().as_deref(), Some(why), "size {size}");
    }
}

// What the writer lays in a movie, held where its bytes are not: a track
// for the pictures, coded as asked — by either name ISO 14496-15 gives the
// codec's entry — with a sample for every frame written, and one track more
// for the sound when there is sound. Each pair of the lineup's MP4 this
// build writes: HEVC chief among them, which not every machine that writes
// it reads back (`tests/decode.rs`). ⚠️The Mac's encoder writes a note of
// its own into the first unit of its H.264 and HEVC streams — an SEI of
// user data under UUID 47564adc-5c4c-433f-94ef-c5113cd143a8, holding a
// count the machine keeps across processes (bundle GPU CI 42366555125,
// 2026-11-07) — which parts any two of its movies byte for byte; inside a
// sample, it leaves how many there are alone.
//
// And on Windows, where this code writes it into the movie the sink
// finished (`edit_list`; 유저 2026-11-10, board
// an-mp4-reopened-loses-its-first-9-ms-of-sound-Q2): the sound's edit list —
// 1,024 in, for as long as the sound that was written, the movie's scale
// being the sound's rate — and none on the pictures. What another
// platform's muxer lays there is its own.
#[test]
fn a_movie_holds_its_streams_and_a_sample_for_every_frame() {
    let _one = one_at_a_time();
    for (name, shape, frames) in [
        ("h264", MOVIE, 24),
        ("h264-silent", Shape { channels: 0, ..MOVIE }, 6),
        ("hevc", Shape { width: 1280, height: 720, codec: 1, ..MOVIE }, 6),
    ] {
        if qa_video_export_probe(shape.container, shape.codec) == 0 {
            continue;
        }
        let file = temp(&format!("streams-{name}"), shape.container);
        let laid = tracks(&movie(&file, shape, frames)).unwrap_or_else(|why| panic!("{name}: it reads — {why}"));
        let entries: &[&str] = if shape.codec == 1 { &["hvc1", "hev1"] } else { &["avc1", "avc3"] };
        let formats: Vec<&str> = laid.iter().map(|track| track.format.as_str()).collect();
        let pictures: Vec<&Track> = laid.iter().filter(|track| entries.contains(&track.format.as_str())).collect();
        let sounds = formats.iter().filter(|format| **format == "mp4a").count();
        let sounding = usize::from(shape.channels > 0);
        assert_eq!((pictures.len(), sounds, formats.len()), (1, sounding, 1 + sounding), "{name}: its tracks, {formats:?}");
        assert_eq!(pictures[0].count, frames as usize, "{name}: a sample for every frame");
        if cfg!(windows) {
            let written = (frames * shape.sample_rate * shape.fps.1 / shape.fps.0) as u32;
            let mut list = vec![0, 0, 0, 0, 0, 0, 0, 1];
            list.extend_from_slice(&written.to_be_bytes());
            list.extend_from_slice(&[0, 0, 4, 0, 0, 1, 0, 0]);
            let sound = laid.iter().find(|track| track.format == "mp4a").and_then(|track| track.list.clone());
            assert_eq!(sound, (sounding == 1).then_some(list), "{name}: its sound starts 1,024 in and plays what was written");
            assert_eq!(pictures[0].list, None, "{name}: the pictures have no list");
        }
    }
}

// The bitrate by hand: an encoder spends what a small frame needs whatever
// it is offered, so the movies above cannot see the ceiling move.
#[test]
fn a_bitrate_stays_between_its_floor_and_ceiling() {
    use super::bitrate;
    for (what, (named, width, height, fps_num, fps_den), want) in [
        ("named past the ceiling", (80_000_000, 64, 64, 24, 1), 50_000_000),
        ("named under the floor", (1_000_000, 64, 64, 24, 1), 2_000_000),
        ("named in between", (3_000_000, 64, 64, 24, 1), 3_000_000),
        ("0.12 bits a pixel a frame", (0, 1000, 1000, 25, 1), 3_000_000),
        ("a small frame at the floor", (0, 64, 48, 24, 1), 2_000_000),
        ("4K at 60 at the ceiling", (0, 3840, 2160, 60, 1), 50_000_000),
    ] {
        assert_eq!(bitrate(named, width, height, fps_num, fps_den), want, "{what}");
    }
}

// What this machine writes, pair by pair: a container outside the lineup
// nowhere, held to the law (`in_the_lineup`) — the C's Apple writer took
// H.264 in any container (관제's judgment, connection-round-checklist 11-07
// 18:15). Within it, where [`HELD`], the platform's writer's own answer:
// Windows writes the MP4's H.264 — Microsoft's encoder ships with it — and
// H.265 where the machine has an encoder, which is the machine's and not
// held (this one has; the ARM runner, unmeasured); the Linux stub writes
// nothing. On Apple, the pairs its source takes ([`APPLE_WRITES`]).
//
// ↩️It was 「what_this_machine_can_write_is_the_c_s_answer」 until the
// connection round deleted the C (H, 2026-11-08): within the lineup each
// pair was the C's answer, Apple's among them.
#[test]
fn what_this_machine_can_write_is_its_own_answer() {
    let _one = one_at_a_time();
    let writes = cfg!(any(windows, target_os = "android", target_vendor = "apple"));
    assert_eq!(qa_video_export_supported(), i32::from(writes), "the builds that write movies");
    for container in -1..=2 {
        for codec in -1..=7 {
            let answer = qa_video_export_probe(container, codec);
            let pair = format!("container {container}, codec {codec}");
            if container != 0 && container != 1 {
                assert_eq!(answer, 0, "{pair}: outside the lineup");
            }
            if HELD && !(cfg!(windows) && (container, codec) == (0, 1)) {
                let own = i32::from(cfg!(windows) && (container, codec) == (0, 0));
                assert_eq!(answer, own, "{pair}: this platform's own answer");
            }
            if cfg!(target_vendor = "apple") {
                assert_eq!(answer, i32::from(APPLE_WRITES.contains(&(container, codec))), "{pair}: Apple's own answer");
            }
        }
    }
}

/// The pairs Apple's writer takes — H.264 in either container, H.265 in the
/// MP4, each ProRes in the MOV — as its source says (`apple.rs` `probe`,
/// which asks no OS). ↩️Held to the C's answer on the Mac until the
/// connection round deleted the C (H, 2026-11-08).
const APPLE_WRITES: [(i32, i32); 8] = [(0, 0), (1, 0), (0, 1), (1, 2), (1, 3), (1, 4), (1, 5), (1, 6)];

/// Whether this platform's writer is held to its own words: Windows's,
/// measured (2026-11-07), and the Linux stub's, its source (`none.rs`).
/// ⚠️Not the Mac's: its words were to be held once its job read alike with
/// the C's (관제 connection-round-checklist 11-07 21:04: two owners' red in
/// one run costs a run to tell apart), and the C went first (H, 2026-11-08)
/// — unmeasured, as Android's are, which no run of these tests reaches.
const HELD: bool = !cfg!(any(target_os = "android", target_vendor = "apple"));

/// What Windows's writer says of a pair it does not write.
const NOT_ON_WINDOWS: &str = "video export: Windows writes MP4 H.264/H.265 here - MOV/ProRes go through FFmpeg";

/// The Linux stub's one answer to every open.
const NO_OS: &str = "video export: no OS encoder on this platform";

/// What a held platform's writer says: Windows's `windows`, the Linux
/// stub's `linux`.
fn own((answer, words): (i32, &str), linux: (i32, &str)) -> (i32, String) {
    let (answer, words) = if cfg!(windows) { (answer, words) } else { linux };
    (answer, words.to_owned())
}

/// A job no platform writes — a codec that is none of them — which every
/// platform's writer turns away: its own refusal of the pair, or the Linux
/// stub's 「no OS encoder」.
///
/// ↩️2026-11-07: it was a container that is none of them, said here to be
/// turned away everywhere without Apple's pair law read: that law — the C's
/// and the Rust's alike — takes H.264 in any container, so on the Mac the
/// job was written, no error was left, and the tests compared whatever the
/// test before had left (bundle GPU CI 42353590096: 「a MOV」 Rust
/// `(1, "…bad open parameters")` against the C's `(1, "")`, and 「room for
/// 2」). Hence the refusal is now asserted, not assumed.
const NO_CODEC: Shape = Shape { codec: 7, ..MOVIE };

/// An open every platform turns away, so the last error a step is read
/// after is that refusal's, not what the test before left. ⚠️Not an open
/// with no path: that is no job, which the one law turns away in its own
/// words (`Job::well_formed`) — the words the law's test must see each step
/// leave anew.
fn turn_away_a_job() {
    let file = temp("turned-away", NO_CODEC.container);
    assert_eq!(tried(Some(file.to_str().unwrap()), NO_CODEC), 0, "{NO_CODEC:?} is a job no platform writes");
}

/// `step`'s answer and what the export said after it, from the same last
/// error — an open turned away ([`turn_away_a_job`]) — since a step that
/// says nothing leaves whatever the test before it left.
/// ↩️2026-11-07: without it a test that asked one writer alone (sound at no
/// rate) made the next test's 「nothing open」 differ, in 2 runs of 8.
fn say(step: impl FnOnce() -> i32) -> (i32, String) {
    turn_away_a_job();
    (step(), last_error())
}

/// `said` held to the platform's writer's own words, where [`HELD`].
fn expect_own(what: &str, said: &(i32, String), windows: (i32, &str), linux: (i32, &str)) {
    if HELD {
        assert_eq!(*said, own(windows, linux), "{what}: this platform's own words");
    }
}

// Every open a platform turns away: pairs it does not write, a path that
// does not convert or that leads nowhere, and a second job while one runs.
// A pair one platform writes (a MOV on Apple) is let go of again. A job that
// is no job is the one law's, below. Where [`HELD`], in the platform's own
// words — but for a folder that is not there: which call refuses it is the
// OS's (on Windows, Media Foundation's sink), and so are the words, held
// only to say why (유저 connection-round-checklist-Q14, 2026-11-07).
// ↩️Each was also turned away with the C's words until the connection round
// deleted the C (H, 2026-11-08).
#[test]
fn an_open_is_refused_in_the_platform_s_words() {
    let _one = one_at_a_time();
    let file = temp("refused", 0);
    let path = file.to_str().unwrap();
    for (what, shape) in [
        ("a MOV", Shape { container: 1, ..MOVIE }),
        ("ProRes in an MP4", Shape { codec: 2, ..MOVIE }),
        ("ProRes 4444", Shape { codec: 6, ..MOVIE }),
        ("no such codec", NO_CODEC),
    ] {
        let said = say(|| tried(Some(path), shape));
        expect_own(what, &said, (0, NOT_ON_WINDOWS), (0, NO_OS));
    }
    let long = std::env::temp_dir().join("a".repeat(1100)).to_str().unwrap().to_owned();
    let said = say(|| tried(Some(&long), MOVIE));
    expect_own("a path too long to convert", &said, (0, "video export: the output path did not convert"), (0, NO_OS));
    let nowhere = std::env::temp_dir().join("no-such-folder-here").join("x.mp4").to_str().unwrap().to_owned();
    let said = say(|| tried(Some(&nowhere), MOVIE));
    assert!(!HELD || (said.0 == 0 && !said.1.is_empty()), "a path into no folder is refused, and says why: {said:?}");
    let said = say(|| {
        if open(Some(path), MOVIE) == 0 {
            return -1;
        }
        let second = open(Some(path), MOVIE);
        qa_video_export_abort();
        second
    });
    expect_own("a second job while one runs", &said, (0, super::BAD_OPEN), (-1, NO_OS));
    std::fs::remove_file(&file).ok();
}

// A job that is no job — bad numbers, a container outside the lineup, sound
// at no rate, no path — turned away by the one law (`Job::well_formed`)
// before any platform answers, on every platform alike. The law's, not a
// platform's: the C spelled it once per platform, and of its four only
// Windows's turned all of these away — Apple's and Android's handed their
// encoders sound at 0 Hz, Apple's wrote H.264 into a container that is none,
// and the Linux stub said 「no OS encoder」 of every one. Each is asked after
// an open that leaves other words, so each answer is its own.
#[test]
fn a_job_that_is_no_job_is_refused_before_any_platform_answers() {
    let _one = one_at_a_time();
    let file = temp("no-job", 0);
    let path = Some(file.to_str().unwrap());
    for (what, path, shape) in [
        ("no width", path, Shape { width: 0, ..MOVIE }),
        ("no height", path, Shape { height: 0, ..MOVIE }),
        ("a negative width", path, Shape { width: -1, ..MOVIE }),
        ("no frame rate", path, Shape { fps: (0, 1), ..MOVIE }),
        ("a rate over nothing", path, Shape { fps: (24, 0), ..MOVIE }),
        ("negative channels", path, Shape { channels: -1, ..MOVIE }),
        ("no such container", path, Shape { container: 2, ..MOVIE }),
        ("a container below the lineup", path, Shape { container: -1, ..MOVIE }),
        ("sound at no rate", path, Shape { sample_rate: 0, ..MOVIE }),
        ("no path", None, MOVIE),
    ] {
        assert_eq!(say(|| tried(path, shape)), (0, super::BAD_OPEN.to_owned()), "{what}");
    }
    std::fs::remove_file(&file).ok();
}

// Nothing open: nothing written, nothing finished, an abort that does
// nothing — and an open job takes no null frame, no sound when silent, and
// opens again after an abort. Where [`HELD`], the platform's own answers,
// none of them saying anything: what is left to read is the open turned
// away before. ↩️Each was also the C's answer until the connection round
// deleted the C (H, 2026-11-08).
#[test]
fn a_call_out_of_turn_is_answered_in_the_platform_s_words() {
    let _one = one_at_a_time();
    let file = temp("out-of-turn", 0);
    let path = file.to_str().unwrap();
    let frame = moving(64, 48, 0);
    let pcm = saw(10, 2, 0);
    // SAFETY: each pointer is null or holds what the call reads.
    let said = say(|| unsafe {
        qa_video_export_abort();
        qa_video_export_write_frame(frame.as_ptr()) * 100
            + qa_video_export_write_audio(pcm.as_ptr(), 10) * 10
            + qa_video_export_finish()
    });
    expect_own("nothing open", &said, (0, NOT_ON_WINDOWS), (0, NO_OS));
    // SAFETY: as above.
    let said = say(|| unsafe {
        if open(Some(path), Shape { channels: 0, ..MOVIE }) == 0 {
            return -1;
        }
        let answers = qa_video_export_write_frame(std::ptr::null()) * 1000
            + qa_video_export_write_audio(pcm.as_ptr(), 10) * 100
            + qa_video_export_write_frame(frame.as_ptr()) * 10;
        qa_video_export_abort();
        let again = open(Some(path), MOVIE);
        qa_video_export_abort();
        answers + again
    });
    expect_own("an open job", &said, (11, NOT_ON_WINDOWS), (-1, NO_OS));
    std::fs::remove_file(&file).ok();
}

// The message is handed out cut to the room given — a byte short of it, for
// the NUL — and -1 where there is no room or nowhere to put it, on every
// platform: the handout is this code's, and only the words are the
// platform's (where [`HELD`], its refusal of a codec that is none).
// ↩️It was held to the C's handout until the connection round deleted the C
// (H, 2026-11-08), and the cut to the platform's words where held alone.
#[test]
fn the_last_error_is_cut_to_the_room_given() {
    let _one = one_at_a_time();
    turn_away_a_job();
    let (length, whole) = error(256);
    assert!(length > 4 && length as usize == whole.len(), "a refusal that says why, whole: {length} {whole:?}");
    expect_own("the refusal", &(0, whole.clone()), (0, NOT_ON_WINDOWS), (0, NO_OS));
    let first = |count: usize| String::from_utf8_lossy(&whole.as_bytes()[..count]).into_owned();
    for (capacity, length, words) in [(-1, -1, String::new()), (0, -1, String::new()), (1, -1, String::new()), (2, 1, first(1)), (5, 4, first(4))] {
        assert_eq!(error(capacity), (length, words), "room for {capacity}");
    }
    // SAFETY: null is nowhere to put it.
    assert_eq!(unsafe { qa_video_export_error(std::ptr::null_mut(), 64) }, -1, "nowhere");
}
