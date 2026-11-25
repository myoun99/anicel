import 'dart:typed_data';

/// A container's sound opened once and read on, at its OWN rate — what a
/// conform is made from (`AudioConformPipeline`). The native decoder answers
/// it (`QaAudioDecoder.openSpan`); tests answer it with sound they already
/// hold.
///
/// 🚨★★★**SO A LONG SOUND IS NEVER HELD WHOLE ON ITS WAY IN** (user
/// 2026-10-10, board long-sound-conform-memory-Q1: 「지금 한다 — 전
/// 플랫폼」). The decoder used to hand the whole sound back at once and the
/// resample ran over all of it: 25 minutes of 44.1 kHz stereo was about
/// 1.1 GB in the worker, an hour about 2.6 GB — the size that kills an app on
/// an old tablet.
abstract interface class AudioDecodeStream {
  int get channels;
  int get sampleRate;

  /// Up to [frames] more frames of the sound, interleaved — fewer only at its
  /// end, none past it. Throws [AudioDecodeFailure] where the decoder fails
  /// partway.
  Float32List read(int frames);

  /// How much of the file the decoder has read through so far, 0–1 — the
  /// furthest byte it read of the container's bytes, counted from where the
  /// sound began (the engine's `Stream::read_through`).
  ///
  /// 🗣️유저 11-23 (decoder-reads-skip-the-percent-Q2, 「디코더가 읽은
  /// 바이트를 센다」): what the import window's percent counts while a sound
  /// is made (F-608-Q2: the bytes read of the bytes to read). ↩️The decoder
  /// read the file where the window could not see it, and a movie on the
  /// cloud stood 47 s at one number (🔬저장 11-23, 910 MB).
  double get readThrough;

  /// Lets go of the decoder.
  void close();
}

/// A decoder that opened a sound and then could not read on through it.
class AudioDecodeFailure implements Exception {
  const AudioDecodeFailure(this.message);

  final String message;

  @override
  String toString() => 'AudioDecodeFailure: $message';
}
