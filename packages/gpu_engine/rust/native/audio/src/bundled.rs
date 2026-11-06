//! The bundled decoders — symphonia's — on every platform: WAV and AIFF,
//! FLAC (native and in an ogg), Vorbis, MPEG audio, and a movie's AAC-LC or
//! ALAC. Each is handed the container through a cursor of its own, and its
//! samples are made floats here (`convert`), never by it.
//!
//! 🚨Each opener says whether symphonia trims what it knows of a sound's
//! start and end itself (its `gapless`, ON unless told). Where this engine
//! says it (`start` — the MP3's LAME tag, a movie's edit list), symphonia
//! is told no: told yes as well, the frames are taken off twice.

use audio_mix::{DEFAULT_BANDWIDTH, DEFAULT_STOPBAND_DB, MONO_ON_STEREO, Resampler, resample_frames};
use symphonia::core::audio::sample::Sample;
use symphonia::core::audio::{Audio, AudioBuffer, GenericAudioBufferRef};
use symphonia::core::codecs::audio::well_known::{CODEC_ID_AAC, CODEC_ID_ALAC, CODEC_ID_FLAC, CODEC_ID_VORBIS};
use symphonia::core::codecs::audio::{AudioCodecParameters, AudioDecoder, AudioDecoderOptions};
use symphonia::core::formats::{FormatOptions, FormatReader, TrackType};
use symphonia::core::io::{MediaSourceStream, MediaSourceStreamOptions};
use symphonia::core::packet::Packet;
use symphonia::core::units::TimeBase;
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
    /// The decoder of the piece last read: the stream's own, until a piece
    /// it refuses is read by a new one (`Decode for Bundled`).
    decoder: Box<dyn AudioDecoder>,
    /// What a new decoder is made from.
    params: AudioCodecParameters,
    options: AudioDecoderOptions,
    track: u32,
    time_base: Option<TimeBase>,
    /// The stream's channels: its first piece's, or the most any piece has
    /// where its reader can say so before (`mpa_turns_stereo`).
    channels: usize,
    /// The stream's rate: its first piece's, whatever the pieces after are.
    rate: u32,
    /// The pieces at another rate being read now, converted to `rate`.
    other: Option<Other>,
}

/// A run of pieces at one rate other than the stream's, and the conversion
/// of them to the stream's (native-to-rust-Q11, the user's answer
/// 2026-11-06: 「FFmpeg 처럼 첫 조각의 레이트로 바꿔 넣는다」 — the one
/// resampler the timeline conforms a sound with, `audio_mix`'s). A run is
/// fed as its pieces come, so a conversion of it is the whole run's, bit
/// for bit; it ends where a piece of another rate, or nothing, comes.
pub(crate) struct Other {
    rate: u32,
    resampler: Resampler,
}

impl Other {
    /// A run of `channels` at `rate` converted to `to`, at the quality a
    /// sound is conformed at — none on bad geometry.
    pub(crate) fn new(channels: usize, rate: u32, to: u32) -> Option<Other> {
        let resampler = Resampler::new(channels, rate as i32, to as i32, DEFAULT_STOPBAND_DB, DEFAULT_BANDWIDTH)?;
        Some(Other { rate, resampler })
    }

    /// The `frames` of `channels` at the head of `block` handed over, and
    /// `block` made what of the run is ready now — all of it, so that the
    /// run holds no more than its filter reads: how many frames — none
    /// where the memory ran out.
    pub(crate) fn feed(&mut self, block: &mut Vec<f32>, frames: usize, channels: usize) -> Option<usize> {
        if !self.resampler.push(&block[..frames * channels]) {
            return None;
        }
        block.resize(usize::try_from(self.resampler.ready()).ok()? * channels, 0.0);
        usize::try_from(self.resampler.pull(block)).ok()
    }
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
        let params = track.codec_params.as_ref()?.audio()?.clone();
        let options = AudioDecoderOptions::default().gapless(gapless);
        let decoder = get_codecs().make_audio_decoder(&params, &options).ok()?;
        let (track, time_base) = (track.id, track.time_base);
        let channels = decoder.codec_params().channels.as_ref()?.count();
        let rate = decoder.codec_params().sample_rate?;
        (channels > 0).then_some(Bundled { reader, decoder, params, options, track, time_base, channels, rate, other: None })
    }

    /// The rate the decoder hands back — what it read of its codec's own
    /// header, where it has one.
    fn sample_rate(&self) -> Option<i32> {
        i32::try_from(self.rate).ok()
    }

    /// Opened as `format`, its sound starting where `start` says.
    fn opened(self, format: i32, start: Start) -> Option<Opened> {
        let sample_rate = self.sample_rate()?;
        let channels = self.channels as i32;
        Some(Opened { decoder: Box::new(self), format, channels, sample_rate, start })
    }

    /// `packet`, which the decoder in hand refused, read by a new one — and
    /// the new one reads the pieces after it. symphonia's decoders refuse a
    /// piece of other channels or another rate than the first they read
    /// (`symphonia-bundle-mp3` 0.6.1 `decode_inner`), so a piece that
    /// changes them takes a decoder of its own, and so does the piece that
    /// changes them back.
    fn afresh(&mut self, packet: &Packet, block: &mut Vec<f32>) -> Piece {
        let Ok(mut decoder) = get_codecs().make_audio_decoder(&self.params, &self.options) else {
            return Piece::Unread;
        };
        let piece = match decoder.decode(packet) {
            Ok(buffer) => piece(buffer, block, self.channels),
            Err(_) => return Piece::Unread,
        };
        if matches!(piece, Piece::Read { .. }) {
            self.decoder = decoder;
        }
        piece
    }

    /// A piece nothing here reads, kept in its place as silence
    /// (native-to-rust-Q8, the user's answer 2026-11-06 — 「깨진 프레임은
    /// 무음으로 자리를 지킨다」): the frames its packet lasts, `dur` in the
    /// track's time base. symphonia 0.6.1's `dur` is the packet's whole
    /// block (`trimmed_dur` takes off the builder's own trims, which are
    /// none: packet.rs:340), and a piece inside a sound is trimmed of
    /// nothing — so it is the frames a decode of it would have handed back.
    ///
    /// 🚨★**NO LONGER THAN ONE DECODE OF IT HANDS BACK** (user 2026-11-07,
    /// native-memory-safety-Q5: 「코덱이 한 조각에 낼 수 있는 만큼까지만
    /// 무음으로」). `dur` is the container's word, and a container may say
    /// anything: the fuzz run's ALAC of 1,040 bytes said a piece lasts
    /// 1,476,395,408 frames — 51 hours at 8 kHz — and this took 5.9 GB at
    /// once for it. A piece that reads hands back its decoder's frames
    /// whatever the container says, so a piece that does not keeps the place
    /// a decode of it could have: the most the decoder's buffer holds. Every
    /// decoder here sizes it as it is made, but the MP3 one, which sizes it
    /// at the header of the first piece it is handed — before anything of
    /// the piece can be refused: its reader hands on only a frame whose
    /// header it parsed with the decoder's own parser, cut to the length
    /// that header says (symphonia-bundle-mp3 `read_mpeg_frame`).
    fn silence(&self, packet: &Packet, block: &mut Vec<f32>) -> usize {
        let lasts = frames_lasting(packet.dur.get(), self.time_base, self.rate);
        self.quiet(block, lasts.min(self.decoder.last_decoded().capacity()))
    }

    /// `block` made `frames` of silence.
    fn quiet(&self, block: &mut Vec<f32>, frames: usize) -> usize {
        block.clear();
        block.resize(frames * self.channels, 0.0);
        frames
    }

    /// The `frames` of a piece at `rate` at the head of `block`, converted
    /// to the stream's by the run of pieces at it — behind what a run at
    /// another rate still held. A piece no conversion is had for keeps its
    /// place as silence, as one nothing reads does (Q8).
    fn convert(&mut self, block: &mut Vec<f32>, frames: usize, rate: u32) -> usize {
        let tail = if self.other.as_ref().is_some_and(|other| other.rate == rate) { Vec::new() } else { self.run_end() };
        if self.other.is_none() {
            self.other = Other::new(self.channels, rate, self.rate);
        }
        let converted = match self.other.as_mut().and_then(|other| other.feed(block, frames, self.channels)) {
            Some(converted) => converted,
            None => {
                let lasts = resample_frames(frames as i64, rate as i32, self.rate as i32);
                self.quiet(block, usize::try_from(lasts).unwrap_or(0))
            }
        };
        Self::ahead(tail, block, self.channels) + converted
    }

    /// What the run of pieces at another rate still holds, the run over.
    fn run_end(&mut self) -> Vec<f32> {
        let Some(mut other) = self.other.take() else { return Vec::new() };
        other.resampler.end();
        let mut tail = vec![0.0; usize::try_from(other.resampler.ready()).unwrap_or(0) * self.channels];
        other.resampler.pull(&mut tail);
        tail
    }

    /// The `frames` of the stream's rate in `block`, behind what the run of
    /// pieces at another rate before them still held.
    fn after_run(&mut self, block: &mut Vec<f32>, frames: usize) -> usize {
        let tail = self.run_end();
        Self::ahead(tail, block, self.channels) + frames
    }

    /// `tail` put ahead of what `block` holds: its frames.
    fn ahead(tail: Vec<f32>, block: &mut Vec<f32>, channels: usize) -> usize {
        let frames = tail.len() / channels;
        block.splice(0..0, tail);
        frames
    }
}

/// The frames that `lasts` ticks of `base` — a track's time base, or the
/// frames themselves where it has none — are at `rate`. A movie's track
/// counts in its own ticks (an AAC frame of 1,024 at 48 kHz is 1,920 of a
/// 90 kHz track); 0 where they cannot be held.
pub(crate) fn frames_lasting(lasts: u64, base: Option<TimeBase>, rate: u32) -> usize {
    let lasts = u128::from(lasts);
    let frames = match base {
        Some(base) => lasts * u128::from(base.numer.get()) * u128::from(rate) / u128::from(base.denom.get()),
        None => lasts,
    };
    usize::try_from(frames).unwrap_or(0)
}

/// What became of a packet.
enum Piece {
    /// Its frames, in the stream's channels, at its rate.
    Read { frames: usize, rate: u32 },
    /// Nothing here reads it, or puts it in the stream's channels.
    Unread,
    /// Read as sound no reader here hands.
    End,
}

/// A decoded piece in `channels` into `block`.
fn piece(buffer: GenericAudioBufferRef<'_>, block: &mut Vec<f32>, channels: usize) -> Piece {
    let spec = buffer.spec();
    let (own, rate) = (spec.channels().count(), spec.rate());
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
        _ => return Piece::End,
    };
    if fit(block, frames, own, channels) { Piece::Read { frames, rate } } else { Piece::Unread }
}

/// The `frames` of `own` channels at the head of `block`, put in `channels`:
/// a piece of one channel in both of two, each at −3 dB — the mixer's own
/// [`MONO_ON_STEREO`], for a mono sound is heard at one level wherever it
/// comes from (native-to-rust-Q12). ⚠️Into fewer
/// channels than its own no piece here goes — a sound opens with the most
/// any piece has (native-to-rust-Q13, `mpa_turns_stereo`), and only MPEG
/// audio changes them on the way; were one to, it keeps its place as
/// silence, as a piece nothing reads does (Q8).
fn fit(block: &mut Vec<f32>, frames: usize, own: usize, channels: usize) -> bool {
    match (own, channels) {
        _ if own == channels => {}
        (1, 2) => {
            block.resize(frames * 2, 0.0);
            // From the end, so that no sample is written over before it is
            // read.
            for frame in (0..frames).rev() {
                let sample = MONO_ON_STEREO as f32 * block[frame];
                block[2 * frame] = sample;
                block[2 * frame + 1] = sample;
            }
        }
        _ => return false,
    }
    true
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
    /// Every piece keeps its place: one the decoder in hand refuses is read
    /// by a new one (`afresh`), put in the stream's channels (`fit`) and
    /// converted to its rate (`convert`), and one nothing reads is its
    /// length of silence (native-to-rust-Q8 · Q11 · Q12 · Q13). One the
    /// reader cannot read ends the sound.
    fn next(&mut self, block: &mut Vec<f32>) -> usize {
        loop {
            let Ok(Some(packet)) = self.reader.next_packet() else { return self.after_run(block, 0) };
            if packet.track_id != self.track {
                continue;
            }
            let piece = match self.decoder.decode(&packet) {
                Ok(buffer) => piece(buffer, block, self.channels),
                Err(_) => self.afresh(&packet, block),
            };
            let frames = match piece {
                Piece::Read { frames, rate } if rate == self.rate => self.after_run(block, frames),
                Piece::Read { frames, rate } => self.convert(block, frames, rate),
                Piece::Unread => {
                    let frames = self.silence(&packet, block);
                    self.after_run(block, frames)
                }
                Piece::End => return 0,
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
    let mut bundled = Bundled::new(Box::new(reader), false)?;
    if bundled.channels == 1 && mpa_turns_stereo(container) {
        bundled.channels = 2;
    }
    bundled.opened(FORMAT_MP3, Start { lead, keep })
}

/// Whether MPEG audio that opens with one channel has two somewhere after
/// it — then the sound opens with two, and its pieces of one are spread
/// into both (native-to-rust-Q13, the user's answer 2026-11-06: 「편집기처럼
/// 스테레오로 연다 — 모노 부분을 펼친다」, as an editor puts each piece in
/// its project's channels). Each frame's header says its own channel mode
/// (`11` is one channel), and the frames asked are the reader's own, read
/// once more to the end — what only a sound that opens with one pays.
fn mpa_turns_stereo(container: &Container) -> bool {
    let Ok(mut reader) = MpaReader::try_new(source(container, past_id3(container), false), FormatOptions::default())
    else {
        return false;
    };
    while let Ok(Some(packet)) = reader.next_packet() {
        if packet.data.get(3).is_some_and(|mode| mode >> 6 != 0b11) {
            return true;
        }
    }
    false
}
