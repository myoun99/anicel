import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/media_asset.dart' show MediaFitMode;
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/guide_geometry.dart' show GuideTransform;
import 'package:anicel/src/services/import/cel_picture.dart';
import 'package:anicel/src/services/import/raster_cel_import.dart';

import '../../helpers/checker_sampling.dart';

/// A 1:1 integer-aligned placement must be a BYTE COPY, not a resample:
/// bicubic (FilterQuality.high) blurs even at identity — a hard black
/// line came back 28/255 gray — and the text bake's contract is that the
/// store pixels ARE the engine render.
void main() {
  testWidgets('an exactly canvas-sized image round-trips through '
      'layCelPicture byte-identically', (tester) async {
    await tester.runAsync(() async {
      const canvas = CanvasSize(width: 64, height: 64);
      final recorder = ui.PictureRecorder();
      final paint = ui.Canvas(recorder);
      paint.drawRect(
        const ui.Rect.fromLTWH(0, 0, 64, 64),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      // Hard 1px black line — the cubic kernel's favorite victim.
      paint.drawRect(
        const ui.Rect.fromLTWH(0, 31, 64, 1),
        ui.Paint()..color = const ui.Color(0xFF000000),
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(64, 64);
      picture.dispose();
      final expected = (await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!.buffer.asUint8List();

      final surface = await layCelPicture(
        picture: EnginePicture(image),
        canvas: canvas,
        placement: fitPlacement(
          CanvasSize(width: image.width, height: image.height),
          canvas,
          MediaFitMode.stretch,
        ),
        tileSize: 64,
      );
      image.dispose();

      final tile = surface.tiles.values.single;
      expect(tile.pixels, expected, reason: 'identity means identity');
    });
  });

  // 🗣️I-120-Q26 (유저 2026-11-07 「굽기를 화면에 맞춘다 — 확대된 그림은
  // 계단 그대로 굽는다」): a placement that grows a picture lays it as the
  // canvas shows it, hard-edged — the display's nearest at the cel's own
  // resolution. ↩️It resampled every placement but 1:1 (I-68: 「or a paper
  // drawn twice its size would come out in blocks」).
  testWidgets('🎯grown, a picture is laid in blocks, as the canvas shows it', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const canvas = CanvasSize(width: 64, height: 64);
      final recorder = ui.PictureRecorder();
      final paint = ui.Canvas(recorder);
      // A hard black | white edge, two pixels across.
      paint.drawRect(
        const ui.Rect.fromLTWH(0, 0, 1, 1),
        ui.Paint()..color = const ui.Color(0xFF000000),
      );
      paint.drawRect(
        const ui.Rect.fromLTWH(1, 0, 1, 1),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(2, 1);
      picture.dispose();

      // Four times its size at a whole-pixel origin: each pixel four times,
      // where a smooth resample blends the two where they meet.
      final surface = await layCelPicture(
        picture: EnginePicture(image),
        canvas: canvas,
        placement: const GuideTransform(4, 0, 0, 4, 0, 0),
        tileSize: 64,
      );
      image.dispose();

      final pixels = surface.tiles.values.single.pixels;
      expect(
        [for (var x = 0; x < 8; x += 1) pixels[(64 + x) * 4]],
        [0, 0, 0, 0, 255, 255, 255, 255],
      );
    });
  });

  // 🗣️I-120-Q28 (「축소도 같은 법 — 화면처럼 최근접으로 굽는다」): shrunk or
  // turned, each pixel takes the one the canvas would — of one-pixel
  // squares, black or white, never the grey a smooth one mixes.
  for (final (how, placement) in [
    ('halved', const GuideTransform(0.5, 0, 0, 0.5, 0, 0)),
    ('shrunk by 0.3', const GuideTransform(0.3, 0, 0, 0.3, 0, 0)),
    (
      'turned 45°',
      GuideTransform(
        math.cos(math.pi / 4),
        math.sin(math.pi / 4),
        -math.sin(math.pi / 4),
        math.cos(math.pi / 4),
        32,
        0,
      ),
    ),
  ]) {
    testWidgets('🎯$how, a picture is laid hard-edged, as the canvas shows '
        'it', (tester) async {
      await tester.runAsync(() async {
        final checker = await checkerImage(64);
        final surface = await layCelPicture(
          picture: EnginePicture(checker),
          canvas: const CanvasSize(width: 64, height: 64),
          placement: placement,
          tileSize: 64,
        );
        checker.dispose();

        // The canvas's own tile: a turn reaches the pasteboard too.
        final pixels = surface.tiles[TileCoord(x: 0, y: 0)]!.pixels;
        // Well inside what each lay covers: the turned square's middle, the
        // shrunk ones' top-left.
        final at = how.startsWith('turned') ? (30, 30) : (4, 4);
        final reds = [
          for (var y = at.$2; y < at.$2 + 8; y += 1)
            for (var x = at.$1; x < at.$1 + 8; x += 1)
              pixels[(y * 64 + x) * 4],
        ];
        expect(reds.every(isPure), isTrue, reason: '$reds');
      });
    });
  }

  // F-374-Q8 ⑦: a picture is laid a block of tiles at a time
  // ([layRasterSide]), so no ONE raster of it passes what a device makes —
  // and its tiles are the tiles one raster of it all makes: a copy byte for
  // byte, every pixel the picture covers whole within one step. 🔬Measured
  // 2026-10-18 on this renderer (one tile a block against one raster): a
  // copy 0 bytes apart, a scale 1 byte by 1, and a TURN's outermost ring —
  // the pixels its edge only partly covers — up to 57/255 apart in alpha,
  // the edge's coverage reckoned within each block. Neither ring is the
  // reference; the pin is everything inside it.
  group('laid a block at a time', () {
    setUp(() => debugLayRasters = 0);
    tearDown(() => debugLayRasterSide = null);

    /// 200×120 of hard edges and a ramp — what a resample shows first.
    ui.Image patterned() {
      final recorder = ui.PictureRecorder();
      final paint = ui.Canvas(recorder);
      for (var x = 0; x < 200; x += 10) {
        paint.drawRect(
          ui.Rect.fromLTWH(x.toDouble(), 0, 10, 120),
          ui.Paint()..color = ui.Color.fromARGB(255, x, 255 - x, x ~/ 2),
        );
      }
      paint.drawLine(
        ui.Offset.zero,
        const ui.Offset(200, 120),
        ui.Paint()
          ..color = const ui.Color(0xFF000000)
          ..strokeWidth = 3,
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(200, 120);
      picture.dispose();
      return image;
    }

    Future<Map<TileCoord, List<int>>> laid(
      ui.Image image,
      GuideTransform placement,
    ) async {
      final surface = await layCelPicture(
        picture: EnginePicture(image),
        canvas: const CanvasSize(width: 256, height: 256),
        placement: placement,
        tileSize: 64,
        whole: true,
      );
      return {
        for (final entry in surface.tiles.entries)
          entry.key: entry.value.pixels,
      };
    }

    /// Lays [placement] once and then a tile a block, and hands back both.
    Future<(Map<TileCoord, List<int>>, Map<TileCoord, List<int>>)> bothWays(
      GuideTransform placement,
    ) async {
      final image = patterned();
      try {
        final once = await laid(image, placement);
        expect(debugLayRasters, 1, reason: 'premise: one raster');

        debugLayRasterSide = 64;
        debugLayRasters = 0;
        final inBlocks = await laid(image, placement);

        expect(once.length, greaterThan(1), reason: 'premise: many tiles');
        expect(
          debugLayRasters,
          greaterThanOrEqualTo(once.length),
          reason: 'a raster a tile',
        );
        expect(inBlocks.keys, unorderedEquals(once.keys));
        return (once, inBlocks);
      } finally {
        image.dispose();
      }
    }

    testWidgets('copied 1:1, each tile laid in a block of its own is the '
        'tile one raster made, byte for byte', (tester) async {
      await tester.runAsync(() async {
        final (once, inBlocks) = await bothWays(
          const GuideTransform(1, 0, 0, 1, 37, 21),
        );

        for (final coord in once.keys) {
          expect(inBlocks[coord], once[coord], reason: '$coord');
        }
      });
    });

    testWidgets('turned and grown, every pixel the picture covers whole is '
        'the one raster\'s, within a step', (tester) async {
      await tester.runAsync(() async {
        const turn = math.pi / 6;
        final (once, inBlocks) = await bothWays(
          GuideTransform(
            1.3 * math.cos(turn),
            1.3 * math.sin(turn),
            -1.3 * math.sin(turn),
            1.3 * math.cos(turn),
            90.25,
            -20.5,
          ),
        );

        var covered = 0;
        for (final coord in once.keys) {
          final a = once[coord]!;
          final b = inBlocks[coord]!;
          for (var p = 0; p < a.length; p += 4) {
            if (a[p + 3] != 255 || b[p + 3] != 255) {
              continue; // The ring a turned edge partly covers.
            }
            covered += 1;
            for (var k = 0; k < 3; k += 1) {
              expect(
                (a[p + k] - b[p + k]).abs(),
                lessThanOrEqualTo(1),
                reason: '$coord pixel ${p ~/ 4}',
              );
            }
          }
        }
        expect(covered, greaterThan(10000), reason: 'premise: the inside');
      });
    });
  });
}
