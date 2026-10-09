import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'qa_engine_abi.dart';

/// Which decoder read a file — reported so a log can say what happened
/// instead of just "it worked". [os] is the platform's own codec stack
/// (Media Foundation / AudioToolbox / MediaCodec), reached only for
/// containers the bundled decoders do not read — AAC/m4a per the decided
/// format table. [vorbis] is the vendored stb_vorbis (ogg).
enum QaAudioFormat { unknown, wav, flac, mp3, os, vorbis }

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
  QaAudioDecoder._(this._decodeSpan, this._free);

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
          format: format >= 1 && format <= 5
              ? QaAudioFormat.values[format]
              : QaAudioFormat.unknown,
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
