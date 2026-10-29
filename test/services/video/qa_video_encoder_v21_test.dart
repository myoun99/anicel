import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_video_encoder.dart';

import '../../helpers/native_call_watch.dart';
import '../../helpers/native_engine_path.dart';
import '../../helpers/os_video_codec.dart';
import '../../helpers/project_scratch_folder.dart';

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

  test('the baseline pair always probes true', () {
    final encoder = osVideoEncoderOrSkip();
    if (encoder == null) {
      return;
    }
    expect(encoder.probe(container: 0, codec: 0), isTrue);
  });

  test('Windows: MOV/ProRes probe false and open refuses toward FFmpeg',
      () async {
    final encoder = osVideoEncoderOrSkip();
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
    deleteAfterSessionEnds(temp);
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
    // It stood under load too (2026-10-16, board
    // the-trimmed-movie-test-can-hang-on-windows-ci): the watch names the
    // call.
    final watch = await NativeCallWatch.start('HEVC: open as the probe says');
    addTearDown(watch.stop);
    watch.step('asking for the encoder');
    final encoder = osVideoEncoderOrSkip();
    if (encoder == null) {
      return;
    }
    watch.step('probing for an HEVC encoder');
    final probed = encoder.probe(container: 0, codec: 1);
    final temp = Directory.systemTemp.createTempSync('qa-v21-hevc');
    deleteAfterSessionEnds(temp);
    final path = '${temp.path}${Platform.pathSeparator}probe.mp4';
    // Hardware HEVC MFTs refuse TINY frames (the H.264 sibling refuses
    // 32×32 — the known gotcha) — probe agreement is pinned at a
    // realistic geometry.
    const width = 320;
    const height = 240;
    watch.step('opening an HEVC writer');
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
      watch.step('writing a frame');
      expect(encoder.writeFrame(frame), isTrue);
      watch.step('finishing the movie');
      expect(encoder.finish(), isTrue);
      expect(File(path).lengthSync(), greaterThan(500));
    } else {
      watch.step('letting the writer go');
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
