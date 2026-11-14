import 'dart:typed_data';

import '../../models/audio_pcm_scale.dart';
import '../../models/kept_span.dart';
import '../../models/movie_clock.dart' show ProjectClock, clockPulledBy;
import '../../models/project_frame_rate.dart';
import '../../native/qa_audio_resampler.dart'
    show resampleAudio, resampleReach;
import '../media/media_byte_source.dart';
import 'audio_conform_runner.dart' show decodeAudioSource;
import 'wav16_header.dart';

/// [source]'s sound over the project frames [kept], as a 16-bit WAV at its
/// own rate — the piece a trimmed sound is carried as (유저 2026-09-23: 자른
/// 구간만 품는다, 「비디오든 이미지든 오디오든 관계없이 법 하나로」). Null
/// when it cannot be decoded.
///
/// A WAV because it is the one sound this app writes ([wav16Bytes]): every
/// door that reads a sound reads it, and a take recorded here is one too
/// (only since 09-25 — see there).
///
/// ⚠️In the SOURCE's time ([int16PcmOfFrames]), not the conform's: the
/// conform applies the project's audio speed to whatever it reads, so a
/// piece cut from the conform would be sped a second time when it is
/// conformed in its turn.
///
/// ⚠️EVERY frame of [kept], silent past the sound's end. [kept] is measured
/// the way the window and the door measure a sound — off its conform's
/// peaks, which count a frame the sound only reaches into, or only reaches
/// a bucket at a time — and the piece is placed at its own length; so it
/// has to last the whole span, as a movie's, a PDF's and an animation's
/// pieces do, or the door would keep a frame less than the window showed.
///
/// [pull]: the sound played that much faster again, as a movie laid frame
/// for frame plays it ([decodeAudioOfFrames]).
Uint8List? soundSpanAsWav(
  MediaByteSource source,
  KeptSpan kept,
  ProjectClock clock, {
  ({int numerator, int denominator}) pull = noPull,
}) {
  final frames = (first: kept.first, count: kept.count);
  final decoded = decodeAudioOfFrames(source, frames, clock, pull: pull);
  if (decoded == null) {
    return null;
  }
  return wav16Bytes(
    int16PcmOfFrames(
      decoded,
      frames,
      clock.rate.inSourceTime(clock.speed),
      from: kept.first,
    ),
    sampleRate: decoded.sampleRate,
    channels: decoded.channels,
  );
}

/// [source]'s sound over project [frames] on [clock] — only those decoded
/// samples held, the first of them [frames.first]'s first sample (user
/// 2026-10-09, sound-lands-on-its-exact-sample-Q5: a piece cut from a long
/// reel holds the piece, not the reel). Null when it cannot be decoded.
///
/// Which samples the frames are depends on the sound's rate, so the decoder
/// is asked for nothing first — that answers the rate — and then for the
/// samples [ProjectFrameRate.frameToSample] names.
///
/// With a [pull] the frames are read on [clockPulledBy] it, and the sound
/// comes back that much faster at its own rate — fewer samples, through
/// the conform's own resampler and as the conform reinterprets a rate
/// (both sides scaled by the exact rational) — so [clock]'s frames count it
/// as they count a sound of its own: what a movie rewritten at the
/// project's speed hears (🗣️F-588, [framePullOf]).
({Float32List samples, int channels, int sampleRate})? decodeAudioOfFrames(
  MediaByteSource source,
  ({int first, int count}) frames,
  ProjectClock clock, {
  ({int numerator, int denominator}) pull = noPull,
}) {
  final probe = _decodedBetween(source, 0, 0);
  if (probe == null) {
    return null;
  }
  final read = clockPulledBy(clock, pull);
  final pace = read.rate.inSourceTime(read.speed);
  return _pulledBetween(
    source,
    pace.frameToSample(frames.first, probe.sampleRate),
    pace.frameToSample(frames.first + frames.count, probe.sampleRate),
    probe.sampleRate,
    pull,
  );
}

/// [source]'s own sound frames [start] up to [end] played [pull] faster at
/// its own [sampleRate]: its output frame j is the sound at [start] +
/// j × [pull]. Pulled by nothing, the window as it was decoded — equal
/// rates have no filter to reach with, and convert nothing.
///
/// Converted with as much of the sound around the window as the filter
/// reads ([resampleReach]) — alone, its edges would be converted against
/// silence, a click where the span begins (🔬F-588, 2026-11-14: 0.008 on a
/// 0.37 tone in the first 16 samples). The sound before it is a whole
/// number of [pull]'s numerators, so the outputs it gives are whole
/// denominators and the window's first lands on [start] exactly; before
/// the sound's first sample stands silence, as a whole conversion reads.
({Float32List samples, int channels, int sampleRate})? _pulledBetween(
  MediaByteSource source,
  int start,
  int end,
  int sampleRate,
  ({int numerator, int denominator}) pull,
) {
  final inputRate = sampleRate * pull.numerator;
  final outputRate = sampleRate * pull.denominator;
  final reach = resampleReach(inputRate: inputRate, outputRate: outputRate);
  final turns = (reach + pull.numerator - 1) ~/ pull.numerator;
  final from = start - turns * pull.numerator;
  final decoded = _decodedBetween(source, from < 0 ? 0 : from, end + reach);
  if (decoded == null) {
    return null;
  }
  final channels = decoded.channels;
  final silence = (from < 0 ? -from : 0) * channels;
  final converted = resampleAudio(
    samples: silence == 0
        ? decoded.samples
        : (Float32List(silence + decoded.samples.length)
            ..setAll(silence, decoded.samples)),
    channels: channels,
    inputRate: inputRate,
    outputRate: outputRate,
  );
  final first = turns * pull.denominator * channels;
  final count = (end - start) * pull.denominator ~/ pull.numerator * channels;
  return (
    samples: Float32List.sublistView(
      converted,
      first.clamp(0, converted.length),
      (first + count).clamp(0, converted.length),
    ),
    channels: channels,
    sampleRate: decoded.sampleRate,
  );
}

/// What project [frames] play of [sound], as interleaved 16-bit PCM — what
/// a WAV holds and what the encoder takes — and silence wherever they run
/// past its end. [sound] begins on project frame [from]'s first sample:
/// [decodeAudioOfFrames] decoded it from there.
///
/// Each frame from the sample the mixer would start it at
/// ([ProjectFrameRate.frameToSample], rounded up), counted in the sound's
/// own time: [pace] is the project's rate as the source's clock counts it
/// ([ProjectFrameRate.inSourceTime]) — at 1001/1000 project frame f plays
/// source time f / rate × 1001/1000.
Int16List int16PcmOfFrames(
  ({Float32List samples, int channels, int sampleRate}) sound,
  ({int first, int count}) frames,
  ProjectFrameRate pace, {
  required int from,
}) {
  final channels = sound.channels;
  final origin = pace.frameToSample(from, sound.sampleRate);
  final start =
      (pace.frameToSample(frames.first, sound.sampleRate) - origin) * channels;
  final end =
      (pace.frameToSample(frames.first + frames.count, sound.sampleRate) -
          origin) *
      channels;
  final pcm = Int16List(end - start);
  final held = (sound.samples.length - start).clamp(0, pcm.length);
  for (var i = 0; i < held; i += 1) {
    pcm[i] = int16FromUnitSample(sound.samples[start + i]);
  }
  return pcm;
}

/// The [count] sound frames [source] plays just before its sample [sample],
/// as interleaved 16-bit PCM — silence where its sound has not begun yet or
/// is already over. Null when nothing lies before [sample], or the sound
/// cannot be decoded.
///
/// What a movie piece's writer puts before the piece's own sound where it
/// has a frame there (`QaVideoEncoder.audioLead`, movie_span.dart): the
/// piece then comes out of the encoder behind its own past, as the span
/// lay in the movie it was cut from.
Int16List? int16PcmBefore(
  MediaByteSource source,
  int sample, {
  required int count,
}) {
  // May lie before the sound's first sample: silence stands there.
  final first = sample - count;
  final start = first < 0 ? 0 : first;
  if (sample <= start) {
    return null;
  }
  final decoded = _decodedBetween(source, start, sample);
  if (decoded == null) {
    return null;
  }
  final pcm = Int16List(count * decoded.channels);
  final at = (start - first) * decoded.channels;
  final held = decoded.samples.length.clamp(0, pcm.length - at);
  int16PcmOf(
    Float32List.sublistView(decoded.samples, 0, held),
    into: Int16List.sublistView(pcm, at, at + held),
  );
  return pcm;
}

/// [source]'s own sound frames [start] up to [end], decoded — null when it
/// cannot be, or decodes to no channel.
({Float32List samples, int channels, int sampleRate})? _decodedBetween(
  MediaByteSource source,
  int start,
  int end,
) {
  final decoded = decodeAudioSource(
    source,
    window: (start: start, count: end - start),
  );
  return decoded == null || decoded.channels <= 0 ? null : decoded;
}
