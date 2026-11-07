import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../services/audio/audio_mixer_reference.dart';
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
  try {
    return qaStructSizeMatches(
          library,
          'qa_audio_clip_sizeof',
          sizeOf<QaAudioClipStruct>(),
        ) &&
        qaStructSizeMatches(
          library,
          'qa_audio_source_sizeof',
          sizeOf<QaAudioSourceStruct>(),
        ) &&
        qaStructSizeMatches(
          library,
          'qa_audio_envelope_key_sizeof',
          sizeOf<QaAudioEnvelopeKeyStruct>(),
        );
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
  QaAudioNative._(this._mix, this._busToFloat, this._busToInt16);

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

  /// 🚨★★★**THE C'S MIXER NAMES ONLY, NOTHING THE ENGINE ANSWERS**
  /// (connection-round-checklist H, 관제 2026-11-08 06:15 ⓓ · 타임라인/콘티
  /// 06:17). Every name is found in one `try`, and one missing stands the
  /// whole class down — the mixer to the Dart reference with it. The
  /// resampler and the denoiser left this class when their C went
  /// (`qa_audio_resampler.dart`, `qa_audio_denoiser.dart`), and their
  /// names went from this list in the same change: on Apple's the library
  /// [openQaEngineLibrary] answers is the process's, which searches every
  /// image loaded, the engine's among them — so a name the C no longer has
  /// would be found there or not by whether the engine had been opened
  /// first, and the mixer would stand on the C or on Dart by that order
  /// alone.
  /// Windows and Linux open the C by its own handle and could never show
  /// it. ⛔Name nothing here the C engine does not export itself.
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

    final arrays = QaAudioScheduleArrays(clips, sources);
    final sampleBuffers = <Pointer<Float>>[];
    final bus = calloc<Double>(total);
    try {
      for (var index = 0; index < sources.length; index += 1) {
        final source = sources[index];
        final samples = calloc<Float>(
          source.samples.isEmpty ? 1 : source.samples.length,
        );
        sampleBuffers.add(samples);
        for (var i = 0; i < source.samples.length; i += 1) {
          samples[i] = source.samples[i];
        }
        // The mixer reads the source IN PLACE: the struct keeps a pointer
        // into this Dart-owned buffer for the length of the call.
        arrays.writeSource(index, source, samples);
      }

      _mix(
        arrays.clipArray,
        clips.length,
        arrays.sourceArray,
        sources.length,
        arrays.envelopeArray,
        arrays.envelopeTotal,
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
      arrays.free();
    }
  }

  /// ⚠️This and [busToInt16] keep the same allocate/call/free skeleton and
  /// the clone scan pairs them (audit 2026-09-04, read and HELD). A generic
  /// over the output pointer cannot work: `asTypedList` has no common
  /// interface across `Pointer<Float>` and `Pointer<Int16>`, so the shared
  /// version would need a read callback per type — more indirection than
  /// the six lines it saves, for two callers. A THIRD output stage is what
  /// changes that.
  /// Output stage: the mix bus to 32-bit float device samples.
  Float32List busToFloat(Float64List busSamples) {
    final result = Float32List(busSamples.length);
    if (busSamples.isEmpty) {
      return result;
    }
    final bus = calloc<Double>(busSamples.length);
    final out = calloc<Float>(busSamples.length);
    try {
      // Bulk copies — the element loops these two used to run were the same
      // twenty lines written twice.
      bus.asTypedList(busSamples.length).setAll(0, busSamples);
      _busToFloat(bus, busSamples.length, out);
      result.setAll(0, out.asTypedList(busSamples.length));
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
      bus.asTypedList(busSamples.length).setAll(0, busSamples);
      _busToInt16(bus, busSamples.length, out);
      result.setAll(0, out.asTypedList(busSamples.length));
      return result;
    } finally {
      calloc.free(out);
      calloc.free(bus);
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

/// The C schedule layout, allocated and filled once: the clip array, the
/// source array, and the ONE flattened envelope key array beside them.
///
/// ⛔BOTH FFI PATHS HAND THE C SIDE THIS EXACT LAYOUT — the device's
/// schedule and the one-shot mixer — and each used to allocate it out
/// itself: three `calloc`s with the same `max(1, n)` guard, the same
/// [qaAudioWriteClips], the same four-field source write, and the same
/// reverse-order frees. The clip half was already shared; the SOURCE
/// struct was still exposed to the hazard the comment on
/// [qaAudioWriteClips] names.
///
/// What genuinely differs between the two paths stays with each caller:
/// the device points each struct at a buffer of its own that it holds
/// for the call (the slot holds it after), the mixer callocs a buffer per
/// source and points the struct at it. That is a value — the `samples`
/// pointer handed to [writeSource] — not a mode.
final class QaAudioScheduleArrays {
  factory QaAudioScheduleArrays(
    List<AudioMixClip> clips,
    List<AudioMixSource> sources,
  ) {
    // Every clip's envelope points flatten into ONE shared array; the
    // clips reference their slice by offset/count (mirrors the C layout).
    final envelopeTotal = qaAudioEnvelopeTotal(clips);
    final arrays = QaAudioScheduleArrays._(
      clipArray: calloc<QaAudioClipStruct>(clips.isEmpty ? 1 : clips.length),
      sourceArray: calloc<QaAudioSourceStruct>(
        sources.isEmpty ? 1 : sources.length,
      ),
      envelopeArray: calloc<QaAudioEnvelopeKeyStruct>(
        envelopeTotal <= 0 ? 1 : envelopeTotal,
      ),
      envelopeTotal: envelopeTotal,
    );
    qaAudioWriteClips(
      clips: clips,
      clipArray: arrays.clipArray,
      envelopeArray: arrays.envelopeArray,
    );
    return arrays;
  }

  QaAudioScheduleArrays._({
    required this.clipArray,
    required this.sourceArray,
    required this.envelopeArray,
    required this.envelopeTotal,
  });

  final Pointer<QaAudioClipStruct> clipArray;
  final Pointer<QaAudioSourceStruct> sourceArray;
  final Pointer<QaAudioEnvelopeKeyStruct> envelopeArray;
  final int envelopeTotal;

  /// Writes [source]'s struct at [index], pointed at [samples] — a device
  /// buffer for the device path, a Dart-owned buffer for the mixer's.
  void writeSource(int index, AudioMixSource source, Pointer<Float> samples) {
    final target = sourceArray[index];
    target.sourceStart = source.sourceStart;
    target.length = source.length;
    target.channels = source.channels;
    target.reserved = 0;
    target.samples = samples;
  }

  /// Frees the three arrays in reverse allocation order.
  void free() {
    calloc.free(envelopeArray);
    calloc.free(sourceArray);
    calloc.free(clipArray);
  }
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
