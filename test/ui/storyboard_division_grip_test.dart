import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';

import 'timeline/timeline_row_chrome_probe.dart';

/// The cut block has no edge grips of its own any more: a cut edge is always
/// ON the strip. EVERY leading edge is a rolling edit with the block in front
/// of it — the panel before it, or at a cut's first panel the previous cut's
/// last panel — so the lengths trade and nothing else moves (I-21: one lead
/// edge law with the frame axis). EVERY trailing edge — inner and last
/// alike — is its panel's comma: the later panels ripple along glued and the
/// cut's length rides the row end (edge unification; the division verb is
/// gone). One shape of grip; where it sits decides what it re-times.
const _trackId = TrackId('grip-track');

Layer _storyboardLayer(String cutId, Map<int, int> divisions) => Layer(
  id: LayerId('$cutId-sb'),
  name: 'SB',
  kind: LayerKind.storyboard,
  frames: [
    for (final start in divisions.keys)
      Frame(id: FrameId('$cutId-$start'), duration: 1, strokes: const []),
  ],
  timeline: {
    for (final entry in divisions.entries)
      entry.key: TimelineExposure.drawing(
        FrameId('$cutId-${entry.key}'),
        length: entry.value,
      ),
  },
);

Cut _cut(String id, int duration, Map<int, int> divisions) => Cut(
  id: CutId(id),
  name: id,
  duration: duration,
  canvasSize: const CanvasSize(width: 640, height: 360),
  layers: [
    Layer(
      id: LayerId('$id-cel'),
      name: 'A',
      frames: const [],
      timeline: const {},
    ),
    _storyboardLayer(id, divisions),
  ],
);

/// Cut 1 covers [0,10) with panels at 0 and 5; cut 2 covers [10,20) with one
/// panel over the whole of it — the degenerate case, which should grow
/// exactly the two grips a cut used to have. Cut 3 is divided too, and it is
/// there for two reasons: its own division belongs to a cut that is NOT
/// active, and it keeps cut 2's trailing edge away from the MOVIE's end,
/// whose full-height handle sits over the last cut's edge.
Project _project() => Project(
  id: const ProjectId('grip-project'),
  name: 'Grips',
  createdAt: DateTime.utc(2026, 7, 27),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [
        _cut('cut-1', 10, {0: 5, 5: 5}),
        _cut('cut-2', 10, {0: 10}),
        _cut('cut-3', 6, {0: 3, 3: 3}),
      ],
    ),
  ],
);

Future<void> _openStoryboard(WidgetTester tester) async {
  // 1500 → 1900. The storyboard's bar grew the timeline's four command pills
  // (2026-08-10), so at 1500 the region's own two-thirds width put the row
  // steppers past the bar's right edge — laid out, scrolled out of view, and
  // a tap on them silently missed. Widening is the honest fix: the bar is
  // SUPPOSED to overflow into its scroller when the room runs out (유저:
  // 버튼이 잘리는 건 이해한다), and this file is about the row heights, not
  // about how narrow a window that starts happening in.
  await tester.binding.setSurfaceSize(const Size(1900, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project())),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
  );
  await tester.pumpAndSettle();
}

double _pixelsPerFrame(WidgetTester tester) =>
    tester.widget<StoryboardPanel>(find.byType(StoryboardPanel)).pixelsPerFrame;

Project _projectOf(WidgetTester tester) =>
    tester.widget<StoryboardPanel>(find.byType(StoryboardPanel)).project;

Cut _cutById(WidgetTester tester, String id) => _projectOf(
  tester,
).tracks.single.cuts.firstWhere((cut) => cut.id == CutId(id));

List<int> _divisionsOf(WidgetTester tester, String cutId) =>
    storyboardLayerForCut(_cutById(tester, cutId))!.timeline.keys.toList();

/// Drags the chrome target [id] by [frames] whole frames.
Future<void> _dragGrip(WidgetTester tester, String id, int frames) async {
  final gesture = await tester.startGesture(
    timelineRowChromeCenter(tester, _trackId.value, id, prefix: 'storyboard'),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  // In two steps, so the drag clears the slop before the frame delta the
  // assertions read is the one that lands.
  await gesture.moveBy(Offset(frames * _pixelsPerFrame(tester) / 2, 0));
  await tester.pump();
  await gesture.moveBy(Offset(frames * _pixelsPerFrame(tester) / 2, 0));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('EVERY panel hangs a leading grip — the two edges of one '
      'boundary name two edits, not one', (tester) async {
    await _openStoryboard(tester);

    // Panels in track order: cut 1's two, then one each for cuts 2 and 3.
    // Panel 1 is INTERIOR to cut 1 and hangs a front grip all the same
    // (user's rule 2026-08-02). It is not the impersonation P5 #8 shipped:
    // panel 0's BACK grip grows the cut at its tail, and panel 1's FRONT
    // grip trades frames with panel 0 inside a cut that keeps its length
    // (I-21). Same boundary, two different edits.
    expect(
      timelineRowChromeIds(tester, _trackId.value, prefix: 'storyboard'),
      <String>[
        'block-edge-grip-start-grip-track-0',
        'block-edge-grip-end-grip-track-0',
        'block-edge-grip-start-grip-track-1',
        'block-edge-grip-end-grip-track-1',
        'block-edge-grip-start-grip-track-2',
        'block-edge-grip-end-grip-track-2',
        'block-edge-grip-start-grip-track-3',
        'block-edge-grip-end-grip-track-3',
        'block-edge-grip-start-grip-track-4',
        'block-edge-grip-end-grip-track-4',
      ],
    );
  });

  testWidgets('the edges sit on the STRIP, not over the cut\'s bands', (
    tester,
  ) async {
    await _openStoryboard(tester);

    final row = find.byKey(
      ValueKey<String>('storyboard-track-timeline-area-${_trackId.value}'),
    );
    final rowRect = tester.getTopLeft(row) & tester.getSize(row);
    final band = StoryboardCutBlocksPainter.stripBandOf(rowRect.height);
    final grip = timelineRowChromeGlobalRect(
      tester,
      _trackId.value,
      'block-edge-grip-end-grip-track-0',
      prefix: 'storyboard',
    );

    expect(grip.top, rowRect.top + band.top);
    expect(grip.height, band.height);
  });

  testWidgets('an edge BETWEEN two panels is that panel\'s COMMA (edge '
      'unification): the later panel ripples along glued and the cut\'s '
      'length rides the row end', (tester) async {
    await _openStoryboard(tester);
    expect(_divisionsOf(tester, 'cut-1'), [0, 5]);

    await _dragGrip(tester, 'block-edge-grip-end-grip-track-0', 2);

    // The first panel's comma grew by 2; the second kept its own 5 and
    // re-keyed right; the cut is 2 longer — where the retired division
    // verb moved the boundary and pinned the length.
    expect(_divisionsOf(tester, 'cut-1'), [0, 7]);
    expect(_cutById(tester, 'cut-1').duration, 12);
    final layer = storyboardLayerForCut(_cutById(tester, 'cut-1'))!;
    expect(layer.timeline[0]!.length, 7);
    expect(layer.timeline[7]!.length, 5);
    // Cut 2 was attached and stays attached — it rode the boundary out.
    expect(_cutById(tester, 'cut-2').leadingGapFrames, 0);
  });

  testWidgets('the inner-comma drag is ONE undo step — row and cut length '
      'restore together', (tester) async {
    await _openStoryboard(tester);

    await _dragGrip(tester, 'block-edge-grip-end-grip-track-0', 2);
    expect(_divisionsOf(tester, 'cut-1'), [0, 7]);
    expect(_cutById(tester, 'cut-1').duration, 12);

    await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
    await tester.pumpAndSettle();

    expect(_divisionsOf(tester, 'cut-1'), [0, 5]);
    expect(_cutById(tester, 'cut-1').duration, 10);
  });

  testWidgets('the LAST panel\'s trailing edge is still the cut\'s LENGTH — '
      'and the stored comma moves with it (feedback #9)', (tester) async {
    await _openStoryboard(tester);

    await _dragGrip(tester, 'block-edge-grip-end-grip-track-1', 3);

    expect(_cutById(tester, 'cut-1').duration, 13);
    expect(_divisionsOf(tester, 'cut-1'), [0, 5]);
    // The edge is the ROW's edge: the last cell's stored comma grew by the
    // same 3 the cut did, so store and coverage stay one picture.
    final layer = storyboardLayerForCut(_cutById(tester, 'cut-1'))!;
    expect(layer.timeline[5]!.length, 8);
  });

  testWidgets('a cut with ONE panel keeps exactly the two grips it had: the '
      'new rule\'s degenerate case is the old behaviour', (tester) async {
    await _openStoryboard(tester);

    await _dragGrip(tester, 'block-edge-grip-end-grip-track-2', 4);

    expect(_cutById(tester, 'cut-2').duration, 14);
    expect(_divisionsOf(tester, 'cut-2'), [0]);
  });

  testWidgets('the LAST cut\'s trailing edge is reachable: the movie-end '
      'handle no longer sits on top of it', (tester) async {
    await _openStoryboard(tester);

    // Cut 3 ends where the movie does, so its trailing edge grip and the
    // end-line handle share a frame. The handle is grabbed from the empty
    // side of the line now, which leaves the grip its own pixels.
    await _dragGrip(tester, 'block-edge-grip-end-grip-track-4', 2);

    expect(_cutById(tester, 'cut-3').duration, 8);
  });

  testWidgets('the V rows share ONE height — rail and strip are one row '
      '(the bar\'s steppers left with B7; the splitter is the next writer)', (
    tester,
  ) async {
    await _openStoryboard(tester);

    double rowHeight() => tester
        .getSize(
          find.byKey(
            ValueKey<String>(
              'storyboard-track-timeline-area-${_trackId.value}',
            ),
          ),
        )
        .height;
    double railHeight() => tester
        .getSize(
          find.byKey(
            ValueKey<String>('storyboard-track-label-row-${_trackId.value}'),
          ),
        )
        .height;

    expect(railHeight(), rowHeight(), reason: 'rail and strip are one row');
    expect(rowHeight(), StoryboardPanel.defaultTrackLaneHeight);
  });

  testWidgets('ANY cut\'s inner edges drag, not only the active one\'s — '
      'the edge reads its cut rather than the active-cut lookup (and syncs '
      'THAT cut\'s length, not the active one\'s)', (tester) async {
    await _openStoryboard(tester);
    // Cut 1 is the active one; cut 3's row is not reachable through the
    // active-cut layer lookup at all.
    expect(_divisionsOf(tester, 'cut-3'), [0, 3]);

    await _dragGrip(tester, 'block-edge-grip-end-grip-track-3', -1);

    expect(_divisionsOf(tester, 'cut-3'), [0, 2]);
    expect(_cutById(tester, 'cut-3').duration, 5, reason: 'its own cut rides');
    expect(_divisionsOf(tester, 'cut-1'), [0, 5]);
    expect(_cutById(tester, 'cut-1').duration, 10, reason: 'not the active');
  });

  // ⛔RETIRED 2026-09-12 (`caa29719`, I-21 hands-on ②): the front grip used to
  // take its frames off the CUT — the grabbed panel shrank, nobody grew, the
  // cut's head absorbed the difference and a glued predecessor slid
  // wholesale. That was a law of the storyboard's own, and the user asked
  // for the other one: 「프레임블록이랑 똑같은 하나의 법으로」 ·
  // 「첫번째 블록의 앞엣지만 이전 컷, 컷 안에 콘티블록있으면 해당 블록」.
  // These cases pinned the retired law and outlived it; they are rewritten
  // to the one that shipped, not deleted.
  group('the LEAD edge trades with the block in front (I-21)', () {
    testWidgets('the cut loses frames off its front, its END holds, and the '
        'emptiness lands at the head of the film — whether or not the cut '
        'has been drawn on', (tester) async {
      await _openStoryboard(tester);
      final firstStart = _cutById(tester, 'cut-1').leadingGapFrames;
      expect(firstStart, 0);

      await _dragGrip(tester, 'block-edge-grip-start-grip-track-0', 2);

      // Cut 1's first panel is the FIRST block of the film, so there is no
      // block in front to trade with: the head is directly in front of it
      // and takes the 2 frames.
      final cut = _cutById(tester, 'cut-1');
      expect(cut.duration, 8);
      expect(cut.leadingGapFrames, 2);
      expect(
        _cutById(tester, 'cut-2').leadingGapFrames,
        0,
        reason: 'the end held, so the follower never moved',
      );
      // The panel the grip sat on is the one that lost the frames. Before
      // 2026-08-02 the row kept its keys and the LAST panel was silently
      // clipped to the new duration instead — the user's report.
      expect(_divisionsOf(tester, 'cut-1'), [0, 3]);
      final row = storyboardLayerForCut(cut)!;
      expect(row.timeline[0]!.length, 3, reason: 'the grabbed panel, 5 -> 3');
      expect(row.timeline[3]!.length, 5, reason: 'the other one, untouched');
    });

    testWidgets('an INNER panel\'s front grip trades with the panel in front: '
        'that one grows, this one shrinks, and the cut keeps its length', (
      tester,
    ) async {
      await _openStoryboard(tester);
      expect(_divisionsOf(tester, 'cut-1'), [0, 5]);

      await _dragGrip(tester, 'block-edge-grip-start-grip-track-1', 2);

      final cut = _cutById(tester, 'cut-1');
      expect(cut.duration, 10, reason: 'a front edge never changes the length');
      expect(cut.leadingGapFrames, 0);
      final row = storyboardLayerForCut(cut)!;
      expect(_divisionsOf(tester, 'cut-1'), [0, 7]);
      expect(row.timeline[0]!.length, 7, reason: 'the panel in front, 5 -> 7');
      expect(row.timeline[7]!.length, 3, reason: 'the grabbed panel, 5 -> 3');
      expect(
        _cutById(tester, 'cut-2').leadingGapFrames,
        0,
        reason: 'nothing behind the cut moved',
      );
    });

    testWidgets('the two edges of one boundary are two edits: the back grip '
        'grows the cut at its TAIL, the front grip trades inside it', (
      tester,
    ) async {
      await _openStoryboard(tester);

      // Panel 0's trailing edge and panel 1's leading edge sit on the same
      // boundary, and both move it. They are still two edits: the back grip
      // is panel 0's comma — the later panels ripple and the cut grows — and
      // the front grip is a rolling edit between the two panels, so the cut
      // keeps its length.
      await _dragGrip(tester, 'block-edge-grip-end-grip-track-0', 2);
      expect(_divisionsOf(tester, 'cut-1'), [0, 7]);
      expect(_cutById(tester, 'cut-1').duration, 12);
      expect(_cutById(tester, 'cut-1').leadingGapFrames, 0);

      await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
      await tester.pumpAndSettle();

      await _dragGrip(tester, 'block-edge-grip-start-grip-track-1', 2);
      expect(_divisionsOf(tester, 'cut-1'), [0, 7]);
      expect(_cutById(tester, 'cut-1').duration, 10);
      expect(_cutById(tester, 'cut-1').leadingGapFrames, 0);
    });

    testWidgets('ONE undo restores the cut length and the head together', (
      tester,
    ) async {
      await _openStoryboard(tester);

      await _dragGrip(tester, 'block-edge-grip-start-grip-track-0', 2);
      expect(_cutById(tester, 'cut-1').duration, 8);
      expect(_cutById(tester, 'cut-1').leadingGapFrames, 2);

      await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
      await tester.pumpAndSettle();

      expect(_cutById(tester, 'cut-1').duration, 10);
      expect(_cutById(tester, 'cut-1').leadingGapFrames, 0);
    });

    testWidgets('on a LATER cut the block in front is the previous cut\'s '
        'LAST panel: it grows, this cut shrinks, and nothing else moves', (
      tester,
    ) async {
      await _openStoryboard(tester);

      await _dragGrip(tester, 'block-edge-grip-start-grip-track-2', 2);

      final previous = _cutById(tester, 'cut-1');
      expect(previous.duration, 12, reason: 'the cut in front GROWS now');
      expect(
        previous.leadingGapFrames,
        0,
        reason: 'the head of the film never empties',
      );
      expect(
        storyboardLayerForCut(previous)!.timeline[5]!.length,
        7,
        reason: 'and the frames land on its last panel, the block in front',
      );
      final grabbed = _cutById(tester, 'cut-2');
      expect(grabbed.duration, 8);
      expect(
        grabbed.leadingGapFrames,
        0,
        reason: 'no gap is torn open between the glued neighbours',
      );
      expect(
        previous.duration + grabbed.duration,
        20,
        reason: 'the grabbed cut\'s END held, so everything after it stayed',
      );
    });
  });

  group('the cut-internal timeline (feedback #9/#10)', () {
    testWidgets('the row\'s end comma drags the cut\'s end along — the '
        'always-synced pair, ONE undo', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: _project())),
      );
      await tester.pumpAndSettle();

      // Still on the TIMELINE tab: drag the storyboard row's last block
      // end grip 2 frames out.
      await _dragTimelineGrip(
        tester,
        'cut-1-sb',
        'block-edge-grip-end-cut-1-sb-1',
        2,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
      );
      await tester.pumpAndSettle();

      final layer = storyboardLayerForCut(_cutById(tester, 'cut-1'))!;
      expect(layer.timeline[5]!.length, 7);
      expect(_cutById(tester, 'cut-1').duration, 12);
      // Cut 2 was attached and stays attached — it rode the boundary out.
      expect(_cutById(tester, 'cut-2').leadingGapFrames, 0);

      await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
      await tester.pumpAndSettle();

      expect(_cutById(tester, 'cut-1').duration, 10);
      expect(
        storyboardLayerForCut(_cutById(tester, 'cut-1'))!.timeline[5]!.length,
        5,
      );
    });

    testWidgets('the storyboard row\'s inner boundary has a FRONT grip, and '
        'it trades with the block in front; only the row\'s very front — '
        'the cut\'s start — has none', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: _project())),
      );
      await tester.pumpAndSettle();

      final ids = timelineRowChromeIds(tester, 'cut-1-sb');
      // ⛔RETIRED with I-21: 「NO start grips at all」 was edge unification
      // widening feedback #10's at-zero rule, because block 1's front grip
      // used to RIPPLE — it pushed block 0 off frame 0. A front grip is a
      // rolling edit now and has nothing to push, so the only one withheld
      // is frame 0's: a gapless row's front edge is the cut's own start.
      expect(ids, isNot(contains('block-edge-grip-start-cut-1-sb-0')));
      expect(ids, contains('block-edge-grip-start-cut-1-sb-1'));
      expect(ids, contains('block-edge-grip-end-cut-1-sb-0'));
      expect(ids, contains('block-edge-grip-end-cut-1-sb-1'));

      await _dragTimelineGrip(
        tester,
        'cut-1-sb',
        'block-edge-grip-start-cut-1-sb-1',
        2,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
      );
      await tester.pumpAndSettle();

      final layer = storyboardLayerForCut(_cutById(tester, 'cut-1'))!;
      expect(layer.timeline.keys.toList(), [0, 7]);
      expect(layer.timeline[0]!.length, 7, reason: 'block 0 kept frame 0');
      expect(layer.timeline[7]!.length, 3);
      expect(_cutById(tester, 'cut-1').duration, 10);
    });
  });
}

/// Drags the TIMELINE row chrome target [id] on [layerId]'s row by
/// [frames] whole frames, reading the axis scale off the row's own
/// painter.
Future<void> _dragTimelineGrip(
  WidgetTester tester,
  String layerId,
  String id,
  int frames,
) async {
  final extent = timelineRowChromePainter(tester, layerId)!.frameCellExtent;
  final gesture = await tester.startGesture(
    timelineRowChromeCenter(tester, layerId, id),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveBy(Offset(frames * extent / 2, 0));
  await tester.pump();
  await gesture.moveBy(Offset(frames * extent / 2, 0));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}
