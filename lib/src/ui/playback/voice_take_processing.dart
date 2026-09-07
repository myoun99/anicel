import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/audio_sync_settings.dart' show VoiceInputChannelMode;

/// A take after the capture chain (REC1-D): channel fold + baked gain,
/// plus whether anything hit the ceiling on the way.
class ProcessedVoiceTake {
  const ProcessedVoiceTake({
    required this.samples,
    required this.channels,
    required this.clipped,
  });

  final Float32List samples;
  final int channels;

  /// True when any post-gain sample reached the ceiling: digital clipping
  /// is about to be baked into a 16-bit file, and the take should say so.
  final bool clipped;
}

/// |v| at or above this counts as clipped — 16-bit full scale minus
/// rounding headroom, the level OBS's indicator lights at.
const double voiceClipThreshold = 0.999;

/// The linear factor for a dB gain (0 dB = 1.0).
double micGainFactor(int gainDb) => math.pow(10.0, gainDb / 20.0).toDouble();

/// Applies the capture chain to a finished take: [channelMode] folds the
/// device's channels (an interface's mono mic otherwise lands one-sided
/// stereo), then [gainDb] bakes in (the OBS model — the meter showed
/// post-gain, the file must match). Output samples clamp to ±1.0; the
/// clip flag reports any sample that needed it (or arrived at the
/// ceiling already — analog overload shows the same way).
ProcessedVoiceTake processVoiceTake({
  required Float32List samples,
  required int channels,
  required int gainDb,
  required VoiceInputChannelMode channelMode,
}) {
  if (channels <= 0) {
    return ProcessedVoiceTake(
      samples: samples,
      channels: channels,
      clipped: false,
    );
  }
  // A one-channel capture has nothing to fold.
  final fold = channels >= 2 ? channelMode : VoiceInputChannelMode.device;
  if (fold == VoiceInputChannelMode.device) {
    return gainDb == 0
        ? _clampedInPlace(samples, channels)
        : _gainedAllChannels(
            samples,
            channels: channels,
            factor: micGainFactor(gainDb),
          );
  }
  return _foldedToMono(
    samples,
    channels: channels,
    fold: fold,
    factor: micGainFactor(gainDb),
  );
}

/// The no-op chain (device channels, 0 dB) still has to CLAMP: a float
/// capture can hand us |v| > 1.0, and the take is about to be baked into
/// 16-bit. Returning those verbatim made "output clamps to +/-1.0" true
/// of every path except this one — and the one it was false of is the
/// default. Only a sample that actually needs it is written, so an
/// in-range take still passes through untouched.
ProcessedVoiceTake _clampedInPlace(Float32List samples, int channels) {
  var clipped = false;
  for (var index = 0; index < samples.length; index += 1) {
    final value = samples[index];
    if (value >= voiceClipThreshold) {
      clipped = true;
      if (value > 1.0) {
        samples[index] = 1.0;
      }
    } else if (value <= -voiceClipThreshold) {
      clipped = true;
      if (value < -1.0) {
        samples[index] = -1.0;
      }
    }
  }
  return ProcessedVoiceTake(
    samples: samples,
    channels: channels,
    clipped: clipped,
  );
}

/// Every channel kept, every sample gained.
///
/// ⛔The clamp is written out here and in [_foldedToMono] rather than
/// shared: this runs per SAMPLE and a take is millions of them, so a
/// helper would be a call — and a record allocation for the clipped
/// flag — on each. The two are the same arithmetic in the same order,
/// deliberately (a mirror, not a divergence); [_clampedInPlace] is the
/// third and differs only in writing back in place.
ProcessedVoiceTake _gainedAllChannels(
  Float32List samples, {
  required int channels,
  required double factor,
}) {
  final frames = samples.length ~/ channels;
  final out = Float32List(frames * channels);
  var clipped = false;
  for (var index = 0; index < out.length; index += 1) {
    var value = samples[index] * factor;
    if (value >= voiceClipThreshold) {
      if (value > 1.0) value = 1.0;
      clipped = true;
    } else if (value <= -voiceClipThreshold) {
      if (value < -1.0) value = -1.0;
      clipped = true;
    }
    out[index] = value;
  }
  return ProcessedVoiceTake(samples: out, channels: channels, clipped: clipped);
}

/// One channel out of the interface's several: the mix, the right, or
/// the left — the one-sided-mic fold (REC1-D).
ProcessedVoiceTake _foldedToMono(
  Float32List samples, {
  required int channels,
  required VoiceInputChannelMode fold,
  required double factor,
}) {
  final frames = samples.length ~/ channels;
  final out = Float32List(frames);
  var clipped = false;
  for (var frame = 0; frame < frames; frame += 1) {
    final base = frame * channels;
    var value = fold.pickFrame(samples, base, channels) * factor;
    if (value >= voiceClipThreshold) {
      if (value > 1.0) value = 1.0;
      clipped = true;
    } else if (value <= -voiceClipThreshold) {
      if (value < -1.0) value = -1.0;
      clipped = true;
    }
    out[frame] = value;
  }
  return ProcessedVoiceTake(samples: out, channels: 1, clipped: clipped);
}

/// The one value a frame folds to under a channel mode.
///
/// The TAKE folds with it ([_foldedToMono]) and the live METER folds with
/// it, which is what "the channel fold picks what the take will keep" says
/// out loud. `device` is not a fold — the take keeps every channel — so it
/// answers the first channel here and the meter states its own rule (the
/// loudest channel) beside this call.
extension VoiceInputChannelFold on VoiceInputChannelMode {
  /// The frame starting at [base] in an interleaved [samples] buffer of
  /// [channels], folded to one value.
  ///
  /// ⚠️Per FRAME, not per sample — the clamp beside the callers stays
  /// written out for exactly that reason. Statically dispatched (an
  /// extension method on an enum) and marked for inlining, so the fold
  /// costs no call in a release build.
  @pragma('vm:prefer-inline')
  double pickFrame(Float32List samples, int base, int channels) {
    switch (this) {
      case VoiceInputChannelMode.monoMix:
        var sum = 0.0;
        for (var channel = 0; channel < channels; channel += 1) {
          sum += samples[base + channel];
        }
        return sum / channels;
      case VoiceInputChannelMode.right:
        return samples[base + 1];
      case VoiceInputChannelMode.left || VoiceInputChannelMode.device:
        return samples[base];
    }
  }
}
