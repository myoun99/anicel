import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/dialogs/rename_cut_dialog.dart';
import 'package:anicel/src/ui/dialogs/se_instance_dialog.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_command_actions.dart'
    show createActiveInstance;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

import '../../helpers/home_page_probes.dart';

/// 🗣️F-261 (유저 2026-10-02): 「자주쓰는 버튼 그냥 직관적이지 않더라도
/// 왼쪽으로 몰아넣을까 … 재생/정지버튼은 S로두고 처음으로버튼 A, 그리고
/// 편집버튼은 D로두자」 — and 「콘티패널에 포커스있으면 플립이 콘티패널기준
/// 작동 … 그거랑 동일하게 법 통일해서 재생」.
///
/// Each key is a BUTTON on the panel being worked in, so each test presses
/// that panel's button first and asks the key to do the same — on both
/// panels, because the two buttons do different things.
Cut _cut(String id) => Cut(
  id: CutId(id),
  name: id,
  duration: 8,
  canvasSize: const CanvasSize(width: 640, height: 360),
  layers: const [],
);

/// Two cuts, so 「처음으로」 can tell the cut's start from the track's.
Project _twoCuts() => Project(
  id: const ProjectId('left-hand-keys'),
  name: 'LeftHandKeys',
  createdAt: DateTime.utc(2026, 10, 2),
  tracks: [
    Track(
      id: const TrackId('track'),
      name: 'Video',
      cuts: [_cut('cut-1'), _cut('cut-2')],
    ),
  ],
);

Future<EditorSessionManager> _pump(WidgetTester tester, Project project) async {
  await tester.binding.setSurfaceSize(const Size(1500, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: project)),
  );
  await tester.pumpAndSettle();
  return tester
      .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
      .session;
}

Future<void> _workIn(WidgetTester tester, WorkingPanel panel) async {
  await tester.tap(
    find.byKey(
      ValueKey<String>(switch (panel) {
        WorkingPanel.timeline => 'timeline-mode-timeline-button',
        WorkingPanel.storyboard => 'timeline-mode-storyboard-button',
      }),
    ),
  );
  await tester.pumpAndSettle();
}

/// Cut 2, three frames in — away from both starts.
Future<void> _standInCutTwo(
  WidgetTester tester,
  EditorSessionManager session,
) async {
  session.selectCut(const CutId('cut-2'));
  session.selectFrameIndex(3);
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

void main() {
  testWidgets('S plays what the play button of the panel being worked in '
      'plays — the timeline its cut, the storyboard the track', (
    tester,
  ) async {
    final session = await _pump(tester, _twoCuts());
    final playback = session.playbackRig.playback;
    for (final (panel, scope) in const [
      (WorkingPanel.timeline, PlaybackScope.activeCut),
      (WorkingPanel.storyboard, PlaybackScope.allCuts),
    ]) {
      await _workIn(tester, panel);
      expect(session.workingPanel, panel, reason: '⛔전제');

      await tester.tap(
        find.byKey(const ValueKey<String>('playback-play-button')),
      );
      await tester.pump();
      expect(playback.isPlaying, isTrue, reason: 'LIVENESS: $panel button');
      expect(playback.scope, scope, reason: 'the $panel button\'s playlist');
      session.playbackRig.transports.stopAll();
      await tester.pumpAndSettle();

      await _press(tester, LogicalKeyboardKey.keyS);
      expect(playback.isPlaying, isTrue, reason: 'S on the $panel');
      expect(playback.scope, scope, reason: 'S plays what its button plays');
      session.playbackRig.transports.stopAll();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('A goes where 「처음으로」 of the panel being worked in goes — '
      'the timeline to its cut\'s frame 0, the storyboard to the track\'s '
      'first frame', (tester) async {
    final session = await _pump(tester, _twoCuts());
    for (final (panel, cut) in const [
      (WorkingPanel.timeline, CutId('cut-2')),
      (WorkingPanel.storyboard, CutId('cut-1')),
    ]) {
      await _workIn(tester, panel);

      await _standInCutTwo(tester, session);
      await tester.tap(
        find.byKey(const ValueKey<String>('playback-skip-to-start-button')),
      );
      await tester.pumpAndSettle();
      expect(session.activeCutOrNull?.id, cut, reason: 'the $panel button');
      expect(session.currentFrameIndex, 0);

      await _standInCutTwo(tester, session);
      await _press(tester, LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();
      expect(session.activeCutOrNull?.id, cut, reason: 'A on the $panel');
      expect(session.currentFrameIndex, 0);
    }
  });

  testWidgets('D opens the storyboard\'s Edit there — the cut\'s rename — and '
      'not on the timeline, whose Edit never reaches for cuts (R5q1)', (
    tester,
  ) async {
    await _pump(tester, _twoCuts());
    await _workIn(tester, WorkingPanel.storyboard);

    await tapToolbarButton(
      tester,
      const ValueKey<String>('shared-edit-button'),
    );
    expect(find.byType(RenameCutDialog), findsOneWidget, reason: 'LIVENESS');
    await _press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(RenameCutDialog), findsNothing, reason: '⛔전제');

    await _press(tester, LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    expect(find.byType(RenameCutDialog), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await _workIn(tester, WorkingPanel.timeline);
    await _press(tester, LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    expect(find.byType(RenameCutDialog), findsNothing);
  });

  testWidgets('D on an X-sheet\'s SE block opens the dialog its button opens, '
      'previewing down the page as the sheet runs', (tester) async {
    final session = await _pump(tester, createDefaultProject());
    session.layerStack.addLayerOfKind(LayerKind.se);
    createActiveInstance(session);
    await tester.pumpAndSettle();
    await tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-orientation-toggle-button'),
    );

    Axis previewAxis() => tester
        .widget<SeInstanceDialog>(find.byType(SeInstanceDialog))
        .previewAxis;

    await tapToolbarButton(
      tester,
      const ValueKey<String>('shared-edit-button'),
    );
    expect(previewAxis(), Axis.vertical, reason: 'the button\'s, on a sheet');
    await _press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SeInstanceDialog), findsNothing, reason: '⛔전제');

    await _press(tester, LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    expect(previewAxis(), Axis.vertical);
  });
}
