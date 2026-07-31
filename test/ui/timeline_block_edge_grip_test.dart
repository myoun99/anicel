import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

import 'timeline/timeline_frame_geometry_probe.dart';
import 'timeline/timeline_row_chrome_probe.dart';

/// TVPaint-style comma grips: every drawing block shows inset bars inside
/// BOTH edges, in both orientations; dragging reports cumulative frame
/// deltas.
///
/// The dense rows PAINT their grips (R28 #4 tier 2), so the assertions read
/// the row's target model and the drags start from those rects — the same
/// geometry the row hit-tests with.
void main() {
  group('comma drag pixel policy', () {
    test('R10: the frame axis follows the boundary NEAREST the pointer, '
        'symmetric in both directions', () {
      // R9 #10 truncated here, reading "the edge leapt out from under the
      // hand" as a rounding fault. The fault was the two grip mounts still
      // discarding their slop (DragStartBehavior.start), which parked the
      // edge ~18px behind the pointer for the whole gesture; truncation on
      // top of that offset put the step 42px out one way and 6px the
      // other. With the slop kept, rounding IS "nearest the cursor".
      expect(commaDragFrameDelta(accumulatedDelta: 20, frameCellExtent: 48), 0);
      expect(commaDragFrameDelta(accumulatedDelta: 25, frameCellExtent: 48), 1);
      expect(commaDragFrameDelta(accumulatedDelta: 47, frameCellExtent: 48), 1);
      expect(commaDragFrameDelta(accumulatedDelta: 48, frameCellExtent: 48), 1);
      expect(
        commaDragFrameDelta(accumulatedDelta: 100, frameCellExtent: 48),
        2,
      );
      expect(
        commaDragFrameDelta(accumulatedDelta: -25, frameCellExtent: 48),
        -1,
      );
      expect(
        commaDragFrameDelta(accumulatedDelta: -48, frameCellExtent: 48),
        -1,
      );
    });

    test('R10: ONE rule — an edge, a move and the run [+] all read the same '
        'function', () {
      // R9 #10 forked a second policy (timelineMoveFrameDelta) so the two
      // could not drift back together by accident. They came back together
      // by DECISION, so the fork is gone rather than sitting there as two
      // identical bodies waiting for someone to edit one of them.
      expect(commaDragFrameDelta(accumulatedDelta: 25, frameCellExtent: 48), 1);
      expect(
        commaDragFrameDelta(accumulatedDelta: -25, frameCellExtent: 48),
        -1,
      );
    });
  });

  group('horizontal row grips', () {
    testWidgets('every block gets a start and an end grip', (tester) async {
      await tester.pumpWidget(_rowHarness(layer: _twoBlockLayer()));

      expect(timelineRowChromeIds(tester, 'layer-a'), [
        _gripId('start', 0),
        _gripId('end', 0),
        _gripId('start', 1),
        _gripId('end', 1),
      ]);
    });

    testWidgets('grips sit inside the block edges', (tester) async {
      await tester.pumpWidget(_rowHarness(layer: _twoBlockLayer()));

      // Block [0,2) at 48px cells: start hit strip begins at the block's
      // left edge, end strip ends at its right edge (x = 96).
      expect(_gripRect(tester, 'start', 0).left, 0);
      expect(_gripRect(tester, 'end', 0).right, 96);
    });

    testWidgets('R9 #12: a dense row\'s grip reads engaged from the pointer '
        'DOWN and lets go on the pointer UP', (tester) async {
      await tester.pumpWidget(_rowHarness(layer: _twoBlockLayer()));

      String? engagedGrip() =>
          timelineRowChromePainter(tester, 'layer-a')?.draggingGripId;

      expect(engagedGrip(), isNull);

      // Press and HOLD, no movement: the drag recognizer has not won —
      // which is exactly the state the user reported as "nothing looks
      // grabbed".
      final gesture = await tester.startGesture(
        _gripRect(tester, 'end', 0).center,
      );
      await tester.pump();
      expect(engagedGrip(), _gripId('end', 0));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(engagedGrip(), isNull, reason: 'the release path #12 lacked');
    });

    testWidgets('camera layers show no grips', (tester) async {
      await tester.pumpWidget(
        _rowHarness(layer: _twoBlockLayer(kind: LayerKind.camera)),
      );

      expect(timelineRowChromeIds(tester, 'layer-a'), isEmpty);
    });

    testWidgets('SYNCED attach rows show no grips even though their '
        'mirror blocks paint as real blocks (the synced-block UI: timing '
        'belongs to the owner)', (tester) async {
      await tester.pumpWidget(
        _rowHarness(
          layer: _twoBlockLayer().copyWith(
            attachedToLayerId: const LayerId('base'),
          ),
        ),
      );

      expect(timelineRowChromeIds(tester, 'layer-a'), isEmpty);
    });

    testWidgets('no grips without commaDrag callbacks', (tester) async {
      await tester.pumpWidget(
        _rowHarness(layer: _twoBlockLayer(), commaDrag: null),
      );

      expect(timelineRowChromeIds(tester, 'layer-a'), isEmpty);
    });

    testWidgets('dragging the end grip reports cumulative frame deltas', (
      tester,
    ) async {
      final log = _DragLog();
      await tester.pumpWidget(
        _rowHarness(layer: _twoBlockLayer(), commaDrag: log.callbacks),
      );

      final gesture = await tester.startGesture(
        _gripRect(tester, 'end', 0).center,
      );
      await gesture.moveBy(const Offset(19, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(48, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(48, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-96, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(log.begins, [
        (const LayerId('layer-a'), 0, TimelineBlockEdge.end),
      ]);
      expect(log.updates, [1, 2, 0]);
      expect(log.ends, 1);
      expect(log.cancels, 0);
    });

    testWidgets('dragging the start grip reports the start edge', (
      tester,
    ) async {
      final log = _DragLog();
      await tester.pumpWidget(
        _rowHarness(layer: _twoBlockLayer(), commaDrag: log.callbacks),
      );

      final gesture = await tester.startGesture(
        _gripRect(tester, 'start', 1).center,
      );
      await gesture.moveBy(const Offset(-19, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-48, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(log.begins, [
        (const LayerId('layer-a'), 4, TimelineBlockEdge.start),
      ]);
      expect(log.updates, [-1]);
      expect(log.ends, 1);
    });

    testWidgets('a rejected begin reports nothing further', (tester) async {
      final log = _DragLog(acceptBegin: false);
      await tester.pumpWidget(
        _rowHarness(layer: _twoBlockLayer(), commaDrag: log.callbacks),
      );

      final gesture = await tester.startGesture(
        _gripRect(tester, 'end', 0).center,
      );
      await gesture.moveBy(const Offset(67, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(log.begins.length, 1);
      expect(log.updates, isEmpty);
      expect(log.ends, 0);
    });
  });

  group('X-sheet grips', () {
    testWidgets('grips render and drag along the vertical frame axis', (
      tester,
    ) async {
      final log = _DragLog();
      await tester.pumpWidget(
        _xsheetHarness(layer: _twoBlockLayer(), commaDrag: log.callbacks),
      );

      final ids = timelineRowChromeIds(tester, 'layer-a', prefix: 'xsheet');
      expect(ids, contains(_gripId('start', 0)));
      expect(ids, contains(_gripId('end', 1)));

      final gesture = await tester.startGesture(
        timelineRowChromeCenter(
          tester,
          'layer-a',
          _gripId('end', 0),
          prefix: 'xsheet',
        ),
      );
      // X-sheet frame rows are 36px tall. R10: the 19px that wins the
      // arena is TRAVEL, not overhead — it is past the row's midpoint, so
      // the edge has already stepped by the time the drag is recognised.
      // Under DragStartBehavior.start those pixels were thrown away and
      // the edge spent the rest of the gesture 19px behind the finger.
      await gesture.moveBy(const Offset(0, 19));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 36));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(log.begins, [
        (const LayerId('layer-a'), 0, TimelineBlockEdge.end),
      ]);
      expect(log.updates, [1, 2]);
      expect(log.ends, 1);
    });
  });

  group('R10: the slop is travel, not overhead', () {
    testWidgets('a drag that only just wins the arena has already moved the '
        'edge — the pixels spent on the slop are not discarded', (
      tester,
    ) async {
      final log = _DragLog();
      await tester.pumpWidget(
        _rowHarness(layer: _twoBlockLayer(), commaDrag: log.callbacks),
      );

      // 48px cells: one move of 30px is over the touch slop (18) AND over
      // the half cell, so the edge owes a step immediately. Under
      // DragStartBehavior.start the recognizer kept only 30 - 18 = 12px
      // and reported nothing — the edge sat still while the finger was
      // already most of a cell away, which is what the user described as
      // the edge staying out of register for the whole gesture.
      final gesture = await tester.startGesture(
        _gripRect(tester, 'end', 0).center,
      );
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();

      expect(log.updates, [1]);

      // And it comes home: back to the down position is back to zero, with
      // no residue left over from the arena.
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(log.updates, [1, 0]);
      expect(log.ends, 1);
    });
  });
}

String _gripId(String edge, int ordinal) =>
    'block-edge-grip-$edge-layer-a-$ordinal';

Rect _gripRect(WidgetTester tester, String edge, int ordinal) =>
    timelineRowChromeGlobalRect(tester, 'layer-a', _gripId(edge, ordinal));

class _DragLog {
  _DragLog({this.acceptBegin = true});

  final bool acceptBegin;
  final begins = <(LayerId, int, TimelineBlockEdge)>[];
  final updates = <int>[];
  var ends = 0;
  var cancels = 0;

  late final callbacks = TimelineCommaDragCallbacks(
    onBegin: (layerId, blockStartIndex, edge) {
      begins.add((layerId, blockStartIndex, edge));
      return acceptBegin;
    },
    onUpdate: updates.add,
    onEnd: () => ends += 1,
    onCancel: () => cancels += 1,
  );
}

/// Blocks [0,2) and [4,6) with an X gap between.
Layer _twoBlockLayer({LayerKind kind = LayerKind.animation}) {
  return Layer(
    id: const LayerId('layer-a'),
    name: 'A',
    kind: kind,
    frames: [
      Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
      Frame(id: const FrameId('f2'), duration: 1, strokes: const []),
    ],
    timeline: {
      0: TimelineExposure.drawing(const FrameId('f1'), length: 2),
      4: TimelineExposure.drawing(const FrameId('f2'), length: 2),
    },
  );
}

TimelineCellExposureState _stateFor(Layer layer, int frameIndex) {
  if (layer.timeline[frameIndex]?.isDrawing ?? false) {
    return TimelineCellExposureState.drawingStart;
  }
  if (coveringDrawingBlockAt(layer.timeline, frameIndex) != null) {
    return TimelineCellExposureState.held;
  }
  return TimelineCellExposureState.uncovered;
}

final _defaultCallbacks = TimelineCommaDragCallbacks(
  onBegin: (_, _, _) => true,
  onUpdate: (_) {},
  onEnd: () {},
  onCancel: () {},
);

Widget _rowHarness({required Layer layer, Object? commaDrag = const _Unset()}) {
  return MaterialApp(
    home: Scaffold(
      body: Material(
        child: TimelineFrameCellsRow(
          layer: layer,
          active: true,
          playbackFrameCount: 24,
          // Classic geometry: the drag distances below assume 48px cells.
          geometry: testFrameGeometry(
            frameCellExtent: 48,
            frameEndIndexExclusive: 8,
          ),
          crossAxisExtent: 52,
          exposureStateForLayer: _stateFor,
          onSelectLayer: (_) {},
          onSelectFrame: (_) {},
          commaDrag: commaDrag is _Unset
              ? _defaultCallbacks
              : commaDrag as TimelineCommaDragCallbacks?,
        ),
      ),
    ),
  );
}

Widget _xsheetHarness({
  required Layer layer,
  required TimelineCommaDragCallbacks commaDrag,
}) {
  return MaterialApp(
    home: Scaffold(
      body: XSheetTimelineGrid(
        layers: [layer],
        activeLayerId: layer.id,
        frameCursor: ValueNotifier<int>(0),
        frameCount: 24,
        exposureStateForLayer: _stateFor,
        onSelectLayer: (_) {},
        onSelectFrame: (_) {},
        onAddLayer: () {},
        onToggleLayerVisibility: (_) {},
        onLayerOpacityChanged: (_, _) {},
        onToggleLayerTimesheet: (_) {},
        onLayerMarkSelected: (_, _) {},
        commaDrag: commaDrag,
      ),
    ),
  );
}

class _Unset {
  const _Unset();
}
