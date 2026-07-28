import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cut_end_handle.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

/// UI-R18 #14: the timeline's red cut-end boundary line grows a drag
/// grip — dragging it end-trims the ACTIVE cut through the session's
/// trim channel, and the LINE follows the live preview.
void main() {
  final layers = [
    Layer(id: const LayerId('layer-1'), name: 'A', frames: const []),
  ];

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) =>
      TimelineCellExposureState.uncovered;

  ({
    TimelineCutEndDragCallbacks callbacks,
    List<int> updates,
    List<int> begins,
    List<int> ends,
  })
  recorder() {
    final updates = <int>[];
    final begins = <int>[];
    final ends = <int>[];
    return (
      callbacks: TimelineCutEndDragCallbacks(
        cutId: const CutId('cut-1'),
        onBegin: () {
          begins.add(1);
          return true;
        },
        onUpdate: updates.add,
        onEnd: () => ends.add(1),
        onCancel: () {},
      ),
      updates: updates,
      begins: begins,
      ends: ends,
    );
  }

  testWidgets('horizontal grid: dragging the end grip reports whole-frame '
      'deltas and the line follows the live trim preview', (tester) async {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    final channel = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(channel.dispose);
    final rec = recorder();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            layers: layers,
            activeLayerId: const LayerId('layer-1'),
            frameCursor: cursor,
            playbackFrameCount: 10,
            exposureStateForLayer: stateFor,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            dragPreview: channel,
            cutEndDrag: rec.callbacks,
          ),
        ),
      ),
    );

    final handle = find.byKey(
      const ValueKey<String>('timeline-cut-end-handle'),
    );
    expect(handle, findsOneWidget);
    final boundary = find.byKey(
      const ValueKey<String>('timeline-cut-end-boundary'),
    );
    final boundaryX = tester.getTopLeft(boundary).dx;

    // The line follows a live trim preview (10 → 12 frames at 24px).
    channel.value = CutTrimDragPreview(
      previewDurations: {const CutId('cut-1'): 12},
    );
    await tester.pump();
    expect(tester.getTopLeft(boundary).dx, boundaryX + 2 * 24);
    channel.value = null;
    await tester.pump();
    expect(tester.getTopLeft(boundary).dx, boundaryX);

    // Dragging the grip end-trims: +48px at 24 px/frame = +2 frames.
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await gesture.moveBy(const Offset(48, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(rec.begins, hasLength(1));
    expect(rec.updates, isNotEmpty);
    expect(rec.updates.last, 2);
    expect(rec.ends, hasLength(1));
  });

  testWidgets('X-sheet grid: the grip rides the VERTICAL frame axis', (
    tester,
  ) async {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    final channel = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(channel.dispose);
    final rec = recorder();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: XSheetTimelineGrid(
            layers: layers,
            activeLayerId: const LayerId('layer-1'),
            frameCursor: cursor,
            frameCount: 10,
            exposureStateForLayer: stateFor,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            dragPreview: channel,
            cutEndDrag: rec.callbacks,
          ),
        ),
      ),
    );

    final cellExtent = tester
        .widget<XSheetTimelineGrid>(find.byType(XSheetTimelineGrid))
        .metrics
        .frameCellWidth;
    final handle = find.byKey(
      const ValueKey<String>('timeline-cut-end-handle'),
    );
    expect(handle, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await gesture.moveBy(Offset(0, cellExtent * 3));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(rec.begins, hasLength(1));
    expect(rec.updates, isNotEmpty);
    expect(rec.updates.last, 3);
    expect(rec.ends, hasLength(1));
  });
}
