import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/sync_image_upload.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/native_scratch.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/cel_text_laying.dart';
import 'package:anicel/src/services/straight_rgba_image.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/level_image.dart';
import 'package:anicel/src/ui/canvas/surface_region_picture.dart';
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
        composePositionedSurfaceImageSync(
          surface,
          reuse: BitmapTileImageCache(),
          makePictures: true,
          snapshot: false,
        )!.deferred.image.dispose();
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

  group('made now, for a row that was on screen', () {
    // The test runner draws its pictures (Skia) and has no upload made
    // now: the door's own drawing stands in for it.
    tearDown(() => debugWholePictureUploader = null);

    ({PositionedSurfaceImage deferred, Future<List<ui.Image>>? real}) madeNow(
      BitmapSurface surface,
      BitmapTileImageCache reuse,
    ) => composePositionedSurfaceImageSync(
      surface,
      reuse: reuse,
      makePictures: true,
      snapshot: true,
      over: lies,
    )!;

    Future<Uint8List> rasteredNow(BitmapSurface surface) async {
      final composes = debugComposesFromBytes;
      debugRastersPastTheWall = true;
      final rastered = madeNow(surface, BitmapTileImageCache());
      debugRastersPastTheWall = false;
      expect(
        debugComposesFromBytes,
        composes,
        reason: 'premise: the hatch rasters',
      );
      final kept = (await rastered.real!).single;
      rastered.deferred.image.dispose();
      try {
        return await bytesOf(kept);
      } finally {
        kept.dispose();
      }
    }

    testWidgets('past the wall it is made from its bytes, in memory of its '
        'own — the raster\'s picture, no tile pictured, and kept as it is', (
      tester,
    ) async {
      if (engineMissing()) {
        return;
      }
      await tester.runAsync(() async {
        final surface = pastTheWallWithAText();
        final shown = celSurfaceWithTextsLaid(surface);
        Uint8List? premultiplied;
        debugWholePictureUploader = (bytes) {
          premultiplied = bytes.readPremultiplied(Uint8List.fromList);
          return pictureOf(bytes);
        };
        final reuse = BitmapTileImageCache();
        NativeScratch.releaseAll();

        final now = madeNow(surface, reuse);

        expect(debugComposesFromBytes, 1);
        expect(
          NativeScratch.liveBytes,
          lessThan(now.deferred.image.width * now.deferred.image.height * 4),
          reason: 'the engine\'s scratch did not grow to hold it',
        );
        expect(
          premultiplied,
          SurfaceRegionBytes(
            shown,
            DirtyRegion.wholePixelsOf(lies),
          ).readPremultiplied(Uint8List.fromList),
          reason: 'the door\'s bytes, premultiplied where they lie',
        );
        expect(
          shown.tiles.values.where((tile) => reuse.imageFor(tile) != null),
          isEmpty,
          reason: 'no tile was pictured for it',
        );
        expect(now.deferred.worldRect, lies);
        final want = await rasteredNow(surface);
        expect(await bytesOf(now.deferred.image), want);
        final kept = (await now.real!).single;
        now.deferred.image.dispose();
        expect(
          await bytesOf(kept),
          want,
          reason: 'the one kept is the same picture, on a handle of its own',
        );
        kept.dispose();
      });
    });

    testWidgets('a row that was NOT on screen is not made now past the wall '
        '— not even with every tile pictured — but inside it, it is', (
      tester,
    ) async {
      await tester.runAsync(() async {
        for (final (surface, over, made) in [
          (laid(-48, 64, lies: lies), lies, false),
          (laid(-16, 32), const ui.Rect.fromLTRB(-16, 0, 32, 16), true),
        ]) {
          final reuse = BitmapTileImageCache();
          for (final tile in surface.tiles.values) {
            reuse.pictureFor(tile);
          }
          final composed = composePositionedSurfaceImageSync(
            surface,
            reuse: reuse,
            makePictures: false,
            snapshot: false,
            over: over,
          );
          expect(composed != null, made, reason: '$over');
          composed?.deferred.image.dispose();
        }
        expect(debugComposesFromBytes, 0);
      });
    });

    testWidgets('an upload refused, or come back another size, is the '
        'raster, as it always was', (tester) async {
      await tester.runAsync(() async {
        final surface = pastTheWallWithAText();
        final want = await rasteredNow(surface);
        /// A picture of [surface] the size of [left]..[right] by
        /// [top]..[bottom] — not the size asked for.
        ui.Image Function() sized(int left, int top, int right, int bottom) =>
            () => pictureOf(
              SurfaceRegionBytes(
                surface,
                DirtyRegion(
                  left: left,
                  top: top,
                  rightExclusive: right,
                  bottomExclusive: bottom,
                ),
              ),
            );
        for (final (refusal, upload) in <(String, ui.Image? Function())>[
          ('refused', () => null),
          // Narrower, its height kept — what this device's decoder does
          // past its limit — and shorter, its width kept.
          ('narrower', sized(-45, 2, 41, 14)),
          ('shorter', sized(-45, 2, 61, 6)),
        ]) {
          debugComposesFromBytes = 0;
          debugWholePictureUploader = (_) => upload();
          final now = madeNow(surface, BitmapTileImageCache());

          expect(debugComposesFromBytes, 1, reason: 'premise: $refusal');
          expect(await bytesOf(now.deferred.image), want, reason: refusal);
          final kept = (await now.real!).single;
          expect(await bytesOf(kept), want, reason: refusal);
          now.deferred.image.dispose();
          kept.dispose();
        }
      });
    });
  });

  group('🗣️its first level is made from its bytes too, halved through the '
      'engine\'s own table (a-big-reference-picture-still-costs-when-'
      'zoomed-out)', () {
    // On the halving grid past the wall — corners even — holding its ink.
    const half = ui.Rect.fromLTRB(-46, 2, 62, 14);

    /// Two rows of tiles laid past the wall across — so a tile's half lands
    /// rows down in the level as well as along it — over [twoRowsHalf].
    BitmapSurface twoRowsPastTheWall() {
      const where = ui.Rect.fromLTRB(-45, 3, 61, 29);
      return BitmapSurface(
        canvasSize: const CanvasSize(width: 16, height: 16),
        tileSize: 16,
        tiles: {
          for (var x = -3; x < 4; x += 1)
            for (var y = 0; y < 2; y += 1)
              TileCoord(x: x, y: y): inked(
                x * 2 + y,
                at: TileCoord(x: x, y: y),
                lies: where,
              ),
        },
        laidBounds: DirtyRegion.wholePixelsOf(where),
      );
    }

    const twoRowsHalf = ui.Rect.fromLTRB(-46, 2, 62, 30);

    /// The Surface Pro 11's halving (`the_cpu_halving_is_the_engines_test`).
    int deviceRule(int sum) =>
        sum % 4 == 2 && sum != 510 ? sum ~/ 4 : (sum + 2) ~/ 4;

    /// [bytes], [width] wide, halved by [deviceRule] block by block.
    Uint8List halvedByRule(Uint8List bytes, int width) {
      final height = bytes.length ~/ (width * 4);
      final halved = Uint8List(bytes.length ~/ 4);
      for (var y = 0; y < height ~/ 2; y += 1) {
        for (var x = 0; x < width ~/ 2; x += 1) {
          for (var channel = 0; channel < 4; channel += 1) {
            int at(int dx, int dy) =>
                bytes[((2 * y + dy) * width + 2 * x + dx) * 4 + channel];
            halved[(y * (width ~/ 2) + x) * 4 + channel] = deviceRule(
              at(0, 0) + at(1, 0) + at(0, 1) + at(1, 1),
            );
          }
        }
      }
      return halved;
    }

    setUp(debugForgetMeasuredHalving);

    tearDown(() {
      debugEngineHalving = null;
      debugWholePictureUploader = null;
      debugForgetMeasuredHalving();
    });

    /// The device's engine, to the measure: the test runner's own halves a
    /// tie two ways and has no table.
    void halvingAsTheDevice() => debugEngineHalving = (bytes, width, _) async =>
        halvedByRule(bytes, width);

    /// The picture over [half] at full size — its bytes, the raster's byte
    /// for byte (pinned above) — halved by [deviceRule].
    Future<Uint8List> wantHalved(
      BitmapSurface surface, {
      ui.Rect over = half,
    }) async {
      final full = (await composePositionedSurfaceImage(surface, over: over))!;
      try {
        return halvedByRule(await bytesOf(full.image), full.image.width);
      } finally {
        full.image.dispose();
      }
    }

    for (final byDart in [false, true]) {
      testWidgets(
        byDart
            ? '…and by Dart where there is no engine'
            : 'its tiles\' bytes premultiplied by the engine and halved a '
                  'tile at a time — the full picture halved, texel for texel',
        (tester) async {
          if (!byDart && engineMissing()) {
            return;
          }
          QaNativeEngine.debugForceDartFallback = byDart;
          halvingAsTheDevice();
          await tester.runAsync(() async {
            for (final (surface, over, size) in [
              (pastTheWallWithAText(), half, (54, 6)),
              (twoRowsPastTheWall(), twoRowsHalf, (54, 14)),
            ]) {
              final want = await wantHalved(surface, over: over);
              debugComposesFromBytes = 0;

              final level = (await composeHalvedSurfaceImage(
                surface,
                over: over,
              ))!.image;

              expect(debugComposesFromBytes, 1, reason: '$over');
              expect((level.width, level.height), size);
              expect(await bytesOf(level), want, reason: '$over');
              level.dispose();
            }
          });
        },
      );
    }

    testWidgets('🔬with no table — the test runner\'s own engine has none — '
        'it is the halved raster, as it always was', (tester) async {
      await tester.runAsync(() async {
        final surface = pastTheWallWithAText();
        debugRastersPastTheWall = true;
        final rastered = (await composeHalvedSurfaceImage(
          surface,
          over: half,
        ))!.image;
        debugRastersPastTheWall = false;

        final level =
            (await composeHalvedSurfaceImage(surface, over: half))!.image;

        expect(measuredHalvingIfRead, isNull, reason: '⛔전제: no table');
        expect(debugComposesFromBytes, 0);
        expect(await bytesOf(level), await bytesOf(rastered));
        level.dispose();
        rastered.dispose();
      });
    });

    testWidgets('made now: rastered until the table has been read, from its '
        'bytes after — and nothing on the free road', (tester) async {
      if (engineMissing()) {
        return;
      }
      halvingAsTheDevice();
      await tester.runAsync(() async {
        final surface = pastTheWallWithAText();
        Uint8List? uploaded;
        debugWholePictureUploader = (bytes) {
          uploaded = bytes.readPremultiplied(Uint8List.fromList);
          final recorder = ui.PictureRecorder();
          ui.Canvas(recorder);
          final picture = recorder.endRecording();
          try {
            return picture.toImageSync(bytes.width, bytes.height);
          } finally {
            picture.dispose();
          }
        };
        ({ui.Image deferred, Future<ui.Image>? real})? madeNow({
          bool makePictures = true,
        }) => composeHalvedSurfaceImageSync(
          surface,
          makePictures: makePictures,
          snapshot: true,
          over: half,
        )?.onePiece;

        final before = madeNow()!;
        expect(debugComposesFromBytes, 0, reason: 'no table yet: rastered');
        before.deferred.dispose();
        (await before.real!).dispose();

        await measuredHalving();
        final want = await wantHalved(surface);
        debugComposesFromBytes = 0;
        final now = madeNow()!;
        expect(debugComposesFromBytes, 1);
        expect(uploaded, want, reason: 'its bytes halved, uploaded now');
        expect((now.deferred.width, now.deferred.height), (54, 6));
        now.deferred.dispose();
        (await now.real!).dispose();

        expect(
          madeNow(makePictures: false),
          isNull,
          reason: 'past the wall a level is no free compose either',
        );
      });
    });

    testWidgets('inside the wall a level is rastered as it was, with a '
        'table read', (tester) async {
      halvingAsTheDevice();
      await tester.runAsync(() async {
        expect(await measuredHalving(), isNotNull, reason: '⛔전제');
        final surface = laid(-16, 32);
        const over = ui.Rect.fromLTRB(-16, 0, 32, 16);
        (await composeHalvedSurfaceImage(surface, over: over))!.image.dispose();
        composeHalvedSurfaceImageSync(
          surface,
          makePictures: true,
          snapshot: false,
          over: over,
        )!.deferred.image.dispose();
        expect(debugComposesFromBytes, 0);
      });
    });
  });
}
