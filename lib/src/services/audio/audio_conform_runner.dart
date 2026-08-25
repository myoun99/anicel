/// Runs one conform off the UI thread (audio program wiring).
///
/// Decoding and resampling a file is seconds of CPU on minutes of audio —
/// running it on the UI isolate would freeze the canvas exactly when the
/// user just imported a sound and wants to keep drawing. `Isolate.run`
/// moves the whole pipeline to a worker; the request is plain values, the
/// result crosses back as one copy.
///
/// The native singletons resolve PER ISOLATE (a `DynamicLibrary` is opened
/// wherever it is first asked for), which is why the entry point builds
/// the pipeline inside the isolate instead of capturing one.
library;

import 'dart:isolate';
import 'dart:typed_data';

import '../../native/qa_audio_decoder.dart';
import '../../native/qa_audio_native.dart';
import '../../native/qa_engine_abi.dart';
import '../media/media_byte_source.dart';
import 'audio_conform_pipeline.dart';
import 'audio_resampler_reference.dart';

/// One conform request — every field a sendable value so the whole thing
/// can cross an isolate boundary.
class ConformRequest {
  const ConformRequest({
    required this.sourcePath,
    required this.conformPath,
    this.source,
    this.projectSampleRate = 48000,
    this.bucketsPerSecond = 80,
    this.speedNumerator = 1,
    this.speedDenominator = 1,
    this.libraryPathOverride,
  });

  final String sourcePath;

  /// Where [sourcePath]'s bytes actually ARE — an archive range for media
  /// the project carries, null for "the file at the path" (which
  /// [MediaByteSource] was built to say without every consumer learning
  /// the difference). This is the read side carrying finally grew: the
  /// save could always stream an embedded asset forward, but playback,
  /// the waveform and the existence probe kept asking the filesystem, so
  /// deleting the import original — the very act carrying exists to
  /// survive — silenced the clip and hung a "missing" banner on an asset
  /// the project owns. Plain data, so it crosses the isolate like the
  /// rest of the request.
  final MediaByteSource? source;

  /// The way to read this request's bytes, wherever they are.
  MediaByteSource get effectiveSource => source ?? MediaFileBytes(sourcePath);

  /// Null = memory-only (the unsaved-project case; see
  /// [AudioConformPipeline.ensureConform]).
  final String? conformPath;

  final int projectSampleRate;
  final int bucketsPerSecond;

  /// The project's audio speed (EXPORT-AUDIO ④, the NTSC pull).
  final int speedNumerator;
  final int speedDenominator;

  /// Test hook: the worker isolate starts with fresh statics, so a test
  /// pointing the loaders at a locally built binary has to send the path
  /// along rather than rely on having set it on the main isolate.
  final String? libraryPathOverride;
}

/// How a store runs a conform; production is [runConformInIsolate], tests
/// substitute a synchronous fake.
typedef ConformRunner = Future<ConformResult> Function(ConformRequest request);

/// The production runner.
Future<ConformResult> runConformInIsolate(ConformRequest request) =>
    Isolate.run(() => runConformHere(request));

/// One rate conversion of already-conformed PCM — the device opened at a
/// rate the conform is not at (WASAPI shared mode owns its own rate and
/// may hand back 44.1k however nicely 48k was asked for), so the sources
/// have to meet the device where it is. Sendable values only, same as
/// [ConformRequest].
class ResampleRequest {
  const ResampleRequest({
    required this.samples,
    required this.channels,
    required this.inputRate,
    required this.outputRate,
    this.libraryPathOverride,
  });

  final Float32List samples;
  final int channels;
  final int inputRate;
  final int outputRate;
  final String? libraryPathOverride;
}

/// How a store runs a rate conversion; production is
/// [runResampleInIsolate], tests substitute a synchronous fake.
typedef ResampleRunner = Future<Float32List> Function(ResampleRequest request);

/// The production resample runner.
Future<Float32List> runResampleInIsolate(ResampleRequest request) =>
    Isolate.run(() => runResampleHere(request));

/// The conversion itself, on whichever isolate this is called from.
Float32List runResampleHere(ResampleRequest request) {
  _applyLibraryOverride(request.libraryPathOverride);
  final native = QaAudioNative.instance;
  if (native != null) {
    return native.resample(
      samples: request.samples,
      channels: request.channels,
      inputRate: request.inputRate,
      outputRate: request.outputRate,
    );
  }
  return resampleAudioReference(
    samples: request.samples,
    channels: request.channels,
    inputRate: request.inputRate,
    outputRate: request.outputRate,
  ).samples;
}

void _applyLibraryOverride(String? override) {
  // A worker isolate re-resolves the singletons from scratch, so the test
  // path has to travel with the request. One assignment now covers every
  // loader — this used to name two of six, which was fine only because
  // the conform path happens to touch exactly those two.
  if (override != null) {
    debugQaEngineLibraryPathOverride = override;
  }
}

/// The pipeline itself, on whichever isolate this is called from —
/// [runConformInIsolate]'s worker body, and directly callable by tests
/// that want the real native path without isolate indirection.
ConformResult runConformHere(ConformRequest request) {
  _applyLibraryOverride(request.libraryPathOverride);
  final pipeline = AudioConformPipeline(
    decode: (bytes) {
      final decoded = QaAudioDecoder.instance?.decode(bytes);
      if (decoded == null) {
        return null;
      }
      return (
        samples: decoded.samples,
        channels: decoded.channels,
        sampleRate: decoded.sampleRate,
      );
    },
    // Native resampler when the binary is present; the byte-identical Dart
    // reference otherwise. Either way the SAME filter design — that is what
    // the parity pins are for.
    resample:
        ({
          required samples,
          required channels,
          required inputRate,
          required outputRate,
        }) {
          final native = QaAudioNative.instance;
          if (native != null) {
            return native.resample(
              samples: samples,
              channels: channels,
              inputRate: inputRate,
              outputRate: outputRate,
            );
          }
          return resampleAudioReference(
            samples: samples,
            channels: channels,
            inputRate: inputRate,
            outputRate: outputRate,
          ).samples;
        },
    projectSampleRate: request.projectSampleRate,
    bucketsPerSecond: request.bucketsPerSecond,
    speedNumerator: request.speedNumerator,
    speedDenominator: request.speedDenominator,
  );
  return pipeline.ensureConform(
    sourcePath: request.sourcePath,
    conformPath: request.conformPath,
    source: request.source,
  );
}
