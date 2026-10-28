import 'dart:typed_data';

import 'package:anicel/src/native/qa_video_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real movie at [path] — [frames] grey pictures, 64×48 at 24 fps, with a
/// sound track that holds nothing — written by the engine's own encoder;
/// false where this run has no encoder.
bool writeGreyMovie(String path, {required int frames}) {
  final encoder = QaVideoEncoder.instance;
  if (encoder == null || !encoder.isSupported) {
    return false;
  }
  expect(
    encoder.open(
      path: path,
      width: 64,
      height: 48,
      fpsNumerator: 24,
      fpsDenominator: 1,
      sampleRate: 44100,
      channels: 2,
    ),
    isTrue,
    reason: encoder.lastError,
  );
  final grey = Uint8List(64 * 48 * 4)..fillRange(0, 64 * 48 * 4, 128);
  for (var frame = 0; frame < frames; frame += 1) {
    expect(encoder.writeFrame(grey), isTrue, reason: encoder.lastError);
  }
  expect(encoder.finish(), isTrue, reason: encoder.lastError);
  return true;
}
