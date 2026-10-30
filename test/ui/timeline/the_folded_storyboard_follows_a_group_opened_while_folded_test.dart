import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';

/// The folded storyboard is the row it stands on, at that row's height
/// (F-322) — in the frame the row changes in. Stood on a lane of a closed
/// group the fold is the V row; the group opened while folded — a graph
/// opened over the lane, or the group twirled down — and the fold is the
/// lane at once: its overlay and the room the region keeps for it at the
/// lane row's height — a graph seats the lane at that extent, as the open
/// rail draws it. ↩️Both stayed the V row's until some other notify (card
/// a-folded-conte-row-keeps-its-height-through-a-graph): the fold read the
/// panel's copy of the rail, which the panel had not been given yet, and
/// the room heard the stand alone.
void main() {
  for (final opening in _Opening.values) {
    testWidgets('the group of the lane the fold stands on, opened by '
        '${opening.name} while folded, folds it to the lane in the same '
        'frame', (tester) async {
      final fold = await _foldedOnALaneOfAClosedGroup(tester);
      final before = fold.overlayHeight();

      opening.toggle(fold);
      await tester.pump();

      expect(
        before,
        isNot(fold.laneHeight),
        reason: 'LIVENESS: the fold was the V row while the group was closed',
      );
      expect(
        fold.overlayHeight(),
        fold.laneHeight,
        reason: 'the overlay is the lane',
      );
      expect(fold.room(), fold.laneHeight, reason: 'the region keeps it');
    });
  }
}

/// What opens the group of the lane stood on.
enum _Opening {
  graph,
  twirl;

  void toggle(_Fold fold) => switch (this) {
    graph => fold.presses.toggleLaneGraph(fold.group),
    twirl => fold.presses.toggleLaneGroup(fold.group),
  };
}


typedef _Fold = ({
  SessionRowButtonPresses presses,
  String group,
  double laneHeight,
  double Function() overlayHeight,
  double Function() room,
});

/// The storyboard folded while it stands on S2's rotation lane, its
/// Transform group shut — S1's and S2's lanes twirled down, so the S rows'
/// own rows are drawn either way — and the lane's height as the open rail
/// draws it, its group twirled down.
Future<_Fold> _foldedOnALaneOfAClosedGroup(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: createDefaultProject())),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -500),
  );
  await tester.pumpAndSettle();
  final session = tester
      .widget<EditorWorkspace>(find.byType(EditorWorkspace))
      .session;
  final presses = SessionRowButtonPresses(session);
  final track = session.repository.requireProject().tracks.first;
  final s1 = track.seLayers[0].id;
  final s2 = track.seLayers[1].id;
  final group = laneGroupKey(s2, 'transform-group');
  presses.toggleLanes(s1);
  presses.toggleLanes(s2);
  presses.toggleLaneGroup(group);
  await tester.pumpAndSettle();
  final lane = find.byKey(
    const ValueKey<String>('storyboard-se-lane-row-0-2-rotation'),
  );
  expect(lane, findsOneWidget, reason: 'LIVENESS: the lane is drawn');
  final laneHeight = tester.getSize(lane).height;
  presses.toggleLaneGroup(group);
  await tester.pumpAndSettle();
  session.standOnRow(
    LaneRowAddress(s2, 'rotation'),
    panel: WorkingPanel.storyboard,
    globalFrameIndex: 3,
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('floating-bottom-collapse')),
  );
  await tester.pumpAndSettle();
  final overlay = find.byType(CollapsedRowOverlay);
  return (
    presses: presses,
    group: group,
    laneHeight: laneHeight,
    overlayHeight: () => tester.widget<CollapsedRowOverlay>(overlay).height,
    room: () => tester.getSize(overlay).height,
  );
}
