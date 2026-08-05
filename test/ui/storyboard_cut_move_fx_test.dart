import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'storyboard_cut_block_probe.dart';

/// R12-⑧ repro: the cut-block slide (gap authoring) must keep working when
/// the TRACK carries fx transform keys (R4: track-owned lanes) — with the
/// Transform strips twirled open too (the state the keys get authored in).
void main() {
  Future<EditorSessionManager> pumpHost(WidgetTester tester) async {
    // The rail matches the timeline's — 372 in UI-R5, 434 since the user
    // unified the two widths (2026-08-04) — so the default 800px surface
    // would push the second cut's block off screen.
    await tester.binding.setSurfaceSize(const Size(1400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final manager = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    manager.createCut();
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

  Future<void> dragSecondCut(
    WidgetTester tester,
    EditorSessionManager manager,
  ) async {
    final secondCut = manager.activeTrack.cuts[1];
    // UI-R18 #1 mode split: a body drag slides only when the cut sits in
    // the selection — select it first (the user's first drag does this).
    final secondStart = manager
        .trackFrameAxis()
        .entryFor(secondCut.id)!
        .startFrame;
    manager.updateStoryboardCutSelectionByFrame(
      trackId: manager.activeTrack.id,
      anchorGlobalFrame: secondStart,
      headGlobalFrame: secondStart,
    );
    await tester.pump();
    final gesture = await tester.startGesture(
      cutBlockBandCenter(tester, secondCut.id.value),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('slide works with fx transform keys on the track', (
    tester,
  ) async {
    final manager = await pumpHost(tester);
    final keyed = TransformTrack(
      keyframes: {
        0: TransformPose(
          center: CanvasPoint(x: 100, y: 100),
          zoom: 1.2,
          rotationDegrees: 0,
        ),
        8: TransformPose(
          center: CanvasPoint(x: 200, y: 100),
          zoom: 1.0,
          rotationDegrees: 10,
        ),
      },
    );
    manager.updateTrackTransformTrack(manager.activeTrack.id, keyed);
    await tester.pumpAndSettle();

    await dragSecondCut(tester, manager);

    // 48px at 12 px/frame = the cut slid 4 frames: its leading gap opened.
    expect(manager.activeTrack.cuts[1].leadingGapFrames, 4);
    // R4 independence: the slide moved the CUT, not the track's keys.
    expect(manager.activeTrack.transformTrack, keyed);
  });

  testWidgets('slide works with the Transform strips twirled open', (
    tester,
  ) async {
    final manager = await pumpHost(tester);
    manager.updateTrackTransformTrack(
      manager.activeTrack.id,
      TransformTrack(
        keyframes: {
          0: TransformPose(
            center: CanvasPoint(x: 100, y: 100),
            zoom: 1.2,
            rotationDegrees: 0,
          ),
        },
      ),
    );
    await tester.pumpAndSettle();

    // Twirl the V track's lane strips open (the chevron), then the
    // Transform group header — the state keys get authored in.
    final trackId = manager.activeTrack.id.value;
    await tester.tap(
      find.byKey(ValueKey<String>('storyboard-track-lane-toggle-$trackId')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'storyboard-lane-group-toggle-v-track:$trackId-transform-group',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await dragSecondCut(tester, manager);

    expect(manager.activeTrack.cuts[1].leadingGapFrames, 4);
  });
}
