/// Sample-rate conversion (audio program 2B) — Dart REFERENCE.
///
/// A conform has to land at the project's sample rate, and 44.1k → 48k
/// means computing sample values at instants that do not exist in the
/// source: the ratio is 147:160, so almost every output falls between two
/// inputs. Linear interpolation gets about −30 dB of alias rejection,
/// which is audible as dullness and grit. Professional converters all use
/// the same thing instead — a windowed-sinc FIR run in polyphase form —
/// and reach −100 dB or better.
///
/// **Linear phase, and the delay removed exactly.** A symmetric FIR delays
/// everything by a constant `(taps − 1) / 2`. At 4096 taps and 48 kHz that
/// is 42.6 ms — MORE than a frame at 24fps. Left uncompensated, every
/// resampled clip would sit a frame late, which is precisely the defect
/// this whole program exists to remove. Because the delay is constant it
/// cancels exactly, and [resampleAudio] does that in the index arithmetic
/// rather than by trimming afterwards, so nothing depends on the delay
/// happening to be a whole number of output samples.
///
/// Minimum phase would trade that away: it has no pre-ringing, but its
/// group delay varies with frequency, so low and high content shift by
/// different amounts and no single correction fixes both. For a program
/// about sync, a delay that cancels exactly beats one that is merely
/// small.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Stopband attenuation target in dB. 120 puts both the aliasing and the
/// pre-ringing more than 20 dB below the quantization noise of a 16-bit
/// source — under the material's own noise floor.
const double defaultResamplerStopbandDb = 120.0;

/// How much of the available band stays flat, as a fraction of the lower
/// of the two Nyquist limits. The remainder is the transition band.
///
/// 0.90 keeps everything below 19.8 kHz flat on a 44.1k → 48k conform and
/// spends 19.8–22.05 kHz rolling off. Pushing this toward 1.0 costs filter
/// length quadratically for band nobody can hear.
const double defaultResamplerBandwidth = 0.90;

/// Ceiling on the prototype length, so a pathological rate pair (44100 →
/// 44101 shares no factors and would ask for billions of taps) degrades
/// into a merely-good filter instead of hanging. Every standard pair —
/// 8k, 16k, 22.05k, 32k, 44.1k, 48k, 96k — lands far below this.
const int maxResamplerTaps = 131071;

/// The result of a conversion, plus what it took to get there — exposed so
/// tests can assert the filter is the one that was asked for.
class ResampledAudio {
  const ResampledAudio({
    required this.samples,
    required this.channels,
    required this.sampleRate,
    required this.taps,
    required this.beta,
    required this.passthrough,
  });

  /// Interleaved by channel.
  final Float32List samples;
  final int channels;
  final int sampleRate;

  /// Prototype filter length (odd, symmetric). 0 when [passthrough].
  final int taps;

  /// The Kaiser shape parameter the stopband target produced.
  final double beta;

  /// True when the source was already at the target rate and the samples
  /// were handed back untouched.
  final bool passthrough;

  int get length => channels <= 0 ? 0 : samples.length ~/ channels;
}

int _gcd(int a, int b) {
  var x = a < 0 ? -a : a;
  var y = b < 0 ? -b : b;
  while (y != 0) {
    final t = x % y;
    x = y;
    y = t;
  }
  return x;
}

/// Modified Bessel function of the first kind, order 0 — the Kaiser
/// window's kernel.
///
/// Fixed termination (relative epsilon, hard iteration cap) so the C twin
/// runs the identical number of terms. A loop that stopped "when it feels
/// converged" would be a parity hazard.
double besselI0(double x) {
  final half = x / 2.0;
  var term = 1.0;
  var sum = 1.0;
  for (var k = 1; k <= 64; k += 1) {
    final ratio = half / k;
    term *= ratio * ratio;
    sum += term;
    if (term < sum * 1e-16) {
      break;
    }
  }
  return sum;
}

/// Kaiser β for a stopband attenuation of [stopbandDb] — the standard
/// empirical fit.
double kaiserBeta(double stopbandDb) {
  if (stopbandDb > 50.0) {
    return 0.1102 * (stopbandDb - 8.7);
  }
  if (stopbandDb >= 21.0) {
    return 0.5842 * math.pow(stopbandDb - 21.0, 0.4).toDouble() +
        0.07886 * (stopbandDb - 21.0);
  }
  return 0.0;
}

double _sinc(double x) {
  if (x == 0.0) {
    return 1.0;
  }
  final pix = math.pi * x;
  return math.sin(pix) / pix;
}

/// Builds the prototype lowpass: a sinc at [cutoff] (normalized to the
/// interpolated rate) under a Kaiser window, with DC gain [interpolation]
/// to make up for the zero-stuffing.
Float64List buildResamplerKernel({
  required int taps,
  required double cutoff,
  required double beta,
  required int interpolation,
}) {
  final kernel = Float64List(taps);
  final center = (taps - 1) / 2.0;
  final denominator = besselI0(beta);
  for (var index = 0; index < taps; index += 1) {
    final offset = index - center;
    final ratio = offset / center;
    final inside = 1.0 - ratio * ratio;
    final window = inside <= 0.0
        ? 0.0
        : besselI0(beta * math.sqrt(inside)) / denominator;
    kernel[index] = 2.0 * cutoff * _sinc(2.0 * cutoff * offset) * window *
        interpolation;
  }
  return kernel;
}

/// A conversion fed a piece at a time — what the next piece needs of the
/// ones before it, carried across. Both resamplers answer it: the Dart
/// reference ([AudioResampleStreamReference]) and the C twin
/// (`QaAudioNativeResampling.openResampler`), bit for bit alike.
///
/// 🚨★★★**THE PIECES' OUTPUTS ARE THE WHOLE CONVERSION'S** (user
/// 2026-10-10, board long-sound-conform-memory-Q1: 「지금 한다 — 전
/// 플랫폼」). A long sound is conformed as the decoder hands it back, so it
/// is never held whole — and an output frame reads the inputs it reads
/// either way, the same taps in the same order. [resampleAudioReference] is
/// the same loop over input that has all arrived.
abstract interface class AudioResampleStream {
  /// Takes [samples] — whole interleaved frames — and answers every output
  /// frame they complete.
  Float32List push(Float32List samples);

  /// Answers the rest, once nothing more comes.
  Float32List finish();

  /// Lets go of what the conversion holds.
  void close();
}

/// What a conversion between two rates runs: its polyphase geometry and the
/// prototype's taps — the C's `qa_audio_resample_design`.
final class _ResamplerDesign {
  _ResamplerDesign._({
    required this.interpolation,
    required this.decimation,
    required this.taps,
    required this.beta,
    required this.kernel,
  }) : halfLength = (taps - 1) ~/ 2;

  /// The design for [inputRate] → [outputRate]; both positive and unequal.
  factory _ResamplerDesign.of({
    required int inputRate,
    required int outputRate,
    required double stopbandDb,
    required double bandwidth,
  }) {
    final divisor = _gcd(inputRate, outputRate);
    final interpolation = outputRate ~/ divisor; // L
    final decimation = inputRate ~/ divisor; // M
    final larger = interpolation > decimation ? interpolation : decimation;

    // Everything is normalized to the INTERPOLATED rate (L × inputRate).
    // The lower of the two Nyquist limits sits at 0.5 / larger; the passband
    // stops short of it and the transition band covers the rest.
    final nyquist = 0.5 / larger;
    final passbandEdge = nyquist * bandwidth;
    final transition = nyquist - passbandEdge;
    final cutoff = (passbandEdge + nyquist) / 2.0;
    final beta = kaiserBeta(stopbandDb);

    // Length comes from the Kaiser design formula, NOT a fixed multiple of
    // the ratio. Sizing it as a multiple looks reasonable until a simple
    // ratio arrives: 48k → 24k has larger = 2, which bought 65 taps and only
    // 93 dB of rejection — a 15 kHz source folding back to an audible 9 kHz
    // tone that was never played. The transition band is what sets the
    // length, and it does not get easier just because the ratio is tidy.
    final estimated = transition <= 0
        ? maxResamplerTaps
        : ((stopbandDb - 8.0) / (2.285 * 2.0 * math.pi * transition)).ceil();
    var taps = estimated < 15 ? 15 : estimated;
    if (taps > maxResamplerTaps) {
      taps = maxResamplerTaps;
    }
    // Odd, so the centre lands ON a sample and the group delay is an exact
    // integer at the interpolated rate — which is what lets the delay cancel
    // exactly rather than approximately.
    if (taps.isEven) {
      taps += 1;
    }
    return _ResamplerDesign._(
      interpolation: interpolation,
      decimation: decimation,
      taps: taps,
      beta: beta,
      kernel: buildResamplerKernel(
        taps: taps,
        cutoff: cutoff,
        beta: beta,
        interpolation: interpolation,
      ),
    );
  }

  final int interpolation;
  final int decimation;
  final int taps;
  final int halfLength;
  final double beta;
  final Float64List kernel;

  /// One past the last output frame this design can write from [total] input
  /// frames: every one there is once the input has [ended], and before that
  /// only those whose every input has arrived.
  int readyEnd(int total, {required bool ended}) {
    final limit = total <= 0 ? 0 : (total * interpolation) ~/ decimation;
    if (ended) {
      return limit;
    }
    // An output reads back from its base frame, (frame × M + half) / L, so
    // it is complete once that frame has arrived: frame × M + half < total
    // × L.
    final reach = total * interpolation - halfLength;
    final complete = reach <= 0 ? 0 : (reach + decimation - 1) ~/ decimation;
    return complete < limit ? complete : limit;
  }

  /// [count] output frames from frame [from], read out of [input].
  ///
  /// ⚠️What the caller promises: every input those outputs read from the
  /// input's first frame on is held, and while more input may come, none
  /// reads past its total ([readyEnd]). An input past the end is skipped,
  /// which is right only at the sound's end.
  Float32List run(_HeldInput input, {required int from, required int count}) {
    final (samples: held, :channels, :first, :total) = input;
    final out = Float32List(count * channels);
    for (var at = 0; at < count; at += 1) {
      // The + halfLength is the delay compensation: it centres the filter on
      // the output instant, so the result carries NO net time shift. Doing
      // it here rather than trimming later means it never has to be a whole
      // number of output samples.
      final position = (from + at) * decimation + halfLength;
      final phase = position % interpolation;
      final base = position ~/ interpolation;

      for (var channel = 0; channel < channels; channel += 1) {
        var sum = 0.0;
        var tap = phase;
        var source = base;
        // Walking one polyphase branch: tap strides by L while the source
        // index walks backwards. Once source goes below what is held every
        // later one does too, so the loop ends there; a source past the END
        // is merely skipped, since the branch may still reach back into
        // range.
        while (tap < taps && source >= first) {
          if (source < total) {
            sum += kernel[tap] * held[(source - first) * channels + channel];
          }
          tap += interpolation;
          source -= 1;
        }
        out[at * channels + channel] = sum;
      }
    }
    return out;
  }
}

/// Input frames [first, total) of a sound — its frames from [first] on,
/// [total] of them so far — interleaved by [channels] at the front of
/// [samples].
typedef _HeldInput = ({
  Float32List samples,
  int channels,
  int first,
  int total,
});

/// The Dart reference's [AudioResampleStream] — the C's
/// `qa_audio_resampler`, line for line.
final class AudioResampleStreamReference implements AudioResampleStream {
  /// A conversion of [channels] from [inputRate] to [outputRate] through the
  /// conform's filter: all positive, the rates unequal — equal ones skip the
  /// filter (see [resampleAudioReference]).
  factory AudioResampleStreamReference({
    required int channels,
    required int inputRate,
    required int outputRate,
  }) {
    if (channels <= 0 ||
        inputRate <= 0 ||
        outputRate <= 0 ||
        inputRate == outputRate) {
      throw ArgumentError(
        'no conversion of $channels channels from $inputRate to $outputRate',
      );
    }
    return AudioResampleStreamReference._(
      channels,
      _ResamplerDesign.of(
        inputRate: inputRate,
        outputRate: outputRate,
        stopbandDb: defaultResamplerStopbandDb,
        bandwidth: defaultResamplerBandwidth,
      ),
    );
  }

  AudioResampleStreamReference._(this.channels, this._design);

  final int channels;
  final _ResamplerDesign _design;

  /// Input frames [_first, _first + _heldFrames), interleaved, at the front
  /// of [_held].
  Float32List _held = Float32List(0);
  int _first = 0;
  int _heldFrames = 0;

  /// The next output frame.
  int _next = 0;
  bool _ended = false;

  /// Input frames it holds now — for the tests that tell a conversion that
  /// lets go of its input from one that keeps the whole sound.
  int get heldFrames => _heldFrames;

  @override
  Float32List push(Float32List samples) {
    if (_ended) {
      throw StateError('the input has ended');
    }
    _letGo();
    final frames = samples.length ~/ channels;
    final wanted = (_heldFrames + frames) * channels;
    if (wanted > _held.length) {
      var capacity = _held.isEmpty ? 4096 * channels : _held.length;
      while (capacity < wanted) {
        capacity *= 2;
      }
      _held = Float32List(capacity)
        ..setRange(0, _heldFrames * channels, _held);
    }
    _held.setRange(_heldFrames * channels, wanted, samples);
    _heldFrames += frames;
    return _pull();
  }

  @override
  Float32List finish() {
    _ended = true;
    return _pull();
  }

  @override
  void close() {
    _held = Float32List(0);
    _heldFrames = 0;
  }

  /// Lets go of the held input no output still to come reads: output frame
  /// f reads back to input (f × M + half − taps) / L + 1.
  void _letGo() {
    final reach =
        _next * _design.decimation +
        _design.halfLength -
        _design.taps +
        _design.interpolation;
    final lowest = reach <= 0 ? 0 : reach ~/ _design.interpolation;
    var drop = lowest - _first;
    if (drop > _heldFrames) {
      drop = _heldFrames;
    }
    if (drop <= 0) {
      return;
    }
    _held.setRange(
      0,
      (_heldFrames - drop) * channels,
      _held,
      drop * channels,
    );
    _heldFrames -= drop;
    _first += drop;
  }

  Float32List _pull() {
    final end = _design.readyEnd(_first + _heldFrames, ended: _ended);
    final count = end > _next ? end - _next : 0;
    final out = _design.run(
      (
        samples: _held,
        channels: channels,
        first: _first,
        total: _first + _heldFrames,
      ),
      from: _next,
      count: count,
    );
    _next += count;
    return out;
  }
}

/// Converts [samples] from [inputRate] to [outputRate].
///
/// Equal rates return the input UNTOUCHED — bit-exact, no filter, no
/// rounding. Most SE libraries and dialogue are already at 44.1k or 48k,
/// so this is the common path, and it costing nothing is the point.
ResampledAudio resampleAudioReference({
  required Float32List samples,
  required int channels,
  required int inputRate,
  required int outputRate,
  double stopbandDb = defaultResamplerStopbandDb,
  double bandwidth = defaultResamplerBandwidth,
}) {
  if (channels <= 0 || inputRate <= 0 || outputRate <= 0) {
    return ResampledAudio(
      samples: Float32List(0),
      channels: channels < 0 ? 0 : channels,
      sampleRate: outputRate < 0 ? 0 : outputRate,
      taps: 0,
      beta: 0,
      passthrough: false,
    );
  }
  if (inputRate == outputRate) {
    return ResampledAudio(
      samples: samples,
      channels: channels,
      sampleRate: outputRate,
      taps: 0,
      beta: 0,
      passthrough: true,
    );
  }

  final design = _ResamplerDesign.of(
    inputRate: inputRate,
    outputRate: outputRate,
    stopbandDb: stopbandDb,
    bandwidth: bandwidth,
  );
  final inputFrames = samples.length ~/ channels;
  final out = design.run(
    (samples: samples, channels: channels, first: 0, total: inputFrames),
    from: 0,
    count: design.readyEnd(inputFrames, ended: true),
  );

  return ResampledAudio(
    samples: out,
    channels: channels,
    sampleRate: outputRate,
    taps: design.taps,
    beta: design.beta,
    passthrough: false,
  );
}
