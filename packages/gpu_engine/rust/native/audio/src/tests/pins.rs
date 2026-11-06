//! 🧭관제 (audio-same-across-devices ③, 2026-11-05): a conform rebuilt on
//! another device holds the same samples (user, gpu-same-formula-Q2). Each
//! decode here is pinned by its fingerprint — the CRC-32 of its float32
//! samples, as the app's ledger writes it (`test/fixtures/fingerprints.json`)
//! — and gpu-engine.yml runs this crate on its Linux and mac jobs as on
//! Windows (관제 11:11 ②). No C is asked: the pins hold where no engine is
//! built.
//!
//! The FLAC's and the WAV's are the ledger's own — the C's samples, to the
//! bit. The rest are this decoder's: what the C's computed differs within a
//! decoder's rounding (`the_fixtures_decode_as_the_c_decodes_them`).
//! ⚠️Those three are where a device could differ: symphonia makes its
//! tables with the platform's own `sin` · `cos` · `powf`, and AAC's 4/3
//! power table in `f32`. A pin the Linux or mac job does not hold is that,
//! found — not a test to loosen.

use std::ffi::CString;
use std::path::Path;

use super::{TempFile, fixture};
use crate::stream::window;

/// The CRC-32 the app's ledger takes (`anicelCrc32*`).
fn crc32(bytes: &[u8]) -> u32 {
    !bytes.iter().fold(!0u32, |crc, &byte| {
        (0..8).fold(crc ^ u32::from(byte), |crc, _| if crc & 1 != 0 { crc >> 1 ^ 0xEDB8_8320 } else { crc >> 1 })
    })
}

/// The fingerprint of `path`'s whole decode, with which decoder read it and
/// how many frames.
fn fingerprint(file: &Path) -> (i32, usize, String) {
    let length = std::fs::metadata(file).unwrap_or_else(|error| panic!("{}: {error}", file.display())).len() as i64;
    let path = CString::new(file.to_str().expect("a UTF-8 path")).expect("no NUL");
    let sound = window(&path, 0, length, false, 0, -1).expect("the fixture decodes");
    let bytes: Vec<u8> = sound.samples.iter().flat_map(|sample| sample.to_le_bytes()).collect();
    (sound.format, sound.samples.len() / sound.channels as usize, format!("{:08x}", crc32(&bytes)))
}

/// Two channels of whole numbers at 48 kHz — a full-scale sawtooth on the
/// left, a linear congruential stream on the right — as the Dart parity
/// test writes it (`wholeNumberWav`, a_sound_decodes_alike_on_every_device_test).
fn whole_number_wav() -> Vec<u8> {
    let mut data = Vec::new();
    let mut seed: u64 = 0x2545_F491;
    for index in 0..4800u64 {
        let left = ((index * 1031) & 0xFFFF) as i64 - 0x8000;
        seed = (seed * 1_103_515_245 + 12_345) & 0x7FFF_FFFF;
        let right = (seed >> 15) as i64 - 0x8000;
        data.extend_from_slice(&(left as i16).to_le_bytes());
        data.extend_from_slice(&(right as i16).to_le_bytes());
    }
    let mut bytes = b"RIFF".to_vec();
    bytes.extend_from_slice(&(36 + data.len() as u32).to_le_bytes());
    bytes.extend_from_slice(b"WAVEfmt \x10\x00\x00\x00\x01\x00\x02\x00");
    bytes.extend_from_slice(&48_000u32.to_le_bytes());
    bytes.extend_from_slice(&(48_000u32 * 4).to_le_bytes());
    bytes.extend_from_slice(b"\x04\x00\x10\x00data");
    bytes.extend_from_slice(&(data.len() as u32).to_le_bytes());
    bytes.extend(data);
    bytes
}

#[test]
fn a_sound_decodes_alike_on_every_device() {
    use crate::{FORMAT_AAC, FORMAT_FLAC, FORMAT_MP3, FORMAT_VORBIS, FORMAT_WAV};
    for (name, format, frames, pinned) in [
        ("tone.flac", FORMAT_FLAC, 44_100, "e9616c02"),
        ("tone.mp3", FORMAT_MP3, 44_975, "61e7d29e"),
        ("tone.ogg", FORMAT_VORBIS, 22_050, "7ef2a0f4"),
        ("tone.m4a", FORMAT_AAC, 22_050, "7383f2de"),
        ("tone_with_video.mp4", FORMAT_AAC, 22_528, "76f94a7b"),
    ] {
        assert_eq!(fingerprint(&fixture(name)), (format, frames, pinned.to_string()), "{name}");
    }
    let wav = TempFile::new("whole-number.wav", &whole_number_wav());
    assert_eq!(fingerprint(wav.path()), (FORMAT_WAV, 4800, "f3b4dddf".to_string()), "the whole-number WAV");
}
