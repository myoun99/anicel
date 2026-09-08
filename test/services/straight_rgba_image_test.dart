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

  /// 🚨★★★**A DECODE THAT CANNOT SUCCEED HAS TO SAY SO.**
  ///
  /// `ui.decodeImageFromPixels` chains two futures and attaches an error
  /// handler to neither, so its callback fires once on success and never on
  /// failure — the caller is told nothing at all. Every image upload in this
  /// app wrapped that in a `Completer` with no `completeError`, which turned
  /// one refused frame into a panel that waited for it forever.
  ///
  /// The fixture is the cheapest genuine refusal there is: a descriptor that
  /// claims 64×64 RGBA over four bytes. Nothing validates that
  /// (`ImageDescriptor.raw` does no length check), so the engine gets as far
  /// as building the image and then hands back nothing — the same road a
  /// resize allocation takes when it fails on a small device, which is the
  /// case this exists for and the one a test cannot stage.
  ///
  /// ⚠️`runAsync`: the upload is engine work on a real thread, and the fake
  /// clock does not drive it. Without this the test would pass on a
  /// TIMEOUT-shaped hang rather than on the rejection.
  /// 🚨★★★**AND THE NATIVE SCRATCH COMES BACK ON THE REFUSED ROAD TOO.**
  ///
  /// The premultiply is a bare `malloc` with no `NativeFinalizer` behind it,
  /// and four call sites used to free it inside the decode CALLBACK — which
  /// `ui.decodeImageFromPixels` does not invoke when it refuses. So every
  /// refused decode leaked a whole stamp of native memory: 256 KB at the
  /// production tile size, megabytes at whole-canvas, invisible to the GC
  /// and to every Dart heap number there is. The release is a `finally` now,
  /// and this is the only thing that can tell the two shapes apart.
  test('🚨a refused decode still gives the native scratch back', () async {
    if (dllPath == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    // ⛔Read around the operation, never absolutely: the counter is
    // process-wide and this suite is not the only thing holding scratches.
    final before = QaStampScratch.debugLiveCount;

    await binding.runAsync(() async {
      await expectLater(
        // A descriptor that lies about its buffer's length: the premultiply
        // succeeds and takes a scratch, and the ENGINE is what refuses.
        decodeStraightRgbaImage(rgba: Uint8List(4), width: 64, height: 64),
        throwsA(anything),
      );
    });

    expect(
      QaStampScratch.debugLiveCount,
      before,
      reason: 'the scratch the premultiply took was handed back even though '
          'no image ever arrived',
    );
  });

  group('a refused upload rejects instead of hanging', () {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();

    test('the straight-alpha door', () async {
      await binding.runAsync(() async {
        await expectLater(
          decodeStraightRgbaImage(rgba: Uint8List(4), width: 64, height: 64),
          throwsA(anything),
        );
      });
    });

    test('and the premultiplied one under it', () async {
      await binding.runAsync(() async {
        await expectLater(
          uploadRawRgba(Uint8List(4), width: 64, height: 64),
          throwsA(anything),
        );
      });
    });
  });
}
