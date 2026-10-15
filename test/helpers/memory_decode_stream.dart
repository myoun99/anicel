import 'dart:typed_data';

import 'package:anicel/src/services/audio/audio_decode_stream.dart';
import 'package:anicel/src/services/audio/audio_resampler_reference.dart';

/// [samples] — a whole sound already in hand — read on the way a decoder
/// reads one: what the fake decoders hand the conform pipeline.
final class MemoryDecodeStream implements AudioDecodeStream {
  MemoryDecodeStream(
    this._samples, {
    required this.channels,
    required this.sampleRate,
  });

  final Float32List _samples;

  @override
  final int channels;

  @override
  final int sampleRate;

  int _at = 0;

  /// Whether the pipeline let it go.
  bool closed = false;

  @override
  Float32List read(int frames) {
    final whole = channels <= 0 ? 0 : _samples.length ~/ channels * channels;
    final want = _at + frames * channels;
    final end = want < whole ? want : whole;
    final piece = Float32List.fromList(
      Float32List.sublistView(_samples, _at, end),
    );
    _at = end;
    return piece;
  }

  @override
  void close() => closed = true;
}

/// A "conversion" that hands every piece back as it came — for a test about
/// what gets decoded, not about the filter (the resampler has its own
/// parity pins).
final class UnchangedResampleStream implements AudioResampleStream {
  @override
  Float32List push(Float32List samples) => samples;

  @override
  Float32List finish() => Float32List(0);

  @override
  void close() {}
}
