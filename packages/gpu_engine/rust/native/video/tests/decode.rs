//! The decoder through its exports: a movie the export wrote, its shape
//! and every frame in order and out of it, a span of a file plain and
//! framed, the slots, and why each failure is refused. Where this build has
//! no decoder, that it says so. And every movie the export writes, read back
//! as it was asked.
//!
//! ↩️It was held to the engine's C (native/oracle) — the same movie opened by
//! both, every frame's bytes and every sentence alike — until the connection
//! round deleted the C's decoder (connection-round-checklist H, 2026-11-08):
//! what the OS decoder makes is not frozen, only what this code decides
//! (유저 connection-round-checklist-Q14, 2026-11-07).
//!
//! ⚠️A process of its own, apart from the crate's tests: the movie is
//! written through the export, which keeps one job for the whole process,
//! and the crate's export tests hold that job for themselves.

use std::ffi::{CStr, CString};
use std::sync::{Mutex, MutexGuard, OnceLock, PoisonError};

use oracle::TempFile;
use video::decode::{
    qa_video_decode_close, qa_video_decode_close_all, qa_video_decode_colours, qa_video_decode_frame,
    qa_video_decode_info, qa_video_decode_last_error, qa_video_decode_open, qa_video_decode_open_nv12,
    qa_video_decode_open_span, qa_video_decode_supported,
};
use video::colour;
use video::export::{
    qa_video_export_abort, qa_video_export_error, qa_video_export_finish, qa_video_export_nv12_shape,
    qa_video_export_open, qa_video_export_probe, qa_video_export_write_audio, qa_video_export_write_frame,
    qa_video_export_write_nv12,
};

/// What `info` answers: the shown size, the frame count and the rate.
type Info = (i32, i32, i64, (i32, i32));

fn error() -> String {
    // SAFETY: the decoder's own NUL-terminated buffer, read under this
    // file's lock before anything rewrites it.
    unsafe { CStr::from_ptr(qa_video_decode_last_error()) }.to_string_lossy().into_owned()
}

fn open(path: &str) -> i32 {
    let path = CString::new(path).expect("no NUL");
    // SAFETY: a NUL-terminated path.
    unsafe { qa_video_decode_open(path.as_ptr()) }
}

fn open_span(path: &str, offset: i64, length: i64, framed: bool) -> i32 {
    let path = CString::new(path).expect("no NUL");
    // SAFETY: a NUL-terminated path.
    unsafe { qa_video_decode_open_span(path.as_ptr(), offset, length, i32::from(framed)) }
}

fn info(handle: i32) -> Option<Info> {
    let (mut width, mut height, mut frames, mut num, mut den) = (0, 0, 0, 0, 0);
    // SAFETY: each out-parameter is a local.
    let answered = unsafe { qa_video_decode_info(handle, &mut width, &mut height, &mut frames, &mut num, &mut den) };
    (answered == 1).then_some((width, height, frames, (num, den)))
}

/// Frame `index` of `handle`, or the sentence its refusal says.
fn frame(handle: i32, index: i64, bytes: usize) -> Result<Vec<u8>, String> {
    let mut rgba = vec![0u8; bytes];
    // SAFETY: the buffer holds `bytes`.
    match unsafe { qa_video_decode_frame(handle, index, rgba.as_mut_ptr(), bytes as i32) } {
        1 => Ok(rgba),
        _ => Err(error()),
    }
}

/// The decoder's slots and its one error buffer are the process's:
/// a test that opens holds this.
fn one_at_a_time() -> MutexGuard<'static, ()> {
    static ONE_AT_A_TIME: Mutex<()> = Mutex::new(());
    ONE_AT_A_TIME.lock().unwrap_or_else(PoisonError::into_inner)
}

const WIDTH: usize = 64;
const HEIGHT: usize = 48;
const FRAMES: usize = 30;
/// Frame `k`'s luma: rising frame by frame, so each frame is nearest its
/// own and a frame read for the wrong index shows.
fn luma(k: usize) -> u8 {
    (40 + k * 6) as u8
}

/// The Cb of chroma row `row` of a frame `height` tall: rising down the
/// rows — blue, read back — so a picture read upside down, or with its
/// channels swapped, is not the same bytes.
fn cb_at(row: usize, height: usize) -> u8 {
    (70 + row * 2 * 120 / height) as u8
}

/// Frame `k` whole as NV12, `width` × `height` (even), rows `stride` apart:
/// its luma, Cb rising down the rows and Cr neutral — YCbCr made by hand,
/// as an H.26x writer is handed it.
fn picture(width: usize, height: usize, stride: usize, k: usize) -> Vec<u8> {
    let mut nv12 = vec![0u8; stride * height * 3 / 2];
    let (y, chroma) = nv12.split_at_mut(stride * height);
    for row in y.chunks_exact_mut(stride) {
        row[..width].fill(luma(k));
    }
    for (row, bytes) in chroma.chunks_exact_mut(stride).enumerate() {
        for pair in bytes[..width].chunks_exact_mut(2) {
            pair.copy_from_slice(&[cb_at(row, height), 128]);
        }
    }
    nv12
}

/// What the law's own reader ([`colour::rgba_of`], BT.601's) makes of
/// frame `k` on chroma row `row`, the frame `height` tall.
fn read_as(k: usize, row: usize, height: usize) -> [u8; 3] {
    let frame = [luma(k), luma(k), luma(k), luma(k), cb_at(row, height), 128];
    let mut rgba = [0u8; 2 * 2 * 4];
    assert!(colour::rgba_of(&frame, (2, 2), colour::BT601[0], &mut rgba), "a 2×2 frame");
    [rgba[0], rgba[1], rgba[2]]
}

/// What `frame`, read `width` × `height`, shows: the frame whose colour is
/// nearest its middle's, whether it is the right way up, and whether it is
/// opaque.
fn shows(frame: &[u8], width: usize, height: usize) -> (usize, bool, bool) {
    let at = |y: usize| &frame[(y * width + width / 2) * 4..][..4];
    let middle = &at(height / 2)[..3];
    let distance = |k: usize| {
        let was = read_as(k, height / 2 / 2, height);
        was.iter().zip(middle).map(|(a, b)| (i32::from(*a) - i32::from(*b)).pow(2)).sum::<i32>()
    };
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
/// export — None where it has none: its bytes. The file the export wrote
/// them into goes as soon as they are read; a test that opens the movie by
/// its path lays one of its own ([`laid_movie`]).
///
/// ↩️Till 2026-11-16 that file stayed for every test to share, and nothing
/// deleted it: Temp kept one of every run (card
/// a-cargo-decode-test-leaves-its-movie-in-temp).
fn movie() -> Option<&'static [u8]> {
    static MOVIE: OnceLock<Option<Vec<u8>>> = OnceLock::new();
    MOVIE
        .get_or_init(|| write_movie("silent", SILENT, FRAMES, 0, Feed::Nv12, picture).map(|(_written, bytes)| bytes))
        .as_deref()
}

/// [`movie`] in a file of the test's own, and its bytes.
fn laid_movie() -> Option<(TempFile, &'static [u8])> {
    movie().map(|bytes| (TempFile::new("silent.mp4", bytes), bytes))
}

/// How a frame is handed to the export: as the NV12 an H.26x writer takes
/// — the GPU engine's of an export's frames, a decoder's of a piece's — or
/// as the RGBA ProRes takes, its OS converting it. ↩️H.26x took RGBA too,
/// made NV12 in the app's law on the CPU, till 2026-11-15.
#[derive(Clone, Copy, Debug, PartialEq)]
enum Feed {
    Rgba,
    Nv12,
}

/// How the export takes `codec`'s frames: H.26x as NV12, ProRes as RGBA.
fn feed_of(codec: i32) -> Feed {
    if codec == 0 || codec == 1 { Feed::Nv12 } else { Feed::Rgba }
}

/// Frame `k` that `paint` makes (`width`, `height`, `stride`, frame) of a
/// picture `width` × `height`, handed to the open job as `feed` says: as
/// NV12 in the writer's frame, on rows longer than it as the engine's
/// readback rows are — or as the RGBA the law's own reader makes of it
/// ([`colour::rgba_of`], BT.601's). What the export answers.
fn hand(feed: Feed, paint: &impl Fn(usize, usize, usize, usize) -> Vec<u8>, width: usize, height: usize, k: usize) -> i32 {
    if feed == Feed::Rgba {
        let (even_width, even_height) = (width + (width & 1), height + (height & 1));
        let nv12 = paint(even_width, even_height, even_width, k);
        let mut rgba = vec![0u8; width * height * 4];
        assert!(colour::rgba_of(&nv12, (width, height), colour::BT601[0], &mut rgba), "its own frame");
        // SAFETY: a whole frame of the size opened.
        return unsafe { qa_video_export_write_frame(rgba.as_ptr()) };
    }
    let mut shape = [0i32; 2];
    // SAFETY: room for the two it says.
    assert_eq!(unsafe { qa_video_export_nv12_shape(shape.as_mut_ptr()) }, 1, "the writer takes NV12");
    let (frame_width, frame_height) = (shape[0] as usize, shape[1] as usize);
    let stride = frame_width + 64;
    let nv12 = paint(frame_width, frame_height, stride, k);
    // SAFETY: the frame it says, rows `stride` apart.
    unsafe { qa_video_export_write_nv12(nv12.as_ptr(), stride as i64) }
}

/// `frames` pictures `paint` makes (`width`, `height`, `stride`, frame) as the movie
/// `asked` this build's export writes, each handed as `feed` says, and the
/// file, gone when it drops — None where it does not write it. Under
/// silence of the sound's rate, if it has one, that runs `sound_past`
/// samples past the last picture.
fn write_movie(
    name: &str,
    asked: Asked,
    frames: usize,
    sound_past: usize,
    feed: Feed,
    paint: impl Fn(usize, usize, usize, usize) -> Vec<u8>,
) -> Option<(TempFile, Vec<u8>)> {
    let extension = if asked.container == 1 { "mov" } else { "mp4" };
    let path = TempFile::at(&format!("{name}.{extension}"));
    let utf8 = CString::new(path.path().to_str().expect("UTF-8")).expect("no NUL");
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
            std::ptr::null(),
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
        assert_eq!(hand(feed, &paint, width, height, k), 1, "frame {k}: {}", export_error());
        if channels > 0 {
            sound(per_frame);
        }
    }
    if channels > 0 && sound_past > 0 {
        sound(sound_past);
    }
    assert_eq!(qa_video_export_finish(), 1, "finish: {}", export_error());
    let bytes = std::fs::read(path.path()).expect("the movie written");
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
fn between_junk(name: &str, body: &[u8]) -> (TempFile, i64) {
    let mut bytes: Vec<u8> = (0..4096u32).map(|k| (k * 31 + 5) as u8).collect();
    let offset = bytes.len() as i64;
    bytes.extend_from_slice(body);
    bytes.extend((0..777u32).map(|k| (k * 29 + 3) as u8));
    (TempFile::new(&format!("{name}.bin"), &bytes), offset)
}

/// Everything the decoder reads of the movie `open` gives it: its info, then
/// every frame in order, then some out of it — two before the first among
/// them, each of which is the first — then one past the end and one into too
/// small a buffer: each as bytes or the sentence refusing it.
fn read_all(open: impl Fn() -> i32) -> (Info, Vec<Result<Vec<u8>, String>>) {
    let handle = open();
    assert!(handle > 0, "it opens: {}", error());
    let info = info(handle).expect("it describes the movie");
    let bytes = (info.0 * info.1 * 4) as usize;
    let count = info.2;
    let order = (0..count).chain([count - 1, 0, count / 2, 3, 4, count / 2, -5, -4, count + 3]);
    let mut frames: Vec<_> = order.map(|index| frame(handle, index, bytes)).collect();
    frames.push(frame(handle, 0, bytes - 1));
    qa_video_decode_close(handle);
    (info, frames)
}

// Which builds read movies is this crate's to say: those with an OS decoder
// under them. One without says so of every open. ↩️It was also the C's
// answer until the connection round deleted the C (H, 2026-11-08).
#[test]
fn where_there_is_no_decoder_it_says_so() {
    let _turn = one_at_a_time();
    let reads = cfg!(any(windows, target_os = "android", target_vendor = "apple"));
    assert_eq!(qa_video_decode_supported(), i32::from(reads), "the builds that read movies");
    if qa_video_decode_supported() == 1 {
        return;
    }
    assert_eq!(open("movie.mp4"), 0);
    assert_eq!(error(), "no video decoder in this build");
}

// The movie on disk is the shape it was written and refuses only a frame
// past its end and a buffer too small for one, in this code's words — its
// every frame the picture for its index is the readback's below. ↩️Its
// every read was the C's bytes too until the connection round deleted the C
// (H, 2026-11-08).
#[test]
fn a_movie_on_disk_refuses_only_past_its_end_and_too_small_a_buffer() {
    let _turn = one_at_a_time();
    let Some((path, _)) = laid_movie() else { return };
    let path = path.path().to_str().expect("UTF-8");
    let (info, read) = read_all(|| open(path));
    assert_eq!(info, (WIDTH as i32, HEIGHT as i32, FRAMES as i64, (24, 1)), "LIVENESS: the movie written");
    let refusals: Vec<_> = read.iter().filter_map(|read| read.as_ref().err()).collect();
    assert_eq!(refusals, ["past the end of the stream", "frame buffer too small"], "LIVENESS: both refusals asked");
}

// 🚨The movie the tests share is held as its bytes: the file the export
// wrote them into goes once they are read, and one a test lays goes with
// the test ([`TempFile`]). ↩️Till 2026-11-16 Temp kept one of every run
// (card a-cargo-decode-test-leaves-its-movie-in-temp).
#[test]
fn the_movie_the_tests_share_leaves_no_file_in_temp() {
    let _turn = one_at_a_time();
    let Some(bytes) = movie() else { return };
    assert!(!bytes.is_empty(), "LIVENESS: the movie written");
    assert_eq!(TempFile::left("silent.mp4"), Vec::<std::path::PathBuf>::new(), "none of the shared movie's");
}

// Every movie the export writes reads back through this crate's reader as
// it was asked: its picture made even, its rate, every frame written, and
// each frame the picture for its index, read in order and out of it —
// handed as RGBA, and an H.26x's as the engine's NV12 too. Its
// bytes are the OS encoder's and are not held (유저
// connection-round-checklist-Q14, 2026-11-07: what the OS decides is not
// frozen) — the shapes are the ones the export's C comparison wrote (↩️until
// the connection round deleted the C, H 2026-11-08), each where this build
// writes its pair: the fixtures' movie, an odd one the pad makes even, a
// film the hardware takes, the hardware law's two sides, an exact NTSC
// fraction with mono sound at another rate and a bitrate named, one named
// past the ceiling, and where Apple writes them, H.264 in a MOV and ProRes —
// 4444 keeping a picture's alpha. Each file's path is Korean.
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
        let feed = feed_of(asked.codec);
        let name = &format!("{name} as {feed:?}");
        let (path, _) = write_movie(&format!("asked-{}", name.replace(' ', "-")), asked, frames, 0, feed, picture)
            .unwrap_or_else(|| panic!("{name}: what the export says it writes opens: {}", export_error()));
        let (info, read) = read_all(|| open(path.path().to_str().expect("UTF-8")));
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
    }
}

/// NV12 of `width` × `height` (even), one colour — its Y, Cb and Cr — all
/// over, rows `stride` apart.
fn flat_nv12(width: usize, height: usize, stride: usize, [y, cb, cr]: [u8; 3]) -> Vec<u8> {
    let mut nv12 = vec![0u8; stride * height * 3 / 2];
    let (luma, chroma) = nv12.split_at_mut(stride * height);
    for row in luma.chunks_exact_mut(stride) {
        row[..width].fill(y);
    }
    for row in chroma.chunks_exact_mut(stride) {
        for pair in row[..width].chunks_exact_mut(2) {
            pair.copy_from_slice(&[cb, cr]);
        }
    }
    nv12
}

// 🚨A flat colour comes back through the reader within 4 a channel, HD and
// SD — the names the writer gives its pictures agreeing with what the
// reader makes of them. Each colour is handed as the law's YCbCr of it,
// worked by hand (BT.601 studio, as `kernels/export/tests.rs` works its
// own). ⚠️Measured on Windows alone (2026-11-14, `export/windows.rs` says
// what each name kept off — 13 and more). ↩️Each was also handed as RGBA,
// the law made on the CPU, till that went (2026-11-15).
// ↩️Within 3 till 2026-11-18, which was the Surface's hardware encoder. The
// OS's own software H.264 — what a machine with none takes, CI's Windows
// ARM64 runner among them (board windows-arm64-video-decode-tests-red) —
// hands [30, 30, 200] back as [31, 29, 196], there and on the Surface made
// to take it: its quantizing, not the names.
#[cfg(windows)]
#[test]
fn a_flat_colour_comes_back_within_four() {
    let _turn = one_at_a_time();
    let colours: [([u8; 3], [u8; 3]); 4] = [
        ([110, 60, 200], [94, 182, 140]),
        ([30, 200, 30], [127, 79, 66]),
        ([30, 30, 200], [58, 202, 116]),
        ([128, 128, 128], [126, 128, 128]),
    ];
    for (width, height) in [(1920, 1080), (256, 144)] {
        for (rgb, ycc) in colours {
            let asked = Asked { width, height, ..SILENT };
            let flat = |width: usize, height: usize, stride: usize, _| flat_nv12(width, height, stride, ycc);
            let name = format!("flat-{width}-{}", rgb[0]);
            let (path, _) = write_movie(&name, asked, 3, 0, Feed::Nv12, flat).expect("it writes an MP4 of H.264");
            let (info, read) = read_all(|| open(path.path().to_str().expect("UTF-8")));
            let frame = read[1].as_ref().expect("the second frame");
            let middle = &frame[((info.1 as usize / 2) * info.0 as usize + info.0 as usize / 2) * 4..][..3];
            let off = middle.iter().zip(rgb).map(|(back, was)| back.abs_diff(was)).max();
            assert!(off <= Some(4), "{width}×{height}: {rgb:?} came back {middle:?}");
        }
    }
}

// An NV12 frame the open writer cannot hold is refused, and the error says
// why — every writer that takes NV12 reads what it is handed in one place
// (`export/nv12.rs`, `handed`).
#[cfg(windows)]
#[test]
fn an_nv12_frame_of_another_shape_is_refused_and_said() {
    let _turn = one_at_a_time();
    let path = TempFile::at("shape.mp4");
    let utf8 = CString::new(path.path().to_str().expect("UTF-8")).expect("no NUL");
    // SAFETY (each): the export's declarations; room for the two the shape
    // says, and a frame of the stride handed.
    let opened = unsafe { qa_video_export_open(utf8.as_ptr(), 64, 48, 24, 1, 0, 0, 0, 0, 0, 0, std::ptr::null()) };
    assert_eq!(opened, 1, "{}", export_error());
    let mut shape = [0i32; 2];
    assert_eq!(unsafe { qa_video_export_nv12_shape(shape.as_mut_ptr()) }, 1, "the writer takes NV12");
    let short = shape[0] as usize - 2;
    let nv12 = vec![0u8; short * shape[1] as usize * 3 / 2];
    let written = unsafe { qa_video_export_write_nv12(nv12.as_ptr(), short as i64) };
    let said = export_error();
    qa_video_export_abort();
    assert_eq!(written, 0, "a stride short of the width is refused");
    assert!(said.contains("an NV12 frame of another shape"), "{said}");
}

// A span reads as the file on disk reads, plain and framed as the archive
// frames it (`oracle::framed`). ↩️And as the C read it, until the connection
// round deleted the C (H, 2026-11-08).
#[test]
fn a_span_reads_as_the_movie_it_holds_plain_or_framed() {
    let _turn = one_at_a_time();
    let Some((path, bytes)) = laid_movie() else { return };
    let whole = read_all(|| open(path.path().to_str().expect("UTF-8")));
    let (plain, offset) = between_junk("plain", bytes);
    let framed_blob = oracle::framed(bytes, 4096);
    let (framed, framed_offset) = between_junk("framed", &framed_blob);
    for (archive, offset, length, is_framed) in
        [(&plain, offset, bytes.len(), false), (&framed, framed_offset, framed_blob.len(), true)]
    {
        let archive = archive.path().to_str().expect("UTF-8");
        let ours = read_all(|| open_span(archive, offset, length as i64, is_framed));
        assert!(ours == whole, "framed {is_framed}: the span reads as the file on disk reads");
    }
}

#[test]
fn a_failure_says_why() {
    let _turn = one_at_a_time();
    let Some((path, bytes)) = laid_movie() else { return };
    let path = path.path().to_str().expect("UTF-8");
    let missing = format!("{path}.not-there");
    let length = bytes.len() as i64;
    // A span that is not one is refused by this crate before the OS sees a
    // byte (`media::span`), in its own words — held where measured. What
    // the OS refuses says the sentence of the call that refused, and which
    // call refuses is the OS's: held only to say why (유저
    // connection-round-checklist-Q14, 2026-11-07: what the OS decides is
    // not frozen). ⚠️Measured on Windows (2026-11-07) alone: the Mac's was
    // to wait for its job to read alike with the C's, and the C went first
    // (connection-round-checklist H, 2026-11-08). ↩️Each failure was also the
    // C's sentence until then.
    let not_a_span = cfg!(windows).then_some("that span does not hold a readable movie");
    let tries: [(&str, Option<&str>, Box<dyn Fn() -> i32>); 4] = [
        ("no file", None, Box::new(|| open(&missing))),
        ("a plain movie said to be framed", not_a_span, Box::new(|| open_span(path, 0, length, true))),
        ("a span past the file", not_a_span, Box::new(|| open_span(path, 10, length, false))),
        ("a span of the movie's middle", None, Box::new(|| open_span(path, 1000, 2000, false))),
    ];
    for (what, says, open) in &tries {
        let handle = open();
        qa_video_decode_close(handle);
        let answer = (handle > 0, error());
        assert!(!answer.0 && !answer.1.is_empty(), "LIVENESS — {what} is refused, and says why: {answer:?}");
        if let Some(says) = says {
            assert_eq!(answer.1, *says, "{what}");
        }
    }
    // And an open that succeeds says nothing: the last failure is not left
    // for the next caller to read as its own.
    let handle = open(path);
    assert!(handle > 0 && error().is_empty(), "a good open clears the failure: {:?}", error());
    qa_video_decode_close(handle);
}

#[test]
fn a_movie_is_as_long_as_its_pictures_not_its_sound() {
    // 🚨The presentation is as long as its LONGEST track: counted by it, a
    // sound that runs past the pictures is frames with no picture in them
    // (유저 2026-08-31 「73프레임째의 빈 화면」). The C's Windows backend
    // counted by the video's own samples (검증 2026-10-23,
    // windows-counts-a-movie-by-its-longest-track). Twelve pictures under a
    // sound a quarter second longer — six frames past, well over the half
    // frame the count rounds away — and the repo's own movie, whose sound
    // runs past its twelve by less. ↩️Each was also counted as the C counted
    // it until the connection round deleted the C (H, 2026-11-08).
    let _turn = one_at_a_time();
    let sounding = Asked { sound: Some((48_000, 2)), ..SILENT };
    let Some((longer, _)) = write_movie("sound-past", sounding, 12, 12_000, Feed::Nv12, picture) else {
        return;
    };
    // This checkout's, read when the test runs (gpu_engine's
    // kernels/shared/one_checkout.rs).
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").expect("cargo runs the test");
    let fixture = format!("{crate_dir}/../../../../../test/fixtures/tone_with_video.mp4");
    for movie in [longer.path().to_str().expect("UTF-8"), &fixture] {
        let handle = open(movie);
        let answer = info(handle);
        qa_video_decode_close(handle);
        assert_eq!(answer.map(|info| info.2), Some(12), "{movie}: LIVENESS — twelve pictures");
    }
}

#[test]
fn eight_movies_open_at_once_and_a_ninth_is_refused() {
    let _turn = one_at_a_time();
    let Some((path, _)) = laid_movie() else { return };
    let path = path.path().to_str().expect("UTF-8");
    let handles: Vec<i32> = (0..8).map(|_| open(path)).collect();
    assert_eq!(handles, (1..=8).collect::<Vec<_>>(), "handles count from one");
    assert_eq!(open(path), 0, "a ninth");
    assert_eq!(error(), "too many movies are open at once");
    qa_video_decode_close(3);
    assert_eq!(open(path), 3, "the one let go is the first free again");
    assert!(info(5).is_some(), "the others are untouched");
    qa_video_decode_close_all();
    assert!(info(5).is_none(), "and close_all closes them all");
}

fn open_nv12(path: &std::path::Path) -> i32 {
    let path = CString::new(path.to_str().expect("UTF-8")).expect("no NUL");
    // SAFETY: a NUL-terminated path.
    unsafe { qa_video_decode_open_nv12(path.as_ptr()) }
}

/// A movie at 24 of `frames` NV12, `width` × `height` (even), written as a
/// piece's are: named `colours`, its frames laid as they are. Its path.
fn write_named(name: &str, (width, height): (usize, usize), colours: [i32; 4], frames: &[Vec<u8>]) -> TempFile {
    let path = TempFile::at(&format!("{name}.mp4"));
    let utf8 = CString::new(path.path().to_str().expect("UTF-8")).expect("no NUL");
    let (width, height) = (width as i32, height as i32);
    // SAFETY (each): the export's declarations; four colours, and a whole
    // frame of rows `width` apart.
    let opened =
        unsafe { qa_video_export_open(utf8.as_ptr(), width, height, 24, 1, 0, 0, 0, 0, 0, 0, colours.as_ptr()) };
    assert_eq!(opened, 1, "{name}: {}", export_error());
    for (k, nv12) in frames.iter().enumerate() {
        let written = unsafe { qa_video_export_write_nv12(nv12.as_ptr(), i64::from(width)) };
        assert_eq!(written, 1, "{name} frame {k}: {}", export_error());
    }
    assert_eq!(qa_video_export_finish(), 1, "{name}: {}", export_error());
    path
}

/// The movie at `path` opened for its NV12: the four it names, and every
/// frame.
fn read_nv12(path: &std::path::Path) -> ([i32; 4], Vec<Vec<u8>>) {
    let handle = open_nv12(path);
    assert!(handle > 0, "it opens for its NV12: {}", error());
    let mut colours = [0; 4];
    // SAFETY: room for the four.
    assert_eq!(unsafe { qa_video_decode_colours(handle, colours.as_mut_ptr()) }, 1);
    let (width, height, count, _) = info(handle).expect("it describes the movie");
    let (width, height) = (width as usize, height as usize);
    let bytes = (width + (width & 1)) * (height + (height & 1)) * 3 / 2;
    let frames = (0..count).map(|k| frame(handle, k, bytes).unwrap_or_else(|why| panic!("frame {k}: {why}"))).collect();
    qa_video_decode_close(handle);
    (colours, frames)
}

/// The Y, Cb and Cr of an NV12 frame `width` wide and `height` tall, in
/// its middle and at its top-left — where its chroma begins, so a chroma
/// read from the wrong row is seen in a flat frame too (a 1080-row movie's
/// decoder lays 1088 rows before it: `decode/windows.rs`, `Layout`).
fn points_of(nv12: &[u8], width: usize, height: usize) -> [[u8; 3]; 2] {
    [(width / 2, height / 2), (0, 0)].map(|(x, y)| {
        let chroma = width * height + (y / 2) * width + (x / 2) * 2;
        [nv12[y * width + x], nv12[chroma], nv12[chroma + 1]]
    })
}

fn near(a: [u8; 3], b: [u8; 3], within: u8) -> bool {
    a.iter().zip(b).all(|(a, b)| a.abs_diff(b) <= within)
}

/// The middle pixel of each of the first `count` frames of the movie at
/// `path`, as every surface shows it: RGBA.
fn shown(path: &std::path::Path, (width, height): (usize, usize), count: usize) -> Vec<[u8; 3]> {
    let handle = open(path.to_str().expect("UTF-8"));
    assert!(handle > 0, "{}", error());
    let at = ((height / 2) * width + width / 2) * 4;
    let pixels = (0..count as i64)
        .map(|k| frame(handle, k, width * height * 4).unwrap_or_else(|why| panic!("frame {k}: {why}")))
        .map(|rgba| [rgba[at], rgba[at + 1], rgba[at + 2]])
        .collect();
    qa_video_decode_close(handle);
    pixels
}

// 🗣️A PIECE IS ITS MOVIE'S OWN BYTES, NAMED AS THE MOVIE NAMES THEM (유저
// 2026-11-14, trimmed-movie-decodes-to-nv12-Q1: 「원본의 색을 그대로 따라
// 쓴다」). A 1920×1080 movie named BT.709 all round — what cameras and
// editors write, and a size read as BT.709 when nothing is named — opened
// for its NV12 says those four and hands its frames as they were written;
// a piece written of those frames says them too, holds the same bytes, and
// is shown as the movie is. ↩️Pieces were RGBA made BT.601 again: the
// movie's BT.709 read as the app's law (`colour`).
// ⚠️As they were written is within 3 of it: the OS's software H.264 (CI's
// Windows ARM64 runner, board windows-arm64-video-decode-tests-red) codes
// a flat frame's first block that far off in its luma — [60, 160, 100]
// came back [63, 159, 100] at the top-left, 2026-11-18. ↩️Within 2 till
// then, the Surface's hardware encoder. The piece holds those bytes still.
#[test]
fn a_piece_is_its_movies_own_bytes_named_as_the_movie_names_them() {
    let _turn = one_at_a_time();
    if qa_video_decode_supported() == 0 {
        return;
    }
    let size = (1920, 1080);
    let bt709 = [1, 1, 1, 0];
    let written = [[120, 90, 170], [60, 160, 100], [200, 128, 128]];
    let frames: Vec<_> = written.iter().map(|&ycc| flat_nv12(size.0, size.1, size.0, ycc)).collect();
    let movie = write_named("bt709", size, bt709, &frames);
    let (named, decoded) = read_nv12(movie.path());
    assert_eq!(named, bt709, "the movie says what it was named");
    assert_eq!(decoded.len(), written.len(), "every frame");
    for (k, frame) in decoded.iter().enumerate() {
        for point in points_of(frame, size.0, size.1) {
            assert!(near(point, written[k], 3), "frame {k}: {:?} came back {point:?}", written[k]);
        }
    }
    let piece = write_named("bt709-piece", size, named, &decoded);
    let (piece_named, pieced) = read_nv12(piece.path());
    assert_eq!(piece_named, bt709, "the piece says what its movie says");
    for (k, (frame, was)) in pieced.iter().zip(&decoded).enumerate() {
        for (point, was) in points_of(frame, size.0, size.1).into_iter().zip(points_of(was, size.0, size.1)) {
            assert!(near(point, was, 2), "piece frame {k}: {was:?} came back {point:?}");
        }
    }
    let (movie_shown, piece_shown) = (shown(movie.path(), size, written.len()), shown(piece.path(), size, written.len()));
    for (k, (piece, movie)) in piece_shown.into_iter().zip(movie_shown).enumerate() {
        assert!(near(piece, movie, 3), "frame {k} shown: the movie {movie:?}, its piece {piece:?}");
    }
}

// A movie that names nothing makes a piece that names nothing — the reader
// of either guesses alike.
#[test]
fn a_piece_of_a_movie_that_names_nothing_names_nothing() {
    let _turn = one_at_a_time();
    if qa_video_decode_supported() == 0 {
        return;
    }
    let unnamed = [2, 2, 2, 2];
    let frames = vec![flat_nv12(64, 48, 64, [120, 90, 170]); 3];
    let movie = write_named("unnamed", (64, 48), unnamed, &frames);
    let (named, _) = read_nv12(movie.path());
    assert_eq!(named, unnamed, "nothing named, nothing said");
}

// 🚨A FRAME SHOWN IS ITS DECODER'S NV12 THROUGH THE LAW, TO THE BYTE (card
// movie-frames-come-as-their-yuv-to-the-engine, 2026-11-16): a document of
// RGBA asks the decoder for its 4:2:0 as a piece's does, and the law makes
// the RGB by what the movie names — by its size where it names no matrix
// (유저 11-16, Q1). ↩️Media Foundation's advanced processing made it till
// then, by a matrix of its own.
#[test]
fn a_frame_shown_is_its_nv12_through_the_law() {
    let _turn = one_at_a_time();
    if qa_video_decode_supported() == 0 {
        return;
    }
    for (name, size, named, sums) in [
        ("law-hd-709", (1280, 720), [1, 1, 1, 0], colour::BT709[0]),
        ("law-hd-unnamed", (1280, 720), [2, 2, 2, 2], colour::BT709[0]),
        ("law-sd-unnamed", (320, 240), [2, 2, 2, 2], colour::BT601[0]),
        ("law-sd-601", (320, 240), [6, 1, 6, 0], colour::BT601[0]),
    ] {
        let frames: Vec<_> = (0..3).map(|k| picture(size.0, size.1, size.0, k)).collect();
        let movie = write_named(name, size, named, &frames);
        let (codes, decoded) = read_nv12(movie.path());
        let [primaries, transfer, matrix, range] = codes.map(|code| code as u8);
        let colours = colour::Colours { primaries, transfer, matrix, range };
        assert_eq!(colour::Sums::of(colours, size), sums, "{name}: what its names and its size say ({codes:?})");
        let handle = open(movie.path().to_str().expect("UTF-8"));
        assert!(handle > 0, "{name}: {}", error());
        for (k, nv12) in decoded.iter().enumerate() {
            let rgba = size.0 * size.1 * 4;
            let shown = frame(handle, k as i64, rgba).unwrap_or_else(|why| panic!("{name} frame {k}: {why}"));
            let mut law = vec![0u8; rgba];
            assert!(colour::rgba_of(nv12, size, sums, &mut law), "{name} frame {k}");
            assert!(shown == law, "{name} frame {k}: the frame shown is its NV12 through the law");
        }
        qa_video_decode_close(handle);
    }
}

// H.264 and H.265 are written of NV12 alone, whoever writes them — an
// export's frames as the GPU engine made them, a piece's as its decoder
// did — so RGBA handed to either is refused, and the error says why: no
// writer of them has a sum of its own to make YCbCr of it (board
// trimmed-movie-decodes-to-nv12-Q2, 2026-11-15). ↩️A piece's writer alone
// refused it till then.
//
// 1280×720, the size the export's H.265 movies are written at
// (`export/tests.rs`): the main PC's H.265 encoder (NVIDIA) turned 64×48
// away at open, so the refusal was never reached there (관제 2026-11-15).
#[test]
fn h26x_takes_no_rgba_whoever_writes_it() {
    let _turn = one_at_a_time();
    const SIDES: (i32, i32) = (1280, 720);
    for codec in [0, 1] {
        if qa_video_export_probe(0, codec) == 0 {
            continue;
        }
        let bt709 = [1, 1, 1, 0];
        for (who, colours) in [("an export", std::ptr::null()), ("a piece", bt709.as_ptr())] {
            let name = format!("{}-{codec}-rgba", who.replace(' ', "-"));
            let path = TempFile::at(&format!("{name}.mp4"));
            let utf8 = CString::new(path.path().to_str().expect("UTF-8")).expect("no NUL");
            // SAFETY (each): the export's declarations; four colours or
            // none, and a whole frame of the size opened.
            let opened =
                unsafe { qa_video_export_open(utf8.as_ptr(), SIDES.0, SIDES.1, 24, 1, 0, 0, 0, codec, 0, 0, colours) };
            assert_eq!(opened, 1, "{name}: {}", export_error());
            let rgba = vec![128u8; (SIDES.0 * SIDES.1 * 4) as usize];
            let refused = unsafe { qa_video_export_write_frame(rgba.as_ptr()) };
            let said = export_error();
            qa_video_export_abort();
            assert_eq!(refused, 0, "{name}: RGBA is refused");
            assert!(said.contains("written of NV12"), "{name}: {said}");
        }
    }
}

// A size the machine's encoder turns away is named when the open fails —
// not that the machine has no encoder, which the main PC's said of H.265
// at 64×48 where it had one (관제 2026-11-15). 32×32 is a size Windows'
// own H.264 encoder turns away at open on any machine (`hardware_law`).
#[cfg(windows)]
#[test]
fn a_size_no_encoder_takes_is_named() {
    let _turn = one_at_a_time();
    let path = TempFile::at("small.mp4");
    let utf8 = CString::new(path.path().to_str().expect("UTF-8")).expect("no NUL");
    // SAFETY: the export's declarations; no colours named.
    let opened = unsafe { qa_video_export_open(utf8.as_ptr(), 32, 32, 24, 1, 0, 0, 0, 0, 0, 0, std::ptr::null()) };
    let said = export_error();
    qa_video_export_abort();
    assert_eq!(opened, 0, "32x32 is turned away");
    assert_eq!(said, "video export: no H.264 encoder accepted 32x32 frames");
}
