import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/session/folder_bands.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_range_gesture.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

/// F-311 (유저 2026-10-06): 「폴더의 블록 드래그로 이동할 수 있게」 — the
/// grid's half. A folder's row is a cells row like any other, so a press on
/// its selected block asks the host to move with the FOLDER's own id; what
/// that carries is the session's half
/// (`session/a_folder_block_is_what_its_rows_hold_test.dart`).
void main() {
  const cell = 16.0;
  const rowHeight = 40.0;
  const folderId = LayerId('f');

  final member = Layer(
    id: const LayerId('a'),
    name: 'a',
    folderId: folderId,
    frames: [Frame(id: const FrameId('a0'), duration: 1, strokes: const [])],
    timeline: {0: const TimelineExposure.drawing(FrameId('a0'), length: 4)},
  );
  // The row as the grids are handed it: the folder carrying its band.
  final band = folderBandOf(createFolderLayer(id: folderId, name: 'F'), [
    member,
  ]);

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) =>
      coveringDrawingBlockAt(layer.timeline, frameIndex) == null
      ? TimelineCellExposureState.uncovered
      : TimelineCellExposureState.held;

  testWidgets('a pen that drags the folder row\'s selected block begins a '
      'move by the folder row, and steps it a frame a cell', (tester) async {
    final begins = <LayerId>[];
    final steps = <int>[];
    var ends = 0;
    final selection = ValueNotifier<TimelineFrameRangeSelection?>(
      const TimelineFrameRangeSelection(
        layerId: folderId,
        startIndex: 0,
        endIndexExclusive: 4,
      ),
    );
    addTearDown(selection.dispose);
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            hooks: TimelineGridHooks(
              activeLayerId: member.id,
              frameCursor: cursor,
              playbackFrameCount: 48,
              exposureStateForLayer: stateFor,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
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
                    }) => fail('a press inside the selection is a move'),
                onClear: () {},
                move: TimelineRangeMoveCallbacks(
                  onBegin: (grabbed) {
                    begins.add(grabbed);
                    return true;
                  },
                  onUpdate: ({required frameDelta, targetLayerId}) =>
                      steps.add(frameDelta),
                  onEnd: () => ends += 1,
                  onCancel: () {},
                ),
              ),
            ),
            layers: [band, member],
            metrics: const TimelineGridMetrics(
              frameCellWidth: cell,
              layerRowHeight: rowHeight,
            ),
          ),
        ),
      ),
    );
    final row = find.byKey(const ValueKey<String>('timeline-range-gesture-f'));
    expect(row, findsOneWidget, reason: 'the folder\'s row takes the drag');

    final gesture = await tester.startGesture(
      tester.getTopLeft(row) + const Offset(cell * 1.5, rowHeight / 2),
      kind: PointerDeviceKind.stylus,
    );
    for (var moved = 0; moved < cell; moved += 1) {
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(begins, [folderId]);
    expect(steps, [1]);
    expect(ends, 1);
  });
}
