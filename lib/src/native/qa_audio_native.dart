import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../services/audio/audio_mixer_reference.dart';
import '../services/audio/audio_resampler_reference.dart';
import 'qa_engine_abi.dart';

/// Whether [library] lays the audio structs out byte-for-byte the way
/// this Dart build does.
///
/// Struct-layout paranoia, and the audio side has the sharpest version of
/// it: if the two sides disagree on a single byte, every field read is
/// garbage — and garbage in an audio buffer is a loud noise through
/// someone's headphones, not a wrong pixel.
///
/// It lives here because this file DECLARES the structs, and it is public
/// because [QaAudioDevice] passes those same structs to the same binary
/// on the path that actually reaches a speaker. Both must call it; the
/// roster test in `qa_engine_abi_test.dart` fails if one stops.
bool qaAudioStructLayoutsMatch(DynamicLibrary library) {
  int sizeOfSymbol(String name) =>
      library.lookupFunction<Int32 Function(), int Function()>(name).call();
  try {
    return sizeOfSymbol('qa_audio_clip_sizeof') ==
            sizeOf<QaAudioClipStruct>() &&
        sizeOfSymbol('qa_audio_source_sizeof') ==
            sizeOf<QaAudioSourceStruct>() &&
        sizeOfSymbol('qa_audio_envelope_key_sizeof') ==
            sizeOf<QaAudioEnvelopeKeyStruct>();
  } on Object {
    return false;
  }
}

/// FFI binding for the native audio mixer (2B).
///
/// Deliberately a SEPARATE loader from [QaNativeEngine]: the mixer is a
/// different subsystem with a different lifetime — in production the C runs
/// on the device's realtime thread, where Dart never goes. What this class
/// binds is the verification and fallback surface: the parity tests drive
/// both implementations through it, and a device that comes up without a
/// native engine still gets sound out of the Dart reference.
///
/// Absence is graceful everywhere, exactly like the raster engine: a
/// missing symbol or a layout disagreement stands the native path down
/// rather than reading garbage.
final class QaAudioNative {
  QaAudioNative._(
    this._mix,
    this._busToFloat,
    this._busToInt16,
    this._resample,
    this._resampleFrames,
    this._denoise,
  );

  final void Function(
    Pointer<QaAudioClipStruct>,
    int,
    Pointer<QaAudioSourceStruct>,
    int,
    Pointer<QaAudioEnvelopeKeyStruct>,
    int,
    int,
    int,
    int,
    Pointer<Double>,
  )
  _mix;
  final void Function(Pointer<Double>, int, Pointer<Float>) _busToFloat;
  final void Function(Pointer<Double>, int, Pointer<Int16>) _busToInt16;
  final int Function(
    Pointer<Float>,
    int,
    int,
    int,
    int,
    double,
    double,
    Pointer<Float>,
  )
  _resample;
  final int Function(int, int, int) _resampleFrames;
  final int Function(Pointer<Float>, int, int, int) _denoise;

  static QaAudioNative? _instance;
  static bool _tried = false;

  /// Test hook: force the Dart reference path even when a binary loads.
  /// (Where the binary IS lives in [debugQaEngineLibraryPathOverride] —
  /// one switch for every loader.)
  static bool debugForceDartFallback = false;

  static void debugResetForTests() {
    _instance = null;
    _tried = false;
  }

  /// The native mixer, or null when none is available (Dart reference
  /// then carries playback).
  static QaAudioNative? get instance {
    if (debugForceDartFallback) {
      return null;
    }
    if (!_tried) {
      _tried = true;
      _instance = _load();
    }
    return _instance;
  }

  static QaAudioNative? _load() {
    final library = openQaEngineLibrary();
    if (library == null || !qaAudioStructLayoutsMatch(library)) {
      return null;
    }
    try {
      return QaAudioNative._(
        library.lookupFunction<
          Void Function(
            Pointer<QaAudioClipStruct>,
            Int32,
            Pointer<QaAudioSourceStruct>,
            Int32,
            Pointer<QaAudioEnvelopeKeyStruct>,
            Int32,
            Int64,
            Int32,
            Int32,
            Pointer<Double>,
          ),
          void Function(
            Pointer<QaAudioClipStruct>,
            int,
            Pointer<QaAudioSourceStruct>,
            int,
            Pointer<QaAudioEnvelopeKeyStruct>,
            int,
            int,
            int,
            int,
            Pointer<Double>,
          )
        >('qa_audio_mix'),
        library.lookupFunction<
          Void Function(Pointer<Double>, Int32, Pointer<Float>),
          void Function(Pointer<Double>, int, Pointer<Float>)
        >('qa_audio_bus_to_float'),
        library.lookupFunction<
          Void Function(Pointer<Double>, Int32, Pointer<Int16>),
          void Function(Pointer<Double>, int, Pointer<Int16>)
        >('qa_audio_bus_to_int16'),
        library.lookupFunction<
          Int64 Function(
            Pointer<Float>,
            Int64,
            Int32,
            Int32,
            Int32,
            Double,
            Double,
            Pointer<Float>,
          ),
          int Function(
            Pointer<Float>,
            int,
            int,
            int,
            int,
            double,
            double,
            Pointer<Float>,
          )
        >('qa_audio_resample'),
        library.lookupFunction<
          Int64 Function(Int64, Int32, Int32),
          int Function(int, int, int)
        >('qa_audio_resample_frames'),
        library.lookupFunction<
          Int32 Function(Pointer<Float>, Int64, Int32, Int32),
          int Function(Pointer<Float>, int, int, int)
        >('qa_audio_denoise_f32'),
      );
    } on Object {
      return null;
    }
  }

  /// Mixes through the native core, marshalling the clips and sources into
  /// native memory for the call.
  ///
  /// This copy exists because the CALLER here is Dart (tests, and the
  /// fallback path). The realtime path never comes through this method —
  /// the device stage hands the C its arrays directly and no Dart runs on
  /// that thread at all.
  Float64List mix({
    required List<AudioMixClip> clips,
    required List<AudioMixSource> sources,
    required int startSample,
    required int sampleCount,
    required int outChannels,
  }) {
    final total = sampleCount <= 0 || outChannels <= 0
        ? 0
        : sampleCount * outChannels;
    final result = Float64List(total <= 0 ? 0 : total);
    if (total <= 0) {
      return result;
    }

    final clipArray = calloc<QaAudioClipStruct>(clips.isEmpty ? 1 : clips.length);
    final sourceArray = calloc<QaAudioSourceStruct>(
      sources.isEmpty ? 1 : sources.length,
    );
    // Every clip's envelope points flatten into ONE shared array; the
    // clips reference their slice by offset/count (mirrors the C layout).
    final envelopeTotal = qaAudioEnvelopeTotal(clips);
    final envelopeArray = calloc<QaAudioEnvelopeKeyStruct>(
      envelopeTotal <= 0 ? 1 : envelopeTotal,
    );
    final sampleBuffers = <Pointer<Float>>[];
    final bus = calloc<Double>(total);
    try {
      qaAudioWriteClips(
        clips: clips,
        clipArray: clipArray,
        envelopeArray: envelopeArray,
      );
      for (var index = 0; index < sources.length; index += 1) {
        final source = sources[index];
        final samples = calloc<Float>(
          source.samples.isEmpty ? 1 : source.samples.length,
        );
        sampleBuffers.add(samples);
        for (var i = 0; i < source.samples.length; i += 1) {
          samples[i] = source.samples[i];
        }
        final target = sourceArray[index];
        target.sourceStart = source.sourceStart;
        target.length = source.length;
        target.channels = source.channels;
        target.reserved = 0;
        target.samples = samples;
      }

      _mix(
        clipArray,
        clips.length,
        sourceArray,
        sources.length,
        envelopeArray,
        envelopeTotal,
        startSample,
        sampleCount,
        outChannels,
        bus,
      );
      for (var index = 0; index < total; index += 1) {
        result[index] = bus[index];
      }
      return result;
    } finally {
      for (final buffer in sampleBuffers) {
        calloc.free(buffer);
      }
      calloc.free(bus);
      calloc.free(envelopeArray);
      calloc.free(sourceArray);
      calloc.free(clipArray);
    }
  }

  /// RNNoise voice suppression over a finished take (48 kHz only — the
  /// model's native rate). Returns the denoised samples, or null when
  /// the C declined (wrong rate/empty) — null always means "use the raw
  /// take", never a half-processed buffer.
  Float32List? denoiseVoice({
    required Float32List samples,
    required int channels,
    required int sampleRate,
  }) {
    if (samples.isEmpty || channels <= 0) {
      return null;
    }
    final frames = samples.length ~/ channels;
    if (frames <= 0) {
      return null;
    }
    final buffer = calloc<Float>(samples.length);
    try {
      buffer.asTypedList(samples.length).setAll(0, samples);
      final processed = _denoise(buffer, frames, channels, sampleRate);
      if (processed != 1) {
        return null;
      }
      final result = Float32List(samples.length);
      result.setAll(0, buffer.asTypedList(samples.length));
      return result;
    } finally {
      calloc.free(buffer);
    }
  }

  /// Output stage: the mix bus to 32-bit float device samples.
  Float32List busToFloat(Float64List busSamples) {
    final result = Float32List(busSamples.length);
    if (busSamples.isEmpty) {
      return result;
    }
    final bus = calloc<Double>(busSamples.length);
    final out = calloc<Float>(busSamples.length);
    try {
      for (var index = 0; index < busSamples.length; index += 1) {
        bus[index] = busSamples[index];
      }
      _busToFloat(bus, busSamples.length, out);
      for (var index = 0; index < busSamples.length; index += 1) {
        result[index] = out[index];
      }
      return result;
    } finally {
      calloc.free(out);
      calloc.free(bus);
    }
  }

  /// Output stage: the mix bus to 16-bit device samples (clipping included).
  Int16List busToInt16(Float64List busSamples) {
    final result = Int16List(busSamples.length);
    if (busSamples.isEmpty) {
      return result;
    }
    final bus = calloc<Double>(busSamples.length);
    final out = calloc<Int16>(busSamples.length);
    try {
      for (var index = 0; index < busSamples.length; index += 1) {
        bus[index] = busSamples[index];
      }
      _busToInt16(bus, busSamples.length, out);
      for (var index = 0; index < busSamples.length; index += 1) {
        result[index] = out[index];
      }
      return result;
    } finally {
      calloc.free(out);
      calloc.free(bus);
    }
  }
}

/// Extension point for the resampler, kept apart from the mixer calls
/// because it belongs to a different moment: this runs ONCE at import,
/// while the mixer runs on the device thread.
extension QaAudioNativeResampling on QaAudioNative {
  /// Converts [samples] to [outputRate] through the native polyphase
  /// resampler.
  ///
  /// Equal rates return the input UNCHANGED — the caller should not even
  /// reach here in that case, but making it explicit keeps the bit-exact
  /// promise from depending on the caller remembering.
  Float32List resample({
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
}


/// How many envelope keys [clips] carry between them — the length the
/// flattened key array has to be.
int qaAudioEnvelopeTotal(List<AudioMixClip> clips) {
  var total = 0;
  for (final clip in clips) {
    total += clip.envelope.length;
  }
  return total;
}

/// Copies [clips] into [clipArray] and flattens their envelopes into
/// [envelopeArray], returning how many keys were written.
///
/// ⛔BOTH FFI PATHS HAND THE C SIDE THIS EXACT LAYOUT — the device's
/// schedule and the one-shot mixer — and each used to write it out itself,
/// twelve fields and the envelope walk, twice. A field added to the struct
/// on one side only is the failure that shape invites, and it is silent:
/// the C reads whatever the calloc left there.
void qaAudioWriteClips({
  required List<AudioMixClip> clips,
  required Pointer<QaAudioClipStruct> clipArray,
  required Pointer<QaAudioEnvelopeKeyStruct> envelopeArray,
}) {
  var envelopeCursor = 0;
  for (var index = 0; index < clips.length; index += 1) {
    final clip = clips[index];
    final target = clipArray[index];
    target.gain = clip.gain;
    target.panLeft = clip.panLeft;
    target.panRight = clip.panRight;
    target.startSample = clip.startSample;
    target.endSample = clip.endSample;
    target.sourceOffset = clip.sourceOffset;
    target.fadeInSamples = clip.fadeInSamples;
    target.fadeOutSamples = clip.fadeOutSamples;
    target.sourceIndex = clip.sourceIndex;
    target.fadeCurve = clip.fadeCurve;
    target.envelopeOffset = envelopeCursor;
    target.envelopeCount = clip.envelope.length;
    for (final point in clip.envelope) {
      final key = envelopeArray[envelopeCursor];
      key.sample = point.sample;
      key.gain = point.gain;
      envelopeCursor += 1;
    }
  }
}
/// Mirrors the C `qa_audio_clip`: doubles, then int64s, then an even
/// number of int32s — natural alignment with no implicit padding on any
/// supported ABI. The loader cross-checks `sizeof` before enabling the
/// native path.
final class QaAudioClipStruct extends Struct {
  @Double()
  external double gain;
  @Double()
  external double panLeft;
  @Double()
  external double panRight;
  @Int64()
  external int startSample;
  @Int64()
  external int endSample;
  @Int64()
  external int sourceOffset;
  @Int64()
  external int fadeInSamples;
  @Int64()
  external int fadeOutSamples;
  @Int32()
  external int sourceIndex;
  @Int32()
  external int fadeCurve;
  @Int32()
  external int envelopeOffset;
  @Int32()
  external int envelopeCount;
}

/// Mirrors the C `qa_audio_envelope_key`.
final class QaAudioEnvelopeKeyStruct extends Struct {
  @Int64()
  external int sample;
  @Double()
  external double gain;
}

/// Mirrors the C `qa_audio_source`.
final class QaAudioSourceStruct extends Struct {
  @Int64()
  external int sourceStart;
  @Int64()
  external int length;
  @Int32()
  external int channels;
  @Int32()
  external int reserved;
  external Pointer<Float> samples;
}
