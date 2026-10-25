import 'dart:async';
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

import '../../helpers/cel_text_fixture.dart' show textOf;
import '../../helpers/native_engine_path.dart';
import '../../helpers/one_piece.dart';

/// F-374-Q8 ⑦: a compose that reaches past the wall — where only a file's
/// picture laid whole lies — is made from its tiles' bytes and uploaded,
/// not rastered: the same picture, without the 9–15 times the image a
/// raster of it held while it ran (`_composedFromBytes` has the numbers).
/// Its bytes are premultiplied by the engine a tile at a time, paced as a
/// raster's pictures are, or by Dart where there is no engine — both roads
/// are held here.
void main() {
  final dllPath = nativeEngineLibraryPathOrNull();

  // The corpus holds a clock of its own (`flutter_test_config.dart`): it is
  // handed back, not dropped for the wall's.
  int Function()? corpusClock;

  setUp(() {
    debugComposesFromBytes = 0;
    corpusClock = debugTilePictureClock;
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
  });

  tearDown(() {
    debugRastersPastTheWall = false;
    debugRawRgbaUploader = null;
    debugTilePictureClock = corpusClock;
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

  /// A tile of 16 [at] its place with ink in the premultiply's three
  /// regimes — clear, part and whole — and none outside [lies].
  BitmapTile inked(int seed, {required TileCoord at, ui.Rect? lies}) {
    final pixels = Uint8List(16 * 16 * 4);
    for (var p = 0; p < 16 * 16; p += 1) {
      final x = at.x * 16 + p % 16 + 0.5;
      final y = at.y * 16 + p ~/ 16 + 0.5;
      if (lies != null && !lies.contains(ui.Offset(x, y))) {
        continue;
      }
      pixels[p * 4] = (p * 7 + seed * 31) & 255;
      pixels[p * 4 + 1] = (p * 13) & 255;
      pixels[p * 4 + 2] = (p * 29 + seed) & 255;
      pixels[p * 4 + 3] = (p * 37 + seed * 11) % 256;
    }
    return BitmapTile(size: 16, pixels: pixels);
  }

  /// A file's picture laid whole on a 16×16 canvas (its wall -16..32), a
  /// row of tiles from [left] to [right], one of them left out — lying in
  /// the tiles, or in [lies] within them.
  BitmapSurface laid(int left, int right, {int? without, ui.Rect? lies}) {
    final where = lies ?? ui.Rect.fromLTRB(left * 1.0, 0, right * 1.0, 16);
    return BitmapSurface(
      canvasSize: const CanvasSize(width: 16, height: 16),
      tileSize: 16,
      tiles: {
        for (var x = left; x < right; x += 16)
          if (x != without)
            TileCoord(x: x ~/ 16, y: 0): inked(
              x,
              at: TileCoord(x: x ~/ 16, y: 0),
              lies: lies,
            ),
      },
      laidBounds: DirtyRegion.wholePixelsOf(where),
    );
  }

  /// Where [pastTheWallWithAText] lies: past the wall on both sides, and
  /// through its edge tiles' clear pixels on every side — as a compose
  /// over where a picture lies cuts them (`_celMoved`).
  const lies = ui.Rect.fromLTRB(-45, 2, 61, 14);

  /// A tile left out inside the wall — and a text over the first tile: a
  /// picture is shown with its texts laid over it (R9-rest, 유저
  /// 2026-10-06: 「셀의 그림이랑 정확히 동일」).
  BitmapSurface pastTheWallWithAText() =>
      laid(-48, 64, without: 16, lies: lies).withTexts([
        textOf(
          1,
          plate: {
            TileCoord(x: -3, y: 0): inked(
              99,
              at: TileCoord(x: -3, y: 0),
              lies: lies,
            ),
          },
        ),
      ]);

  /// [surface] composed over [over] from its bytes, against the raster.
  Future<void> expectTheRastersPicture(
    BitmapSurface surface, {
    required ui.Rect over,
  }) async {
    expect(
      over.left < -16 && over.right > 32,
      isTrue,
      reason: 'premise: past the wall on both sides ($over)',
    );
    var uploads = 0;
    Future<ui.Image> counted(
      Uint8List rgba, {
      required int width,
      required int height,
      int? targetWidth,
      int? targetHeight,
    }) {
      uploads += 1;
      debugRawRgbaUploader = null;
      try {
        return uploadRawRgba(
          rgba,
          width: width,
          height: height,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
        );
      } finally {
        debugRawRgbaUploader = counted;
      }
    }

    debugRawRgbaUploader = counted;
    final fromBytes = (await composePositionedSurfaceImage(
      surface,
      over: over,
    ))!;
    expect(debugComposesFromBytes, 1);
    expect(uploads, 1, reason: 'made from its bytes, and uploaded');
    debugRastersPastTheWall = true;
    final rastered = (await composePositionedSurfaceImage(
      surface,
      over: over,
    ))!;
    debugRastersPastTheWall = false;
    debugRawRgbaUploader = null;
    expect(debugComposesFromBytes, 1, reason: 'premise: the hatch rasters');
    expect(uploads, 1, reason: 'premise: a raster uploads nothing');

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
      'by the engine — the raster\'s picture byte for byte, its texts and '
      'all', (tester) async {
    if (engineMissing()) {
      return;
    }
    expect(kQaEngineAbiVersion, greaterThanOrEqualTo(46));
    await tester.runAsync(
      () => expectTheRastersPicture(pastTheWallWithAText(), over: lies),
    );
  });

  testWidgets('…and by Dart where there is no engine', (tester) async {
    QaNativeEngine.debugForceDartFallback = true;
    expect(QaNativeEngine.instance, isNull);
    await tester.runAsync(
      () => expectTheRastersPicture(pastTheWallWithAText(), over: lies),
    );
  });

  testWidgets('inside the wall a compose is rastered as it was — a picture '
      'laid whole that lies within it too, and a cel whose tile straddles '
      'the wall: its rect reaches past it, and nothing lies there', (
    tester,
  ) async {
    // A 20×16 canvas's wall is -20..40: a tile at 32..48 straddles it, its
    // ink cut at the wall as every stroke is.
    const wall = ui.Rect.fromLTRB(-20, -16, 40, 32);
    final straddling = BitmapSurface(
      canvasSize: const CanvasSize(width: 20, height: 16),
      tileSize: 16,
      tiles: {
        TileCoord(x: 2, y: 0): inked(3, at: TileCoord(x: 2, y: 0), lies: wall),
      },
    );
    expect(
      surfaceContentWorldRect(straddling).right,
      greaterThan(wall.right),
      reason: 'premise: its rect reaches past the wall',
    );
    await tester.runAsync(() async {
      for (final surface in [
        BitmapSurface(
          canvasSize: const CanvasSize(width: 16, height: 16),
          tileSize: 16,
          tiles: {
            TileCoord(x: -1, y: -1): inked(1, at: TileCoord(x: -1, y: -1)),
            TileCoord(x: 1, y: 1): inked(2, at: TileCoord(x: 1, y: 1)),
          },
        ),
        laid(-16, 32),
        straddling,
      ]) {
        final composed = (await composePositionedSurfaceImage(surface))!;
        composed.image.dispose();
      }
      expect(debugComposesFromBytes, 0);
    });
  });

  testWidgets('an upload that comes back another size — past what a '
      'device\'s decoder holds, on either side — is let go, and the '
      'picture rastered', (tester) async {
    await tester.runAsync(() async {
      final surface = laid(-48, 64);
      final over = surfaceInkWorldRect(surface);
      debugRastersPastTheWall = true;
      final rastered = (await composePositionedSurfaceImage(
        surface,
        over: over,
      ))!;
      debugRastersPastTheWall = false;
      final wide = rastered.image.width;
      final high = rastered.image.height;

      for (final (uploadedWidth, uploadedHeight) in [
        // What this device's decoder does past its limit: narrower, its
        // height kept.
        (wide - 12, high),
        (wide, high - 8),
      ]) {
        debugComposesFromBytes = 0;
        Future<ui.Image> comesBackShort(
          Uint8List rgba, {
          required int width,
          required int height,
          int? targetWidth,
          int? targetHeight,
        }) {
          debugRawRgbaUploader = null;
          return uploadRawRgba(
            Uint8List(uploadedWidth * uploadedHeight * 4),
            width: uploadedWidth,
            height: uploadedHeight,
          );
        }

        debugRawRgbaUploader = comesBackShort;
        final composed = (await composePositionedSurfaceImage(
          surface,
          over: over,
        ))!;

        final upload = '${uploadedWidth}x$uploadedHeight';
        expect(debugComposesFromBytes, 1, reason: 'premise: the bytes first');
        expect(
          [composed.image.width, composed.image.height],
          [wide, high],
          reason: upload,
        );
        expect(
          await bytesOf(composed.image),
          await bytesOf(rastered.image),
          reason: upload,
        );
        composed.image.dispose();
      }
      rastered.image.dispose();
    });
  });

  testWidgets('stood down before it uploads, it uploads nothing', (
    tester,
  ) async {
    QaNativeEngine.debugForceDartFallback = true;
    await tester.runAsync(() async {
      var uploads = 0;
      debugRawRgbaUploader =
          (rgba, {required width, required height, targetWidth, targetHeight}) {
            uploads += 1;
            return uploadRawRgba(rgba, width: width, height: height);
          };
      final surface = laid(-48, 64);

      expect(
        await composePositionedSurfaceImage(
          surface,
          over: surfaceInkWorldRect(surface),
          shouldAbort: () => true,
        ),
        isNull,
      );
      expect(debugComposesFromBytes, 1);
      expect(uploads, 0);
    });
  });

  group('in turn it gives way as a raster does', () {
    // A test's clock, moved on a quarter of a run by every check before a
    // tile: the queue's turn comes before the fifth tile, the ninth, the
    // thirteenth (the raster's own group in `tiled_surface_compose_test`).
    var clock = 0;
    final aQuarterOfARun = tilePictureRun.inMicroseconds ~/ 4;
    bool Function() checking(bool Function() abandoned) => () {
      clock += aQuarterOfARun;
      return abandoned();
    };

    setUp(() {
      clock = 0;
      debugTilePictureClock = () => clock;
    });

    /// A picture laid past the wall, [tiles] tiles in a row.
    BitmapSurface rowOf(int tiles) => laid(-48, -48 + tiles * 16);

    Future<PositionedSurfaceImage?> composed(
      BitmapSurface surface, {
      required bool Function() shouldAbort,
      MissingTilePictures missing = MissingTilePictures.madeInTurn,
    }) => composePositionedSurfaceImage(
      surface,
      over: surfaceInkWorldRect(surface),
      shouldAbort: shouldAbort,
      missing: missing,
    );

    testWidgets('🚨what was waiting in the event queue is heard before a '
        'compose longer than a run is done — and a compose somebody waits '
        'for does not stop for it', (tester) async {
      if (engineMissing()) {
        return;
      }
      await tester.runAsync(() async {
        var heard = false;
        Timer.run(() => heard = true);
        expect(
          await composed(rowOf(5), shouldAbort: checking(() => heard)),
          isNull,
          reason: 'what was waiting was let in when the run was up, and it '
              'stood the compose down',
        );
        expect(heard, isTrue);
        expect(debugComposesFromBytes, 1, reason: 'premise: the bytes road');

        clock = 0;
        var heardInARun = false;
        Timer.run(() => heardInARun = true);
        final oneRun = await composed(
          rowOf(4),
          shouldAbort: checking(() => heardInARun),
        );
        expect(
          oneRun,
          isNotNull,
          reason: 'a run is made in one go: nothing was let in before its '
              'last tile, nor before the upload after it',
        );
        oneRun!.image.dispose();

        // A render somebody waits for — an export's frame — never gives way.
        clock = 0;
        var heardAtOnce = false;
        Timer.run(() => heardAtOnce = true);
        final atOnce = await composed(
          rowOf(5),
          missing: MissingTilePictures.madeAtOnce,
          shouldAbort: checking(() => heardAtOnce),
        );
        expect(atOnce, isNotNull);
        atOnce!.image.dispose();
        expect(debugComposesFromBytes, 3);
      });
    });

    testWidgets('once a RUN, not once a tile', (tester) async {
      if (engineMissing()) {
        return;
      }
      await tester.runAsync(() async {
        // Every turn of the event queue from here on is counted: each one,
        // when it comes, asks for the next.
        var turns = 0;
        var counting = true;
        void count() {
          if (counting) {
            turns += 1;
            Timer.run(count);
          }
        }

        Timer.run(count);
        var turnsAtTheLastCheck = -1;
        final image = await composed(
          // Three whole runs, and one tile more.
          rowOf(13),
          shouldAbort: checking(() {
            turnsAtTheLastCheck = turns;
            return false;
          }),
        );
        counting = false;
        image!.image.dispose();
        expect(debugComposesFromBytes, 1, reason: 'premise: the bytes road');
        expect(
          turnsAtTheLastCheck,
          3,
          reason: 'the queue had its turn after each of the three runs, '
              'and at no other tile',
        );
      });
    });
  });
}
