//! The Rust decoder against the engine's C (native/oracle): every file
//! decoded by both, through the export each has — which decoder read it,
//! its channels and rate, and its samples: to the bit where both read whole
//! numbers, within a decoder's rounding where both compute (MP3, Vorbis).

use std::ffi::{CString, c_char};
use std::path::{Path, PathBuf};

use oracle::export;

mod movies;
mod pins;
mod wavs;

type Window =
    unsafe extern "C" fn(*const c_char, i64, i64, i32, i64, i64, *mut *mut f32, *mut i64, *mut i32, *mut i32) -> i32;
type Free = unsafe extern "C" fn(*mut f32);
type Compress = unsafe extern "C" fn(*mut u8, i64, *const u8, i64, i32) -> i64;
type Bound = extern "C" fn(i64) -> i64;

/// What a decode answered.
#[derive(Debug, Clone)]
pub(crate) struct Decoded {
    pub(crate) format: i32,
    pub(crate) channels: i32,
    pub(crate) rate: i32,
    pub(crate) samples: Vec<f32>,
}

/// Where a container sits: a file, its span in it, and whether it is framed.
pub(crate) struct Span<'a> {
    pub(crate) path: &'a Path,
    pub(crate) offset: i64,
    pub(crate) length: i64,
    pub(crate) framed: bool,
}

impl Span<'_> {
    pub(crate) fn whole(path: &Path) -> Span<'_> {
        let length = std::fs::metadata(path).unwrap_or_else(|error| panic!("{}: {error}", path.display())).len();
        Span { path, offset: 0, length: length as i64, framed: false }
    }
}

fn decode_with(window: Window, free: Free, span: &Span, first: i64, count: i64) -> Decoded {
    let path = CString::new(span.path.to_str().expect("a UTF-8 path")).expect("no NUL");
    let mut samples = std::ptr::null_mut();
    let (mut frames, mut channels, mut rate) = (0i64, 0i32, 0i32);
    // SAFETY: a NUL-terminated path, and out pointers to locals.
    let format = unsafe {
        window(
            path.as_ptr(),
            span.offset,
            span.length,
            i32::from(span.framed),
            first,
            count,
            &mut samples,
            &mut frames,
            &mut channels,
            &mut rate,
        )
    };
    let held = if samples.is_null() {
        Vec::new()
    } else {
        // SAFETY: the decoder handed over `frames` frames of `channels`.
        let held = unsafe { std::slice::from_raw_parts(samples, frames as usize * channels as usize) }.to_vec();
        // SAFETY: handed over by the same library, freed once.
        unsafe { free(samples) };
        held
    };
    assert_eq!(held.len(), frames as usize * channels.max(0) as usize, "the frames said are the frames handed over");
    Decoded { format, channels, rate, samples: held }
}

/// The C's decode of `count` frames from `first` (-1: to the end).
pub(crate) fn c_window(span: &Span, first: i64, count: i64) -> Decoded {
    // SAFETY: qa_audio_decode.c's declarations.
    let (window, free) =
        unsafe { (export::<Window>("qa_audio_decode_span_window"), export::<Free>("qa_audio_decode_free")) };
    decode_with(window, free, span, first, count)
}

/// This crate's, through its own exports.
pub(crate) fn rust_window(span: &Span, first: i64, count: i64) -> Decoded {
    decode_with(crate::qa_audio_decode_span_window, crate::qa_audio_decode_free, span, first, count)
}

/// Holds the Rust's decode of `span` to the C's, to the bit.
pub(crate) fn expect_same(what: &str, span: &Span, first: i64, count: i64) -> Decoded {
    let (rust, c) = (rust_window(span, first, count), c_window(span, first, count));
    assert_eq!((rust.format, rust.channels, rust.rate), (c.format, c.channels, c.rate), "{what}: which decoder, channels, rate");
    assert_eq!(rust.samples.len(), c.samples.len(), "{what}: how many samples");
    if let Some(at) = rust.samples.iter().zip(&c.samples).position(|(r, c)| r.to_bits() != c.to_bits()) {
        panic!("{what}: sample {at} is {} where the C's is {}", rust.samples[at], c.samples[at]);
    }
    rust
}

/// The biggest difference between two decodes of the same sound.
pub(crate) fn largest_difference(a: &[f32], b: &[f32]) -> f32 {
    a.iter().zip(b).map(|(a, b)| (a - b).abs()).fold(0.0, f32::max)
}

/// A file of its own in the temporary folder — named in Hangul, so every
/// test also walks the path through its one widening — deleted on drop.
/// Numbered too: the tests run at once, and two of one name would write
/// over each other's.
pub(crate) struct TempFile(PathBuf);

impl TempFile {
    pub(crate) fn new(name: &str, bytes: &[u8]) -> TempFile {
        static MADE: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
        let number = MADE.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!("오디오-{}-{number}-{name}", std::process::id()));
        std::fs::write(&path, bytes).unwrap_or_else(|error| panic!("{}: {error}", path.display()));
        TempFile(path)
    }

    pub(crate) fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

/// `body` between junk — the shape a carried sound has, and the shape that
/// catches a missing base: the file, and the span of `body` in it.
pub(crate) fn between_junk(name: &str, body: &[u8]) -> (TempFile, i64) {
    let mut bytes: Vec<u8> = (0..1234).map(|i| (i * 13 + 7) as u8).collect();
    let offset = bytes.len() as i64;
    bytes.extend_from_slice(body);
    bytes.extend((0..777).map(|i| (i * 29 + 3) as u8));
    (TempFile::new(name, &bytes), offset)
}

/// `medium` framed as the save frames it — blocks of `block_bytes`, each a
/// zstd frame the C compresses.
pub(crate) fn framed(medium: &[u8], block_bytes: usize) -> Vec<u8> {
    // SAFETY: qa_compress.c's declarations.
    let (bound, compress) =
        unsafe { (export::<Bound>("qa_zstd_compress_bound"), export::<Compress>("qa_zstd_compress")) };
    let blocks: Vec<Vec<u8>> = medium
        .chunks(block_bytes)
        .map(|block| {
            let mut frame = vec![0u8; bound(block.len() as i64) as usize];
            // SAFETY: both buffers hold the sizes passed.
            let written =
                unsafe { compress(frame.as_mut_ptr(), frame.len() as i64, block.as_ptr(), block.len() as i64, 9) };
            frame.truncate(written as usize);
            frame
        })
        .collect();
    let mut bytes = Vec::new();
    bytes.extend_from_slice(&(block_bytes as u32).to_le_bytes());
    bytes.extend_from_slice(&(medium.len() as u64).to_le_bytes());
    bytes.extend_from_slice(&(blocks.len() as u32).to_le_bytes());
    blocks.iter().for_each(|block| bytes.extend_from_slice(&(block.len() as u32).to_le_bytes()));
    blocks.iter().for_each(|block| bytes.extend_from_slice(block));
    bytes
}

/// A stream of bytes that looks like nothing, the same every run.
pub(crate) fn noise(count: usize, seed: u32) -> Vec<u8> {
    let mut state = seed;
    (0..count)
        .map(|_| {
            state = state.wrapping_mul(1_103_515_245).wrapping_add(12_345);
            (state >> 16) as u8
        })
        .collect()
}

/// A file of this checkout's own test fixtures.
pub(crate) fn fixture(name: &str) -> PathBuf {
    // The checkout the test runs in, read when it runs (one_checkout).
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").expect("cargo runs the test");
    PathBuf::from(crate_dir).join("../../../../../test/fixtures").join(name)
}

#[test]
fn the_fixtures_decode_as_the_c_decodes_them() {
    let flac = fixture("tone.flac");
    expect_same("tone.flac", &Span::whole(&flac), 0, -1);

    // The lossy ones compute: the same frames, each within a decoder's
    // rounding of the C's.
    for (name, largest) in [("tone.mp3", 0.000_1), ("tone.ogg", 0.000_1)] {
        let path = fixture(name);
        let span = Span::whole(&path);
        let (rust, c) = (rust_window(&span, 0, -1), c_window(&span, 0, -1));
        assert_eq!((rust.format, rust.channels, rust.rate), (c.format, c.channels, c.rate), "{name}");
        assert_eq!(rust.samples.len(), c.samples.len(), "{name}: the frames the C hands back");
        let difference = largest_difference(&rust.samples, &c.samples);
        assert!(difference <= largest, "{name}: a sample {difference} off the C's");
    }

    // A movie's AAC, which the C left to the OS (on Windows, Media
    // Foundation): the same frames from the same start, within one
    // decoder's rounding of the other's.
    //
    // ⚠️But for one place, measured 2026-11-06: a first packet's rising
    // half is windowed by the shape of the block before it, and the first
    // has none. This decoder takes the sine, as ffmpeg's and FAAD's do;
    // Media Foundation takes the first packet's own shape. Where that is
    // KBD and the packet is not a long one, the two differ over its short
    // rising window — the Media Foundation movie's first packet is a long
    // stop with KBD, and its frames 448..576 came back the KBD-to-sine
    // window ratio apart, to four places, 0.125 at most. Every other sample
    // holds; a movie that says where it starts takes that packet off.
    // ⚠️Measured against Media Foundation; the mac job holds this decoder to
    // AudioToolbox, unmeasured.
    for (name, unlike) in [("tone.m4a", 0..0), ("tone_with_video.mp4", 448..576)] {
        let path = fixture(name);
        let span = Span::whole(&path);
        let (rust, c) = (rust_window(&span, 0, -1), c_window(&span, 0, -1));
        assert_eq!(rust.format, crate::FORMAT_AAC, "{name}: read by the bundled decoder");
        // Linux has no OS stack, so the C read no AAC there: the pins hold
        // this decoder's samples (pins.rs).
        if c.format != crate::FORMAT_OS {
            assert_eq!(c.format, crate::FORMAT_UNKNOWN, "{name}: the C's, with no OS stack");
            continue;
        }
        assert_eq!((rust.channels, rust.rate), (c.channels, c.rate), "{name}");
        assert_eq!(rust.samples.len(), c.samples.len(), "{name}: the frames the C hands back");
        let channels = rust.channels as usize;
        let (unlike_from, unlike_to) = (unlike.start * channels, unlike.end * channels);
        let before = largest_difference(&rust.samples[..unlike_from], &c.samples[..unlike_from]);
        let after = largest_difference(&rust.samples[unlike_to..], &c.samples[unlike_to..]);
        assert!(before.max(after) <= 0.001, "{name}: a sample {} off the C's", before.max(after));
    }
}

#[test]
fn a_window_holds_the_frames_a_whole_decode_has_there() {
    let flac = fixture("tone.flac");
    let span = Span::whole(&flac);
    for (first, count) in [(0, 0), (0, 1), (1, 1), (4095, 2), (4096, 4096), (10_000, -1), (44_099, 5), (44_100, 3), (90_000, 10)] {
        expect_same(&format!("tone.flac from {first}, {count}"), &span, first, count);
    }
    // A window cannot start before the sound.
    assert_eq!(rust_window(&span, -1, 5).format, crate::FORMAT_UNKNOWN);
    assert_eq!(c_window(&span, -1, 5).format, crate::FORMAT_UNKNOWN);
}

#[test]
fn what_is_not_a_sound_is_refused_as_the_c_refuses_it() {
    let junk = TempFile::new("junk.bin", &noise(20_000, 7));
    let span = Span::whole(junk.path());
    let (rust, c) = (rust_window(&span, 0, -1), c_window(&span, 0, -1));
    assert_eq!(rust.format, c.format, "junk");

    let flac = fixture("tone.flac");
    let whole = Span::whole(&flac);
    for (what, offset, length) in [
        ("an empty span", 0, 0),
        ("a span past the end", 1, whole.length),
        ("a negative offset", -1, 10),
        ("a negative length", 0, -10),
    ] {
        let span = Span { offset, length, ..Span::whole(&flac) };
        assert_eq!(rust_window(&span, 0, -1).format, crate::FORMAT_UNKNOWN, "{what}");
        assert_eq!(c_window(&span, 0, -1).format, crate::FORMAT_UNKNOWN, "{what}");
    }
    let missing = std::env::temp_dir().join("오디오-없는-파일.wav");
    assert_eq!(rust_window(&Span { path: &missing, offset: 0, length: 100, framed: false }, 0, -1).format, 0);
}
