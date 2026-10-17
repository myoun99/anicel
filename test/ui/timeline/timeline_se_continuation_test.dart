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
    int? spillInLeadFrames,
    TimelineCommaDragCallbacks? commaDrag,
    int drawnFrameCount = 6,
    Axis axis = Axis.horizontal,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Material(
          child: TimelineFrameCellsRow(
            axis: axis,
            layer: layer,
            // The cut is drawn for 6 frames; the row shows a few runway
            // frames.
            drawnFrameCount: drawnFrameCount,
            geometry: testFrameGeometry(
              frameCellExtent: 48,
              frameEndIndexExclusive: 10,
            ),
            crossAxisExtent: 52,
            exposureStateForLayer: stateFor,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            commaDrag: commaDrag,
            spillInLeadFrames: spillInLeadFrames,
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
        spillInLeadFrames: 2,
        commaDrag: commaDrag,
      ),
    );

    final start = find.byKey(
      const ValueKey<String>('timeline-se-crossing-se-1-start'),
    );
    expect(start, findsOneWidget);
    expect(
      tester.getCenter(start).dx -
          tester.getTopLeft(find.byType(TimelineFrameCellsRow)).dx,
      0,
      reason: 'it straddles the cut start',
    );
    final targets = timelineRowChromeTargets(tester, 'se-1');
    expect(
      targets,
      hasLength(1),
      reason: 'only the END grip: the ~ replaces the start edge',
    );
    expect((targets.single as TimelineRowGripTarget).edge, TimelineBlockEdge.end);

    // Without a spill-in the same geometry keeps BOTH grips.
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

  // 🗣️F-358 (유저 2026-10-17): 「컷 엔드라인(OL여백이든 뭐든 총합적인
  // 엔드라인)」 — the 尺 plus the のりしろ, the timeline's blue line.
  testWidgets('🚨F-358: the end ~ stands on the line the cut is DRAWN to, '
      'and a sound ending short of it carries none', (tester) async {
    final end = find.byKey(
      const ValueKey<String>('timeline-se-crossing-se-1-end'),
    );
    await tester.pumpWidget(
      harness(
        layer: seLayer({
          2: const TimelineExposure.drawing(FrameId('f1'), length: 8),
        }),
        drawnFrameCount: 8,
      ),
    );
    expect(
      tester.getCenter(end).dx -
          tester.getTopLeft(find.byType(TimelineFrameCellsRow)).dx,
      8 * 48,
    );

    await tester.pumpWidget(
      harness(
        layer: seLayer({
          2: const TimelineExposure.drawing(FrameId('f1'), length: 5),
        }),
        drawnFrameCount: 8,
      ),
    );
    expect(end, findsNothing);
  });
}
