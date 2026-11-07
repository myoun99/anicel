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
                s.alpha,
                s.bitrate_bps,
            )
        }
    }

    /// What an open of `shape` at `path` answers, the job let go of again
    /// if it was taken — a pair one platform turns away, another writes.
    fn tried(&self, path: Option<&str>, shape: Shape) -> i32 {
        let opened = self.open(path, shape);
        if opened == 1 {
            // SAFETY: an open writer, let go of.
            unsafe { (self.abort)() };
        }
        opened
    }

    /// Whether this writer takes `shape` on this machine.
    fn opens(&self, shape: Shape) -> bool {
        let file = temp("opens", shape.container);
        let opened = self.tried(Some(file.to_str().unwrap()), shape) == 1;
        std::fs::remove_file(&file).ok();
        opened
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

/// One box of a movie: its type, where it starts, where what it holds
/// starts past its header, and where it ends.
#[derive(Clone, Copy)]
struct Atom {
    kind: [u8; 4],
    at: usize,
    body: usize,
    until: usize,
}

/// The boxes directly in `movie[start..end]`. A box's size is its first 32
/// bits — or, when those say 1, the 64 that follow its type, and when they
/// say 0, all the rest of what holds it (ISO/IEC 14496-12, 4.2). A box that
/// does not fit says where it is and what its head holds.
///
/// ↩️2026-11-07: it read the 32 bits alone, and a MOV the Mac wrote stopped
/// the whole comparison at its first box past `ftyp` — 「a box at 28 runs
/// past its parent」 (bundle GPU CI 42353590096), with no movie named and
/// none of the rest asked.
fn children(movie: &[u8], start: usize, end: usize) -> Result<Vec<Atom>, String> {
    let mut atoms = Vec::new();
    let mut at = start;
    while at + 8 <= end {
        let (size, body) = match be32(movie, at) {
            0 => (end - at, at + 8),
            1 if at + 16 <= end => {
                let large = u64::from_be_bytes(movie[at + 8..at + 16].try_into().unwrap());
                (usize::try_from(large).unwrap_or(usize::MAX), at + 16)
            }
            size => (size, at + 8),
        };
        if size < body - at || size > end - at {
            return Err(format!("the box at {at} does not fit what holds it (to {end}), its head {}", hex(&movie[at..end.min(at + 16)])));
        }
        atoms.push(Atom { kind: movie[at + 4..at + 8].try_into().unwrap(), at, body, until: at + size });
        at += size;
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
    if rest.is_empty() { Ok(Some(atom)) } else { find(movie, atom.body, atom.until, rest) }
}

/// A track as its writer laid it: the four letters its sample entry names
/// (`avc1`, `mp4a`, `apcn` …) and its samples in order — its sample sizes,
/// laid along its chunks, with VideoToolbox's notes taken out ([`NOTE`]),
/// and how many it held.
struct Track {
    format: String,
    samples: Vec<u8>,
    notes: usize,
}

/// The UUID of the user data VideoToolbox writes into its H.264 and HEVC
/// streams, 47564adc-5c4c-433f-94ef-c5113cd143a8: an SEI message of
/// payloadType 5 (user data unregistered — a UUID, then bytes the standard
/// leaves to whoever wrote them), which Apple names nowhere (developer
/// forums thread 778196 asks what it holds and has no answer;
/// github.com/PierceLBrooks/vtUudSeiNalCmake prints its UUID).
///
/// ↩️2026-11-07: ITS USER DATA IS TAKEN OUT; its UUID and size stay. Every
/// H.264 and HEVC movie the Mac wrote parted from the C's at one place, and
/// the C's own second movie parted from its first there too (bundle GPU CI
/// 42366555125, `3845e935c`; 관제 11-07 20:30: 「a byte the C cannot match
/// with itself cannot be asked of the Rust」). Measured there: two bytes,
/// 49–50 of an H.264 track's samples and 50–51 of an HEVC one's — the one
/// byte the HEVC NAL header is longer, so the first NAL unit, and the same
/// bytes after it in both codecs, so none of either codec's own syntax —
/// holding a count that rose 0x14 with every movie made, in the order they
/// were made (C, Rust, C again; c3c8, c3dc, c3f0, then c404 for the next
/// movie), on into the release run's process (c724). Read, not measured:
/// the first unit is this SEI, its user data past the unit's size, its
/// header, a byte each of payloadType and payloadSize, and the UUID — from
/// byte 23 in H.264, 24 in HEVC — and the count is the user data's 27th and
/// 28th bytes as written in both: a number the machine keeps across
/// processes, rising with each encoder session, which no writer decides.
/// The whole user data goes, not
/// those two bytes: Apple names none of its fields, and a field cut from one
/// run's bytes would be a guess. Each track says how many notes it held, so
/// a movie whose notes are not where this says still parts, and says so.
const NOTE: [u8; 16] = [0x47, 0x56, 0x4a, 0xdc, 0x5c, 0x4c, 0x43, 0x3f, 0x94, 0xef, 0xc5, 0x11, 0x3c, 0xd1, 0x43, 0xa8];

/// How a track's samples are coded, for the codecs that carry SEI: the
/// bytes each NAL unit's size takes, the bytes of its header, and its SEI
/// unit types.
struct Coding {
    length: usize,
    header: usize,
    sei: &'static [u8],
}

impl Coding {
    /// The coding `format`'s entry names, its sizes as long as its
    /// configuration box says (the low two bits of `avcC`'s fifth byte,
    /// `hvcC`'s twenty-second) — or none for a codec without SEI.
    fn of(movie: &[u8], entry: Atom, format: &str) -> Result<Option<Coding>, String> {
        let (kind, at, header, sei): (&[u8; 4], usize, usize, &'static [u8]) = match format {
            "avc1" => (b"avcC", 4, 1, &[6]),
            "hvc1" => (b"hvcC", 21, 2, &[39, 40]),
            _ => return Ok(None),
        };
        // A visual sample entry's own fields, 78 bytes, before its boxes.
        let config = find(movie, entry.body + 78, entry.until, &[kind])?.ok_or_else(|| format!("an {format} entry with no configuration"))?;
        let length = usize::from(*movie.get(config.body + at).ok_or("a configuration too short to say its sizes")? & 3) + 1;
        Ok(Some(Coding { length, header, sei }))
    }

    fn unit_type(&self, unit: &[u8]) -> u8 {
        if self.header == 1 { unit[0] & 0x1f } else { unit[0] >> 1 & 0x3f }
    }
}

/// Takes VideoToolbox's notes out of one coded sample, its NAL units each
/// after its size; how many it took.
fn take_out_notes(sample: &mut [u8], coding: &Coding) -> Result<usize, String> {
    let mut notes = 0;
    let mut at = 0;
    while at < sample.len() {
        let size = sample.get(at..at + coding.length).ok_or("a NAL unit's size runs past its sample")?;
        let size = size.iter().fold(0, |size, &byte| size << 8 | usize::from(byte));
        let unit = sample.get_mut(at + coding.length..at + coding.length + size).ok_or("a NAL unit runs past its sample")?;
        if unit.len() > coding.header && coding.sei.contains(&coding.unit_type(unit)) {
            notes += take_out_note(&mut unit[coding.header..])?;
        }
        at += coding.length + size;
    }
    Ok(notes)
}

/// Takes VideoToolbox's note out of one SEI unit's messages, as written
/// (past its header): the note's user data is zeroed where it lies, the
/// 0x03 the encoder put after two zeros in it along with it.
fn take_out_note(written: &mut [u8]) -> Result<usize, String> {
    // Where each byte of the messages lies as written: every 0x03 that
    // follows two zeros is the encoder's, not the messages'.
    let mut lies = Vec::new();
    let mut zeros = 0;
    for (at, &byte) in written.iter().enumerate() {
        if zeros >= 2 && byte == 3 {
            zeros = 0;
            continue;
        }
        zeros = if byte == 0 { zeros + 1 } else { 0 };
        lies.push(at);
    }
    let messages: Vec<u8> = lies.iter().map(|&at| written[at]).collect();
    let mut notes = 0;
    let mut at = 0;
    // Message after message, up to the last byte's stop bit.
    while messages.len() - at > 1 {
        let (kind, after) = sei_number(&messages, at)?;
        let (size, body) = sei_number(&messages, after)?;
        let end = body + size;
        let payload = messages.get(body..end).ok_or("an SEI message runs past its unit")?;
        if kind == 5 && payload.len() > NOTE.len() && payload[..NOTE.len()] == NOTE {
            written[lies[body + NOTE.len()]..=lies[end - 1]].fill(0);
            notes += 1;
        }
        at = end;
    }
    Ok(notes)
}

/// An SEI message's type or size — 255 for each 0xff byte, then the byte
/// that is not — and where what follows it starts.
fn sei_number(messages: &[u8], mut at: usize) -> Result<(usize, usize), String> {
    let mut number = 0;
    loop {
        let byte = *messages.get(at).ok_or("an SEI message runs past its unit")?;
        number += usize::from(byte);
        at += 1;
        if byte != 0xff {
            return Ok((number, at));
        }
    }
}

fn track(movie: &[u8], trak: Atom) -> Result<Track, String> {
    let table = find(movie, trak.body, trak.until, &[b"mdia", b"minf", b"stbl"])?.ok_or("a track with no sample table")?;
    // Where a table's fields start: past its version and flags.
    let fields = |kind: &[u8; 4]| -> Result<usize, String> {
        let atom = find(movie, table.body, table.until, &[kind])?;
        Ok(atom.ok_or_else(|| format!("a sample table with no {}", String::from_utf8_lossy(kind)))?.body + 4)
    };
    // The first entry, past the version, the flags and the count of entries.
    let stsd = find(movie, table.body, table.until, &[b"stsd"])?.ok_or("a sample table with no stsd")?;
    let entry = *children(movie, stsd.body + 8, stsd.until)?.first().ok_or("a sample table with no entry")?;
    let format = String::from_utf8_lossy(&entry.kind).into_owned();
    let coding = Coding::of(movie, entry, &format)?;
    let sizes_at = fields(b"stsz")?;
    let uniform = be32(movie, sizes_at);
    let sizes: Vec<usize> =
        (0..be32(movie, sizes_at + 4)).map(|k| if uniform != 0 { uniform } else { be32(movie, sizes_at + 8 + 4 * k) }).collect();
    // 32-bit chunk offsets: the only kind the comparison reads.
    let chunks_at = fields(b"stco")?;
    let runs_at = fields(b"stsc")?;
    let runs: Vec<(usize, usize)> =
        (0..be32(movie, runs_at)).map(|k| (be32(movie, runs_at + 4 + 12 * k), be32(movie, runs_at + 8 + 12 * k))).collect();
    let mut bytes = Vec::new();
    let mut notes = 0;
    let mut sample = 0;
    for chunk in 0..be32(movie, chunks_at) {
        let per_chunk = runs.iter().take_while(|(first, _)| *first <= chunk + 1).last().ok_or("no run from chunk 1")?.1;
        let mut at = be32(movie, chunks_at + 4 + 4 * chunk);
        for size in sizes.get(sample..sample + per_chunk).ok_or("more samples in chunks than sizes")? {
            let start = bytes.len();
            bytes.extend_from_slice(movie.get(at..at + size).ok_or_else(|| format!("a sample at {at} runs past the file"))?);
            if let Some(coding) = &coding {
                notes += take_out_notes(&mut bytes[start..], coding).map_err(|why| format!("the sample at {at}: {why}"))?;
            }
            at += size;
        }
        sample += per_chunk;
    }
    if sample != sizes.len() {
        return Err(format!("{} of {} samples lie in a chunk", sample, sizes.len()));
    }
    Ok(Track { format, samples: bytes, notes })
}

/// A movie as its writer decides it: every box but the media data and the
/// chunk tables, the clock taken out, and each track's samples in order,
/// VideoToolbox's notes taken out ([`NOTE`]).
///
/// The clock is the creation and modification times the muxer stamps into
/// each `mvhd`, `tkhd` and `mdhd` — the seconds the file was finished in,
/// which two writers a second apart never share. How the samples are cut
/// into chunks is the muxer's too: the C's own fixture movie comes out of
/// it two ways (2026-11-06, 30 runs: its 47 sound samples chunked
/// 15/15/17 in half of them, 15/16/16 in the other half, every sample the
/// same) — the cut follows when the sound encoder's output reaches it.
struct Movie {
    boxes: Vec<([u8; 4], Vec<u8>)>,
    tracks: Vec<Track>,
    /// The boxes the clock was taken out of, so a mask that found none
    /// says so.
    stamped: usize,
}

fn read_into(movie: &[u8], start: usize, end: usize, into: &mut Movie) -> Result<(), String> {
    for atom in children(movie, start, end)? {
        match &atom.kind {
            b"moov" | b"mdia" | b"minf" | b"stbl" => read_into(movie, atom.body, atom.until, into)?,
            b"trak" => {
                read_into(movie, atom.body, atom.until, into)?;
                into.tracks.push(track(movie, atom)?);
            }
            b"mdat" | b"stco" | b"stsc" => {}
            b"mvhd" | b"tkhd" | b"mdhd" => {
                let mut bytes = movie[atom.at..atom.until].to_vec();
                // Past the header: the version, the flags, then the two times
                // — in 32 bits each at version 0, in 64 at 1.
                let version = atom.body - atom.at;
                let times = if bytes[version] == 1 { 16 } else { 8 };
                bytes[version + 4..version + 4 + times].fill(0);
                into.stamped += 1;
                into.boxes.push((atom.kind, bytes));
            }
            _ => into.boxes.push((atom.kind, movie[atom.at..atom.until].to_vec())),
        }
    }
    Ok(())
}

fn read_movie(movie: &[u8]) -> Result<Movie, String> {
    let mut read = Movie { boxes: Vec::new(), tracks: Vec::new(), stamped: 0 };
    read_into(movie, 0, movie.len(), &mut read)?;
    Ok(read)
}

/// Where two runs of bytes first part: the first byte that differs, or the
/// end of the shorter when one runs on past the other.
fn parted(a: &[u8], b: &[u8]) -> Option<usize> {
    a.iter().zip(b).position(|(a, b)| a != b).or_else(|| (a.len() != b.len()).then_some(a.len().min(b.len())))
}

/// The bytes around `at`, in hex, the one at `at` in brackets.
fn around(bytes: &[u8], at: usize) -> String {
    let from = at.saturating_sub(8);
    let hex: Vec<String> =
        (from..(at + 9).min(bytes.len())).map(|i| if i == at { format!("[{:02x}]", bytes[i]) } else { format!("{:02x}", bytes[i]) }).collect();
    format!("@{from} {}", hex.join(" "))
}

/// What parts the Rust's movie of `shape` from the C's, but for the clock
/// and the chunking: each box that is not the same, and each track whose
/// samples are not — said with the track's format, the bytes around where
/// they part, and whether the C's own second movie parts there too. A movie
/// that does not read is said so, with what stopped the reading.
fn movie_apart(name: &str, shape: Shape, frames: i32) -> Vec<String> {
    let (c, rust) = (c(), rust());
    let c_movie = |run: &str| read_movie(&c.movie(&temp(&format!("{name}-c{run}"), shape.container), shape, frames));
    let (theirs, ours) = (c_movie(""), read_movie(&rust.movie(&temp(&format!("{name}-rust"), shape.container), shape, frames)));
    let (theirs, ours) = match (theirs, ours) {
        (Ok(theirs), Ok(ours)) => (theirs, ours),
        (theirs, ours) => {
            let unread = [("the C's", theirs.err()), ("ours", ours.err())];
            return unread.into_iter().filter_map(|(whose, why)| Some(format!("{name}: {whose} movie does not read — {}", why?))).collect();
        }
    };
    let tracks = if shape.channels > 0 { 2 } else { 1 };
    if theirs.stamped != 1 + 2 * tracks || theirs.tracks.len() != tracks {
        return vec![format!(
            "{name}: the C's movie has {} clocks and {} tracks where the mask looks for {} and {tracks}",
            theirs.stamped,
            theirs.tracks.len(),
            1 + 2 * tracks
        )];
    }
    let kinds = |movie: &Movie| movie.boxes.iter().map(|(kind, _)| String::from_utf8_lossy(kind).into_owned()).collect::<Vec<_>>();
    if kinds(&ours) != kinds(&theirs) {
        return vec![format!("{name}: the boxes, {:?} against the C's {:?}", kinds(&ours), kinds(&theirs))];
    }
    let mut apart: Vec<String> = ours
        .boxes
        .iter()
        .zip(&theirs.boxes)
        .filter(|((_, ours), (_, theirs))| ours != theirs)
        .map(|((kind, _), _)| format!("{name}: the {} box", String::from_utf8_lossy(kind)))
        .collect();
    let mut again = None;
    for (k, (ours, theirs)) in ours.tracks.iter().zip(&theirs.tracks).enumerate() {
        if ours.notes != theirs.notes {
            apart.push(format!("{name}: track {k} ({}) holds {} VideoToolbox notes against the C's {}", ours.format, ours.notes, theirs.notes));
        }
        let Some(at) = parted(&ours.samples, &theirs.samples) else {
            continue;
        };
        // The premise, measured where it failed: whether the C writes these
        // samples the same twice.
        let itself = match again.get_or_insert_with(|| c_movie("-again")) {
            Ok(again) => match again.tracks.get(k) {
                Some(again) => parted(&again.samples, &theirs.samples)
                    .map_or("the same".to_owned(), |at| format!("apart at {at}, {}", around(&again.samples, at))),
                None => format!("has {} tracks", again.tracks.len()),
            },
            Err(why) => format!("does not read — {why}"),
        };
        apart.push(format!(
            "{name}: track {k} ({})'s samples, {} bytes against the C's {}, {} notes taken out, first apart at {at} — ours {}, the C's {}; the C's own second movie: {itself}",
            ours.format,
            ours.samples.len(),
            theirs.samples.len(),
            theirs.notes,
            around(&ours.samples, at),
            around(&theirs.samples, at),
        ));
    }
    apart
}

// The box walker by hand, since no movie this machine writes has a box sized
// in 64 bits or one that runs to the end: a box of each after a plain one,
// and boxes that do not fit — longer than what holds them, shorter than
// their own header.
#[test]
fn every_box_size_iso_bmff_writes_is_walked() {
    let mut movie = vec![0, 0, 0, 12];
    movie.extend_from_slice(b"ftyp");
    movie.extend_from_slice(&[1, 2, 3, 4, 0, 0, 0, 1]);
    movie.extend_from_slice(b"free");
    movie.extend_from_slice(&20u64.to_be_bytes());
    movie.extend_from_slice(&[7, 7, 7, 7, 0, 0, 0, 0]);
    movie.extend_from_slice(b"mdat");
    movie.extend_from_slice(&[9; 6]);
    let atoms = children(&movie, 0, movie.len()).unwrap();
    let spans: Vec<_> = atoms.iter().map(|atom| (atom.kind, atom.at, atom.body, atom.until)).collect();
    assert_eq!(spans, [(*b"ftyp", 0, 8, 12), (*b"free", 12, 28, 32), (*b"mdat", 32, 40, 46)]);
    for (size, why) in [
        (40, "the box at 0 does not fit what holds it (to 12), its head 00 00 00 28 6d 6f 6f 76 00 00 00 00"),
        (5, "the box at 0 does not fit what holds it (to 12), its head 00 00 00 05 6d 6f 6f 76 00 00 00 00"),
    ] {
        let unfit = [0, 0, 0, size, b'm', b'o', b'o', b'v', 0, 0, 0, 0];
        assert_eq!(children(&unfit, 0, unfit.len()).err().as_deref(), Some(why), "size {size}");
    }
}

// VideoToolbox's note by hand, since no writer on this machine puts one in:
// an SEI unit of two messages — the note, its user data holding a 0x03 the
// encoder put after two zeros and one of the data's own after it, then a
// recovery point — an SEI unit of the note's UUID under the payloadType
// 255 + 5 and of another UUID under 5, and a slice, in H.264 and in HEVC,
// each the one sample of a track as a movie holds it; and units that do not
// fit.
#[test]
fn video_toolbox_s_note_and_only_it_is_taken_out() {
    let sized = |bytes: &[u8]| [&(bytes.len() as u32 + 4).to_be_bytes()[..], bytes].concat();
    let unit = |header: &[u8], body: &[u8]| [&(header.len() as u32 + body.len() as u32).to_be_bytes()[..], header, body].concat();
    for (format, config, at, sei, slice) in
        [(b"avc1", b"avcC", 4, &[0x06][..], &[0x65][..]), (b"hvc1", b"hvcC", 21, &[0x4e, 0x01][..], &[0x26, 0x01][..])]
    {
        let sample = |user_data: &[u8]| {
            let noted = [&[5, 22][..], &NOTE, user_data, &[6, 1, 0x84, 0x80]].concat();
            let others = [&[0xff, 5, 18][..], &NOTE, &[0xaa, 0xbb, 5, 18], &[0x11; 16], &[0xaa, 0xbb, 0x80]].concat();
            [unit(sei, &noted), unit(sei, &others), unit(slice, &[0x88, 0x84, 0x00, 0x00, 0x03, 0x01])].concat()
        };
        let written = sample(&[0x01, 0x00, 0x00, 0x03, 0x03, 0xc3, 0xdc]);
        // The sample first, at 0, then its track.
        let mut configuration = vec![0; at + 1];
        configuration[at] = 0xff;
        let entry = sized(&[&format[..], &[0; 78], &sized(&[&config[..], &configuration].concat())].concat());
        let table = [
            sized(&[&b"stsd"[..], &[0, 0, 0, 0, 0, 0, 0, 1], &entry].concat()),
            sized(&[&b"stsz"[..], &[0; 8], &1u32.to_be_bytes(), &(written.len() as u32).to_be_bytes()].concat()),
            sized(&[&b"stco"[..], &[0; 4], &1u32.to_be_bytes(), &[0; 4]].concat()),
            sized(&[&b"stsc"[..], &[0; 4], &[0, 0, 0, 1], &[0, 0, 0, 1], &[0, 0, 0, 1], &[0, 0, 0, 1]].concat()),
        ]
        .concat();
        let trak = sized(&[&b"trak"[..], &sized(&[&b"mdia"[..], &sized(&[&b"minf"[..], &sized(&[&b"stbl"[..], &table].concat())].concat())].concat())].concat());
        let movie = [&written[..], &trak].concat();
        let read = track(&movie, children(&movie, written.len(), movie.len()).unwrap()[0]).unwrap();
        assert_eq!((read.format.as_str(), read.notes), (std::str::from_utf8(format).unwrap(), 1));
        assert_eq!(hex(&read.samples), hex(&sample(&[0; 7])), "{format:?}");
    }
    let h264 = Coding { length: 4, header: 1, sei: &[6] };
    for (mut sample, why) in [
        (vec![0, 0], "a NAL unit's size runs past its sample"),
        (vec![0, 0, 0, 9, 0x06, 0x05], "a NAL unit runs past its sample"),
        (vec![0, 0, 0, 4, 0x06, 0x05, 0x30, 0x80], "an SEI message runs past its unit"),
        (vec![0, 0, 0, 3, 0x06, 0xff, 0xff], "an SEI message runs past its unit"),
    ] {
        assert_eq!(take_out_notes(&mut sample, &h264), Err(why.to_owned()), "{why}");
    }
}

// The fixtures' movie, which the hardware law keeps in software; an odd,
// silent one the pad makes even; a film the hardware takes; the law's first
// side past the failed one — and the side that failed, held off hardware
// (on the Intel machine the law was measured on, asking there fails at
// Finalize); an exact NTSC fraction with mono sound at another rate and a
// bitrate named; one named past the ceiling; a Korean name; and where the
// C writes them (Apple), H.264 in a MOV, ProRes 422 with its PCM, and
// ProRes 4444 keeping a picture's alpha. Each byte for byte with the C's,
// but for the clock, the chunking and VideoToolbox's note (`Movie`).
//
// ↩️2026-11-07: every movie is made before any is judged, and a track that
// parts says where, around what, and whether the C parts from itself there.
// The first Mac run stopped at its first movie — 「mov: track 0's samples,
// 732 bytes against the C's 732, first apart at Some(50)」 (bundle GPU CI
// 1cca0c1de) — with the other eleven unasked and the premise, that the C
// writes the same bytes twice, unmeasured; no Mac is on the machine this is
// written on, so the next run has to answer both (관제 11-07). It answered
// (42366555125): every H.264 and HEVC movie parts at one place, where the C
// parts from itself — VideoToolbox's note ([`NOTE`]).
#[test]
fn the_movie_is_the_c_s_but_for_its_clock_chunking_and_note() {
    let _one = one_at_a_time();
    // SAFETY: no arguments.
    if unsafe { (c().supported)() } == 0 {
        return;
    }
    let mut movies = Vec::new();
    for (name, shape) in [
        ("mov", Shape { container: 1, ..MOVIE }),
        ("prores-422", Shape { container: 1, codec: 4, ..MOVIE }),
        ("prores-4444-alpha", Shape { container: 1, codec: 6, alpha: 1, channels: 0, ..MOVIE }),
    ] {
        if c().opens(shape) {
            movies.push((name, shape, 6));
        }
    }
    let ntsc = Shape { width: 96, height: 64, fps: (24000, 1001), sample_rate: 44100, channels: 1, bitrate_bps: 3_000_000, ..MOVIE };
    movies.extend([
        ("fixture", MOVIE, 24),
        ("odd-silent", Shape { width: 63, height: 47, channels: 0, ..MOVIE }, 6),
        ("full-hd", Shape { width: 1920, height: 1080, ..MOVIE }, 6),
        ("past-the-law", Shape { width: 49, height: 64, channels: 0, ..MOVIE }, 6),
        ("the-failed-side", Shape { width: 48, height: 64, channels: 0, ..MOVIE }, 6),
        ("ntsc-mono", ntsc, 12),
        ("past-the-ceiling", Shape { width: 64, height: 64, bitrate_bps: 80_000_000, ..MOVIE }, 6),
        ("영상", MOVIE, 3),
    ]);
    // SAFETY: no arguments.
    if unsafe { (c().probe)(0, 1) } == 1 {
        movies.push(("hevc", Shape { width: 1280, height: 720, channels: 0, codec: 1, ..MOVIE }, 6));
    }
    let apart: Vec<String> = movies.into_iter().flat_map(|(name, shape, frames)| movie_apart(name, shape, frames)).collect();
    assert!(apart.is_empty(), "{}", apart.join("\n"));
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

// What this machine writes, pair by pair, is the C's answer — in the
// lineup's two containers. A container outside it is written nowhere, held
// to the law (`in_the_lineup`) rather than to the C, whose Apple writer took
// H.264 in any container (관제's judgment, connection-round-checklist 11-07
// 18:15).
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
            let want = if container == 0 || container == 1 { theirs } else { 0 };
            assert_eq!(ours, want, "container {container}, codec {codec}");
        }
    }
}

/// A job no platform writes — a codec that is none of them — which the C
/// and the Rust turn away in the same words wherever this runs: the
/// writer's own refusal of the pair, or the Linux stub's 「no OS encoder」.
///
/// ↩️2026-11-07: it was a container that is none of them, said here to be
/// turned away everywhere without Apple's pair law read: that law — the C's
/// and the Rust's alike — takes H.264 in any container, so on the Mac the
/// job was written, no error was left, and the tests compared whatever the
/// test before had left (bundle GPU CI 42353590096: 「a MOV」 Rust
/// `(1, "…bad open parameters")` against the C's `(1, "")`, and 「room for
/// 2」). Hence the refusal is now asserted, not assumed.
const NO_CODEC: Shape = Shape { codec: 7, ..MOVIE };

/// An open `encoder` turns away as the other does, so the last error it
/// leaves is one both said. ⚠️Not an open with no path: that is no job,
/// which the Rust turns away before any platform answers and the C's Linux
/// stub does not (`Job::well_formed`).
fn turned_away_alike(encoder: &Encoder) {
    let file = temp("alike", NO_CODEC.container);
    assert_eq!(encoder.tried(Some(file.to_str().unwrap()), NO_CODEC), 0, "{NO_CODEC:?} is a job no platform writes");
}

/// `step` asked of both, with what each said after it: the answer and the
/// last error — from the same last error, an open both turn away, since a
/// step that says nothing leaves whatever the test before it left.
/// ↩️2026-11-07: without it a test that asked one writer alone (sound at no
/// rate) made the next test's 「nothing open」 differ, in 2 runs of 8.
fn both_say(what: &str, step: impl Fn(&Encoder) -> i32) {
    let (c, rust) = (c(), rust());
    for encoder in [c, rust] {
        turned_away_alike(&encoder);
    }
    let theirs = (step(&c), c.last_error());
    let ours = (step(&rust), rust.last_error());
    assert_eq!(ours, theirs, "{what}");
}

// Every open the C turns away, turned away with the C's words: pairs this
// platform does not write, a path that does not convert or that leads
// nowhere, and a second job while one runs. A pair one platform writes (a
// MOV on Apple) is let go of again, by both. A job that is no job is the
// one law's, below, not the C's.
#[test]
fn an_open_is_refused_as_the_c_refuses_it() {
    let _one = one_at_a_time();
    let file = temp("refused", 0);
    let path = file.to_str().unwrap();
    for (what, shape) in [
        ("a MOV", Shape { container: 1, ..MOVIE }),
        ("ProRes in an MP4", Shape { codec: 2, ..MOVIE }),
        ("ProRes 4444", Shape { codec: 6, ..MOVIE }),
        ("no such codec", NO_CODEC),
    ] {
        both_say(what, |encoder| encoder.tried(Some(path), shape));
    }
    let long = std::env::temp_dir().join("a".repeat(1100)).to_str().unwrap().to_owned();
    both_say("a path too long to convert", |encoder| encoder.tried(Some(&long), MOVIE));
    let nowhere = std::env::temp_dir().join("no-such-folder-here").join("x.mp4").to_str().unwrap().to_owned();
    both_say("a path into no folder", |encoder| encoder.tried(Some(&nowhere), MOVIE));
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

// A job that is no job — bad numbers, a container outside the lineup, sound
// at no rate, no path — turned away by the one law (`Job::well_formed`)
// before any platform answers, on every platform alike. Held to the law
// rather than to the C: the C spelled it once per platform, and of its four
// only Windows's turned all of these away — Apple's and Android's handed
// their encoders sound at 0 Hz, Apple's wrote H.264 into a container that is
// none, and the Linux stub said 「no OS encoder」 of every one. Each is asked
// after an open that leaves other words, so each answer is its own.
#[test]
fn a_job_that_is_no_job_is_refused_before_any_platform_answers() {
    let _one = one_at_a_time();
    let rust = rust();
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
        turned_away_alike(&rust);
        assert_eq!((rust.tried(path, shape), rust.last_error()), (0, super::BAD_OPEN.to_owned()), "{what}");
    }
    std::fs::remove_file(&file).ok();
}

// Nothing open: nothing written, nothing finished, an abort that does
// nothing — and an open job takes no null frame, no sound when silent, and
// opens again after an abort.
#[test]
fn a_call_out_of_turn_is_answered_as_the_c_answers_it() {
    let _one = one_at_a_time();
    let file = temp("out-of-turn", 0);
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
        turned_away_alike(&encoder);
    }
    for capacity in [-1, 0, 1, 2, 5, 256] {
        assert_eq!(rust.error(capacity), c.error(capacity), "room for {capacity}");
    }
    // SAFETY: null is nowhere to put it.
    let nowhere = unsafe { ((rust.error)(std::ptr::null_mut(), 64), (c.error)(std::ptr::null_mut(), 64)) };
    assert_eq!(nowhere, (-1, -1));
}
