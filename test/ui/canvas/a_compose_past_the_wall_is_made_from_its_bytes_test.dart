import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/straight_rgba_image.dart';
import 'package:anicel/src/ui/canvas/tiled_surface_compose.dart';

import '../../helpers/native_engine_path.dart';

/// F-374-Q8 ⑦: a compose that reaches past the wall — where only a file's
/// picture laid whole lies — is made from its tiles' bytes and uploaded,
/// not rastered: the same picture, without the 9–15 times the image a
/// raster of it held while it ran (`_composedFromBytes` has the numbers).
/// Its bytes are premultiplied by the engine a run of tiles at a time, or
/// by Dart where there is no engine — both roads are held here.
void main() {
  final dllPath = nativeEngineLibraryPathOrNull();

  setUp(() {
    debugComposesFromBytes = 0;
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
  });

  tearDown(() {
    debugRastersPastTheWall = false;
    debugTilePictureClock = null;
    QaNativeEngine.debugResetForTests();
    QaNativeEngine.debugForceDartFallback = false;
    debugQaEngineLibraryPathOverride = null;
  });

  bool engineMissing() {
    if (dllPath != null && QaNativeEngine.instance != null) {
      return false;
    }
    if (nativeEngineRequired) {
      fail(nativeEngineMissingSkipReason);
    }
    markTestSkipped(nativeEngineMissingSkipReason);
    return true;
  }

  Future<Uint8List> bytesOf(ui.Image image) async => (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();

  /// A tile of 16 with ink in the premultiply's three regimes — clear,
  /// part and whole.
  BitmapTile inked(int seed) {
    final pixels = Uint8List(16 * 16 * 4);
    for (var p = 0; p < 16 * 16; p += 1) {
      pixels[p * 4] = (p * 7 + seed * 31) & 255;
      pixels[p * 4 + 1] = (p * 13) & 255;
      pixels[p * 4 + 2] = (p * 29 + seed) & 255;
      pixels[p * 4 + 3] = (p * 37 + seed * 11) % 256;
    }
    return BitmapTile(size: 16, pixels: pixels);
  }

  /// A file's picture laid whole on a 16×16 canvas (its wall -16..32), a
  /// row of tiles from [left] to [right], one of them left out.
  BitmapSurface laid(int left, int right, {int? without}) => BitmapSurface(
    canvasSize: const CanvasSize(width: 16, height: 16),
    tileSize: 16,
    tiles: {
      for (var x = left; x < right; x += 16)
        if (x != without) TileCoord(x: x ~/ 16, y: 0): inked(x),
    },
    laidBounds: DirtyRegion(
      left: left,
      top: 0,
      rightExclusive: right,
      bottomExclusive: 16,
    ),
  );

  /// [surface] over its ink from its bytes, against the raster of it.
  Future<void> expectTheRastersPicture(BitmapSurface surface) async {
    final over = surfaceInkWorldRect(surface);
    expect(
      over.left < -16 && over.right > 32,
      isTrue,
      reason: 'premise: past the wall on both sides ($over)',
    );
    final fromBytes = (await composePositionedSurfaceImage(
      surface,
      over: over,
    ))!;
    expect(debugComposesFromBytes, 1);
    debugRastersPastTheWall = true;
    final rastered = (await composePositionedSurfaceImage(
      surface,
      over: over,
    ))!;
    debugRastersPastTheWall = false;
    expect(debugComposesFromBytes, 1, reason: 'premise: the hatch rasters');

    expect(fromBytes.worldRect, rastered.worldRect);
    expect(
      [fromBytes.image.width, fromBytes.image.height],
      [rastered.image.width, rastered.image.height],
    );
    expect(await bytesOf(fromBytes.image), await bytesOf(rastered.image));
    fromBytes.image.dispose();
    rastered.image.dispose();
  }

  testWidgets('past the wall the picture is its tiles\' bytes, premultiplied '
      'by the engine — the raster\'s picture byte for byte', (tester) async {
    if (engineMissing()) {
      return;
    }
    expect(kQaEngineAbiVersion, greaterThanOrEqualTo(46));
    await tester.runAsync(
      () => expectTheRastersPicture(laid(-48, 64, without: 16)),
    );
  });

  testWidgets('…and by Dart where there is no engine', (tester) async {
    QaNativeEngine.debugForceDartFallback = true;
    expect(QaNativeEngine.instance, isNull);
    await tester.runAsync(
      () => expectTheRastersPicture(laid(-48, 64, without: 16)),
    );
  });

  testWidgets('inside the wall a compose is rastered as it was — a picture '
      'laid whole that lies within it too', (tester) async {
    await tester.runAsync(() async {
      for (final surface in [
        BitmapSurface(
          canvasSize: const CanvasSize(width: 16, height: 16),
          tileSize: 16,
          tiles: {
            TileCoord(x: -1, y: -1): inked(1),
            TileCoord(x: 1, y: 1): inked(2),
          },
        ),
        laid(-16, 32),
      ]) {
        final composed = (await composePositionedSurfaceImage(surface))!;
        composed.image.dispose();
      }
      expect(debugComposesFromBytes, 0);
    });
  });

  testWidgets('an upload that comes back another size — past what a '
      'device\'s decoder holds — is let go, and the picture rastered', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final surface = laid(-48, 64);
      final over = surfaceInkWorldRect(surface);
      debugRastersPastTheWall = true;
      final rastered = (await composePositionedSurfaceImage(
        surface,
        over: over,
      ))!;
      debugRastersPastTheWall = false;

      // What the device's decoder does past its limit: a smaller picture.
      debugRawRgbaUploader =
          (rgba, {required width, required height, targetWidth, targetHeight}) {
            debugRawRgbaUploader = null;
            return uploadRawRgba(Uint8List(4 * 4 * 4), width: 4, height: 4);
          };
      addTearDown(() => debugRawRgbaUploader = null);
      final composed = (await composePositionedSurfaceImage(
        surface,
        over: over,
      ))!;

      expect(debugComposesFromBytes, 1, reason: 'premise: the bytes first');
      expect(
        [composed.image.width, composed.image.height],
        [rastered.image.width, rastered.image.height],
      );
      expect(await bytesOf(composed.image), await bytesOf(rastered.image));
      composed.image.dispose();
      rastered.image.dispose();
    });
  });

  testWidgets('stood down between its runs of tiles, it makes nothing — '
      'and asks before each run, not only before the upload', (tester) async {
    if (engineMissing()) {
      return;
    }
    await tester.runAsync(() async {
      var clock = 0;
      debugTilePictureClock = () => clock += tilePictureRun.inMicroseconds;
      var asked = 0;
      var uploads = 0;
      debugRawRgbaUploader =
          (rgba, {required width, required height, targetWidth, targetHeight}) {
            uploads += 1;
            debugRawRgbaUploader = null;
            return uploadRawRgba(rgba, width: width, height: height);
          };
      addTearDown(() => debugRawRgbaUploader = null);
      final surface = laid(-48, 64);

      final composed = await composePositionedSurfaceImage(
        surface,
        over: surfaceInkWorldRect(surface),
        shouldAbort: () => (asked += 1) > 2,
      );

      expect(composed, isNull);
      expect(debugComposesFromBytes, 1);
      expect(asked, 3, reason: 'the third run was stood down');
      expect(uploads, 0);
    });
  });
}
