import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/transform_track.dart';

import 'timeline_cell_probe.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_range_gesture.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformPropertyLanes;
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

/// UI-R8: the row-wide range gesture layer — a cell drag SELECTS a frame
/// range, a drag starting inside the selection MOVES it (frame steps along
/// the main axis, row steps across; the grid resolves rows to layers).
void main() {
  Layer blockLayer(String id, {int length = 4, int start = 0}) => Layer(
    id: LayerId(id),
    name: id,
    frames: [Frame(id: FrameId('$id-f1'), duration: 1, strokes: const [])],
    timeline: {
      start: TimelineExposure.drawing(FrameId('$id-f1'), length: length),
    },
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

  Widget harness({
    required List<Layer> layers,
    required ValueNotifier<int> cursor,
    required TimelineFrameRangeHooks rangeHooks,
    ValueChanged<int>? onSelectFrame,
    // Classic geometry: this file's pan distances assume 48×52 cells.
    TimelineGridMetrics metrics = const TimelineGridMetrics(
      frameCellWidth: 48,
      layerRowHeight: 52,
    ),
  }) {
    return MaterialApp(
      home: Scaffold(
        body: LayerTimelineGrid(
          layers: layers,
          activeLayerId: layers.first.id,
          frameCursor: cursor,
          playbackFrameCount: 24,
          exposureStateForLayer: stateFor,
          onSelectLayer: (_) {},
          onSelectFrame: onSelectFrame ?? (_) {},
          onAddLayer: () {},
          onToggleLayerVisibility: (_) {},
          onLayerOpacityChanged: (_, _) {},
          onToggleLayerTimesheet: (_) {},
          onLayerMarkSelected: (_, _) {},
          rangeHooks: rangeHooks,
          metrics: metrics,
        ),
      ),
    );
  }

  TimelineFrameRangeHooks hooks({
    required ValueNotifier<TimelineFrameRangeSelection?> selection,
    void Function(LayerId, int, int)? onSelectUpdate,

    /// The rows the GRID says the drag swept — the seam the span law rides.
    /// Captured here rather than read off the session because this file
    /// mounts the real grid and drives real gestures, which is the only
    /// place that can tell "the slice is computed" from "the slice is
    /// handed over".
    void Function(List<TimelineRowAddress>)? onSpanRows,
    VoidCallback? onClear,
    bool Function()? onMoveBegin,
    void Function({required int frameDelta, LayerId? targetLayerId})?
    onMoveUpdate,
    VoidCallback? onMoveEnd,
  }) {
    return TimelineFrameRangeHooks(
      selection: selection,
      onSelectUpdate:
          (
            layerId,
            anchorIndex,
            headIndex, {
            headLayerId,
            headLaneId,
            spanRows = const [],
          }) {
            onSelectUpdate?.call(layerId, anchorIndex, headIndex);
            onSpanRows?.call(spanRows);
          },
      onClear: onClear ?? () {},
      move: TimelineRangeMoveCallbacks(
        onBegin: onMoveBegin == null ? (_) => true : (_) => onMoveBegin(),
        onUpdate: onMoveUpdate ?? ({required frameDelta, targetLayerId}) {},
        onEnd: onMoveEnd ?? () {},
        onCancel: () {},
      ),
    );
  }

  testWidgets('EVERY layer row mounts the range gesture layer — SE, camera '
      'and instruction rows select too (UI-R20 #2)', (tester) async {
    final cursor = ValueNotifier<int>(0);
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(null);
    addTearDown(cursor.dispose);
    addTearDown(selection.dispose);
    final selectUpdates = <(LayerId, int, int)>[];

    await tester.pumpWidget(
      harness(
        layers: [
          blockLayer('layer-a'),
          blockLayer('se-1').copyWith(kind: LayerKind.se),
          blockLayer('cam-1').copyWith(kind: LayerKind.camera),
          blockLayer('instr-1').copyWith(kind: LayerKind.instruction),
        ],
        cursor: cursor,
        rangeHooks: hooks(
          selection: selection,
          onSelectUpdate: (layerId, anchor, head) =>
              selectUpdates.add((layerId, anchor, head)),
        ),
      ),
    );

    for (final id in ['layer-a', 'se-1', 'cam-1', 'instr-1']) {
      expect(
        find.byKey(ValueKey<String>('timeline-range-gesture-$id')),
        findsOneWidget,
        reason: '$id must carry the gesture layer',
      );
    }

    // An SE-ORIGIN drag reports select updates with the SE row's id (the
    // reported bug: selection could extend INTO SE but never start
    // there). Start on an EMPTY cell (past the block at [0,4) — the SE
    // writing overlays sit above the gesture layer over the block span).
    final seLayer = find.byKey(
      const ValueKey<String>('timeline-range-gesture-se-1'),
    );
    final gesture = await tester.startGesture(
      tester.getTopLeft(seLayer) + const Offset(24 + 5 * 48, 26),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(96, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(selectUpdates, isNotEmpty);
    expect(selectUpdates.last.$1, const LayerId('se-1'));
  });

  testWidgets('the grid HANDS OVER the rows it swept, not just the layer ids '
      '— the span law\'s seam', (tester) async {
    // 🚨This is the half a pure-function test cannot reach. The slice itself
    // is pinned in `selection_span_rows_test.dart`, and it would keep
    // passing with the grid quietly sending `const []` — which is exactly
    // the shape of failure this repo has hit before (「배선을 고쳤으면 오라클도
    // 배선의 산출물이어야 한다」).
    final cursor = ValueNotifier<int>(0);
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(null);
    addTearDown(cursor.dispose);
    addTearDown(selection.dispose);
    final spans = <List<TimelineRowAddress>>[];

    await tester.pumpWidget(
      harness(
        layers: [
          blockLayer('layer-a'),
          blockLayer('se-1').copyWith(kind: LayerKind.se),
        ],
        cursor: cursor,
        rangeHooks: hooks(selection: selection, onSpanRows: spans.add),
      ),
    );

    final anchorRow = find.byKey(
      const ValueKey<String>('timeline-range-gesture-layer-a'),
    );
    final gesture = await tester.startGesture(
      tester.getTopLeft(anchorRow) + const Offset(24 + 5 * 48, 26),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(96, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(spans, isNotEmpty, reason: 'the drag reported at least once');
    expect(
      spans.last,
      isNotEmpty,
      reason: 'an empty span means the grid computed the slice and threw it '
          'away — the selection then falls back to a model walk, which is '
          'the whole thing this round removed',
    );
    expect(
      spans.last.first,
      const LayerRowAddress(LayerId('layer-a')),
      reason: 'the run starts at the row the drag anchored on',
    );
  });

  testWidgets('with touch-timeline-scroll ON, a TOUCH pan no longer '
      'selects (UI-R22 #6: the scroll owns touch then)', (tester) async {
    AppInput.settings.value = const AppInputSettings(touchTimelineScroll: true);
    addTearDown(() {
      // Back to the CORPUS baseline (flutter_test_config pins OFF; the
      // class default is ON since UI-R22F).
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    });
    final cursor = ValueNotifier<int>(0);
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(null);
    addTearDown(cursor.dispose);
    addTearDown(selection.dispose);
    final selectUpdates = <(LayerId, int, int)>[];

    await tester.pumpWidget(
      harness(
        layers: [blockLayer('layer-a')],
        cursor: cursor,
        rangeHooks: hooks(
          selection: selection,
          onSelectUpdate: (layerId, anchor, head) =>
              selectUpdates.add((layerId, anchor, head)),
        ),
      ),
    );

    final gestureLayer = find.byKey(
      const ValueKey<String>('timeline-range-gesture-layer-a'),
    );
    final gesture = await tester.startGesture(
      tester.getTopLeft(gestureLayer) + const Offset(24 + 5 * 48, 26),
      kind: PointerDeviceKind.touch,
    );
    await gesture.moveBy(const Offset(96, 0));
    await gesture.up();
    await tester.pump();
    expect(
      selectUpdates,
      isEmpty,
      reason: 'touch belongs to the scroll while the toggle is ON',
    );
  });

  testWidgets('a SLOW SMALL pen drag SELECTS — it must not lose the arena '
      'to the scroll (UI-R22F #2: eager slop, no fast/slow split)', (
    tester,
  ) async {
    final cursor = ValueNotifier<int>(0);
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(null);
    addTearDown(cursor.dispose);
    addTearDown(selection.dispose);
    final selectUpdates = <(LayerId, int, int)>[];

    await tester.pumpWidget(
      harness(
        layers: [blockLayer('layer-a')],
        cursor: cursor,
        rangeHooks: hooks(
          selection: selection,
          onSelectUpdate: (layerId, anchor, head) =>
              selectUpdates.add((layerId, anchor, head)),
        ),
      ),
    );

    List<double> scrollOffsets() => tester
        .stateList<ScrollableState>(
          find.byType(Scrollable, skipOffstage: false),
        )
        .map((state) => state.position.pixels)
        .toList();
    final offsetsBefore = scrollOffsets();

    // 6 × 4px stylus creeps = 24px total: past the viewport recognizers'
    // ~18px hit slop but UNDER the old ~36px pan slop — exactly the drag
    // the horizontal scroll used to steal (fast big drags selected, slow
    // small ones scrolled: the "random" split this pins away).
    final gestureLayer = find.byKey(
      const ValueKey<String>('timeline-range-gesture-layer-a'),
    );
    final gesture = await tester.startGesture(
      tester.getTopLeft(gestureLayer) + const Offset(24 + 5 * 48, 26),
      kind: PointerDeviceKind.stylus,
    );
    for (var step = 0; step < 6; step += 1) {
      await gesture.moveBy(const Offset(4, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(
      selectUpdates,
      isNotEmpty,
      reason: 'the slow pen drag must range-select, never scroll',
    );
    expect(selectUpdates.last.$1, const LayerId('layer-a'));
    expect(
      scrollOffsets(),
      offsetsBefore,
      reason: 'no viewport may have consumed the pen drag',
    );
  });

  testWidgets('a drag on a LANE BAND selects on THAT (layer, lane) — the '
      'lane-scoped domain (UI-R23 #3 part 2, superseding the R22-C '
      'owner-layer fallback) — and selected keys ring accent 1', (
    tester,
  ) async {
    final cursor = ValueNotifier<int>(0);
    final laneSelection = ValueNotifier<TimelineLaneSelection?>(null);
    addTearDown(cursor.dispose);
    addTearDown(laneSelection.dispose);
    final selectUpdates = <(LayerId, String, int, int)>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            layers: [blockLayer('layer-a')],
            activeLayerId: const LayerId('layer-a'),
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
            expandedLaneLayerIds: {const LayerId('layer-a')},
            lanesForLayer: (_) => [
              const PropertyLaneRow(
                laneId: 'position',
                label: 'Position',
                keyedFrames: {2},
              ),
            ],
            laneRange: TimelineLaneRangeCallbacks(
              selection: laneSelection,
              onSelectUpdate: (layerId, laneId, anchor, head, headRowDelta) {
                selectUpdates.add((layerId, laneId, anchor, head));
                laneSelection.value = TimelineLaneSelection(
                  layerId: layerId,
                  laneId: laneId,
                  startIndex: anchor < head ? anchor : head,
                  endIndexExclusive: (anchor > head ? anchor : head) + 1,
                );
              },
              onTapAt: (_, _, _) => laneSelection.value = null,
              onMoveBegin: () => false,
              onMoveUpdate: (_) {},
              onMoveEnd: () {},
              onMoveCancel: () {},
            ),
            metrics: const TimelineGridMetrics(
              frameCellWidth: 48,
              layerRowHeight: 52,
            ),
          ),
        ),
      ),
    );

    final laneGesture = find.byKey(
      const ValueKey<String>('timeline-lane-range-gesture-layer-a-position'),
    );
    expect(laneGesture, findsOneWidget);

    // Drag on band cells: selects on the LANE domain (layer-a, position).
    final gesture = await tester.startGesture(
      tester.getTopLeft(laneGesture) + const Offset(5 * 48 + 24, 26),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(96, 0));
    await gesture.up();
    await tester.pump();

    expect(selectUpdates, isNotEmpty);
    expect(selectUpdates.last.$1, const LayerId('layer-a'));
    expect(selectUpdates.last.$2, 'position');
    expect(selectUpdates.first.$3, 5, reason: 'anchor = the pressed cell');

    // Selected key markers ring in ACCENT 1 (UI-R23 #4): the LANE
    // selection covering the key at frame 2 flips the marker's border to
    // the thin accent-1 stroke; the wash overlay marks the span.
    Border markerBorder() {
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(
                const ValueKey<String>('timeline-lane-key-layer-a-position-2'),
              ),
              matching: find.byType(Container),
            )
            .first,
      );
      return (container.decoration! as BoxDecoration).border! as Border;
    }

    laneSelection.value = null;
    await tester.pump();
    expect(markerBorder().top.color, isNot(AppColors.accent));
    laneSelection.value = const TimelineLaneSelection(
      layerId: LayerId('layer-a'),
      laneId: 'position',
      startIndex: 0,
      endIndexExclusive: 4,
    );
    await tester.pump();
    expect(markerBorder().top.color, AppColors.accent);
    expect(markerBorder().top.width, moreOrLessEquals(4 / 3));
    // R27 #14: the span BAND no longer lives inside the lane row — it is
    // the cell selection's band, drawn by the cursor overlay. This
    // harness mounts lane bands alone, so only the key ring is visible
    // here; the shared band is pinned in the grid-level test below.
  });

  testWidgets('the gesture layer SURVIVES mid-drag preview rebuilds that '
      'change the row\'s overlay count (UI-R22 #1: the SE row-change '
      'used to commit the move under the pointer)', (tester) async {
    final cursor = ValueNotifier<int>(0);
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(
      const TimelineFrameRangeSelection(
        layerId: LayerId('se-1'),
        startIndex: 0,
        endIndexExclusive: 4,
      ),
    );
    final dragPreview = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(cursor.dispose);
    addTearDown(selection.dispose);
    addTearDown(dragPreview.dispose);
    var ended = 0;
    final se1 = blockLayer('se-1').copyWith(kind: LayerKind.se);
    final se2 = blockLayer('se-2', start: 10).copyWith(kind: LayerKind.se);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            layers: [se1, se2],
            activeLayerId: const LayerId('se-1'),
            frameCursor: cursor,
            playbackFrameCount: 24,
            dragPreview: dragPreview,
            exposureStateForLayer: stateFor,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            rangeHooks: TimelineFrameRangeHooks(
              selection: selection,
              onSelectUpdate:
                  (_, _, _, {headLayerId, headLaneId, spanRows = const []}) {},
              onClear: () {},
              move: TimelineRangeMoveCallbacks(
                onBegin: (_) => true,
                // The session's row-change preview: the SOURCE row loses
                // its blocks — its SE overlays (labels/marks) vanish, so
                // the row's Stack children count CHANGES mid-drag.
                onUpdate: ({required frameDelta, targetLayerId}) {
                  dragPreview.value = BlockMoveDragPreview(
                    previewLayers: {
                      const LayerId('se-1'): se1.copyWith(
                        frames: const [],
                        timeline: const {},
                      ),
                      const LayerId('se-2'): se2,
                    },
                  );
                },
                onEnd: () => ended += 1,
                onCancel: () {},
              ),
            ),
            metrics: const TimelineGridMetrics(
              frameCellWidth: 48,
              layerRowHeight: 52,
            ),
          ),
        ),
      ),
    );

    final gestureLayer = find.byKey(
      const ValueKey<String>('timeline-range-gesture-se-1'),
    );
    // Start a MOVE inside the selection, drag toward the sibling row.
    final gesture = await tester.startGesture(
      tester.getTopLeft(gestureLayer) + const Offset(24 + 48, 26),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 52));
    await tester.pump();
    await tester.pump();
    expect(
      ended,
      0,
      reason: 'the preview rebuild must NOT commit the move mid-drag',
    );

    await gesture.up();
    await tester.pump();
    expect(ended, 1, reason: 'the release commits exactly once');
  });

  testWidgets('a press INSIDE the selection never seeks — sparse rows '
      'follow the painter rule now (UI-R22 #2)', (tester) async {
    final cursor = ValueNotifier<int>(0);
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(
      const TimelineFrameRangeSelection(
        layerId: LayerId('se-1'),
        startIndex: 0,
        endIndexExclusive: 4,
      ),
    );
    addTearDown(cursor.dispose);
    addTearDown(selection.dispose);
    final seeks = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            layers: [blockLayer('se-1').copyWith(kind: LayerKind.se)],
            activeLayerId: const LayerId('se-1'),
            frameCursor: cursor,
            playbackFrameCount: 24,
            exposureStateForLayer: stateFor,
            onSelectLayer: (_) {},
            onSelectFrame: seeks.add,
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            rangeHooks: hooks(selection: selection),
            metrics: const TimelineGridMetrics(
              frameCellWidth: 48,
              layerRowHeight: 52,
            ),
          ),
        ),
      ),
    );

    final gestureLayer = find.byKey(
      const ValueKey<String>('timeline-range-gesture-se-1'),
    );
    // Press INSIDE the selected span (cell 1): no seek.
    var gesture = await tester.startGesture(
      tester.getTopLeft(gestureLayer) + const Offset(24 + 48, 26),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
    await tester.pump();
    expect(seeks, isEmpty, reason: 'inside the selection = a move press');

    // Press OUTSIDE (cell 6): seeks as always.
    gesture = await tester.startGesture(
      tester.getTopLeft(gestureLayer) + const Offset(24 + 6 * 48, 26),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
    await tester.pump();
    expect(seeks, [6]);
  });

  testWidgets('with touch-timeline-scroll ON, a TOUCH press never SEEKS '
      '(UI-R23 feedback #2: the first scroll touch kept moving the '
      'playhead) — painter and sparse rows alike; pen/mouse still seek '
      'and OFF keeps touch-as-pen', (tester) async {
    AppInput.settings.value = const AppInputSettings(touchTimelineScroll: true);
    addTearDown(() {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    });
    final cursor = ValueNotifier<int>(0);
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(null);
    addTearDown(cursor.dispose);
    addTearDown(selection.dispose);
    final seeks = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            layers: [
              blockLayer('anim-1'), // painter row
              blockLayer('se-1').copyWith(kind: LayerKind.se), // sparse row
            ],
            activeLayerId: const LayerId('anim-1'),
            frameCursor: cursor,
            playbackFrameCount: 24,
            exposureStateForLayer: stateFor,
            onSelectLayer: (_) {},
            onSelectFrame: seeks.add,
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            rangeHooks: hooks(selection: selection),
            metrics: const TimelineGridMetrics(
              frameCellWidth: 48,
              layerRowHeight: 52,
            ),
          ),
        ),
      ),
    );

    Offset pressPoint(String layerId) =>
        tester.getTopLeft(
          find.byKey(ValueKey<String>('timeline-range-gesture-$layerId')),
        ) +
        const Offset(24 + 2 * 48, 26);

    Future<void> press(String layerId, {required PointerDeviceKind kind}) {
      return tester
          .startGesture(pressPoint(layerId), kind: kind)
          .then((g) => g.up())
          .then((_) => tester.pump());
    }

    // A touch press that becomes a DRAG never seeks — the scroll owns it
    // (UI-R23 #2: the first scroll touch kept re-seeking).
    Future<void> dragTouch(String layerId) async {
      final gesture = await tester.startGesture(
        pressPoint(layerId),
        kind: PointerDeviceKind.touch,
      );
      for (var step = 0; step < 4; step += 1) {
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
    }

    await dragTouch('anim-1');
    await dragTouch('se-1');
    expect(seeks, isEmpty, reason: 'a scrolling finger must not seek');

    // PEN-12 #6: a clean finger TAP is a click — it seeks (at the UP,
    // once the press provably wasn't a scroll) on both row shapes.
    await press('anim-1', kind: PointerDeviceKind.touch);
    await press('se-1', kind: PointerDeviceKind.touch);
    expect(seeks, [2, 2], reason: 'a finger tap = a click');
    seeks.clear();

    // Pen and mouse keep the instant seek.
    await press('anim-1', kind: PointerDeviceKind.stylus);
    await press('se-1', kind: PointerDeviceKind.mouse);
    expect(seeks, [2, 2]);

    // Toggle OFF (touch-as-pen, R17-⑥): touch seeks at the DOWN again.
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    await press('anim-1', kind: PointerDeviceKind.touch);
    expect(seeks, [2, 2, 2]);
  });

  testWidgets('a cell drag reports anchor/head SELECT updates, never a '
      'move', (tester) async {
    final selectUpdates = <(LayerId, int, int)>[];
    var moveBegan = 0;
    final cursor = ValueNotifier<int>(0);
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(null);
    addTearDown(cursor.dispose);
    addTearDown(selection.dispose);

    await tester.pumpWidget(
      harness(
        layers: [blockLayer('layer-a')],
        cursor: cursor,
        rangeHooks: hooks(
          selection: selection,
          onSelectUpdate: (layerId, anchor, head) =>
              selectUpdates.add((layerId, anchor, head)),
          onMoveBegin: () {
            moveBegan += 1;
            return true;
          },
        ),
      ),
    );

    final gestureLayer = find.byKey(
      const ValueKey<String>('timeline-range-gesture-layer-a'),
    );
    expect(gestureLayer, findsOneWidget);

    // Drag from cell 0 two cells right (48px cells): head lands on 2.
    final start = tester.getTopLeft(gestureLayer) + const Offset(24, 26);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(96, 0));
    await gesture.up();
    await tester.pump();

    expect(selectUpdates.first, (const LayerId('layer-a'), 0, 0));
    expect(selectUpdates.last, (const LayerId('layer-a'), 0, 2));
    expect(moveBegan, 0);
  });

  testWidgets('a drag starting INSIDE the selection moves it: frame steps '
      'and the row under the pointer resolve to the target layer', (
    tester,
  ) async {
    final moveUpdates = <(int, LayerId?)>[];
    var ended = 0;
    final cursor = ValueNotifier<int>(0);
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(
      const TimelineFrameRangeSelection(
        layerId: LayerId('layer-a'),
        startIndex: 0,
        endIndexExclusive: 4,
      ),
    );
    addTearDown(cursor.dispose);
    addTearDown(selection.dispose);

    await tester.pumpWidget(
      harness(
        layers: [blockLayer('layer-a'), blockLayer('layer-b', start: 10)],
        cursor: cursor,
        rangeHooks: hooks(
          selection: selection,
          onMoveUpdate: ({required frameDelta, targetLayerId}) =>
              moveUpdates.add((frameDelta, targetLayerId)),
          onMoveEnd: () => ended += 1,
        ),
      ),
    );

    final gestureLayer = find.byKey(
      const ValueKey<String>('timeline-range-gesture-layer-a'),
    );
    // Press inside the selected span (cell 1), two cells right.
    final start = tester.getTopLeft(gestureLayer) + const Offset(72, 26);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(96, 0));
    await tester.pump();
    expect(moveUpdates.last, (2, const LayerId('layer-a')));

    // One row down: layer B becomes the target.
    await gesture.moveBy(const Offset(0, 52));
    await tester.pump();
    expect(moveUpdates.last, (2, const LayerId('layer-b')));

    await gesture.up();
    await tester.pump();
    expect(ended, 1, reason: 'exactly one commit, on release');
  });

  testWidgets('touch selects like the pen (UI-R17 #6, superseding R12-⑤: '
      'pens report as touch on some drivers)', (tester) async {
    final selectUpdates = <(LayerId, int, int)>[];
    final cursor = ValueNotifier<int>(0);
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(null);
    addTearDown(cursor.dispose);
    addTearDown(selection.dispose);

    await tester.pumpWidget(
      harness(
        layers: [blockLayer('layer-a')],
        cursor: cursor,
        rangeHooks: hooks(
          selection: selection,
          onSelectUpdate: (layerId, anchor, head) =>
              selectUpdates.add((layerId, anchor, head)),
        ),
      ),
    );

    final gestureLayer = find.byKey(
      const ValueKey<String>('timeline-range-gesture-layer-a'),
    );
    final stylus = await tester.startGesture(
      tester.getTopLeft(gestureLayer) + const Offset(24, 26),
      kind: PointerDeviceKind.stylus,
    );
    await stylus.moveBy(const Offset(96, 0));
    await stylus.up();
    await tester.pump();
    expect(selectUpdates, isNotEmpty, reason: 'the pen selects');

    selectUpdates.clear();
    final touch = await tester.startGesture(
      tester.getTopLeft(gestureLayer) + const Offset(24, 26),
    );
    await touch.moveBy(const Offset(96, 0));
    await touch.up();
    await tester.pump();
    expect(
      selectUpdates,
      isNotEmpty,
      reason:
          'touch joins the pan arena — pen-as-touch drivers must work; '
          'grid panning lives on the rulers/scrollbars',
    );
  });

  testWidgets('a plain tap clears the selection AND still selects the cell '
      'underneath', (tester) async {
    final selectedFrames = <int>[];
    var cleared = 0;
    final cursor = ValueNotifier<int>(0);
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(null);
    addTearDown(cursor.dispose);
    addTearDown(selection.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            layers: [blockLayer('layer-a')],
            activeLayerId: const LayerId('layer-a'),
            frameCursor: cursor,
            playbackFrameCount: 24,
            exposureStateForLayer: stateFor,
            onSelectLayer: (_) {},
            onSelectFrame: selectedFrames.add,
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            rangeHooks: hooks(
              selection: selection,
              onClear: () => cleared += 1,
            ),
          ),
        ),
      ),
    );

    await tapTimelineCell(tester, 'layer-a', 1);
    expect(selectedFrames, [1]);
    expect(cleared, 1);
  });

  testWidgets('the X-sheet mounts the same gesture layer transposed '
      '(Axis policy)', (tester) async {
    final selectUpdates = <(LayerId, int, int)>[];
    final moveUpdates = <(int, LayerId?)>[];
    final cursor = ValueNotifier<int>(0);
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(null);
    addTearDown(cursor.dispose);
    addTearDown(selection.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: XSheetTimelineGrid(
            layers: [blockLayer('layer-a'), blockLayer('layer-b', start: 10)],
            activeLayerId: const LayerId('layer-a'),
            frameCursor: cursor,
            frameCount: 24,
            exposureStateForLayer: stateFor,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            rangeHooks: hooks(
              selection: selection,
              onSelectUpdate: (layerId, anchor, head) =>
                  selectUpdates.add((layerId, anchor, head)),
              onMoveUpdate: ({required frameDelta, targetLayerId}) =>
                  moveUpdates.add((frameDelta, targetLayerId)),
            ),
          ),
        ),
      ),
    );

    final gestureLayer = find.byKey(
      const ValueKey<String>('timeline-range-gesture-layer-a'),
    );
    expect(gestureLayer, findsOneWidget);

    // Two frame rows down: head = frame 2. Both distances come from the
    // metrics now — R10 R6 made a frame row the timeline's frame cell
    // (36 → 24) and a column the timeline's row height (164 → 28), and a
    // literal here would keep passing while meaning something else.
    final rowExtent = XSheetTimelineGrid.defaultMetrics.frameCellWidth;
    final columnExtent = XSheetTimelineGrid.defaultMetrics.layerRowHeight;
    final start = tester.getTopLeft(gestureLayer) + const Offset(20, 18);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(Offset(0, rowExtent * 2));
    await gesture.up();
    await tester.pump();
    expect(selectUpdates.last, (const LayerId('layer-a'), 0, 2));

    // With a selection in place, dragging inside it one COLUMN right
    // targets layer B.
    selection.value = const TimelineFrameRangeSelection(
      layerId: LayerId('layer-a'),
      startIndex: 0,
      endIndexExclusive: 4,
    );
    final move = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await move.moveBy(Offset(columnExtent, 0));
    await move.up();
    await tester.pump();
    expect(moveUpdates.last, (0, const LayerId('layer-b')));
  });

  testWidgets('PEN-9: a pen landing MID-COAST cannot select — the glide '
      'ignore-pointers the gesture layer (the tablet bug, pinned)', (
    tester,
  ) async {
    AppInput.settings.value = const AppInputSettings(touchTimelineScroll: true);
    addTearDown(() {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    });
    final cursor = ValueNotifier<int>(0);
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(null);
    addTearDown(cursor.dispose);
    addTearDown(selection.dispose);
    final selectUpdates = <(LayerId, int, int)>[];

    await tester.pumpWidget(
      harness(
        layers: [blockLayer('layer-a')],
        cursor: cursor,
        rangeHooks: hooks(
          selection: selection,
          onSelectUpdate: (layerId, anchor, head) =>
              selectUpdates.add((layerId, anchor, head)),
        ),
      ),
    );

    final gestureLayer = find.byKey(
      const ValueKey<String>('timeline-range-gesture-layer-a'),
    );
    final rowY = tester.getTopLeft(gestureLayer).dy + 26;

    // A touch fling starts the horizontal coast…
    await tester.flingFrom(Offset(500, rowY), const Offset(-250, 0), 1200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    // …and a pen that lands WITHOUT hovering first was never hit-tested
    // against the (ignore-pointered) gesture layer: its drag can only
    // feed the scroll. This is the accepted fallback for hoverless pens
    // (first contact = tap-to-stop); EMR pens are saved by hover below.
    final pen = await tester.startGesture(
      Offset(500, rowY),
      kind: PointerDeviceKind.stylus,
    );
    for (var step = 0; step < 6; step += 1) {
      await pen.moveBy(const Offset(8, 0));
      await tester.pump();
    }
    await pen.up();
    await tester.pumpAndSettle();
    expect(selectUpdates, isEmpty);
  });

  testWidgets('PEN-9: stylus HOVER stops the coast, so the pen SELECTS '
      'right after a touch fling (the Galaxy Tab fix)', (tester) async {
    AppInput.settings.value = const AppInputSettings(touchTimelineScroll: true);
    addTearDown(() {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    });
    final cursor = ValueNotifier<int>(0);
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(null);
    addTearDown(cursor.dispose);
    addTearDown(selection.dispose);
    final selectUpdates = <(LayerId, int, int)>[];

    await tester.pumpWidget(
      harness(
        layers: [blockLayer('layer-a')],
        cursor: cursor,
        rangeHooks: hooks(
          selection: selection,
          onSelectUpdate: (layerId, anchor, head) =>
              selectUpdates.add((layerId, anchor, head)),
        ),
      ),
    );

    final gestureLayer = find.byKey(
      const ValueKey<String>('timeline-range-gesture-layer-a'),
    );
    final rowY = tester.getTopLeft(gestureLayer).dy + 26;

    await tester.flingFrom(Offset(500, rowY), const Offset(-250, 0), 1200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    List<double> scrollOffsets() => tester
        .stateList<ScrollableState>(
          find.byType(Scrollable, skipOffstage: false),
        )
        .map((state) => state.position.pixels)
        .toList();

    // The pen APPROACHES first (EMR pens always hover before contact):
    // the glide stops…
    final hover = await tester.createGesture(
      kind: PointerDeviceKind.stylus,
      pointer: 77,
    );
    await hover.addPointer(location: Offset(500, rowY));
    await hover.moveTo(Offset(501, rowY));
    await tester.pump();
    final stoppedOffsets = scrollOffsets();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      scrollOffsets(),
      stoppedOffsets,
      reason: 'the pen approach must freeze the glide',
    );
    await hover.removePointer();
    await tester.pump();

    // …and the SAME slow creep that just scrolled now range-selects.
    final pen = await tester.startGesture(
      Offset(500, rowY),
      kind: PointerDeviceKind.stylus,
    );
    for (var step = 0; step < 6; step += 1) {
      await pen.moveBy(const Offset(8, 0));
      await tester.pump();
    }
    await pen.up();
    await tester.pumpAndSettle();
    expect(
      selectUpdates,
      isNotEmpty,
      reason: 'after the hover-stop the pen drag must select, not scroll',
    );
    expect(selectUpdates.last.$1, const LayerId('layer-a'));
  });

  testWidgets('PEN-10: with the pen recently seen, a NEW coast keeps cells '
      'hittable — the pen lands with NO hover and still selects', (
    tester,
  ) async {
    AppInput.settings.value = const AppInputSettings(touchTimelineScroll: true);
    addTearDown(() {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    });
    final cursor = ValueNotifier<int>(0);
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(null);
    addTearDown(cursor.dispose);
    addTearDown(selection.dispose);
    final selectUpdates = <(LayerId, int, int)>[];

    await tester.pumpWidget(
      harness(
        layers: [blockLayer('layer-a')],
        cursor: cursor,
        rangeHooks: hooks(
          selection: selection,
          onSelectUpdate: (layerId, anchor, head) =>
              selectUpdates.add((layerId, anchor, head)),
        ),
      ),
    );

    final gestureLayer = find.byKey(
      const ValueKey<String>('timeline-range-gesture-layer-a'),
    );
    final rowY = tester.getTopLeft(gestureLayer).dy + 26;

    // The pen was seen once (a hover pass) BEFORE any scroll existed —
    // the pen-nearby window opens with nothing to stop.
    final hover = await tester.createGesture(
      kind: PointerDeviceKind.stylus,
      pointer: 77,
    );
    await hover.addPointer(location: Offset(500, rowY));
    await hover.moveTo(Offset(501, rowY));
    await tester.pump();
    await hover.removePointer();
    await tester.pump();

    // A touch fling starts a FRESH coast; the pen then lands with no
    // hover move in between (stationary-hover pen). Without PEN-10 this
    // is the stolen case pinned above — pen-nearby keeps the cells
    // hittable through the coast, so the drag selects.
    await tester.flingFrom(Offset(500, rowY), const Offset(-250, 0), 1200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    final pen = await tester.startGesture(
      Offset(500, rowY),
      kind: PointerDeviceKind.stylus,
    );
    for (var step = 0; step < 6; step += 1) {
      await pen.moveBy(const Offset(8, 0));
      await tester.pump();
    }
    await pen.up();
    await tester.pumpAndSettle();
    expect(
      selectUpdates,
      isNotEmpty,
      reason: 'pen-nearby must keep the coast hittable for the landing pen',
    );
    expect(selectUpdates.last.$1, const LayerId('layer-a'));
  });

  testWidgets('PEN-12 #6: with touch-timeline-scroll ON a clean finger TAP '
      'selects the frame; a finger DRAG still only scrolls', (tester) async {
    AppInput.settings.value = const AppInputSettings(touchTimelineScroll: true);
    addTearDown(() {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    });
    final cursor = ValueNotifier<int>(0);
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(null);
    addTearDown(cursor.dispose);
    addTearDown(selection.dispose);
    final selectedFrames = <int>[];

    await tester.pumpWidget(
      harness(
        layers: [blockLayer('layer-a')],
        cursor: cursor,
        rangeHooks: hooks(selection: selection),
        onSelectFrame: selectedFrames.add,
      ),
    );

    final gestureLayer = find.byKey(
      const ValueKey<String>('timeline-range-gesture-layer-a'),
    );
    final rowY = tester.getTopLeft(gestureLayer).dy + 26;

    await tester.tapAt(Offset(500, rowY));
    await tester.pumpAndSettle();
    expect(selectedFrames, hasLength(1), reason: 'a finger tap = a click');

    // A DRAG keeps belonging to the scroll: no further selects.
    final drag = await tester.startGesture(
      Offset(500, rowY),
      kind: PointerDeviceKind.touch,
    );
    for (var step = 0; step < 5; step += 1) {
      await drag.moveBy(const Offset(-24, 0));
      await tester.pump();
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(selectedFrames, hasLength(1), reason: 'a drag never selects');
  });

  group('a key marker is a DRAWING; the band owns every gesture', () {
    /// The grid, with one lane carrying keys at 2 and 5 and whatever lane
    /// selection [selection] holds.
    Future<
      ({
        List<int> moveUpdates,
        List<int> selectUpdates,

        ValueNotifier<TimelineLaneSelection?> selection,
      })
    >
    pumpLane(WidgetTester tester, TimelineLaneSelection? initial) async {
      final cursor = ValueNotifier<int>(0);
      final selection = ValueNotifier<TimelineLaneSelection?>(initial);
      addTearDown(cursor.dispose);
      addTearDown(selection.dispose);
      final moveUpdates = <int>[];
      final selectUpdates = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayerTimelineGrid(
              layers: [blockLayer('layer-a')],
              activeLayerId: const LayerId('layer-a'),
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
              expandedLaneLayerIds: {const LayerId('layer-a')},
              lanesForLayer: (_) => [
                const PropertyLaneRow(
                  laneId: 'position',
                  label: 'Position',
                  keyedFrames: {2, 5},
                ),
              ],
              laneEdit: PropertyLaneEditCallbacks(onToggleKeyAt: (_, _, _) {}),
              laneRange: TimelineLaneRangeCallbacks(
                selection: selection,
                onSelectUpdate: (_, _, anchor, _, _) =>
                    selectUpdates.add(anchor),
                onTapAt: (_, _, _) {},
                onMoveBegin: () => true,
                onMoveUpdate: moveUpdates.add,
                onMoveEnd: () {},
                onMoveCancel: () {},
              ),
              metrics: const TimelineGridMetrics(
                frameCellWidth: 48,
                layerRowHeight: 52,
              ),
            ),
          ),
        ),
      );
      return (
        moveUpdates: moveUpdates,
        selectUpdates: selectUpdates,

        selection: selection,
      );
    }

    Finder keyMarker(int frame) => find.byKey(
      ValueKey<String>('timeline-lane-key-layer-a-position-$frame'),
    );

    testWidgets('pressing a diamond that is IN the span moves the whole '
        'span — the marker stands down', (tester) async {
      final log = await pumpLane(
        tester,
        const TimelineLaneSelection(
          layerId: LayerId('layer-a'),
          laneId: 'position',
          startIndex: 0,
          endIndexExclusive: 8,
        ),
      );

      // The ring proves the marker agrees it is inside the span — the same
      // predicate the stand-down reads.
      final ringed = tester.widget<Container>(
        find
            .descendant(of: keyMarker(2), matching: find.byType(Container))
            .first,
      );
      expect(
        ((ringed.decoration! as BoxDecoration).border! as Border).top.color,
        AppColors.accent,
      );

      final laneGesture = find.byKey(
        const ValueKey<String>('timeline-lane-range-gesture-layer-a-position'),
      );
      expect(laneGesture, findsOneWidget);
      expect(
        tester.getRect(laneGesture).contains(tester.getCenter(keyMarker(2))),
        isTrue,
        reason: 'the band covers the diamond',
      );

      // Grab the diamond at 2, which the span covers, and drag two cells.
      final gesture = await tester.startGesture(
        tester.getCenter(keyMarker(2)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(96, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(
        log.moveUpdates,
        contains(2),
        reason: 'the union moves as one — the diamond is part of it',
      );
      expect(
        log.selectUpdates,
        isEmpty,
        reason: 'and it is a MOVE, not a fresh selection anchored on the key',
      );
    });

    testWidgets('a diamond OUTSIDE the span SELECTS, like any other cell', (
      tester,
    ) async {
      final log = await pumpLane(
        tester,
        // The span covers 2 but not 5.
        const TimelineLaneSelection(
          layerId: LayerId('layer-a'),
          laneId: 'position',
          startIndex: 0,
          endIndexExclusive: 4,
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(keyMarker(5)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(96, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // 2026-08-08: this used to move key 5 to key 7 on the spot. The
      // marker had a drag of its own, so a lane obeyed a different rule
      // than a frame block depending on whether you grabbed a diamond.
      expect(
        log.selectUpdates,
        contains(5),
        reason: 'outside the selection, a drag selects — the block rule',
      );
      expect(
        log.moveUpdates,
        isEmpty,
        reason: 'nothing moves until the thing under the pointer is selected',
      );
    });

    testWidgets('with NO selection at all a diamond drag selects too', (
      tester,
    ) async {
      final log = await pumpLane(tester, null);

      final gesture = await tester.startGesture(
        tester.getCenter(keyMarker(2)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(48, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(log.selectUpdates, contains(2));
      expect(log.moveUpdates, isEmpty);
    });
  });

  group('R10: wherever frame cells exist, the playhead can stand', () {
    testWidgets('tapping a PROPERTY band seeks to that frame — the row that '
        'had visible cells and refused the head', (tester) async {
      final cursor = ValueNotifier<int>(0);
      addTearDown(cursor.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayerTimelineGrid(
              layers: [blockLayer('layer-a')],
              activeLayerId: const LayerId('layer-a'),
              frameCursor: cursor,
              playbackFrameCount: 24,
              exposureStateForLayer: stateFor,
              onSelectLayer: (_) {},
              onSelectFrame: (frame) => cursor.value = frame,
              onAddLayer: () {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
              expandedLaneLayerIds: {const LayerId('layer-a')},
              lanesForLayer: (_) => [
                const PropertyLaneRow(
                  laneId: 'position',
                  label: 'Position',
                  keyedFrames: {2},
                ),
              ],
              laneRange: TimelineLaneRangeCallbacks(
                selection: ValueNotifier<TimelineLaneSelection?>(null),
                onSelectUpdate: (_, _, _, _, _) {},
                // The production host seeks here; this harness stands in
                // for it with the same one line.
                onTapAt: (_, _, frame) => cursor.value = frame,
                onMoveBegin: () => false,
                onMoveUpdate: (_) {},
                onMoveEnd: () {},
                onMoveCancel: () {},
              ),
              metrics: const TimelineGridMetrics(
                frameCellWidth: 48,
                layerRowHeight: 52,
              ),
            ),
          ),
        ),
      );

      final band = find.byKey(
        const ValueKey<String>('timeline-lane-range-gesture-layer-a-position'),
      );
      expect(band, findsOneWidget);

      // Frame 5, clear of the key diamond at 2.
      await tester.tapAt(
        tester.getTopLeft(band) + const Offset(5 * 48 + 24, 26),
      );
      await tester.pumpAndSettle();

      expect(cursor.value, 5);
    });
  });

  group('R10: a lane row follows the drag preview', () {
    /// A layer whose transform track keys Position at [keyFrames].
    Layer keyedLayer(Set<int> keyFrames) => Layer(
      id: const LayerId('layer-a'),
      name: 'A',
      frames: const [],
      transformTrack: TransformTrack(
        keyframes: {
          for (final frame in keyFrames)
            frame: CameraPose(center: CanvasPoint(x: 0, y: 0), zoom: 1),
        },
      ),
    );

    testWidgets('the band re-derives from the PREVIEWED layer, and so does '
        'the value column beside it', (tester) async {
      final cursor = ValueNotifier<int>(2);
      final dragPreview = ValueNotifier<TimelineDragPreview?>(null);
      addTearDown(cursor.dispose);
      addTearDown(dragPreview.dispose);

      final committed = keyedLayer({2});
      // What a lane-move drag stages: the same layer with the key shifted.
      final previewed = committed.copyWith(
        transformTrack: keyedLayer({5}).transformTrack,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayerTimelineGrid(
              layers: [committed],
              activeLayerId: const LayerId('layer-a'),
              frameCursor: cursor,
              playbackFrameCount: 24,
              dragPreview: dragPreview,
              exposureStateForLayer: stateFor,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
              onAddLayer: () {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
              expandedLaneLayerIds: {const LayerId('layer-a')},
              // THE production shape: the lane is derived from the layer,
              // so whichever layer the gate hands over decides the keys.
              lanesForLayer: (layer) => transformPropertyLanes(
                layer.transformTrack,
              ).where((lane) => lane.laneId == 'position').toList(),
              metrics: const TimelineGridMetrics(
                frameCellWidth: 48,
                layerRowHeight: 52,
              ),
            ),
          ),
        ),
      );

      Finder marker(int frame) => find.byKey(
        ValueKey<String>('timeline-lane-key-layer-a-position-$frame'),
      );

      expect(marker(2), findsOneWidget);
      expect(marker(5), findsNothing);

      // One drag step: the session publishes the shifted layer.
      dragPreview.value = BlockMoveDragPreview(
        previewLayers: {const LayerId('layer-a'): previewed},
      );
      await tester.pump();

      expect(
        marker(5),
        findsOneWidget,
        reason:
            'the band read `row.lane` — built once from the COMMITTED '
            'layer — so the keys sat still until the pointer came up',
      );
      expect(marker(2), findsNothing);

      // And the rail's label row, which is where the number is read.
      expect(
        find.byKey(
          const ValueKey<String>('timeline-lane-key-toggle-layer-a-position'),
        ),
        findsOneWidget,
      );

      // Dropping the preview puts the committed lane straight back.
      dragPreview.value = null;
      await tester.pump();
      expect(marker(2), findsOneWidget);
      expect(marker(5), findsNothing);
    });
  });
}
