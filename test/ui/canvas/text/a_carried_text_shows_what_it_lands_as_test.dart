import 'dart:ui' as ui;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart'
    show bitmapSurfaceRegionPixels;
import 'package:anicel/src/services/cel_surface_as_shown.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/colour_key_shader.dart';
import 'package:anicel/src/ui/canvas/landing_preview.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_float.dart';
import 'package:anicel/src/ui/canvas/tile_picture_budget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/a_plugin_that_shifts.dart';
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
/// does (F-240). On a row that keys a colour away the same holds over ink
/// too, to the byte: what floats there is the landing itself (F-344-Q3,
/// 유저 2026-10-15: 「놓을 때와 같은 코드로 — 완전히 같게」).
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

  /// A tile of [seed]'s pattern, every [clear]th pixel clear, the rest
  /// of alphas that step through partly clear ones.
  BitmapTile patterned(int seed, int size, {required int clear}) {
    final px = Uint8List(BitmapTile.bytesFor(size));
    for (var i = 0; i < size * size; i += 1) {
      final o = i * 4;
      if (i % clear == 0) {
        continue;
      }
      px[o] = (i * 37 + seed * 7) % 256;
      px[o + 1] = (i * 53 + seed * 13) % 256;
      px[o + 2] = (i * 29 + seed * 31) % 256;
      px[o + 3] = 40 + (i * 11 + seed) % 216;
    }
    return BitmapTile(size: size, pixels: px);
  }

  /// A key that takes a colour away where partly clear letters over the
  /// [patterned] ink mix into it, and nowhere else much.
  LayerEffect inkKey() => LayerEffect(
    id: const EffectId('text-tool-key'),
    kind: EffectKind.colorKey,
    colors: {
      'keyColor': PropertyTrack<int>.empty().withKey(0, 0xFFA06464),
    },
    parameters: {
      'tolerance': EffectParameter(value: 80),
      'amount': EffectParameter(value: 100),
    },
  );

  /// [patterned] ink of [seed] over every tile [region] reaches, in place
  /// of the drawing of the cel under the tool — its texts kept.
  Future<void> inkUnder(
    WidgetTester tester,
    Rect region, {
    int seed = 0,
  }) async {
    final cel = celOf(tester);
    final size = cel.tileSize;
    coordinatorOf(tester).restoreSurfaceSnapshot(
      textToolKey,
      BitmapSurface(
        canvasSize: cel.canvasSize,
        tileSize: size,
        tiles: {
          for (var y = region.top ~/ size; y * size < region.bottom; y++)
            for (var x = region.left ~/ size; x * size < region.right; x++)
              TileCoord(x: x, y: y): patterned(
                seed + x + y * 7,
                size,
                clear: 3,
              ),
        },
        texts: cel.texts,
      ),
    );
    await pumpFrames(tester);
  }

  /// A text typed at the middle of the canvas and dragged by its box: the
  /// canvas over the region round it while the hand carries it — [floats]
  /// what the canvas floats there — and once it has landed, read at
  /// [level] — [whileHeld] done while the hand holds it.
  Future<({Uint8List carried, Uint8List landed})> dragged(
    WidgetTester tester, {
    required int level,
    required Matcher floats,
    Future<void> Function()? whileHeld,
  }) async {
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
    if (whileHeld != null) {
      await whileHeld();
      await pumpFrames(tester);
    }
    expect(canvasFloat(tester), floats, reason: '⛔fixture');
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
    return (carried: carried, landed: landed);
  }

  for (final level in [0, 1]) {
    final zoom = '${100 >> level}%';

    testWidgets('a text dragged by its box shows at $zoom the bytes it lands '
        'as', (tester) async {
      await pumpTextToolApp(tester);

      final (:carried, :landed) = await dragged(
        tester,
        level: level,
        floats: isA<CelTextFloat>(),
      );

      expect(differing(carried, landed), 0);
    });

    testWidgets('🚨on a row whose chain runs a PLUGIN a text dragged by its '
        'box shows at $zoom the bytes it lands as — what floats is its '
        'landing (🗣️I-132-Q32 b)', (tester) async {
      await pumpTextToolApp(
        tester,
        project: textToolProject(effects: [shiftingFxPluginLayerEffect()]),
        fxPlugins: await installedShiftingFxPlugin(tester),
      );
      expect(
        theCanvasRowRunsAPlugin(tester),
        isTrue,
        reason: '⛔fixture: the device\'s plugin runs on the canvas',
      );

      final (:carried, :landed) = await dragged(
        tester,
        level: level,
        floats: isA<CelTextLanding>(),
      );

      expect(differing(carried, landed), 0);
    });

    testWidgets('on a row that keys and runs a PLUGIN a text carried at '
        '$zoom shows the bytes it lands as once the device lets the plugin '
        'go while the hand holds it', (tester) async {
      final plugins = await installedShiftingFxPlugin(tester);
      await pumpTextToolApp(
        tester,
        project: textToolProject(
          effects: [inkKey(), shiftingFxPluginLayerEffect()],
        ),
        fxPlugins: plugins,
      );

      final (:carried, :landed) = await dragged(
        tester,
        level: level,
        floats: isA<CelTextLanding>(),
        whileHeld: () async {
          await tester.runAsync(
            () => plugins.uninstall(shiftingFxPluginDescription.id),
          );
          await pumpFrames(tester);
          expect(
            theCanvasRowRunsAPlugin(tester),
            isFalse,
            reason: '⛔fixture: the plugin is gone from the canvas',
          );
        },
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
        canvasFloat(tester),
        isA<CelTextFloat>().having((float) => float.above, 'above', isNotNull),
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

    testWidgets('🚨on a row that KEYS a colour away, a text carried over INK '
        'and under another shows at $zoom the bytes it lands as — the '
        'landing itself floats (F-344-Q3)', (tester) async {
      await pumpTextToolApp(
        tester,
        project: textToolProject(effects: [inkKey()]),
      );
      await takeTextTool(tester);
      final c = canvasPixelInView(tester);
      final region = regionAround(c);
      await inkUnder(tester, region);
      // Partly clear letters, so a letter and the ink under it mix.
      await clickAt(tester, c.dx, c.dy);
      textToolOf(
        tester,
      ).changeLetters((style) => style.copyWith(color: 0x80FF0000));
      await typeText(tester, 'hi');
      await clickAt(tester, c.dx + 300, c.dy + 200);
      await clickAt(tester, c.dx, c.dy + 120);
      textToolOf(
        tester,
      ).changeLetters((style) => style.copyWith(color: 0xB00040FF));
      await typeText(tester, 'yo');
      await clickAt(tester, c.dx + 300, c.dy + 200);
      expect(
        [for (final text in celOf(tester).texts) text.content.text],
        ['hi', 'yo'],
        reason: '⛔fixture: 「yo」 is over 「hi」',
      );
      expect(canvasShows(tester).tiles, isNotEmpty, reason: '⛔fixture: ink');

      // 「hi」 down by (30, 90): over the top half of 「yo」, and over ink.
      final mouse = await pressAt(tester, c.dx + 10, c.dy + 30);
      await mouse.moveTo(onScreen(tester, c.dx + 25, c.dy + 75));
      await tester.pump();
      await mouse.moveTo(onScreen(tester, c.dx + 40, c.dy + 120));
      await tester.pump();
      expect(
        canvasFloat(tester),
        isA<CelTextLanding>(),
        reason: '⛔fixture: lifted — the landing floats',
      );
      final carried = await canvasRaster(tester, region, level: level);
      await mouse.up();
      await pumpFrames(tester);
      final landed = await canvasRaster(tester, region, level: level);

      expect(
        celOf(tester).texts.first.content.anchor,
        isNot(CanvasPoint(x: c.dx, y: c.dy)),
        reason: '⛔fixture: it moved',
      );
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
              kind: EffectKind.colorKey,
              colors: {
                'keyColor': PropertyTrack<int>.empty().withKey(0, 0xFFFF0000),
              },
              parameters: {
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
      expect(canvasFloat(tester), isA<CelTextLanding>(), reason: '⛔fixture');
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

    testWidgets('🚨keyed AGAIN while a text is in hand, it floats through '
        'the row\'s new keys — and so do the texts above it', (tester) async {
      LayerEffect keyOf({int red = 0, int green = 0}) => LayerEffect(
        id: const EffectId('text-tool-key'),
        kind: EffectKind.colorKey,
        colors: {
          'keyColor': PropertyTrack<int>.empty().withKey(
            0,
            0xFF000000 | red << 16 | green << 8,
          ),
        },
        parameters: {
          'amount': EffectParameter(value: 100),
        },
      );
      await pumpTextToolApp(
        tester,
        project: textToolProject(effects: [keyOf(red: 255)]),
      );
      await takeTextTool(tester);
      final c = canvasPixelInView(tester);
      await clickAt(tester, c.dx, c.dy);
      textToolOf(
        tester,
      ).changeLetters((style) => style.copyWith(color: 0xFFFF0000));
      await typeText(tester, 'hi');
      await clickAt(tester, c.dx + 300, c.dy + 200);
      await clickAt(tester, c.dx, c.dy + 120);
      textToolOf(
        tester,
      ).changeLetters((style) => style.copyWith(color: 0xFFFF0000));
      await typeText(tester, 'yo');
      await clickAt(tester, c.dx + 300, c.dy + 200);
      // 「hi」 taken, by its letters at the second click, and typed into:
      // lifted, 「yo」 with it.
      await clickAt(tester, c.dx + 10, c.dy + 30);
      await clickAt(tester, c.dx + 30, c.dy + 55);
      await typeText(tester, 'hiz');
      final region = regionAround(c);
      final width = region.width.toInt();
      List<int> at(Uint8List raster, double dx, double dy) => pixelOf(
        raster,
        width,
        (c.dx - region.left + dx).toInt(),
        (c.dy - region.top + dy).toInt(),
      );
      expect(
        [for (final text in celOf(tester).texts) text.content.text],
        ['hi', 'yo'],
        reason: '⛔fixture: nothing landed yet',
      );
      expect(
        canvasFloat(tester),
        isA<CelTextLanding>(),
        reason: '⛔fixture: lifted — the landing floats',
      );
      final keyed = await canvasRaster(tester, region);
      expect(
        [at(keyed, 10, 10), at(keyed, 10, 130)],
        [
          [0, 0, 0, 0],
          [0, 0, 0, 0],
        ],
        reason: '⛔fixture: the red key takes both off the canvas',
      );

      sessionOf(
        tester,
      ).effectsAndFx.updateLayerEffects(textToolLayerId, [keyOf(green: 255)]);
      await pumpFrames(tester);
      final rekeyed = await canvasRaster(tester, region);
      expect(textToolOf(tester).letters, isNotNull, reason: '⛔fixture');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      final landed = await canvasRaster(tester, region);

      expect(
        [for (final text in celOf(tester).texts) text.content.text],
        ['hiz', 'yo'],
        reason: '⛔fixture: landed',
      );
      expect(
        [at(landed, 10, 10), at(landed, 10, 130)],
        [
          [255, 0, 0, 255],
          [255, 0, 0, 255],
        ],
        reason: '⛔fixture: the green key leaves both',
      );
      expect(differing(rekeyed, landed), 0);
    });

    testWidgets('🚨the picture changed under a carried text is what shows '
        'under it — what floats is made again for the cel as it stands', (
      tester,
    ) async {
      await pumpTextToolApp(
        tester,
        project: textToolProject(effects: [inkKey()]),
      );
      await takeTextTool(tester);
      final c = canvasPixelInView(tester);
      final region = regionAround(c);
      await inkUnder(tester, region);
      await clickAt(tester, c.dx, c.dy);
      textToolOf(
        tester,
      ).changeLetters((style) => style.copyWith(color: 0x80FF0000));
      await typeText(tester, 'hi');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);

      final mouse = await pressAt(tester, c.dx + 10, c.dy + 30);
      await mouse.moveTo(onScreen(tester, c.dx + 30, c.dy + 50));
      await tester.pump();
      expect(canvasFloat(tester), isA<CelTextLanding>(), reason: '⛔fixture');
      final before = await canvasRaster(tester, region);
      // Carried no further, over other ink.
      await inkUnder(tester, region, seed: 5);
      final carried = await canvasRaster(tester, region);
      await mouse.up();
      await pumpFrames(tester);
      final landed = await canvasRaster(tester, region);

      expect(
        differing(before, carried),
        greaterThan(0),
        reason: '⛔premise: the ink under it changed',
      );
      expect(differing(carried, landed), 0);
    });
  });

  group('over a drawing', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    const tile = 16;
    const canvasSize = CanvasSize(width: 64, height: 48);

    var lineages = 0;
    BitmapSurfacePainter painterOf(
      BitmapSurface surface, {
      ValueListenable<LandingPreview?>? landing,
    }) => BitmapSurfacePainter(
      surface: surface,
      showTransparentBackground: false,
      lineage: landing == null
          ? 'f344-${lineages++}'
          : TilePictureBudget.noLineage,
      landingPreview: landing,
    );

    Future<Uint8List> paint(BitmapSurfacePainter painter) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..clipRect(const ui.Rect.fromLTWH(0, 0, 64, 48));
      painter.paintContentInto(canvas, pixelRatio: 1);
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
            TileCoord(x: x, y: y): patterned(x + y * 4, tile, clear: 3),
      };
      final plate = {
        TileCoord(x: 1, y: 1): patterned(20, tile, clear: 5),
        TileCoord(x: 2, y: 1): patterned(21, tile, clear: 7),
      };
      final content = CelTextContent(
        spans: const [
          CelTextSpan(text: 'ab', style: TextLetterStyle(fontSize: 8)),
        ],
        anchor: CanvasPoint(x: 16, y: 16),
      );
      final wall = canvasSize.pasteboardAt(PasteboardReach.whole).rect;
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
            (plate: plate, dx: 5, dy: 3),
            canvasSize: canvasSize,
            pasteboardReach: PasteboardReach.whole,
            tileSize: tile,
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

    /// Text [id] of the tests, its pixels [plate].
    CelText text(int id, Map<TileCoord, BitmapTile> plate) => CelText(
      id: id,
      content: CelTextContent(
        spans: const [
          CelTextSpan(text: 'ab', style: TextLetterStyle(fontSize: 8)),
        ],
        anchor: CanvasPoint(x: 16.0 * id, y: 16),
      ),
      plate: plate,
    );

    /// A text carried over ink — everywhere but tile (2, 2), where it lands
    /// over nothing — on a cel with a text under it and one over it: the
    /// cel without the carried text and the one over it ([under]), what the
    /// hand carries, and the cel once it has landed ([landed]).
    ({
      BitmapSurface under,
      BitmapSurface landed,
      CelText below,
      CelText above,
      CelTextPixels hand,
    })
    carriedOverInk() {
      final drawing = {
        for (var y = 0; y < 3; y += 1)
          for (var x = 0; x < 4; x += 1)
            if (x != 2 || y != 2)
              TileCoord(x: x, y: y): patterned(x + y * 4, tile, clear: 3),
      };
      final below = text(1, {
        TileCoord(x: 0, y: 1): patterned(30, tile, clear: 4),
        TileCoord(x: 1, y: 1): patterned(31, tile, clear: 6),
      });
      final hand = (
        plate: {
          TileCoord(x: 1, y: 1): patterned(20, tile, clear: 5),
          TileCoord(x: 2, y: 1): patterned(21, tile, clear: 7),
          TileCoord(x: 1, y: 2): patterned(22, tile, clear: 2),
        },
        dx: 5,
        dy: 3,
      );
      final above = text(3, {
        TileCoord(x: 2, y: 1): patterned(40, tile, clear: 2),
        TileCoord(x: 2, y: 2): patterned(41, tile, clear: 3),
      });
      final under = BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tile,
        tiles: drawing,
        texts: [below],
      );
      final landed = under.withTexts([
        below,
        text(
          2,
          celTextPlateMoved(
            hand,
            canvasSize: canvasSize,
            pasteboardReach: PasteboardReach.whole,
            tileSize: tile,
          ),
        ),
        above,
      ]);
      return (
        under: under,
        landed: landed,
        below: below,
        above: above,
        hand: hand,
      );
    }

    test('🚨on a row with a colour KEY, a carried text over INK shows what '
        'it lands as to the byte — the landing floats, the texts above it '
        'in their place (F-344-Q3)', () async {
      final keys = [
        ResolvedLayerEffect(
          kind: EffectKind.colorKey,
          values: const [0, 0xFF808080, 100, 100],
        ),
      ];
      final (:under, :landed, :below, :above, :hand) = carriedOverInk();
      final made = celTextLandingAsShown(
        under: under,
        carried: hand,
        above: [above],
        effects: keys,
      )!;
      final landing = CelTextLanding.of(made.region, made.straight);
      addTearDown(landing.picture.dispose);
      BitmapSurfacePainter apart(BitmapSurface surface) => painterOf(
        celSurfaceAsShown(surface, keys),
        landing: ValueNotifier(null),
      );
      final wall = canvasSize.pasteboardAt(PasteboardReach.whole).rect;

      final carried = await paint(
        painterOf(
          celSurfaceAsShown(under.withTexts([below, above]), keys),
          landing: ValueNotifier(landing),
        ),
      );
      final after = await paint(painterOf(celSurfaceAsShown(landed, keys)));

      expect(
        differing(
          await paint(
            painterOf(
              celSurfaceAsShown(under, keys),
              landing: ValueNotifier(
                CelTextFloat(
                  held: SelectionFloatPaint(
                    surface: apart(
                      BitmapSurface(
                        canvasSize: canvasSize,
                        tileSize: tile,
                        tiles: hand.plate,
                      ),
                    ),
                    surfaceOffset: CanvasPoint(
                      x: hand.dx.toDouble(),
                      y: hand.dy.toDouble(),
                    ),
                    clip: wall,
                  ),
                  above: SelectionFloatPaint(
                    surface: apart(
                      BitmapSurface(
                        canvasSize: canvasSize,
                        tileSize: tile,
                        texts: [above],
                      ),
                    ),
                    clip: wall,
                  ),
                ),
              ),
            ),
          ),
          after,
        ),
        greaterThan(0),
        reason: '⛔premise: floated as its own pixels, each keyed by itself, '
            'the text shows other than it lands here',
      );
      expect(differing(carried, after), 0);
    });

    test('🚨on a row whose chain runs a PLUGIN, a carried text over INK '
        'shows what it lands as to the byte — the landing is the whole cel '
        'the plugin makes of it (🗣️I-132-Q32 b)', () async {
      final shifted = [shiftingFxPluginEffect()];
      final (:under, :landed, :below, :above, :hand) = carriedOverInk();
      final made = celTextLandingAsShown(
        under: under,
        carried: hand,
        above: [above],
        effects: shifted,
      )!;
      final landing = CelTextLanding.of(made.region, made.straight);
      addTearDown(landing.picture.dispose);
      final hole = celSurfaceAsShown(under.withTexts([below, above]), shifted);
      final shown = celSurfaceAsShown(landed, shifted);

      final carried = await paint(
        painterOf(hole, landing: ValueNotifier(landing)),
      );
      final after = await paint(painterOf(shown));

      final (:left, :top, :rightExclusive, :bottomExclusive) =
          bitmapSurfaceContentBounds(
            BitmapSurface(
              canvasSize: canvasSize,
              tileSize: tile,
              tiles: celTextPlateMoved(
                hand,
                canvasSize: canvasSize,
                pasteboardReach: PasteboardReach.whole,
                tileSize: tile,
              ),
            ),
          )!;
      final ink = DirtyRegion(
        left: left,
        top: top,
        rightExclusive: rightExclusive,
        bottomExclusive: bottomExclusive,
      );
      final overInkAlone = CelTextLanding.of(
        ink,
        bitmapSurfaceRegionPixels(shown, ink),
      );
      addTearDown(overInkAlone.picture.dispose);
      expect(
        differing(
          await paint(painterOf(hole, landing: ValueNotifier(overInkAlone))),
          after,
        ),
        greaterThan(0),
        reason: '⛔premise: landed over its ink alone, as a key lands it, the '
            'text shows the hole where the plugin moves it past its ink',
      );
      expect(differing(carried, after), 0);
    });

    test('🚨on a row whose PLUGIN reads the whole picture, a carried text '
        'shows what it lands as wherever the cel changes — here it shows '
        'nothing once red is anywhere (🗣️I-132-Q32 b)', () async {
      final effects = [
        ResolvedLayerEffect(
          kind: EffectKind.plugin,
          // Any description with no parameters; the runner is the plugin.
          plugin: shiftingFxPluginDescription,
          values: const [],
          run: fxPluginRunOf(_NothingOnceItHoldsRed()),
        ),
      ];
      /// A tile of [rgba] — whole, or at its first pixel alone.
      BitmapTile tileOf(List<int> rgba, {required bool whole}) {
        final px = Uint8List(BitmapTile.bytesFor(tile));
        for (var i = 0; i < (whole ? tile * tile : 1); i += 1) {
          px.setAll(i * 4, rgba);
        }
        return BitmapTile(size: tile, pixels: px);
      }

      final above = text(3, {
        TileCoord(x: 2, y: 1): tileOf(const [0, 0, 255, 255], whole: true),
      });
      final under = BitmapSurface(canvasSize: canvasSize, tileSize: tile);
      final hand = (
        plate: {
          TileCoord(x: 1, y: 1): tileOf(const [255, 0, 0, 255], whole: false),
        },
        dx: 0,
        dy: 0,
      );
      final landed = under.withTexts([
        text(
          2,
          celTextPlateMoved(
            hand,
            canvasSize: canvasSize,
            pasteboardReach: PasteboardReach.whole,
            tileSize: tile,
          ),
        ),
        above,
      ]);
      final made = celTextLandingAsShown(
        under: under,
        carried: hand,
        above: [above],
        effects: effects,
      );
      expect(made, isNotNull, reason: 'the cel under the hand changes');
      final landing = CelTextLanding.of(made!.region, made.straight);
      addTearDown(landing.picture.dispose);
      final hole = celSurfaceAsShown(under.withTexts([above]), effects);

      final after = await paint(painterOf(celSurfaceAsShown(landed, effects)));

      expect(
        differing(await paint(painterOf(hole)), after),
        greaterThan(0),
        reason: '⛔premise: the text above shows while the red is in hand, '
            'and nothing once it lands',
      );
      expect(
        differing(
          await paint(painterOf(hole, landing: ValueNotifier(landing))),
          after,
        ),
        0,
      );
    });
  });
}

/// Shows the picture as it is, or nothing at all once a pixel of it is
/// opaque red — a plugin whose every pixel hangs on the whole picture, as
/// an auto-levels does.
final class _NothingOnceItHoldsRed implements FxPluginRunner {
  @override
  int? reach(Float64List values, FxPluginMoment moment) => 0;

  @override
  Uint8List? render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) {
    final pixels = input.pixels;
    for (var at = 0; at < pixels.length; at += 4) {
      if (pixels[at] == 255 &&
          pixels[at + 1] == 0 &&
          pixels[at + 2] == 0 &&
          pixels[at + 3] == 255) {
        return Uint8List(pixels.length);
      }
    }
    return Uint8List.fromList(pixels);
  }

  @override
  void close() {}
}
