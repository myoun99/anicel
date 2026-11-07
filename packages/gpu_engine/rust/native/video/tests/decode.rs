//! The Rust decoder against the engine's C (native/oracle): the same movie
//! opened by both, through the exports each has — its shape, every frame's
//! bytes in order and out of it, a span of a file plain and framed, the
//! slots, and the sentence each failure says. Where this build has no
//! decoder, that the two say so alike. And every movie the export writes,
//! read back by the Rust's as it was asked.
//!
//! ⚠️A process of its own, apart from the crate's tests: the movie is
//! written through the export, which keeps one job for the whole process,
//! and the crate's export tests hold that job for themselves.

use std::ffi::{CStr, CString, c_char};
use std::path::PathBuf;
use std::sync::{Mutex, MutexGuard, OnceLock, PoisonError};

use video::decode::{
    qa_video_decode_close, qa_video_decode_close_all, qa_video_decode_frame, qa_video_decode_info,
    qa_video_decode_last_error, qa_video_decode_open, qa_video_decode_open_span, qa_video_decode_supported,
};
use video::export::{
    qa_video_export_error, qa_video_export_finish, qa_video_export_open, qa_video_export_probe,
    qa_video_export_write_audio, qa_video_export_write_frame,
};

#[derive(Clone, Copy)]
struct Decoder {
    supported: extern "C" fn() -> i32,
    last_error: extern "C" fn() -> *const c_char,
    open: unsafe extern "C" fn(*const c_char) -> i32,
    open_span: unsafe extern "C" fn(*const c_char, i64, i64, i32) -> i32,
    info: unsafe extern "C" fn(i32, *mut i32, *mut i32, *mut i64, *mut i32, *mut i32) -> i32,
    frame: unsafe extern "C" fn(i32, i64, *mut u8, i32) -> i32,
    close: extern "C" fn(i32),
    close_all: extern "C" fn(),
}

fn c() -> Decoder {
    // SAFETY: qa_video_decode.c's declarations.
    unsafe {
        Decoder {
            supported: oracle::export("qa_video_decode_supported"),
            last_error: oracle::export("qa_video_decode_last_error"),
            open: oracle::export("qa_video_decode_open"),
            open_span: oracle::export("qa_video_decode_open_span"),
            info: oracle::export("qa_video_decode_info"),
            frame: oracle::export("qa_video_decode_frame"),
            close: oracle::export("qa_video_decode_close"),
            close_all: oracle::export("qa_video_decode_close_all"),
        }
    }
}

fn rust() -> Decoder {
    Decoder {
        supported: qa_video_decode_supported,
        last_error: qa_video_decode_last_error,
        open: qa_video_decode_open,
        open_span: qa_video_decode_open_span,
        info: qa_video_decode_info,
        frame: qa_video_decode_frame,
        close: qa_video_decode_close,
        close_all: qa_video_decode_close_all,
    }
}

/// What `info` answers: the shown size, the frame count and the rate.
type Info = (i32, i32, i64, (i32, i32));

impl Decoder {
    fn error(&self) -> String {
        // SAFETY: the decoder's own NUL-terminated buffer, read under this
        // file's lock before anything rewrites it.
        unsafe { CStr::from_ptr((self.last_error)()) }.to_string_lossy().into_owned()
    }

    fn open(&self, path: &str) -> i32 {
        let path = CString::new(path).expect("no NUL");
        // SAFETY: a NUL-terminated path.
        unsafe { (self.open)(path.as_ptr()) }
    }

    fn open_span(&self, path: &str, offset: i64, length: i64, framed: bool) -> i32 {
        let path = CString::new(path).expect("no NUL");
        // SAFETY: a NUL-terminated path.
        unsafe { (self.open_span)(path.as_ptr(), offset, length, i32::from(framed)) }
    }

    fn info(&self, handle: i32) -> Option<Info> {
        let (mut width, mut height, mut frames, mut num, mut den) = (0, 0, 0, 0, 0);
        // SAFETY: each out-parameter is a local.
        let answered = unsafe { (self.info)(handle, &mut width, &mut height, &mut frames, &mut num, &mut den) };
        (answered == 1).then_some((width, height, frames, (num, den)))
    }

    /// Frame `index` of `handle`, or the sentence its refusal says.
    fn frame(&self, handle: i32, index: i64, bytes: usize) -> Result<Vec<u8>, String> {
        let mut rgba = vec![0u8; bytes];
        // SAFETY: the buffer holds `bytes`.
        match unsafe { (self.frame)(handle, index, rgba.as_mut_ptr(), bytes as i32) } {
            1 => Ok(rgba),
            _ => Err(self.error()),
        }
    }
}

/// The decoders' slots and their one error buffer are each the process's:
/// a test that opens holds this.
fn one_at_a_time() -> MutexGuard<'static, ()> {
    static ONE_AT_A_TIME: Mutex<()> = Mutex::new(());
    ONE_AT_A_TIME.lock().unwrap_or_else(PoisonError::into_inner)
}

const WIDTH: usize = 64;
const HEIGHT: usize = 48;
const FRAMES: usize = 30;

/// Frame `k`'s red and green: red rising and green falling, so each frame
/// is nearest its own and a frame read for the wrong index shows.
fn colour(k: usize) -> [u8; 2] {
    [(k * 8) as u8, (255 - k * 8) as u8]
}

/// Frame `k` whole, `width` × `height`: its colour, and blue rising down the
/// rows — so a picture read upside down, or with its channels swapped, is
/// not the same bytes.
fn picture(width: usize, height: usize, k: usize) -> Vec<u8> {
    let [r, g] = colour(k);
    (0..height).flat_map(|y| [r, g, (20 + y * 200 / height) as u8, 255].repeat(width)).collect()
}

/// What `frame`, read `width` × `height`, shows: the frame whose colour
/// is nearest its middle's, whether it is the right way up, and whether it
/// is opaque.
fn shows(frame: &[u8], width: usize, height: usize) -> (usize, bool, bool) {
    let at = |y: usize| &frame[(y * width + width / 2) * 4..][..4];
    let middle = &at(height / 2)[..2];
    let distance =
        |k: usize| colour(k).iter().zip(middle).map(|(a, b)| (i32::from(*a) - i32::from(*b)).pow(2)).sum::<i32>();
    let nearest = (0..FRAMES).min_by_key(|&k| distance(k)).expect("frames");
    (nearest, u16::from(at(2)[2]) + 100 < u16::from(at(height - 3)[2]), at(2)[3] == 255)
}

/// What a movie is asked to be, as the export's open takes it.
#[derive(Clone, Copy, Debug)]
struct Asked {
    width: usize,
    height: usize,
    fps: (i32, i32),
    /// The sound's rate and channels, or none for a silent movie.
    sound: Option<(i32, i32)>,
    container: i32,
    codec: i32,
    alpha: i32,
    bitrate_bps: i32,
}

/// [`movie`]'s: silent at 24, an MP4 of H.264.
const SILENT: Asked =
    Asked { width: WIDTH, height: HEIGHT, fps: (24, 1), sound: None, container: 0, codec: 0, alpha: 0, bitrate_bps: 0 };

/// A movie of [`FRAMES`] such pictures at 24, written once by this build's
/// export — None where it has none — and the file it is in.
fn movie() -> Option<&'static (PathBuf, Vec<u8>)> {
    static MOVIE: OnceLock<Option<(PathBuf, Vec<u8>)>> = OnceLock::new();
    MOVIE.get_or_init(|| write_movie("silent", SILENT, FRAMES, 0)).as_ref()
}

/// `frames` such pictures as the movie `asked` this build's export writes,
/// and the file — None where it does not write it. Under silence of the
/// sound's rate, if it has one, that runs `sound_past` samples past the
/// last picture.
fn write_movie(name: &str, asked: Asked, frames: usize, sound_past: usize) -> Option<(PathBuf, Vec<u8>)> {
    let extension = if asked.container == 1 { "mov" } else { "mp4" };
    let path = std::env::temp_dir().join(format!("영상-디코드-{}-{name}.{extension}", std::process::id()));
    let utf8 = CString::new(path.to_str().expect("UTF-8")).expect("no NUL");
    let (rate, channels) = asked.sound.unwrap_or((0, 0));
    let Asked { width, height, fps, container, codec, alpha, bitrate_bps, .. } = asked;
    // SAFETY (each): the export's declarations; a whole frame of the size
    // opened, and as many samples of its channels as are passed.
    let opened = unsafe {
        qa_video_export_open(
            utf8.as_ptr(),
            width as i32,
            height as i32,
            fps.0,
            fps.1,
            rate,
            channels,
            container,
            codec,
            alpha,
            bitrate_bps,
        )
    };
    if opened != 1 {
        return None;
    }
    let sound = |samples: usize| {
        let pcm = vec![0i16; samples * channels as usize];
        assert_eq!(unsafe { qa_video_export_write_audio(pcm.as_ptr(), samples as i32) }, 1, "{}", export_error());
    };
    let per_frame = (rate * fps.1 / fps.0) as usize;
    for k in 0..frames {
        let rgba = picture(width, height, k);
        assert_eq!(unsafe { qa_video_export_write_frame(rgba.as_ptr()) }, 1, "frame {k}: {}", export_error());
        if channels > 0 {
            sound(per_frame);
        }
    }
    if channels > 0 && sound_past > 0 {
        sound(sound_past);
    }
    assert_eq!(qa_video_export_finish(), 1, "finish: {}", export_error());
    let bytes = std::fs::read(&path).expect("the movie written");
    Some((path, bytes))
}

fn export_error() -> String {
    let mut out = [0u8; 256];
    // SAFETY: the buffer holds what is passed.
    let length = unsafe { qa_video_export_error(out.as_mut_ptr().cast(), out.len() as i32) };
    String::from_utf8_lossy(&out[..length.max(0) as usize]).into_owned()
}

/// `body` between junk, in a file of its own: the archive a span sits in,
/// and the body's offset in it.
fn between_junk(name: &str, body: &[u8]) -> (PathBuf, i64) {
    let mut bytes: Vec<u8> = (0..4096u32).map(|k| (k * 31 + 5) as u8).collect();
    let offset = bytes.len() as i64;
    bytes.extend_from_slice(body);
    bytes.extend((0..777u32).map(|k| (k * 29 + 3) as u8));
    let path = std::env::temp_dir().join(format!("영상-디코드-{}-{name}.bin", std::process::id()));
    std::fs::write(&path, bytes).expect("write the archive");
    (path, offset)
}

/// Everything `decoder` reads of the movie `open` gives it: its info, then
/// every frame in order, then some out of it — two before the first among
/// them, each of which is the first — then one past the end and one into too
/// small a buffer: each as bytes or the sentence refusing it.
fn read_all(decoder: Decoder, open: impl Fn(Decoder) -> i32) -> (Info, Vec<Result<Vec<u8>, String>>) {
    let handle = open(decoder);
    assert!(handle > 0, "it opens: {}", decoder.error());
    let info = decoder.info(handle).expect("it describes the movie");
    let bytes = (info.0 * info.1 * 4) as usize;
    let count = info.2;
    let order = (0..count).chain([count - 1, 0, count / 2, 3, 4, count / 2, -5, -4, count + 3]);
    let mut frames: Vec<_> = order.map(|index| decoder.frame(handle, index, bytes)).collect();
    frames.push(decoder.frame(handle, 0, bytes - 1));
    (decoder.close)(handle);
    (info, frames)
}

#[test]
fn where_there_is_no_decoder_both_say_so() {
    let _turn = one_at_a_time();
    assert_eq!((rust().supported)(), (c().supported)(), "both, or neither");
    // Which builds read movies is this crate's to say: those with an OS
    // decoder under them.
    let reads = cfg!(any(windows, target_os = "android", target_vendor = "apple"));
    assert_eq!((rust().supported)(), i32::from(reads), "the builds that read movies");
    if (rust().supported)() == 1 {
        return;
    }
    for decoder in [c(), rust()] {
        assert_eq!(decoder.open("movie.mp4"), 0);
        assert_eq!(decoder.error(), "no video decoder in this build");
    }
}

#[test]
fn a_movie_on_disk_reads_alike() {
    let _turn = one_at_a_time();
    let Some((path, _)) = movie() else { return };
    let path = path.to_str().expect("UTF-8");
    let theirs = read_all(c(), |decoder| decoder.open(path));
    let ours = read_all(rust(), |decoder| decoder.open(path));
    assert_eq!(ours.0, theirs.0, "the same shape, count and rate");
    assert_eq!(ours.0, (WIDTH as i32, HEIGHT as i32, FRAMES as i64, (24, 1)), "LIVENESS: the movie written");
    for (at, (ours, theirs)) in ours.1.iter().zip(&theirs.1).enumerate() {
        let sizes = (ours.as_ref().map(Vec::len), theirs.as_ref().map(Vec::len));
        assert!(ours == theirs, "read {at}: {:?} against the C's {:?}", sizes.0, sizes.1);
    }
    let refusals: Vec<_> = ours.1.iter().filter_map(|read| read.as_ref().err()).collect();
    assert_eq!(refusals, ["past the end of the stream", "frame buffer too small"], "LIVENESS: both refusals asked");
}

// Every movie the export writes reads back through this crate's reader as
// it was asked: its picture made even, its rate, every frame written, and
// each frame the picture for its index, read in order and out of it. Its
// bytes are the OS encoder's and are not held (유저
// connection-round-checklist-Q14, 2026-11-07: what the OS decides is not
// frozen) — the shapes are the ones the export's C comparison writes, each
// where this build writes its pair: the fixtures' movie, an odd one the pad
// makes even, a film the hardware takes, the hardware law's two sides, an
// exact NTSC fraction with mono sound at another rate and a bitrate named,
// one named past the ceiling, and where Apple writes them, H.264 in a MOV
// and ProRes — 4444 keeping a picture's alpha. Each file's path is Korean.
// ⚠️Not HEVC: whether a machine reads it back is its own — Windows reads
// HEVC only through the Store's extension, which a machine that writes it
// may lack (this one: 「no RGB conversion for this codec」, 2026-11-07).
#[test]
fn what_the_export_writes_reads_back_as_it_was_asked() {
    let _turn = one_at_a_time();
    let sounding = Asked { sound: Some((48_000, 2)), ..SILENT };
    let ntsc =
        Asked { width: 96, height: 64, fps: (24000, 1001), sound: Some((44_100, 1)), bitrate_bps: 3_000_000, ..SILENT };
    for (name, asked, frames) in [
        ("silent", SILENT, FRAMES),
        ("fixture", sounding, 24),
        ("odd-silent", Asked { width: 63, height: 47, ..SILENT }, 6),
        ("full-hd", Asked { width: 1920, height: 1080, ..sounding }, 6),
        ("past-the-law", Asked { width: 49, height: 64, ..SILENT }, 6),
        ("the-failed-side", Asked { width: 48, height: 64, ..SILENT }, 6),
        ("ntsc-mono", ntsc, 12),
        ("past-the-ceiling", Asked { width: 64, height: 64, bitrate_bps: 80_000_000, ..sounding }, 6),
        ("mov", Asked { container: 1, ..sounding }, 6),
        ("prores-422", Asked { container: 1, codec: 4, ..sounding }, 6),
        ("prores-4444-alpha", Asked { container: 1, codec: 6, alpha: 1, ..SILENT }, 6),
    ] {
        if qa_video_export_probe(asked.container, asked.codec) == 0 {
            continue;
        }
        let (path, _) = write_movie(&format!("asked-{name}"), asked, frames, 0)
            .unwrap_or_else(|| panic!("{name}: what the export says it writes opens: {}", export_error()));
        let (info, read) = read_all(rust(), |decoder| decoder.open(path.to_str().expect("UTF-8")));
        let even = |side: usize| (side + (side & 1)) as i32;
        let shape = (even(asked.width), even(asked.height), frames as i64);
        assert_eq!((info.0, info.1, info.2), shape, "{name}: as asked");
        // The rate as the reader hands it: Media Foundation's, in the 100 ns
        // it keeps a frame's time in (24000/1001 came back 10000000/417083,
        // 2026-11-07) — so a frame lasts as asked, to that tick.
        let lasts = |(num, den): (i32, i32)| 1e7 * f64::from(den) / f64::from(num);
        assert!((lasts(info.3) - lasts(asked.fps)).abs() <= 1.0, "{name}: a frame lasts as asked: {:?}", info.3);
        // -5 and then -4 are each asked as the first: an index before it is
        // clamped BEFORE 「already positioned」 is asked, or -4 would read as
        // the frame after -5's.
        let order = (0..frames).chain([frames - 1, 0, frames / 2, 3, 4, frames / 2, 0, 0]);
        for (index, frame) in order.zip(&read) {
            let frame = frame.as_ref().unwrap_or_else(|why| panic!("{name}: frame {index}: {why}"));
            let shown = shows(frame, info.0 as usize, info.1 as usize);
            assert_eq!(shown, (index, true, true), "{name}: frame {index} — its picture, the right way up, opaque");
        }
        std::fs::remove_file(path).ok();
    }
}

#[test]
fn a_span_reads_as_the_movie_it_holds_plain_or_framed() {
    let _turn = one_at_a_time();
    let Some((path, bytes)) = movie() else { return };
    let whole = read_all(rust(), |decoder| decoder.open(path.to_str().expect("UTF-8")));
    let (plain, offset) = between_junk("plain", bytes);
    let framed_blob = oracle::framed(bytes, 4096);
    let (framed, framed_offset) = between_junk("framed", &framed_blob);
    for (archive, offset, length, is_framed) in
        [(&plain, offset, bytes.len(), false), (&framed, framed_offset, framed_blob.len(), true)]
    {
        let archive = archive.to_str().expect("UTF-8");
        let open = |decoder: Decoder| decoder.open_span(archive, offset, length as i64, is_framed);
        let (ours, theirs) = (read_all(rust(), open), read_all(c(), open));
        assert!(ours == theirs, "framed {is_framed}: the span reads as the C reads it");
        assert!(ours == whole, "framed {is_framed}: and as the file on disk reads");
    }
    std::fs::remove_file(plain).ok();
    std::fs::remove_file(framed).ok();
}

#[test]
fn a_failure_says_the_same_sentence() {
    let _turn = one_at_a_time();
    let Some((path, bytes)) = movie() else { return };
    let path = path.to_str().expect("UTF-8");
    let missing = format!("{path}.not-there");
    let length = bytes.len() as i64;
    // A span that is not one is refused by this crate before the OS sees a
    // byte (`media::span`), in its own words — held where measured. What
    // the OS refuses says the sentence of the call that refused, and which
    // call refuses is the OS's: held only to say why (유저
    // connection-round-checklist-Q14, 2026-11-07: what the OS decides is
    // not frozen). ⚠️Measured on Windows (2026-11-07); the Mac's waits for
    // its job to read alike with the C's first.
    let not_a_span = cfg!(windows).then_some("that span does not hold a readable movie");
    let tries: [(&str, Option<&str>, Box<dyn Fn(Decoder) -> i32>); 4] = [
        ("no file", None, Box::new(|decoder: Decoder| decoder.open(&missing))),
        (
            "a plain movie said to be framed",
            not_a_span,
            Box::new(|decoder: Decoder| decoder.open_span(path, 0, length, true)),
        ),
        ("a span past the file", not_a_span, Box::new(|decoder: Decoder| decoder.open_span(path, 10, length, false))),
        ("a span of the movie's middle", None, Box::new(|decoder: Decoder| decoder.open_span(path, 1000, 2000, false))),
    ];
    for (what, says, open) in &tries {
        let answers = [c(), rust()].map(|decoder| {
            let handle = open(decoder);
            (decoder.close)(handle);
            (handle > 0, decoder.error())
        });
        assert_eq!(answers[1], answers[0], "{what}: as the C answers");
        assert!(!answers[1].0 && !answers[1].1.is_empty(), "LIVENESS — {what} is refused, and says why: {answers:?}");
        if let Some(says) = says {
            assert_eq!(answers[1].1, *says, "{what}");
        }
    }
    // And an open that succeeds says nothing: the last failure is not left
    // for the next caller to read as its own.
    for decoder in [c(), rust()] {
        let handle = decoder.open(path);
        assert!(handle > 0 && decoder.error().is_empty(), "a good open clears the failure: {:?}", decoder.error());
        (decoder.close)(handle);
    }
}

#[test]
fn a_movie_is_as_long_as_its_pictures_not_its_sound() {
    // 🚨The presentation is as long as its LONGEST track: counted by it, a
    // sound that runs past the pictures is frames with no picture in them
    // (유저 2026-08-31 「73프레임째의 빈 화면」). The C's Windows backend
    // counts by the video's own samples (검증 2026-10-23,
    // windows-counts-a-movie-by-its-longest-track). Twelve pictures under a
    // sound a quarter second longer — six frames past, well over the half
    // frame the count rounds away — and the repo's own movie, whose sound
    // runs past its twelve by less.
    let _turn = one_at_a_time();
    let Some((longer, _)) = write_movie("sound-past", Asked { sound: Some((48_000, 2)), ..SILENT }, 12, 12_000) else {
        return;
    };
    // This checkout's, read when the test runs (gpu_engine's
    // kernels/shared/one_checkout.rs).
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").expect("cargo runs the test");
    let fixture = format!("{crate_dir}/../../../../../test/fixtures/tone_with_video.mp4");
    for movie in [longer.to_str().expect("UTF-8"), &fixture] {
        let answers = [c(), rust()].map(|decoder| {
            let handle = decoder.open(movie);
            let info = decoder.info(handle);
            (decoder.close)(handle);
            info
        });
        assert_eq!(answers[1], answers[0], "{movie}: as the C counts it");
        assert_eq!(answers[0].map(|info| info.2), Some(12), "{movie}: LIVENESS — twelve pictures");
    }
    std::fs::remove_file(longer).ok();
}

#[test]
fn eight_movies_open_at_once_and_a_ninth_is_refused() {
    let _turn = one_at_a_time();
    let Some((path, _)) = movie() else { return };
    let path = path.to_str().expect("UTF-8");
    for decoder in [c(), rust()] {
        let handles: Vec<i32> = (0..8).map(|_| decoder.open(path)).collect();
        assert_eq!(handles, (1..=8).collect::<Vec<_>>(), "handles count from one");
        assert_eq!(decoder.open(path), 0, "a ninth");
        assert_eq!(decoder.error(), "too many movies are open at once");
        (decoder.close)(3);
        assert_eq!(decoder.open(path), 3, "the one let go is the first free again");
        assert!(decoder.info(5).is_some(), "the others are untouched");
        (decoder.close_all)();
        assert!(decoder.info(5).is_none(), "and close_all closes them all");
    }
}
