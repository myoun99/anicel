// The engine's Rust library carries the encoder (rust/src/lib.rs), and its
// names are found in that code asset — no library opened, no path named.
@DefaultAsset(gpuEngineAsset)
library;

import 'dart:convert' show utf8;
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'gpu_engine_asset.dart';
import 'native_scratch.dart';

@Native<Int32 Function()>(symbol: 'qa_video_export_supported')
external int _supported();

@Native<
  Int32 Function(
    Pointer<Utf8>,
    Int32,
    Int32,
    Int32,
    Int32,
    Int32,
    Int32,
    Int32,
    Int32,
    Int32,
    Int32,
  )
>(symbol: 'qa_video_export_open')
external int _open(
  Pointer<Utf8> utf8Path,
  int width,
  int height,
  int fpsNumerator,
  int fpsDenominator,
  int sampleRate,
  int channels,
  int container,
  int codec,
  int alpha,
  int bitrateBps,
);

@Native<Int32 Function(Int32, Int32)>(symbol: 'qa_video_export_probe')
external int _probe(int container, int codec);

@Native<Int32 Function(Pointer<Uint8>)>(symbol: 'qa_video_export_write_frame')
external int _writeFrame(Pointer<Uint8> rgba);

@Native<Int32 Function(Pointer<Int32>)>(symbol: 'qa_video_export_nv12_shape')
external int _nv12Shape(Pointer<Int32> shape);

@Native<Int32 Function(Pointer<Uint8>, Int64)>(
  symbol: 'qa_video_export_write_nv12',
)
external int _writeNv12(Pointer<Uint8> bytes, int stride);

@Native<Int32 Function(Pointer<Int16>, Int32)>(
  symbol: 'qa_video_export_write_audio',
)
external int _writeAudio(Pointer<Int16> interleaved, int frames);

@Native<Int32 Function()>(symbol: 'qa_video_export_audio_lead')
external int _audioLead();

@Native<Int32 Function(Pointer<Int16>, Int32)>(
  symbol: 'qa_video_export_write_lead',
)
external int _writeLead(Pointer<Int16> interleaved, int frames);

@Native<Int32 Function()>(symbol: 'qa_video_export_finish')
external int _finish();

@Native<Void Function()>(symbol: 'qa_video_export_abort')
external void _abort();

@Native<Int32 Function(Pointer<Utf8>, Int32)>(symbol: 'qa_video_export_error')
external int _error(Pointer<Utf8> out, int capacity);

/// The OS video encoder (AUDIO-PRO R7): frames + mixed PCM in, an
/// H.264/AAC MP4 out through the operating system's own codec stack —
/// Media Foundation on Windows, AVAssetWriter on Apple, NDK MediaCodec on
/// Android. No ffmpeg.
///
/// Absence is graceful: a platform with no OS encoder (Linux) leaves
/// [isSupported] false and the caller on the ffmpeg fallback — chosen, not
/// crashed into. The engine itself is wherever the app runs — its library
/// ships with the app, and `flutter test` builds it too — so [instance] is
/// always one. ↩️Until the connection round (connection-round-checklist H,
/// 2026-11-08) it was the C engine's (`qa_video_encode.c`), which a machine
/// could be without, and the instance was null there.
final class QaVideoEncoder {
  QaVideoEncoder._();

  /// The process's one writer, as the engine keeps one job at a time.
  static final QaVideoEncoder instance = QaVideoEncoder._();

  /// Whether THIS build and OS can encode (Android answers by actually
  /// resolving the NDK media symbols).
  bool get isSupported => _supported() != 0;

  /// Whether this platform could take the [container]/[codec] pair
  /// (ABI v21) — the format picker grays what the machine cannot write.
  bool probe({required int container, required int codec}) =>
      _probe(container, codec) != 0;

  /// Opens the output at [path]. [channels] 0 = silent video;
  /// [container]/[codec] follow the ABI v21 values ([alpha] only matters
  /// for ProRes 4444, [bitrateBps] 0 = the encoder's own budget).
  /// Returns false with [lastError] readable on any refusal.
  bool open({
    required String path,
    required int width,
    required int height,
    required int fpsNumerator,
    required int fpsDenominator,
    int sampleRate = 0,
    int channels = 0,
    int container = 0,
    int codec = 0,
    bool alpha = false,
    int bitrateBps = 0,
  }) {
    final pathUtf8 = path.toNativeUtf8();
    try {
      return _open(
            pathUtf8,
            width,
            height,
            fpsNumerator,
            fpsDenominator,
            sampleRate,
            channels,
            container,
            codec,
            alpha ? 1 : 0,
            bitrateBps,
          ) !=
          0;
    } finally {
      calloc.free(pathUtf8);
    }
  }

  /// Writes one top-down RGBA frame of the size [open] was given.
  bool writeFrame(Uint8List rgba) =>
      withNativeBytes(rgba, (buffer) => _writeFrame(buffer) != 0);

  /// The frame the open writer takes as NV12 ([writeNv12]) — the encoder's,
  /// padded even — or none where it takes RGBA ([writeFrame]). Android's
  /// and Apple's H.26x take the GPU engine's NV12 (gpu-export-path ⑶);
  /// Media Foundation and ProRes convert for themselves.
  ({int width, int height})? get nv12Frame => using((arena) {
    final shape = arena<Int32>(2);
    if (_nv12Shape(shape) == 0) {
      return null;
    }
    return (width: shape[0], height: shape[1]);
  });

  /// Writes one frame as the engine made it NV12: [nv12Frame]'s height of
  /// Y rows, then half of it of CbCr rows, each [stride] bytes after the
  /// last.
  bool writeNv12(Uint8List bytes, {required int stride}) =>
      withNativeBytes(bytes, (buffer) => _writeNv12(buffer, stride) != 0);

  /// Writes interleaved int16 PCM ([frames] per channel) — call in chunks
  /// alongside the frames so neither side buffers the whole track.
  bool writeAudio(Int16List interleaved, int frames) =>
      _hand(interleaved, frames, _writeAudio);

  /// The frames of sound this build's writer puts before the mix, for the
  /// caller to fill ([writeLead]) — 0 where it puts none. Windows' writer
  /// puts one AAC frame there and says so in the movie
  /// (`export/windows.rs`, `AUDIO_LEAD`).
  int get audioLead => _audioLead();

  /// Hands the sound just before the mix — [audioLead] frames of it,
  /// interleaved as the mix is, before any [writeAudio]. Silence goes there
  /// when none is handed; false, with [lastError] readable, for any other
  /// count or once sound has gone in.
  bool writeLead(Int16List interleaved, int frames) =>
      _hand(interleaved, frames, _writeLead);

  /// THE copy of int16 sound into the engine's reach, for whichever call
  /// [take]s it (`native_scratch.dart`: the Int16 copy stays here until
  /// that type has three sites — this is still its one).
  static bool _hand(
    Int16List interleaved,
    int frames,
    int Function(Pointer<Int16> interleaved, int frames) take,
  ) {
    final buffer = calloc<Int16>(interleaved.length);
    try {
      buffer.asTypedList(interleaved.length).setAll(0, interleaved);
      return take(buffer, frames) != 0;
    } finally {
      calloc.free(buffer);
    }
  }

  /// Finalizes the MP4 — a cancelled run finalizes a playable partial,
  /// matching the ffmpeg path's behavior.
  bool finish() => _finish() != 0;

  /// Discards an export that failed partway.
  void abort() => _abort();

  /// The last failure, for the export dialog to show verbatim.
  String get lastError {
    final buffer = calloc<Uint8>(256);
    try {
      final length = _error(buffer.cast<Utf8>(), 256);
      if (length <= 0) {
        return '';
      }
      return utf8.decode(buffer.asTypedList(length));
    } finally {
      calloc.free(buffer);
    }
  }
}
