import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/playback/frame_demand.dart'
    show FrameGhosts, standingPicturesOf;
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/a_move_lands.dart';
import '../../helpers/panel_finders.dart' show visibleCanvasPoint;
import '../../helpers/settle_async.dart';

/// the-standing-canvas-composes-a-frame-twice-before-its-picture-Q1 = B
/// (유저 2026-11-18): on the editor's own canvas, a seek and a scrub to a
/// frame whose picture is not there leave the playhead — where the
/// timeline draws it — on the frame shown, and it goes with the picture
/// (`StandsWithItsPicture`). Let go of mid-wait, a scrub lands on the
/// frame the hand let go on.
void main() {
  /// Whether every picture the canvas standing on [frame] shows is there.
  bool shown(EditorSessionManager session, int frame) {
    final pictures = session.playbackRig.framePictures;
    final standing = standingPicturesOf(
      session.activeCutOrNull!,
      frame,
      session.onionSkin.settings.value.placement,
    );
    final over = standing.over;
    return pictures.has(standing.frame) &&
        (over == null || pictures.has(over));
  }

  /// The editor standing on frame 0, a stroke on frame 0's drawing and
  /// another on frame 1's, and no picture of frame 1 kept.
  Future<EditorSessionManager> twoDrawnFrames(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    final area = tester.widget<EditorCanvasArea>(find.byType(EditorCanvasArea));
    final session = area.session;
    for (final frame in [0, 1]) {
      session.selectFrameIndex(frame);
      await theMoveLands(tester, session);
      session.createDrawingAtCurrentFrame();
      await tester.pumpAndSettle();
      final at = visibleCanvasPoint(tester) + Offset(frame * 30.0, 0);
      final pen = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      );
      await tester.pump();
      await pen.moveTo(at + const Offset(24, 6));
      await tester.pump();
      await pen.up();
      await tester.pumpAndSettle();
    }
    session.selectFrameIndex(0);
    await theMoveLands(tester, session);
    await tester.pumpAndSettle();
    expect(
      await settleAsync(tester, () => shown(session, 0)),
      isTrue,
      reason: 'premise: the canvas stands on frame 0 with its picture',
    );
    session.playbackRig.framePictures.store.letGoUnpinnedWhere((_) => true);
    expect(session.currentFrameIndex, 0, reason: 'premise');
    expect(shown(session, 0), isTrue, reason: 'premise: held where shown');
    expect(shown(session, 1), isFalse, reason: 'premise: none of frame 1');
    return session;
  }

  testWidgets('a seek stands on the frame shown till the frame sought has '
      'its picture, and the playhead goes with it', (tester) async {
    final session = await twoDrawnFrames(tester);

    session.selectFrameIndex(1);
    await tester.pump();

    expect(
      session.standsWithItsPicture.waitsFor.value,
      1,
      reason: 'premise: frame 1 has no picture yet',
    );
    expect(session.currentFrameIndex, 0);
    expect(
      session.playheadCursors.cutFrame.value,
      0,
      reason: '유저 11-15: 「재생헤드는 바꼈는데 화면이 이전그림인 순간이 있는게 '
          '어긋나는거지」',
    );

    await theMoveLands(tester, session);

    expect(session.currentFrameIndex, 1);
    expect(session.playheadCursors.cutFrame.value, 1);
    // The canvas's own key for the frame — stacked as the canvas stacks it,
    // the pen's row live — is the one the move waited for.
    final frameShown = standingPicturesOf(
      session.activeCutOrNull!,
      1,
      session.onionSkin.settings.value.placement,
    ).frame;
    final pictures = session.playbackRig.framePictures;
    final nodes = frameShown.ghosts == FrameGhosts.inPlace
        ? session.editingCanvas.stackWithItsGhosts.nodes
        : session.editingCanvas.stack.nodes;
    expect(
      pictures.store.holds(pictures.keyOfStack(nodes, frameShown)),
      isTrue,
      reason: 'the canvas takes the picture the move waited for, and makes '
          'none of its own',
    );
  });

  testWidgets('a scrub stands the same way, and let go of mid-wait it lands '
      'on the frame the hand let go on', (tester) async {
    final session = await twoDrawnFrames(tester);

    session.frameScrub.scrubFrameIndex(1);
    await tester.pump();

    expect(session.standsWithItsPicture.waitsFor.value, 1, reason: 'premise');
    expect(session.currentFrameIndex, 0);
    expect(session.playheadCursors.cutFrame.value, 0);

    session.frameScrub.commitFrameScrub();
    await theMoveLands(tester, session);

    expect(session.currentFrameIndex, 1);
    expect(session.playheadCursors.cutFrame.value, 1);
  });
}
