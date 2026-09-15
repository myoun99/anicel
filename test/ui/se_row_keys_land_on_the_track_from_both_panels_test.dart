import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

/// F-102's two HOSTS. Both panels key an SE row through `LaneVerbs`, and each
/// tells the verbs which axis its frames are on: the timeline's rail speaks
/// the ACTIVE cut's local frames, the storyboard's the track's global ones.
/// `se_row_keys_live_on_the_track_in_every_cut_test` pins the verbs; this
/// pins that each host hands them the right axis — pressing the real ◆ on the
/// real rail, in cut 2, with the key cut 1 made still on the row.

EditorSessionManager _sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

/// Cut 1 keys S1's Rotation at global frame 2; a second cut is made, which
/// makes it active, and the playhead parks on its local frame 3. Returns the
/// second cut's global start.
int _keyInCut1ThenStandInCut2(EditorSessionManager session) {
  final se = session.activeTrack.seLayers.first;
  session.updateLayerTransformTrack(
    se.id,
    TransformTrack.empty().copyWith(
      rotation: PropertyTrack(keys: {2: const PropertyKey(30.0)}),
    ),
  );
  session.cutVerbs.createCut();
  session.selectFrameIndex(3);
  final cut2Start = session.activeCutGlobalStartFrame;
  expect(
    cut2Start,
    greaterThan(2),
    reason: 'fixture premise: cut 2 starts after the key cut 1 made',
  );
  return cut2Start;
}

List<int> _rotationKeysOnTheRow(EditorSessionManager session) =>
    session.activeTrack.seLayers.first.transformTrack.rotation.keys.keys
        .toList();

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('🚨the TIMELINE\'s ◆ on S1 in cut 2 keys the row at the global '
      'frame under the playhead, and cut 1 keeps its key', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final session = _sessionOf(tester);
    final cut2Start = _keyInCut1ThenStandInCut2(session);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();

    final se = session.activeTrack.seLayers.first.id.value;
    await _tapVisible(
      tester,
      find.byKey(ValueKey<String>('timeline-lane-toggle-$se')),
    );
    await _tapVisible(
      tester,
      find.byKey(
        ValueKey<String>('timeline-lane-group-toggle-$se-transform-group'),
      ),
    );
    await _tapVisible(
      tester,
      find.byKey(ValueKey<String>('timeline-lane-key-toggle-$se-rotation')),
    );

    expect(_rotationKeysOnTheRow(session), [2, cut2Start + 3]);
  });

  testWidgets('🚨the STORYBOARD\'s ◆ on S1 keys the row at the global frame '
      'its label reads — not shifted by the cut start a second time', (
    tester,
  ) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final cut2Start = _keyInCut1ThenStandInCut2(session);
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
              thumbnailFor: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final track = session.activeTrack.id.value;
    final se = session.activeTrack.seLayers.first.id.value;
    await _tapVisible(
      tester,
      find.byKey(ValueKey<String>('storyboard-se-lane-toggle-$track-1')),
    );
    await _tapVisible(
      tester,
      find.byKey(
        ValueKey<String>('storyboard-lane-group-toggle-$se-transform-group'),
      ),
    );
    await _tapVisible(
      tester,
      find.byKey(ValueKey<String>('storyboard-lane-key-toggle-$se-rotation')),
    );

    expect(_rotationKeysOnTheRow(session), [2, cut2Start + 3]);
  });
}
