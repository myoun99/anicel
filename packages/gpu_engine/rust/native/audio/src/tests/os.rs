//! The OS stage against the C's: what no bundled decoder reads, read by the
//! OS's own codec stack. On Windows both are Media Foundation's in the one
//! process — the C's and this crate's — so the same samples, to the bit.
//!
//! The fixtures are Media Foundation's own encodes of a tone, written on
//! this machine's encoder (2026-11-07) — each channel its own pitch with a
//! 9 kHz high over it, for SBR to carry: `tone_aac_22khz` AAC-LC at
//! 22,050 Hz, `tone_he_aac` HE-AAC (profile 0x2C) at 48 kHz,
//! `tone_he_aac_v2` HE-AAC v2 (0x30, parametric stereo) at 44.1 kHz,
//! `tone_5_1` AAC-LC in six channels at 48 kHz, `tone.wma` WMA 8 at
//! 44.1 kHz.

use oracle::export;

use super::{
    Close, Open, Read, Span, TempFile, between_junk, c_window, expect_left_to_the_os, expect_same, fixture, framed,
    rust_close, rust_open, rust_read, rust_window, stream_in_pieces,
};
use crate::{FORMAT_OS, FORMAT_UNKNOWN};

/// Where what these tests hold was measured — Media Foundation's answers.
/// ⚠️Elsewhere a fixture is held to the C's alone (`expect_left_to_the_os`):
/// a device's MediaCodec reads what it reads, and there is no Android run of
/// these tests; on the Mac job AudioToolbox is both the C's and this
/// crate's, in the one process, unmeasured.
const MEASURED: bool = cfg!(windows);

/// What only the OS reads: the fixture, and the channels and rate its
/// decoder hands back.
///
/// ⚠️The AAC-LC of 22,050 Hz comes back at 44,100: Media Foundation's
/// decoder takes a core of 24 kHz or less to be half of an HE-AAC stream
/// that may not say so (measured 2026-11-07) — the reason such a core is
/// left to it (`bundled::core_may_hide_sbr`).
const ONLY_THE_OS: [(&str, i32, i32); 5] = [
    ("tone_aac_22khz.m4a", 2, 44_100),
    ("tone_he_aac.m4a", 2, 48_000),
    ("tone_he_aac_v2.m4a", 2, 44_100),
    ("tone_5_1.m4a", 6, 48_000),
    ("tone.wma", 2, 44_100),
];

#[test]
fn what_no_bundled_decoder_reads_the_os_stage_reads_as_the_c_does() {
    for (name, channels, rate) in ONLY_THE_OS {
        let path = fixture(name);
        let span = Span::whole(&path);
        if !MEASURED {
            expect_left_to_the_os(name, &span);
            continue;
        }
        let sound = expect_same(name, &span, 0, -1);
        assert_eq!((sound.format, sound.channels, sound.rate), (FORMAT_OS, channels, rate), "{name}");
        assert!(sound.samples.len() >= (rate / 4) as usize * channels as usize, "{name}: the sound, not a scrap of it");
        assert!(sound.samples.iter().any(|&s| s.abs() > 0.05), "{name}: the tone, not silence");
    }
}

#[test]
fn a_carried_sound_reads_through_the_os_stage_as_its_file_does() {
    // The span arithmetic in the reader it is there for: between junk, as a
    // carried sound sits in the project file, and framed as the save frames
    // it — blocks small enough that the reader crosses many.
    let path = fixture("tone_he_aac.m4a");
    let bytes = std::fs::read(&path).expect("the fixture");
    let whole = rust_window(&Span::whole(&path), 0, -1);
    let (carried, offset) = between_junk("carried.m4a", &bytes);
    let blob = framed(&bytes, 1000);
    let (framed_file, framed_offset) = between_junk("framed.m4a", &blob);
    for (what, span) in [
        ("between junk", Span { path: carried.path(), offset, length: bytes.len() as i64, framed: false }),
        ("framed", Span { path: framed_file.path(), offset: framed_offset, length: blob.len() as i64, framed: true }),
    ] {
        if !MEASURED {
            expect_left_to_the_os(what, &span);
            continue;
        }
        let sound = expect_same(what, &span, 0, -1);
        assert_eq!(sound.format, FORMAT_OS, "{what}");
        assert!(sound.samples.iter().map(|s| s.to_bits()).eq(whole.samples.iter().map(|s| s.to_bits())), "{what}");
    }
}

#[test]
fn what_the_os_reads_starts_where_the_movie_says() {
    // Media Foundation takes nothing off the front, so where the sound
    // starts is the movie's to say, as for every sound read here
    // (`start::container_start`). The fixtures are Media Foundation's and
    // say nothing, which leaves their sound where it is; the same movie
    // without the writer's mark says nothing either, and takes AAC's
    // standard 1,024 off — as the C's does.
    let path = fixture("tone_he_aac.m4a");
    let mut bytes = std::fs::read(&path).expect("the fixture");
    assert_eq!((&bytes[28..32], bytes[32]), (&b"uuid"[..], 0x5C), "the mark, straight after the file type");
    bytes[32] ^= 1;
    let unmarked = TempFile::new("unmarked.m4a", &bytes);
    let span = Span::whole(unmarked.path());
    if !MEASURED {
        expect_left_to_the_os("unmarked", &span);
        return;
    }
    let marked = rust_window(&Span::whole(&path), 0, -1);
    let sound = expect_same("unmarked", &span, 0, -1);
    let lead = 1024 * sound.channels as usize;
    assert_eq!(sound.samples.len(), marked.samples.len() - lead);
    assert!(sound.samples.iter().map(|s| s.to_bits()).eq(marked.samples[lead..].iter().map(|s| s.to_bits())));
}

#[test]
fn a_window_of_what_the_os_reads_holds_the_frames_a_whole_decode_has_there() {
    if !MEASURED {
        return;
    }
    let path = fixture("tone_5_1.m4a");
    let span = Span::whole(&path);
    let whole = rust_window(&span, 0, -1);
    let frames = (whole.samples.len() / 6) as i64;
    for (first, count) in [(0, 0), (0, 1), (1000, 2000), (frames - 5, 10), (frames, 3), (frames + 100, 10)] {
        expect_same(&format!("tone_5_1.m4a from {first}, {count}"), &span, first, count);
    }
}

#[test]
fn a_stream_of_what_the_os_reads_hands_back_what_the_c_s_does() {
    if !MEASURED {
        return;
    }
    // SAFETY: qa_audio_decode.c's declarations.
    let c = unsafe {
        (export::<Open>("qa_audio_stream_open"), export::<Read>("qa_audio_stream_read"), export::<Close>("qa_audio_stream_close"))
    };
    let rust: (Open, Read, Close) = (rust_open, rust_read, rust_close);
    let path = fixture("tone.wma");
    for piece in [1, 1000, 50_000] {
        let span = Span::whole(&path);
        let (rust_sound, rust_answers, rust_misuses) = stream_in_pieces(rust, &span, piece);
        let (c_sound, c_answers, c_misuses) = stream_in_pieces(c, &span, piece);
        assert_eq!((rust_sound.format, rust_sound.channels, rust_sound.rate), (c_sound.format, c_sound.channels, c_sound.rate));
        assert_eq!(rust_sound.format, FORMAT_OS);
        assert_eq!(rust_answers, c_answers, "each read, {piece} frames at a time");
        assert_eq!(rust_misuses, c_misuses, "what a misuse answers");
        assert!(rust_sound.samples.iter().map(|s| s.to_bits()).eq(c_sound.samples.iter().map(|s| s.to_bits())));
    }
}

#[test]
fn a_file_the_os_does_not_read_either_is_no_sound() {
    // The fixture cut short of its movie box: nothing reads it, the OS
    // stage included — and it says so rather than hand back a scrap.
    let bytes = std::fs::read(fixture("tone_he_aac.m4a")).expect("the fixture");
    let cut = TempFile::new("cut.m4a", &bytes[..bytes.len() / 3]);
    let span = Span::whole(cut.path());
    if !MEASURED {
        expect_left_to_the_os("cut short", &span);
        return;
    }
    let rust = rust_window(&span, 0, -1);
    assert_eq!((rust.format, rust.samples.len()), (FORMAT_UNKNOWN, 0));
    assert_eq!(c_window(&span, 0, -1).format, FORMAT_UNKNOWN, "the C's");
}
