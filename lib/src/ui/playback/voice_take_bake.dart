import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/on_a_worker.dart';
import '../../models/audio_pcm_scale.dart' show int16PcmOf;
import '../../models/audio_sync_settings.dart' show VoiceInputChannelMode;
import '../../models/project_frame_rate.dart';
import '../../services/audio/wav16_header.dart' show wav16Bytes;
import 'voice_take_processing.dart';

/// The RNNoise pass a take is suppressed by: its samples back suppressed,
/// or null — declined (another rate, an empty take), the take kept raw.
typedef VoiceDenoiser =
    Float32List? Function(Float32List samples, int channels, int sampleRate);

/// A finished take, trimmed, and what it is baked by: suppressed where
/// [denoiser] is given, through the capture chain at [gainDb] and
/// [channelMode], cut to [windowFrames] of [rate] where it has a punch
/// window.
typedef VoiceTakeToBake = ({
  Float32List samples,
  int channels,
  int sampleRate,
  int gainDb,
  VoiceInputChannelMode channelMode,
  VoiceDenoiser? denoiser,
  int? windowFrames,
  ProjectFrameRate rate,
});

/// A take baked: the WAV it is written as, the whole frames it covers —
/// its punch window's at most — and whether anything reached the ceiling.
typedef BakedVoiceTake = ({Uint8List wav, int lengthFrames, bool clipped});

/// [take] baked on a worker ([onAWorker]) — what a take placed becomes.
///
/// 🚨OFF THE THREAD THAT DRAWS (board a-voice-take-is-denoised-on-the-ui-
/// isolate, 11-17): the take's whole length runs through RNNoise's FFT and
/// network, 480 samples at a time, then the fold, the gain and the 16-bit
/// write — seconds of a long take, which the screen stood through when
/// recording stopped. The road a long sound's windows took off it.
///
/// In a function of its own: a closure carries its whole scope, and this
/// one holds the take alone.
Future<BakedVoiceTake> bakeVoiceTakeOnAWorker(VoiceTakeToBake take) =>
    onAWorker(() => _bakeVoiceTake(take));

BakedVoiceTake _bakeVoiceTake(VoiceTakeToBake take) {
  var samples = take.samples;
  // Suppression first, on the trimmed raw capture (per channel, the
  // OBS filter order) — the RNNoise round. A declined pass (another rate,
  // an empty take) keeps the raw take: recording never fails because the
  // denoiser said no.
  final denoiser = take.denoiser;
  if (denoiser != null) {
    samples = denoiser(samples, take.channels, take.sampleRate) ?? samples;
  }
  // The capture chain (REC1-D): channel fold + baked gain, applied to
  // the trimmed take — the file holds exactly what the meter showed.
  final processed = processVoiceTake(
    samples: samples,
    channels: take.channels,
    gainDb: take.gainDb,
    channelMode: take.channelMode,
  );
  samples = processed.samples;
  final channels = processed.channels;
  // Whole frames covering the take, so the block window matches what
  // was actually said (min 1 — a sub-frame take still needs a cell).
  var lengthFrames = math.max(
    1,
    take.rate.framesCoveringExactSeconds(
      samples.length ~/ channels,
      take.sampleRate,
    ),
  );
  final window = take.windowFrames;
  if (window != null && window >= 1 && lengthFrames > window) {
    lengthFrames = window;
    // The file carries the window alone — capture past the punch-out
    // is context the performer heard, not part of the take.
    final windowFloats =
        take.rate.frameToSample(window, take.sampleRate) * channels;
    if (windowFloats > 0 && windowFloats < samples.length) {
      samples = Float32List.sublistView(samples, 0, windowFloats);
    }
  }
  // A WAV, the file every sound door reads ([wav16Bytes]) — 🪦it was the
  // conform encoder's output, and no decoder reads that (유저 09-25:
  // 「녹음중에는 파형 보이는데 녹음끝내면 사라지네」, card `F-178` ⑥).
  return (
    wav: wav16Bytes(
      int16PcmOf(samples),
      sampleRate: take.sampleRate,
      channels: channels,
    ),
    lengthFrames: lengthFrames,
    clipped: processed.clipped,
  );
}
