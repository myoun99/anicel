// The engine's Rust library carries the mixer (rust/src/lib.rs,
// native/audio_mix), and its names are found in that code asset — no
// library opened, no path named (connection-round-checklist H, the mixer
// leaving the C with the device it plays through).
@DefaultAsset(gpuEngineAsset)
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../services/audio/audio_mixer_reference.dart';
import 'gpu_engine_asset.dart';

@Native<Int32 Function()>(symbol: 'qa_audio_clip_sizeof')
external int _clipSizeof();

@Native<Int32 Function()>(symbol: 'qa_audio_source_sizeof')
external int _sourceSizeof();

@Native<Int32 Function()>(symbol: 'qa_audio_envelope_key_sizeof')
external int _envelopeKeySizeof();

@Native<
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
  )
>(symbol: 'qa_audio_mix')
external void _mix(
  Pointer<QaAudioClipStruct> clips,
  int clipCount,
  Pointer<QaAudioSourceStruct> sources,
  int sourceCount,
  Pointer<QaAudioEnvelopeKeyStruct> keys,
  int keyCount,
  int startSample,
  int sampleCount,
  int outChannels,
  Pointer<Double> bus,
);

@Native<Void Function(Pointer<Double>, Int32, Pointer<Float>)>(
  symbol: 'qa_audio_bus_to_float',
)
external void _busToFloat(Pointer<Double> bus, int count, Pointer<Float> out);

@Native<Void Function(Pointer<Double>, Int32, Pointer<Int16>)>(
  symbol: 'qa_audio_bus_to_int16',
)
external void _busToInt16(Pointer<Double> bus, int count, Pointer<Int16> out);

/// Whether the engine lays the audio structs out byte-for-byte the way
/// this Dart build does.
///
/// Struct-layout paranoia, and the audio side has the sharpest version of
/// it: if the two sides disagree on a single byte, every field read is
/// garbage — and garbage in an audio buffer is a loud noise through
/// someone's headphones, not a wrong pixel.
///
/// It lives here because this file DECLARES the structs, and it is public
/// because [QaAudioDevice] passes those same structs to the same library
/// on the path that actually reaches a speaker. Both must call it; the
/// roster test in `a_loader_opens_no_library_of_its_own_test.dart` fails if
/// one stops.
bool qaAudioStructLayoutsMatch() =>
    _clipSizeof() == sizeOf<QaAudioClipStruct>() &&
    _sourceSizeof() == sizeOf<QaAudioSourceStruct>() &&
    _envelopeKeySizeof() == sizeOf<QaAudioEnvelopeKeyStruct>();

/// FFI binding for the engine's audio mixer (2B).
///
/// In production the mixer runs on the device's realtime thread, where Dart
/// never goes. What this class binds is the verification surface: the
/// parity tests drive it against the Dart reference the export mixes with
/// (`mixAudioReference`), so what is exported is what is played.
///
/// A layout disagreement stands it down rather than reading garbage.
final class QaAudioNative {
  const QaAudioNative._();

  /// The engine's mixer, or null when it lays the structs out otherwise.
  static QaAudioNative? get instance =>
      qaAudioStructLayoutsMatch() ? const QaAudioNative._() : null;

  /// Mixes through the native core, marshalling the clips and sources into
  /// native memory for the call.
  ///
  /// This copy exists because the CALLER here is Dart (tests, and the
  /// fallback path). The realtime path never comes through this method —
  /// the device stage hands the engine its arrays directly and no Dart runs on
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

/// The engine's schedule layout, allocated and filled once: the clip array, the
/// source array, and the ONE flattened envelope key array beside them.
///
/// ⛔BOTH FFI PATHS HAND THE ENGINE THIS EXACT LAYOUT — the device's
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
    // clips reference their slice by offset/count (mirrors the engine's layout).
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
/// ⛔BOTH FFI PATHS HAND THE ENGINE THIS EXACT LAYOUT — the device's
/// schedule and the one-shot mixer — and each used to write it out itself,
/// twelve fields and the envelope walk, twice. A field added to the struct
/// on one side only is the failure that shape invites, and it is silent:
/// the engine reads whatever the calloc left there.
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
/// Mirrors the engine's `qa_audio_clip`: doubles, then int64s, then an even
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

/// Mirrors the engine's `qa_audio_envelope_key`.
final class QaAudioEnvelopeKeyStruct extends Struct {
  @Int64()
  external int sample;
  @Double()
  external double gain;
}

/// Mirrors the engine's `qa_audio_source`.
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
