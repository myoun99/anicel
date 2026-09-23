import 'dart:typed_data';

import '../../models/audio_pcm_scale.dart';
import '../../models/kept_span.dart';
import '../../models/project_frame_rate.dart';
import '../media/media_byte_source.dart';
import 'audio_conform_runner.dart' show decodeAudioSource;
import 'wav16_header.dart';

/// Which of a sound's own samples play over project frames [first] ..
/// [first] + [count] - 1, at the sound's own [sampleRate].
///
/// ⚠️In the SOURCE's time, not the conform's. The conform applies the
/// project's audio [speed] to whatever it reads (1001/1000 keeps a 23.976
/// take aligned in a 24 project), so project frame f plays source time
/// f / rate × speed — and a piece cut from the conform instead would be
/// sped a second time when it is conformed in its turn.
({int start, int end}) sourceSamplesOfFrames({
  required int first,
  required int count,
  required ProjectFrameRate rate,
  required ({int numerator, int denominator}) speed,
  required int sampleRate,
}) {
  int at(int frame) =>
      frame *
      rate.denominator *
      speed.numerator *
      sampleRate ~/
      (rate.numerator * speed.denominator);
  return (start: at(first), end: at(first + count));
}

/// [source]'s sound over the project frames [inFrame] .. [outFrame] (null:
/// to its end), as a 16-bit WAV at its own rate — the piece a trimmed sound
/// is carried as (유저 2026-09-23: 자른 구간만 품는다, 「비디오든 이미지든
/// 오디오든 관계없이 법 하나로」) — with the span it kept. Null when it
/// cannot be decoded.
///
/// A WAV because it is the one sound this app writes ([wav16HeaderBytes]):
/// every door that reads a sound reads it, and a take recorded here is one
/// already.
({KeptSpan kept, Uint8List wav})? soundSpanAsWav(
  MediaByteSource source, {
  required int inFrame,
  int? outFrame,
  required ProjectFrameRate rate,
  required ({int numerator, int denominator}) speed,
}) {
  final decoded = decodeAudioSource(source);
  if (decoded == null || decoded.channels <= 0) {
    return null;
  }
  // As many project frames as the sound lasts, the last one partial.
  final perFrame = rate.denominator * speed.numerator * decoded.sampleRate;
  final frames =
      (decoded.samples.length ~/ decoded.channels * rate.numerator *
              speed.denominator +
          perFrame -
          1) ~/
      perFrame;
  final kept = KeptSpan(
    length: frames < 1 ? 1 : frames,
    inFrame: inFrame,
    outFrame: outFrame,
  );
  final pcm = int16SamplesOf(
    decoded,
    sourceSamplesOfFrames(
      first: kept.first,
      count: kept.count,
      rate: rate,
      speed: speed,
      sampleRate: decoded.sampleRate,
    ),
  );
  final data = pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes);
  return (
    kept: kept,
    wav: (BytesBuilder(copy: false)
          ..add(
            wav16HeaderBytes(
              dataBytes: data.length,
              sampleRate: decoded.sampleRate,
              channels: decoded.channels,
            ),
          )
          ..add(data))
        .takeBytes(),
  );
}

/// [sound]'s samples [span] (per channel, clamped to what it holds) as
/// interleaved 16-bit PCM — what a WAV holds and what the encoder takes.
Int16List int16SamplesOf(
  ({Float32List samples, int channels, int sampleRate}) sound,
  ({int start, int end}) span,
) {
  final channels = sound.channels;
  final available = sound.samples.length ~/ channels;
  final start = span.start.clamp(0, available);
  final end = span.end.clamp(start, available);
  final pcm = Int16List((end - start) * channels);
  for (var i = 0; i < pcm.length; i += 1) {
    pcm[i] = int16FromUnitSample(sound.samples[start * channels + i]);
  }
  return pcm;
}
