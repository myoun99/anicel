import 'dart:typed_data';

import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/straight_rgba_image.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/native_engine_path.dart';

/// ⛔THE NATIVE PASS AND THE DART FALLBACK ARE ONE DECISION, which is what
/// `premultipliedStraightRgba` says at the top of itself — so the rounding
/// rule (`+127`, round-to-nearest, matching the C) has to be pinned as ONE
/// answer that both branches give, not as whichever branch this machine
/// happens to take.
void main() {
  final dllPath = nativeEngineLibraryPathOrNull();

  setUp(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
  });

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  /// Runs the multiply with the engine forced OFF, so the Dart branch is
  /// the one measured no matter what is built here.
  Uint8List dartBranch(Uint8List rgba) {
    QaNativeEngine.debugForceDartFallback = true;
    final result = premultipliedStraightRgba(rgba);
    expect(result.scratch, isNull, reason: 'the Dart branch owns no scratch');
    return Uint8List.fromList(result.pixels);
  }

  /// Edge-biased bytes: 0 and 255 are where the rounding and the opaque
  /// fast path both live.
  Uint8List sample() {
    final bytes = Uint8List(4 * 8);
    const rows = <List<int>>[
      [255, 128, 1, 255],
      [255, 128, 1, 0],
      [255, 128, 1, 128],
      [1, 2, 3, 1],
      [200, 100, 50, 127],
      [255, 255, 255, 254],
      [0, 0, 0, 128],
      [7, 251, 129, 3],
    ];
    for (var row = 0; row < rows.length; row += 1) {
      for (var channel = 0; channel < 4; channel += 1) {
        bytes[row * 4 + channel] = rows[row][channel];
      }
    }
    return bytes;
  }

  test('the multiply rounds to NEAREST and leaves opaque pixels alone', () {
    final source = sample();
    final premultiplied = dartBranch(source);

    for (var i = 0; i < source.length; i += 4) {
      final alpha = source[i + 3];
      expect(premultiplied[i + 3], alpha, reason: 'alpha is carried, not cut');
      for (var channel = 0; channel < 3; channel += 1) {
        expect(
          premultiplied[i + channel],
          (source[i + channel] * alpha + 127) ~/ 255,
          reason:
              'byte ${i + channel}: value ${source[i + channel]} at alpha '
              '$alpha rounds to nearest, not toward zero',
        );
      }
    }

    // Row 2 is (255, 128, 1) at alpha 128, spelled out so the rule reads
    // without doing the arithmetic. 1*128/255 is 0.502: rounding gives 1,
    // and truncation would drop that channel to black.
    expect(premultiplied.sublist(8, 12), <int>[128, 64, 1, 128]);
  });

  test('the caller\'s buffer is never touched', () {
    final source = sample();
    final before = Uint8List.fromList(source);
    dartBranch(source);
    expect(source, before);
  });

  test('the native pass and the Dart fallback agree BYTE FOR BYTE', () {
    if (dllPath == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    final source = sample();

    final native = premultipliedStraightRgba(source);
    expect(
      native.scratch,
      isNotNull,
      reason:
          'the engine is built here, so the native pass must be the one '
          'that ran — a null scratch means this compared Dart with Dart',
    );
    final fromEngine = Uint8List.fromList(native.pixels);
    native.scratch?.free();

    expect(fromEngine, dartBranch(source));
  });
}
