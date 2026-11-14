//! The decoder through its exports: which decoder read a file, its channels
//! and rate, and its samples — held to the ledger where the bundled
//! decoders read them (the C's samples to the bit where it read whole
//! numbers, this decoder's where it computed: pins.rs), and a window, a
//! stream and a carried span to the whole decode of the same sound.
//! ↩️Until the connection round deleted the C (connection-round-checklist
//! H, 2026-11-08) every file was decoded by both, through the export each
//! had (native/oracle); what outlives it was pinned before it went
//! (connection-round-checklist A, 관제 2026-11-07).

use std::ffi::CString;
use std::path::{Path, PathBuf};

use oracle::framed;

mod movies;
mod os;
mod pins;
mod wavs;

/// 🚨The most one request of these tests asks the heap for: past it the
/// request is refused, and the tests stop there (`handle_alloc_error`)
/// rather than take the machine's memory before they fail — as a decoder
/// that sizes a buffer by a file's word would (native-memory-safety-Q5: 5.9
/// GB for one piece of a file of 1,040 bytes). No test here asks for a
/// gigabyte.
const ROOM: usize = 1 << 30;

/// The system's allocator, refusing a request past [ROOM].
struct Room;

// SAFETY: the system's allocator, or null — which a caller must meet for
// any request.
unsafe impl std::alloc::GlobalAlloc for Room {
    unsafe fn alloc(&self, layout: std::alloc::Layout) -> *mut u8 {
        if layout.size() > ROOM {
            return std::ptr::null_mut();
        }
        // SAFETY: the caller's contract.
        unsafe { std::alloc::System.alloc(layout) }
    }

    unsafe fn alloc_zeroed(&self, layout: std::alloc::Layout) -> *mut u8 {
        if layout.size() > ROOM {
            return std::ptr::null_mut();
        }
        // SAFETY: the caller's contract.
        unsafe { std::alloc::System.alloc_zeroed(layout) }
    }

    unsafe fn realloc(&self, at: *mut u8, layout: std::alloc::Layout, size: usize) -> *mut u8 {
        if size > ROOM {
            return std::ptr::null_mut();
        }
        // SAFETY: the caller's contract.
        unsafe { std::alloc::System.realloc(at, layout, size) }
    }

    unsafe fn dealloc(&self, at: *mut u8, layout: std::alloc::Layout) {
        // SAFETY: the caller's contract.
        unsafe { std::alloc::System.dealloc(at, layout) }
    }
}

#[global_allocator]
static ROOM_ONLY: Room = Room;

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

/// The decode of `count` frames of `span` from `first` (-1: to the end),
/// through the exports the app calls.
pub(crate) fn decode(span: &Span, first: i64, count: i64) -> Decoded {
    let path = CString::new(span.path.to_str().expect("a UTF-8 path")).expect("no NUL");
    let mut samples = std::ptr::null_mut();
    let (mut frames, mut channels, mut rate) = (0i64, 0i32, 0i32);
    // SAFETY: a NUL-terminated path, and out pointers to locals.
    let format = unsafe {
        crate::qa_audio_decode_span_window(
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
        unsafe { crate::qa_audio_decode_free(samples) };
        held
    };
    assert_eq!(held.len(), frames as usize * channels.max(0) as usize, "the frames said are the frames handed over");
    assert_eq!(samples.is_null(), frames == 0, "a buffer handed over is one of frames");
    Decoded { format, channels, rate, samples: held }
}

/// A test's decodes in a row, fingerprinted for the ledger: each its
/// decoder, channels and rate (i32 little-endian), then its samples — their
/// count (u64) and each as float32 little-endian — the C's answers, pinned
/// before the C was deleted (connection-round-checklist A, 관제
/// 2026-11-07). Only the bundled decoders', which decode alike on every
/// device (pins.rs).
#[derive(Default)]
pub(crate) struct Sounds(ledger::Running);

impl Sounds {
    pub(crate) fn add(&mut self, sound: &Decoded) {
        // What the OS reads is its own on each device, and a pin a job does
        // not hold is not split by platform (pins.rs).
        assert_ne!(sound.format, crate::FORMAT_OS, "a row holds the bundled decoders' sounds");
        for word in [sound.format, sound.channels, sound.rate] {
            self.0.add(&word.to_le_bytes());
        }
        self.add_samples(&sound.samples);
    }

    pub(crate) fn add_samples(&mut self, samples: &[f32]) {
        self.0.add(&(samples.len() as u64).to_le_bytes());
        let bytes: Vec<u8> = samples.iter().flat_map(|sample| sample.to_le_bytes()).collect();
        self.0.add(&bytes);
    }

    pub(crate) fn pinned(self, id: &str) {
        self.0.assert_pinned(id);
    }
}

/// Holds `sound` to be `whole`, to the bit: its decoder, channels and rate,
/// and every sample.
pub(crate) fn expect_the_same_sound(what: &str, sound: &Decoded, whole: &Decoded) {
    assert_eq!((sound.format, sound.channels, sound.rate), (whole.format, whole.channels, whole.rate), "{what}");
    assert!(sound.samples.iter().map(|s| s.to_bits()).eq(whole.samples.iter().map(|s| s.to_bits())), "{what}: the samples");
}

/// Holds `window` to be the frames `whole` has from `first` on — `count` of
/// them, or to the end at -1, and none past it.
pub(crate) fn expect_window_of(what: &str, window: &Decoded, whole: &Decoded, first: i64, count: i64) {
    let channels = whole.channels as usize;
    let from = (first as usize * channels).min(whole.samples.len());
    let to = if count < 0 { whole.samples.len() } else { (from + count as usize * channels).min(whole.samples.len()) };
    let there = Decoded { samples: whole.samples[from..to].to_vec(), ..whole.clone() };
    expect_the_same_sound(what, window, &there);
}

/// Holds a stream of `whole` read `piece` frames at a time to be it: each
/// read a whole piece until what is left, then nothing; a read of no
/// buffer or of fewer than no frames refused, of no frames nothing.
pub(crate) fn expect_stream_of(what: &str, (sound, answers, misuses): &(Decoded, Vec<i64>, [i64; 3]), whole: &Decoded, piece: i64) {
    expect_the_same_sound(what, sound, whole);
    let frames = (whole.samples.len() / whole.channels as usize) as i64;
    let mut reads = vec![piece; (frames / piece) as usize];
    reads.extend([frames % piece].into_iter().filter(|&left| left > 0));
    reads.push(0);
    assert_eq!(answers, &reads, "{what}: each read");
    assert_eq!(misuses, &[-1, -1, 0], "{what}: what a misuse answers");
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
    id3_holding(&vec![0u8; usize::from(size & 0x7F)], footer)
}

/// An ID3v2 tag holding `payload` (under 128 bytes).
fn id3_holding(payload: &[u8], footer: bool) -> Vec<u8> {
    let size = payload.len() as u8;
    let mut tag = b"ID3\x04\x00".to_vec();
    tag.extend_from_slice(&[if footer { 0x10 } else { 0 }, 0, 0, 0, size]);
    tag.extend_from_slice(payload);
    if footer {
        tag.extend_from_slice(b"3DI\x04\x00\x10\x00\x00\x00");
        tag.push(size);
    }
    tag
}

#[test]
fn a_flac_behind_an_id3_tag_reads_as_the_flac_alone() {
    let flac = fixture("tone.flac");
    let untagged = decode(&Span::whole(&flac), 0, -1);
    // ⚠️Behind an ID3 tag the C's dr_flac read no FLAC, whatever the tag
    // (measured 2026-11-06: v3 and v4, 0 to 127 bytes): Media Foundation
    // read it to the same samples, and one with a footer not at all. Here
    // it is a FLAC, read past the tag.
    for footer in [false, true] {
        let tagged = TempFile::new("tagged.flac", &[id3(100, footer), std::fs::read(&flac).expect("the fixture")].concat());
        let sound = decode(&Span::whole(tagged.path()), 0, -1);
        assert_eq!(sound.format, crate::FORMAT_FLAC, "behind an ID3 tag, a footer {footer}");
        assert!(sound.samples.iter().map(|s| s.to_bits()).eq(untagged.samples.iter().map(|s| s.to_bits())));
    }
}

// ↩️The fixtures' decodes were held to the C's here until the connection
// round deleted it (connection-round-checklist H, 2026-11-08) — the FLAC to
// the bit, the MP3 and the Vorbis within 0.0001 of dr_mp3's and
// stb_vorbis's, a movie's AAC within 0.001 of what the C left to Media
// Foundation; the pins hold every one of them now (pins.rs).
//
// ⚠️But for one place, measured 2026-11-06: a first packet's rising half
// is windowed by the shape of the block before it, and the first has none.
// This decoder takes the sine, as ffmpeg's and FAAD's do; Media Foundation
// takes the first packet's own shape. Where that is KBD and the packet is
// not a long one, the two differ over its short rising window — the Media
// Foundation movie's first packet (`tone_with_video.mp4`) is a long stop
// with KBD, and its frames 448..576 came back the KBD-to-sine window ratio
// apart, to four places, 0.125 at most. Every other sample held; a movie
// that says where it starts takes that packet off. Measured against Media
// Foundation; never against AudioToolbox.

/// The AAC of `movie` as a bare ADTS stream: each packet behind the header
/// an ADTS frame carries.
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
    let mut bytes = Vec::new();
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
    let frames = adts_of(&movie);
    let adts = TempFile::new("tone.aac", &[id3(40, false), frames.clone()].concat());
    let bare = decode(&Span::whole(adts.path()), 0, -1);
    // The same packets from the same start — AAC's standard lead, which the
    // movie takes too — but to their end: the movie says its sound is
    // shorter, and a bare stream has nowhere to say it.
    let from_movie = decode(&Span::whole(&movie), 0, -1);
    assert_eq!(bare.format, crate::FORMAT_AAC);
    assert_eq!((bare.channels, bare.rate), (from_movie.channels, from_movie.rate));
    assert!(bare.samples.iter().zip(&from_movie.samples).all(|(a, b)| a.to_bits() == b.to_bits()));
    assert_eq!(bare.samples.len(), 22_528 * bare.channels as usize, "23 packets, less one");
    assert_eq!(from_movie.samples.len(), 22_050 * bare.channels as usize);
    // ↩️Where the C's OS stack read it too, it was held within 0.001 of
    // that until the connection round deleted the C
    // (connection-round-checklist H, 2026-11-08).

    // A tag that holds what looks like a frame is passed over whole: the
    // stream starts after it.
    let fake = [0xFF, 0xF1, 0x50, 0x80, 0x02, 0x1F, 0xFC, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    let tagged = TempFile::new("tone.aac", &[id3_holding(&fake, false), frames.clone()].concat());
    let past_the_tag = decode(&Span::whole(tagged.path()), 0, -1);
    assert!(past_the_tag.samples.iter().map(|s| s.to_bits()).eq(bare.samples.iter().map(|s| s.to_bits())));

    // Frames behind something that is no tag are no bare stream: its start
    // is where its first frame says nothing of (`start::is_adts`).
    let behind = TempFile::new("tone.aac", &[vec![0x11; 100], frames].concat());
    expect_left_to_the_os("frames behind something", &Span::whole(behind.path()));
}

#[test]
fn a_movie_is_what_its_head_says() {
    // The m4a with its first box named something no movie opens with, and
    // its file type said last instead: the movie's reader would find its
    // sound all the same, but where that sound starts is read only of a
    // movie by its head — so neither reads.
    let mut bytes = std::fs::read(fixture("tone.m4a")).expect("the fixture");
    assert_eq!(&bytes[4..8], b"ftyp");
    bytes[4..8].copy_from_slice(b"uuid");
    bytes.extend_from_slice(b"\x00\x00\x00\x18ftypM4A \x00\x00\x00\x00M4A isom");
    let renamed = TempFile::new("renamed.m4a", &bytes);
    expect_left_to_the_os("a movie by another head", &Span::whole(renamed.path()));
}

/// Whether this platform has an OS stage — Media Foundation's, the NDK's
/// MediaCodec, AudioToolbox. Linux has none, and nothing reads there what
/// only the OS reads, as the C's read nothing there.
pub(crate) const OS_STAGE_HERE: bool = cfg!(any(windows, target_os = "android", target_vendor = "apple"));

/// Holds that no bundled decoder reads `span`: what reads it, where
/// anything does, is the OS stage. ↩️And, until the connection round
/// deleted the C (connection-round-checklist H, 2026-11-08), that the C's
/// read it alike.
pub(crate) fn expect_left_to_the_os(what: &str, span: &Span) {
    let format = decode(span, 0, -1).format;
    if OS_STAGE_HERE {
        assert!([crate::FORMAT_OS, crate::FORMAT_UNKNOWN].contains(&format), "{what}: {format}");
    } else {
        assert_eq!(format, crate::FORMAT_UNKNOWN, "{what}");
    }
}

#[test]
fn an_aac_core_of_24_khz_or_less_may_hide_its_sbr() {
    assert!(crate::bundled::core_may_hide_sbr(24_000));
    assert!(!crate::bundled::core_may_hide_sbr(32_000));
}

/// What a stream of `span` hands back read `piece` frames at a time to its
/// end, through the exports the app calls: which decoder, channels and
/// rate, the samples, every count each read answered, and what the misuses
/// answer — a read of no buffer, of fewer than no frames, and of none.
fn stream_in_pieces(span: &Span, piece: i64) -> (Decoded, Vec<i64>, [i64; 3]) {
    use crate::{qa_audio_stream_close as close, qa_audio_stream_open as open, qa_audio_stream_read as read};
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

// Each read a whole piece until what is left, then nothing — the C's
// answers, which the tests held this crate's to until the connection round
// deleted it (connection-round-checklist H, 2026-11-08).
#[test]
fn a_stream_read_in_pieces_hands_back_what_the_c_s_does() {
    let flac = fixture("tone.flac");
    let whole = decode(&Span::whole(&flac), 0, -1);
    assert_eq!(whole.samples.len(), 44_100 * whole.channels as usize);
    for piece in [1, 1000, 4096, 50_000] {
        let streamed = stream_in_pieces(&Span::whole(&flac), piece);
        expect_stream_of(&format!("{piece} frames at a time"), &streamed, &whole, piece);
    }
    // A stream of nothing is none.
    let missing = std::env::temp_dir().join("오디오-없는-파일.wav");
    let span = Span { path: &missing, offset: 0, length: 100, framed: false };
    assert_eq!(stream_in_pieces(&span, 10).0.format, crate::FORMAT_UNKNOWN);
    // SAFETY: a null stream, read and closed as the contract allows.
    unsafe {
        assert_eq!(crate::qa_audio_stream_read(std::ptr::null_mut(), std::ptr::null_mut(), 1), -1);
        crate::qa_audio_stream_close(std::ptr::null_mut());
    }
}

#[test]
fn a_window_holds_the_frames_a_whole_decode_has_there() {
    let flac = fixture("tone.flac");
    let span = Span::whole(&flac);
    let whole = decode(&span, 0, -1);
    for (first, count) in [(0, 0), (0, 1), (1, 1), (4095, 2), (4096, 4096), (10_000, -1), (44_099, 5), (44_100, 3), (90_000, 10)] {
        let what = format!("tone.flac from {first}, {count}");
        expect_window_of(&what, &decode(&span, first, count), &whole, first, count);
    }
    // A window cannot start before the sound.
    assert_eq!(decode(&span, -1, 5).format, crate::FORMAT_UNKNOWN);
}

#[test]
fn what_is_not_a_sound_is_refused_as_the_c_refuses_it() {
    let junk = TempFile::new("junk.bin", &noise(20_000, 7));
    assert_eq!(decode(&Span::whole(junk.path()), 0, -1).format, crate::FORMAT_UNKNOWN, "junk");

    let flac = fixture("tone.flac");
    let whole = Span::whole(&flac);
    for (what, offset, length) in [
        ("an empty span", 0, 0),
        ("a span past the end", 1, whole.length),
        ("a negative offset", -1, 10),
        ("a negative length", 0, -10),
    ] {
        let span = Span { offset, length, ..Span::whole(&flac) };
        assert_eq!(decode(&span, 0, -1).format, crate::FORMAT_UNKNOWN, "{what}");
    }
    let missing = std::env::temp_dir().join("오디오-없는-파일.wav");
    assert_eq!(decode(&Span { path: &missing, offset: 0, length: 100, framed: false }, 0, -1).format, 0);
}

#[test]
fn a_broken_piece_is_silence_no_longer_than_a_decode_of_it_hands_back() {
    // The fuzz run's ALAC (run 42274861215, sha1 ec4c17b7…df183): its one
    // piece is broken, and its table says the piece lasts 1,476,395,408
    // frames — 51 hours at 8 kHz. A decode of a piece of it hands back the
    // 4,096 frames its cookie says at most, so the broken one is 4,096 of
    // silence (native-memory-safety-Q5).
    let sound = decode(&Span::whole(&fixture("alac_piece_said_to_last_51_hours.m4a")), 0, -1);
    assert_eq!((sound.format, sound.channels, sound.rate), (crate::FORMAT_ALAC, 1, 8000));
    assert_eq!(sound.samples.len(), 4096);
    assert!(sound.samples.iter().all(|&s| s == 0.0), "silence");
}

// What a decoder took off itself is not taken again — AudioToolbox's packet
// table, which only the Mac job reads (`os::audio_toolbox`): the arithmetic
// pinned here, where every platform runs it.
#[test]
fn what_a_decoder_took_off_itself_is_not_taken_again() {
    use crate::start::Start;
    for (lead, taken, left) in [(2112, 0, 2112), (2112, 1024, 1088), (1024, 2112, 0), (0, 2112, 0)] {
        assert_eq!(Start { lead, taken, keep: -1 }.left_to_take(), left, "{lead} less {taken}");
    }
}
