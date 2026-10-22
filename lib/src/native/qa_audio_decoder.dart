import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../services/audio/audio_decode_stream.dart';
import 'native_scratch.dart';
import 'qa_engine_abi.dart';

/// Which decoder read a file — reported so a log can say what happened
/// instead of just "it worked". [os] is the platform's own codec stack
/// (Media Foundation / AudioToolbox / MediaCodec), reached only for
/// containers the engine does not read itself — AAC/m4a per the decided
/// format table. [vorbis] is the vendored stb_vorbis (ogg). [moviePcm] is a
/// movie's uncompressed sound, which the engine reads itself on every
/// platform (`qa_movie_pcm_open`).
enum QaAudioFormat { unknown, wav, flac, mp3, os, vorbis, moviePcm }

/// A decoded audio file, at the file's OWN sample rate.
///
/// Resampling to the project rate is deliberately NOT done here: it is a
/// quality decision (what filter, what rolloff) and hiding it inside a
/// decode call would make it invisible.
class QaDecodedAudio {
  const QaDecodedAudio({
    required this.samples,
    required this.channels,
    required this.sampleRate,
    required this.format,
  });

  /// Interleaved by channel, normalized to [-1, 1].
  final Float32List samples;
  final int channels;
  final int sampleRate;
  final QaAudioFormat format;

  /// Samples per channel.
  int get length => channels <= 0 ? 0 : samples.length ~/ channels;
}

/// Decodes WAV / FLAC / MP3 through the vendored dr_libs in the native
/// core.
///
/// Decoding runs ONCE at import — that is what conforming means, and why a
/// variable-length codec never has to finish inside an audio callback.
///
/// ONE door: [decodeSpan], a container stored in [length] bytes of a file
/// from [offset] — as it is, or FRAMED (compressed in blocks). That is what a
/// sound inside the project file looks like, what a staged copy looks like,
/// AND what a plain file looks like (offset 0, the whole length, not
/// framed). 🚨Nothing on that path holds the container, which is why a
/// movie's sound can be conformed at all — reading a three-gigabyte
/// reference video into a `Uint8List` first was the reason it could not be.
///
/// 🪦There was a second door, `decode(Uint8List)`, kept for 「a FRAMED
/// archive entry is stored in pieces, so there is no range to point at」. The
/// engine reads framed spans itself now (`qa_media_span.c`), so the pieces
/// ARE something to point at, and the door went with the reason for it
/// (2026-09-24).
///
/// 🪦Handing C a path was refused for a year because 「a `const char*` would
/// drag in the question of whether a Windows path is UTF-8 or the local
/// codepage, and a Korean filename would settle it the hard way」. The video
/// decoder had to answer that question and did — UTF-8 in, widened once, in
/// `qa_platform_path.h` — so the hazard is now handled in one place instead
/// of avoided in two.
final class QaAudioDecoder {
  QaAudioDecoder._(this._decodeSpan, this._free, this._stream);

  final int Function(
    Pointer<Utf8>,
    int,
    int,
    int,
    int,
    int,
    Pointer<Pointer<Float>>,
    Pointer<Int64>,
    Pointer<Int32>,
    Pointer<Int32>,
  )
  _decodeSpan;
  final void Function(Pointer<Float>) _free;
  final _QaAudioStreamApi _stream;

  static QaAudioDecoder? _instance;
  static bool _tried = false;

  static void debugResetForTests() {
    _instance = null;
    _tried = false;
  }

  /// The native decoder, or null when no binary is available.
  static QaAudioDecoder? get instance {
    if (!_tried) {
      _tried = true;
      _instance = _load();
    }
    return _instance;
  }

  static QaAudioDecoder? _load() {
    final library = openQaEngineLibrary();
    if (library == null) {
      return null;
    }
    try {
      return QaAudioDecoder._(
        library.lookupFunction<
          Int32 Function(
            Pointer<Utf8>,
            Int64,
            Int64,
            Int32,
            Int64,
            Int64,
            Pointer<Pointer<Float>>,
            Pointer<Int64>,
            Pointer<Int32>,
            Pointer<Int32>,
          ),
          int Function(
            Pointer<Utf8>,
            int,
            int,
            int,
            int,
            int,
            Pointer<Pointer<Float>>,
            Pointer<Int64>,
            Pointer<Int32>,
            Pointer<Int32>,
          )
        >('qa_audio_decode_span_window'),
        library.lookupFunction<
          Void Function(Pointer<Float>),
          void Function(Pointer<Float>)
        >('qa_audio_decode_free'),
        _QaAudioStreamApi(library),
      );
    } on Object {
      return null;
    }
  }

  /// Decodes the container stored in [span]'s length bytes of its path from
  /// its offset — FRAMED when it says so; null when no decoder recognized
  /// it, the span is not inside the file, or the file will not open.
  ///
  /// A whole file is `offset: 0` with its own length — the ordinary case
  /// goes through the same door as a carried one, so no caller has to know
  /// which it has.
  ///
  /// [window]: only [window.count] frames of the sound from frame
  /// [window.start] — the sound's own frames at its own rate, frame 0 its
  /// first — and only those are held (user 2026-10-09,
  /// sound-lands-on-its-exact-sample-Q5). They are exactly the frames the
  /// whole decode has there. A count of 0 decodes nothing and answers the
  /// rate and the channels: ask for that first when the frames to name
  /// depend on the rate. A window past the end is no frames, not null.
  ///
  /// [span] is a `MediaSpan` (`media_byte_source.dart`) by shape: a record
  /// type is its fields, so a source's span is handed over as it is, and this
  /// layer imports nothing to say so.
  QaDecodedAudio? decodeSpan(
    ({String path, int offset, int length, bool framed}) span, {
    ({int start, int count})? window,
  }) {
    final (:path, :offset, :length, :framed) = span;
    if (path.isEmpty ||
        offset < 0 ||
        length <= 0 ||
        (window != null && (window.start < 0 || window.count < 0))) {
      return null;
    }
    final native = path.toNativeUtf8();
    try {
      return _harvest(
        (samplesOut, frameCountOut, channelsOut, sampleRateOut) => _decodeSpan(
          native,
          offset,
          length,
          framed ? 1 : 0,
          window?.start ?? 0,
          window?.count ?? -1,
          samplesOut,
          frameCountOut,
          channelsOut,
          sampleRateOut,
        ),
      );
    } finally {
      calloc.free(native);
    }
  }

  /// The container stored in [span]'s length bytes of its path from its
  /// offset, opened once to be read on — its frames [decodeSpan]'s, a piece
  /// at a time; null when no decoder recognized it, the span is not inside
  /// the file, or the file will not open. [QaAudioStream.close] lets it go.
  ///
  /// 🚨What a conform is made from: a long sound is decoded, resampled and
  /// written as it comes and never held whole (user 2026-10-10, board
  /// long-sound-conform-memory-Q1).
  QaAudioStream? openSpan(
    ({String path, int offset, int length, bool framed}) span,
  ) {
    final (:path, :offset, :length, :framed) = span;
    if (path.isEmpty || offset < 0 || length <= 0) {
      return null;
    }
    final native = path.toNativeUtf8();
    final formatOut = calloc<Int32>();
    final channelsOut = calloc<Int32>();
    final sampleRateOut = calloc<Int32>();
    try {
      final handle = _stream.open(
        native,
        offset,
        length,
        framed ? 1 : 0,
        formatOut,
        channelsOut,
        sampleRateOut,
      );
      if (handle == nullptr) {
        return null;
      }
      return QaAudioStream._(
        _stream,
        handle,
        channels: channelsOut.value,
        sampleRate: sampleRateOut.value,
        format: _formatOf(formatOut.value),
      );
    } finally {
      calloc.free(sampleRateOut);
      calloc.free(channelsOut);
      calloc.free(formatOut);
      calloc.free(native);
    }
  }

  /// The four out-parameters, and what to do with what comes back.
  QaDecodedAudio? _harvest(
    int Function(
      Pointer<Pointer<Float>>,
      Pointer<Int64>,
      Pointer<Int32>,
      Pointer<Int32>,
    )
    call,
  ) {
    final samplesOut = calloc<Pointer<Float>>();
    final frameCountOut = calloc<Int64>();
    final channelsOut = calloc<Int32>();
    final sampleRateOut = calloc<Int32>();
    try {
      final format = call(
        samplesOut,
        frameCountOut,
        channelsOut,
        sampleRateOut,
      );
      final samples = samplesOut.value;
      // A window can answer with no frames, and then no block to free.
      if (format == 0 || (samples == nullptr && frameCountOut.value > 0)) {
        return null;
      }
      try {
        final channels = channelsOut.value;
        final frames = frameCountOut.value;
        final total = frames * channels;
        // Copy out of native memory before freeing it — the decoder owns
        // that block, and a Dart view over it would dangle.
        final copied = Float32List(total < 0 ? 0 : total);
        if (total > 0) {
          copied.setAll(0, samples.asTypedList(total));
        }
        return QaDecodedAudio(
          samples: copied,
          channels: channels,
          sampleRate: sampleRateOut.value,
          format: _formatOf(format),
        );
      } finally {
        if (samples != nullptr) {
          _free(samples);
        }
      }
    } finally {
      calloc.free(sampleRateOut);
      calloc.free(channelsOut);
      calloc.free(frameCountOut);
      calloc.free(samplesOut);
    }
  }
}

QaAudioFormat _formatOf(int format) =>
    format >= 1 && format < QaAudioFormat.values.length
    ? QaAudioFormat.values[format]
    : QaAudioFormat.unknown;

/// The engine's sound streams — `qa_audio_stream_*`.
final class _QaAudioStreamApi {
  _QaAudioStreamApi(DynamicLibrary library)
    : open = library
          .lookupFunction<
            Pointer<Void> Function(
              Pointer<Utf8>,
              Int64,
              Int64,
              Int32,
              Pointer<Int32>,
              Pointer<Int32>,
              Pointer<Int32>,
            ),
            Pointer<Void> Function(
              Pointer<Utf8>,
              int,
              int,
              int,
              Pointer<Int32>,
              Pointer<Int32>,
              Pointer<Int32>,
            )
          >('qa_audio_stream_open'),
      read = library
          .lookupFunction<
            Int64 Function(Pointer<Void>, Pointer<Float>, Int64),
            int Function(Pointer<Void>, Pointer<Float>, int)
          >('qa_audio_stream_read'),
      close = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('qa_audio_stream_close');

  final Pointer<Void> Function(
    Pointer<Utf8>,
    int,
    int,
    int,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Int32>,
  )
  open;
  final int Function(Pointer<Void>, Pointer<Float>, int) read;
  final void Function(Pointer<Void>) close;
}

/// A sound the engine opened to read on ([QaAudioDecoder.openSpan]).
final class QaAudioStream implements AudioDecodeStream {
  QaAudioStream._(
    this._api,
    this._handle, {
    required this.channels,
    required this.sampleRate,
    required this.format,
  });

  final _QaAudioStreamApi _api;
  Pointer<Void> _handle;

  @override
  final int channels;

  @override
  final int sampleRate;

  final QaAudioFormat format;

  /// ⚠️One for the isolate, not one per stream: nothing here suspends
  /// between the native read and the copy out.
  static final NativeScratch<Float> _room = NativeScratch<Float>(
    (count) => calloc<Float>(count),
    bytesPerElement: sizeOf<Float>(),
  );

  @override
  Float32List read(int frames) {
    if (_handle == nullptr) {
      throw StateError('the stream is closed');
    }
    if (frames <= 0 || channels <= 0) {
      return Float32List(0);
    }
    final room = _room.ensure(frames * channels);
    final got = _api.read(_handle, room, frames);
    if (got < 0) {
      throw const AudioDecodeFailure(
        'the decoder failed partway through the sound',
      );
    }
    // Copied out: the room is the next read's.
    return Float32List.fromList(room.asTypedList(got * channels));
  }

  @override
  void close() {
    if (_handle != nullptr) {
      _api.close(_handle);
      _handle = nullptr;
    }
  }
}
