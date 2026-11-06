//! The Rust decoder against the engine's C (native/oracle): every file
//! decoded by both, through the export each has — which decoder read it,
//! its channels and rate, and its samples: to the bit where both read whole
//! numbers, within a decoder's rounding where both compute (MP3, Vorbis).

use std::ffi::{CString, c_char, c_void};
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
    assert_eq!(samples.is_null(), frames == 0, "a buffer handed over is one of frames");
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

/// An ID3v2 tag of `size` bytes of nothing, a footer after it when `footer`.
pub(crate) fn id3(size: u8, footer: bool) -> Vec<u8> {
    let mut tag = b"ID3\x04\x00".to_vec();
    tag.extend_from_slice(&[if footer { 0x10 } else { 0 }, 0, 0, 0, size & 0x7F]);
    tag.extend(vec![0u8; usize::from(size & 0x7F)]);
    if footer {
        tag.extend_from_slice(b"3DI\x04\x00\x10\x00\x00\x00");
        tag.push(size & 0x7F);
    }
    tag
}

#[test]
fn the_fixtures_decode_as_the_c_decodes_them() {
    let flac = fixture("tone.flac");
    let untagged = expect_same("tone.flac", &Span::whole(&flac), 0, -1);
    // ⚠️Behind an ID3 tag the C's dr_flac reads no FLAC, whatever the tag
    // (measured 2026-11-06: v3 and v4, 0 to 127 bytes): Media Foundation
    // read it to the same samples, and one with a footer not at all. Here
    // it is a FLAC, read past the tag.
    for footer in [false, true] {
        let tagged = TempFile::new("tagged.flac", &[id3(100, footer), std::fs::read(&flac).expect("the fixture")].concat());
        let span = Span::whole(tagged.path());
        let (rust, c) = (rust_window(&span, 0, -1), c_window(&span, 0, -1));
        assert_eq!(rust.format, crate::FORMAT_FLAC, "behind an ID3 tag, a footer {footer}");
        assert!(rust.samples.iter().map(|s| s.to_bits()).eq(untagged.samples.iter().map(|s| s.to_bits())));
        assert_ne!(c.format, crate::FORMAT_FLAC, "the C's, a footer {footer}");
    }

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

/// The AAC of `movie` as a bare ADTS stream behind an ID3 tag: each packet
/// behind the header an ADTS frame carries.
fn adts_of(movie: &Path) -> Vec<u8> {
    use symphonia::core::formats::{FormatOptions, FormatReader, TrackType};
    use symphonia::core::io::{MediaSourceStream, MediaSourceStreamOptions};
    let file = std::fs::File::open(movie).expect("the fixture");
    let source = MediaSourceStream::new(Box::new(file), MediaSourceStreamOptions::default());
    let mut reader = symphonia::default::formats::IsoMp4Reader::try_new(source, FormatOptions::default()).expect("a movie");
    let track = reader.first_track(TrackType::Audio).expect("a sound");
    let params = track.codec_params.as_ref().and_then(|params| params.audio()).expect("audio");
    let rates = [96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000, 22_050, 16_000, 12_000, 11_025, 8_000];
    let rate = rates.iter().position(|&rate| Some(rate) == params.sample_rate).expect("a rate ADTS names") as u8;
    let channels = params.channels.as_ref().expect("channels").count() as u8;
    let id = track.id;
    let mut bytes = id3(40, false);
    while let Ok(Some(packet)) = reader.next_packet() {
        if packet.track_id != id {
            continue;
        }
        // Sync, MPEG-4, no CRC; AAC-LC (profile 1), the rate's index, the
        // channels, the frame's length with its header; a fullness of all
        // ones, one block.
        let length = packet.data.len() + 7;
        bytes.extend_from_slice(&[
            0xFF,
            0xF1,
            1 << 6 | rate << 2 | channels >> 2,
            (channels & 3) << 6 | (length >> 11) as u8,
            (length >> 3) as u8,
            ((length & 7) << 5) as u8 | 0x1F,
            0xFC,
        ]);
        bytes.extend_from_slice(&packet.data);
    }
    bytes
}

#[test]
fn a_bare_aac_stream_reads_as_its_movie_reads() {
    let movie = fixture("tone.m4a");
    let adts = TempFile::new("tone.aac", &adts_of(&movie));
    let span = Span::whole(adts.path());
    let (rust, c) = (rust_window(&span, 0, -1), c_window(&span, 0, -1));
    // The same packets from the same start — AAC's standard lead, which the
    // movie takes too — but to their end: the movie says its sound is
    // shorter, and a bare stream has nowhere to say it.
    let from_movie = rust_window(&Span::whole(&movie), 0, -1);
    assert_eq!(rust.format, crate::FORMAT_AAC);
    assert_eq!((rust.channels, rust.rate), (from_movie.channels, from_movie.rate));
    assert!(rust.samples.iter().zip(&from_movie.samples).all(|(a, b)| a.to_bits() == b.to_bits()));
    assert_eq!(rust.samples.len(), 22_528 * rust.channels as usize, "23 packets, less one");
    assert_eq!(from_movie.samples.len(), 22_050 * rust.channels as usize);
    // Where the C's OS stack read it too, within its rounding.
    if c.format == crate::FORMAT_OS {
        assert_eq!(rust.samples.len(), c.samples.len(), "the frames the C hands back");
        assert!(largest_difference(&rust.samples, &c.samples) <= 0.001);
    }
}

type Open = unsafe extern "C" fn(*const c_char, i64, i64, i32, *mut i32, *mut i32, *mut i32) -> *mut c_void;
type Read = unsafe extern "C" fn(*mut c_void, *mut f32, i64) -> i64;
type Close = unsafe extern "C" fn(*mut c_void);

unsafe extern "C" fn rust_open(
    path: *const c_char,
    offset: i64,
    length: i64,
    framed: i32,
    format: *mut i32,
    channels: *mut i32,
    rate: *mut i32,
) -> *mut c_void {
    // SAFETY: passed on as the caller's.
    unsafe { crate::qa_audio_stream_open(path, offset, length, framed, format, channels, rate) }.cast()
}

unsafe extern "C" fn rust_read(stream: *mut c_void, out: *mut f32, frames: i64) -> i64 {
    // SAFETY: passed on as the caller's.
    unsafe { crate::qa_audio_stream_read(stream.cast(), out, frames) }
}

unsafe extern "C" fn rust_close(stream: *mut c_void) {
    // SAFETY: passed on as the caller's.
    unsafe { crate::qa_audio_stream_close(stream.cast()) }
}

/// What a stream of `span` hands back read `piece` frames at a time to its
/// end: which decoder, channels and rate, the samples, every count each
/// read answered, and what the misuses answer — a read of no buffer, and of
/// fewer than no frames.
fn stream_in_pieces((open, read, close): (Open, Read, Close), span: &Span, piece: i64) -> (Decoded, Vec<i64>, [i64; 3]) {
    let path = CString::new(span.path.to_str().expect("a UTF-8 path")).expect("no NUL");
    let (mut format, mut channels, mut rate) = (0, 0, 0);
    // SAFETY: a NUL-terminated path, out pointers to locals; the stream read
    // into buffers of the frames asked for, and closed once.
    unsafe {
        let stream = open(path.as_ptr(), span.offset, span.length, i32::from(span.framed), &mut format, &mut channels, &mut rate);
        let mut decoded = Decoded { format, channels, rate, samples: Vec::new() };
        if stream.is_null() {
            return (decoded, Vec::new(), [0; 3]);
        }
        let mut answers = Vec::new();
        let mut buffer = vec![0f32; piece as usize * channels as usize];
        loop {
            let got = read(stream, buffer.as_mut_ptr(), piece);
            answers.push(got);
            if got <= 0 {
                break;
            }
            decoded.samples.extend_from_slice(&buffer[..got as usize * channels as usize]);
        }
        let misuses = [read(stream, std::ptr::null_mut(), 1), read(stream, buffer.as_mut_ptr(), -1), read(stream, buffer.as_mut_ptr(), 0)];
        close(stream);
        (decoded, answers, misuses)
    }
}

#[test]
fn a_stream_read_in_pieces_hands_back_what_the_c_s_does() {
    // SAFETY: qa_audio_decode.c's declarations.
    let c = unsafe {
        (export::<Open>("qa_audio_stream_open"), export::<Read>("qa_audio_stream_read"), export::<Close>("qa_audio_stream_close"))
    };
    let rust: (Open, Read, Close) = (rust_open, rust_read, rust_close);
    let flac = fixture("tone.flac");
    for piece in [1, 1000, 4096, 50_000] {
        let span = Span::whole(&flac);
        let (rust_sound, rust_answers, rust_misuses) = stream_in_pieces(rust, &span, piece);
        let (c_sound, c_answers, c_misuses) = stream_in_pieces(c, &span, piece);
        assert_eq!((rust_sound.format, rust_sound.channels, rust_sound.rate), (c_sound.format, c_sound.channels, c_sound.rate));
        assert_eq!(rust_answers, c_answers, "each read, {piece} frames at a time");
        assert_eq!(rust_misuses, c_misuses, "what a misuse answers");
        assert!(rust_sound.samples.iter().zip(&c_sound.samples).all(|(a, b)| a.to_bits() == b.to_bits()));
        assert_eq!(rust_sound.samples.len(), 44_100 * rust_sound.channels as usize);
    }
    // A stream of nothing is none.
    let missing = std::env::temp_dir().join("오디오-없는-파일.wav");
    let span = Span { path: &missing, offset: 0, length: 100, framed: false };
    assert_eq!(stream_in_pieces(rust, &span, 10).0.format, crate::FORMAT_UNKNOWN);
    // SAFETY: a null stream, read and closed as the contract allows.
    unsafe {
        assert_eq!(rust_read(std::ptr::null_mut(), std::ptr::null_mut(), 1), -1);
        rust_close(std::ptr::null_mut());
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
