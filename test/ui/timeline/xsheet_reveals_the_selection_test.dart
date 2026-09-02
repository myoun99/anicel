import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

/// R5 on the sheet: the session's "bring the selection back into view"
/// tick scrolls THIS surface's axes — the frame runs down and the layer
/// columns run across — so the cursor's row and the active layer's column
/// are both on screen after one tick.
///
/// The audit's adversarial check (2026-09-02) found the reveal unmeasured:
/// the sheet's `_revealSelection` made to return early passed every suite
/// that pumps the sheet. This is the measure.
void main() {
  testWidgets('the tick scrolls the frame cursor row into view', (
    tester,
  ) async {
    final tick = ValueNotifier<int>(0);
    addTearDown(tick.dispose);
    const cursor = 150;
    await tester.pumpWidget(
      _sheet(frameCount: 200, cursor: cursor, revealSelectionTick: tick),
    );
    final frames = _controller(tester, 'xsheet-frame-vertical-viewport');
    expect(frames.offset, 0);

    tick.value++;
    await tester.pump();
    await tester.pump();

    const rowTop = cursor * timelineFrameCellWidth;
    expect(frames.offset, greaterThan(0));
    expect(frames.offset, lessThanOrEqualTo(rowTop));
    expect(
      frames.offset + frames.position.viewportDimension,
      greaterThanOrEqualTo(rowTop + timelineFrameCellWidth),
    );
  });

  testWidgets('the tick scrolls the active layer column into view', (
    tester,
  ) async {
    final tick = ValueNotifier<int>(0);
    addTearDown(tick.dispose);
    await tester.pumpWidget(
      _sheet(
        layerCount: 60,
        activeLayerId: const LayerId('layer-60'),
        revealSelectionTick: tick,
      ),
    );
    final columns = _controller(tester, 'xsheet-layer-horizontal-viewport');
    expect(columns.offset, 0);

    tick.value++;
    await tester.pump();
    await tester.pump();

    expect(columns.offset, greaterThan(0));
    expect(columns.offset, lessThanOrEqualTo(columns.position.maxScrollExtent));
  });
}

ScrollController _controller(WidgetTester tester, String key) => tester
    .widget<SingleChildScrollView>(find.byKey(ValueKey<String>(key)))
    .controller!;

Widget _sheet({
  int frameCount = 12,
  int cursor = 0,
  int layerCount = 2,
  LayerId activeLayerId = const LayerId('layer-1'),
  required ValueListenable<int> revealSelectionTick,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 900,
        height: 600,
        child: XSheetTimelineGrid(
          hooks: TimelineGridHooks(
            activeLayerId: activeLayerId,
            frameCursor: ValueNotifier<int>(cursor),
            revealSelectionTick: revealSelectionTick,
            playbackFrameCount: frameCount,
            exposureStateForLayer: (_, _) =>
                TimelineCellExposureState.uncovered,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
          ),
          layers: [
            for (var i = 1; i <= layerCount; i++)
              Layer(
                id: LayerId('layer-$i'),
                name: 'Layer $i',
                frames: [
                  Frame(
                    id: FrameId('frame-$i'),
                    duration: 1,
                    strokes: const [],
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}
