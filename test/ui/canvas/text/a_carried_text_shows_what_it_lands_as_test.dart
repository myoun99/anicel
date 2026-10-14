import 'dart:ui' as ui;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/services/cel_surface_as_shown.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/colour_key_shader.dart';
import 'package:anicel/src/ui/canvas/landing_preview.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_float.dart';
import 'package:anicel/src/ui/canvas/tile_pyramid.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/cel_text_tool_harness.dart';

/// 🚨★★★F-344 — WHILE A HAND CARRIES A TEXT, THE CANVAS SHOWS WHAT IT
/// LANDS AS, AT EVERY ZOOM.
///
/// 🗣️유저 2026-10-12: 「텍스트도구, 잡고 이동할때나 변형할때나 너무 느림.
/// 변형로직같은거 참고/재사용하면서 라이브 빠르게 움직이도록 구조개편」. A text
/// in hand floats over the hole its lifting left (`CelTextFloat`), the way
/// a lifted selection floats, instead of being laid into its cel at every
/// move of the hand. The canvas's own painter is read over one region
/// mid-drag and again once the drag has landed, and the two must be the
/// same bytes — at 100%, and at 50%, where a float composites as its layer
/// does (F-240).
void main() {
  int differing(Uint8List a, Uint8List b) {
    var count = 0;
    for (var i = 0; i < a.length; i += 4) {
      if (a[i] != b[i] ||
          a[i + 1] != b[i + 1] ||
          a[i + 2] != b[i + 2] ||
          a[i + 3] != b[i + 3]) {
        count += 1;
      }
    }
    return count;
  }

  /// The four bytes of the pixel ([x], [y]) of a raster [width] wide.
  List<int> pixelOf(Uint8List raster, int width, int x, int y) {
    final at = (y * width + x) * 4;
    return raster.sublist(at, at + 4);
  }

  /// A region round [c] the tests' texts stay inside, on the grid of every
  /// level.
  Rect regionAround(Offset c) => Rect.fromLTWH(
    (c.dx ~/ 64) * 64 - 64.0,
    (c.dy ~/ 64) * 64 - 64.0,
    384,
    384,
  );

  for (final level in [0, 1]) {
    final zoom = '${100 >> level}%';

    testWidgets('a text dragged by its box shows at $zoom the bytes it lands '
        'as', (tester) async {
      await pumpTextToolApp(tester);
      await takeTextTool(tester);
      final c = canvasPixelInView(tester);
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      final region = regionAround(c);

      final mouse = await pressAt(tester, c.dx + 10, c.dy + 30);
      await mouse.moveTo(onScreen(tester, c.dx + 40, c.dy + 50));
      await tester.pump();
      await mouse.moveTo(onScreen(tester, c.dx + 87, c.dy + 71));
      await tester.pump();
      expect(canvasShows(tester).texts, isEmpty, reason: '⛔fixture: lifted');
      final carried = await canvasRaster(tester, region, level: level);
      await mouse.up();
      await pumpFrames(tester);
      final landed = await canvasRaster(tester, region, level: level);

      expect(
        celOf(tester).texts.single.content.anchor,
        isNot(CanvasPoint(x: c.dx, y: c.dy)),
        reason: '⛔fixture: it moved',
      );
      expect(
        differing(landed, Uint8List(landed.length)),
        greaterThan(0),
        reason: '⛔fixture: it is drawn',
      );
      expect(differing(carried, landed), 0);
    });

    testWidgets('🚨a text carried UNDER another stays under it at $zoom — '
        'the texts above it float with it', (tester) async {
      await pumpTextToolApp(tester);
      await takeTextTool(tester);
      final c = canvasPixelInView(tester);
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');
      await clickAt(tester, c.dx + 300, c.dy + 200);
      await clickAt(tester, c.dx, c.dy + 120);
      textToolOf(
        tester,
      ).changeLetters((style) => style.copyWith(color: 0xFFFF0000));
      await typeText(tester, 'yo');
      await clickAt(tester, c.dx + 300, c.dy + 200);
      expect(
        [for (final text in celOf(tester).texts) text.content.text],
        ['hi', 'yo'],
        reason: '⛔fixture: 「yo」 is over 「hi」',
      );
      expect(
        shownPixel(celOf(tester), c.dx.toInt() + 10, c.dy.toInt() + 10),
        allOf(isNotNull, isNot([255, 0, 0, 255])),
        reason: '⛔fixture: 「hi」 is not red — which is on top shows',
      );
      final region = regionAround(c);

      // 「hi」 down by (30, 90): over the top half of 「yo」.
      final mouse = await pressAt(tester, c.dx + 10, c.dy + 30);
      await mouse.moveTo(onScreen(tester, c.dx + 25, c.dy + 75));
      await tester.pump();
      await mouse.moveTo(onScreen(tester, c.dx + 40, c.dy + 120));
      await tester.pump();
      expect(
        canvasShows(tester).texts,
        isEmpty,
        reason: '⛔fixture: lifted, 「yo」 with it',
      );
      final carried = await canvasRaster(tester, region, level: level);
      await mouse.up();
      await pumpFrames(tester);
      final landed = await canvasRaster(tester, region, level: level);

      // Where the two meet, 「yo」 is on top.
      final width = region.width.toInt() >> level;
      final x = (c.dx - region.left + 60).toInt() >> level;
      final y = (c.dy - region.top + 135).toInt() >> level;
      expect(pixelOf(landed, width, x, y), [255, 0, 0, 255]);
      expect(differing(carried, landed), 0);
    });
  }

  group('on a layer that KEYS a colour away', () {
    // The app loads it before its first frame (`main`).
    setUpAll(ColourKeyShader.load);

    testWidgets('🚨the text carried is keyed as the cel it lands on is — it '
        'floats through the row\'s keys', (tester) async {
      await pumpTextToolApp(
        tester,
        project: textToolProject(
          effects: [
            LayerEffect(
              id: const EffectId('text-tool-key'),
              kind: EffectKind.deleteColor,
              parameters: {
                'keyRed': EffectParameter(value: 255),
                'amount': EffectParameter(value: 100),
              },
            ),
          ],
        ),
      );
      await takeTextTool(tester);
      final c = canvasPixelInView(tester);
      await clickAt(tester, c.dx, c.dy);
      textToolOf(
        tester,
      ).changeLetters((style) => style.copyWith(color: 0xFFFF0000));
      await typeText(tester, 'hi');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      final region = regionAround(c);
      final width = region.width.toInt();
      int across(double dx) => (c.dx - region.left + dx).toInt();
      int down(double dy) => (c.dy - region.top + dy).toInt();
      expect(
        shownPixel(celOf(tester), c.dx.toInt() + 10, c.dy.toInt() + 10),
        [255, 0, 0, 255],
        reason: '⛔fixture: the cel holds red letters',
      );
      expect(
        pixelOf(
          await canvasRaster(tester, region),
          width,
          across(10),
          down(10),
        ),
        [0, 0, 0, 0],
        reason: '⛔fixture: the key takes them off the canvas',
      );

      final mouse = await pressAt(tester, c.dx + 10, c.dy + 30);
      await mouse.moveTo(onScreen(tester, c.dx + 30, c.dy + 40));
      await tester.pump();
      await mouse.moveTo(onScreen(tester, c.dx + 57, c.dy + 41));
      await tester.pump();
      expect(canvasShows(tester).texts, isEmpty, reason: '⛔fixture: lifted');
      final carried = await canvasRaster(tester, region);
      await mouse.up();
      await pumpFrames(tester);
      final landed = await canvasRaster(tester, region);

      expect(
        pixelOf(carried, width, across(57), down(21)),
        [0, 0, 0, 0],
        reason: 'keyed while it floats, as it is where it lands',
      );
      expect(differing(carried, landed), 0);
    });
  });

  group('over a drawing', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    const tile = 16;
    const canvasSize = CanvasSize(width: 64, height: 48);

    /// A tile of [seed]'s pattern, every [clear]th pixel clear, the rest
    /// of alphas that step through partly clear ones.
    BitmapTile patterned(int seed, {required int clear}) {
      final px = Uint8List(BitmapTile.bytesFor(tile));
      for (var i = 0; i < tile * tile; i += 1) {
        final o = i * 4;
        if (i % clear == 0) {
          continue;
        }
        px[o] = (i * 37 + seed * 7) % 256;
        px[o + 1] = (i * 53 + seed * 13) % 256;
        px[o + 2] = (i * 29 + seed * 31) % 256;
        px[o + 3] = 40 + (i * 11 + seed) % 216;
      }
      return BitmapTile(size: tile, pixels: px);
    }

    var lineages = 0;
    BitmapSurfacePainter painterOf(
      BitmapSurface surface, {
      ValueListenable<LandingPreview?>? landing,
    }) => BitmapSurfacePainter(
      surface: surface,
      showTransparentBackground: false,
      lineage: landing == null ? 'f344-${lineages++}' : TilePyramid.noLineage,
      landingPreview: landing,
    );

    Future<Uint8List> paint(BitmapSurfacePainter painter) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..clipRect(const ui.Rect.fromLTWH(0, 0, 64, 48));
      painter.paintContentInto(canvas);
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 48);
      picture.dispose();
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      image.dispose();
      return bytes;
    }

    test('🚨a carried text\'s partly clear pixels over INK are within ONE '
        'of what it lands as — the float is blended where the landing is '
        'stamped (the transform tool\'s float, the same cost)', () async {
      final drawing = {
        for (var y = 0; y < 3; y += 1)
          for (var x = 0; x < 4; x += 1)
            TileCoord(x: x, y: y): patterned(x + y * 4, clear: 3),
      };
      final plate = {
        TileCoord(x: 1, y: 1): patterned(20, clear: 5),
        TileCoord(x: 2, y: 1): patterned(21, clear: 7),
      };
      final content = CelTextContent(
        spans: const [
          CelTextSpan(text: 'ab', style: TextLetterStyle(fontSize: 8)),
        ],
        anchor: CanvasPoint(x: 16, y: 16),
      );
      final wall = canvasSize.pasteboardRect;
      final hole = BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tile,
        tiles: drawing,
      );
      final float = CelTextFloat(
        held: SelectionFloatPaint(
          surface: painterOf(
            BitmapSurface(canvasSize: canvasSize, tileSize: tile, tiles: plate),
            landing: ValueNotifier(null),
          ),
          surfaceOffset: CanvasPoint(x: 5, y: 3),
          clip: wall,
        ),
        above: null,
      );
      final landed = hole.withTexts([
        CelText(
          id: 1,
          content: content,
          plate: celTextPlateMoved(
            plate,
            canvasSize: canvasSize,
            tileSize: tile,
            dx: 5,
            dy: 3,
          ),
        ),
      ]);

      final carried = await paint(
        painterOf(hole, landing: ValueNotifier(float)),
      );
      final after = await paint(painterOf(landed));

      var apart = 0;
      var most = 0;
      for (var i = 0; i < after.length; i += 1) {
        final by = (carried[i] - after[i]).abs();
        if (by > 0) {
          apart += 1;
        }
        if (by > most) {
          most = by;
        }
      }
      debugPrint('F-344 over ink: $apart bytes apart, at most $most');
      expect(differing(after, Uint8List(after.length)), greaterThan(0));
      expect(most, lessThanOrEqualTo(1), reason: '$apart bytes apart');
    });

    test('⚠️on a row with a colour KEY, a carried text shows other than it '
        'lands only where it lies over INK — it is keyed by itself, and the '
        'landing keys it with the ink under it (F-344-Q1)', () async {
      final keys = [
        ResolvedLayerEffect(
          kind: EffectKind.deleteColor,
          values: const [128, 128, 128, 100, 100],
        ),
      ];
      final drawing = {
        for (var y = 0; y < 3; y += 1)
          for (var x = 0; x < 4; x += 1)
            TileCoord(x: x, y: y): patterned(x + y * 4, clear: 3),
      };
      final plate = {
        TileCoord(x: 1, y: 1): patterned(20, clear: 5),
        TileCoord(x: 2, y: 1): patterned(21, clear: 7),
      };
      final moved = celTextPlateMoved(
        plate,
        canvasSize: canvasSize,
        tileSize: tile,
        dx: 5,
        dy: 3,
      );
      final hole = BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tile,
        tiles: drawing,
      );
      final float = CelTextFloat(
        held: SelectionFloatPaint(
          surface: painterOf(
            celSurfaceAsShown(
              BitmapSurface(
                canvasSize: canvasSize,
                tileSize: tile,
                tiles: plate,
              ),
              keys,
            ),
            landing: ValueNotifier(null),
          ),
          surfaceOffset: CanvasPoint(x: 5, y: 3),
          clip: canvasSize.pasteboardRect,
        ),
        above: null,
      );
      final landed = hole.withTexts([
        CelText(
          id: 1,
          content: CelTextContent(
            spans: const [
              CelTextSpan(text: 'ab', style: TextLetterStyle(fontSize: 8)),
            ],
            anchor: CanvasPoint(x: 16, y: 16),
          ),
          plate: moved,
        ),
      ]);
      int alphaOf(Map<TileCoord, BitmapTile> tiles, int x, int y) =>
          tiles[TileCoord(x: x ~/ tile, y: y ~/ tile)]?.readPixels(
            (_, view) => view[((y % tile) * tile + x % tile) * 4 + 3],
          ) ??
          0;

      final carried = await paint(
        painterOf(celSurfaceAsShown(hole, keys), landing: ValueNotifier(float)),
      );
      final after = await paint(painterOf(celSurfaceAsShown(landed, keys)));

      var apart = 0;
      var offInk = 0;
      for (var y = 0; y < canvasSize.height; y += 1) {
        for (var x = 0; x < canvasSize.width; x += 1) {
          final at = (y * canvasSize.width + x) * 4;
          var most = 0;
          for (var channel = 0; channel < 4; channel += 1) {
            final by = (carried[at + channel] - after[at + channel]).abs();
            most = by > most ? by : most;
          }
          if (most <= 1) {
            continue;
          }
          apart += 1;
          if (alphaOf(moved, x, y) == 0 || alphaOf(drawing, x, y) == 0) {
            offInk += 1;
          }
        }
      }
      debugPrint('F-344 keyed over ink: $apart pixels apart');
      expect(
        differing(
          await paint(painterOf(hole)),
          await paint(painterOf(celSurfaceAsShown(hole, keys))),
        ),
        greaterThan(0),
        reason: '⛔fixture: the key takes some of the ink',
      );
      expect(offInk, 0, reason: '$apart pixels apart');
    });
  });
}
