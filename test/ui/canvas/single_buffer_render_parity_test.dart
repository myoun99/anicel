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
import 'package:anicel/src/ui/canvas/display_resample.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨★★★ (v) 2단계의 계약 — **한 장으로 합치고 한 번만 리샘플한다.**
///
/// 유저 확정 (T21): 「줌이 정한다 — 확대는 `none`, 축소는 필터, **액티브인지는
/// 안 묻는다**」. 유저 2026-08-15: 「왜 비액티브레이어는 aa걸려있고
/// 액티브레이어는 aa없어서 **전환할때마다 그림 바뀌지?**」
///
/// The old stack drew every layer straight under the viewport transform, so
/// the CTM resampled each of them separately and each brought its own
/// `filterQuality` — `none` for the live surface, `low` for a cached image.
/// Becoming the active layer therefore changed how a layer LOOKED.
///
/// ⚠️Parity here is an identity **at 1:1 only**, and that is the change
/// rather than a hole in the test: above and below 100% the buffer resamples
/// once where the old walk resampled N times, and the pixels are SUPPOSED to
/// differ. So this file pins the two halves separately — the composite
/// (order, blending, paper, pasteboard) must be untouched, and the sampling
/// must now be the display's decision.
void main() {
  const canvasSize = CanvasSize(width: 4, height: 4);
  final projectId = ProjectId('p');
  final cutId = CutId('c');
  final trackId = TrackId('t');

  BrushFrameKey key(String id) => BrushFrameKey(
    projectId: projectId,
    cutId: cutId,
    trackId: trackId,
    layerId: LayerId(id),
    frameId: FrameId('$id-f'),
  );

  /// 🚨Real artwork, or the tree resolves to nothing and every comparison
  /// passes without the code under test ever running — the trap the stage 1
  /// suite recorded (its first version had no siblings and was green on
  /// code that never ran).
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
    required bool disableBuffer,
    required CanvasViewport viewport,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        // A distinct key per render, so the second pump builds a FRESH state
        // rather than reusing the first one's warm bake.
        key: ValueKey<String>('$disableBuffer/${viewport.zoom}'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 4,
              height: 4,
              child: CanvasLayerStackView(
                nodes: nodes,
                imageCache: cache,
                canvasSize: canvasSize,
                viewport: viewport,
                activeSurfacePainter: surfacePainter,
                paintPaper: true,
                paperBackground: const ProjectBackground.color(0xFF00FF00),
                debugDisableSingleBuffer: disableBuffer,
              ),
            ),
          ),
        ),
      ),
    );
    // 🚨WARM FIRST, THEN LOOK — a cold cache resolves some rows on a later
    // pass, so the first pump and the second draw different numbers of rows.
    // Stage 1 measured this failing with the feature OFF on both sides.
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

  Future<Uint8List> render(
    WidgetTester tester, {
    required List<CanvasLayerStackNode> nodes,
    required List<String> drawn,
    required bool disableBuffer,
    CanvasViewport? viewport,
  }) async {
    // 🚨Each side gets its OWN cache and its OWN state. Sharing a cache made
    // stage 1's second render come back as bare paper — an instrument
    // disagreeing with itself cannot report on the thing under test.
    final painter = await pumpStack(
      tester,
      nodes: nodes,
      surfacePainter: redSurface(),
      cache: cacheWithStrokes(drawn),
      disableBuffer: disableBuffer,
      viewport: viewport ?? CanvasViewport(),
    );
    // ⚠️`toImage` is a real async round-trip: awaited under the widget
    // test's fake clock it hangs. It belongs inside `runAsync`.
    return (await tester.runAsync(() => _rasterize(painter)))!;
  }

  group('the composite is untouched — parity at 1:1', () {
    testWidgets('a drawn row under and a drawn row over the active layer', (
      tester,
    ) async {
      final nodes = [
        drawnRow('under'),
        const CanvasActiveLayerNode(opacity: 1),
        drawnRow('over'),
      ];
      final buffered = await render(
        tester,
        nodes: nodes,
        drawn: ['under', 'over'],
        disableBuffer: false,
      );
      final direct = await render(
        tester,
        nodes: nodes,
        drawn: ['under', 'over'],
        disableBuffer: true,
      );
      expect(
        buffered,
        equals(direct),
        reason: 'at 1:1 nothing is resampled either way, so compositing '
            'through a buffer may not change one pixel',
      );
    });

    testWidgets('the active layer inside a BLENDED folder', (tester) async {
      // The case the flat below/above pair could never do: a folder's
      // saveLayer cannot span sibling painters. If the buffer broke it, the
      // multiply would resolve against the wrong backdrop.
      final nodes = [
        drawnRow('under'),
        CanvasLayerGroupNode(
          children: [
            drawnRow('inside'),
            const CanvasActiveLayerNode(opacity: 1),
          ],
          opacity: 0.5,
          blendMode: LayerBlendMode.multiply,
        ),
      ];
      final buffered = await render(
        tester,
        nodes: nodes,
        drawn: ['under', 'inside'],
        disableBuffer: false,
      );
      final direct = await render(
        tester,
        nodes: nodes,
        drawn: ['under', 'inside'],
        disableBuffer: true,
      );
      expect(buffered, equals(direct));
    });
  });

  testWidgets('reduced, the buffer really is the one that resamples', (
    tester,
  ) async {
    // 🚨The counterpart to the parity group: if these matched, the buffer
    // would be an expensive no-op. At 50% the old walk resamples every layer
    // separately with its own quality; the buffer resamples one image once,
    // so the pixels MUST differ.
    final nodes = [
      drawnRow('under'),
      const CanvasActiveLayerNode(opacity: 1),
      drawnRow('over'),
    ];
    final reduced = CanvasViewport(zoom: 0.5);
    final buffered = await render(
      tester,
      nodes: nodes,
      drawn: ['under', 'over'],
      disableBuffer: false,
      viewport: reduced,
    );
    final direct = await render(
      tester,
      nodes: nodes,
      drawn: ['under', 'over'],
      disableBuffer: true,
      viewport: reduced,
    );
    expect(
      buffered,
      isNot(equals(direct)),
      reason: 'one resample of one image is not the same picture as N '
          'resamples of N layers — if it were, nothing would have changed',
    );
  });

  group('the law: 줌이 정한다, 액티브는 안 묻는다', () {
    test('reduced filters, magnified does not', () {
      expect(
        filterQualityForDisplayScale(0.5),
        ui.FilterQuality.low,
        reason: 'more artwork pixels than screen pixels — point sampling '
            'throws most of them away and the line work crawls',
      );
      expect(
        filterQualityForDisplayScale(2),
        ui.FilterQuality.none,
        reason: 'the artist is looking at pixels, so show pixels',
      );
      expect(
        filterQualityForDisplayScale(1),
        ui.FilterQuality.none,
        reason: 'nothing is being resampled at all',
      );
    });

    test('the scale is the zoom — rotation and flips do not resample', () {
      expect(displayScaleOf(0.5), 0.5);
      expect(displayScaleOf(-2), 2, reason: 'a flip is not a reduction');
    });
  });
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
