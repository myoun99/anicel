//! The bundled decoders — symphonia's — on every platform: WAV and AIFF,
//! FLAC (native and in an ogg), Vorbis, MPEG audio, and a movie's AAC-LC or
//! ALAC. Each is handed the container through a cursor of its own, and its
//! samples are made floats here (`convert`), never by it.
//!
//! 🚨Each opener says whether symphonia trims what it knows of a sound's
//! start and end itself (its `gapless`, ON unless told). Where this engine
//! says it (`start` — the MP3's LAME tag, a movie's edit list), symphonia
//! is told no: told yes as well, the frames are taken off twice.

use symphonia::core::audio::sample::Sample;
use symphonia::core::audio::{Audio, AudioBuffer, GenericAudioBufferRef};
use symphonia::core::codecs::audio::well_known::{CODEC_ID_AAC, CODEC_ID_ALAC, CODEC_ID_FLAC, CODEC_ID_VORBIS};
use symphonia::core::codecs::audio::{AudioDecoder, AudioDecoderOptions};
use symphonia::core::formats::{FormatOptions, FormatReader, TrackType};
use symphonia::core::io::{MediaSourceStream, MediaSourceStreamOptions};
use symphonia::default::formats::{
    AdtsReader, AiffReader, FlacReader, IsoMp4Reader, MpaReader, OggReader, WavReader,
};
use symphonia::default::get_codecs;

use crate::container::{Container, Cursor};
use crate::start::{MP3_STANDARD_LEAD, Start, head_is_a_movie_box, is_adts, mp3_may_try, past_id3};
use crate::stream::{Decode, Opened};
use crate::{FORMAT_AAC, FORMAT_ALAC, FORMAT_FLAC, FORMAT_MP3, FORMAT_VORBIS, FORMAT_WAV, convert, wav_family};

/// A reader's audio track and the decoder of it.
struct Bundled {
    reader: Box<dyn FormatReader>,
    decoder: Box<dyn AudioDecoder>,
    track: u32,
    channels: usize,
}

/// `container` from `origin` on, as a symphonia reader is handed it.
fn source(container: &Container, origin: i64, seekable: bool) -> MediaSourceStream<'static> {
    MediaSourceStream::new(Box::new(Cursor::new(container, origin, seekable)), MediaSourceStreamOptions::default())
}

/// The codec of `reader`'s first audio track.
fn codec_of(reader: &dyn FormatReader) -> Option<symphonia::core::codecs::audio::AudioCodecId> {
    Some(reader.first_track(TrackType::Audio)?.codec_params.as_ref()?.audio()?.codec)
}

impl Bundled {
    /// `reader`'s first audio track with a decoder for it, trimming what it
    /// knows of the sound's ends when `gapless` — or None when there is no
    /// decoder here for it, or it has no channels.
    fn new(reader: Box<dyn FormatReader>, gapless: bool) -> Option<Bundled> {
        let track = reader.first_track(TrackType::Audio)?;
        let params = track.codec_params.as_ref()?.audio()?;
        let options = AudioDecoderOptions::default().gapless(gapless);
        let decoder = get_codecs().make_audio_decoder(params, &options).ok()?;
        let track = track.id;
        let channels = decoder.codec_params().channels.as_ref()?.count();
        (channels > 0).then_some(Bundled { reader, decoder, track, channels })
    }

    /// The rate the decoder hands back — what it read of its codec's own
    /// header, where it has one.
    fn sample_rate(&self) -> Option<i32> {
        i32::try_from(self.decoder.codec_params().sample_rate?).ok()
    }

    /// Opened as `format`, its sound starting where `start` says.
    fn opened(self, format: i32, start: Start) -> Option<Opened> {
        let sample_rate = self.sample_rate()?;
        let channels = self.channels as i32;
        Some(Opened { decoder: Box::new(self), format, channels, sample_rate, start })
    }
}

/// Every sample of `buffer` through `convert`, interleaved into `block`.
fn interleave<S: Sample>(buffer: &AudioBuffer<S>, block: &mut Vec<f32>, convert: impl Fn(S) -> f32) -> usize {
    let channels = buffer.num_planes();
    let frames = buffer.frames();
    block.resize(frames * channels, 0.0);
    for channel in 0..channels {
        let plane = buffer.plane(channel).expect("a plane for each channel");
        for (frame, &sample) in plane[..frames].iter().enumerate() {
            block[frame * channels + channel] = convert(sample);
        }
    }
    frames
}

impl Decode for Bundled {
    /// ⚠️A packet that does not decode is passed over, as the C's decoders
    /// passed over a frame they could not read; one the reader cannot read
    /// ends the sound.
    fn next(&mut self, block: &mut Vec<f32>) -> usize {
        loop {
            let Ok(Some(packet)) = self.reader.next_packet() else { return 0 };
            if packet.track_id != self.track {
                continue;
            }
            // symphonia's decoders refuse a packet of other channels than
            // their stream's, so it is passed over here — ⚠️where dr_mp3 kept
            // its place, as noise (board native-to-rust-Q8).
            let Ok(buffer) = self.decoder.decode(&packet) else { continue };
            // ⚠️No decoder here hands one back (measured 2026-11-06: the
            // check never answers). Were one to, its block would be shorter
            // than the stream's channels read it — a panic past the C
            // boundary — so the sound ends there instead.
            if buffer.spec().channels().count() != self.channels {
                return 0;
            }
            let frames = match buffer {
                GenericAudioBufferRef::U8(buffer) => interleave(buffer, block, convert::u8),
                // AIFF's 8-bit sound is signed, and dr_wav read it as a WAV
                // holds it, offset binary.
                GenericAudioBufferRef::S8(buffer) => interleave(buffer, block, |s| convert::u8(s as u8 ^ 0x80)),
                GenericAudioBufferRef::S16(buffer) => interleave(buffer, block, convert::s16),
                GenericAudioBufferRef::S24(buffer) => interleave(buffer, block, |s| convert::s24(s.inner())),
                GenericAudioBufferRef::S32(buffer) => interleave(buffer, block, convert::s32),
                GenericAudioBufferRef::F32(buffer) => interleave(buffer, block, |s| s),
                GenericAudioBufferRef::F64(buffer) => interleave(buffer, block, convert::f64),
                // No reader here hands unsigned sound wider than 8 bits.
                _ => return 0,
            };
            if frames > 0 {
                return frames;
            }
        }
    }
}

/// A WAV or an AIFF — what dr_wav read: symphonia's readers, then the WAVs
/// they do not open or decode (`wav_family`).
pub(crate) fn open_wav(container: &Container) -> Option<Opened> {
    let options = FormatOptions::default();
    let reader: Option<Box<dyn FormatReader>> = match WavReader::try_new(source(container, 0, true), options.clone()) {
        Ok(reader) => Some(Box::new(reader)),
        Err(_) => AiffReader::try_new(source(container, 0, true), options)
            .ok()
            .map(|reader| Box::new(reader) as Box<dyn FormatReader>),
    };
    reader
        .and_then(|reader| Bundled::new(reader, false)?.opened(FORMAT_WAV, Start::default()))
        .or_else(|| wav_family::open(container))
}

/// A FLAC, behind an ID3 tag or not, as dr_flac read it.
pub(crate) fn open_flac(container: &Container) -> Option<Opened> {
    let reader = FlacReader::try_new(source(container, past_id3(container), true), FormatOptions::default()).ok()?;
    Bundled::new(Box::new(reader), false)?.opened(FORMAT_FLAC, Start::default())
}

/// An ogg: Vorbis, or FLAC in an ogg — which dr_flac read before
/// stb_vorbis was asked, so it is a FLAC still. Its ends are the ogg's own
/// to say, in the granule positions of its pages, and symphonia reads them.
pub(crate) fn open_ogg(container: &Container) -> Option<Opened> {
    let reader = OggReader::try_new(source(container, 0, true), FormatOptions::default()).ok()?;
    let format = match codec_of(&reader)? {
        CODEC_ID_VORBIS => FORMAT_VORBIS,
        CODEC_ID_FLAC => FORMAT_FLAC,
        _ => return None,
    };
    Bundled::new(Box::new(reader), true)?.opened(format, Start::default())
}

/// ⚠️HE-AAC that does not say so carries its SBR in the stream alone, and
/// symphonia's decoder hands back only the core — half the rate, the highs
/// gone, and nothing tells it from a plain stream. So an AAC whose core runs
/// at 24 kHz or less is left to the decoder after (native-to-rust-Q6, the
/// user's answer: 「symphonia 먼저, 못 읽는 것만 지금처럼 OS 로」). The HE-AAC
/// that does say so, and AAC of more than two channels, symphonia refuses
/// itself.
fn plain_aac(bundled: Bundled) -> Option<Bundled> {
    bundled.sample_rate().is_some_and(|rate| !core_may_hide_sbr(rate)).then_some(bundled)
}

/// Whether an AAC core of `rate` may be the half of an HE-AAC stream that
/// does not say so — the standard's own bound, 24 kHz.
pub(crate) fn core_may_hide_sbr(rate: i32) -> bool {
    rate <= 24_000
}

/// A movie's (MP4 · M4A · MOV) AAC or ALAC — where its sound starts is the
/// movie's to say (`start::container_start`).
pub(crate) fn open_movie_codec(container: &Container) -> Option<Opened> {
    if !head_is_a_movie_box(&container.head()) {
        return None;
    }
    let reader = IsoMp4Reader::try_new(source(container, 0, true), FormatOptions::default()).ok()?;
    match codec_of(&reader)? {
        CODEC_ID_AAC => plain_aac(Bundled::new(Box::new(reader), false)?)?.opened(FORMAT_AAC, Start::default()),
        CODEC_ID_ALAC => Bundled::new(Box::new(reader), false)?.opened(FORMAT_ALAC, Start::default()),
        _ => None,
    }
}

/// A bare AAC stream (ADTS), behind an ID3 tag or not — its standard lead is
/// AAC's (`start::container_start`).
///
/// 🚨Only one whose first frame header is where the stream starts
/// (`is_adts`), the one rule its lead is taken by: the reader looks for a
/// frame's sync wherever it is, and would find one in anything.
pub(crate) fn open_adts(container: &Container) -> Option<Opened> {
    if !is_adts(container) {
        return None;
    }
    let reader = AdtsReader::try_new(source(container, past_id3(container), true), FormatOptions::default()).ok()?;
    plain_aac(Bundled::new(Box::new(reader), false)?)?.opened(FORMAT_AAC, Start::default())
}

/// MPEG audio, when the container's head lets it try (`mp3_may_try`).
///
/// Where its sound starts is the LAME tag's to say — LAME's encoder delay
/// and the decoder's 529 — or else the standard 1,105, and it runs to the
/// end, or to the frames a Xing/Info tag counts less the tag's padding: what
/// dr_mp3 took off itself.
///
/// 🚨The reader is told the container does not seek. Told it does, it
/// ESTIMATES a length from the bitrate where no tag counts the frames, and
/// a sound cut at an estimate loses its end; told it does not, the frames
/// a tag counts are the only length it gives.
pub(crate) fn open_mp3(container: &Container) -> Option<Opened> {
    if !mp3_may_try(container) {
        return None;
    }
    let reader = MpaReader::try_new(source(container, past_id3(container), false), FormatOptions::default()).ok()?;
    let track = reader.first_track(TrackType::Audio)?;
    let delay = track.delay.map(i64::from);
    let lead = delay.unwrap_or(MP3_STANDARD_LEAD);
    let keep = track.num_frames.map_or(-1, |frames| (frames as i64 + delay.unwrap_or(0) - lead).max(0));
    Bundled::new(Box::new(reader), false)?.opened(FORMAT_MP3, Start { lead, keep })
}
