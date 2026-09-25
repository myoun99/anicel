import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart'
    show conformPcmToFloat32;

/// A sound this app WROTE as a WAV (`wav16Bytes`) — a take, the count-in's
/// beep — read back without an engine: the 44-byte header it always writes,
/// then 16-bit PCM at the app's one scale. [length] is in frames, as the
/// conform's is.
///
/// 🪦These tests read a take with `decodeConform`, because a take WAS a
/// conform — the very format no decoder reads, which is why a recorded take
/// had no waveform and no sound (card `F-178` ⑥). The decoders themselves
/// are asked in `a_take_is_staged_like_any_carry_test` and `adr_cueing_test`.
({Float32List samples, int channels, int sampleRate, int length})
readWrittenWav(Uint8List bytes) {
  expect(
    String.fromCharCodes(bytes.sublist(0, 4)),
    'RIFF',
    reason: 'a WAV — the file every sound door reads',
  );
  expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
  final view = ByteData.sublistView(bytes);
  final channels = view.getUint16(22, Endian.little);
  final dataBytes = view.getUint32(40, Endian.little);
  final samples = conformPcmToFloat32(
    Uint8List.sublistView(bytes, 44, 44 + dataBytes),
    dataBytes ~/ 2,
  );
  return (
    samples: samples,
    channels: channels,
    sampleRate: view.getUint32(24, Endian.little),
    length: samples.length ~/ channels,
  );
}
