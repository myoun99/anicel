
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/key_mark.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cells_row_facts.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

/// lane-rows-built-twice — ONE builder lays a lane row for both grids
/// ([timelineLaneRowFrom]), and each grid's way of laying it rides in: the
/// timeline's along its row, the x-sheet's down its column, under each
/// grid's own keys.
void main() {
  const frames = 16;
  final drawing = Layer(
    id: const LayerId('a'),
    name: 'A',
    frames: const [],
    timeline: const {},
  );
  const position = PropertyLaneRow(
    laneId: 'position',
    label: 'Position',
    keyMarks: {5: KeyMark.linear},
  );

  /// The box [key] is laid in when [row] is built at [layer] by a grid that
  /// lays its rows along [axis] under [keyPrefix].
  Future<Rect> laid(
    WidgetTester tester,
    TimelineDisplayRow row,
    Layer layer, {
    required Axis axis,
    required String keyPrefix,
    required String key,
    Map<LayerId, int> spillInLeadFrames = const {},
  }) async {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    final geometry = ValueNotifier(
      const TimelineFrameGeometry(
        viewExtentPx: 400.0,
        frameCellExtent: 24,
        frameStartIndex: 0,
        frameEndIndexExclusive: frames,
      ),
    );
    addTearDown(geometry.dispose);
    final grid = (
      hooks: TimelineGridHooks(
        activeLayerId: null,
        frameCursor: cursor,
        playbackFrameCount: frames,
        exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
        onSelectLayer: (_) {},
        onSelectFrame: (_) {},
        onToggleLayerVisibility: (_) {},
        onLayerOpacityChanged: (_, _) {},
        onToggleLayerTimesheet: (_) {},
        onLayerMarkSelected: (_, _) {},
        projectFrameRate: ProjectFrameRate.fps24,
        audioPeaksFor: (_) => null,
        spillInLeadFrames: spillInLeadFrames,
      ),
      metrics: TimelineGridMetrics.defaults,
      geometry: geometry,
      windowBucket: null,
      frameAxisController: null,
      nextPage: null,
      rangeGesture: null,
      axis: axis,
      keyPrefix: keyPrefix,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: timelineLaneRowFrom(row, layer, grid, (
              startIndex: 0,
              endIndexExclusive: frames,
              leadingSpacer: 0,
              trailingSpacer: 0,
              laneRange: null,
            )),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getRect(find.byKey(ValueKey<String>('$keyPrefix-$key')));
  }

  testWidgets('a property lane runs its frames along the timeline\'s row and '
      'down the x-sheet\'s column', (tester) async {
    final row = TimelineDisplayRow.lane(drawing, position, layerIndex: 0);
    const key = 'lane-key-a-position-5';
    final along = await laid(
      tester,
      row,
      drawing,
      axis: Axis.horizontal,
      keyPrefix: 'timeline',
      key: key,
    );
    final down = await laid(
      tester,
      row,
      drawing,
      axis: Axis.vertical,
      keyPrefix: 'xsheet',
      key: key,
    );
    const cell = TimelineGridMetrics.defaults;
    expect(
      along.center.dx,
      inExclusiveRange(5 * cell.frameCellWidth, 6 * cell.frameCellWidth),
      reason: 'frame 5\'s key stands in the sixth cell of the frames given',
    );
    expect(
      down.center,
      Offset(along.center.dy, along.center.dx),
      reason: 'turned on its side',
    );
  });
}
