import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_playhead_mapping.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/timeline_shift_buttons.dart';
import 'storyboard_cut_block_probe.dart';

/// A COMMITTED SEEK — an arrow-key flip, a ruler release, a `.`/`,` step —
/// must not rebuild the storyboard panel. It reaches exactly the places
/// that show a frame, each through its own channel: the playhead overlay
/// and ruler, the rail's lane-label value cells, and the push/pull pair.
///
/// Measured before this contract existed: `frameSeekCommitted` sat in the
/// workspace's storyboard-tab merge, so one arrow press rebuilt the whole
/// tab — 38ms a step on a six-cut project (12 build / 22 layout / 3 paint),
/// against 1.6ms after. The timeline tab never had that subscription; this
/// panel was the odd one out.
///
/// ⚠️ The wiring below is the WORKSPACE's, which is the SESSION ALONE.
/// Most storyboard tests merge `frameSeekCommitted` in as well — under that
/// harness the panel rebuilds anyway and none of this is observable, which
/// is exactly why the contract needs its own file.
void main() {
  Future<EditorSessionManager> pumpHost(
    WidgetTester tester,
    EditorSessionManager manager,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            // The workspace's storyboard-tab listenable, verbatim.
            listenable: manager,
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

  Future<void> twirlOpenTrackLanes(WidgetTester tester, String trackId) async {
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
  }

  double playheadX(WidgetTester tester) => tester
      .getTopLeft(find.byKey(const ValueKey<String>('storyboard-playhead')))
      .dx;

  /// Every test here ends on a bare `pump` — settling would hand the panel
  /// a second chance to rebuild and hide the very thing being asserted — so
  /// the warm loop's idle timers are stood down by hand instead.
  void quiesce(EditorSessionManager manager) =>
      manager.prerenderScheduler.cancel();

  testWidgets('a committed seek moves the playhead and leaves the panel\'s '
      'painted rows untouched', (tester) async {
    final manager = await pumpHost(
      tester,
      EditorSessionManager(initialProject: createDefaultProject()),
    );
    manager.selectFrameIndex(0);
    await tester.pumpAndSettle();

    final painterBefore = cutBlocksPainter(tester);
    final xBefore = playheadX(tester);

    manager.selectFrameIndex(5);
    await tester.pump();

    expect(
      playheadX(tester) - xBefore,
      5 * 12.0,
      reason: 'the overlay followed the seek through its own channel',
    );
    expect(
      identical(cutBlocksPainter(tester), painterBefore),
      isTrue,
      reason: 'and the panel never rebuilt to do it',
    );
    quiesce(manager);
  });

  testWidgets('a V lane\'s value cell follows a committed seek WITHOUT a '
      'panel rebuild', (tester) async {
    final manager = await pumpHost(
      tester,
      EditorSessionManager(initialProject: createDefaultProject()),
    );
    final trackId = manager.activeTrack.id;
    manager.updateTrackTransformTrack(
      trackId,
      TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty()
            .withKey(0, CanvasPoint(x: 0, y: 0))
            .withKey(6, CanvasPoint(x: 120, y: 240)),
      ),
    );
    await tester.pumpAndSettle();
    await twirlOpenTrackLanes(tester, trackId.value);

    final valueCell = find.descendant(
      of: find.byKey(
        ValueKey<String>('storyboard-lane-value-v-track:${trackId.value}-'
            'position'),
      ),
      matching: find.byType(Text),
    );
    String valueText() => tester.widget<Text>(valueCell).data!;

    seekStoryboardGlobalFrame(manager, 0);
    await tester.pumpAndSettle();
    final atStart = valueText();
    final painterBefore = cutBlocksPainter(tester);

    seekStoryboardGlobalFrame(manager, 6);
    await tester.pump();

    expect(
      valueText(),
      isNot(atStart),
      reason: 'the lane label reads the value AT the cursor, so it must move',
    );
    expect(
      identical(cutBlocksPainter(tester), painterBefore),
      isTrue,
      reason: 'through the cursor channel, not a panel rebuild',
    );
    quiesce(manager);
  });

  testWidgets('the push/pull pair re-gates on a committed seek with no '
      'parent rebuild at all', (tester) async {
    // A block, a gap, a block (push_pull_test's own fixture): a pull from
    // frame 0 has nothing in front of it, one from frame 4 has the gap.
    final manager = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(manager.dispose);
    manager.selectFrameIndex(0);
    manager.createDrawingAtCurrentFrame();
    manager.selectFrameIndex(4);
    manager.createDrawingAtCurrentFrame();
    expect(manager.framePullSlack(), 3, reason: 'the fixture has the gap');
    manager.selectFrameIndex(0);
    expect(manager.framePullSlack(), 0, reason: 'and none at the start');

    // Mounted BARE: nothing above these buttons can rebuild them, so a
    // change in their enabled state can only come from their own listener.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TimelineShiftButtons(session: manager)),
      ),
    );
    await tester.pumpAndSettle();

    bool pullEnabled() =>
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey<String>('pull-blocks-button')),
            )
            .onPressed !=
        null;

    expect(
      pullEnabled(),
      isFalse,
      reason: 'at frame 0 the moved run already touches the start',
    );

    manager.selectFrameIndex(4);
    await tester.pump();

    expect(
      pullEnabled(),
      isTrue,
      reason: 'the seek alone re-derived the gating — no parent rebuilt',
    );
    quiesce(manager);
  });

  testWidgets('through the REAL workspace: a committed seek does not rebuild '
      'the storyboard tab', (tester) async {
    // The one test here that mounts the app, because the subscription this
    // round removed lived in the WORKSPACE. The three above wire the host
    // by hand and would keep passing if it came back.
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();

    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.selectFrameIndex(0);
    await tester.pumpAndSettle();

    final painterBefore = cutBlocksPainter(tester);
    session.selectFrameIndex(3);
    await tester.pump();

    expect(session.currentFrameIndex, 3, reason: 'the seek landed');
    expect(
      identical(cutBlocksPainter(tester), painterBefore),
      isTrue,
      reason: 'an arrow press must not rebuild this tab',
    );
    quiesce(session);
  });
}
