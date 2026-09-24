import 'dart:typed_data';

import '../../models/audio_pcm_scale.dart';
import '../../models/kept_span.dart';
import '../../models/movie_clock.dart' show ProjectClock;
import '../../models/project_frame_rate.dart';
import '../media/media_byte_source.dart';
import 'audio_conform_runner.dart' show decodeAudioSource;
import 'wav16_header.dart';

/// [source]'s sound over the project frames [kept], as a 16-bit WAV at its
/// own rate — the piece a trimmed sound is carried as (유저 2026-09-23: 자른
/// 구간만 품는다, 「비디오든 이미지든 오디오든 관계없이 법 하나로」). Null
/// when it cannot be decoded.
///
/// A WAV because it is the one sound this app writes ([wav16HeaderBytes]):
/// every door that reads a sound reads it, and a take recorded here is one
/// already.
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
Uint8List? soundSpanAsWav(
  MediaByteSource source,
  KeptSpan kept,
  ProjectClock clock,
) {
  final decoded = decodeAudioSource(source);
  if (decoded == null || decoded.channels <= 0) {
    return null;
  }
  final pcm = int16PcmOfFrames(
    decoded,
    (first: kept.first, count: kept.count),
    clock.rate.inSourceTime(clock.speed),
  );
  final data = pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes);
  return (BytesBuilder(copy: false)
        ..add(
          wav16HeaderBytes(
            dataBytes: data.length,
            sampleRate: decoded.sampleRate,
            channels: decoded.channels,
          ),
        )
        ..add(data))
      .takeBytes();
}

/// What project [frames] play of [sound], as interleaved 16-bit PCM — what
/// a WAV holds and what the encoder takes — and silence wherever they run
/// past its end.
///
/// Each frame from the sample the mixer would start it at
/// ([ProjectFrameRate.frameToSample], rounded up), counted in the sound's
/// own time: [pace] is the project's rate as the source's clock counts it
/// ([ProjectFrameRate.inSourceTime]) — at 1001/1000 project frame f plays
/// source time f / rate × 1001/1000.
Int16List int16PcmOfFrames(
  ({Float32List samples, int channels, int sampleRate}) sound,
  ({int first, int count}) frames,
  ProjectFrameRate pace,
) {
  final channels = sound.channels;
  final start = pace.frameToSample(frames.first, sound.sampleRate) * channels;
  final end =
      pace.frameToSample(frames.first + frames.count, sound.sampleRate) *
      channels;
  final pcm = Int16List(end - start);
  final held = (sound.samples.length - start).clamp(0, pcm.length);
  for (var i = 0; i < held; i += 1) {
    pcm[i] = int16FromUnitSample(sound.samples[start + i]);
  }
  return pcm;
}
