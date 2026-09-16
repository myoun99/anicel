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
import 'package:anicel/src/models/composite_tree.dart';

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
  const projectId = ProjectId('p');
  const cutId = CutId('c');
  const trackId = TrackId('t');

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
        historyPolicy: const BrushHistoryPolicy(),
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

  CompositeNode<CanvasStackRow> drawnRow(String id, {double opacity = 1}) =>
      CompositeLeaf<CanvasStackRow>(
        CanvasLayerImageRequest(frameKey: key(id), opacity: opacity),
      );

  BitmapSurfacePainter redSurface() {
    var tile = BitmapTile.blank(size: 4);
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
        tiles: {TileCoord(x: 0, y: 0): tile},
      ),
      showTransparentBackground: false,
    );
  }

  Future<CustomPainter> pumpStack(
    WidgetTester tester, {
    required List<CompositeNode<CanvasStackRow>> nodes,
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
    required List<CompositeNode<CanvasStackRow>> nodes,
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
        const CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1)),
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
        CompositeGroup<CanvasStackRow>(
          children: [
            drawnRow('inside'),
            const CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1)),
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
    //
    // ⚠️50% ON SCREEN, so the ratio is pinned: the scale the law reads is
    // zoom × ratio, and on the tester's default ratio of 3 a render zoom of
    // 0.5 is 150% on screen — magnified, nearest on both routes, and the
    // two pictures rightly agree there (2026-09-16).
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final nodes = [
      drawnRow('under'),
      const CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1)),
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

    test(
      'the scale is the DEVICE scale, zoom × ratio — rotation and flips do '
      'not resample, and a tablet\'s ratio does not make 140% a reduction',
      () {
        expect(displayScaleOf(0.5, 1), 0.5);
        expect(displayScaleOf(-2, 1), 2, reason: 'a flip is not a reduction');
        expect(
          displayScaleOf(0.7, 2),
          moreOrLessEquals(1.4),
          reason: 'render zoom 0.7 on a ratio-2 screen is 140% on screen — '
              'magnified. Reading the zoom alone called it reduced and '
              'filtered a magnified view (유저 09-16: 「표시배율 100%부터는 '
              '필터가 걸리면안되」).',
        );
        expect(
          filterQualityForDisplayScale(displayScaleOf(0.5, 2)),
          ui.FilterQuality.none,
          reason: 'device 100% is 1:1 whatever the render zoom says',
        );
        expect(
          filterQualityForDisplayScale(displayScaleOf(0.4, 2)),
          ui.FilterQuality.low,
          reason: 'device 80% is a reduction',
        );
      },
    );

    test(
      'the edge is one more texel boundary: cut on the pixel grid under '
      'nearest, anti-aliased under bilinear and under rotation '
      '(F-67-paper-edge)',
      () {
        expect(
          displayEdgeAntiAliased(CanvasViewport(zoom: 1.1), 1),
          isFalse,
          reason: 'magnified samples nearest: every boundary inside the '
              'image is decided by pixel centres, and the outer edge is '
              'one more of them — anti-aliasing it alone paints the '
              'blended line the phase snap made visible at 110%',
        );
        expect(displayEdgeAntiAliased(CanvasViewport(zoom: 1), 1), isFalse);
        expect(displayEdgeAntiAliased(CanvasViewport(zoom: 2), 1), isFalse);
        expect(
          displayEdgeAntiAliased(
            CanvasViewport(zoom: 1.1, flipHorizontal: true),
            1,
          ),
          isFalse,
          reason: 'a flip is axis-aligned',
        );
        expect(
          displayEdgeAntiAliased(CanvasViewport(zoom: 0.5), 1),
          isTrue,
          reason: 'reduced samples bilinear: the boundaries inside blend, '
              'so the edge blends with them',
        );
        expect(
          displayEdgeAntiAliased(CanvasViewport(zoom: 0.5), 2),
          isFalse,
          reason: 'device 100% on a ratio-2 screen samples nearest, so its '
              'edge is cut on the grid like every other 1:1 view',
        );
        expect(
          displayEdgeAntiAliased(
            CanvasViewport(zoom: 1.1, rotationDegrees: 15),
            1,
          ),
          isTrue,
          reason: 'a rotated edge is a diagonal',
        );
      },
    );
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
