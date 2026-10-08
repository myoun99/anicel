import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_section_policy.dart';

import '../../helpers/conte_track_fixture.dart';
import '../../helpers/home_page_probes.dart';
import '../storyboard_conte_row_probe.dart';

/// 🗣️F-199 (유저 2026-09-27): 「콘티패널도 타임라인이랑 동일하게 se나
/// 카메라섹션 접을수있게 로직통일」.
///
/// The storyboard's rail hides the SE section (its S rows) and the camera
/// section (its transition row) by the set the timeline's grids read, from
/// the same legend menu — which it carried all along, greyed, because it
/// was never handed the toggle. [conteTrackProject]: one track `t` with a
/// transition row, one S row (S1), its V row and, under that, its conte
/// row (I-73) — a drawing row, by the section the timeline puts it in.
void main() {
  const vRow = TrackRowAddress(conteTrackId);
  const sRow = LayerRowAddress(conteSeId);
  final conteRow = LayerRowAddress(trackConteRowId(conteTrackId));

  group('the session', () {
    late EditorSessionManager session;
    late LayerRowAddress transitionRow;

    setUp(() {
      session = EditorSessionManager(initialProject: conteTrackProject());
      transitionRow = LayerRowAddress(
        session.repository.requireProject().tracks.single.transitionLayer.id,
      );
    });
    tearDown(() => session.dispose());

    List<TimelineRowAddress> railRows() =>
        session.storyboardRows.storyboardRailRows(conteTrackId);

    test('a range drag walks only the rows the rail shows', () {
      expect(railRows(), [transitionRow, sRow, vRow], reason: 'premise');
      session.railView.hiddenSections.value = {TimelineSection.se};
      expect(railRows(), [transitionRow, vRow]);
      session.railView.hiddenSections.value = {TimelineSection.camera};
      expect(railRows(), [sRow, vRow]);
    });

    test('hiding the section the storyboard stands in hands it to the V '
        'row', () {
      session.standOnRow(sRow, panel: WorkingPanel.storyboard);
      expect(session.storyboardStandingRow, sRow, reason: 'premise');

      session.railView.hiddenSections.value = {TimelineSection.se};
      session.standing.keepStandingShown();

      expect(session.storyboardStandingRow, vRow);
    });

    test('…the camera section too, standing on the transition row', () {
      session.standOnRow(transitionRow, panel: WorkingPanel.storyboard);
      expect(session.storyboardStandingRow, transitionRow, reason: 'premise');

      session.railView.hiddenSections.value = {TimelineSection.camera};
      session.standing.keepStandingShown();

      expect(session.storyboardStandingRow, vRow);
    });

    test('a hidden section the storyboard does not stand in moves nothing',
        () {
      session.standOnRow(sRow, panel: WorkingPanel.storyboard);
      session.railView.hiddenSections.value = {TimelineSection.camera};
      session.standing.keepStandingShown();
      expect(session.storyboardStandingRow, sRow);
    });

    // I-73: the conte row sits in the section the timeline puts its kind
    // in — the drawing rows'.
    test('…the drawing section too, standing on the conte row', () {
      session.standOnRow(conteRow, panel: WorkingPanel.storyboard);
      expect(session.storyboardStandingRow, conteRow, reason: 'premise');

      session.railView.hiddenSections.value = {TimelineSection.drawing};
      session.standing.keepStandingShown();

      expect(session.storyboardStandingRow, vRow);
    });

    test('…and the conte row stays stood on while another section hides',
        () {
      session.standOnRow(conteRow, panel: WorkingPanel.storyboard);
      session.railView.hiddenSections.value = {
        TimelineSection.se,
        TimelineSection.camera,
      };
      session.standing.keepStandingShown();
      expect(session.storyboardStandingRow, conteRow);
    });
  });

  testWidgets('the conte row hides with the drawing section — its band, its '
      'label and its strip — and the V row stays', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: conteTrackProject())),
    );
    await tester.pumpAndSettle();
    await showStoryboardPanel(tester);
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;

    Finder inStoryboard(String key) => find.descendant(
      of: find.byType(StoryboardPanel),
      matching: find.byKey(ValueKey<String>(key)),
    );
    const conteZone = 'storyboard-section-zone-t-conte';
    expect(inStoryboard(conteZone), findsOneWidget, reason: 'premise');
    expect(conteRowFinder('t'), findsOneWidget, reason: 'premise');

    session.railView.hiddenSections.value = {TimelineSection.drawing};
    await tester.pumpAndSettle();

    expect(inStoryboard(conteZone), findsNothing);
    expect(inStoryboard('storyboard-conte-label-t'), findsNothing);
    expect(conteRowFinder('t'), findsNothing, reason: 'its strip with it');
    expect(inStoryboard('storyboard-section-zone-t-v'), findsOneWidget);
    expect(inStoryboard('storyboard-track-row-t'), findsOneWidget);
  });

  testWidgets('the storyboard\'s legend hides its SE and camera sections, '
      'in the timeline\'s one set', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: conteTrackProject())),
    );
    await tester.pumpAndSettle();
    await showStoryboardPanel(tester);
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;

    Finder inStoryboard(String key) => find.descendant(
      of: find.byType(StoryboardPanel),
      matching: find.byKey(ValueKey<String>(key)),
    );
    const seZone = 'storyboard-section-zone-t-se';
    const camZone = 'storyboard-section-zone-t-transition';
    const vZone = 'storyboard-section-zone-t-v';
    expect(inStoryboard(seZone), findsOneWidget, reason: 'premise');
    expect(inStoryboard(camZone), findsOneWidget, reason: 'premise');

    Future<void> toggle(String entry) async {
      await tester.tap(inStoryboard('legend-sections'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>(entry)));
      await tester.pumpAndSettle();
    }

    await toggle('legend-section-se');
    expect(inStoryboard(seZone), findsNothing, reason: 'the S rows hid');
    expect(inStoryboard(camZone), findsOneWidget);
    expect(inStoryboard(vZone), findsOneWidget, reason: 'the V row stays');
    expect(
      session.railView.hiddenSections.value,
      {TimelineSection.se},
      reason: 'the timeline\'s one set',
    );

    await toggle('legend-section-camera');
    expect(inStoryboard(camZone), findsNothing, reason: 'the CAM row hid');
    expect(inStoryboard(vZone), findsOneWidget);

    await toggle('legend-section-se');
    expect(inStoryboard(seZone), findsOneWidget, reason: 'and it comes back');
  });
}
