import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/models/composite_tree.dart';

/// 🚨★★★A GROUP IS AN IMAGE — AND IT IS THE SAME PIXELS `saveLayer` MADE.
///
/// The editing stack used to composite a folder with `saveLayer`. It now
/// rasterises the folder to a `ui.Image` and blits it, because a saveLayer
/// offscreen belongs to Skia and nobody can sample it: a fragment shader on
/// a FOLDER needs the group as pixels, and so does a per-group cache.
///
/// ⚠️The existing route-parity tests cannot certify that swap. They compare
/// the buffered route against the direct walk — and BOTH changed, so a
/// systematic error would agree with itself. This file compares the new
/// technique against the old one directly, in isolation, at the geometry
/// the stack actually uses.
///
/// 📐The stack's normal route composites into a recorder whose CTM is
/// `translate(-rect.left, -rect.top)` with an INTEGER rect and scale 1, so
/// the group blit is 1:1 on the device grid. That is the class this file
/// pins as an identity. A fractional device phase is measured separately
/// and stated rather than assumed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const deviceWidth = 96;
  const deviceHeight = 64;

  void drawBackdrop(Canvas canvas, double scale) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, deviceWidth / scale, deviceHeight / scale),
      Paint()
        ..color = const Color(0xFF204060)
        ..isAntiAlias = false,
    );
  }

  // ⛔Anti-aliasing OFF and edges on whole units: this file is about the
  // COMPOSITE, and an aliased edge would fold rasterisation phase into the
  // same number and make a pass or a fail impossible to attribute.
  void drawChildren(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(10, 8, 24, 20),
      Paint()
        ..color = const Color(0xFFE04030)
        ..isAntiAlias = false,
    );
    canvas.drawRect(
      const Rect.fromLTWH(26, 18, 20, 22),
      Paint()
        ..color = const Color(0x8030A0FF)
        ..isAntiAlias = false,
    );
  }

  // ⛔THE PRODUCTION FUNCTION, not a copy of it. A second copy of this
  // arithmetic here would certify the copy and let the original drift —
  // mutate [drawSubtreeAsImage] and this file must go red.
  void drawGroupAsImage(
    Canvas canvas,
    Rect groupRect,
    Paint paint,
    double scale,
    int maxPixelSide,
  ) => drawSubtreeAsImage(
    canvas: canvas,
    bounds: groupRect,
    rasterScale: scale,
    maxPixelSide: maxPixelSide,
    paintSubtree: (into, _) => drawChildren(into),
    compose: (blit) => blit(paint),
  );

  Future<Uint8List> render({
    required Paint groupPaint,
    required Rect groupRect,
    required bool asImage,
    double scale = 1,
    double devicePhase = 0,
    int maxPixelSide = 8192,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(devicePhase, devicePhase);
    canvas.scale(scale);
    drawBackdrop(canvas, scale);
    if (asImage) {
      drawGroupAsImage(canvas, groupRect, groupPaint, scale, maxPixelSide);
    } else {
      canvas.saveLayer(groupRect, groupPaint);
      drawChildren(canvas);
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(deviceWidth, deviceHeight);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  int differingPixels(Uint8List a, Uint8List b) {
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

  Future<void> expectSamePixels(
    String what, {
    required Paint Function() groupPaint,
    Rect groupRect = const Rect.fromLTWH(6, 4, 46, 42),
    double scale = 1,
  }) async {
    final layered = await render(
      groupPaint: groupPaint(),
      groupRect: groupRect,
      asImage: false,
      scale: scale,
    );
    final imaged = await render(
      groupPaint: groupPaint(),
      groupRect: groupRect,
      asImage: true,
      scale: scale,
    );
    // ⛔An all-transparent pair would pass this trivially. Prove the scene
    // actually drew before believing the two agree about it.
    expect(
      layered.any((byte) => byte != 0),
      isTrue,
      reason: '$what drew nothing at all',
    );
    expect(
      differingPixels(layered, imaged),
      0,
      reason: '$what: the image blit must be the saveLayer, pixel for pixel',
    );
  }

  group('the group image is the saveLayer it replaced', () {
    test('plain — no opacity, no blend, no effect', () async {
      await expectSamePixels(
        'plain',
        groupPaint: () => Paint()..color = const Color(0xFF000000),
      );
    });

    test('folder opacity', () async {
      await expectSamePixels(
        'opacity 0.5',
        groupPaint: () => Paint()..color = const Color(0x80000000),
      );
    });

    test('folder blend mode', () async {
      await expectSamePixels(
        'multiply',
        groupPaint: () => Paint()
          ..color = const Color(0xFF000000)
          ..blendMode = BlendMode.multiply,
      );
      await expectSamePixels(
        'screen at half opacity',
        groupPaint: () => Paint()
          ..color = const Color(0x80000000)
          ..blendMode = BlendMode.screen,
      );
    });

    test('folder colour filter', () async {
      await expectSamePixels(
        'saturation matrix',
        groupPaint: () => Paint()
          ..color = const Color(0xFF000000)
          ..colorFilter = const ColorFilter.matrix(<double>[
            0.6, 0.3, 0.1, 0, 0, //
            0.2, 0.7, 0.1, 0, 0, //
            0.2, 0.3, 0.5, 0, 0, //
            0, 0, 0, 1, 0, //
          ]),
      );
    });

    test(
      'folder blur — the same blur, at the same extent',
      () async {
        // The stack inflates the group rect by the blur's spread before it
        // gets here ([effectBufferBounds]), so this rect is what the stack
        // would hand in: content plus spread.
        await expectSamePixels(
          'blur sigma 3',
          groupRect: const Rect.fromLTWH(-3, -5, 64, 60),
          groupPaint: () => Paint()
            ..color = const Color(0xFF000000)
            ..imageFilter = ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        );
      },
    );

    test('a fractional group rect still lands on the same pixels', () async {
      await expectSamePixels(
        'fractional bounds',
        groupRect: const Rect.fromLTWH(6.37, 4.82, 46.4, 42.1),
        groupPaint: () => Paint()
          ..color = const Color(0xC0000000)
          ..blendMode = BlendMode.multiply,
      );
    });

    test('above 100% — every device pixel still matches', () async {
      await expectSamePixels(
        'scale 2',
        scale: 2,
        groupPaint: () => Paint()
          ..color = const Color(0xC0000000)
          ..blendMode = BlendMode.multiply,
      );
    });
  });

  group('the grid it rasterised on, read rather than inferred', () {
    // ⛔Pixel equality alone let four broken grids through: a scene where the
    // drift lands on transparent margin reports "same pixels" about
    // arithmetic that has already moved. These read what the function
    // actually did.
    setUp(() => debugLastSubtreeRaster = null);

    // The blit declares its quality by writing it onto the paint it was
    // handed, so the paint IS the observation — deriving the expected value
    // in the test would just certify a copy of the rule.
    late Paint blitPaint;

    void rasterise({
      required Rect bounds,
      double scale = 1,
      int maxPixelSide = 8192,
      void Function(double childScale)? onChildScale,
    }) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      blitPaint = Paint()..color = const Color(0xFF000000);
      drawSubtreeAsImage(
        canvas: canvas,
        bounds: bounds,
        rasterScale: scale,
        maxPixelSide: maxPixelSide,
        paintSubtree: (into, childScale) {
          onChildScale?.call(childScale);
          drawChildren(into);
        },
        compose: (blit) => blit(blitPaint),
      );
      recorder.endRecording().dispose();
    }

    test('whole bounds at 1:1 blit onto themselves', () {
      rasterise(bounds: const Rect.fromLTWH(6, 4, 46, 42));
      final raster = debugLastSubtreeRaster!;
      expect(raster.destination, const Rect.fromLTWH(6, 4, 46, 42));
      expect(raster.pixelWidth, 46);
      expect(raster.pixelHeight, 42);
      expect(raster.scale, 1);
      // 1:1 by construction, and it says so instead of letting the default
      // decide.
      expect(blitPaint.filterQuality, FilterQuality.none);
    });

    test('fractional bounds snap OUTWARD, never to the nearest', () {
      // 🚨THE CASE ROUNDING SURVIVES. At scale 1.5 a left edge of 6.37 sits
      // at device 9.555: floor keeps device 9 (canvas 6.0) and rounding
      // would take device 10 (canvas 6.667) — a column of the group thrown
      // away. Rounding a RIGHT edge loses one the same way.
      rasterise(
        bounds: const Rect.fromLTWH(6.37, 4.82, 46.4, 42.1),
        scale: 1.5,
      );
      final raster = debugLastSubtreeRaster!;
      expect(raster.destination.left, closeTo(9 / 1.5, 1e-9));
      expect(raster.destination.top, closeTo(7 / 1.5, 1e-9));
      expect(raster.destination.right, closeTo(80 / 1.5, 1e-9));
      expect(raster.destination.bottom, closeTo(71 / 1.5, 1e-9));
      // The destination is exactly `pixels / scale` — the property that
      // makes the blit 1:1 and stops the group resampling twice.
      expect(raster.pixelWidth, 71);
      expect(raster.pixelHeight, 64);
      expect(
        raster.destination.width * raster.scale,
        closeTo(raster.pixelWidth, 1e-9),
      );
      expect(
        raster.destination.height * raster.scale,
        closeTo(raster.pixelHeight, 1e-9),
      );
      expect(raster.destination.left, lessThanOrEqualTo(6.37));
      expect(raster.destination.right, greaterThanOrEqualTo(6.37 + 46.4));
    });

    test('the cap clamps the scale, and the blit says it magnified', () {
      rasterise(bounds: const Rect.fromLTWH(6, 4, 46, 42), maxPixelSide: 16);
      final raster = debugLastSubtreeRaster!;
      expect(raster.pixelWidth, lessThanOrEqualTo(16));
      expect(raster.pixelHeight, lessThanOrEqualTo(16));
      expect(raster.scale, lessThan(1));
      // ⛔`none` here would be nearest-neighbour on a ~3x magnification.
      expect(blitPaint.filterQuality, FilterQuality.low);
    });

    // The uniform shrink itself, named. Both cap sites — this file's
    // sub-tree plan and the display buffer's knee scale one level up —
    // apply THIS, and differ only in the cap they hand in.
    group('scaleFittingSide', () {
      test('a scale that already fits is handed straight back', () {
        expect(
          scaleFittingSide(
            scale: 0.5,
            bounds: const Size(100, 40),
            maxSide: 8192,
          ),
          0.5,
        );
      });

      test('the LONG side decides, whichever axis it is', () {
        expect(
          scaleFittingSide(
            scale: 4,
            bounds: const Size(100, 10),
            maxSide: 200,
          ),
          2,
        );
        expect(
          scaleFittingSide(
            scale: 4,
            bounds: const Size(10, 100),
            maxSide: 200,
          ),
          2,
        );
      });

      test('landing exactly ON the cap is not over it', () {
        expect(
          scaleFittingSide(
            scale: 2,
            bounds: const Size(100, 100),
            maxSide: 200,
          ),
          2,
        );
      });

      test('the shrink is uniform: the clamped scale puts the long side '
          'exactly on the cap', () {
        final clamped = scaleFittingSide(
          scale: 10,
          bounds: const Size(46, 42),
          maxSide: 16,
        );
        expect(46 * clamped, closeTo(16, 1e-9));
        expect(42 * clamped, lessThan(16));
      });
    });

    test('children rasterise at the scale the parent SETTLED on', () {
      // A clamped group whose children still drew at the unclamped scale
      // would paint at 3x into a 1x image — the children would land off the
      // side of their own parent.
      var childScale = double.nan;
      rasterise(
        bounds: const Rect.fromLTWH(6, 4, 46, 42),
        maxPixelSide: 16,
        onChildScale: (scale) => childScale = scale,
      );
      expect(childScale, debugLastSubtreeRaster!.scale);
      expect(childScale, lessThan(1));
    });
  });

  test('a filter spreads exactly as far as the saveLayer let it', () async {
    // 🚨THE RULE I ALMOST INVENTED. A first version clipped the blit to the
    // bounds, on the theory that it "reproduced the saveLayer's bounds clip".
    // 🧪MEASURED: a saveLayer hinted at this rect puts 1150 device pixels
    // OUTSIDE it once its paint carries a blur — the bounds cut the content
    // going in, never the filter coming out. The clip was an invented rule,
    // and it cost an adjustment crossfade 488 pixels.
    //
    // This is the case that says so: bounds NOT inflated by the spread, which
    // is what an adjustment hands in today and what any filter that forgets
    // to inflate will hand in tomorrow.
    const tight = Rect.fromLTWH(8, 6, 40, 36);
    Paint blurred() => Paint()
      ..color = const Color(0xFF000000)
      ..imageFilter = ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6);
    final layered = await render(
      groupPaint: blurred(),
      groupRect: tight,
      asImage: false,
    );
    final imaged = await render(
      groupPaint: blurred(),
      groupRect: tight,
      asImage: true,
    );
    // ⛔Prove the spread actually leaves the bounds, or this compares two
    // pictures that were never asked the question.
    var outside = 0;
    for (var y = 0; y < deviceHeight; y++) {
      for (var x = 0; x < deviceWidth; x++) {
        final at = (y * deviceWidth + x) * 4;
        final isBackdrop =
            layered[at] == 0x20 &&
            layered[at + 1] == 0x40 &&
            layered[at + 2] == 0x60 &&
            layered[at + 3] == 0xFF;
        if (!tight.contains(Offset(x + 0.5, y + 0.5)) && !isBackdrop) {
          outside += 1;
        }
      }
    }
    expect(
      outside,
      greaterThan(100),
      reason: 'the saveLayer this compares against must itself spread past '
          'the bounds, or the comparison proves nothing',
    );
    expect(
      differingPixels(layered, imaged),
      0,
      reason: 'the blit must spread exactly as far as the saveLayer did — '
          'no further, and no less',
    );
  });


  test('the cap clamps the raster instead of refusing to draw', () async {
    // ⛔THE ONE ARM THAT IS NOT AN IDENTITY, and it must still be a DRAW. A
    // refusal here would be a second code path — the path where a folder's
    // effect silently does not apply — so the cap shrinks the raster the way
    // the display buffer does and keeps one way to composite a group.
    const rect = Rect.fromLTWH(6, 4, 46, 42);
    final clamped = await render(
      groupPaint: Paint()..color = const Color(0xFF000000),
      groupRect: rect,
      asImage: true,
      // 46px of group through a 16px cap: the blit magnifies ~2.9×.
      maxPixelSide: 16,
    );
    var drewInside = 0;
    var escaped = 0;
    for (var y = 0; y < deviceHeight; y++) {
      for (var x = 0; x < deviceWidth; x++) {
        final at = (y * deviceWidth + x) * 4;
        final isBackdrop =
            clamped[at] == 0x20 &&
            clamped[at + 1] == 0x40 &&
            clamped[at + 2] == 0x60 &&
            clamped[at + 3] == 0xFF;
        if (rect.contains(Offset(x + 0.5, y + 0.5))) {
          if (!isBackdrop) {
            drewInside += 1;
          }
        } else if (!isBackdrop) {
          escaped += 1;
        }
      }
    }
    expect(drewInside, greaterThan(200), reason: 'the clamped group must '
        'still draw, not silently vanish');
    expect(escaped, 0, reason: 'the clamped blit must stay inside the bounds '
        'the saveLayer clipped to');
  });

  group('the stack tells the group what scale it is at', () {
    // 🚨A `Canvas` will not say what its CTM is at, so the walk carries the
    // number. Cut that wire and the group still draws — at the WRONG
    // resolution, which no route-parity test can see because both routes
    // would be cut together. This reads the number the group settled on.
    const canvasSize = CanvasSize(width: 400, height: 300);

    BitmapSurfacePainter inkedPage() {
      var tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 256);
      tile = writeRgbaColorToBitmapTile(
        tile: tile,
        x: 4,
        y: 4,
        color: RgbaColor(r: 0, g: 0, b: 255, a: 255),
      );
      return BitmapSurfacePainter(
        surface: BitmapSurface(canvasSize: canvasSize, tiles: {tile.coord: tile}),
        showTransparentBackground: false,
      );
    }

    Future<void> paintFolder(
      WidgetTester tester, {
      required bool directWalk,
      required double devicePixelRatio,
    }) async {
      tester.view.devicePixelRatio = devicePixelRatio;
      addTearDown(tester.view.resetDevicePixelRatio);
      debugLastSubtreeRaster = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 150,
                child: CanvasLayerStackView(
                  nodes: [
                    const CompositeGroup<CanvasStackRow>(
                      children: [CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1))],
                      opacity: 1,
                      blendMode: LayerBlendMode.multiply,
                    ),
                  ],
                  imageCache: LayerFrameImageCache(
                    frameStore: BrushFrameStore(),
                  ),
                  canvasSize: canvasSize,
                  viewport: CanvasViewport(zoom: 1, panX: 0, panY: 0),
                  activeSurfacePainter: inkedPage(),
                  paintPaper: true,
                  paperBackground: ProjectBackground.defaultBackground,
                  debugDisableSingleBuffer: directWalk,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // A pump builds and lays out; the number only moves inside
      // CustomPainter.paint.
      final painted = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(CanvasLayerStackView),
              matching: find.byType(CustomPaint),
            ),
          )
          .where((paint) => paint.painter != null)
          .toList();
      expect(painted, isNotEmpty);
      const size = Size(200, 150);
      final recorder = ui.PictureRecorder();
      painted.first.painter!.paint(Canvas(recorder, Offset.zero & size), size);
      recorder.endRecording().dispose();
    }

    testWidgets('the direct walk hands down zoom x devicePixelRatio', (
      tester,
    ) async {
      await paintFolder(tester, directWalk: true, devicePixelRatio: 3);
      expect(
        debugLastSubtreeRaster,
        isNotNull,
        reason: 'the folder never rasterised at all',
      );
      expect(
        debugLastSubtreeRaster!.scale,
        3,
        reason: 'drawn straight under the viewport transform, the group has '
            'to match the CTM it lands in — a group rasterised at 1 while its '
            'siblings draw at 3 is a soft folder next to sharp layers',
      );
    });

    testWidgets('the canvas-resolution buffer hands down 1', (tester) async {
      await paintFolder(tester, directWalk: false, devicePixelRatio: 3);
      expect(debugLastSubtreeRaster, isNotNull);
      expect(
        debugLastSubtreeRaster!.scale,
        1,
        reason: 'the buffer records at canvas resolution, so a group inside '
            'it is at canvas resolution too — this is the route that matches '
            'the export',
      );
    });
  });

  test('an adjustment crossfade is the pixels the two saveLayers made', () async {
    // 🚨THE BRANCH WITH NO ROUTE TEST. A mix below 1 with a BLUR is the only
    // chain that crossfades — a colour-only chain folds the mix into its own
    // matrix and never draws twice.
    //
    // 🧪The passes KEEP their layers and only what is inside them changed:
    // a blit of one raster instead of a second walk of the scope. A first
    // version blitted with the passes' own paints instead, which rounds
    // each pass separately — a crossfade adds two of them and this scene
    // moved by 2/255 over 488 pixels. Exactness is why the layers stayed.
    const rect = Rect.fromLTWH(-3, -5, 64, 60);
    AdjustmentScopePass freshPass() => resolveAdjustmentScopePass(
      bounds: rect,
      effects: [
        ResolvedLayerEffect(kind: EffectKind.blur, values: const [3, 3]),
      ],
      mix: 0.5,
    );
    // ⛔Prove the scene is the case this test is named for. A chain that did
    // not crossfade would compare one blit against one saveLayer and pass
    // while saying nothing.
    expect(freshPass().crossfades, isTrue);

    Future<Uint8List> render({required bool asImage}) async {
      final pass = freshPass();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      drawBackdrop(canvas, 1);
      if (asImage) {
        drawSubtreeAsImage(
          canvas: canvas,
          bounds: pass.bufferBounds,
          rasterScale: 1,
          maxPixelSide: maxSubtreeRasterSide,
          paintSubtree: (into, _) => drawChildren(into),
          // ⛔THE ROUTES. COMPOSE, not a copy of it — the three walks hand
          // this exact function to `drawSubtreeAsImage`.
          compose: composeAdjustmentScope(canvas, pass),
        );
      } else {
        // The recipe as it stood before this round.
        canvas.saveLayer(pass.bufferBounds, pass.crossfadeLayerPaint!);
        canvas.saveLayer(pass.bufferBounds, pass.unfilteredPaint!);
        drawChildren(canvas);
        canvas.restore();
        canvas.saveLayer(pass.bufferBounds, pass.filteredPaint);
        drawChildren(canvas);
        canvas.restore();
        canvas.restore();
      }
      final picture = recorder.endRecording();
      final image = picture.toImageSync(deviceWidth, deviceHeight);
      picture.dispose();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes!.buffer.asUint8List();
    }

    final layered = await render(asImage: false);
    final imaged = await render(asImage: true);
    expect(layered.any((byte) => byte != 0), isTrue);
    expect(
      differingPixels(layered, imaged),
      0,
      reason: 'one raster blitted twice must be the two saveLayers, pixel '
          'for pixel',
    );
  });

  test('an adjustment rasterises its scope ONCE and blits it twice', () {
    // 🚨THE WHOLE POINT OF `compose`. An adjustment below full strength used
    // to paint its scope twice — once into an unfiltered saveLayer and once
    // into a filtered one — because its mix is a crossfade, not a fade-out.
    // It is the same picture both times. On the playback route "painting the
    // scope" means awaiting every layer image in it, so the second pass was
    // not a rounding error.
    var rasters = 0;
    final blitted = <Paint>[];
    final unfiltered = Paint()..color = const Color(0x80000000);
    final filtered = Paint()
      ..color = const Color(0xFF000000)
      ..colorFilter = const ColorFilter.mode(
        Color(0xFF00FF00),
        BlendMode.modulate,
      );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    drawSubtreeAsImage(
      canvas: canvas,
      bounds: const Rect.fromLTWH(6, 4, 46, 42),
      rasterScale: 1,
      maxPixelSide: maxSubtreeRasterSide,
      paintSubtree: (into, _) {
        rasters += 1;
        drawChildren(into);
      },
      compose: (blit) {
        canvas.saveLayer(const Rect.fromLTWH(6, 4, 46, 42), Paint());
        blit(unfiltered);
        blitted.add(unfiltered);
        blit(filtered);
        blitted.add(filtered);
        canvas.restore();
      },
    );
    recorder.endRecording().dispose();
    expect(rasters, 1, reason: 'the scope must be rasterised once');
    expect(blitted, [unfiltered, filtered]);
    // Both blits declared their own quality on their own paint — the second
    // must not inherit whatever the first left behind by accident.
    expect(unfiltered.filterQuality, FilterQuality.none);
    expect(filtered.filterQuality, FilterQuality.none);
  });

  test('a fractional DEVICE phase never changes the body of the group', () async {
    // 📐STATED, NOT ASSUMED. Placed at a fractional device offset, an image
    // blit resamples where vector content would have rasterised at the true
    // phase. The stack's canvas-resolution buffer records under
    // `translate(-integer, -integer)` at scale 1, so it never asks this
    // question — but the number belongs on the record rather than in an
    // argument, and this fails loudly if the geometry ever drifts far
    // enough to make the difference more than an edge.
    Paint paint() => Paint()..color = const Color(0xFF000000);
    const rect = Rect.fromLTWH(6, 4, 46, 42);
    final layered = await render(
      groupPaint: paint(),
      groupRect: rect,
      asImage: false,
      devicePhase: 0.5,
    );
    final imaged = await render(
      groupPaint: paint(),
      groupRect: rect,
      asImage: true,
      devicePhase: 0.5,
    );
    expect(
      differingPixels(layered, imaged),
      lessThan(deviceWidth * deviceHeight ~/ 8),
      reason: 'a half-pixel phase may soften edges; it must never change '
          'the body of the group',
    );
  });
}
