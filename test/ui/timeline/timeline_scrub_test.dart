import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

import '../../helpers/the_classic_rail.dart';
import 'timeline_cell_probe.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';
import '../../helpers/timeline_host.dart';

/// The ruler-scrub performance invariant (R4): drag moves ride the cursor
/// path — per-move frames go to the scrub callback WITHOUT a session
/// notify, and the pointer's release commits the selection exactly once.
void main() {
  final layers = [
    Layer(id: const LayerId('layer-1'), name: 'A', frames: const []),
  ];

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) =>
      TimelineCellExposureState.uncovered;

  testWidgets('timeline ruler drag routes moves to onScrubFrame and the '
      'release to onScrubEnd', (tester) async {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    final scrubbed = <int>[];
    final selected = <int>[];
    var scrubEnds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
hooks: TimelineGridHooks(activeLayerId: const LayerId('layer-1'),
frameCursor: cursor,
playbackFrameCount: 20,
exposureStateForLayer: stateFor,
onSelectLayer: (_) {},
onSelectFrame: selected.add,
onScrubFrame: scrubbed.add,
onScrubEnd: () => scrubEnds += 1,
onToggleLayerVisibility: (_) {},
onLayerOpacityChanged: (_, _) {},
onToggleLayerTimesheet: (_) {},
onLayerMarkSelected: (_, _) {},),
layers: layers,
),
        ),
      ),
    );

    final scrubArea = find.byKey(
      const ValueKey<String>('timeline-frame-ruler-scrub-area'),
    );
    // 24px slim cells (R-toolbar round): one cell in from the ruler start,
    // then a four-cell drag.
    final start = tester.getTopLeft(scrubArea) + const Offset(24 + 4, 20);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(24 * 4, 0));

    expect(scrubbed, containsAllInOrder(<int>[1, 5]));
    expect(selected, isEmpty, reason: 'moves must not commit');
    expect(scrubEnds, 0, reason: 'no commit before the release');

    await gesture.up();
    await tester.pumpAndSettle();

    expect(scrubEnds, 1, reason: 'the release commits exactly once');
    expect(selected, isEmpty, reason: 'commits go through onScrubEnd');
  });

  testWidgets('X-sheet frame rail drag routes moves to onScrubFrame and '
      'the release to onScrubEnd (Axis policy)', (tester) async {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    final scrubbed = <int>[];
    final selected = <int>[];
    var scrubEnds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: XSheetTimelineGrid(
hooks: TimelineGridHooks(activeLayerId: const LayerId('layer-1'),
frameCursor: cursor,
playbackFrameCount: 20,
exposureStateForLayer: stateFor,
onSelectLayer: (_) {},
onSelectFrame: selected.add,
onScrubFrame: scrubbed.add,
onScrubEnd: () => scrubEnds += 1,
onToggleLayerVisibility: (_) {},
onLayerOpacityChanged: (_, _) {},
onToggleLayerTimesheet: (_) {},
onLayerMarkSelected: (_, _) {},),
layers: layers,
),
        ),
      ),
    );

    final rail = find.byKey(
      const ValueKey<String>('xsheet-frame-rail-scrub-area'),
    );
    final cellExtent = tester
        .widget<XSheetTimelineGrid>(find.byType(XSheetTimelineGrid))
        .metrics
        .frameCellWidth;
    final start = tester.getTopLeft(rail) + Offset(10, cellExtent + 4);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(Offset(0, cellExtent * 4));

    expect(scrubbed, isNotEmpty);
    expect(selected, isEmpty, reason: 'moves must not commit');
    expect(scrubEnds, 0);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(scrubEnds, 1);
    expect(selected, isEmpty);
  });

  group('session scrub path', () {
    EditorSessionManager session() {
      return EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('scrub-project'),
          name: 'Scrub Project',
          createdAt: DateTime.utc(2026, 7, 10),
          tracks: [
            Track(
              id: const TrackId('scrub-track'),
              name: 'Video',
              cuts: [
                Cut(
                  id: const CutId('scrub-cut'),
                  name: 'Scrub Cut',
                  duration: 24,
                  canvasSize: const CanvasSize(width: 640, height: 360),
                  layers: [
                    Layer(
                      id: const LayerId('cel-a'),
                      name: 'A',
                      frames: const [],
                      timeline: const {},
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    }

    test('scrub moves never notify; the commit fires the committed-seek '
        'signal once and never a session notify', () {
      final manager = session();
      addTearDown(manager.dispose);
      var notifies = 0;
      manager.addListener(() => notifies += 1);
      final commitsBefore = manager.frameSeekCommitted.value;

      manager.frameScrub.scrubFrameIndex(5);
      manager.frameScrub.scrubFrameIndex(9);
      expect(notifies, 0, reason: 'scrub moves ride the cursor path');
      expect(manager.currentFrameIndex, 9);
      expect(manager.editingFrameCursor.value, 9);
      expect(manager.frameScrub.active.value, isTrue);
      expect(manager.frameSeekCommitted.value, commitsBefore);

      manager.frameScrub.commitFrameScrub();
      expect(
        manager.frameSeekCommitted.value,
        commitsBefore + 1,
        reason: 'the release commits exactly once',
      );
      expect(
        notifies,
        0,
        reason: 'a seek is never a session notify — nothing else rebuilds',
      );
      expect(manager.frameScrub.active.value, isFalse);
      expect(manager.currentFrameIndex, 9);
    });

    test('a same-frame scrub never engages the gesture', () {
      final manager = session();
      addTearDown(manager.dispose);

      manager.frameScrub.scrubFrameIndex(manager.currentFrameIndex);
      expect(
        manager.frameScrub.active.value,
        isFalse,
        reason: 'a plain tap is not a drag — the flag decides the GAP answer '
            'now (#26 retired the preview it used to swap in), and a tap '
            'must not turn a parked position into a live scrub',
      );

      manager.frameScrub.commitFrameScrub();
      expect(manager.frameScrub.active.value, isFalse);
    });

    test('selectFrameIndex keeps the editing cursor in sync and fires the '
        'committed-seek signal instead of a session notify', () {
      final manager = session();
      addTearDown(manager.dispose);
      var notifies = 0;
      manager.addListener(() => notifies += 1);
      final commitsBefore = manager.frameSeekCommitted.value;

      manager.selectFrameIndex(7);
      expect(manager.editingFrameCursor.value, 7);
      expect(manager.frameSeekCommitted.value, commitsBefore + 1);
      expect(notifies, 0);
    });

    testWidgets('tab host: a ruler drag moves the playhead without a '
        'session notify and commits once on release', (tester) async {
      final manager = session();
      addTearDown(manager.dispose);
      var notifies = 0;
      manager.addListener(() => notifies += 1);

      // The workspace's wrapper: a session notify rebuilds the host —
      // exactly what scrub moves must avoid.
      await pumpTimelineHostOn(
        tester,
        manager,
        surface: const Size(800, 600),
        pixelsPerFrame: 48,
      );
      await standTheClassicRail(tester);
      notifies = 0;

      final rowFinder = find.named('timeline-row-cells-cel-a');
      final rowBefore = tester.widget(rowFinder);

      final scrubArea = find.byKey(
        const ValueKey<String>('timeline-frame-ruler-scrub-area'),
      );
      final start = tester.getTopLeft(scrubArea) + const Offset(48 + 8, 20);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(48 * 4, 0));
      await tester.pump();

      expect(notifies, 0, reason: 'scrub moves must not notify the session');
      expect(manager.currentFrameIndex, 5);
      expect(
        identical(tester.widget(rowFinder), rowBefore),
        isTrue,
        reason: 'scrub moves must never rebuild cells',
      );
      // The playhead followed the pointer mid-gesture (cursor path).
      final ring = find.byKey(const ValueKey<String>('timeline-selected-cell'));
      expect(
        tester.getTopLeft(ring),
        timelineCellGlobalRect(tester, 'cel-a', 5).topLeft,
      );

      final commitsBefore = manager.frameSeekCommitted.value;
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        manager.frameSeekCommitted.value,
        commitsBefore + 1,
        reason: 'the release commits exactly once',
      );
      expect(notifies, 0, reason: 'seeks are never session notifies');
      expect(manager.currentFrameIndex, 5);
      expect(manager.frameScrub.active.value, isFalse);
    });

    /// 🚨★★★ #26 — A SCRUB SHOWS THE EDITING CANVAS, AT THE CROSSED FRAME.
    ///
    /// 「그냥 액티브레이어급으로 그냥 원본 보여주게하고싶어 … 그냥 항상 full」
    ///
    /// This replaces the test that asserted the opposite — that the canvas
    /// swapped to a composite-cache stand-in for the length of the gesture.
    /// Both halves are here because shipping only the first one is what
    /// failed on the user's build: the stand-in came out, the canvas stayed
    /// — and stayed on the frame the gesture STARTED on, so 「룰러에서 손 떼야
    /// 그림이 생기는데?」. A scrub does not notify the session, and nothing
    /// else was asking the canvas for the new frame.
    ///
    /// ⛔The last expectation is the price tag, not a nicety: the canvas
    /// follows the CURSOR now, and a drag spends most of its pointer events
    /// inside one frame's width. Those must rebuild the canvas ZERO times,
    /// or this traded a stand-in for a rebuild storm.
    ///
    /// ⚠️It pins the CHAIN, not one link — measured: today the same-frame
    /// move is already dead at the notifier (a `ValueNotifier` set to the
    /// value it holds tells nobody), so the retarget scope's own index guard
    /// never even gets asked. Removing that guard leaves this green. Both
    /// are worth having; neither is allowed to be the only one.
    testWidgets('the editing canvas stays through a scrub and retargets to '
        'the crossed frame — only when the frame changes', (tester) async {
      final manager = session();
      addTearDown(manager.dispose);
      final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
      final cameraView = ValueNotifier<bool>(false);
      final cameraDim = ValueNotifier<double>(0.5);
      addTearDown(brushTool.dispose);
      addTearDown(cameraView.dispose);
      addTearDown(cameraDim.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorCanvasArea(
              session: manager,
              brushToolState: brushTool,
              cameraViewEnabled: cameraView,
              cameraDimOpacity: cameraDim,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final stackFinder = find.byType(FramePictureView);
      FramePictureView stack() => tester.widget(stackFinder.first);

      // ⛔The gesture must already BE a scrub before the interesting part:
      // the very first move flips `frameScrub.active`, and that flag has its
      // own builder, so a canvas rebuild there proves nothing about the
      // cursor. Everything below happens with the flag already true.
      manager.frameScrub.scrubFrameIndex(4);
      await tester.pump();
      expect(
        stackFinder,
        findsWidgets,
        reason: 'the scrub shows the editing canvas — there is no stand-in '
            'to swap to any more',
      );
      expect(manager.frameScrub.active.value, isTrue, reason: 'still a scrub');
      final atFourth = stack();

      // The drag keeps going. Only the cursor fires from here.
      manager.frameScrub.scrubFrameIndex(7);
      await tester.pump();
      expect(manager.frameScrub.active.value, isTrue, reason: 'still a scrub');
      final atSeventh = stack();
      expect(
        identical(atSeventh, atFourth),
        isFalse,
        reason: 'the crossed frame retargeted the canvas MID-GESTURE — this '
            'is the work the release used to be doing',
      );

      // The pointer keeps moving inside frame 7's cell: the cursor fires,
      // the frame does not change, and the canvas must not stir.
      manager.frameScrub.scrubFrameIndex(7);
      manager.frameScrub.scrubFrameIndex(7);
      await tester.pump();
      expect(
        identical(stack(), atSeventh),
        isTrue,
        reason: 'same-frame cursor moves rebuild the canvas zero times',
      );

      manager.frameScrub.commitFrameScrub();
      await tester.pumpAndSettle();
      expect(manager.currentFrameIndex, 7);
      expect(
        stackFinder,
        findsWidgets,
        reason: 'the release changes nothing about WHAT is on screen',
      );
    });

    testWidgets('🗣️I-57 ② storyboard: a ruler drag across the cut boundary '
        'CROSSES into the next cut while the finger is down — one cut '
        'switch at the boundary, quiet per move in the gap and in the cut', (
      tester,
    ) async {
      final manager = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('cross-project'),
          name: 'Cross Project',
          createdAt: DateTime.utc(2026, 7, 30),
          tracks: [
            Track(
              id: const TrackId('cross-track'),
              name: 'Video',
              cuts: [
                Cut(
                  id: const CutId('cut-a'),
                  name: 'A',
                  duration: 24,
                  canvasSize: const CanvasSize(width: 640, height: 360),
                  layers: [
                    Layer(
                      id: const LayerId('a-cel'),
                      name: 'A1',
                      frames: const [],
                    ),
                  ],
                ),
                Cut(
                  id: const CutId('cut-b'),
                  name: 'B',
                  duration: 24,
                  leadingGapFrames: 6,
                  canvasSize: const CanvasSize(width: 640, height: 360),
                  layers: [
                    Layer(
                      id: const LayerId('b-cel'),
                      name: 'B1',
                      frames: const [],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(manager.dispose);
      var notifies = 0;
      manager.addListener(() => notifies += 1);

      await pumpStoryboardHostOn(
        tester,
        manager,
        surface: const Size(800, 600),
        pixelsPerFrame: 8,
      );
      notifies = 0;

      final ruler = find.byKey(const ValueKey<String>('storyboard-ruler'));
      final start = tester.getTopLeft(ruler) + const Offset(8 * 2 + 4, 10);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(8 * 24, 0)); // into the gap [24,30)
      await tester.pump();

      expect(notifies, 0, reason: 'moves in the gap rebuild no panel');
      expect(
        manager.activeCutId,
        const CutId('cut-a'),
        reason: 'a gap is no cut to cross into — the drag left A behind',
      );
      expect(
        manager.editingSession.gapGlobalFrame,
        isNotNull,
        reason: 'the playhead follows through the parking notifier',
      );

      await gesture.moveBy(const Offset(8 * 9, 0)); // over cut-b [30,54)
      await tester.pump();
      expect(
        manager.activeCutId,
        const CutId('cut-b'),
        reason: 'the boundary crossed IS the cut switch — before the release',
      );
      expect(manager.editingSession.gapGlobalFrame, isNull);
      expect(notifies, 1, reason: 'ONE switch at the boundary');

      await gesture.moveBy(const Offset(8 * 3, 0)); // further into cut-b
      await tester.pump();
      expect(notifies, 1, reason: 'moves inside the cut stay quiet');

      await gesture.up();
      await tester.pumpAndSettle();

      expect(manager.activeCutId, const CutId('cut-b'));
      expect(manager.editingSession.gapGlobalFrame, isNull);
    });

    testWidgets('storyboard: a ruler drag scrubs the active cut on the '
        'cursor path and commits once on release', (tester) async {
      final manager = session();
      addTearDown(manager.dispose);
      var notifies = 0;
      manager.addListener(() => notifies += 1);

      // ↩️The wrapper here rebuilt the host on every cursor move too, and
      // called that the workspace's — whose merge never held the cursor:
      // the playhead rides its own channel.
      await pumpStoryboardHostOn(
        tester,
        manager,
        surface: const Size(800, 600),
        pixelsPerFrame: 12,
      );
      notifies = 0;

      final ruler = find.byKey(const ValueKey<String>('storyboard-ruler'));
      final start = tester.getTopLeft(ruler) + const Offset(12 * 2 + 4, 10);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(12 * 6, 0));
      await tester.pump();

      expect(
        notifies,
        0,
        reason: 'storyboard scrub moves ride the cursor path',
      );
      expect(manager.currentFrameIndex, greaterThan(2));
      expect(manager.frameScrub.active.value, isTrue);

      final commitsBefore = manager.frameSeekCommitted.value;
      await gesture.up();
      await tester.pumpAndSettle();

      expect(manager.frameSeekCommitted.value, commitsBefore + 1);
      expect(notifies, 0, reason: 'seeks are never session notifies');
      expect(manager.frameScrub.active.value, isFalse);
    });
  });

  group('global scrub across cut boundaries', () {
    // cut-a [0,24), gap [24,30), cut-b [30,54).
    EditorSessionManager twoCutSession() {
      return EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('cross-project'),
          name: 'Cross Project',
          createdAt: DateTime.utc(2026, 7, 30),
          tracks: [
            Track(
              id: const TrackId('cross-track'),
              name: 'Video',
              cuts: [
                Cut(
                  id: const CutId('cut-a'),
                  name: 'A',
                  duration: 24,
                  canvasSize: const CanvasSize(width: 640, height: 360),
                  layers: [
                    Layer(
                      id: const LayerId('a-cel'),
                      name: 'A1',
                      frames: const [],
                    ),
                  ],
                ),
                Cut(
                  id: const CutId('cut-b'),
                  name: 'B',
                  duration: 24,
                  leadingGapFrames: 6,
                  canvasSize: const CanvasSize(width: 640, height: 360),
                  layers: [
                    Layer(
                      id: const LayerId('b-cel'),
                      name: 'B1',
                      frames: const [],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    }

    test('🗣️I-57 ②: the move that reaches another cut IS the cut switch — '
        'one notify and one landing at the boundary, the gap before it and '
        'the cut after it quiet, and the release lands where it stands', () {
      final manager = twoCutSession();
      addTearDown(manager.dispose);
      var notifies = 0;
      manager.addListener(() => notifies += 1);
      final commitsBefore = manager.frameSeekCommitted.value;

      manager.frameScrub.scrubGlobalFrame(5); // in-cut: the cursor path
      manager.frameScrub.scrubGlobalFrame(26); // the gap: parked, quiet
      expect(notifies, 0);
      expect(manager.frameSeekCommitted.value, commitsBefore);
      expect(manager.activeCutId, const CutId('cut-a'));
      expect(manager.editingSession.gapGlobalFrame, 26);

      manager.frameScrub.scrubGlobalFrame(35); // cut-b: the crossing
      expect(manager.activeCutId, const CutId('cut-b'));
      expect(manager.currentFrameIndex, 5, reason: '35 - cut-b start 30');
      expect(manager.editingSession.gapGlobalFrame, isNull);
      expect(notifies, 1, reason: 'ONE cut switch at the boundary');
      expect(
        manager.frameSeekCommitted.value,
        commitsBefore + 1,
        reason: 'one landing — no from-the-gap frame-0 detour',
      );

      manager.frameScrub.scrubGlobalFrame(36); // inside cut-b
      expect(notifies, 1, reason: 'moves inside the cut stay quiet');
      expect(manager.frameSeekCommitted.value, commitsBefore + 1);
      expect(manager.frameScrub.active.value, isTrue);

      manager.frameScrub.commitFrameScrub();
      expect(manager.activeCutId, const CutId('cut-b'));
      expect(manager.currentFrameIndex, 6);
      expect(notifies, 1, reason: 'the release lands where it stands');
      expect(manager.frameScrub.active.value, isFalse);
    });

    test('a press on another cut\'s frames crosses into it on the DOWN — and '
        'only a MOVE engages the live scrub (a tap is a cut switch, never a '
        'live scrub)', () {
      final manager = twoCutSession();
      addTearDown(manager.dispose);

      manager.frameScrub.scrubGlobalFrame(40); // pointer-down over cut-b
      expect(manager.activeCutId, const CutId('cut-b'));
      expect(manager.currentFrameIndex, 10, reason: '40 - cut-b start 30');
      expect(manager.frameScrub.active.value, isFalse, reason: 'a down alone');
      expect(manager.editingSession.gapGlobalFrame, isNull);
      manager.frameScrub.scrubGlobalFrame(41); // an actual drag move engages
      expect(manager.frameScrub.active.value, isTrue);
      manager.frameScrub.commitFrameScrub();
      expect(manager.activeCutId, const CutId('cut-b'));
      expect(manager.currentFrameIndex, 11);
    });

    // 🗣️I-57-Q1 memo (유저 10-08): 「컷 안 선택 풀려도 됨 … 콘티패널 ·
    // 글로벌 선택만 남으면 됨」.
    testWidgets('a crossing keeps the TRACK\'s selection — the rows the '
        'conte panel selects — whether a scrub or a run makes it', (
      tester,
    ) async {
      final manager = twoCutSession();
      addTearDown(manager.dispose);
      manager.updateTrackRowRangeSelectionByFrame(
        layerId: manager.activeTrack.transitionLayer.id,
        anchorGlobalFrame: 2,
        headGlobalFrame: 40,
      );
      final held = manager.trackFrameRangeSelection.value;
      expect(held, isNotNull, reason: 'fixture');

      manager.frameScrub.scrubGlobalFrame(5);
      manager.frameScrub.scrubGlobalFrame(35); // cut-b: the crossing
      expect(manager.activeCutId, const CutId('cut-b'), reason: 'fixture');
      expect(manager.trackFrameRangeSelection.value, same(held));
      manager.frameScrub.commitFrameScrub();
      expect(manager.trackFrameRangeSelection.value, same(held));

      final playback = manager.playbackRig.playback;
      playback.play(scope: PlaybackScope.allCuts);
      playback.seekToGlobalFrame(5); // back into cut-a
      // A run's crossing lands once its frame is out (I-57, 10-13).
      await tester.pump();
      expect(manager.activeCutId, const CutId('cut-a'), reason: 'fixture');
      expect(manager.trackFrameRangeSelection.value, same(held));
      playback.stop();
      expect(manager.trackFrameRangeSelection.value, same(held));
      await tester.pumpAndSettle();
    });

    test('a same-frame tap on an already-parked position never engages '
        'the scrub', () {
      final manager = twoCutSession();
      addTearDown(manager.dispose);
      manager.frameScrub.scrubGlobalFrame(26);
      manager.frameScrub.commitFrameScrub(); // parked in the gap, no active cut
      expect(manager.activeCutId, isNull);
      expect(manager.frameScrub.active.value, isFalse);

      manager.frameScrub.scrubGlobalFrame(26); // the same parked frame again
      expect(manager.frameScrub.active.value, isFalse);
      manager.frameScrub.commitFrameScrub();
      expect(manager.editingSession.gapGlobalFrame, 26);
    });
  });
}
