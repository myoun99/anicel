//! The WAVs symphonia does not open, read here as dr_wav read them: RF64 —
//! a WAV past 4 GB, which field recorders write — Sony's Wave64, and RIFX,
//! a RIFF big-endian (native-to-rust-Q6: every answer read them here); and
//! a RIFF symphonia refuses, as 12 bits in 16 or an A-law whose format
//! chunk has no size of its extension. Their sound is whole numbers, floats
//! or G.711, converted as a movie's is ([Interleaved]); ⚠️an ADPCM in them
//! is not read.

use crate::FORMAT_WAV;
use crate::container::Container;
use crate::convert::{Interleaved, Kind, Pcm};
use crate::start::{Start, big_endian};
use crate::stream::{BLOCK_FRAMES, Decode, Opened};

/// Wave64's names: `riff` · `wave` · `fmt ` · `data`, each in a GUID.
const W64_RIFF: [u8; 16] = *b"riff\x2E\x91\xCF\x11\xA5\xD6\x28\xDB\x04\xC1\x00\x00";
const W64_WAVE: [u8; 16] = *b"wave\xF3\xAC\xD3\x11\x8C\xD1\x00\xC0\x4F\x8E\xDB\x8A";
const W64_FMT: [u8; 16] = *b"fmt \xF3\xAC\xD3\x11\x8C\xD1\x00\xC0\x4F\x8E\xDB\x8A";
const W64_DATA: [u8; 16] = *b"data\xF3\xAC\xD3\x11\x8C\xD1\x00\xC0\x4F\x8E\xDB\x8A";

/// Which of the three, by its head.
#[derive(Clone, Copy, PartialEq)]
enum Family {
    Riff,
    Rf64,
    Rifx,
    W64,
}

/// A chunk: what it is (`fmt ` · `data` · `ds64`, or anything else), where
/// its body starts, and its size as it says it.
struct Chunk {
    name: [u8; 4],
    body: i64,
    size: u64,
}

impl Family {
    fn of(head: &[u8; 40]) -> Option<Family> {
        match (&head[..4], &head[8..12]) {
            (b"RIFF", b"WAVE") => Some(Family::Riff),
            (b"RF64", b"WAVE") => Some(Family::Rf64),
            (b"RIFX", b"WAVE") => Some(Family::Rifx),
            _ if head[..16] == W64_RIFF && head[24..40] == W64_WAVE => Some(Family::W64),
            _ => None,
        }
    }

    /// Where the first chunk starts.
    fn first(self) -> i64 {
        if self == Family::W64 { 40 } else { 12 }
    }

    /// A number of `bytes.len()` bytes in the family's order.
    fn number(self, bytes: &[u8]) -> u64 {
        if self == Family::Rifx {
            big_endian(bytes)
        } else {
            bytes.iter().rev().fold(0, |value, &byte| value << 8 | u64::from(byte))
        }
    }

    /// The chunk at `at`, and where the next one starts.
    fn chunk(self, container: &Container, at: i64) -> Option<(Chunk, i64)> {
        if self == Family::W64 {
            let mut head = [0u8; 24];
            if !container.read_all_at(at, &mut head) {
                return None;
            }
            // A Wave64 chunk's size counts its 24-byte header; chunks sit on
            // eight-byte bounds.
            let size = self.number(&head[16..]).checked_sub(24)?;
            let id: [u8; 16] = head[..16].try_into().expect("16 bytes");
            let name = match id {
                W64_FMT => *b"fmt ",
                W64_DATA => *b"data",
                _ => [0; 4],
            };
            let next = (at + 24).checked_add(i64::try_from(size.next_multiple_of(8)).ok()?)?;
            return Some((Chunk { name, body: at + 24, size }, next));
        }
        let mut head = [0u8; 8];
        if !container.read_all_at(at, &mut head) {
            return None;
        }
        let size = self.number(&head[4..]);
        let next = at + 8 + (size + size % 2) as i64;
        Some((Chunk { name: head[..4].try_into().expect("4 bytes"), body: at + 8, size }, next))
    }
}

/// The sound of one of the three.
struct WavFamily {
    container: Container,
    samples: Interleaved,
    at: i64,
    frames_left: i64,
}

/// One of the three, when it holds whole numbers or floats.
pub(crate) fn open(container: &Container) -> Option<Opened> {
    let mut head = [0u8; 40];
    container.read_at(0, &mut head);
    let family = Family::of(&head)?;
    let mut format = None;
    let mut data = None;
    let mut ds64_data = None;
    let mut at = family.first();
    while let Some((chunk, next)) = family.chunk(container, at) {
        let name = chunk.name;
        match &name {
            b"fmt " => format = Some(chunk),
            b"ds64" => {
                let mut sizes = [0u8; 16];
                if container.read_all_at(chunk.body, &mut sizes) {
                    ds64_data = Some(family.number(&sizes[8..]));
                }
            }
            b"data" => {
                data = Some(chunk);
                break;
            }
            _ => {}
        }
        at = next;
    }
    let (format, data) = (format?, data?);
    let mut fields = [0u8; 26];
    if format.size < 16 || !container.read_all_at(format.body, &mut fields[..format.size.min(26) as usize]) {
        return None;
    }
    let number = |at: usize, bytes: usize| family.number(&fields[at..at + bytes]);
    // WAVE_FORMAT_EXTENSIBLE names its format in the first word of its
    // subformat.
    let tag = if number(0, 2) == 0xFFFE && format.size >= 26 { number(24, 2) } else { number(0, 2) };
    let channels = number(2, 2) as usize;
    let rate = i32::try_from(number(4, 4)).ok()?;
    let bits = number(14, 2) as usize;
    // dr_wav's frame: the bits' bytes when the bits are whole bytes, the
    // block's when they are not (drwav_get_bytes_per_pcm_frame).
    let frame_bytes = if bits % 8 == 0 { bits / 8 * channels } else { number(12, 2) as usize };
    if channels == 0 || rate == 0 || frame_bytes == 0 || frame_bytes % channels != 0 {
        return None;
    }
    let sample_bytes = frame_bytes / channels;
    let kind = match (tag, sample_bytes) {
        (1, 1) => Kind::Unsigned,
        (1, _) => Kind::Signed,
        (3, _) => Kind::Float,
        (6, _) => Kind::ALaw,
        (7, _) => Kind::MuLaw,
        _ => return None,
    };
    let pcm = Pcm { kind, sample_bytes, big_endian: family == Family::Rifx };
    if !pcm.readable() {
        return None;
    }
    // An RF64's data chunk says all ones, and its size is in `ds64`.
    let size = match ds64_data {
        Some(size) if family == Family::Rf64 && data.size == 0xFFFF_FFFF => size,
        _ => data.size,
    };
    let sound = WavFamily {
        container: container.clone(),
        samples: Interleaved::new(pcm, channels, BLOCK_FRAMES),
        at: data.body,
        frames_left: i64::try_from(size / frame_bytes as u64).ok()?,
    };
    Some(Opened { decoder: Box::new(sound), format: FORMAT_WAV, channels: channels as i32, sample_rate: rate, start: Start::default() })
}

impl Decode for WavFamily {
    fn next(&mut self, block: &mut Vec<f32>) -> usize {
        let frames = self.frames_left.min(self.samples.capacity());
        let got = self.samples.read(&self.container, self.at, frames, block);
        // A file cut short ends where its bytes do.
        self.frames_left = if got < frames { 0 } else { self.frames_left - got };
        self.at += got * self.samples.frame_bytes();
        got as usize
    }
}
