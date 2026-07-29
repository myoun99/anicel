import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

/// R4a window adapter, driven through the real strips: the per-cut lane UI
/// still speaks CUT-LOCAL frames, but every verb must land on the TRACK's
/// global axis through the cut's window — a key toggled "at frame 0" of
/// the SECOND cut lives at the second cut's global start, not at 0.
void main() {
  Future<EditorSessionManager> pumpHost(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final manager = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    manager.createCut(); // Two cuts; the NEW (second) one is active.
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([manager, manager.frameSeekCommitted]),
            builder: (context, _) => StoryboardTabHost(
              session: manager,
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
    return manager;
  }

  Future<void> twirlOpenTransformLanes(
    WidgetTester tester,
    String trackId,
  ) async {
    await tester.tap(
      find.byKey(ValueKey<String>('storyboard-track-lane-toggle-$trackId')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'storyboard-lane-group-toggle-v-$trackId-transform-group',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a key toggled on the ACTIVE second cut\'s lane lands at the '
      'cut\'s GLOBAL start on the track — and toggles back off there', (
    tester,
  ) async {
    final manager = await pumpHost(tester);
    final trackId = manager.activeTrack.id;
    final secondCut = manager.activeTrack.cuts[1];
    expect(manager.activeCutId, secondCut.id, reason: 'createCut selects it');
    final secondStart = manager
        .trackFrameAxis()
        .entryFor(secondCut.id)!
        .startFrame;
    expect(secondStart, greaterThan(0));

    await twirlOpenTransformLanes(tester, trackId.value);

    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'storyboard-lane-key-toggle-v-${trackId.value}-position',
        ),
      ),
    );
    await tester.pumpAndSettle();

    var lane = manager.activeTrack.transformTrack.position;
    expect(
      lane.keyAt(secondStart),
      isNotNull,
      reason: 'local frame 0 of the second cut = global $secondStart',
    );
    expect(lane.keyAt(0), isNull, reason: 'NOT at the raw local frame');

    // The same toggle removes it — the round-trip stays in the window.
    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'storyboard-lane-key-toggle-v-${trackId.value}-position',
        ),
      ),
    );
    await tester.pumpAndSettle();
    lane = manager.activeTrack.transformTrack.position;
    expect(lane.keyAt(secondStart), isNull);
    expect(lane.isEmpty, isTrue);
  });

  testWidgets('the fade handles write into the ACTIVE cut\'s window at its '
      'global offset (setCutFade through the host)', (tester) async {
    final manager = await pumpHost(tester);
    final secondCut = manager.activeTrack.cuts[1];
    final secondStart = manager
        .trackFrameAxis()
        .entryFor(secondCut.id)!
        .startFrame;

    await twirlOpenTransformLanes(tester, manager.activeTrack.id.value);

    // 3 frames rightward on the fade-in handle (12 px/frame).
    await tester.drag(
      find.byKey(
        ValueKey<String>(
          'storyboard-cut-fade-in-handle-${secondCut.id.value}',
        ),
      ),
      const Offset(36, 0),
    );
    await tester.pumpAndSettle();

    final opacity = manager.activeTrack.transformTrack.opacity;
    expect(opacity.keyAt(secondStart)?.value, 0.0);
    expect(opacity.keyAt(secondStart + 3)?.value, 1.0);
    expect(opacity.keyAt(0), isNull, reason: 'first cut\'s window untouched');
  });
}
