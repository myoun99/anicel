/// The Dart REFERENCE implementation of the native audio mixer (2B).
///
/// Like every other native hot loop in this project, the C has a Dart twin
/// that stays in the tree forever and is pinned byte-identical by tests —
/// so the mixer can never silently diverge on a platform nobody ran.
///
/// It is also the fallback: a device that opens but finds no native engine
/// still makes sound. Silence is never an acceptable outcome for audio the
/// way a stood-down rasterizer was acceptable for pixels.
///
/// **Positions are SAMPLES (per channel), never "frames"** — in this
/// codebase a frame is a picture. `ProjectFrameRate.frameToSample` is the
/// bridge between the two.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// One volume-envelope point (AUDIO-PRO R1) — mirrors the C
/// `qa_audio_envelope_key`: at [sample] (clip-local, from the clip's
/// start) the envelope passes [gain]. Linear between points, held past
/// the ends.
class AudioEnvelopePoint {
  const AudioEnvelopePoint({required this.sample, required this.gain});

  final int sample;
  final double gain;
}

/// One scheduled clip on the timeline — mirrors the C `qa_audio_clip`.
class AudioMixClip {
  const AudioMixClip({
    required this.sourceIndex,
    required this.startSample,
    required this.endSample,
    this.sourceOffset = 0,
    this.gain = 1.0,
    this.fadeInSamples = 0,
    this.fadeOutSamples = 0,
    this.panLeft = 1.0,
    this.panRight = 1.0,
    this.fadeCurve = 0,
    this.envelope = const [],
  });

  final int sourceIndex;

  /// Timeline position, inclusive.
  final int startSample;

  /// Timeline position, exclusive.
  final int endSample;

  /// Sample index into the source that [startSample] plays — the clip's
  /// trim.
  final int sourceOffset;

  final double gain;
  final int fadeInSamples;
  final int fadeOutSamples;

  /// Per-output-side pan factors, PRECOMPUTED here in Dart (see
  /// [equalPowerPanGains]) so the C never calls trig — a libm sin/cos can
  /// differ from Dart's by an ulp and break byte parity. Applied on a
  /// stereo bus only; unity leaves the mix untouched.
  final double panLeft;
  final double panRight;

  /// 0 = linear ramps (the historical shape), 1 = equal-power (sqrt).
  final int fadeCurve;

  /// The volume envelope, sorted by sample; empty = unity. The FFI layer
  /// flattens every clip's points into one shared array for the C.
  final List<AudioEnvelopePoint> envelope;

  /// This clip re-pointed at [sourceIndex]. NOTHING else changes.
  ///
  /// 🚨IT LIVES ON THE CLASS SO IT CANNOT BE HALF-COPIED. Two places
  /// re-point clips at a slot — the playback schedule's streaming windows
  /// and the export mix's — and each spelled all eleven fields itself.
  /// Pan, the fade curve and the volume envelope arrived with AUDIO-PRO R1
  /// and had to be added to both; a copy that forgets one is how a preview
  /// starts telling a small lie about the render.
  AudioMixClip pointedAt(int sourceIndex) => AudioMixClip(
    sourceIndex: sourceIndex,
    startSample: startSample,
    endSample: endSample,
    sourceOffset: sourceOffset,
    gain: gain,
    fadeInSamples: fadeInSamples,
    fadeOutSamples: fadeOutSamples,
    panLeft: panLeft,
    panRight: panRight,
    fadeCurve: fadeCurve,
    envelope: envelope,
  );
}

/// The COMPENSATED equal-power pan law: -1 (full left) .. +1 (full
/// right) to the two side factors, scaled so CENTER IS UNITY — sum of
/// squares constant at 2, hard pans reach √2 (+3 dB, the panned energy
/// concentrated in one speaker; the output stage clamps and the meter
/// shows it).
///
/// Center-unity is not a taste choice here: the platform-player fallback
/// cannot pan, so an uncompensated law would put center-panned sound
/// 3 dB quieter on the device path than on the fallback — the same file
/// at two levels depending on the path, the exact defect this program
/// exists to remove. Computed ONCE per clip here so both mixer
/// implementations consume identical doubles.
({double left, double right}) equalPowerPanGains(double pan) {
  final clamped = pan < -1.0 ? -1.0 : (pan > 1.0 ? 1.0 : pan);
  final angle = (clamped + 1.0) * math.pi / 4.0;
  return (
    left: math.cos(angle) * math.sqrt2,
    right: math.sin(angle) * math.sqrt2,
  );
}

/// The fade ramp's shape — mirrors the C `qa_audio_fade_ramp`. sqrt, not
/// sin, for the equal-power curve: IEEE 754 requires sqrt correctly
/// rounded, so C and Dart produce the same bits.
double audioFadeRamp(double ramp, int curve) {
  final clamped = ramp < 0.0 ? 0.0 : ramp;
  return curve == 1 ? math.sqrt(clamped) : clamped;
}

/// The envelope's value at [position] (clip-local samples): linear between
/// points, held past either end, 1.0 when there are none — mirrors the C
/// `qa_audio_envelope_at` expression for expression.
///
/// ↩️The platform players' sync asked the same law in FRAMES. Its own twin
/// drifted (it guarded a zero span with `<= 0`, this with `<= 0.0`), so the
/// two shared one generic fold until the sync went with the players
/// (2026-10-23); the mixer is the one asker again.
double audioEnvelopeAt(List<AudioEnvelopePoint> points, int position) {
  if (points.isEmpty) {
    return 1.0;
  }
  if (position <= points.first.sample) {
    return points.first.gain;
  }
  if (position >= points.last.sample) {
    return points.last.gain;
  }
  for (var index = 0; index < points.length - 1; index += 1) {
    final a = points[index];
    final b = points[index + 1];
    if (position < b.sample) {
      final span = (b.sample - a.sample).toDouble();
      if (span <= 0.0) {
        return b.gain;
      }
      final t = (position - a.sample) / span;
      return a.gain + (b.gain - a.gain) * t;
    }
  }
  return points.last.gain;
}

/// A block of decoded samples, interleaved by channel — mirrors the C
/// `qa_audio_source`.
///
/// [sourceStart] is the source-sample index that `samples[0]` holds, which
/// is what lets a STREAMED clip present a sliding window through the same
/// type a fully-resident one uses: residency is a policy the mixer never
/// sees.
class AudioMixSource {
  const AudioMixSource({
    required this.samples,
    required this.channels,
    this.sourceStart = 0,
  });

  final Float32List samples;
  final int channels;
  final int sourceStart;

  /// Samples per channel available from [sourceStart].
  int get length => channels <= 0 ? 0 : samples.length ~/ channels;
}

/// The clip's volume at one timeline position: gain × envelope × fade-in
/// ramp × fade-out ramp, the ramps through [audioFadeRamp] with the clip's
/// fade curve (0 linear, 1 equal-power).
///
/// ⚠️The multiplication order is UNCHANGED from the C `qa_audio_clip_volume`
/// — gain, envelope, fade-in, fade-out — which is what keeps the native
/// parity test byte-equal. ↩️The fold stood apart for the sync's frames as
/// well (round-8 audit, 2026-09-06), and came back with it gone.
///
/// Deliberately NOT clamped to [0, 1] — see the note on the C twin: the old
/// preview path clamped because a platform player's volume tops out at 1.0
/// while export applied gain exactly, so a boosted clip sounded different
/// in preview than in the rendered file. The bus has headroom; clipping is
/// the output stage's job.
double audioClipVolumeAt(AudioMixClip clip, int positionSample) {
  final position = positionSample - clip.startSample;
  final remaining = clip.endSample - positionSample;
  var volume = clip.gain;
  volume *= audioEnvelopeAt(clip.envelope, position);
  if (clip.fadeInSamples > 0 && position < clip.fadeInSamples) {
    volume *= audioFadeRamp(position / clip.fadeInSamples, clip.fadeCurve);
  }
  if (clip.fadeOutSamples > 0 && remaining < clip.fadeOutSamples) {
    volume *= audioFadeRamp(remaining / clip.fadeOutSamples, clip.fadeCurve);
  }
  return volume;
}

/// Which source channel feeds [outChannel]: a mono source feeds every
/// output channel, anything wider maps straight across and holds its last
/// channel when the output is wider.
int audioSourceChannelFor(int sourceChannels, int outChannel) {
  if (sourceChannels <= 1) {
    return 0;
  }
  return outChannel < sourceChannels ? outChannel : sourceChannels - 1;
}

/// Mixes [sampleCount] samples starting at timeline sample [startSample]
/// into an interleaved DOUBLE bus of `sampleCount * outChannels`.
///
/// The bus is double, not float, for the same two reasons the C twin gives:
/// summing in 64-bit avoids rounding once per clip in an SE-heavy scene
/// (what Pro Tools does), and it makes the two implementations bit-equal
/// for free — Dart has only 64-bit doubles, so a float bus would round in C
/// at points this side cannot reproduce.
Float64List mixAudioReference({
  required List<AudioMixClip> clips,
  required List<AudioMixSource> sources,
  required int startSample,
  required int sampleCount,
  required int outChannels,
  Float64List? into,
}) {
  final total = sampleCount <= 0 || outChannels <= 0
      ? 0
      : sampleCount * outChannels;
  final out = into ?? Float64List(total);
  for (var index = 0; index < out.length; index += 1) {
    out[index] = 0;
  }
  if (total == 0 || clips.isEmpty || sources.isEmpty) {
    return out;
  }

  final blockEnd = startSample + sampleCount;
  for (final clip in clips) {
    if (clip.sourceIndex < 0 || clip.sourceIndex >= sources.length) {
      continue;
    }
    final source = sources[clip.sourceIndex];
    if (source.channels <= 0 || source.length <= 0) {
      continue;
    }

    final from = clip.startSample > startSample ? clip.startSample : startSample;
    final to = clip.endSample < blockEnd ? clip.endSample : blockEnd;
    for (var position = from; position < to; position += 1) {
      final sourceIndex = clip.sourceOffset + (position - clip.startSample);
      final offset = sourceIndex - source.sourceStart;
      if (offset < 0 || offset >= source.length) {
        continue; // Outside the available window: silence, never a wait.
      }
      final volume = audioClipVolumeAt(clip, position);
      final frame = offset * source.channels;
      final destination = (position - startSample) * outChannels;
      for (var channel = 0; channel < outChannels; channel += 1) {
        final sourceChannel = audioSourceChannelFor(source.channels, channel);
        // Pan factors apply on a STEREO bus only; multiplication order
        // mirrors the C exactly (sample × volume × factor).
        final factor = outChannels == 2
            ? (channel == 0 ? clip.panLeft : clip.panRight)
            : 1.0;
        out[destination + channel] +=
            source.samples[frame + sourceChannel] * volume * factor;
      }
    }
  }
  return out;
}

/// Output stage: the mix bus to 32-bit float device samples.
Float32List audioBusToFloat(Float64List bus, {Float32List? into}) {
  final out = into ?? Float32List(bus.length);
  for (var index = 0; index < bus.length; index += 1) {
    out[index] = bus[index];
  }
  return out;
}

// 🪦`audioBusToInt16` — the mix bus to 16-bit samples — was one of three
// loops over [int16FromUnitSample]; the bus goes through `int16PcmOf` now,
// beside the scale it applies (09-25).
