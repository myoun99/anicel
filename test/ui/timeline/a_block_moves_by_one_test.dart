import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_range_gesture.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_run_end_handles.dart';

import 'timeline_row_chrome_probe.dart';

/// 🗣️F-238 (유저 2026-09-29): 「블록선택하고 이동, 1코마만 움직일려해도
/// 안되고 2콤마 움직이는만큼 커서 움직여야 2콤마 움직이고, 다시 반대로
/// 1콤마 움직이게 해야하는 번거로움 존재. 1콤마만 바로바로 움직이는게
/// 불가능함.」
///
/// A pen's range drag waited out the 18px hit slop and then spent all of it
/// at once: on cells narrower than 12px its first step was already two. The
/// drag now starts at its FIRST STEP when that comes sooner — a move when
/// the block would leave its seat, a select when the pointer leaves the cell
/// it pressed.
void main() {
  const cell = 8.0;

  Layer blockLayer() => Layer(
    id: const LayerId('layer-a'),
    name: 'layer-a',
    frames: [Frame(id: const FrameId('a-f1'), duration: 1, strokes: const [])],
    timeline: {
      0: const TimelineExposure.drawing(FrameId('a-f1'), length: 4),
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

  TimelineGridHooks gridHooks({
    TimelineFrameRangeHooks? rangeHooks,
    TimelineLaneRangeHooks? laneRange,
  }) {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    return TimelineGridHooks(
      activeLayerId: const LayerId('layer-a'),
      frameCursor: cursor,
      playbackFrameCount: 48,
      exposureStateForLayer: stateFor,
      onSelectLayer: (_) {},
      onSelectFrame: (_) {},
      onToggleLayerVisibility: (_) {},
      onLayerOpacityChanged: (_, _) {},
      onToggleLayerTimesheet: (_) {},
      onLayerMarkSelected: (_, _) {},
      rangeHooks: rangeHooks,
      expandedLaneLayerIds: {if (laneRange != null) const LayerId('layer-a')},
      lanesForLayer: (_) => [
        const PropertyLaneRow(
          laneId: 'position',
          label: 'Position',
          keyedFrames: {1},
        ),
      ],
      laneRange: laneRange,
    );
  }

  Future<void> mount(
    WidgetTester tester,
    TimelineGridHooks hooks, {
    double rowHeight = 52,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LayerTimelineGrid(
          hooks: hooks,
          layers: [blockLayer()],
          metrics: TimelineGridMetrics(
            frameCellWidth: cell,
            layerRowHeight: rowHeight,
          ),
        ),
      ),
    ),
  );

  /// Cells 0..3 selected (the block); returns what the grid told the host
  /// and the middle of cell 1.
  Future<(Heard, Offset)> mountSelected(
    WidgetTester tester, {
    bool moveBegins = true,
    double rowHeight = 52,
  }) async {
    final heard = Heard();
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(
      const TimelineFrameRangeSelection(
        layerId: LayerId('layer-a'),
        startIndex: 0,
        endIndexExclusive: 4,
      ),
    );
    addTearDown(selection.dispose);
    await mount(
      tester,
      gridHooks(
        rangeHooks: TimelineFrameRangeHooks(
          selection: selection,
          onSelectUpdate:
              (
                layerId,
                anchorIndex,
                headIndex, {
                headLayerId,
                headLaneId,
                spanRows = const [],
              }) => heard.selects.add((anchorIndex, headIndex)),
          onClear: () => heard.clears += 1,
          move: TimelineRangeMoveCallbacks(
            onBegin: (_) {
              heard.begins.add(heard.steps.length);
              return moveBegins;
            },
            onUpdate: ({required frameDelta, targetLayerId}) =>
                heard.steps.add(frameDelta),
            onEnd: () => heard.ends += 1,
            onCancel: () {},
          ),
        ),
      ),
      rowHeight: rowHeight,
    );
    final layer = find.byKey(
      const ValueKey<String>('timeline-range-gesture-layer-a'),
    );
    // The middle of cell 1, halfway down the row.
    return (
      heard,
      tester.getTopLeft(layer) + Offset(cell * 1.5, rowHeight / 2),
    );
  }

  /// A hand that travels [pixels] one pixel at a time — the slow, careful
  /// motion a one-frame nudge is.
  Future<void> creep(
    WidgetTester tester,
    TestGesture gesture,
    int pixels,
  ) async {
    for (var moved = 0; moved < pixels.abs(); moved += 1) {
      await gesture.moveBy(Offset(pixels.sign.toDouble(), 0));
      await tester.pump();
    }
  }

  group('cells', () {
    for (final kind in [PointerDeviceKind.stylus, PointerDeviceKind.mouse]) {
      testWidgets('🚨F-238: a ${kind.name} that travels ONE cell moves the '
          'selection one frame — the first step is 1, never 2', (
        tester,
      ) async {
        final (heard, middle) = await mountSelected(tester);

        // Two pixels into cell 1: half a cell on, the block has stepped
        // while the pointer is still on the cell it pressed.
        final gesture = await tester.startGesture(
          middle - const Offset(2, 0),
          kind: kind,
        );
        await creep(tester, gesture, 4);
        expect(heard.steps, [1], reason: 'the block steps at half a cell');

        await creep(tester, gesture, 4);
        expect(
          heard.steps,
          [1],
          reason: '↩️the pen reported nothing until 18px, then 2 at once',
        );
        await gesture.up();
        await tester.pump();
        expect(heard.ends, 1, reason: 'one move, committed on the release');
        expect(heard.clears, 0, reason: 'a move is not a tap');
      });
    }

    testWidgets('F-238: a pen trembling short of the first step is still a '
        'TAP — no move begins, and the selection clears (T10)', (
      tester,
    ) async {
      final (heard, inside) = await mountSelected(tester);

      final gesture = await tester.startGesture(
        inside,
        kind: PointerDeviceKind.stylus,
      );
      // Less than half a cell: the block would not leave its seat.
      await creep(tester, gesture, 3);
      await creep(tester, gesture, -2);
      await gesture.up();
      await tester.pump();

      expect(heard.begins, isEmpty, reason: 'nothing was carried');
      expect(heard.steps, isEmpty);
      expect(heard.clears, 1, reason: 'T10 「클릭하고 떼면 뭐든 비우게」');
    });

    testWidgets('F-238: a move the host refuses becomes a SELECT from the '
        'press, at the same first step', (tester) async {
      final (heard, inside) = await mountSelected(tester, moveBegins: false);

      final gesture = await tester.startGesture(
        inside,
        kind: PointerDeviceKind.stylus,
      );
      await creep(tester, gesture, cell.toInt());
      await gesture.up();
      await tester.pump();

      expect(heard.begins, [0], reason: 'asked once');
      expect(heard.steps, isEmpty);
      expect(heard.selects.last, (1, 2), reason: 'anchored where it pressed');
    });

    testWidgets('🚨F-238: a pen SELECT starts where it leaves the pressed '
        'cell — two cells, not three, and not before', (tester) async {
      final (heard, inside) = await mountSelected(tester);

      // Two pixels into cell 6, outside the selection.
      final gesture = await tester.startGesture(
        inside + const Offset(cell * 5 - 2, 0),
        kind: PointerDeviceKind.stylus,
      );
      await creep(tester, gesture, 5);
      expect(heard.selects, isEmpty, reason: 'still on the pressed cell');

      await creep(tester, gesture, 3);
      await gesture.up();
      await tester.pump();
      expect(
        heard.selects.toSet(),
        {(6, 6), (6, 7)},
        reason: '↩️nothing until 18px, and then the head was already 8',
      );
    });

    testWidgets('F-238: a pen select that leaves the pressed ROW starts '
        'there too — the cell is a box, not a column', (tester) async {
      final (heard, inside) = await mountSelected(tester, rowHeight: 28);

      final gesture = await tester.startGesture(
        inside + const Offset(cell * 5, 0),
        kind: PointerDeviceKind.stylus,
      );
      // Fifteen pixels up: out of a 28px row, short of the 18px slop.
      for (var moved = 0; moved < 15; moved += 1) {
        await gesture.moveBy(const Offset(0, -1));
        await tester.pump();
      }

      expect(heard.selects, isNotEmpty, reason: 'the select has begun');
      await gesture.up();
      await tester.pump();
    });
  });

  group('lane band', () {
    Future<(Heard, Offset)> mountBand(
      WidgetTester tester, {
      TimelineLaneSelection? selected,
      double rowHeight = 52,
    }) async {
      final heard = Heard();
      final laneSelection = ValueNotifier<TimelineLaneSelection?>(selected);
      addTearDown(laneSelection.dispose);
      await mount(
        tester,
        gridHooks(
          laneRange: TimelineLaneRangeHooks(
            selection: laneSelection,
            onSelectUpdate: (_, _, anchor, head, _, _) =>
                heard.selects.add((anchor, head)),
            onTapAt: (_, _, _) {},
            onTapClear: () => heard.clears += 1,
            onMoveBegin: () {
              heard.begins.add(heard.steps.length);
              return true;
            },
            onMoveUpdate: heard.steps.add,
            onMoveEnd: () => heard.ends += 1,
            onMoveCancel: () {},
          ),
        ),
        rowHeight: rowHeight,
      );
      final band = find.byKey(
        const ValueKey<String>('timeline-lane-range-gesture-layer-a-position'),
      );
      return (heard, tester.getTopLeft(band) + const Offset(cell * 1.5, 12));
    }

    testWidgets('🚨F-238: a pen that travels one cell inside the lane '
        'selection moves its keys one frame', (tester) async {
      final (heard, inside) = await mountBand(
        tester,
        selected: const TimelineLaneSelection(
          layerId: LayerId('layer-a'),
          laneId: 'position',
          startIndex: 0,
          endIndexExclusive: 4,
        ),
      );

      // Two pixels into cell 1, as the cells' pin presses.
      final gesture = await tester.startGesture(
        inside - const Offset(2, 0),
        kind: PointerDeviceKind.stylus,
      );
      await creep(tester, gesture, 4);
      expect(heard.steps, [1], reason: 'the keys step at half a cell');

      await creep(tester, gesture, 4);
      await gesture.up();
      await tester.pump();
      expect(heard.steps, [1]);
      expect(heard.ends, 1);
    });

    testWidgets('F-238: a pen select on the band that leaves its ROW starts '
        'there', (tester) async {
      final (heard, _) = await mountBand(tester, rowHeight: 28);
      final band = find.byKey(
        const ValueKey<String>('timeline-lane-range-gesture-layer-a-position'),
      );
      final height = tester.getSize(band).height;
      expect(height, lessThan(36), reason: '⛔전제: the row is left before 18px');

      final gesture = await tester.startGesture(
        tester.getTopLeft(band) + Offset(cell * 1.5, height / 2),
        kind: PointerDeviceKind.stylus,
      );
      for (var moved = 0; moved < height / 2 + 1; moved += 1) {
        await gesture.moveBy(const Offset(0, -1));
        await tester.pump();
      }

      expect(heard.selects, isNotEmpty, reason: 'the select has begun');
      await gesture.up();
      await tester.pump();
    });

    testWidgets('🚨F-238: a pen select on the band starts where it leaves '
        'the pressed cell', (tester) async {
      final (heard, middle) = await mountBand(tester);

      // Two pixels into cell 1.
      final gesture = await tester.startGesture(
        middle - const Offset(2, 0),
        kind: PointerDeviceKind.stylus,
      );
      await creep(tester, gesture, 5);
      expect(heard.selects, isEmpty, reason: 'still on the pressed cell');

      await creep(tester, gesture, 3);
      await gesture.up();
      await tester.pump();
      expect(heard.selects.toSet(), {(1, 1), (1, 2)});
    });
  });

  testWidgets('🚨F-238: a pen that drags the run\'s end [+] one cell adds '
      'one cel — the count starts at 1, not 2', (tester) async {
    final counts = <int>[];
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            hooks: TimelineGridHooks(
              activeLayerId: const LayerId('layer-a'),
              frameCursor: cursor,
              playbackFrameCount: 48,
              exposureStateForLayer: stateFor,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
              runEdit: TimelineRunEditCallbacks(
                onAddBegin: (_, _, {required atEnd}) => true,
                onAddUpdate: counts.add,
                onAddEnd: () {},
                onAddCancel: () {},
                onEdgeModeSelected:
                    (_, _, _, _, {scopeToSelection = false}) {},
              ),
            ),
            layers: [
              blockLayer().copyWith(
                timeline: {
                  0: const TimelineExposure.drawing(FrameId('a-f1'), length: 8),
                },
              ),
            ],
            metrics: const TimelineGridMetrics(
              frameCellWidth: cell,
              layerRowHeight: 52,
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      timelineRowChromeCenter(tester, 'layer-a', 'run-add-end-layer-a-0'),
      kind: PointerDeviceKind.stylus,
    );
    await creep(tester, gesture, cell.toInt());

    expect(
      counts.where((count) => count != 0),
      everyElement(1),
      reason: '↩️nothing until 18px, and then two at once',
    );
    expect(counts, contains(1), reason: 'the drag has begun — not a tap yet');
    await gesture.up();
    await tester.pump();
  });
}

/// What the grid told the host, in order. [begins] records how many steps
/// had been reported when each move began.
final class Heard {
  final begins = <int>[];
  final steps = <int>[];
  final selects = <(int, int)>[];
  int ends = 0;
  int clears = 0;
}
