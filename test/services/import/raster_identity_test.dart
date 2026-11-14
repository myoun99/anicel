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
      const canvas = CanvasSize(width: 128, height: 128);
      final recorder = ui.PictureRecorder();
      final paint = ui.Canvas(recorder);
      paint.drawRect(
        const ui.Rect.fromLTWH(0, 0, 128, 128),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      // Hard 1px black line — the cubic kernel's favorite victim.
      paint.drawRect(
        const ui.Rect.fromLTWH(0, 63, 128, 1),
        ui.Paint()..color = const ui.Color(0xFF000000),
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(128, 128);
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
      const canvas = CanvasSize(width: 128, height: 128);
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
      );
      image.dispose();

      final pixels = surface.tiles.values.single.pixels;
      expect(
        [for (var x = 0; x < 8; x += 1) pixels[(128 + x) * 4]],
        [0, 0, 0, 0, 255, 255, 255, 255],
      );
    });
  });

  // 🗣️I-120-Q28 (「축소도 같은 법 — 화면처럼 최근접으로 굽는다」): shrunk or
  // turned, each pixel takes the one the canvas would — of one-pixel
  // squares, black or white, never the grey a smooth one mixes, its edge
  // as hard as the canvas draws it. ↩️Read well inside what each lay
  // covered while Flutter laid it, its edge antialiased (🔬2026-11-11).
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
          canvas: const CanvasSize(width: 128, height: 128),
          placement: placement,
        );
        checker.dispose();

        // The canvas's own tile, its every byte: a turn reaches the
        // pasteboard too.
        final pixels = surface.tiles[TileCoord(x: 0, y: 0)]!.pixels;
        expect(pixels.toSet(), {0, 255});
      });
    });
  }

  // F-374-Q8 ⑦: a picture is laid a block of tiles at a time
  // ([layRasterSide]), so no ONE raster of it passes what a device makes —
  // and its tiles are the tiles one run of it all makes, byte for byte,
  // each pixel the texel its centre lands on whatever block it is laid in
  // (the engine's Nearest). ↩️A turn's outermost ring — the pixels its edge
  // only partly covers — came out up to 57/255 apart in alpha, and a scale
  // a step, while Flutter laid it a raster a block (🔬2026-10-18).
  group('laid a block at a time', () {
    setUp(() => debugLayRuns = 0);
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
        whole: true,
      );
      return {
        for (final entry in surface.tiles.entries)
          entry.key: entry.value.pixels,
      };
    }

    /// Lays [placement] once and then a piece of a tile a run, and hands
    /// back both.
    Future<(Map<TileCoord, List<int>>, Map<TileCoord, List<int>>)> bothWays(
      GuideTransform placement,
    ) async {
      final image = patterned();
      try {
        final once = await laid(image, placement);
        expect(debugLayRuns, 1, reason: 'premise: one run');

        debugLayRasterSide = 64;
        debugLayRuns = 0;
        final inBlocks = await laid(image, placement);

        expect(once.length, greaterThan(1), reason: 'premise: many tiles');
        expect(
          debugLayRuns,
          greaterThan(once.length),
          reason: 'more than a run a tile',
        );
        expect(inBlocks.keys, unorderedEquals(once.keys));
        return (once, inBlocks);
      } finally {
        image.dispose();
      }
    }

    for (final (how, placement) in [
      ('copied 1:1', const GuideTransform(1, 0, 0, 1, 37, 21)),
      (
        'turned and grown',
        GuideTransform(
          1.3 * math.cos(math.pi / 6),
          1.3 * math.sin(math.pi / 6),
          -1.3 * math.sin(math.pi / 6),
          1.3 * math.cos(math.pi / 6),
          90.25,
          -20.5,
        ),
      ),
    ]) {
      testWidgets('$how, each tile laid in pieces of its own is the tile '
          'one run made, byte for byte', (tester) async {
        await tester.runAsync(() async {
          final (once, inBlocks) = await bothWays(placement);

          for (final coord in once.keys) {
            expect(inBlocks[coord], once[coord], reason: '$coord');
          }
        });
      });
    }
  });
}
