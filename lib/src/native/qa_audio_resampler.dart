// The engine's Rust library carries the resampler (rust/src/lib.rs,
// native/audio_mix), and its names are found in that code asset — no
// library opened, no path named. It runs once at import (the conform) or
// where the device's rate is not the project's, never on the device thread.
@DefaultAsset(gpuEngineAsset)
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../services/audio/audio_resample_stream.dart';
import 'gpu_engine_asset.dart';
import 'native_scratch.dart';

@Native<Int64 Function(Int64, Int32, Int32)>(
  symbol: 'qa_audio_resample_frames',
)
external int _resampleFrames(int inputFrames, int inputRate, int outputRate);

@Native<Int32 Function(Int32, Int32, Double, Double)>(
  symbol: 'qa_audio_resample_taps',
)
external int _resampleTaps(
  int inputRate,
  int outputRate,
  double stopbandDb,
  double bandwidth,
);

@Native<
  Int64 Function(
    Pointer<Float>,
    Int64,
    Int32,
    Int32,
    Int32,
    Double,
    Double,
    Pointer<Float>,
  )
>(symbol: 'qa_audio_resample')
external int _resample(
  Pointer<Float> samples,
  int inputFrames,
  int channels,
  int inputRate,
  int outputRate,
  double stopbandDb,
  double bandwidth,
  Pointer<Float> out,
);

@Native<Pointer<Void> Function(Int32, Int32, Int32, Double, Double)>(
  symbol: 'qa_audio_resampler_open',
)
external Pointer<Void> _open(
  int channels,
  int inputRate,
  int outputRate,
  double stopbandDb,
  double bandwidth,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Float>, Int64)>(
  symbol: 'qa_audio_resampler_push',
)
external int _push(Pointer<Void> resampler, Pointer<Float> samples, int frames);

@Native<Void Function(Pointer<Void>)>(symbol: 'qa_audio_resampler_end')
external void _end(Pointer<Void> resampler);

@Native<Int64 Function(Pointer<Void>)>(symbol: 'qa_audio_resampler_ready')
external int _ready(Pointer<Void> resampler);

@Native<Int64 Function(Pointer<Void>, Pointer<Float>, Int64)>(
  symbol: 'qa_audio_resampler_pull',
)
external int _pull(Pointer<Void> resampler, Pointer<Float> out, int capacity);

@Native<Int64 Function(Pointer<Void>)>(symbol: 'qa_audio_resampler_held')
external int _held(Pointer<Void> resampler);

@Native<Void Function(Pointer<Void>)>(symbol: 'qa_audio_resampler_close')
external void _close(Pointer<Void> resampler);

/// Converts [samples] to [outputRate] through the engine's polyphase
/// resampler.
///
/// Equal rates return the input UNCHANGED — the caller should not even
/// reach here in that case, but making it explicit keeps the bit-exact
/// promise from depending on the caller remembering.
Float32List resampleAudio({
  required Float32List samples,
  required int channels,
  required int inputRate,
  required int outputRate,
  double stopbandDb = defaultResamplerStopbandDb,
  double bandwidth = defaultResamplerBandwidth,
}) {
  if (channels <= 0 || inputRate <= 0 || outputRate <= 0) {
    return Float32List(0);
  }
  if (inputRate == outputRate) {
    return samples;
  }
  final inputFrames = samples.length ~/ channels;
  if (inputFrames <= 0) {
    return Float32List(0);
  }
  final outputFrames = _resampleFrames(inputFrames, inputRate, outputRate);
  if (outputFrames <= 0) {
    return Float32List(0);
  }

  final input = calloc<Float>(samples.length);
  final output = calloc<Float>(outputFrames * channels);
  try {
    input.asTypedList(samples.length).setAll(0, samples);
    final written = _resample(
      input,
      inputFrames,
      channels,
      inputRate,
      outputRate,
      stopbandDb,
      bandwidth,
      output,
    );
    final result = Float32List(written * channels);
    result.setAll(0, output.asTypedList(written * channels));
    return result;
  } finally {
    calloc.free(output);
    calloc.free(input);
  }
}

/// How many input frames either side of its own instant an output frame of
/// [resampleAudio] reads — 0 for equal rates. A window cut from inside a
/// sound and converted alone is exact only that far in from its edges:
/// past them the filter reads silence where the sound went on.
int resampleReach({
  required int inputRate,
  required int outputRate,
  double stopbandDb = defaultResamplerStopbandDb,
  double bandwidth = defaultResamplerBandwidth,
}) {
  final taps = _resampleTaps(inputRate, outputRate, stopbandDb, bandwidth);
  if (taps <= 0) {
    return 0;
  }
  // The filter runs at the rate both meet at, interpolation × the input's,
  // centred on the output's instant: half its length either side, which
  // is the farthest any output reads (resample.rs, `Design::run`).
  final interpolation = outputRate ~/ outputRate.gcd(inputRate);
  final half = (taps - 1) ~/ 2;
  return (half + interpolation - 1) ~/ interpolation;
}

/// A conversion of [channels] from [inputRate] to [outputRate] fed a piece
/// at a time through the engine's resampler, by the conform's filter — the
/// loop [resampleAudio] runs, so the pieces' outputs are its outputs bit
/// for bit. The rates unequal: equal ones skip the filter.
QaAudioResampleStream openAudioResampler({
  required int channels,
  required int inputRate,
  required int outputRate,
}) {
  final handle = _open(
    channels,
    inputRate,
    outputRate,
    defaultResamplerStopbandDb,
    defaultResamplerBandwidth,
  );
  if (handle == nullptr) {
    throw ArgumentError(
      'no conversion of $channels channels from $inputRate to $outputRate',
    );
  }
  return QaAudioResampleStream._(handle, channels);
}

/// The engine's resampler fed a piece at a time ([openAudioResampler]).
final class QaAudioResampleStream implements AudioResampleStream {
  QaAudioResampleStream._(this._handle, this._channels);

  Pointer<Void> _handle;
  final int _channels;

  /// Input frames it holds now — for the tests that tell a conversion that
  /// lets go of its input from one that keeps the whole sound.
  int get heldFrames => _held(_handle);

  /// ⚠️One for the isolate, not one per conversion: nothing here suspends
  /// between filling it and copying out of it, a piece in or a piece out.
  static final NativeScratch<Float> _room = NativeScratch<Float>(
    (count) => calloc<Float>(count),
    bytesPerElement: sizeOf<Float>(),
  );

  @override
  Float32List push(Float32List samples) {
    final frames = samples.length ~/ _channels;
    if (frames > 0) {
      final input = _room.ensure(frames * _channels);
      input
          .asTypedList(frames * _channels)
          .setAll(0, Float32List.sublistView(samples, 0, frames * _channels));
      if (_push(_handle, input, frames) == 0) {
        throw StateError('the engine resampler could not take the piece');
      }
    }
    return _pulled();
  }

  @override
  Float32List finish() {
    _end(_handle);
    return _pulled();
  }

  Float32List _pulled() {
    final ready = _ready(_handle);
    if (ready <= 0) {
      return Float32List(0);
    }
    final out = _room.ensure(ready * _channels);
    final written = _pull(_handle, out, ready);
    // Copied out: the room is the next piece's.
    return Float32List.fromList(out.asTypedList(written * _channels));
  }

  @override
  void close() {
    if (_handle != nullptr) {
      _close(_handle);
      _handle = nullptr;
    }
  }
}
