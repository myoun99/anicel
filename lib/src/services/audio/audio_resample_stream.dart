/// Sample-rate conversion (audio program 2B) — what a conform asks of a
/// resampler, and the quality it asks it at. The engine's resampler
/// answers it (`qa_audio_resampler.dart`). Its Dart twin, held to it bit
/// for bit, is a test answer key in the test helpers, the app's fallback
/// no more since the engine always loads (connection-round-checklist H,
/// 관제 2026-11-08 05:58).
library;

import 'dart:typed_data';

/// Stopband attenuation target in dB. 120 puts both the aliasing and the
/// pre-ringing more than 20 dB below the quantization noise of a 16-bit
/// source — under the material's own noise floor.
const double defaultResamplerStopbandDb = 120.0;

/// How much of the available band stays flat, as a fraction of the lower
/// of the two Nyquist limits. The remainder is the transition band.
///
/// 0.90 keeps everything below 19.8 kHz flat on a 44.1k → 48k conform and
/// spends 19.8–22.05 kHz rolling off. Pushing this toward 1.0 costs filter
/// length quadratically for band nobody can hear.
const double defaultResamplerBandwidth = 0.90;

/// A conversion fed a piece at a time — what the next piece needs of the
/// ones before it, carried across. The engine's resampler answers it
/// (`openAudioResampler`), and so does its Dart twin in the tests, bit for
/// bit alike.
///
/// 🚨★★★**THE PIECES' OUTPUTS ARE THE WHOLE CONVERSION'S** (user
/// 2026-10-10, board long-sound-conform-memory-Q1: 「지금 한다 — 전
/// 플랫폼」). A long sound is conformed as the decoder hands it back, so it
/// is never held whole — and an output frame reads the inputs it reads
/// either way, the same taps in the same order. A whole sound's conversion
/// (`resampleAudio`) is the same loop over input that has all arrived.
abstract interface class AudioResampleStream {
  /// Takes [samples] — whole interleaved frames — and answers every output
  /// frame they complete.
  Float32List push(Float32List samples);

  /// Answers the rest, once nothing more comes.
  Float32List finish();

  /// Lets go of what the conversion holds.
  void close();
}
