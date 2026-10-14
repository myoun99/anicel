import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

/// 🚨ONE PRESS ON THE LEGEND'S TWIRL-ALL IS ONE UNDO (유저 08-28: 「일괄로
/// 버튼 조작하고 언두하면 바꼈던 레이어들 다 한번에 언두되야하는데 안됨」).
///
/// F-360 made a twirl the row's, written through history as a fold is
/// (유저 08-29: 「접기도 마찬가지야」) — and the legend's twirl-all presses
/// each row's twirl in turn, so one press became a step per row and one
/// Ctrl+Z took back one row. Both rails, each pressing its own legend.
void main() {
  /// Every row of the project whose lanes are twirled down.
  Set<LayerId> twirled(EditorSessionManager session) => {
    for (final track in session.repository.requireProject().tracks) ...{
      for (final row in track.seLayers)
        if (row.lanesExpanded) row.id,
      for (final cut in track.cuts)
        for (final row in cut.layers)
          if (row.lanesExpanded) row.id,
    },
  };

  const toggle = ValueKey<String>('legend-lanes-toggle');

  Future<void> pressAndUndo(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    expect(twirled(session), isEmpty, reason: 'premise — nothing is open');
    final depth = session.historyManager.undoCount;

    await tester.tap(find.byKey(toggle));
    await tester.pumpAndSettle();
    expect(
      twirled(session).length,
      greaterThanOrEqualTo(2),
      reason: 'premise — the press turned more than one row',
    );
    expect(session.historyManager.undoCount, depth + 1, reason: 'one step');

    session.undo();
    await tester.pumpAndSettle();
    expect(twirled(session), isEmpty, reason: 'one undo takes them all back');
  }

  testWidgets('on the timeline', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.layerStack.addLayerOfKind(LayerKind.animation);
    await tester.pumpAndSettle();
    // Room for lane rows: pull the timeline dock up.
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();

    await pressAndUndo(tester, session);
  });

  testWidgets('on the storyboard — a camera row on each of two tracks', (
    tester,
  ) async {
    final session = EditorSessionManager(initialProject: _twoTracks());
    addTearDown(session.dispose);
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await pressAndUndo(tester, session);
  });
}

/// The default project with a second track behind its first, a cut with
/// its own camera on it.
Project _twoTracks() {
  final project = createDefaultProject();
  return project.copyWith(
    tracks: [
      ...project.tracks,
      Track(
        id: const TrackId('second-track'),
        name: 'Track 2',
        cuts: [
          createDefaultCut(
            cutId: const CutId('second-cut'),
            name: '2',
            layerId: const LayerId('second-a'),
          ),
        ],
      ),
    ],
  );
}
