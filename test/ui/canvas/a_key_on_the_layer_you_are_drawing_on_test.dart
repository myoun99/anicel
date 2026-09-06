import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/colour_key_shader.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/models/composite_tree.dart';

/// 🚨★★★A COLOUR KEY ON THE LAYER YOU ARE DRAWING ON.
///
/// ⛔THIS THREW, and had since the day colour keys shipped. The live-surface
/// node carried the WHOLE chain where every other row carries only the paint
/// half, so the paint resolver was handed keys that had already run on the
/// surface — and it refuses those, by assert. No test ever painted a keyed
/// active layer, so nothing said so; a structural audit did.
///
/// The second case is the one free ordering opened: a key BELOW a painted
/// effect keys what that effect made, and a shader cannot sample a
/// `saveLayer`. That is the only configuration where the live layer
/// rasterises to an image — a plainly buffered one keeps the cheaper layer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(ColourKeyShader.load);

  const canvasSize = CanvasSize(width: 32, height: 32);

  BitmapSurfacePainter whiteSurface() {
    var tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 8);
    for (var x = 0; x < 8; x++) {
      for (var y = 0; y < 8; y++) {
        tile = writeRgbaColorToBitmapTile(
          tile: tile,
          x: x,
          y: y,
          color: RgbaColor(r: 255, g: 255, b: 255, a: 255),
        );
      }
    }
    return BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 8,
        tiles: {tile.coord: tile},
      ),
      showTransparentBackground: false,
    );
  }

  ResolvedLayerEffect deleteWhite() => ResolvedLayerEffect(
    kind: EffectKind.deleteColor,
    values: const [255, 255, 255, 0, 100],
  );

  Future<Uint8List> paintWith(
    WidgetTester tester,
    List<ResolvedLayerEffect> effects,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 64,
              height: 64,
              child: CanvasLayerStackView(
                nodes: [
                  CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1, effects: effects)),
                ],
                imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
                canvasSize: canvasSize,
                viewport: CanvasViewport(zoom: 1, panX: 0, panY: 0),
                activeSurfacePainter: whiteSurface(),
                // No paper: the key's work has to be visible as ALPHA, and a
                // white page under it would hide the erase behind more white.
                paintPaper: false,
                paperBackground: const ProjectBackground.color(0x00000000),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
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
    const size = Size(64, 64);
    final recorder = ui.PictureRecorder();
    painted.first.painter!.paint(Canvas(recorder, Offset.zero & size), size);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(64, 64);
    picture.dispose();
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  int inkPixels(Uint8List bytes) {
    var n = 0;
    for (var i = 3; i < bytes.length; i += 4) {
      if (bytes[i] != 0) {
        n += 1;
      }
    }
    return n;
  }

  ResolvedLayerEffect keepWhite() => ResolvedLayerEffect(
    kind: EffectKind.keepColor,
    values: const [255, 255, 255, 0, 100],
  );

  ResolvedLayerEffect darken() => ResolvedLayerEffect(
    kind: EffectKind.brightnessContrast,
    values: const [-0.5, 0],
  );

  testWidgets('a key at the HEAD of the chain belongs to the SURFACE', (
    tester,
  ) async {
    final plain = await paintWith(tester, const []);
    expect(inkPixels(plain), greaterThan(0), reason: 'fixture: the layer drew');
    final keyed = await paintWith(tester, [deleteWhite()]);
    // ⛔IDENTICAL, and that is the fix. A leading key runs on the cel's own
    // bytes — the session applies it through `celSurfaceWithSourceEffects`
    // before it hands this painter over — so the node takes only the PAINT
    // half and this paint has nothing left to do. Handing it the whole chain
    // ran the key a SECOND time: 🧪on this fixture, whose surface the session
    // never touched, that erased every pixel.
    expect(
      inkPixels(keyed),
      inkPixels(plain),
      reason: 'the leading key belongs to the surface, not to this paint',
    );
  });

  testWidgets('a key BELOW a painted effect keys what that effect MADE', (
    tester,
  ) async {
    // The configuration free ordering opened, and the one that forces the
    // live layer to rasterise: a shader needs an image to sample.
    //
    // ⛔KEEP, not DELETE, and that is the whole design of this fixture. "Keep
    // white, tolerance 0" over a picture where the darken has left NOTHING
    // white erases everything — so the assertion fails both when the key
    // never runs AND when it runs on the cel instead of on the darkened
    // picture. A delete-white here would have passed on a key that did
    // nothing at all, which is exactly how the first draft of this test lied.
    final darkenedOnly = await paintWith(tester, [darken()]);
    expect(
      inkPixels(darkenedOnly),
      greaterThan(0),
      reason: 'fixture: the darkened layer drew',
    );
    final keyed = await paintWith(tester, [darken(), keepWhite()]);
    expect(
      inkPixels(keyed),
      0,
      reason: 'the key ran AFTER the darken, where nothing is white any more '
          '— so KEEP WHITE keeps nothing',
    );
    // ⛔And the same key at the HEAD keeps everything: white IS white on the
    // cel. Same two effects, opposite order, opposite picture — which is the
    // order-is-free law, on the row you are drawing on.
    final keptFirst = await paintWith(tester, [keepWhite(), darken()]);
    expect(
      inkPixels(keptFirst),
      inkPixels(darkenedOnly),
      reason: 'a leading keep-white is the surface\'s job and keeps the '
          'white cel whole',
    );
  });
}
