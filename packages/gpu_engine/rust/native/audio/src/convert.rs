//! Whole-number samples as floats — dr_wav's conversions, which a WAV of the
//! same samples got from the C. One set for every uncompressed sound here:
//! a WAV's, an AIFF's, a movie's — and one reader of interleaved frames
//! ([Interleaved]) for the sound this crate reads itself (a movie's, and the
//! WAVs symphonia does not open).
//!
//! ⚠️8-bit is where libraries differ: dr_wav spreads 0..255 over -1..1
//! (`x / 255 * 2 - 1`), where symphonia's own conversion takes 128 as 0 —
//! so its buffers are converted here, never by it.

use crate::container::Container;

/// Offset-binary 8-bit, 0..255 spread over -1..1.
pub(crate) fn u8(sample: u8) -> f32 {
    f32::from(sample) * 0.007_843_137_254_901_960_78 - 1.0
}

pub(crate) fn s16(sample: i16) -> f32 {
    f32::from(sample) * 0.000_030_517_578_125
}

/// A 24-bit sample, sign-extended.
pub(crate) fn s24(sample: i32) -> f32 {
    (f64::from(sample) * 0.000_000_119_209_289_550_781_25) as f32
}

pub(crate) fn s32(sample: i32) -> f32 {
    (f64::from(sample) / 2_147_483_648.0) as f32
}

pub(crate) fn f64(sample: f64) -> f32 {
    sample as f32
}

/// G.711's A-law byte as the 16-bit sample it stands for — dr_wav's table.
fn a_law(byte: u8) -> i16 {
    let byte = byte ^ 0x55;
    let segment = (byte & 0x70) >> 4;
    let step = i16::from(byte & 0x0F) << 4;
    let magnitude = match segment {
        0 => step + 0x8,
        _ => (step + 0x108) << (segment - 1),
    };
    if byte & 0x80 != 0 { magnitude } else { -magnitude }
}

/// G.711's μ-law byte as the 16-bit sample it stands for — dr_wav's table.
fn mu_law(byte: u8) -> i16 {
    const BIAS: i16 = 0x84;
    let byte = !byte;
    let biased = ((i16::from(byte & 0x0F) << 3) + BIAS) << ((byte & 0x70) >> 4);
    if byte & 0x80 != 0 { BIAS - biased } else { biased - BIAS }
}

/// How uncompressed samples are kept.
#[derive(Clone, Copy, PartialEq)]
pub(crate) enum Kind {
    Unsigned,
    Signed,
    Float,
    ALaw,
    MuLaw,
}

/// A sample's kind, its bytes and their order.
#[derive(Clone, Copy)]
pub(crate) struct Pcm {
    pub(crate) kind: Kind,
    pub(crate) sample_bytes: usize,
    pub(crate) big_endian: bool,
}

impl Pcm {
    /// Whether these are samples this crate converts: offset-binary or G.711
    /// bytes, signed whole numbers of one to four bytes, or floats of four
    /// or eight.
    pub(crate) fn readable(&self) -> bool {
        match self.kind {
            Kind::Unsigned | Kind::ALaw | Kind::MuLaw => self.sample_bytes == 1,
            Kind::Signed => (1..=4).contains(&self.sample_bytes),
            Kind::Float => self.sample_bytes == 4 || self.sample_bytes == 8,
        }
    }

    /// The samples in `raw` as floats into `out` — put in little-endian
    /// order first.
    pub(crate) fn convert(&self, raw: &mut [u8], out: &mut [f32]) {
        let bytes = self.sample_bytes;
        let raw = &mut raw[..out.len() * bytes];
        if self.big_endian {
            raw.chunks_exact_mut(bytes).for_each(<[u8]>::reverse);
        }
        let samples = raw.chunks_exact(bytes).zip(out);
        match (self.kind, bytes) {
            (Kind::Float, 4) => samples.for_each(|(s, o)| *o = f32::from_le_bytes([s[0], s[1], s[2], s[3]])),
            (Kind::Float, _) => samples.for_each(|(s, o)| *o = f64(f64::from_le_bytes(s.try_into().expect("8 bytes")))),
            (Kind::ALaw, _) => samples.for_each(|(s, o)| *o = s16(a_law(s[0]))),
            (Kind::MuLaw, _) => samples.for_each(|(s, o)| *o = s16(mu_law(s[0]))),
            // dr_wav reads 8-bit sound as a WAV holds it, offset binary.
            (Kind::Signed, 1) => samples.for_each(|(s, o)| *o = u8(s[0] ^ 0x80)),
            (_, 1) => samples.for_each(|(s, o)| *o = u8(s[0])),
            (_, 2) => samples.for_each(|(s, o)| *o = s16(i16::from_le_bytes([s[0], s[1]]))),
            (_, 3) => samples.for_each(|(s, o)| *o = s24(i32::from_le_bytes([0, s[0], s[1], s[2]]) >> 8)),
            _ => samples.for_each(|(s, o)| *o = s32(i32::from_le_bytes([s[0], s[1], s[2], s[3]]))),
        }
    }
}

/// The most a read of uncompressed sound lands at once, in bytes — a frame
/// of the widest movie description is 65,535 samples of 8.
const READ_BYTES: i64 = 1 << 20;

/// Interleaved frames of `pcm` read from a container a block at a time.
pub(crate) struct Interleaved {
    pcm: Pcm,
    channels: usize,
    frame_bytes: i64,
    /// Where a read lands before it is converted.
    raw: Vec<u8>,
}

impl Interleaved {
    pub(crate) fn new(pcm: Pcm, channels: usize, block_frames: usize) -> Interleaved {
        let frame_bytes = (channels * pcm.sample_bytes) as i64;
        let raw_frames = (READ_BYTES / frame_bytes).min(block_frames as i64);
        Interleaved { pcm, channels, frame_bytes, raw: vec![0; (raw_frames * frame_bytes) as usize] }
    }

    /// The most frames one [Interleaved::read] lands.
    pub(crate) fn capacity(&self) -> i64 {
        self.raw.len() as i64 / self.frame_bytes
    }

    pub(crate) fn frame_bytes(&self) -> i64 {
        self.frame_bytes
    }

    /// `frames` frames — no more than [Interleaved::capacity] — from `at` as
    /// floats into `block`: how many came, which is fewer only where the
    /// file is cut short, and then as many as its bytes hold whole (as
    /// dr_wav ends a WAV cut short).
    pub(crate) fn read(&mut self, container: &Container, at: i64, frames: i64, block: &mut Vec<f32>) -> i64 {
        let want = (frames * self.frame_bytes) as usize;
        let got = container.read_at(at, &mut self.raw[..want]) as i64 / self.frame_bytes;
        block.resize(got as usize * self.channels, 0.0);
        self.pcm.convert(&mut self.raw, block);
        got
    }
}
