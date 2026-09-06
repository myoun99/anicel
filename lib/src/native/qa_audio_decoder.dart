import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_scratch.dart';
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
/// Two doors, and the only difference is where the bytes are.
///
/// [decodeRange] is the one to reach for: a container is [length] bytes of a
/// file starting at [offset], which is what a sound inside the project file
/// looks like AND what a plain file looks like (offset 0, the whole length).
/// 🚨Nothing on that path holds the container, which is why a movie's sound
/// can be conformed at all — reading a three-gigabyte reference video into a
/// `Uint8List` first was the reason it could not be.
///
/// [decode] takes assembled bytes, and stays for the case that genuinely has
/// them: a FRAMED archive entry is stored in pieces, so there is no range to
/// point at.
///
/// 🪦Handing C a path was refused for a year because 「a `const char*` would
/// drag in the question of whether a Windows path is UTF-8 or the local
/// codepage, and a Korean filename would settle it the hard way」. The video
/// decoder had to answer that question and did — UTF-8 in, widened once, in
/// `qa_platform_path.h` — so the hazard is now handled in one place instead
/// of avoided in two.
final class QaAudioDecoder {
  QaAudioDecoder._(this._decode, this._decodeRange, this._free);

  final int Function(
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Float>>,
    Pointer<Int64>,
    Pointer<Int32>,
    Pointer<Int32>,
  )
  _decode;
  final int Function(
    Pointer<Utf8>,
    int,
    int,
    Pointer<Pointer<Float>>,
    Pointer<Int64>,
    Pointer<Int32>,
    Pointer<Int32>,
  )
  _decodeRange;
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
            Pointer<Uint8>,
            Int64,
            Pointer<Pointer<Float>>,
            Pointer<Int64>,
            Pointer<Int32>,
            Pointer<Int32>,
          ),
          int Function(
            Pointer<Uint8>,
            int,
            Pointer<Pointer<Float>>,
            Pointer<Int64>,
            Pointer<Int32>,
            Pointer<Int32>,
          )
        >('qa_audio_decode_memory'),
        library.lookupFunction<
          Int32 Function(
            Pointer<Utf8>,
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
            Pointer<Pointer<Float>>,
            Pointer<Int64>,
            Pointer<Int32>,
            Pointer<Int32>,
          )
        >('qa_audio_decode_range'),
        library.lookupFunction<
          Void Function(Pointer<Float>),
          void Function(Pointer<Float>)
        >('qa_audio_decode_free'),
      );
    } on Object {
      return null;
    }
  }

  /// Decodes [bytes]; null when no decoder recognized the container.
  ///
  /// ⚠️Prefer [decodeRange] when the bytes are a file: this one has to hold
  /// the whole container, and for a movie that is the file's whole size.
  QaDecodedAudio? decode(Uint8List bytes) {
    if (bytes.isEmpty) {
      return null;
    }
    return withNativeBytes(
      bytes,
      (data) => _harvest(
        (samplesOut, frameCountOut, channelsOut, sampleRateOut) => _decode(
          data,
          bytes.length,
          samplesOut,
          frameCountOut,
          channelsOut,
          sampleRateOut,
        ),
      ),
    );
  }

  /// Decodes [length] bytes of [path] starting at [offset]; null when no
  /// decoder recognized the container, the range is not inside the file, or
  /// the file will not open.
  ///
  /// A whole file is `offset: 0` with its own length — the ordinary case
  /// goes through the same door as a carried one, so no caller has to know
  /// which it has.
  QaDecodedAudio? decodeRange(String path, {int offset = 0, required int length}) {
    if (path.isEmpty || offset < 0 || length <= 0) {
      return null;
    }
    final native = path.toNativeUtf8();
    try {
      return _harvest(
        (samplesOut, frameCountOut, channelsOut, sampleRateOut) => _decodeRange(
          native,
          offset,
          length,
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

  /// The four out-parameters, and what to do with what comes back — written
  /// once so the two doors above cannot drift into two answers.
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
      if (format == 0 || samples == nullptr) {
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
        _free(samples);
      }
    } finally {
      calloc.free(sampleRateOut);
      calloc.free(channelsOut);
      calloc.free(frameCountOut);
      calloc.free(samplesOut);
    }
  }
}
