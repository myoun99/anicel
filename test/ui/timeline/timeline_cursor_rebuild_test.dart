import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

import 'timeline_cell_probe.dart';

/// THE playback-performance invariant: moving the frame cursor (a playback
/// tick, an editing seek) repaints the cursor layer and rulers only — the
/// grids' cell widgets are never rebuilt. Pinned via widget identity: a
/// widget instance only changes when its parent rebuilds it.
void main() {
  final layers = [
    Layer(id: const LayerId('layer-1'), name: 'A', frames: const []),
    Layer(id: const LayerId('layer-2'), name: 'B', frames: const []),
  ];

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) =>
      frameIndex < 4
      ? TimelineCellExposureState.drawingStart
      : TimelineCellExposureState.uncovered;

  testWidgets('timeline: a cursor tick rebuilds no frame cells and moves '
      'the selection ring', (tester) async {
    final cursor = ValueNotifier<int>(2);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            layers: layers,
            activeLayerId: const LayerId('layer-1'),
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
            layers: layers,
            activeLayerId: const LayerId('layer-1'),
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
