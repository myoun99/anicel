import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/controllers/default_project_helpers.dart';
import 'package:quick_animaker_v2/src/models/bitmap_surface.dart';
import 'package:quick_animaker_v2/src/models/bitmap_tile.dart';
import 'package:quick_animaker_v2/src/models/canvas_size.dart';
import 'package:quick_animaker_v2/src/models/frame.dart';
import 'package:quick_animaker_v2/src/models/frame_id.dart';
import 'package:quick_animaker_v2/src/models/layer.dart';
import 'package:quick_animaker_v2/src/models/layer_id.dart';
import 'package:quick_animaker_v2/src/models/layer_kind.dart';
import 'package:quick_animaker_v2/src/models/tile_coord.dart';
import 'package:quick_animaker_v2/src/models/timeline_coverage.dart';
import 'package:quick_animaker_v2/src/models/timeline_exposure.dart';
import 'package:quick_animaker_v2/src/ui/editor_session_manager.dart';
import 'package:quick_animaker_v2/src/ui/timeline/property_lane_model.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_cell_style.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_frame_rows_scroll_body.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_row_cells_painter.dart';

import 'timeline_frame_geometry_probe.dart';

/// R26 #44: ACTION-section blocks whose cel holds no picture yet paint a
/// slightly grayed paper — the painter's style resolution, the session's
/// fact/token pair, and the row memo's token invalidation.
void main() {
  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (layer.timeline[frameIndex]?.isDrawing ?? false) {
      return TimelineCellExposureState.drawingStart;
    }
    if (coveringDrawingBlockAt(layer.timeline, frameIndex) != null) {
      return TimelineCellExposureState.held;
    }
    return TimelineCellExposureState.uncovered;
  }

  Layer twoBlockLayer() => Layer(
    id: const LayerId('layer-a'),
    name: 'A',
    frames: [
      Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
      Frame(id: const FrameId('f2'), duration: 1, strokes: const []),
    ],
    timeline: {
      0: const TimelineExposure.drawing(FrameId('f1'), length: 2),
      2: const TimelineExposure.drawing(FrameId('f2'), length: 1),
    },
  );

  TimelineRowCellsPainter painterFor(
    Layer layer, {
    bool Function(Layer layer, int frameIndex)? celHasContentForLayer,
  }) {
    return TimelineRowCellsPainter(
      layer: layer,
      playbackFrameCount: 24,
      geometry: testFrameGeometry(
        frameCellExtent: 24,
        frameEndIndexExclusive: 24,
      ),
      crossAxisExtent: 28,
      exposureStateForLayer: stateFor,
      celHasContentForLayer: celHasContentForLayer,
      colorScheme: const ColorScheme.dark(),
      baseTextStyle: const TextStyle(fontSize: 11),
    );
  }

  group('painter style resolution', () {
    test('an empty-cel block grays its WHOLE run (start + held); a block '
        'with content and uncovered cells stay untouched', () {
      final painter = painterFor(
        twoBlockLayer(),
        // f1's block (cells 0-1) is unworked, f2's block (cell 2) has ink.
        celHasContentForLayer: (layer, frameIndex) => frameIndex >= 2,
      );

      expect(
        painter.resolvedCellStyleFor(0).background,
        timelineEmptyCelBlockColor,
        reason: 'the empty block\'s start cell grays',
      );
      expect(
        painter.resolvedCellStyleFor(1).background,
        timelineEmptyCelBlockColor,
        reason: 'the held cell follows its block',
      );
      expect(
        painter.resolvedCellStyleFor(2).background,
        timelineDrawingStartColor,
        reason: 'a worked block keeps the plain paper',
      );
      expect(
        painter.resolvedCellStyleFor(5).background,
        Colors.transparent,
        reason: 'uncovered cells carry no substrate at all',
      );
    });

    test('no resolver = no tint (every block keeps the plain paper)', () {
      final painter = painterFor(twoBlockLayer());
      expect(painter.resolvedCellStyleFor(0).background,
          timelineDrawingStartColor);
    });
  });

  group('session fact + memo token', () {
    BitmapSurface surfaceWithInk() {
      final pixels = Uint8List(4 * 4 * 4)..fillRange(0, 16, 255);
      return BitmapSurface(
        canvasSize: const CanvasSize(width: 4, height: 4),
        tileSize: 4,
      ).putTile(
        BitmapTile(coord: TileCoord(x: 0, y: 0), size: 4, pixels: pixels),
      );
    }

    test('an undrawn cel answers false and joins the token; storing ink '
        'flips both; non-drawing sections always answer true', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      s.createDrawingAtCurrentFrame();
      final layer = s.activeLayer!;
      final frameId = layer.frames.single.id;

      expect(s.celHasContentForLayer(layer, 0), isFalse);
      expect(s.celContentTokenForLayer(layer), frameId.value);

      s.brushFrameStore.storeBakedSurface(
        s.brushFrameKeyForCut(s.activeCutOrNull!, layer.id, frameId),
        surfaceWithInk(),
      );
      expect(s.celHasContentForLayer(layer, 0), isTrue);
      expect(s.celContentTokenForLayer(layer), isEmpty);

      // CAM rows never tint and carry no token — the fact never renders
      // outside the ACTION section.
      final camera = s.layers.firstWhere((l) => l.kind == LayerKind.camera);
      expect(s.celHasContentForLayer(camera, 0), isTrue);
      expect(s.celContentTokenForLayer(camera), isNull);
    });

    test('R27 #13: the store ANNOUNCES the empty↔drawn crossing, and only '
        'the crossing — the tint had no signal to clear on before', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.createDrawingAtCurrentFrame();
      final layer = s.activeLayer!;
      final key = s.brushFrameKeyForCut(
        s.activeCutOrNull!,
        layer.id,
        layer.frames.single.id,
      );

      var bumps = 0;
      s.brushFrameStore.celContentRevision.addListener(() => bumps += 1);

      s.brushFrameStore.storeBakedSurface(key, surfaceWithInk());
      expect(bumps, 1, reason: 'empty → drawn');

      // A second stroke on an already-drawn cel changes no emptiness.
      s.brushFrameStore.storeBakedSurface(key, surfaceWithInk());
      expect(bumps, 1);

      // Back to blank (an undo to an empty surface).
      s.brushFrameStore.storeBakedSurface(
        key,
        BitmapSurface(
          canvasSize: const CanvasSize(width: 4, height: 4),
          tileSize: 4,
        ),
      );
      expect(bumps, 2, reason: 'drawn → empty');
      expect(s.celHasContentForLayer(layer, 0), isFalse);
    });
  });

  group('row memo invalidation', () {
    testWidgets('an unchanged token reuses the cached row; a token flip '
        'rebuilds it with the fresh fact', (tester) async {
      final layer = twoBlockLayer();
      var hasContent = false;
      var token = 'f1,f2';
      // STABLE closures across pumps — session method tear-offs compare
      // equal in production; here the same objects stand in for them.
      bool celHasContent(Layer l, int frameIndex) => hasContent;
      String? celToken(Layer l) => token;
      void onSelectLayer(LayerId id) {}
      void onSelectFrame(int index) {}

      Widget body() => MaterialApp(
        home: Material(
          child: SizedBox(
            width: 700,
            height: 200,
            child: TimelineFrameRowsScrollBody(
              rows: [TimelineDisplayRow.layer(layer, layerIndex: 0)],
              activeLayerId: null,
              playbackFrameCount: 24,
              frameStartIndex: 0,
              frameEndIndexExclusive: 24,
              leadingFrameSpacerWidth: 0,
              trailingFrameSpacerWidth: 0,
              totalFrameContentWidth: 24 * 24,
              metrics: const TimelineGridMetrics(),
              exposureStateForLayer: stateFor,
              celHasContentForLayer: celHasContent,
              celContentTokenForLayer: celToken,
              onSelectLayer: onSelectLayer,
              onSelectFrame: onSelectFrame,
            ),
          ),
        ),
      );

      TimelineRowCellsPainter painterOf() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<TimelineRowCellsPainter>()
          .single;

      await tester.pumpWidget(body());
      final first = painterOf();
      expect(
        first.resolvedCellStyleFor(0).background,
        timelineEmptyCelBlockColor,
      );

      // Same inputs = memo hit: the row (and its painter) is reused.
      await tester.pumpWidget(body());
      expect(identical(painterOf(), first), isTrue,
          reason: 'unchanged inputs must reuse the cached row');

      // An emptiness flip changes ONLY store state + the token — the
      // Layer instance is untouched. The token must carry the memo miss.
      hasContent = true;
      token = '';
      await tester.pumpWidget(body());
      final rebuilt = painterOf();
      expect(identical(rebuilt, first), isFalse,
          reason: 'the token flip must rebuild the row');
      expect(
        rebuilt.resolvedCellStyleFor(0).background,
        timelineDrawingStartColor,
      );
    });
  });
}
