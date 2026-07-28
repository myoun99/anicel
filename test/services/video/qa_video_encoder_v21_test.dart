import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_video_encoder.dart';

import '../../helpers/native_engine_path.dart';

/// ABI v21: the container/codec surface. Real-binary-or-skip, like every
/// native suite; the assertions stay machine-honest (an HEVC MFT may or
/// may not exist) by pinning CONSISTENCY between probe and open.
void main() {
  final enginePath = nativeEngineLibraryPathOrNull();

  setUp(() {
    QaVideoEncoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = enginePath;
  });

  tearDown(() {
    debugQaEngineLibraryPathOverride = null;
    QaVideoEncoder.debugResetForTests();
  });

  QaVideoEncoder? encoderOrSkip() {
    final encoder = QaVideoEncoder.instance;
    if (encoder == null || !encoder.isSupported) {
      if (nativeEngineRequired &&
          (Platform.isWindows || Platform.isMacOS)) {
        fail('QA_REQUIRE_NATIVE=1 but no OS encoder: '
            '$nativeEngineMissingSkipReason');
      }
      markTestSkipped(
        encoder == null
            ? nativeEngineMissingSkipReason
            : 'no OS encoder on this platform',
      );
      return null;
    }
    return encoder;
  }

  test('the baseline pair always probes true', () {
    final encoder = encoderOrSkip();
    if (encoder == null) {
      return;
    }
    expect(encoder.probe(container: 0, codec: 0), isTrue);
  });

  test('Windows: MOV/ProRes probe false and open refuses toward FFmpeg',
      () async {
    final encoder = encoderOrSkip();
    if (encoder == null) {
      return;
    }
    if (!Platform.isWindows) {
      markTestSkipped('the MOV refusal matrix is the Windows one');
      return;
    }
    // MOV of any codec, and ProRes anywhere, are not MF jobs.
    expect(encoder.probe(container: 1, codec: 0), isFalse);
    expect(encoder.probe(container: 1, codec: 4), isFalse);
    expect(encoder.probe(container: 0, codec: 4), isFalse);

    final temp = Directory.systemTemp.createTempSync('qa-v21');
    addTearDown(() => temp.deleteSync(recursive: true));
    final opened = encoder.open(
      path: '${temp.path}${Platform.pathSeparator}refused.mov',
      width: 64,
      height: 48,
      fpsNumerator: 24,
      fpsDenominator: 1,
      container: 1,
      codec: 4,
    );
    expect(opened, isFalse);
    expect(encoder.lastError, contains('FFmpeg'));
  });

  test('HEVC: open succeeds exactly when the probe says so', () async {
    final encoder = encoderOrSkip();
    if (encoder == null) {
      return;
    }
    final probed = encoder.probe(container: 0, codec: 1);
    final temp = Directory.systemTemp.createTempSync('qa-v21-hevc');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } on Object {
        // A straggling encoder handle on Windows can hold the file a beat.
      }
    });
    final path = '${temp.path}${Platform.pathSeparator}probe.mp4';
    // Hardware HEVC MFTs refuse TINY frames (the H.264 sibling refuses
    // 32×32 — the known gotcha) — probe agreement is pinned at a
    // realistic geometry.
    const width = 320;
    const height = 240;
    final opened = encoder.open(
      path: path,
      width: width,
      height: height,
      fpsNumerator: 24,
      fpsDenominator: 1,
      container: 0,
      codec: 1,
    );
    if (opened) {
      // Drive a real tiny encode so "openable" is proven end-to-end.
      final frame = Uint8List.fromList(
        List<int>.filled(width * height * 4, 0x80),
      );
      expect(encoder.writeFrame(frame), isTrue);
      expect(encoder.finish(), isTrue);
      expect(File(path).lengthSync(), greaterThan(500));
    } else {
      encoder.abort();
    }
    expect(
      opened,
      probed,
      reason: 'the picker grays by probe — open must agree with it '
          '(at a realistic frame size)',
    );
  });
}
