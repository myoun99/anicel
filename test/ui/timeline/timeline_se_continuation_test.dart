import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_row_edit_chrome.dart';

import 'timeline_frame_geometry_probe.dart';
import 'timeline_row_chrome_probe.dart';

/// UI-R7 #6: the cut-scoped timeline announces an SE sound's other half
/// with `~` continuation marks — at the cut end when the block runs past
/// it, at the cut start when it spills in from the previous cut (whose
/// start grip stands down; the real start lives in that cut).
void main() {
  Layer seLayer(Map<int, TimelineExposure> timeline) => Layer(
    id: const LayerId('se-1'),
    name: 'S1',
    kind: LayerKind.se,
    frames: const [],
    timeline: timeline,
  );

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) =>
      TimelineCellExposureState.uncovered;

  Widget harness({
    required Layer layer,
    bool seSpillsIn = false,
    TimelineCommaDragCallbacks? commaDrag,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Material(
          child: TimelineFrameCellsRow(
            layer: layer,
            active: true,
            // The cut is 6 frames long; the row shows a few runway frames.
            playbackFrameCount: 6,
            geometry: testFrameGeometry(
              frameCellExtent: 48,
              frameEndIndexExclusive: 10,
            ),
            crossAxisExtent: 52,
            exposureStateForLayer: stateFor,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            commaDrag: commaDrag,
            seSpillsIn: seSpillsIn,
          ),
        ),
      ),
    );
  }

  testWidgets('a block running past the cut end marks the cut end with ~', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        layer: seLayer({
          2: const TimelineExposure.drawing(FrameId('f1'), length: 6),
        }),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('timeline-se-crossing-se-1-end')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-se-crossing-se-1-start')),
      findsNothing,
    );
  });

  testWidgets('a block INSIDE the cut carries no marks', (tester) async {
    await tester.pumpWidget(
      harness(
        layer: seLayer({
          1: const TimelineExposure.drawing(FrameId('f1'), length: 3),
        }),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('timeline-se-crossing-se-1-end')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-se-crossing-se-1-start')),
      findsNothing,
    );
  });

  testWidgets('a spill-in block marks the cut start with ~ and its start '
      'grip stands down (the end grip stays)', (tester) async {
    final commaDrag = TimelineCommaDragCallbacks(
      onBegin: (_, _, _) => true,
      onUpdate: (_) {},
      onEnd: () {},
      onCancel: () {},
    );
    await tester.pumpWidget(
      harness(
        layer: seLayer({
          0: const TimelineExposure.drawing(FrameId('f0'), length: 3),
        }),
        seSpillsIn: true,
        commaDrag: commaDrag,
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('timeline-se-crossing-se-1-start')),
      findsOneWidget,
    );
    final targets = timelineRowChromeTargets(tester, 'se-1');
    expect(
      targets,
      hasLength(1),
      reason: 'only the END grip: the ~ replaces the start edge',
    );
    expect((targets.single as TimelineRowGripTarget).edge, TimelineBlockEdge.end);

    // Without the spill flag the same geometry keeps BOTH grips.
    await tester.pumpWidget(
      harness(
        layer: seLayer({
          0: const TimelineExposure.drawing(FrameId('f0'), length: 3),
        }),
        commaDrag: commaDrag,
      ),
    );
    expect(timelineRowChromeTargets(tester, 'se-1'), hasLength(2));
    expect(
      find.byKey(const ValueKey<String>('timeline-se-crossing-se-1-start')),
      findsNothing,
    );
  });
}
