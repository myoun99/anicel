import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_row_filter.dart';

/// The folded storyboard is the row it stands on, at that row's height
/// (F-322) — in the frame the row changes in. Stood on a lane of a closed
/// group the fold is the V row; the group opened while folded — a graph
/// opened over the lane, or the group twirled down — and the fold is the
/// lane at once: its overlay and the room the region keeps for it at the
/// lane row's height — a graph seats the lane at that extent, as the open
/// rail draws it. So for a stand that moves alone (lane to lane, no session
/// notify) and an edit that hides the row (the session alone).
/// ↩️Both stayed the V row's until some other notify (card
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

  testWidgets('a stand moved from lane to lane — no session notify — folds '
      'to the lane it lands on in the same frame', (tester) async {
    final fold = await _foldedOnALaneOfAClosedGroup(tester);
    fold.presses.toggleLaneGroup(fold.group);
    await tester.pumpAndSettle();
    final before = fold.shownRow();

    final session = _Heard(fold.session);
    fold.session.standOnRow(
      LaneRowAddress(fold.s2, 'position'),
      panel: WorkingPanel.storyboard,
    );
    session.stop();
    await tester.pump();
    final folded = fold.shownRow();
    await tester.pumpAndSettle();

    expect(
      session.notified,
      isFalse,
      reason: '⛔전제: in one S row the stand moves on its own notifier',
    );
    expect(
      folded,
      isNot(before),
      reason: 'LIVENESS: the fold shows another lane',
    );
    expect(folded, fold.shownRow(), reason: 'the fold is that lane at once');
  });

  testWidgets('the row the fold stands on filtered out by an edit — the '
      'session alone — folds to what is left in the same frame', (
    tester,
  ) async {
    final fold = await _foldedOnALaneOfAClosedGroup(tester);
    fold.presses.toggleLaneGroup(fold.group);
    fold.session.railView.rowFilter.value = const TimelineRowFilter(
      fxOnly: true,
    );
    await tester.pumpAndSettle();
    final before = fold.overlayHeight();
    expect(before, fold.laneHeight, reason: '⛔전제: the fold is the lane');

    final stand = fold.session.standing.currentRowListenable.value;
    var drawn = false;
    void heard() => drawn = true;
    fold.session.railView.drawn.addListener(heard);
    fold.presses.toggleFx(fold.s2);
    fold.session.railView.drawn.removeListener(heard);
    await tester.pump();
    final folded = (overlay: fold.overlayHeight(), room: fold.room());
    await tester.pumpAndSettle();

    expect(
      (drawn, fold.session.standing.currentRowListenable.value),
      (false, stand),
      reason: '⛔전제: the rail\'s view and the stand stay as they were',
    );
    expect(
      fold.overlayHeight(),
      isNot(fold.laneHeight),
      reason: 'LIVENESS: its S row filtered out, the lane is not drawn',
    );
    expect(
      folded,
      (overlay: fold.overlayHeight(), room: fold.room()),
      reason: 'the fold is laid in the frame of the edit',
    );
    expect(folded.room, folded.overlay, reason: 'the region keeps it');
  });
}

/// Whether [session] notified between its making and [stop].
class _Heard {
  _Heard(this._session) {
    _session.addListener(_hear);
  }

  final ChangeNotifier _session;
  bool notified = false;

  void _hear() => notified = true;

  void stop() => _session.removeListener(_hear);
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
  EditorSessionManager session,
  SessionRowButtonPresses presses,
  LayerId s1,
  LayerId s2,
  String group,
  double laneHeight,
  double Function() overlayHeight,
  double Function() room,
  String? Function() shownRow,
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
    session: session,
    presses: presses,
    s1: s1,
    s2: s2,
    group: group,
    laneHeight: laneHeight,
    overlayHeight: () => tester.widget<CollapsedRowOverlay>(overlay).height,
    room: () => tester.getSize(overlay).height,
    shownRow: () =>
        tester.widget<CollapsedRowOverlay>(overlay).snapshot.currentRow?.name,
  );
}
