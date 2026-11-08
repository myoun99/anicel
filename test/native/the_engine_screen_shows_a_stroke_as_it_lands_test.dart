import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/cel_surface_as_shown.dart'
    show celSurfaceAsShown;
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../helpers/a_plugin_that_shifts.dart' show shiftingFxPluginEffect;
import '../helpers/cel_text_fixture.dart' show textOf;
import '../helpers/engine_screen_shown.dart';

/// 🚨★★★THE ENGINE'S SCREEN SHOWS A STROKE AS IT LANDS (flip lane ⓐ, 유저
/// 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」): the
/// live row laid while the pen is down — its cel with the tile each
/// coordinate the stroke replaces shows in its place
/// ([BitmapSurfacePainter.shownSurface]) — is, byte for byte, the row laid
/// once the stroke has landed, and not the cel the stroke found: a stroke
/// that paints, one that erases, a fill's result, one under a text, whose
/// letters show over it, one on a row whose chain runs a plugin over the
/// whole cel.
void main() {
  // The letters read their faces from the bundle.
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvas = CanvasSize(width: 256, height: 128);
  const side = 128;
  final left = TileCoord(x: 0, y: 0);
  final right = TileCoord(x: 1, y: 0);
  late GpuComposite composite;
  late EngineLetters letters;

  setUpAll(() async {
    composite = GpuComposite(appGpuEngine);
    letters = await EngineLetters.open(composite);
  });
  tearDownAll(() {
    letters.free();
    composite.free();
  });

  /// A tile of [seed]'s pixels, alphas of every kind.
  BitmapTile tileOf(int seed) {
    final pixels = Uint8List(side * side * 4);
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final n = x * 7 + y * 13 + seed * 101;
        final alpha = switch ((x ~/ 16 + y ~/ 32 + seed) % 4) {
          0 => 0,
          1 => 255,
          2 => 96 + (n & 63),
          _ => 200 + (n & 31),
        };
        if (alpha > 0) {
          pixels.setAll((y * side + x) * 4, [
            (n * 37) & 255,
            (n * 23 + 91) & 255,
            (n * 11) & 255,
            alpha,
          ]);
        }
      }
    }
    return BitmapTile(size: side, pixels: pixels);
  }

  /// The cel a stroke lands on: ink on both tiles.
  BitmapSurface cel() => BitmapSurface(
    canvasSize: canvas,
    tileSize: side,
    tiles: {left: tileOf(1), right: tileOf(2)},
  );

  /// A line across both tiles and past the page's foot.
  List<BrushDab> strokeDabs() {
    var sequence = 0;
    return [
      for (var x = 20.0; x < 240; x += 6)
        BrushDab(
          center: CanvasPoint(x: x, y: 40 + x / 4),
          color: 0xC0204080,
          size: 18,
          opacity: 1,
          flow: 0.7,
          hardness: 0.6,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: sequence++,
        ),
    ];
  }

  /// The overlay a stroke on [base] shows through, as the view sets it at
  /// stroke start, and the stroke flushed into it as the view flushes it.
  ({ActiveStrokeOverlayModel overlay, BrushLiveStrokeRasterizer rasterizer})
  strokeOn(
    BitmapSurface base, {
    required bool erase,
    List<ResolvedLayerEffect> sourceEffects = const [],
  }) {
    final overlay = ActiveStrokeOverlayModel(tileSize: side)
      ..erase = erase
      ..blendMode = BrushBlendMode.color
      ..preBlendBase = base
      ..sourceEffects = sourceEffects;
    addTearDown(overlay.dispose);
    final rasterizer = BrushLiveStrokeRasterizer(
      pasteboard: canvas.pasteboardAt(PasteboardReach.whole),
      tileSize: side,
    );
    final dabs = strokeDabs();
    final region = rasterizer.blendFrom(dabs, from: 0)!;
    overlay.dabs.addAll(dabs);
    overlay.updateRegion(source: rasterizer, region: region);
    return (overlay: overlay, rasterizer: rasterizer);
  }

  /// [base] with the stroke [rasterizer] holds landed, as the commit puts
  /// it.
  BitmapSurface landed(
    BitmapSurface base,
    BrushLiveStrokeRasterizer rasterizer, {
    required bool erase,
  }) => base.putMaterializedTiles([
    for (final entry in rasterizer.promoteStrokeTiles(
      base: base,
      mode: BrushBlendMode.color,
      erase: erase,
    ))
      (coord: entry.coord, tile: entry.tile),
  ]);

  /// The frame of one row, the pen's, drawn by [live].
  StackedFrame frameOf(BitmapSurfacePainter live) => stackedFrameOf(
    const [CompositeLeaf(CanvasActiveLayerRow(opacity: 1))],
    page: (
      canvasSize: canvas,
      pasteboardReach: PasteboardReach.whole,
      paintPaper: true,
      paperBackground: const ProjectBackground.color(0xFF30A060),
    ),
    surfaceOf: (_) => null,
    live: (
      rows: (
        activeSurfacePainter: live,
        floatOverlay: null,
        liftedRows: const {},
      ),
      painters: LiftedRowPainters(),
    ),
  );

  /// What the engine's screen shows of [frame] at rest, one texel a canvas
  /// pixel — its fingerprint.
  int shown(StackedFrame frame) => engineScreenShown(
    frame,
    composite: composite,
    letters: letters,
    size: (canvas.width, canvas.height),
  );

  for (final erase in [false, true]) {
    test('🚨a stroke that ${erase ? 'erases' : 'paints'} shows on the '
        'engine\'s screen as it lands', () {
      final base = cel();
      final (:overlay, :rasterizer) = strokeOn(base, erase: erase);
      final drawing = shown(
        frameOf(BitmapSurfacePainter(surface: base, overlayModel: overlay)),
      );
      expect(overlay.shownTiles.keys, containsAll([left, right]));

      expect(
        drawing,
        shown(
          frameOf(
            BitmapSurfacePainter(
              surface: landed(base, rasterizer, erase: erase),
            ),
          ),
        ),
      );
      expect(
        drawing,
        isNot(shown(frameOf(BitmapSurfacePainter(surface: base)))),
        reason: 'the stroke shows while the pen is down',
      );
    });
  }

  test('🚨a fill\'s result shows on the engine\'s screen as it lands', () {
    final base = cel();
    final overlay = ActiveStrokeOverlayModel(tileSize: side)
      ..preBlendBase = base;
    addTearDown(overlay.dispose);
    final result = PromotedStrokeTile(left, tileOf(5), 1);
    overlay.showResultTiles([result]);

    expect(
      shown(
        frameOf(BitmapSurfacePainter(surface: base, overlayModel: overlay)),
      ),
      shown(
        frameOf(
          BitmapSurfacePainter(
            surface: base.putMaterializedTiles([
              (coord: result.coord, tile: result.tile),
            ]),
          ),
        ),
      ),
    );
  });

  test('🚨a stroke under a text shows on the engine\'s screen with the '
      'letters over it, as it lands', () {
    final plate = tileOf(7);
    final base = cel().withTexts([
      textOf(1, plate: {left: plate}),
    ]);
    final (:overlay, :rasterizer) = strokeOn(base, erase: false);
    final drawing = shown(
      frameOf(BitmapSurfacePainter(surface: base, overlayModel: overlay)),
    );

    expect(
      drawing,
      shown(
        frameOf(
          BitmapSurfacePainter(
            surface: landed(base, rasterizer, erase: false),
          ),
        ),
      ),
    );
    expect(
      drawing,
      isNot(
        shown(
          frameOf(
            BitmapSurfacePainter(
              surface: cel(),
              overlayModel: strokeOn(cel(), erase: false).overlay,
            ),
          ),
        ),
      ),
      reason: 'the letters show over the stroke',
    );
  });

  test('🚨on a row whose chain runs a plugin, the stroke shows as the '
      'whole cel the plugin makes of it, as it lands', () {
    final plugin = [shiftingFxPluginEffect(by: 3)];
    final base = cel();
    final (:overlay, :rasterizer) = strokeOn(
      base,
      erase: false,
      sourceEffects: plugin,
    );
    final drawing = shown(
      frameOf(
        BitmapSurfacePainter(
          surface: celSurfaceAsShown(base, plugin),
          overlayModel: overlay,
        ),
      ),
    );

    expect(
      drawing,
      shown(
        frameOf(
          BitmapSurfacePainter(
            surface: celSurfaceAsShown(
              landed(base, rasterizer, erase: false),
              plugin,
            ),
          ),
        ),
      ),
    );
    expect(
      drawing,
      isNot(
        shown(
          frameOf(
            BitmapSurfacePainter(surface: celSurfaceAsShown(base, plugin)),
          ),
        ),
      ),
      reason: 'the stroke shows while the pen is down',
    );
  });

  test('a picture a reduced paint remakes with its chain still shows the '
      'tile it is of', () {
    final base = cel();
    final (:overlay, :rasterizer) = strokeOn(base, erase: false);
    overlay.chainedTileImageAt(left);

    expect(
      shown(
        frameOf(BitmapSurfacePainter(surface: base, overlayModel: overlay)),
      ),
      shown(
        frameOf(
          BitmapSurfacePainter(
            surface: landed(base, rasterizer, erase: false),
          ),
        ),
      ),
    );
  });
}
