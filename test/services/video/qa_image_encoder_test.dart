import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_image_encoder.dart';

import '../../helpers/native_engine_path.dart';

void main() {
  final enginePath = nativeEngineLibraryPathOrNull();

  setUp(() {
    QaImageEncoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = enginePath;
  });

  tearDown(() {
    debugQaEngineLibraryPathOverride = null;
    QaImageEncoder.debugResetForTests();
  });

  Uint8List gradient(int width, int height) {
    final rgb = Uint8List(width * height * 3);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final i = (y * width + x) * 3;
        rgb[i] = (x * 255) ~/ width;
        rgb[i + 1] = (y * 255) ~/ height;
        rgb[i + 2] = 128;
      }
    }
    return rgb;
  }

  test('encodes a JFIF baseline JPEG with the right dimensions', () {
    final encoder = QaImageEncoder.instance;
    if (encoder == null) {
      if (nativeEngineRequired) {
        fail('QA_REQUIRE_NATIVE=1 but no engine: '
            '$nativeEngineMissingSkipReason');
      }
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    final bytes = encoder.encodeJpg(
      rgb: gradient(64, 48),
      width: 64,
      height: 48,
      quality: 90,
    );
    expect(bytes, isNotNull);
    // SOI … EOI.
    expect(bytes!.sublist(0, 2), [0xFF, 0xD8]);
    expect(bytes.sublist(bytes.length - 2), [0xFF, 0xD9]);
    // The SOF0 marker carries height/width big-endian at +5/+7.
    var sof = -1;
    for (var i = 2; i + 8 < bytes.length; i += 1) {
      if (bytes[i] == 0xFF && bytes[i + 1] == 0xC0) {
        sof = i;
        break;
      }
    }
    expect(sof, greaterThan(0), reason: 'baseline SOF0 expected');
    expect((bytes[sof + 5] << 8) | bytes[sof + 6], 48);
    expect((bytes[sof + 7] << 8) | bytes[sof + 8], 64);
  });

  test('output is byte-deterministic', () {
    final encoder = QaImageEncoder.instance;
    if (encoder == null) {
      if (nativeEngineRequired) {
        fail('QA_REQUIRE_NATIVE=1 but no engine: '
            '$nativeEngineMissingSkipReason');
      }
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    final a = encoder.encodeJpg(
      rgb: gradient(32, 32),
      width: 32,
      height: 32,
      quality: 75,
    );
    final b = encoder.encodeJpg(
      rgb: gradient(32, 32),
      width: 32,
      height: 32,
      quality: 75,
    );
    expect(a, isNotNull);
    expect(a, equals(b));
  });

  test('degenerate input refuses instead of crashing', () {
    final encoder = QaImageEncoder.instance;
    if (encoder == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    expect(
      encoder.encodeJpg(rgb: Uint8List(3), width: 4, height: 4, quality: 90),
      isNull,
    );
  });
}
