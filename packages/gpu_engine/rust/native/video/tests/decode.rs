//! The Rust decoder against the engine's C (native/oracle): the same movie
//! opened by both, through the exports each has — its shape, every frame's
//! bytes in order and out of it, a span of a file plain and framed, the
//! slots, and the sentence each failure says. Where this build has no
//! decoder, that the two say so alike.
//!
//! ⚠️A process of its own, apart from the crate's tests: the movie is
//! written through the export, which keeps one job for the whole process,
//! and the crate's export tests hold that job for themselves.
//!
//! ⏳On Apple each is IGNORED BY NAME, not skipped: the engine's C reads a
//! movie there and this crate's reader is 공통's, still to come
//! (`decode/mod.rs`'s `os`). The line comes off with `apple.rs`.

use std::ffi::{CStr, CString, c_char};
use std::path::PathBuf;
use std::sync::{Mutex, MutexGuard, OnceLock, PoisonError};

use video::decode::{
    qa_video_decode_close, qa_video_decode_close_all, qa_video_decode_frame, qa_video_decode_info,
    qa_video_decode_last_error, qa_video_decode_open, qa_video_decode_open_span, qa_video_decode_supported,
};
use video::export::{qa_video_export_error, qa_video_export_finish, qa_video_export_open, qa_video_export_write_frame};

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

/// Frame `k`'s colour: red rising and green falling, so each frame is
/// nearest its own and a frame read for the wrong index shows.
fn colour(k: usize) -> [u8; 3] {
    [(k * 8) as u8, (255 - k * 8) as u8, 128]
}

/// A movie of [`FRAMES`] flat frames at 24, written once by this build's
/// export — None where it has none — and the file it is in.
fn movie() -> Option<&'static (PathBuf, Vec<u8>)> {
    static MOVIE: OnceLock<Option<(PathBuf, Vec<u8>)>> = OnceLock::new();
    MOVIE
        .get_or_init(|| {
            let path = std::env::temp_dir().join(format!("영상-디코드-{}.mp4", std::process::id()));
            let utf8 = CString::new(path.to_str().expect("UTF-8")).expect("no NUL");
            // SAFETY (each): the export's declarations; a whole frame of the
            // size opened; MP4 · H.264, silent.
            let opened =
                unsafe { qa_video_export_open(utf8.as_ptr(), WIDTH as i32, HEIGHT as i32, 24, 1, 0, 0, 0, 0, 0, 0) };
            if opened != 1 {
                return None;
            }
            for k in 0..FRAMES {
                let [r, g, b] = colour(k);
                let rgba: Vec<u8> = [r, g, b, 255].repeat(WIDTH * HEIGHT);
                assert_eq!(unsafe { qa_video_export_write_frame(rgba.as_ptr()) }, 1, "frame {k}: {}", export_error());
            }
            assert_eq!(qa_video_export_finish(), 1, "finish: {}", export_error());
            let bytes = std::fs::read(&path).expect("the movie written");
            Some((path, bytes))
        })
        .as_ref()
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
/// every frame in order, then some out of it, then one past the end and one
/// into too small a buffer — each as bytes or the sentence refusing it.
fn read_all(decoder: Decoder, open: impl Fn(Decoder) -> i32) -> (Info, Vec<Result<Vec<u8>, String>>) {
    let handle = open(decoder);
    assert!(handle > 0, "it opens: {}", decoder.error());
    let info = decoder.info(handle).expect("it describes the movie");
    let bytes = (info.0 * info.1 * 4) as usize;
    let count = info.2;
    let order = (0..count).chain([count - 1, 0, count / 2, 3, 4, count / 2, count + 3]);
    let mut frames: Vec<_> = order.map(|index| decoder.frame(handle, index, bytes)).collect();
    frames.push(decoder.frame(handle, 0, bytes - 1));
    (decoder.close)(handle);
    (info, frames)
}

#[test]
#[cfg_attr(target_vendor = "apple", ignore = "Apple's reader is 공통's, still to come (connection-round-checklist)")]
fn where_there_is_no_decoder_both_say_so() {
    let _turn = one_at_a_time();
    assert_eq!((rust().supported)(), (c().supported)(), "both, or neither");
    if (c().supported)() == 1 {
        return;
    }
    for decoder in [c(), rust()] {
        assert_eq!(decoder.open("movie.mp4"), 0);
        assert_eq!(decoder.error(), "no video decoder in this build");
    }
}

#[test]
#[cfg_attr(target_vendor = "apple", ignore = "Apple's reader is 공통's, still to come (connection-round-checklist)")]
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

#[test]
#[cfg_attr(target_vendor = "apple", ignore = "Apple's reader is 공통's, still to come (connection-round-checklist)")]
fn each_frame_is_the_picture_for_its_index() {
    let _turn = one_at_a_time();
    let Some((path, _)) = movie() else { return };
    let (_, frames) = read_all(rust(), |decoder| decoder.open(path.to_str().expect("UTF-8")));
    let order = (0..FRAMES).chain([FRAMES - 1, 0, FRAMES / 2, 3, 4, FRAMES / 2]);
    for (index, frame) in order.zip(&frames) {
        let frame = frame.as_ref().expect("a frame");
        let middle = &frame[(HEIGHT / 2 * WIDTH + WIDTH / 2) * 4..][..3];
        let distance =
            |k: usize| colour(k).iter().zip(middle).map(|(a, b)| (i32::from(*a) - i32::from(*b)).pow(2)).sum::<i32>();
        let nearest = (0..FRAMES).min_by_key(|&k| distance(k)).expect("frames");
        assert_eq!(nearest, index, "frame {index} shows {middle:?}");
    }
}

#[test]
#[cfg_attr(target_vendor = "apple", ignore = "Apple's reader is 공통's, still to come (connection-round-checklist)")]
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
#[cfg_attr(target_vendor = "apple", ignore = "Apple's reader is 공통's, still to come (connection-round-checklist)")]
fn a_failure_says_the_same_sentence() {
    let _turn = one_at_a_time();
    let Some((path, bytes)) = movie() else { return };
    let path = path.to_str().expect("UTF-8");
    let missing = format!("{path}.not-there");
    let length = bytes.len() as i64;
    let tries: [(&str, Box<dyn Fn(Decoder) -> i32>); 4] = [
        ("no file", Box::new(|decoder: Decoder| decoder.open(&missing))),
        ("a plain movie said to be framed", Box::new(|decoder: Decoder| decoder.open_span(path, 0, length, true))),
        ("a span past the file", Box::new(|decoder: Decoder| decoder.open_span(path, 10, length, false))),
        ("a span of the movie's middle", Box::new(|decoder: Decoder| decoder.open_span(path, 1000, 2000, false))),
    ];
    for (what, open) in &tries {
        let answers = [c(), rust()].map(|decoder| {
            let handle = open(decoder);
            (decoder.close)(handle);
            (handle > 0, decoder.error())
        });
        assert_eq!(answers[1], answers[0], "{what}: as the C answers");
        assert!(!answers[0].0 && !answers[0].1.is_empty(), "LIVENESS — {what} is refused, and says why: {answers:?}");
    }
}

#[test]
#[cfg_attr(target_vendor = "apple", ignore = "Apple's reader is 공통's, still to come (connection-round-checklist)")]
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
