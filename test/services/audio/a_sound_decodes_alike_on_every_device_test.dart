import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_decoder.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';

import '../../helpers/decode_audio_file.dart';
import '../../helpers/pinned_fingerprints.dart';

/// 🧭관제 (audio-same-across-devices ③, 2026-11-05): a conform rebuilt on
/// another device holds the same samples (user, gpu-same-formula-Q2) — so
/// each bundled decoder's output is pinned in the one fingerprint ledger,
/// and the release builds' parity step runs this file on ARM64 (TestFlight,
/// the Mac build, windows-11-arm) where the CI shards run it on x64.
///
/// The MP3 and FLAC were made once on Windows 11 by its own encoders
/// (MediaTranscoder, `CreateMp3` · `CreateFlac` at Medium) from a one-second
/// stereo source: a sweep on the left, a chord on the right, a 220 Hz tone
/// on both, four clicks. That gives the MP3 mid/side frames and every block
/// type, and the FLAC LPC subframes. The WAV is written here from whole
/// numbers by the app's own writer.
///
/// The ogg and the two AAC movies are the bundled decoder's too since the
/// connection round (connection-round-checklist H, 2026-11-08): symphonia
/// with `libm`'s maths, one fingerprint for every device (native/audio's
/// `pins.rs`, which reads these rows). ↩️They waited here — the Vorbis
/// tables on one deterministic set of cos/sin (관제 12:10), the AAC on the
/// OS's decoder, which may differ by device (관제 12:01) — and the MP3's row
/// was dr_mp3's samples until then.
void main() {
  void expectPinned(
    QaDecodedAudio? decoded, {
    required QaAudioFormat format,
    required int channels,
    required int sampleRate,
    required int frames,
    required String ledgerId,
  }) {
    expect(decoded, isNotNull, reason: 'nothing decoded it');
    expect(
      (decoded!.format, decoded.channels, decoded.sampleRate, decoded.length),
      (format, channels, sampleRate, frames),
    );
    final samples = decoded.samples;
    expect(
      fingerprintHex(
        samples.buffer.asUint8List(
          samples.offsetInBytes,
          samples.lengthInBytes,
        ),
      ),
      pinnedFingerprint(ledgerId),
    );
  }

  test('the MP3 decodes to the pinned samples', () {
    expectPinned(
      decodeAudioFile('test/fixtures/tone.mp3'),
      format: QaAudioFormat.mp3,
      channels: 2,
      sampleRate: 44100,
      frames: 44975,
      ledgerId: 'audio/tone.mp3-samples',
    );
  });

  test('the FLAC decodes to the pinned samples', () {
    expectPinned(
      decodeAudioFile('test/fixtures/tone.flac'),
      format: QaAudioFormat.flac,
      channels: 2,
      sampleRate: 44100,
      frames: 44100,
      ledgerId: 'audio/tone.flac-samples',
    );
  });

  test('the ogg decodes to the pinned samples', () {
    expectPinned(
      decodeAudioFile('test/fixtures/tone.ogg'),
      format: QaAudioFormat.vorbis,
      channels: 2,
      sampleRate: 44100,
      frames: 22050,
      ledgerId: 'audio/tone.ogg-samples',
    );
  });

  test('a movie\'s AAC decodes to the pinned samples', () {
    for (final (name, frames) in [
      ('tone.m4a', 22050),
      ('tone_with_video.mp4', 22528),
    ]) {
      expectPinned(
        decodeAudioFile('test/fixtures/$name'),
        format: QaAudioFormat.aac,
        channels: 2,
        sampleRate: 44100,
        frames: frames,
        ledgerId: 'audio/$name-samples',
      );
    }
  });

  test('the WAV decodes to the pinned samples', () {
    expectPinned(
      decodeAudioBytes(wholeNumberWav()),
      format: QaAudioFormat.wav,
      channels: 2,
      sampleRate: 48000,
      frames: 4800,
      ledgerId: 'audio/whole-number.wav-samples',
    );
  });
}

/// Two channels of whole numbers at 48 kHz: a full-scale sawtooth on the
/// left, a linear congruential stream on the right.
Uint8List wholeNumberWav() {
  const frames = 4800;
  final pcm = Int16List(frames * 2);
  var seed = 0x2545F491;
  for (var index = 0; index < frames; index += 1) {
    pcm[index * 2] = ((index * 1031) & 0xFFFF) - 0x8000;
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    pcm[index * 2 + 1] = (seed >> 15) - 0x8000;
  }
  return wav16Bytes(pcm, sampleRate: 48000, channels: 2);
}
