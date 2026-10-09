import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// I-37 — A ROW A FOLDER'S LIFT HOLDS SHOWS WHAT THE LIVE ROW WOULD.
///
/// 유저 2026-10-02: 「폴더 전체를 하나로 들도록」. A folder's rows show at
/// the same frame, so while its box is open each of them is drawn as its
/// cel with the hole the lift cut and its own float over it — in its own
/// slot, with its own opacity, blend, pose and effects. That is exactly
/// what the LIVE row is while a box is open on it, and one body draws both
/// ([LiftedRowPaint]). Here the same surface and the same float are drawn
/// once as the live row and once as a lifted row, and the bytes must agree
/// through every route the body has: riding the draws, a plain buffer, an
/// advanced blend's image, a pose, a spreading effect, inside a folder.
/// One row's composite paint, written once for both of its shapes.
typedef _RowPaint = ({
  double opacity,
  LayerBlendMode blendMode,
  LayerPlacement? placement,
  List<ResolvedLayerEffect> effects,
});

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  BrushFrameKey keyOf(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );

  BitmapSurfacePainter surfaceOf(Map<(int, int), RgbaColor> pixels) {
    var tile = BitmapTile.blank(size: 8);
    for (final MapEntry(key: (x, y), value: color) in pixels.entries) {
      tile = writeRgbaColorToBitmapTile(tile: tile, x: x, y: y, color: color);
    }
    return BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 8,
        tiles: {TileCoord(x: 0, y: 0): tile},
      ),
      showTransparentBackground: false,
    );
  }

  /// A cel with the hole a lift cut: every pixel inked, some half
  /// transparent, all different — but the 2×2 the lift took.
  BitmapSurfacePainter holedCel(int seed) => surfaceOf({
    for (var y = 0; y < 8; y += 1)
      for (var x = 0; x < 8; x += 1)
        if (!(x >= 2 && x < 4 && y >= 2 && y < 4))
          (x, y): RgbaColor(
            r: (x * 31 + seed * 70) % 256,
            g: (y * 29 + seed * 40) % 256,
            b: (x * y * 7 + seed * 90) % 256,
            a: (x + y).isEven ? 255 : 150,
          ),
  });

  /// The 2×2 the lift took, carried [by] — dragged off its hole.
  SelectionFloatOverlay floatOf(int seed, {CanvasPoint? by}) {
    final float = SelectionFloatOverlay(
      SelectionFloatPaint(
        surface: surfaceOf({
          (2, 2): RgbaColor(r: 250, g: seed * 60 % 256, b: 10, a: 255),
          (3, 2): RgbaColor(r: 10, g: 20, b: 240, a: 255),
          (2, 3): RgbaColor(r: 255, g: 255, b: 255, a: 120),
          (3, 3): RgbaColor(r: 240, g: 230, b: seed * 50 % 256, a: 255),
        }),
        surfaceOffset: by ?? CanvasPoint(x: 3, y: 1),
      ),
    );
    addTearDown(float.dispose);
    return float;
  }

  CompositeNode<CanvasStackRow> liveRow(_RowPaint paint) =>
      CompositeLeaf<CanvasStackRow>(
        CanvasActiveLayerRow(
          opacity: paint.opacity,
          blendMode: paint.blendMode,
          placement: paint.placement,
          effects: paint.effects,
        ),
      );

  CompositeNode<CanvasStackRow> liftedRow(String layer, _RowPaint paint) =>
      CompositeLeaf<CanvasStackRow>(
        CanvasLayerImageRequest(
          frameKey: keyOf(layer),
          opacity: paint.opacity,
          blendMode: paint.blendMode,
          placement: paint.placement,
          effects: paint.effects,
        ),
      );

  Future<CustomPainter> pumpStack(
    WidgetTester tester, {
    required List<CompositeNode<CanvasStackRow>> nodes,
    BitmapSurfacePainter? live,
    SelectionFloatOverlay? liveFloat,
    Map<BrushFrameKey, LiftedRowPaint> lifted = const {},
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 8,
              height: 8,
              child: CanvasLayerStackView(
                nodes: nodes,
                imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
                canvasSize: canvasSize,
                viewport: CanvasViewport(),
                activeSurfacePainter: live,
                floatOverlay: liveFloat,
                liftedRows: lifted,
                // Something to blend AGAINST: a multiply over nothing is
                // indistinguishable from a dropped blend.
                paintPaper: true,
                paperBackground: const ProjectBackground.color(0xFF30A060),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .first
        .painter!;
  }

  Future<Uint8List> shot(WidgetTester tester, CustomPainter painter) async =>
      (await tester.runAsync(() => _rasterize(painter)))!;

  const _RowPaint plain = (
    opacity: 1.0,
    blendMode: LayerBlendMode.normal,
    placement: null,
    effects: <ResolvedLayerEffect>[],
  );

  final routes = <String, _RowPaint>{
    'a plain row': plain,
    'a half-opacity row': (
      opacity: 0.5,
      blendMode: LayerBlendMode.normal,
      placement: null,
      effects: const [],
    ),
    // An advanced blend never rides a buffer: the slot is drawn as an
    // image, sized by the slot's own bounds.
    'a multiply row': (
      opacity: 0.7,
      blendMode: LayerBlendMode.multiply,
      placement: null,
      effects: const [],
    ),
    // The float is canvas space and the slot is drawn inside the pose:
    // the slot's way back from the canvas has to be its own row's.
    'a posed row': (
      opacity: 1.0,
      blendMode: LayerBlendMode.normal,
      placement: const LayerPlacement(1, 0, 0, 1, 2, 1),
      effects: const [],
    ),
    'a blurred row': (
      opacity: 1.0,
      blendMode: LayerBlendMode.normal,
      placement: null,
      effects: [ResolvedLayerEffect(kind: EffectKind.blur, values: [1, 1])],
    ),
  };

  for (final MapEntry(key: name, value: paint) in routes.entries) {
    testWidgets('$name: lifted, it shows what it shows live', (tester) async {
      final cel = holedCel(1);
      final float = floatOf(1);

      final live = await pumpStack(
        tester,
        nodes: [liveRow(paint)],
        live: cel,
        liveFloat: float,
      );
      final asLive = await shot(tester, live);
      final lifted = await pumpStack(
        tester,
        nodes: [liftedRow('a', paint)],
        lifted: {keyOf('a'): (surface: cel, float: float)},
      );
      final asLifted = await shot(tester, lifted);

      expect(
        _differing(asLifted, asLive),
        0,
        reason: 'the same cel and the same float, drawn as a lifted row, '
            'came out different from the live row drawing them — the two '
            'shapes of one row went two ways',
      );
    });
  }

  testWidgets('in a folder, each row lifted shows what it shows live', (
    tester,
  ) async {
    final under = holedCel(1);
    final underFloat = floatOf(1);
    final over = holedCel(2);
    final overFloat = floatOf(2, by: CanvasPoint(x: 1, y: 3));
    const _RowPaint overPaint = (
      opacity: 0.8,
      blendMode: LayerBlendMode.screen,
      placement: null,
      effects: <ResolvedLayerEffect>[],
    );
    CompositeNode<CanvasStackRow> folder(CompositeNode<CanvasStackRow> top) =>
        CompositeGroup<CanvasStackRow>(
          children: [liftedRow('under', plain), top],
          opacity: 0.6,
          blendMode: LayerBlendMode.multiply,
        );

    final withLiveTop = await pumpStack(
      tester,
      nodes: [folder(liveRow(overPaint))],
      live: over,
      liveFloat: overFloat,
      lifted: {keyOf('under'): (surface: under, float: underFloat)},
    );
    final liveTop = await shot(tester, withLiveTop);
    final bothLifted = await pumpStack(
      tester,
      nodes: [folder(liftedRow('over', overPaint))],
      lifted: {
        keyOf('under'): (surface: under, float: underFloat),
        keyOf('over'): (surface: over, float: overFloat),
      },
    );
    final allLifted = await shot(tester, bothLifted);

    expect(
      _differing(allLifted, liveTop),
      0,
      reason: 'a folder whose rows are all lifted came out different from '
          'the same folder with its top row live',
    );
  });

  // ── The scene can tell: a parity of two blanks proves nothing. ──

  testWidgets('a lifted row draws its cel and its float — not nothing', (
    tester,
  ) async {
    final cel = holedCel(1);
    final float = floatOf(1);
    final empty = SelectionFloatOverlay(null);
    addTearDown(empty.dispose);

    final withFloat = await shot(
      tester,
      await pumpStack(
        tester,
        nodes: [liftedRow('a', plain)],
        lifted: {keyOf('a'): (surface: cel, float: float)},
      ),
    );
    final withoutFloat = await shot(
      tester,
      await pumpStack(
        tester,
        nodes: [liftedRow('a', plain)],
        lifted: {keyOf('a'): (surface: cel, float: empty)},
      ),
    );
    final notLifted = await shot(
      tester,
      await pumpStack(tester, nodes: [liftedRow('a', plain)]),
    );

    expect(
      _differing(withFloat, withoutFloat),
      greaterThan(0),
      reason: 'the float was not drawn on its row',
    );
    expect(
      _differing(withoutFloat, notLifted),
      greaterThan(0),
      reason: 'the lifted cel was not drawn — the row drew what an image '
          'row with nothing held draws',
    );
  });

  testWidgets('a lifted row does not answer for the live row\'s route', (
    tester,
  ) async {
    // The live row rides the draws (nothing overlaps on it); the lifted row
    // above it cannot (its float overlaps its cel). The probe is the LIVE
    // row's, so the lifted row's paint after it must not overwrite it.
    debugLiveLayerRodeTheDraws = null;
    final painter = await pumpStack(
      tester,
      nodes: [liveRow(plain), liftedRow('a', plain)],
      live: holedCel(2),
      lifted: {keyOf('a'): (surface: holedCel(1), float: floatOf(1))},
    );
    await shot(tester, painter);

    expect(debugLiveLayerRodeTheDraws, isTrue);
  });

  testWidgets('a lifted float moving repaints — no buffer is kept under it', (
    tester,
  ) async {
    final float = floatOf(1);
    final painter = await pumpStack(
      tester,
      nodes: [liftedRow('a', plain)],
      lifted: {keyOf('a'): (surface: holedCel(1), float: float)},
    );
    var repaints = 0;
    painter.addListener(() => repaints += 1);

    // 🚨WARM FIRST, as the live float's own pin learned: the first paints
    // miss on their own and would pick the move up with the guard gone.
    await shot(tester, painter);
    await shot(tester, painter);
    final before = await shot(tester, painter);

    // The drag: the float moves and nothing else does — no pump, as a drag
    // step reaches the canvas through the repaint Listenable alone.
    float.value = SelectionFloatPaint(
      surface: float.value!.surface,
      surfaceOffset: CanvasPoint(x: 0, y: 4),
    );
    final after = await shot(tester, painter);

    expect(
      repaints,
      greaterThan(0),
      reason: 'a lifted float moved and the canvas was not told — the step '
          'waits for a rebuild that a drag never makes',
    );
    expect(
      _differing(after, before),
      greaterThan(0),
      reason: 'the lifted float moved and the canvas did not — a kept '
          'buffer is showing where it used to be',
    );
  });
}

Future<Uint8List> _rasterize(CustomPainter painter) async {
  final recorder = ui.PictureRecorder();
  const size = Size(8, 8);
  final canvas = Canvas(recorder, Offset.zero & size);
  painter.paint(canvas, size);
  final image = await recorder.endRecording().toImage(8, 8);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bytes!.buffer.asUint8List();
}

int _differing(Uint8List a, Uint8List b) {
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
