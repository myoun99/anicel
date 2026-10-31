import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/frame_census.dart';

/// 🔬I-22-rest (10-31, S5_BA's cut 352): the storyboard's stand rides along
/// where the timeline stands (I-126), and the room the folded storyboard
/// keeps heard it — so a press on a timeline row built the workspace's floor
/// again, for a fold nobody was showing. It hears a stand while the fold is
/// the storyboard's (`the_folded_storyboard_follows_a_group_opened_while_
/// folded_test`).
void main() {
  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a row stood on in the timeline, the storyboard\'s stand riding '
      'along, builds none of the floor', (tester) async {
    await pumpApp(tester);
    final session = sessionOf(tester);
    final row = session.repository.requireProject().tracks.first.seLayers[0].id;
    final before = session.standing.storyboardStandingRow;

    final frame = await frameCensus(
      tester,
      () => session.standOnRow(
        LayerRowAddress(row),
        panel: WorkingPanel.timeline,
      ),
    );

    expect(
      session.standing.storyboardStandingRow,
      isNot(before),
      reason: '⛔전제: the storyboard\'s stand moved with the timeline\'s',
    );
    expect(
      frame.rebuilt,
      isNot(contains(CanvasFloorInsets)),
      reason: '↩️the fold heard the stand with no fold of the storyboard\'s '
          'to show, and built the floor',
    );
  });

  testWidgets('and with the storyboard\'s panel in the region the stand is '
      'news to the fold again', (tester) async {
    await pumpApp(tester);
    final session = sessionOf(tester);
    final row = session.repository.requireProject().tracks.first.seLayers[0].id;
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();

    final frame = await frameCensus(
      tester,
      () => session.standOnRow(
        LayerRowAddress(row),
        panel: WorkingPanel.storyboard,
      ),
    );

    expect(frame.rebuilt, contains(CanvasFloorInsets));
  });
}
