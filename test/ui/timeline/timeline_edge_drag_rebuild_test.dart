import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

import 'timeline_cell_probe.dart';

/// THE edit-drag performance invariant (W1): an edge-drag step travels the
/// scoped [dragPreview] channel only — it rebuilds the dragged layer's row
/// gate (and the cursor overlay), never the other rows, the grid, or the
/// session listeners. The release commits ONE undoable command.
void main() {
  Layer blockLayer(String id, {int length = 2}) => Layer(
    id: LayerId(id),
    name: id,
    frames: [Frame(id: FrameId('$id-f1'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-f1'), length: length)},
  );

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (layer.timeline[frameIndex]?.isDrawing ?? false) {
      return TimelineCellExposureState.drawingStart;
    }
    if (coveringDrawingBlockAt(layer.timeline, frameIndex) != null) {
      return TimelineCellExposureState.held;
    }
    return TimelineCellExposureState.uncovered;
  }

  Widget gridHarness({
    required List<Layer> layers,
    required ValueNotifier<int> cursor,
    ValueNotifier<TimelineDragPreview?>? dragPreview,
    LayerId? activeLayerId,
    double? height,
  }) {
    final grid = LayerTimelineGrid(
      layers: layers,
      activeLayerId: activeLayerId ?? layers.first.id,
      frameCursor: cursor,
      dragPreview: dragPreview,
      playbackFrameCount: 24,
      exposureStateForLayer: stateFor,
      onSelectLayer: (_) {},
      onSelectFrame: (_) {},
      onAddLayer: () {},
      onToggleLayerVisibility: (_) {},
      onLayerOpacityChanged: (_, _) {},
      onToggleLayerTimesheet: (_) {},
      onLayerMarkSelected: (_, _) {},
    );
    return MaterialApp(
      home: Scaffold(
        body: height == null
            ? grid
            : Align(
                alignment: Alignment.topLeft,
                child: SizedBox(height: height, child: grid),
              ),
      ),
    );
  }

  group('drag preview channel (widget)', () {
    testWidgets('a preview step rebuilds only the dragged layer\'s row', (
      tester,
    ) async {
      final layerA = blockLayer('layer-a');
      final layerB = blockLayer('layer-b');
      final cursor = ValueNotifier<int>(0);
      final preview = ValueNotifier<TimelineDragPreview?>(null);
      addTearDown(cursor.dispose);
      addTearDown(preview.dispose);

      await tester.pumpWidget(
        gridHarness(
          layers: [layerA, layerB],
          cursor: cursor,
          dragPreview: preview,
        ),
      );

      final rowB = find.byKey(
        const ValueKey<String>('timeline-row-cells-layer-b'),
      );
      final rowBBefore = tester.widget(rowB);
      // Base: block [0,2) — frame 2 is an empty X cell.
      expect(timelineCellModel(tester, 'layer-a', 2).glyph, 'X');

      // One drag step: the preview layer holds the block out to length 4.
      preview.value = ExposureEdgeDragPreview(
        previewLayer: layerA.copyWith(
          timeline: {
            0: TimelineExposure.drawing(const FrameId('layer-a-f1'), length: 4),
          },
        ),
      );
      await tester.pump();

      // The dragged row follows the preview…
      expect(timelineCellModel(tester, 'layer-a', 2).glyph, isNot('X'));
      // …and the OTHER row was never rebuilt (paint identity, UI-R9 #12b).
      expect(
        identical(tester.widget(rowB), rowBBefore),
        isTrue,
        reason: 'a drag step must rebuild only the dragged layer\'s row',
      );

      // Clearing the preview restores the base row.
      preview.value = null;
      await tester.pump();
      expect(timelineCellModel(tester, 'layer-a', 2).glyph, 'X');
      expect(identical(tester.widget(rowB), rowBBefore), isTrue);
    });

    testWidgets('X-sheet columns gate the same way (Axis policy)', (
      tester,
    ) async {
      final layerA = blockLayer('layer-a');
      final layerB = blockLayer('layer-b');
      final cursor = ValueNotifier<int>(0);
      final preview = ValueNotifier<TimelineDragPreview?>(null);
      addTearDown(cursor.dispose);
      addTearDown(preview.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: XSheetTimelineGrid(
              layers: [layerA, layerB],
              activeLayerId: layerA.id,
              frameCursor: cursor,
              dragPreview: preview,
              frameCount: 24,
              exposureStateForLayer: stateFor,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
              onAddLayer: () {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
            ),
          ),
        ),
      );

      final columnB = find.byKey(
        const ValueKey<String>('xsheet-row-cells-layer-b'),
      );
      final columnBBefore = tester.widget(columnB);
      expect(
        timelineCellModel(tester, 'layer-a', 2, prefix: 'xsheet').glyph,
        'X',
      );

      preview.value = ExposureEdgeDragPreview(
        previewLayer: layerA.copyWith(
          timeline: {
            0: TimelineExposure.drawing(const FrameId('layer-a-f1'), length: 4),
          },
        ),
      );
      await tester.pump();

      expect(
        timelineCellModel(tester, 'layer-a', 2, prefix: 'xsheet').glyph,
        isNot('X'),
      );
      expect(
        identical(tester.widget(columnB), columnBBefore),
        isTrue,
        reason: 'a drag step must rebuild only the dragged layer\'s column',
      );
    });
  });

  group('drag preview channel (session)', () {
    test('exposure drag: repo untouched per step, one notify + one undo on '
        'end', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      s.createDrawingAtCurrentFrame();
      final layer = s.activeLayer!;
      final baseTimeline = Map.of(layer.timeline);
      var notifies = 0;
      s.addListener(() => notifies += 1);

      expect(
        s.beginExposureEdgeDrag(
          layerId: layer.id,
          blockStartIndex: 0,
          edge: TimelineBlockEdge.end,
        ),
        isTrue,
      );
      s.updateExposureEdgeDrag(3);

      // The preview rides the channel; the repository and the session
      // listeners stay untouched (the drag-lag fix's core invariant).
      final preview = s.dragPreview.value;
      expect(preview, isA<ExposureEdgeDragPreview>());
      expect(
        (preview as ExposureEdgeDragPreview).previewLayer.timeline[0]!.length,
        baseTimeline[0]!.length! + 3,
      );
      expect(s.activeLayer!.timeline[0]!.length, baseTimeline[0]!.length);
      expect(notifies, 0);

      s.endExposureEdgeDrag();
      expect(s.dragPreview.value, isNull);
      expect(s.activeLayer!.timeline[0]!.length, baseTimeline[0]!.length! + 3);
      expect(notifies, 1);

      // ONE undo step for the whole drag.
      s.undo();
      expect(s.activeLayer!.timeline[0]!.length, baseTimeline[0]!.length);
      s.redo();
      expect(s.activeLayer!.timeline[0]!.length, baseTimeline[0]!.length! + 3);
    });

    test('cancel drops the preview without repo or history traces', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      s.createDrawingAtCurrentFrame();
      final layer = s.activeLayer!;
      final baseLength = layer.timeline[0]!.length;
      final undoProbe = s.canUndo;
      var notifies = 0;
      s.addListener(() => notifies += 1);

      s.beginExposureEdgeDrag(
        layerId: layer.id,
        blockStartIndex: 0,
        edge: TimelineBlockEdge.end,
      );
      s.updateExposureEdgeDrag(5);
      s.cancelExposureEdgeDrag();

      expect(s.dragPreview.value, isNull);
      expect(s.activeLayer!.timeline[0]!.length, baseLength);
      expect(s.canUndo, undoProbe);
      expect(notifies, 0);
    });
  });

  group('layer-axis virtualization', () {
    testWidgets('off-window rows are not built; scrolling reveals them', (
      tester,
    ) async {
      final layers = [for (var i = 0; i < 40; i++) blockLayer('layer-$i')];
      final cursor = ValueNotifier<int>(0);
      addTearDown(cursor.dispose);

      await tester.pumpWidget(
        gridHarness(layers: layers, cursor: cursor, height: 300),
      );

      final nearCell = find.byKey(
        const ValueKey<String>('timeline-row-cells-layer-0'),
      );
      final farCell = find.byKey(
        const ValueKey<String>('timeline-row-cells-layer-38'),
      );
      expect(nearCell, findsOneWidget);
      expect(
        farCell,
        findsNothing,
        reason: 'rows far below the viewport must not be built',
      );

      // Jump the vertical viewport to the end: the window slides to the
      // last rows (rows are layerRowHeight tall).
      final scrollable = find.descendant(
        of: find.byKey(
          const ValueKey<String>('timeline-vertical-scroll-viewport'),
        ),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable.first).position;
      expect(position.maxScrollExtent, greaterThan(0));
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();

      expect(farCell, findsOneWidget);
      expect(nearCell, findsNothing);
    });
  });

  group('commit-time row memo', () {
    testWidgets('an untouched layer\'s row survives a sibling edit rebuild', (
      tester,
    ) async {
      var layerA = blockLayer('layer-a');
      final layerB = blockLayer('layer-b');
      final cursor = ValueNotifier<int>(0);
      addTearDown(cursor.dispose);
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return LayerTimelineGrid(
                  layers: [layerA, layerB],
                  activeLayerId: layerA.id,
                  frameCursor: cursor,
                  playbackFrameCount: 24,
                  exposureStateForLayer: stateFor,
                  onSelectLayer: (_) {},
                  onSelectFrame: (_) {},
                  onAddLayer: () {},
                  onToggleLayerVisibility: (_) {},
                  onLayerOpacityChanged: (_, _) {},
                  onToggleLayerTimesheet: (_) {},
                  onLayerMarkSelected: (_, _) {},
                );
              },
            ),
          ),
        ),
      );

      final rowA = find.byKey(
        const ValueKey<String>('timeline-row-cells-layer-a'),
      );
      final rowB = find.byKey(
        const ValueKey<String>('timeline-row-cells-layer-b'),
      );
      final rowABefore = tester.widget(rowA);
      final rowBBefore = tester.widget(rowB);

      // A commit-style rebuild: layer A's identity changes, B's does not.
      layerA = layerA.copyWith(
        timeline: {
          0: TimelineExposure.drawing(const FrameId('layer-a-f1'), length: 4),
        },
      );
      rebuild(() {});
      await tester.pump();

      expect(
        identical(tester.widget(rowB), rowBBefore),
        isTrue,
        reason: 'rows of identical layers must reuse their cached widget',
      );
      expect(
        identical(tester.widget(rowA), rowABefore),
        isFalse,
        reason: 'the edited layer\'s row must rebuild',
      );
    });
  });
}
