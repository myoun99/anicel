/// Runs one conform off the UI thread (audio program wiring).
///
/// Decoding and resampling a file is seconds of CPU on minutes of audio —
/// running it on the UI isolate would freeze the canvas exactly when the
/// user just imported a sound and wants to keep drawing. `Isolate.run`
/// moves the whole pipeline to a worker; the request is plain values, the
/// result crosses back as one copy.
///
/// The entry point builds the pipeline inside the isolate instead of
/// capturing one: what crosses is the request's plain values. Every native
/// function the conform asks is the Rust engine's, bound with `@Native`, so
/// a worker finds it with no path named. ↩️While the decoder was the C
/// engine's, its singleton resolved PER ISOLATE (a `DynamicLibrary` opened
/// wherever it was first asked for), and a test's library path travelled
/// with the request — until the connection round (connection-round-checklist
/// H, 2026-11-08).
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../core/on_a_worker.dart';
import '../../native/qa_audio_decoder.dart';
import '../../native/qa_audio_device.dart';
import '../../native/qa_audio_filter.dart';
import '../../native/qa_audio_resampler.dart';
import '../media/media_byte_source.dart';
import 'audio_conform_pipeline.dart';
import 'sound_filters.dart' show FilteredSpan;
import 'audio_decode_stream.dart';

/// One conform request — every field a sendable value so the whole thing
/// can cross an isolate boundary.
class ConformRequest {
  const ConformRequest({
    required this.sourcePath,
    required this.conformPath,
    this.source,
    this.carriedConform,
    this.projectSampleRate = 48000,
    this.bucketsPerSecond = 80,
    this.speedNumerator = 1,
    this.speedDenominator = 1,
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

  /// The conform the PROJECT carries for this source, when it has one —
  /// a range inside the `.anicel`. Restored into the cache before
  /// anything is decided, so opening on a machine with an empty cache
  /// plays at once instead of decoding every sound first.
  ///
  /// Plain data, so it crosses the isolate like the rest of the request.
  final MediaByteSource? carriedConform;

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
class ResampleRequest implements _PcmFromPcm<ResampleRequest> {
  const ResampleRequest({
    required this.samples,
    required this.channels,
    required this.inputRate,
    required this.outputRate,
  });

  @override
  final Float32List samples;
  final int channels;
  final int inputRate;
  final int outputRate;

  /// This conversion of [samples] instead.
  @override
  ResampleRequest withSamples(Float32List samples) => ResampleRequest(
    samples: samples,
    channels: channels,
    inputRate: inputRate,
    outputRate: outputRate,
  );
}

/// How a store runs a rate conversion; production is
/// [runResampleInIsolate], tests substitute a synchronous fake.
typedef ResampleRunner = Future<Float32List> Function(ResampleRequest request);

/// The production resample runner.
Future<Float32List> runResampleInIsolate(ResampleRequest request) =>
    Isolate.run(() => runResampleHere(request));

/// One span of already-conformed PCM through its row's filters — what
/// playback and an export both read of a filtered span (board
/// audio-fx-grows-like-the-pros ③). [samples] are the whole conform at
/// [rate]; [span] says which of them, baked from rest at its first.
/// Sendable values only, same as [ConformRequest].
class FilterRequest implements _PcmFromPcm<FilterRequest> {
  const FilterRequest({
    required this.samples,
    required this.channels,
    required this.rate,
    required this.span,
  });

  @override
  final Float32List samples;
  final int channels;
  final int rate;
  final FilteredSpan span;

  /// This bake of [samples] instead.
  @override
  FilterRequest withSamples(Float32List samples) => FilterRequest(
    samples: samples,
    channels: channels,
    rate: rate,
    span: span,
  );
}

/// How a store bakes a span; production is [runFilterInIsolate], tests
/// substitute a synchronous fake.
typedef FilterRunner = Future<Float32List> Function(FilterRequest request);

/// The production bake runner.
Future<Float32List> runFilterInIsolate(FilterRequest request) =>
    Isolate.run(() => runFilterHere(request));

/// A job that makes PCM out of PCM already conformed — a conversion to the
/// device's rate, a span through its filters — so the samples it reads
/// can be lent to its worker where they lie ([_pcmFromPcmInto]).
abstract interface class _PcmFromPcm<R extends _PcmFromPcm<R>> {
  Float32List get samples;
  R withSamples(Float32List samples);
}

/// What a worker hands back: its result, less its PCM where that was
/// placed in the device's buffers, and where — at 0 where it was not.
typedef _Landed<T> = ({T result, int address, int floats});

/// The production runner, its PCM placed where [device] plays it — or, with
/// no device, [runConformInIsolate]'s.
///
/// 🚨THE PCM THE DEVICE PLAYS LIVES IN THE DEVICE FROM THE MOMENT IT LANDS
/// (play-press-first-frame-stall, 10-15). A conform's samples, each rate
/// they were converted to ([resamplingInto]) and each span baked through
/// its filters ([filteringInto]) are placed there ONCE, and every
/// schedule after names them without a copy. ↩️They stayed in Dart memory,
/// and every upload — each press, seek and streaming advance — copied every
/// resident sound into the device again, however many takes a project had.
ConformRunner conformingInto(QaAudioDevice? Function() device) =>
    (request) => _landedWhereTheDevicePlays(
      device(),
      plainly: () => runConformInIsolate(request),
      worked: (_) => _conformOnAWorker(request),
      withAdopted: (result, adopted) => result.withSamples(adopted),
    );

/// The production resample runner, its PCM placed as [conformingInto]
/// places a conform's, the conform it converts lent to its worker
/// ([_pcmFromPcmInto]).
ResampleRunner resamplingInto(QaAudioDevice? Function() device) =>
    (request) => _pcmFromPcmInto(
      device(),
      request,
      plainly: runResampleInIsolate,
      here: runResampleHere,
    );

/// The production bake runner, placed and lent as [resamplingInto]'s.
FilterRunner filteringInto(QaAudioDevice? Function() device) =>
    (request) => _pcmFromPcmInto(
      device(),
      request,
      plainly: runFilterInIsolate,
      here: runFilterHere,
    );

/// 🚨THE ONE WAY PCM MADE ON A WORKER LANDS WHERE THE DEVICE PLAYS IT: with
/// no device [into], [plainly]; with one, [worked] makes it on a worker that
/// places its PCM in the device's buffers ([_placedOnTheWorker]), and this
/// isolate adopts it as it lands, put back into its result by
/// [withAdopted] — here, the one place, so no buffer is left that nobody
/// holds.
///
/// 🚨PLACED BY THE WORKER THAT MADE THEM (conform-landing-copies-on-the-ui-
/// thread): ↩️the store copied them in as they landed
/// (`placeForPlayback`), on the thread that draws: two minutes of stereo
/// is 46 MB, and an unsaved project's sound is held whole however long it
/// is.
///
/// ↩️The conform's runner and the conversion's each spelled it (the
/// one-algorithm ledger's 86 → 87), until the equalizer's bake came as the
/// third kind of PCM landing here, which merged the three.
Future<T> _landedWhereTheDevicePlays<T>(
  QaAudioDevice? into, {
  required Future<T> Function() plainly,
  required Future<_Landed<T>> Function(QaAudioDevice into) worked,
  required T Function(T result, Float32List adopted) withAdopted,
}) async {
  if (into == null) {
    return plainly();
  }
  final landed = await worked(into);
  return landed.address == 0
      ? landed.result
      : withAdopted(
          landed.result,
          into.adoptSamples(landed.address, landed.floats),
        );
}

/// [request]'s job, landed as [_landedWhereTheDevicePlays] lands PCM.
///
/// 🚨THE CONFORM IT READS IS READ WHERE IT LIES (resample-request-copies-
/// the-conform-to-the-worker): the conform's samples are a buffer of the
/// device's, lent to the worker by address for as long as it works
/// ([QaAudioDevice.lendToAWorker]). ↩️The request carried them, and a
/// message copies what it carries — on the thread that draws, a sound's
/// whole PCM once more for each sound a device at another rate asks for.
Future<Float32List> _pcmFromPcmInto<R extends _PcmFromPcm<R>>(
  QaAudioDevice? into,
  R request, {
  required Future<Float32List> Function(R request) plainly,
  required Float32List Function(R request) here,
}) => _landedWhereTheDevicePlays(
  into,
  plainly: () => plainly(request),
  worked: (into) => into.lendToAWorker(
    request.samples,
    (lent) => _fromLentOnAWorker(
      lent == null ? request : request.withSamples(Float32List(0)),
      lent,
      here,
    ),
  ),
  withAdopted: (_, adopted) => adopted,
);

/// The workers' jobs, each in a function of its own: [onAWorker] copies
/// the closure's whole context, and these hold a request and an address.
Future<_Landed<ConformResult>> _conformOnAWorker(ConformRequest request) =>
    onAWorker(() {
      final result = runConformHere(request);
      return _placedOnTheWorker(
        result,
        result.samples,
        () => result.withSamples(null),
      );
    });

/// [lent]: where the samples [request] left out lie, when it left them out.
Future<_Landed<Float32List>> _fromLentOnAWorker<R extends _PcmFromPcm<R>>(
  R request,
  ({int address, int floats})? lent,
  Float32List Function(R request) here,
) => onAWorker(() {
  assert(
    lent == null || request.samples.isEmpty,
    'a lent job carries its samples by address alone',
  );
  final made = here(
    lent == null
        ? request
        : request.withSamples(
            Pointer<Float>.fromAddress(lent.address).asTypedList(lent.floats),
          ),
  );
  return _placedOnTheWorker(made, made, () => Float32List(0));
});

/// On a worker: [made]'s PCM, [samples], placed where the device plays it
/// ([placedWhereTheDevicePlays]), and [made] handed back [without] it
/// where it was placed.
_Landed<T> _placedOnTheWorker<T>(
  T made,
  Float32List? samples,
  T Function() without,
) {
  final placed = placedWhereTheDevicePlays(samples, audioBuffersHere());
  return (
    result: placed.address == 0 ? made : without(),
    address: placed.address,
    floats: placed.floats,
  );
}

/// [samples] in a buffer [hands] makes, by its address and its floats — or
/// none, at 0, where there are none or the buffer cannot be made, and the
/// samples stay where they are, as a device that had no room left them.
({int address, int floats}) placedWhereTheDevicePlays(
  Float32List? samples,
  AudioBufferHands hands,
) {
  if (samples == null || samples.isEmpty) {
    return (address: 0, floats: 0);
  }
  final Pointer<Float> buffer;
  try {
    buffer = hands.make(samples.length);
  } on StateError {
    return (address: 0, floats: 0);
  }
  buffer.asTypedList(samples.length).setAll(0, samples);
  return (address: buffer.address, floats: samples.length);
}

/// The conversion itself, on whichever isolate this is called from.
Float32List runResampleHere(ResampleRequest request) => resampleAudio(
  samples: request.samples,
  channels: request.channels,
  inputRate: request.inputRate,
  outputRate: request.outputRate,
);

/// The bake itself, on whichever isolate this is called from: the span's
/// samples — those of it the conform holds — through its settings.
///
/// Throws where the engine refuses what it was handed, so the store
/// remembers the bake as failed rather than playing silence for it.
Float32List runFilterHere(FilterRequest request) {
  final channels = request.channels;
  final frames = channels <= 0 ? 0 : request.samples.length ~/ channels;
  final start = request.span.start.clamp(0, frames);
  final end = (request.span.start + request.span.length).clamp(start, frames);
  final baked = filterAudio(
    samples: Float32List.sublistView(
      request.samples,
      start * channels,
      end * channels,
    ),
    channels: channels,
    rate: request.rate,
    stages: request.span.stages,
  );
  if (baked.length != (end - start) * channels) {
    throw StateError(
      'the engine would not bake ${end - start} samples of $channels '
      'channels at ${request.rate} Hz',
    );
  }
  return baked;
}

/// [source]'s sound, decoded at its own rate — what a conform starts from,
/// and what a trimmed sound's piece is cut from.
///
/// 🚨★★★**DECODED WHERE IT LIES, ALWAYS.** Every source names its span — a
/// loose file, a sound or a movie carried inside the project, a staged
/// copy — framed or not, and the decoder reads that span itself.
///
/// 🪦A FRAMED entry used to be assembled in memory first, on the grounds
/// that 「nothing enormous is stored framed」. That was never measured and
/// was false — compression is decided per file and an MP4 shrinks 6.7% —
/// so a carried movie's soundtrack arrived whole in memory before a decoder
/// saw it (2026-09-24).
///
/// [window]: only those of the sound's own frames, and only those held — see
/// [QaAudioDecoder.decodeSpan].
({Float32List samples, int channels, int sampleRate})? decodeAudioSource(
  MediaByteSource source, {
  ({int start, int count})? window,
}) {
  final decoded = QaAudioDecoder.instance.decodeSpan(
    _spanOf(source),
    window: window,
  );
  if (decoded == null) {
    return null;
  }
  return (
    samples: decoded.samples,
    channels: decoded.channels,
    sampleRate: decoded.sampleRate,
  );
}

/// [source]'s sound opened to be read on, at its own rate — what a conform
/// is made from, so a long one is never held whole (user 2026-10-10, board
/// long-sound-conform-memory-Q1). Null when no decoder recognized it.
/// Decoded where it lies, as [decodeAudioSource] is.
AudioDecodeStream? openAudioSource(MediaByteSource source) =>
    QaAudioDecoder.instance.openSpan(_spanOf(source));

/// Where [source]'s bytes lie for the decoder.
MediaSpan _spanOf(MediaByteSource source) {
  final span = source.span;
  if (span == null) {
    // Only a file that is no longer there has no span; say so the way
    // reading it would have, so the pipeline counts it as unreadable.
    throw FileSystemException('the sound is not there to decode', '$source');
  }
  return span;
}

/// The pipeline itself, on whichever isolate this is called from —
/// [runConformInIsolate]'s worker body, and directly callable by tests
/// that want the real native path without isolate indirection.
ConformResult runConformHere(ConformRequest request) {
  final pipeline = AudioConformPipeline(
    decode: openAudioSource,
    // The engine's resampler, which always loads — its Dart twin is the
    // tests' answer key, no fallback (connection-round-checklist H).
    resample: openAudioResampler,
    projectSampleRate: request.projectSampleRate,
    bucketsPerSecond: request.bucketsPerSecond,
    speedNumerator: request.speedNumerator,
    speedDenominator: request.speedDenominator,
  );
  return pipeline.ensureConform(
    sourcePath: request.sourcePath,
    conformPath: request.conformPath,
    source: request.source,
    carriedConform: request.carriedConform,
  );
}
