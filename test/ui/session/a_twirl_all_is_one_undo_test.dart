import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

import '../../helpers/storyboard_twirls.dart';

/// 🚨ONE PRESS ON THE LEGEND'S TWIRL-ALL IS ONE UNDO (유저 08-28: 「일괄로
/// 버튼 조작하고 언두하면 바꼈던 레이어들 다 한번에 언두되야하는데 안됨」).
///
/// F-360 made a twirl the row's, written through history as a fold is
/// (유저 08-29: 「접기도 마찬가지야」) — and the legend's twirl-all presses
/// each row's twirl in turn, so one press became a step per row and one
/// Ctrl+Z took back one row. Both rails, each pressing its own legend.
void main() {
  /// Every row of the project whose lanes are twirled down — a layer's by
  /// its id, a V row's by its track's.
  Set<Object> twirled(EditorSessionManager session) => {
    for (final track in session.repository.requireProject().tracks) ...{
      if (track.lanesExpanded) track.id,
      for (final row in track.seLayers)
        if (row.lanesExpanded) row.id,
      for (final cut in track.cuts)
        for (final row in cut.layers)
          if (row.lanesExpanded) row.id,
    },
  };

  const toggle = ValueKey<String>('legend-lanes-toggle');

  /// Presses the legend open and shut, then undoes each press — and
  /// returns what the opening press turned.
  Future<Set<Object>> pressAndUndo(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    expect(twirled(session), isEmpty, reason: 'premise — nothing is open');
    final depth = session.historyManager.undoCount;

    await tester.tap(find.byKey(toggle));
    await tester.pumpAndSettle();
    final opened = twirled(session);
    expect(
      opened.length,
      greaterThanOrEqualTo(2),
      reason: 'premise — the press turned more than one row',
    );
    expect(session.historyManager.undoCount, depth + 1, reason: 'one step');

    // Once any row is open the same button shuts them all.
    await tester.tap(find.byKey(toggle));
    await tester.pumpAndSettle();
    expect(twirled(session), isEmpty, reason: 'premise — it shut them');
    expect(session.historyManager.undoCount, depth + 2, reason: 'one step');

    session.undo();
    await tester.pumpAndSettle();
    expect(twirled(session), opened, reason: 'one undo opens them all again');
    session.undo();
    await tester.pumpAndSettle();
    expect(twirled(session), isEmpty, reason: 'one more shuts them all');
    return opened;
  }

  /// The app on the default project and a second drawing row, the timeline
  /// pulled up for lane rows — with the two drawing rows.
  Future<({EditorSessionManager session, LayerId a, LayerId b})> timeline(
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final a = session.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    final before = {for (final layer in session.layers) layer.id};
    session.layerStack.addLayerOfKind(LayerKind.animation);
    await tester.pumpAndSettle();
    final b = session.layers.firstWhere((layer) => !before.contains(layer.id));
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    return (session: session, a: a, b: b.id);
  }

  testWidgets('on the timeline', (tester) async {
    final rig = await timeline(tester);

    await pressAndUndo(tester, rig.session);
  });

  testWidgets('on the timeline, over rows selected together — the press on '
      'one turns the other, and the sweep reaching it reads it turned', (
    tester,
  ) async {
    final rig = await timeline(tester);
    rig.session.rowSelection.value = [
      LayerRowAddress(rig.a),
      LayerRowAddress(rig.b),
    ];
    await tester.pumpAndSettle();

    final opened = await pressAndUndo(tester, rig.session);

    expect(opened, containsAll([rig.a, rig.b]), reason: 'both were opened');
  });

  testWidgets('on the storyboard — a camera row on each of two tracks, and a '
      'V row its fx chain twirls down under', (tester) async {
    final session = EditorSessionManager(initialProject: _twoTracks());
    addTearDown(session.dispose);
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: withStoryboardTwirls(
            session,
            (twirls) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
              expandedLaneLayerIds: twirls.expandedLaneLayerIds,
              onToggleLayerLanes: twirls.onToggleLayerLanes,
              expandedLaneGroupKeys: twirls.expandedLaneGroupKeys,
              onToggleLaneGroupKey: twirls.onToggleLaneGroupKey,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final opened = await pressAndUndo(tester, session);

    expect(
      opened,
      contains(const TrackId('second-track')),
      reason: 'the V row is its track\'s, turned in the same step',
    );
  });
}

/// The default project with a second track behind its first, a cut with
/// its own camera on it — and an fx chain on the track, which its V row
/// twirls down.
Project _twoTracks() {
  final project = createDefaultProject();
  return project.copyWith(
    tracks: [
      ...project.tracks,
      Track(
        id: const TrackId('second-track'),
        name: 'Track 2',
        effects: [
          LayerEffect.defaults(
            id: const EffectId('second-blur'),
            kind: EffectKind.blur,
          ),
        ],
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
