import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/services/playback/frame_demand.dart'
    show FrameGhosts, standingPicturesOf;
import 'package:anicel/src/ui/brush/brush_tool_state.dart' show CanvasTool;
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart'
    show FramePictureKey;
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart'
    show nothingOnItsWay, theFrameIsShown;
import '../../helpers/a_move_lands.dart';
import '../../helpers/home_page_probes.dart' show showStoryboardPanel;
import '../../helpers/named_finders.dart';
import '../../helpers/panel_finders.dart'
    show mainCanvasPanel, visibleCanvasPoint;
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

  /// The key of the picture the canvas standing on [frame] of the cut open
  /// shows — the frame stacked as the canvas stacks it, the pen's row live.
  FramePictureKey keyShownAt(EditorSessionManager session, int frame) {
    final frameShown = standingPicturesOf(
      session.activeCutOrNull!,
      frame,
      session.onionSkin.settings.value.placement,
    ).frame;
    final nodes = frameShown.ghosts == FrameGhosts.inPlace
        ? session.editingCanvas.stackWithItsGhosts.nodes
        : session.editingCanvas.stack.nodes;
    return session.playbackRig.framePictures.keyOfStack(nodes, frameShown);
  }

  /// A stroke on the drawing of the frame stood on, [dx] right of the
  /// middle of the canvas.
  Future<void> strokeAt(WidgetTester tester, double dx) async {
    final at = visibleCanvasPoint(tester) + Offset(dx, 0);
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

  /// The app open on the first of two cuts, a stroke on the second cut's
  /// frame 0 — the key its canvas opens with, [opensWith] — and no picture
  /// of it kept: a move into it waits.
  Future<
    ({
      EditorSessionManager session,
      CutId first,
      CutId second,
      FramePictureKey opensWith,
    })
  >
  inTheFirstOfTwoCuts(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    final area = tester.widget<EditorCanvasArea>(find.byType(EditorCanvasArea));
    final session = area.session;
    final first = session.activeCutId!;
    session.cutVerbs.createCut();
    await tester.pumpAndSettle();
    final second = session.repository.requireProject().tracks.first.cuts
        .firstWhere((cut) => cut.id != first)
        .id;
    session.selectCut(second);
    await theMoveLands(tester, session);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    await strokeAt(tester, 0);
    final opensWith = keyShownAt(session, 0);
    session.selectCut(first);
    await theMoveLands(tester, session);
    await tester.pumpAndSettle();
    session.playbackRig.framePictures.store.letGoUnpinnedWhere((_) => true);
    return (
      session: session,
      first: first,
      second: second,
      opensWith: opensWith,
    );
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
      await strokeAt(tester, frame * 30.0);
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
    final pictures = session.playbackRig.framePictures;
    expect(
      pictures.store.holds(keyShownAt(session, 1)),
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

  testWidgets('a cut switch stands in the cut shown till the frame it goes '
      'to has its picture, and goes with it (Q3 = stand, 유저 11-18 「컷도 앞 '
      '컷에 서 있는다」)', (tester) async {
    final (:session, :first, :second, :opensWith) = await inTheFirstOfTwoCuts(
      tester,
    );
    final pictures = session.playbackRig.framePictures;
    final rowStood = session.activeLayerId;

    session.selectCut(second);
    await tester.pump();

    expect(
      session.standsWithItsPicture.cutWaitedFor,
      second,
      reason: "premise: the second cut's frame has no picture yet",
    );
    expect(session.activeCutId, first, reason: 'the cut shown stands');
    expect(session.activeLayerId, rowStood, reason: 'and its row');
    await theMoveLands(tester, session);

    expect(session.activeCutId, second);
    expect(session.currentFrameIndex, 0);
    expect(keyShownAt(session, 0), opensWith);
    expect(
      pictures.store.holds(opensWith),
      isTrue,
      reason: 'the canvas takes the picture the switch waited for, and '
          'makes none of its own',
    );
  });

  testWidgets('a scrub let go while its crossing into another cut waits '
      'lands in that cut, on the frame it crossed to — not as a move in '
      'the cut it left (Q3 = stand)', (tester) async {
    final (:session, first: _, :second, opensWith: _) =
        await inTheFirstOfTwoCuts(tester);

    session.frameScrub.scrubGlobalFrame(0);
    await theMoveLands(tester, session);
    session.frameScrub.scrubGlobalFrame(
      session.trackFrameAxis().entryFor(second)!.startFrame,
    );
    await tester.pump();
    expect(
      session.standsWithItsPicture.cutWaitedFor,
      second,
      reason: '⛔premise: the crossing waits',
    );
    session.frameScrub.commitFrameScrub();
    await theMoveLands(tester, session);

    expect(session.activeCutId, second);
    expect(session.currentFrameIndex, 0);
  });

  testWidgets('🗣️a cut a command opens: the canvas stands bare till its '
      'picture comes, not on the cut it left (Q5 = blank, 유저 11-18 「빈 '
      '종이로 기다린다」)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    final area = tester.widget<EditorCanvasArea>(find.byType(EditorCanvasArea));
    final session = area.session;
    final first = session.activeCutId!;
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    await strokeAt(tester, 0);
    session.cutVerbs.createCut();
    await tester.pumpAndSettle();
    final second = session.repository.requireProject().tracks.first.cuts
        .firstWhere((cut) => cut.id != first)
        .id;
    session.selectCut(second);
    await theMoveLands(tester, session);
    await theFrameIsShown(tester, within: mainCanvasPanel());
    session.playbackRig.framePictures.store.letGoUnpinnedWhere((_) => true);

    session.cutVerbs.deleteActiveCut();
    await tester.pump();

    expect(
      session.activeCutId,
      first,
      reason: '⛔premise: the command opened the cut before it',
    );
    expect(
      nothingOnItsWay(tester, within: mainCanvasPanel()),
      isFalse,
      reason: 'bare till its picture comes',
    );
    await theFrameIsShown(tester, within: mainCanvasPanel());
  });

  testWidgets('a storyboard lane cell double clicked in a cut whose picture '
      'is still to come keys the cell the move lands on — nothing in the '
      'cut it waits in (Q3 = stand)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (:session, :first, :second, opensWith: _) =
        await inTheFirstOfTwoCuts(tester);
    final se = session.activeTrack.seLayers.first.id;
    Set<int> keyed() => session.activeTrack.seLayers
        .firstWhere((layer) => layer.id == se)
        .transformTrack
        .keyedFrames;
    await showStoryboardPanel(tester);
    for (final toggle in [
      'storyboard-lane-toggle-${se.value}',
      // An S row's pose is its name tag's (audio-fx-grows-like-the-pros-Q3).
      'storyboard-lane-group-toggle-${se.value}-name-tag-group',
    ]) {
      await tester.ensureVisible(find.named(toggle));
      await tester.pumpAndSettle();
      await tester.tap(find.named(toggle));
      await tester.pumpAndSettle();
    }
    session.standOnRow(
      LaneRowAddress(se, 'position'),
      panel: WorkingPanel.storyboard,
      globalFrameIndex: 0,
    );
    await tester.pumpAndSettle();
    final into = session.trackFrameAxis().entryFor(second)!.startFrame;
    expect(keyed(), isEmpty, reason: '⛔premise');
    // The panel's pumps warmed what lies near: none of it kept.
    session.playbackRig.framePictures.store.letGoUnpinnedWhere((_) => true);

    tester
        .widget<TimelineLaneFrameRow>(
          find.descendant(
            of: find.byType(StoryboardTabHost),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is TimelineLaneFrameRow &&
                  widget.layer.id == se &&
                  widget.lane.laneId == 'position',
            ),
          ),
        )
        .laneRange!
        .onActivateAt!(se, 'position', into);
    await tester.pump();

    expect(
      session.activeCutId,
      first,
      reason: '⛔premise: the move waits for its picture',
    );
    expect(keyed(), isEmpty, reason: 'the cell opens in its turn');
    await theMoveLands(tester, session);
    await tester.pumpAndSettle();
    expect(session.activeCutId, second);
    expect(keyed(), {into});
  });

  /// The frames [session]'s playhead stands on from now, in turn.
  List<int> framesStoodOn(EditorSessionManager session) {
    final cursor = session.playheadCursors.cutFrame;
    final stood = <int>[];
    void moved() => stood.add(cursor.value);
    cursor.addListener(moved);
    addTearDown(() => cursor.removeListener(moved));
    return stood;
  }

  testWidgets('the flip key pressed twice while a move waits walks two '
      'frames, each stood on in turn (유저 11-18 14:02, as TVPaint)', (
    tester,
  ) async {
    final session = await twoDrawnFrames(tester);
    final stood = framesStoodOn(session);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);

    expect(
      session.standsWithItsPicture.waitsFor.value,
      1,
      reason: 'premise: frame 1 has no picture yet',
    );
    expect(session.currentFrameIndex, 0);
    await theMoveLands(tester, session);
    expect(
      await settleAsync(tester, () => session.currentFrameIndex == 2),
      isTrue,
      reason: 'the second press is a step of its own',
    );
    expect(stood, [1, 2]);
  });

  testWidgets('the flip key held walks as the pictures come: a repeat '
      'that comes while a move waits is not lined up (Q4 = 1)', (
    tester,
  ) async {
    final session = await twoDrawnFrames(tester);
    final stood = framesStoodOn(session);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    expect(
      session.standsWithItsPicture.waitsFor.value,
      1,
      reason: 'premise: the press waits for frame 1',
    );
    await theMoveLands(tester, session);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(stood, [1], reason: 'let go, it stands where it came');
  });

  testWidgets('🗣️a key pressed while a move waits acts once it lands, where '
      'it lands: Ctrl+Z takes back the edit made on that frame (Q6 = '
      'turn)', (tester) async {
    final session = await twoDrawnFrames(tester);
    final history = session.historyManager;
    final edits = history.undoCount;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(
      session.standsWithItsPicture.waitsFor.value,
      1,
      reason: '⛔premise: the press waits for frame 1',
    );
    expect(history.undoCount, edits, reason: 'in its turn');
    await theMoveLands(tester, session);
    expect(
      await settleAsync(tester, () => history.undoCount == edits - 1),
      isTrue,
      reason: "frame 1's stroke taken back, not a walk to it from frame 0",
    );
    expect(session.currentFrameIndex, 1);
  });

  testWidgets('…and a tool key pressed meanwhile takes up its tool once the '
      'move lands (Q6 = turn)', (tester) async {
    final session = await twoDrawnFrames(tester);
    final tool = tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .brushToolState;
    expect(tool.value.tool, isNot(CanvasTool.eraser), reason: '⛔premise');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);

    expect(
      session.standsWithItsPicture.waitsFor.value,
      1,
      reason: '⛔premise: the press waits for frame 1',
    );
    expect(tool.value.tool, isNot(CanvasTool.eraser), reason: 'in its turn');
    await theMoveLands(tester, session);
    expect(
      await settleAsync(tester, () => tool.value.tool == CanvasTool.eraser),
      isTrue,
    );
  });
}
