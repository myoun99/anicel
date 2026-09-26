import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

import '../../helpers/exposure_of.dart';
import 'timeline_cell_probe.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';

/// THE playback-performance invariant: moving the frame cursor (a playback
/// tick, an editing seek) repaints the cursor layer and rulers only — the
/// grids' cell widgets are never rebuilt. Pinned via widget identity: a
/// widget instance only changes when its parent rebuilds it.
void main() {
  // Four one-frame drawings on each row, on the LAYER: a row walks its
  // cells by where its layer's blocks change (I-22).
  Layer row(String id, String name) => Layer(
    id: LayerId(id),
    name: name,
    frames: [Frame(id: const FrameId('cel'), duration: 1, strokes: const [])],
    timeline: {
      for (var frame = 0; frame < 4; frame += 1)
        frame: const TimelineExposure.drawing(FrameId('cel'), length: 1),
    },
  );
  final layers = [row('layer-1', 'A'), row('layer-2', 'B')];

  const stateFor = exposureOf;

  testWidgets('timeline: a cursor tick rebuilds no frame cells and moves '
      'the selection ring', (tester) async {
    final cursor = ValueNotifier<int>(2);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            hooks: TimelineGridHooks(
              activeLayerId: const LayerId('layer-1'),
              frameCursor: cursor,
              playbackFrameCount: 24,
              exposureStateForLayer: stateFor,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
            ),
            layers: layers,
          ),
        ),
      ),
    );

    final rowFinder = find.byKey(
      const ValueKey<String>('timeline-row-cells-layer-1'),
    );
    final rowBefore = tester.widget(rowFinder);
    final ring = find.byKey(const ValueKey<String>('timeline-selected-cell'));
    expect(
      tester.getTopLeft(ring),
      timelineCellGlobalRect(tester, 'layer-1', 2).topLeft,
    );

    // Tick the cursor a few frames, pumping like playback would.
    for (final frame in [3, 4, 5]) {
      cursor.value = frame;
      await tester.pump();
    }

    expect(
      identical(tester.widget(rowFinder), rowBefore),
      isTrue,
      reason: 'cursor ticks must never rebuild cells',
    );
    expect(
      tester.getTopLeft(ring),
      timelineCellGlobalRect(tester, 'layer-1', 5).topLeft,
    );
  });

  testWidgets('X-sheet: a cursor tick rebuilds no frame cells (Axis '
      'policy)', (tester) async {
    final cursor = ValueNotifier<int>(1);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: XSheetTimelineGrid(
            hooks: TimelineGridHooks(
              activeLayerId: const LayerId('layer-1'),
              frameCursor: cursor,
              playbackFrameCount: 24,
              exposureStateForLayer: stateFor,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
            ),
            layers: layers,
          ),
        ),
      ),
    );

    final columnFinder = find.byKey(
      const ValueKey<String>('xsheet-row-cells-layer-1'),
    );
    final columnBefore = tester.widget(columnFinder);

    for (final frame in [2, 3, 4]) {
      cursor.value = frame;
      await tester.pump();
    }

    expect(
      identical(tester.widget(columnFinder), columnBefore),
      isTrue,
      reason: 'cursor ticks must never rebuild cells',
    );
    expect(
      find.byKey(const ValueKey<String>('xsheet-selected-cell')),
      findsOneWidget,
    );
  });
}
