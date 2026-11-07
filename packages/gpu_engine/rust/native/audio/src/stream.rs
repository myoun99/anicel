//! 🚨★★★**A SOUND IS READ AS A STREAM — EVERY DECODER THROUGH ONE DOOR**
//! (user 2026-10-10, board long-sound-conform-memory-Q1: 「지금 한다 — 전
//! 플랫폼」).
//!
//! A decoder is opened once and read on: each hands back a block at a
//! time, and the stream counts the lead off the front and stops at the
//! sound's end ([Stream::pass]) — the one place either is counted, whatever
//! decoded the container. A conform is made from it a piece at a time, so a
//! long sound is never held whole on its way in: 25 minutes of 44.1 kHz
//! stereo used to be about 1.1 GB in the worker at once, an hour about
//! 2.6 GB.
//!
//! A WINDOW is the same stream, passed over up to the window and read
//! through it (user 2026-10-09, board sound-lands-on-its-exact-sample-Q5: a
//! piece cut from a long reel holds the piece, not the reel). It still
//! decodes from the start, so a piece's samples are exactly the ones a whole
//! decode has there, with no seek to land differently on each platform;
//! only the window's frames are held, and the decoder stops once past it.

use std::ffi::CStr;

use crate::container::Container;
use crate::start::{Start, container_start};
use crate::{FORMAT_AAC, FORMAT_ALAC, FORMAT_MOVIE_PCM, FORMAT_OS, bundled, movie_pcm, os};

/// Frames a decoder is asked for at a time, where it is the one to say.
pub(crate) const BLOCK_FRAMES: usize = 4096;

/// One decoder behind a stream.
pub(crate) trait Decode {
    /// The next block of what the decoder hands back, interleaved, into
    /// `block`: how many frames — 0 at the end.
    fn next(&mut self, block: &mut Vec<f32>) -> usize;

    /// The channels and the rate of what it hands back, once it has handed
    /// a block back, for a decoder that says them only then — the NDK's
    /// MediaCodec, by its output format, where its first block fixes them.
    /// None: what it said as it opened.
    fn shape(&self) -> Option<(i32, i32)> {
        None
    }
}

/// A decoder that read the container as it opened: which one, the sound's
/// channels and rate, and what it knows of where the sound starts.
pub(crate) struct Opened {
    pub(crate) decoder: Box<dyn Decode>,
    pub(crate) format: i32,
    pub(crate) channels: i32,
    pub(crate) sample_rate: i32,
    pub(crate) start: Start,
}

/// The container opened with one decoder, or None when it does not read it.
type Opener = fn(&Container) -> Option<Opened>;

/// Format is detected by TRYING each decoder rather than sniffing magic
/// bytes — a WAV with a junk chunk before `fmt `, or an MP3 with a fat ID3
/// tag, defeats a naive sniff, and each reader already knows how to
/// recognize its own container.
///
/// 🚨★★★**THE TRYING STAYS — THE CONTAINER'S FIRST BYTES SAY WHETHER THE MP3
/// DECODER MAY TRY** (user 2026-10-09, board
/// sound-lands-on-its-exact-sample-Q2: 「파일 머리를 먼저 본다」). An MP3
/// frame-sync scan finds frames in the quiet stretches of uncompressed
/// sound, whose small negative samples are `FF Fx` bytes: a 30-minute
/// H.264 + PCM reel came back as a tenth of a second of noise (2026-10-06).
/// The sniff reads only a container's own magic at its first byte
/// (`start::mp3_may_try`), never a chunk inside it.
///
/// The ogg sits BEFORE the MP3 on purpose: `OggS` makes its reader strict,
/// while an MP3 scan is the most permissive of all. What tries after it is
/// kept from it all the same — a movie by its head (`mp3_may_try`), a bare
/// AAC stream by its layer, 00, which no MPEG audio frame has. Then a
/// movie's uncompressed sound, which needs no codec; then a movie's AAC or
/// ALAC, and a bare AAC stream; and for whatever none of these reads, the
/// OS's own codec stack ([os]) — last, so that what a bundled decoder reads
/// decodes alike on every device.
const OPENERS: [Opener; 8] = [
    bundled::open_wav,
    bundled::open_flac,
    bundled::open_ogg,
    bundled::open_mp3,
    movie_pcm::open,
    bundled::open_movie_codec,
    bundled::open_adts,
    os::open,
];

/// The sound of a container, read on.
pub struct Stream {
    decoder: Box<dyn Decode>,
    format: i32,
    channels: i32,
    sample_rate: i32,
    /// The block the decoder handed back last, and how far into it the
    /// stream has read.
    block: Vec<f32>,
    block_frames: usize,
    block_at: usize,
    /// Frames still to pass before the sound: what the file says came first.
    lead: i64,
    /// Frames of the sound still to come, or -1: all the decoder hands back.
    left: i64,
}

impl Stream {
    /// The sound of a container stored in `[offset, offset + length)` of
    /// `path` — as it is, or FRAMED (compressed in blocks) when `framed` —
    /// opened to be read on: interleaved float32 at its OWN rate, frame 0
    /// its first (what the file says came before it is not counted).
    /// Resampling to the project rate is a separate step: it is a quality
    /// decision, and burying it here would make it invisible.
    ///
    /// None when nothing could read it, or the span is not inside the file:
    /// a span that runs past the end is refused rather than clamped — a
    /// short container decodes as a corrupt file, which is a much worse
    /// answer than 「that span is not in there」.
    pub fn open(path: &CStr, offset: i64, length: i64, framed: bool) -> Option<Stream> {
        let container = Container::open(path, offset, length, framed)?;
        OPENERS.iter().find_map(|open| Stream::begin(&container, open(&container)?))
    }

    /// The stream of what `opened` reads, or None when it hands back
    /// nothing: a decoder READ the container when it opened and handed
    /// something back — the one rule — and one that hands back nothing falls
    /// through to the next.
    fn begin(container: &Container, opened: Opened) -> Option<Stream> {
        let Opened { mut decoder, format, channels, sample_rate, mut start } = opened;
        let mut block = Vec::new();
        let block_frames = decoder.next(&mut block);
        if block_frames == 0 {
            return None;
        }
        let (channels, sample_rate) = decoder.shape().unwrap_or((channels, sample_rate));
        // A movie's sound starts where the movie says, and a bare AAC
        // stream's where AAC's standard says — only the file knows, not the
        // decoder: its rate is the decoder's by the first block. The OS
        // stack's too: Media Foundation takes nothing off the front.
        if [FORMAT_MOVIE_PCM, FORMAT_AAC, FORMAT_ALAC, FORMAT_OS].contains(&format) {
            container_start(container, sample_rate, &mut start);
        }
        Some(Stream {
            decoder,
            format,
            channels,
            sample_rate,
            block,
            block_frames,
            block_at: 0,
            lead: start.lead,
            left: start.keep,
        })
    }

    /// Which decoder read the container (`FORMAT_*`).
    pub fn format(&self) -> i32 {
        self.format
    }

    pub fn channels(&self) -> i32 {
        self.channels
    }

    pub fn sample_rate(&self) -> i32 {
        self.sample_rate
    }

    /// Moves on through up to `frames` frames of the sound — into `out`, or
    /// over them when there is none — and answers how many: short only at
    /// the sound's end.
    pub fn pass(&mut self, mut out: Option<&mut [f32]>, frames: i64) -> i64 {
        let channels = self.channels as usize;
        let mut passed = 0;
        while passed < frames && self.left != 0 {
            if self.block_at == self.block_frames {
                let got = self.decoder.next(&mut self.block);
                if got == 0 {
                    self.left = 0;
                    break;
                }
                self.block_frames = got;
                self.block_at = 0;
            }
            let mut take = (self.block_frames - self.block_at) as i64;
            if self.lead > 0 {
                let drop = take.min(self.lead);
                self.block_at += drop as usize;
                self.lead -= drop;
                continue;
            }
            take = take.min(frames - passed);
            if self.left > 0 {
                take = take.min(self.left);
            }
            if let Some(out) = out.as_deref_mut() {
                let to = passed as usize * channels;
                let from = self.block_at * channels;
                let count = take as usize * channels;
                out[to..to + count].copy_from_slice(&self.block[from..from + count]);
            }
            self.block_at += take as usize;
            passed += take;
            if self.left > 0 {
                self.left -= take;
            }
        }
        passed
    }
}

/// What [window] answers: the samples, which decoder read them, and the
/// sound's channels and rate.
pub struct Window {
    pub samples: Vec<f32>,
    pub format: i32,
    pub channels: i32,
    pub sample_rate: i32,
}

/// The container's `count` frames of sound from frame `first` — the sound's
/// own frames at the container's own rate, frame 0 its first — and only
/// those held (user 2026-10-09, sound-lands-on-its-exact-sample-Q5: a piece
/// cut from a long reel holds the piece, not the reel). -1: to the end. 0:
/// none — the rate and the channels, which a caller needs before it can name
/// its frames: ask for nothing, then for what that says to ask. A window
/// past the end is no frames, not a failure. None when nothing could read
/// it.
pub fn window(path: &CStr, offset: i64, length: i64, framed: bool, first: i64, count: i64) -> Option<Window> {
    if first < 0 {
        return None;
    }
    let mut stream = Stream::open(path, offset, length, framed)?;
    let channels = stream.channels as usize;
    let mut samples = Vec::new();
    if count != 0 {
        stream.pass(None, first);
    }
    let mut kept = 0;
    while count < 0 || kept < count {
        let mut want = (BLOCK_FRAMES * 16) as i64;
        if count >= 0 {
            want = want.min(count - kept);
        }
        samples.resize((kept + want) as usize * channels, 0.0);
        let got = stream.pass(Some(&mut samples[kept as usize * channels..]), want);
        kept += got;
        if got == 0 {
            break;
        }
    }
    samples.truncate(kept as usize * channels);
    Some(Window { samples, format: stream.format, channels: stream.channels, sample_rate: stream.sample_rate })
}

#[cfg(test)]
mod tests;
