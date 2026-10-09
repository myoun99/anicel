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
