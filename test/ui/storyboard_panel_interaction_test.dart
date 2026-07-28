import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/storyboard_cut_thumbnail_store.dart'
    show StoryboardThumbnailResolver;
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/storyboard_timeline_layout.dart';
import 'storyboard_cut_block_probe.dart';
import 'timeline/timeline_row_chrome_probe.dart';

void main() {
  group('StoryboardPanel cut selection interactions', () {
    testWidgets('tapping an inactive cut calls onCutSelected once', (
      tester,
    ) async {
      final selectedCutIds = <CutId>[];

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: selectedCutIds.add,
      );

      await tester.tapAt(cutBlockCenter(tester, 'cut-b'));
      await tester.pumpAndSettle();

      expect(selectedCutIds, [const CutId('cut-b')]);
    });

    testWidgets('a press in a GAP announces no cut', (tester) async {
      final selectedCutIds = <CutId>[];

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          // A 10-frame gap sits before cut-b.
          _cut('cut-b', name: 'Cut B').copyWith(leadingGapFrames: 10),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: selectedCutIds.add,
      );

      // 8 px/frame: cut-a spans frames 0..23, the gap 24..33.
      final blockA = cutBlockScreenRect(tester, 'cut-a');
      final gesture = await tester.startGesture(
        blockA.topLeft + const Offset(8 * 28.0, 10),
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(selectedCutIds, isEmpty);
    });

    testWidgets('cut selection works across multiple tracks', (tester) async {
      final selectedCutIds = <CutId>[];

      await _pumpStoryboardPanel(
        tester,
        _project([
          Track(
            id: const TrackId('track-a'),
            name: 'V1',
            cuts: [_cut('cut-a', name: 'Cut A')],
          ),
          Track(
            id: const TrackId('track-b'),
            name: 'V2',
            cuts: [_cut('cut-b', name: 'Cut B')],
          ),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: selectedCutIds.add,
      );

      await tester.tapAt(cutBlockCenter(tester, 'cut-b'));
      await tester.pumpAndSettle();

      expect(selectedCutIds, [const CutId('cut-b')]);
    });

    testWidgets('selection uses CutId identity, not cut name', (tester) async {
      final selectedCutIds = <CutId>[];

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Duplicate Cut'),
          _cut('cut-b', name: 'Duplicate Cut'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: selectedCutIds.add,
      );

      await tester.tapAt(cutBlockCenter(tester, 'cut-b'));
      await tester.pumpAndSettle();

      expect(
        cutBlocks(
          tester,
        ).where((block) => block.title == 'Duplicate Cut').length,
        2,
      );
      expect(selectedCutIds, [const CutId('cut-b')]);
    });

    testWidgets(
      'storyboard layer presence does not change inactive cut selection',
      (tester) async {
        final selectedCutIds = <CutId>[];

        await _pumpStoryboardPanel(
          tester,
          _singleTrackProject([
            _cut(
              'cut-a',
              name: 'Cut A',
              layers: [_storyboardLayer('storyboard-a')],
            ),
            _cut('cut-b', name: 'Cut B'),
          ]),
          activeCutId: const CutId('cut-a'),
          onCutSelected: selectedCutIds.add,
        );

        expect(requireCutBlock(tester, 'cut-a').hasStoryboardLayer, isTrue);
        expect(requireCutBlock(tester, 'cut-b').hasStoryboardLayer, isFalse);

        await tester.tapAt(cutBlockCenter(tester, 'cut-b'));
        await tester.pumpAndSettle();

        expect(selectedCutIds, [const CutId('cut-b')]);
      },
    );

    testWidgets(
      'storyboard layer absence does not change inactive cut selection',
      (tester) async {
        final selectedCutIds = <CutId>[];

        await _pumpStoryboardPanel(
          tester,
          _singleTrackProject([
            _cut('cut-a', name: 'Cut A'),
            _cut('cut-b', name: 'Cut B'),
          ]),
          activeCutId: const CutId('cut-a'),
          onCutSelected: selectedCutIds.add,
        );

        expect(requireCutBlock(tester, 'cut-a').hasStoryboardLayer, isFalse);
        expect(requireCutBlock(tester, 'cut-b').hasStoryboardLayer, isFalse);

        await tester.tapAt(cutBlockCenter(tester, 'cut-b'));
        await tester.pumpAndSettle();

        expect(selectedCutIds, [const CutId('cut-b')]);
      },
    );
  });

  group('StoryboardPanel cut drag', () {
    testWidgets('a drag on a cut SLIDES it (R10-④): begin → whole-frame '
        'updates → end', (tester) async {
      final began = <CutId>[];
      final updates = <int>[];
      var ended = 0;

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
        cutMove: StoryboardCutMoveCallbacks(
          onBegin: (cutId) {
            began.add(cutId);
            return true;
          },
          onUpdate: updates.add,
          onEnd: () => ended += 1,
          onCancel: () {},
        ),
      );

      // Drag the SECOND block 40px right at 8 px/frame = +5 frames.
      // MOUSE: the shared range gesture uses the timeline's edit-pan
      // device policy, where a finger scrolls unless the user says
      // otherwise.
      final block = cutBlockScreenRect(tester, 'cut-b');
      final gesture = await tester.startGesture(
        block.center,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(began, [const CutId('cut-b')]);
      expect(updates, isNotEmpty);
      expect(updates.last, 5);
      expect(ended, 1);
    });

    testWidgets('a drag that starts in a GAP begins no slide', (tester) async {
      final began = <CutId>[];

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B').copyWith(leadingGapFrames: 10),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
        cutMove: StoryboardCutMoveCallbacks(
          onBegin: (cutId) {
            began.add(cutId);
            return true;
          },
          onUpdate: (_) {},
          onEnd: () {},
          onCancel: () {},
        ),
      );

      final blockA = cutBlockScreenRect(tester, 'cut-a');
      final gesture = await tester.startGesture(
        blockA.topLeft + const Offset(8 * 28.0, 10),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(began, isEmpty);
    });

    testWidgets('the slide still works when the cut carries fx transform '
        'keys (R12-⑧)', (tester) async {
      final began = <CutId>[];
      final updates = <int>[];

      final keyed = Cut(
        id: const CutId('cut-b'),
        name: 'Cut B',
        duration: 24,
        canvasSize: const CanvasSize(width: 1280, height: 720),
        layers: [_animationLayer('animation-cut-b')],
        transformTrack: TransformTrack(
          keyframes: {
            0: TransformPose(
              center: CanvasPoint(x: 640, y: 360),
              zoom: 1.2,
              rotationDegrees: 0,
            ),
            12: TransformPose(
              center: CanvasPoint(x: 700, y: 360),
              zoom: 1.0,
              rotationDegrees: 5,
            ),
          },
        ),
      );
      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([_cut('cut-a', name: 'Cut A'), keyed]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
        cutMove: StoryboardCutMoveCallbacks(
          onBegin: (cutId) {
            began.add(cutId);
            return true;
          },
          onUpdate: updates.add,
          onEnd: () {},
          onCancel: () {},
        ),
      );

      final block = cutBlockScreenRect(tester, 'cut-b');
      final gesture = await tester.startGesture(
        block.center,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(began, [const CutId('cut-b')]);
      expect(updates, isNotEmpty);
      expect(updates.last, 5);
    });

    testWidgets('with cutSelect a drag on an UNSELECTED cut paints a '
        'run selection instead of sliding (UI-R18 #1)', (tester) async {
      final selection = ValueNotifier<TrackFrameRangeSelection?>(null);
      addTearDown(selection.dispose);
      final dragSteps = <(TrackId, int, int)>[];
      final began = <CutId>[];

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
          _cut('cut-c', name: 'Cut C'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
        cutMove: StoryboardCutMoveCallbacks(
          onBegin: (cutId) {
            began.add(cutId);
            return true;
          },
          onUpdate: (_) {},
          onEnd: () {},
          onCancel: () {},
        ),
        cutSelect: StoryboardCutSelectCallbacks(
          selectedRange: selection,
          onDrag:
              ({
                required TrackId trackId,
                required int anchorGlobalFrame,
                required int headGlobalFrame,
                int headRowDelta = 0,
              }) {
                dragSteps.add((trackId, anchorGlobalFrame, headGlobalFrame));
              },
          onClear: () => selection.value = null,
        ),
      );

      // Sweep from the middle of cut-a (frame 12) across into cut-b: the
      // anchor holds, the head follows the pointer's FRAME. No slide
      // begins. 24-frame cuts at 8 px/frame → cut-b starts at frame 24.
      final blockA = cutBlockScreenRect(tester, 'cut-a');
      final gesture = await tester.startGesture(
        blockA.topLeft + const Offset(8 * 12.0 + 4, 10),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(8 * 20.0, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(began, isEmpty);
      expect(dragSteps, isNotEmpty);
      expect(dragSteps.first, (const TrackId('track-a'), 12, 12));
      expect(dragSteps.last, (const TrackId('track-a'), 12, 32));
    });

    testWidgets('a drag starting in a GAP still paints a run — the gesture '
        'covers the row, not the blocks', (tester) async {
      final selection = ValueNotifier<TrackFrameRangeSelection?>(null);
      addTearDown(selection.dispose);
      final dragSteps = <(int, int)>[];

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B').copyWith(leadingGapFrames: 10),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
        cutSelect: StoryboardCutSelectCallbacks(
          selectedRange: selection,
          onDrag:
              ({
                required TrackId trackId,
                required int anchorGlobalFrame,
                required int headGlobalFrame,
                int headRowDelta = 0,
              }) {
                dragSteps.add((anchorGlobalFrame, headGlobalFrame));
              },
          onClear: () => selection.value = null,
        ),
      );

      // Press at frame 28 — inside the gap between the cuts, where no
      // block exists — and sweep right into cut-b (frame 34 onward).
      final blockA = cutBlockScreenRect(tester, 'cut-a');
      final gesture = await tester.startGesture(
        blockA.topLeft + const Offset(8 * 28.0, 10),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(8 * 10.0, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(dragSteps.first, (28, 28));
      expect(dragSteps.last, (28, 38));
    });

    testWidgets('a body drag starting INSIDE the selection slides the run '
        'through cutMove (UI-R18 #1)', (tester) async {
      // Both 24-frame cuts: the run is the range [0,48) on the track axis.
      final selection = ValueNotifier<TrackFrameRangeSelection?>(
        const TrackFrameRangeSelection(
          trackId: TrackId('track-a'),
          anchorRow: TrackRowAddress(TrackId('track-a')),
          startFrame: 0,
          endFrameExclusive: 48,
        ),
      );
      addTearDown(selection.dispose);
      final began = <CutId>[];
      final updates = <int>[];
      var selectDrags = 0;

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
        cutMove: StoryboardCutMoveCallbacks(
          onBegin: (cutId) {
            began.add(cutId);
            return true;
          },
          onUpdate: updates.add,
          onEnd: () {},
          onCancel: () {},
        ),
        cutSelect: StoryboardCutSelectCallbacks(
          selectedRange: selection,
          onDrag:
              ({
                required TrackId trackId,
                required int anchorGlobalFrame,
                required int headGlobalFrame,
                int headRowDelta = 0,
              }) => selectDrags += 1,
          onClear: () => selection.value = null,
        ),
      );

      final blockA = cutBlockScreenRect(tester, 'cut-a');
      final gesture = await tester.startGesture(
        blockA.center,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(selectDrags, 0);
      expect(began, [const CutId('cut-a')]);
      expect(updates, isNotEmpty);
      expect(updates.last, 5);
    });

    testWidgets('tapping a V-row label selects its TRACK (UI-R18 #6)', (
      tester,
    ) async {
      final selectedTracks = <TrackId>[];

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([_cut('cut-a', name: 'Cut A')]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
        onSelectTrack: selectedTracks.add,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('storyboard-track-select-track-a')),
      );
      await tester.pumpAndSettle();

      expect(selectedTracks, [const TrackId('track-a')]);
    });

    testWidgets('while a selection is live a tap clears it — even on the '
        'ACTIVE cut (UI-R18 #1)', (tester) async {
      // cut-b alone: the second 24-frame cut is the range [24,48).
      final selection = ValueNotifier<TrackFrameRangeSelection?>(
        const TrackFrameRangeSelection(
          trackId: TrackId('track-a'),
          anchorRow: TrackRowAddress(TrackId('track-a')),
          startFrame: 24,
          endFrameExclusive: 48,
        ),
      );
      addTearDown(selection.dispose);
      var clears = 0;
      final selectedCuts = <CutId>[];

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: selectedCuts.add,
        cutSelect: StoryboardCutSelectCallbacks(
          selectedRange: selection,
          onDrag:
              ({
                required TrackId trackId,
                required int anchorGlobalFrame,
                required int headGlobalFrame,
                int headRowDelta = 0,
              }) {},
          onClear: () {
            clears += 1;
            selection.value = null;
          },
        ),
      );

      // Tap an UNSELECTED cut while cut-b is selected: the press picks the
      // cut, the release clears the selection (the timeline cell contract).
      await tester.tapAt(cutBlockCenter(tester, 'cut-a'));
      await tester.pumpAndSettle();

      expect(clears, 1);
      expect(selectedCuts, [const CutId('cut-a')]);
    });

    testWidgets('a press INSIDE the selection picks no cut — it is starting '
        'a move, not choosing (UI-R10 #12)', (tester) async {
      // cut-b alone: the second 24-frame cut is the range [24,48).
      final selection = ValueNotifier<TrackFrameRangeSelection?>(
        const TrackFrameRangeSelection(
          trackId: TrackId('track-a'),
          anchorRow: TrackRowAddress(TrackId('track-a')),
          startFrame: 24,
          endFrameExclusive: 48,
        ),
      );
      addTearDown(selection.dispose);
      final selectedCuts = <CutId>[];

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: selectedCuts.add,
        cutSelect: StoryboardCutSelectCallbacks(
          selectedRange: selection,
          onDrag:
              ({
                required TrackId trackId,
                required int anchorGlobalFrame,
                required int headGlobalFrame,
                int headRowDelta = 0,
              }) {},
          onClear: () => selection.value = null,
        ),
      );

      await tester.tapAt(cutBlockCenter(tester, 'cut-b'));
      await tester.pumpAndSettle();

      expect(selectedCuts, isEmpty);
    });

    testWidgets('the ruler PRESS itself scrubs and the release commits '
        'once — the timeline scheme (UI-R18 #13)', (tester) async {
      final scrubbed = <int>[];
      var ends = 0;

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
        onScrubGlobalFrame: scrubbed.add,
        onScrubEnd: () => ends += 1,
      );

      final ruler = find.byKey(const ValueKey<String>('storyboard-ruler'));
      // Press on frame 4 (8 px/frame): the DOWN scrubs immediately.
      final gesture = await tester.startGesture(
        tester.getTopLeft(ruler) + const Offset(8 * 4 + 4, 10),
      );
      await tester.pump();
      expect(scrubbed, [4], reason: 'the press itself scrubs');
      expect(ends, 0);

      await gesture.moveBy(const Offset(8 * 3, 0));
      await tester.pump();
      expect(scrubbed.last, 7);
      expect(ends, 0, reason: 'moves never commit');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(ends, 1, reason: 'the raw release commits exactly once');

      // A plain TAP scrubs + commits too (the timeline behavior).
      await tester.tapAt(
        tester.getTopLeft(ruler) + const Offset(8 * 9 + 4, 10),
      );
      await tester.pumpAndSettle();
      expect(scrubbed.last, 9);
      expect(ends, 2);
    });

    testWidgets('the end line drags the MOVIE length (UI-R20 #3) — the '
        'trailing gap, never a cut trim', (tester) async {
      var begins = 0;
      final updates = <int>[];
      var ends = 0;
      final trims = <CutId>[];

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
        stripEdges: StoryboardStripEdgeCallbacks(
          onCutEdgeBegin: (cutId, edge) {
            trims.add(cutId);
            return true;
          },
          onDivisionBegin: (_, _) => false,
          onUpdate: (_) {},
          onEnd: () {},
          onCancel: () {},
        ),
        movieEnd: StoryboardMovieEndCallbacks(
          onBegin: () {
            begins += 1;
            return true;
          },
          onUpdate: updates.add,
          onEnd: () => ends += 1,
          onCancel: () {},
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('storyboard-cut-end-line')),
        findsOneWidget,
      );
      final handle = find.byKey(
        const ValueKey<String>('storyboard-cut-end-handle'),
      );
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await gesture.moveBy(const Offset(32, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // +32px at 8 px/frame = the movie grows 4 frames of trailing gap.
      expect(begins, 1);
      expect(updates, isNotEmpty);
      expect(updates.last, 4);
      expect(ends, 1);
      expect(trims, isEmpty, reason: 'no cut is ever trimmed by the end line');
    });

    testWidgets('nothing lifts a block any more — reordering is the move '
        'drag reaching past a neighbour', (tester) async {
      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
      );

      expect(find.byType(LongPressDraggable<CutId>), findsNothing);
      expect(find.byType(DragTarget<CutId>), findsNothing);
    });

    testWidgets('ruler tap seeks the frame under the pointer', (tester) async {
      final seekedFrames = <int>[];

      // Two 24-frame cuts: the ruler spans 48 frames at 8px each.
      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
        onSeekGlobalFrame: seekedFrames.add,
      );

      final ruler = find.byKey(const ValueKey<String>('storyboard-ruler'));
      expect(ruler, findsOneWidget);

      final topLeft = tester.getTopLeft(ruler);
      // Frame 30 starts at 240px; tap inside its cell.
      await tester.tapAt(topLeft + const Offset(30 * 8 + 3, 10));
      await tester.pumpAndSettle();

      expect(seekedFrames, [30]);
    });

    testWidgets('ruler scrub reports frames while dragging', (tester) async {
      final seekedFrames = <int>[];

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
        onSeekGlobalFrame: seekedFrames.add,
      );

      final topLeft = tester.getTopLeft(
        find.byKey(const ValueKey<String>('storyboard-ruler')),
      );
      final gesture = await tester.startGesture(
        topLeft + const Offset(8 * 8 + 3, 10),
      );
      await gesture.moveBy(const Offset(8 * 8, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(seekedFrames.first, 8);
      expect(seekedFrames.last, 16);
    });

    testWidgets('playhead line sits on the global frame', (tester) async {
      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
        playheadGlobalFrame: 30,
      );

      final playhead = find.byKey(
        const ValueKey<String>('storyboard-playhead'),
      );
      expect(playhead, findsOneWidget);
      // Timeline-style frame-wide tint: sits ON the frame, one cell wide.
      expect(tester.widget<Positioned>(playhead).left, 30 * 8);
      expect(tester.widget<Positioned>(playhead).width, 8);
    });

    testWidgets('no playhead line without a frame', (tester) async {
      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([_cut('cut-a', name: 'Cut A')]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
      );

      expect(
        find.byKey(const ValueKey<String>('storyboard-playhead')),
        findsNothing,
      );
    });

    testWidgets('blocks show resolver thumbnails, placeholder when pending', (
      tester,
    ) async {
      final image = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint());
        final picture = recorder.endRecording();
        try {
          return picture.toImage(2, 2);
        } finally {
          picture.dispose();
        }
      });
      addTearDown(() => image!.dispose());

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
        thumbnailFor: (cut, _) => cut.id == const CutId('cut-a') ? image : null,
      );

      expect(requireCutBlock(tester, 'cut-a').thumbnails.first, isNotNull);
      expect(requireCutBlock(tester, 'cut-b').thumbnails.first, isNull);
    });

    testWidgets('no thumbnails at all without a resolver', (tester) async {
      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([_cut('cut-a', name: 'Cut A')]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
      );

      expect(cutBlocksPainter(tester).showThumbnails, isFalse);
      // Not "one null picture" — no pictures asked for at all, which is
      // what keeps the store idle when nothing can show its output.
      expect(requireCutBlock(tester, 'cut-a').thumbnails, isEmpty);
    });

    testWidgets('each PANEL asks for its own picture, at its own frame', (
      tester,
    ) async {
      final asked = <(CutId, int)>[];

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut(
            'cut-a',
            name: 'Cut A',
            duration: 12,
            layers: [
              Layer(
                id: const LayerId('sb-a'),
                name: 'SB',
                kind: LayerKind.storyboard,
                frames: [
                  Frame(
                    id: const FrameId('sb-a-0'),
                    duration: 1,
                    strokes: const [],
                  ),
                  Frame(
                    id: const FrameId('sb-a-5'),
                    duration: 1,
                    strokes: const [],
                  ),
                ],
                timeline: const {
                  0: TimelineExposure.drawing(FrameId('sb-a-0'), length: 5),
                  5: TimelineExposure.drawing(FrameId('sb-a-5'), length: 7),
                },
              ),
            ],
          ),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
        thumbnailFor: (cut, frameIndex) {
          asked.add((cut.id, frameIndex));
          return null;
        },
      );

      // Two panels, two pictures, each at the division it opens on — the
      // conte's cells are panels, so this IS the sheet's picture column.
      // Asked as a SET: the painter reads its blocks for painting, for
      // hit-testing and for semantics, and the store answers a repeat from
      // cache.
      expect(asked.toSet(), {
        (const CutId('cut-a'), 0),
        (const CutId('cut-a'), 5),
      });
      expect(requireCutBlock(tester, 'cut-a').thumbnails, hasLength(2));
    });

    testWidgets('pixelsPerFrame rescales blocks, ruler and playhead', (
      tester,
    ) async {
      Future<void> pumpAt(double pixelsPerFrame) {
        return _pumpStoryboardPanel(
          tester,
          _singleTrackProject([
            _cut('cut-a', name: 'Cut A'),
            _cut('cut-b', name: 'Cut B'),
          ]),
          activeCutId: const CutId('cut-a'),
          onCutSelected: (_) {},
          playheadGlobalFrame: 24,
          pixelsPerFrame: pixelsPerFrame,
        );
      }

      final playhead = find.byKey(
        const ValueKey<String>('storyboard-playhead'),
      );

      await pumpAt(8);
      expect(requireCutBlock(tester, 'cut-a').rect.width, 24 * 8);
      expect(tester.widget<Positioned>(playhead).left, 24 * 8);

      await pumpAt(16);
      expect(requireCutBlock(tester, 'cut-a').rect.width, 24 * 16);
      expect(tester.widget<Positioned>(playhead).left, 24 * 16);

      // Fully zoomed out blocks stay frame-linear (no min-width overlap).
      await pumpAt(4);
      expect(requireCutBlock(tester, 'cut-a').rect.width, 24 * 4);
      expect(
        requireCutBlock(tester, 'cut-a').rect.right,
        lessThanOrEqualTo(requireCutBlock(tester, 'cut-b').rect.left),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('thumbnails fill the block background, centered', (
      tester,
    ) async {
      final image = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 4, 2), Paint());
        final picture = recorder.endRecording();
        try {
          return picture.toImage(4, 2);
        } finally {
          picture.dispose();
        }
      });
      addTearDown(() => image!.dispose());

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
        thumbnailFor: (cut, _) => cut.id == const CutId('cut-a') ? image : null,
      );

      expect(requireCutBlock(tester, 'cut-a').thumbnails.first, same(image));
      // Pending cuts have no picture yet — the block paints its
      // placeholder for them.
      expect(requireCutBlock(tester, 'cut-b').thumbnails.first, isNull);
      // The old ACTIVE badge is gone.
      expect(find.text('ACTIVE'), findsNothing);
    });

    testWidgets('cut totals switch between frames and seconds', (tester) async {
      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
      );
      expect(requireCutBlock(tester, 'cut-b').total, '48');

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
        showSeconds: true,
        projectFrameRate: const ProjectFrameRate.integer(24),
      );
      expect(requireCutBlock(tester, 'cut-b').total, '2+0');
    });

    testWidgets('frame axis: scrolling stays CLAMPED to the built cells; '
        'the ruler edge-drag alone extends it (UI-R12 #16)', (tester) async {
      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
      );

      final ruler = find.byKey(const ValueKey<String>('storyboard-ruler'));
      final initialWidth = tester.getSize(ruler).width;

      // Scroll gestures wall at the built extent: the strip never grows
      // from scrolling (the scrollbar range = the existing cells).
      for (var i = 0; i < 3; i += 1) {
        await tester.drag(
          find.byKey(
            const ValueKey<String>('storyboard-timeline-horizontal-viewport'),
          ),
          const Offset(-1200, 0),
        );
        await tester.pumpAndSettle();
      }
      expect(
        tester.getSize(ruler).width,
        initialWidth,
        reason: 'scroll cannot extend the axis (UI-R12 #16)',
      );

      // The ruler edge-drag is THE way past the wall — each move pans the
      // axis (overshooting the built extent) and growth materializes the
      // frames the view needs. The pointer sits inside the 24px edge zone
      // of the 1400px surface's ruler viewport.
      final rulerTop = tester.getTopLeft(ruler).dy;
      final gesture = await tester.startGesture(Offset(1390, rulerTop + 12));
      for (var i = 0; i < 12; i += 1) {
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getSize(ruler).width, greaterThan(initialWidth));
    });

    testWidgets('cut edge grips report trim drags', (tester) async {
      final began = <(CutId, TimelineBlockEdge)>[];
      final updates = <int>[];
      var ended = 0;

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
        stripEdges: StoryboardStripEdgeCallbacks(
          onCutEdgeBegin: (cutId, edge) {
            began.add((cutId, edge));
            return true;
          },
          onDivisionBegin: (_, _) => false,
          onUpdate: updates.add,
          onEnd: () => ended += 1,
          onCancel: () {},
        ),
      );

      // These cuts have no storyboard row, so each is ONE panel and its two
      // edges are the cut's own: the ordinals below are those panels'. The
      // TRAILING edge is the cut's length and reaches these hooks; the
      // leading one is the first panel's comma and has its own verb.
      // The grips are PAINTED targets on the timeline's chrome layer now,
      // so they are read off its model rather than found by key.
      expect(
        timelineRowChromeIds(tester, 'track-a', prefix: 'storyboard'),
        containsAll(<String>[
          'block-edge-grip-start-track-a-0',
          'block-edge-grip-start-track-a-1',
          'block-edge-grip-end-track-a-0',
        ]),
      );

      final gesture = await tester.startGesture(
        timelineRowChromeCenter(
          tester,
          'track-a',
          'block-edge-grip-end-track-a-0',
          prefix: 'storyboard',
        ),
      );
      await gesture.moveBy(const Offset(19, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(16, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(began, [(const CutId('cut-a'), TimelineBlockEdge.end)]);
      expect(updates, isNotEmpty);
      expect(updates.last, greaterThanOrEqualTo(2));
      expect(ended, 1);
    });

    testWidgets('tap-to-select still works when dragging is enabled', (
      tester,
    ) async {
      final selectedCutIds = <CutId>[];

      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: selectedCutIds.add,
      );

      await tester.tapAt(cutBlockCenter(tester, 'cut-b'));
      await tester.pumpAndSettle();

      expect(selectedCutIds, [const CutId('cut-b')]);
    });
  });

  group('StoryboardPanel zoom-around-playhead', () {
    testWidgets('zooming keeps a visible playhead at the same screen spot', (
      tester,
    ) async {
      Future<void> pumpAtZoom(double pixelsPerFrame) {
        return _pumpStoryboardPanel(
          tester,
          _singleTrackProject([
            _cut('cut-a', name: 'Cut A', duration: 60),
            _cut('cut-b', name: 'Cut B', duration: 60),
          ]),
          activeCutId: const CutId('cut-a'),
          onCutSelected: (_) {},
          playheadGlobalFrame: 30,
          pixelsPerFrame: pixelsPerFrame,
        );
      }

      await pumpAtZoom(8);
      final playhead = find.byKey(
        const ValueKey<String>('storyboard-playhead'),
      );
      final centerBefore = tester.getRect(playhead).center.dx;

      await pumpAtZoom(16);
      await tester.pumpAndSettle();

      expect(tester.getRect(playhead).center.dx, centerBefore);
    });

    testWidgets('zooming with the playhead off screen keeps the leading '
        'edge anchored', (tester) async {
      Future<void> pumpAtZoom(double pixelsPerFrame) {
        return _pumpStoryboardPanel(
          tester,
          _singleTrackProject([
            _cut('cut-a', name: 'Cut A', duration: 200),
            _cut('cut-b', name: 'Cut B', duration: 200),
          ]),
          activeCutId: const CutId('cut-a'),
          onCutSelected: (_) {},
          // Far beyond the (now wider, UI-R5) viewport at either zoom.
          playheadGlobalFrame: 380,
          pixelsPerFrame: pixelsPerFrame,
        );
      }

      await pumpAtZoom(8);
      final blockBefore = cutBlockScreenRect(tester, 'cut-a').left;

      await pumpAtZoom(16);
      await tester.pumpAndSettle();

      // Offset 0 scales to 0: the track start stays at the same edge.
      expect(cutBlockScreenRect(tester, 'cut-a').left, blockBefore);
    });
  });

  group('StoryboardPanel pinned ruler', () {
    testWidgets('the ruler stays put while tracks scroll vertically', (
      tester,
    ) async {
      // Enough tracks that the panel scrolls vertically.
      await _pumpStoryboardPanel(
        tester,
        _project([
          for (var index = 0; index < 10; index += 1)
            Track(
              id: TrackId('track-$index'),
              name: 'V${index + 1}',
              cuts: [_cut('cut-$index', name: 'Cut $index')],
            ),
        ]),
        activeCutId: const CutId('cut-0'),
        onCutSelected: (_) {},
      );

      final ruler = find.byKey(const ValueKey<String>('storyboard-ruler'));
      final firstRow = find.byKey(
        const ValueKey<String>('storyboard-track-row-track-0'),
      );
      final rulerTopLeft = tester.getTopLeft(ruler);
      final firstRowTop = tester.getTopLeft(firstRow).dy;

      await tester.drag(
        find.byKey(const ValueKey<String>('storyboard-vertical-viewport')),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      // Tracks scrolled under the ruler; the ruler did not move.
      expect(tester.getTopLeft(firstRow).dy, lessThan(firstRowTop));
      expect(tester.getTopLeft(ruler), rulerTopLeft);
    });

    testWidgets('the pinned ruler follows horizontal scrolling with the '
        'blocks', (tester) async {
      await _pumpStoryboardPanel(
        tester,
        _singleTrackProject([
          _cut('cut-a', name: 'Cut A'),
          _cut('cut-b', name: 'Cut B'),
        ]),
        activeCutId: const CutId('cut-a'),
        onCutSelected: (_) {},
      );

      final ruler = find.byKey(const ValueKey<String>('storyboard-ruler'));
      final rulerX = tester.getTopLeft(ruler).dx;
      final blockX = cutBlockScreenRect(tester, 'cut-a').left;

      await tester.drag(
        find.byKey(
          const ValueKey<String>('storyboard-timeline-horizontal-viewport'),
        ),
        const Offset(-160, 0),
      );
      await tester.pumpAndSettle();

      final rulerShift = rulerX - tester.getTopLeft(ruler).dx;
      final blockShift = blockX - cutBlockScreenRect(tester, 'cut-a').left;
      expect(rulerShift, greaterThan(0));
      // Frame labels stay aligned with the blocks under them.
      expect(rulerShift, blockShift);
    });
  });
}

Future<void> _pumpStoryboardPanel(
  WidgetTester tester,
  Project project, {
  required CutId activeCutId,
  required ValueChanged<CutId> onCutSelected,
  StoryboardStripEdgeCallbacks? stripEdges,
  StoryboardCutMoveCallbacks? cutMove,
  StoryboardCutSelectCallbacks? cutSelect,
  StoryboardMovieEndCallbacks? movieEnd,
  ValueChanged<TrackId>? onSelectTrack,
  int? playheadGlobalFrame,
  ValueChanged<int>? onSeekGlobalFrame,
  ValueChanged<int>? onScrubGlobalFrame,
  VoidCallback? onScrubEnd,
  StoryboardThumbnailResolver? thumbnailFor,
  double pixelsPerFrame = 8,
  bool showSeconds = false,
  ProjectFrameRate projectFrameRate = const ProjectFrameRate.integer(24),
}) async {
  // The rail widened to the timeline's 372 (UI-R5): keep every cut block
  // of the three-cut fixtures on screen for the drag gestures.
  await tester.binding.setSurfaceSize(const Size(1400, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StoryboardPanel(
          project: project,
          activeCutId: activeCutId,
          // The HOST's landing verb, stood in for: a cells press states a
          // row and a frame, and the seek behind it is what picks the cut
          // (a frame in a gap picks none). These tests keep asserting on
          // the cut so the press contract stays readable as "this cut".
          onRowFramePress: (row, globalFrame) {
            for (final entry in buildStoryboardTimelineLayout(project)) {
              if (row == TrackRowAddress(entry.trackId) &&
                  globalFrame >= entry.startFrame &&
                  globalFrame < entry.endFrame) {
                onCutSelected(entry.cutId);
                return;
              }
            }
          },
          stripEdges: stripEdges,
          cutMove: cutMove,
          cutSelect: cutSelect,
          movieEnd: movieEnd,
          onSelectTrack: onSelectTrack,
          playheadFrame: playheadGlobalFrame == null
              ? null
              : ValueNotifier<int?>(playheadGlobalFrame),
          onSeekGlobalFrame: onSeekGlobalFrame,
          onScrubGlobalFrame: onScrubGlobalFrame,
          onScrubEnd: onScrubEnd,
          thumbnailFor: thumbnailFor,
          pixelsPerFrame: pixelsPerFrame,
          showSeconds: showSeconds,
          projectFrameRate: projectFrameRate,
        ),
      ),
    ),
  );
}

Project _singleTrackProject(List<Cut> cuts) {
  return _project([
    Track(id: const TrackId('track-a'), name: 'Track A', cuts: cuts),
  ]);
}

Project _project(List<Track> tracks) {
  return Project(
    id: const ProjectId('project-storyboard-interactions'),
    name: 'Project Storyboard Interactions',
    createdAt: DateTime.utc(2026, 6, 21),
    tracks: tracks,
  );
}

Cut _cut(
  String id, {
  required String name,
  List<Layer>? layers,
  int duration = 24,
}) {
  return Cut(
    id: CutId(id),
    name: name,
    duration: duration,
    canvasSize: const CanvasSize(width: 1280, height: 720),
    layers: layers ?? [_animationLayer('animation-$id')],
  );
}

Layer _animationLayer(String id) {
  return _layer(id, LayerKind.animation, name: 'Animation $id');
}

Layer _storyboardLayer(String id) {
  return _layer(id, LayerKind.storyboard, name: 'Storyboard $id');
}

Layer _layer(String id, LayerKind kind, {required String name}) {
  return Layer(
    id: LayerId(id),
    name: name,
    kind: kind,
    frames: [Frame(id: FrameId('frame-$id'), duration: 1, strokes: const [])],
  );
}
