import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart'
    show conformPcmToFloat32;
import 'package:anicel/src/services/audio/wav16_header.dart';

/// A sound this app WROTE as a WAV (`wav16Bytes`) — a take, the count-in's
/// beep — read back without an engine, through the one reader of that
/// header ([readWav16Header]), then 16-bit PCM at the app's one scale.
/// [length] is in frames, as the conform's is.
///
/// 🪦These tests read a take with `decodeConform`, because a take WAS a
/// conform — the very format no decoder reads, which is why a recorded take
/// had no waveform and no sound (card `F-178` ⑥). The decoders themselves
/// are asked in `a_take_is_staged_like_any_carry_test` and `adr_cueing_test`.
({Float32List samples, int channels, int sampleRate, int length})
readWrittenWav(Uint8List bytes) {
  final wav = readWav16Header(bytes);
  expect(wav, isNotNull, reason: 'a WAV — the file every sound door reads');
  final samples = conformPcmToFloat32(
    Uint8List.sublistView(
      bytes,
      wav16HeaderLength,
      wav16HeaderLength + wav!.dataBytes,
    ),
    wav.dataBytes ~/ 2,
  );
  return (
    samples: samples,
    channels: wav.channels,
    sampleRate: wav.sampleRate,
    length: samples.length ~/ wav.channels,
  );
}
