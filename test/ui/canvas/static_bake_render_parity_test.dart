import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨★★★ (v) 1단계의 진짜 계약 — **더 빨라도 되고, 다르게 그리면 안 된다.**
///
/// The bake replays a recording for everything the stroke cannot change.
/// The only way that is allowed to be wrong is by drawing a different
/// picture, so every case here renders the SAME tree twice — once with the
/// bake and once with `debugDisableBake` — and compares raw pixels.
///
/// 🚨The folder case is the one that matters most. This file's subject used
/// to be two FLAT lists (below / above the active layer), and that shape was
/// abandoned precisely because a folder's `saveLayer` cannot span sibling
/// painters: drawing inside a blended folder never matched playback. A split
/// that baked the enclosing folder would restore that bug, which is why the
/// axis is 「the chain that ENCLOSES the active layer」 rather than
/// 「below / above」.
void main() {
  const canvasSize = CanvasSize(width: 4, height: 4);

  BrushFrameKey key(String id) => BrushFrameKey(
    projectId: const ProjectId('project'),
    trackId: const TrackId('track'),
    cutId: const CutId('cut'),
    layerId: LayerId(id),
    frameId: const FrameId('frame'),
  );

  /// 🚨A cache with REAL artwork in it, because a `CanvasLayerImageNode`
  /// whose image is not held is silently dropped from the resolved tree.
  ///
  /// ⚠️This is what makes the parity claim mean anything. With the active
  /// layer as the ONLY node there are no siblings, so nothing is baked and
  /// every comparison below would pass without the code under test ever
  /// running — the instrument agreeing with itself. Every tree here has a
  /// drawn row on at least one side of the active layer.
  LayerFrameImageCache cacheWithStrokes(List<String> ids) {
    final store = BrushFrameStore();
    for (final id in ids) {
      BrushFrameEditingCoordinator(
        initialFrameKey: key(id),
        frameStore: store,
        sessionStore: BrushFrameEditSessionStore(
          canvasSize: canvasSize,
          tileSize: 4,
        ),
        historyPolicy: const BrushHistoryPolicy(
          userUndoLimit: 8,
          deferredBakeRatio: 0,
        ),
      ).commitSourceStroke(
        sourceDabs: [
          BrushDab(
            center: CanvasPoint(x: 1, y: 1),
            color: 0xFF0000FF,
            size: 2,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: 0,
          ),
        ],
      );
    }
    return LayerFrameImageCache(frameStore: store);
  }

  CanvasLayerStackNode drawnRow(String id, {double opacity = 1}) =>
      CanvasLayerImageNode(
        CanvasLayerImageRequest(frameKey: key(id), opacity: opacity),
      );

  BitmapSurfacePainter redSurface() {
    var tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 4);
    tile = writeRgbaColorToBitmapTile(
      tile: tile,
      x: 0,
      y: 0,
      color: RgbaColor(r: 255, g: 0, b: 0, a: 255),
    );
    return BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 4,
        tiles: {tile.coord: tile},
      ),
      showTransparentBackground: false,
    );
  }

  Future<CustomPainter> pumpStack(
    WidgetTester tester, {
    required List<CanvasLayerStackNode> nodes,
    required BitmapSurfacePainter surfacePainter,
    required LayerFrameImageCache cache,
    required bool disableBake,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        // A distinct key per render, so the second pump builds a FRESH
        // state rather than reusing the first one's warm bake.
        key: ValueKey<bool>(disableBake),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 4,
              height: 4,
              child: CanvasLayerStackView(
                nodes: nodes,
                imageCache: cache,
                canvasSize: canvasSize,
                viewport: CanvasViewport(),
                activeSurfacePainter: surfacePainter,
                paintPaper: true,
                paperBackground: const ProjectBackground.color(0xFF00FF00),
                debugDisableBake: disableBake,
              ),
            ),
          ),
        ),
      ),
    );
    // 🚨WARM FIRST, THEN LOOK. A cold `LayerFrameImageCache` resolves some
    // rows on a later pass, so the first pump of a tree and the second draw
    // different numbers of rows — measured: with the bake OFF on BOTH sides
    // these comparisons still failed until this settle went in. That is the
    // instrument disagreeing with itself, and taking it for a finding about
    // the bake is exactly the mistake [[canvas-raster-perf-round]] records.
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
    return painted.first.painter!;
  }

  Future<void> expectSamePixels(
    WidgetTester tester,
    List<CanvasLayerStackNode> nodes, {
    required List<String> drawn,
    required String reason,
  }) async {
    // 🚨EACH SIDE GETS ITS OWN CACHE AND ITS OWN STATE, and that is not
    // tidiness — it is what makes the comparison mean anything.
    //
    // 실측: pumping the same stack view a second time loses its resolved
    // images (the second render came back as bare paper), so a shared cache
    // compared render #1 against a render that had no artwork in it at all.
    // With the bake OFF on BOTH sides those comparisons failed exactly the
    // same way, which is how it was caught: an instrument that disagrees
    // with itself cannot be reporting on the thing under test.
    final surfacePainter = redSurface();
    final baked = await pumpStack(
      tester,
      nodes: nodes,
      surfacePainter: surfacePainter,
      cache: cacheWithStrokes(drawn),
      disableBake: false,
    );
    // ⚠️`toImage` is a REAL async round-trip: awaited under the widget
    // test's fake clock it simply hangs. It belongs inside `runAsync`.
    final bakedBytes = (await tester.runAsync(() => _rasterize(baked)))!;

    final plain = await pumpStack(
      tester,
      nodes: nodes,
      surfacePainter: surfacePainter,
      cache: cacheWithStrokes(drawn),
      disableBake: true,
    );
    final plainBytes = (await tester.runAsync(() => _rasterize(plain)))!;

    expect(bakedBytes, equals(plainBytes), reason: reason);
  }

  testWidgets('n=0 — a drawn row under and a drawn row over the active layer', (
    tester,
  ) async {
    await expectSamePixels(
      tester,
      [
        drawnRow('under', opacity: 0.6),
        const CanvasActiveLayerNode(opacity: 1),
        drawnRow('over', opacity: 0.4),
      ],
      drawn: const ['under', 'over'],
      reason: 'the commonest case: one recording below, one above',
    );
  });

  testWidgets('the active layer INSIDE a blended folder — the case the flat '
      'split could never do', (tester) async {
    await expectSamePixels(
      tester,
      [
        drawnRow('under'),
        CanvasLayerGroupNode(
          children: [
            drawnRow('folder-under'),
            const CanvasActiveLayerNode(opacity: 1),
            drawnRow('folder-over'),
          ],
          opacity: 0.5,
          blendMode: LayerBlendMode.multiply,
        ),
        drawnRow('over'),
      ],
      drawn: const ['under', 'folder-under', 'folder-over', 'over'],
      reason:
          'the enclosing folder must stay LIVE — baking it would put the '
          'stroke outside the saveLayer it belongs in',
    );
  });

  testWidgets('a blended folder that does NOT contain the active layer bakes '
      'whole, and still looks the same', (tester) async {
    await expectSamePixels(
      tester,
      [
        CanvasLayerGroupNode(
          children: [drawnRow('a'), drawnRow('b')],
          opacity: 0.5,
          blendMode: LayerBlendMode.multiply,
        ),
        const CanvasActiveLayerNode(opacity: 1),
      ],
      drawn: const ['a', 'b'],
      reason: 'a folder off the chain is static for the stroke, buffer and all',
    );
  });

  testWidgets('nested — the active layer two folders deep, with siblings at '
      'every level', (tester) async {
    await expectSamePixels(
      tester,
      [
        drawnRow('root-under'),
        CanvasLayerGroupNode(
          children: [
            drawnRow('outer-under'),
            CanvasLayerGroupNode(
              children: [
                drawnRow('inner-under'),
                const CanvasActiveLayerNode(opacity: 0.75),
                drawnRow('inner-over'),
              ],
              opacity: 0.5,
              blendMode: LayerBlendMode.multiply,
            ),
            drawnRow('outer-over'),
          ],
          opacity: 1,
          blendMode: LayerBlendMode.screen,
        ),
      ],
      drawn: const [
        'root-under',
        'outer-under',
        'inner-under',
        'inner-over',
        'outer-over',
      ],
      reason: 'both enclosing buffers stay live, and all six recordings match',
    );
  });

  testWidgets('an ADJUSTMENT scope enclosing the active layer stays live', (
    tester,
  ) async {
    await expectSamePixels(
      tester,
      [
        CanvasLayerAdjustmentNode(
          children: [
            drawnRow('graded'),
            const CanvasActiveLayerNode(opacity: 1),
          ],
          effects: const [],
          mix: 0.5,
        ),
        drawnRow('over'),
      ],
      drawn: const ['graded', 'over'],
      reason: 'R6b: a stroke under a grade reads through it while you draw',
    );
  });

  /// 🚨🚨★★★ THE CONTRACT THE PIXEL COMPARISONS ABOVE CANNOT MAKE.
  ///
  /// Baking the active layer along with everything else produces an
  /// IDENTICAL first paint — the recording contains the right pixels, so a
  /// one-shot comparison sees nothing wrong. It only goes wrong on the
  /// second paint, which is every paint of a stroke after the first: the
  /// replay keeps handing back the stroke as it looked when it was
  /// recorded, and the drawing stops following the pen.
  ///
  /// 🔬Measured, not reasoned: mutating `_enclosesActiveSurface` to answer
  /// false for folders (so an enclosing folder — and the live surface
  /// inside it — gets baked whole) left every comparison above PASSING.
  /// This is the test that kills that mutation.
  /// ⚠️Every enclosing KIND needs its own run of this. The folder arm and
  /// the adjustment arm of `_enclosesActiveSurface` are separate lines, and
  /// mutating the adjustment one survived a suite that only nested the live
  /// surface in a folder.
  Future<void> expectStrokeFollowsThePen(
    WidgetTester tester, {
    required CanvasLayerStackNode Function(List<CanvasLayerStackNode>) enclose,
  }) async {
    final surfacePainter = _SwappableSurface(canvasSize);
    final painter = await pumpStack(
      tester,
      nodes: [
        drawnRow('under'),
        enclose([
          drawnRow('inside'),
          const CanvasActiveLayerNode(opacity: 1),
        ]),
        drawnRow('over'),
      ],
      cache: cacheWithStrokes(const ['under', 'inside', 'over']),
      surfacePainter: surfacePainter,
      disableBake: false,
    );

    final beforeStroke = (await tester.runAsync(() => _rasterize(painter)))!;

    // One more stroke step: the live surface, and ONLY the live surface, now
    // draws something else. No pump — a stroke step reaches the canvas
    // through the repaint Listenable rather than a rebuild, which is the
    // whole reason the bake is worth having.
    surfacePainter.ink = const Color(0xFF0000FF);
    final afterStroke = (await tester.runAsync(() => _rasterize(painter)))!;

    expect(
      afterStroke,
      isNot(equals(beforeStroke)),
      reason:
          'the canvas replayed a recording of the live surface — the stroke '
          'froze at the frame the bake was taken',
    );
  }

  testWidgets('⛔inside a FOLDER, the live surface is never in a recording', (
    tester,
  ) async {
    await expectStrokeFollowsThePen(
      tester,
      // ⚠️NORMAL, not multiply. Under multiply over green paper red and blue
      // both resolve to black, so the ink swap would be invisible for a
      // reason that has nothing to do with the bake — this failed on correct
      // code until that was spotted.
      enclose: (children) => CanvasLayerGroupNode(
        children: children,
        opacity: 1,
        blendMode: LayerBlendMode.normal,
      ),
    );
  });

  testWidgets('⛔inside an ADJUSTMENT scope, the live surface is never in a '
      'recording either', (tester) async {
    await expectStrokeFollowsThePen(
      tester,
      enclose: (children) => CanvasLayerAdjustmentNode(
        children: children,
        effects: const [],
        mix: 0.5,
      ),
    );
  });

  testWidgets('replaying is not drifting — the second paint of one bake '
      'matches its first', (tester) async {
    final surfacePainter = redSurface();
    final painter = await pumpStack(
      tester,
      nodes: [
        drawnRow('under'),
        const CanvasActiveLayerNode(opacity: 1),
        drawnRow('over'),
      ],
      cache: cacheWithStrokes(const ['under', 'over']),
      surfacePainter: surfacePainter,
      disableBake: false,
    );

    // The first paint records; every one after it replays. A stroke is
    // hundreds of the latter, so they had better be identical.
    final first = (await tester.runAsync(() => _rasterize(painter)))!;
    final second = (await tester.runAsync(() => _rasterize(painter)))!;

    expect(second, equals(first));
  });
}

/// A live surface whose content can change between paints WITHOUT a rebuild
/// — which is exactly how a stroke step reaches the canvas.
class _SwappableSurface extends BitmapSurfacePainter {
  _SwappableSurface(CanvasSize canvasSize)
    : super(
        surface: BitmapSurface(
          canvasSize: canvasSize,
          tileSize: 4,
          tiles: const {},
        ),
        showTransparentBackground: false,
      );

  Color ink = const Color(0xFFFF0000);

  /// 🚨This double draws from a field it does not publish, so nothing that
  /// inspects a surface painter can tell WHEN — let alone where — it
  /// changed. Saying so is not a concession to a cache: it is the honest
  /// answer, and a cache that believed otherwise would serve this stub's
  /// first frame for the rest of the stroke. That is exactly what the two
  /// tests below catch.
  @override
  bool get drawsOnlyFromPublishedState => false;

  @override
  void paintContentInto(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 4, 4),
      Paint()..color = ink,
    );
  }
}

Future<Uint8List> _rasterize(CustomPainter painter) async {
  final recorder = ui.PictureRecorder();
  const size = Size(4, 4);
  final canvas = Canvas(recorder, Offset.zero & size);
  painter.paint(canvas, size);
  final image = await recorder.endRecording().toImage(4, 4);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bytes!.buffer.asUint8List();
}
