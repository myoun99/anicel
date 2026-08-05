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
/// ON the strip. The first panel's leading edge re-times the cut's LEAD, and
/// EVERY trailing edge — inner and last alike — is its panel's comma: the
/// later panels ripple along glued and the cut's length rides the row end
/// (edge unification; the division verb is gone). One shape of grip; where
/// it sits decides what it re-times.
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
  await tester.binding.setSurfaceSize(const Size(1500, 800));
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
    // panel 0's BACK grip grows the cut at its tail, panel 1's FRONT grip
    // shortens the cut at its head. Same boundary, opposite ends give way.
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

  testWidgets('the V rows share ONE height, and the steppers change it', (
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

    final before = rowHeight();
    expect(railHeight(), before, reason: 'rail and strip are one row');

    await tester.tap(
      find.byKey(const ValueKey<String>('storyboard-row-taller-button')),
    );
    await tester.pumpAndSettle();

    expect(rowHeight(), greaterThan(before));
    expect(railHeight(), rowHeight());

    await tester.tap(
      find.byKey(const ValueKey<String>('storyboard-row-shorter-button')),
    );
    await tester.pumpAndSettle();

    expect(rowHeight(), before);
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

  group('the LEAD edge is the frame axis\'s (R10 R4)', () {
    testWidgets('the cut loses frames off its front, its END holds, and the '
        'emptiness lands at the head of the film — whether or not the cut '
        'has been drawn on', (tester) async {
      await _openStoryboard(tester);
      final firstStart = _cutById(tester, 'cut-1').leadingGapFrames;
      expect(firstStart, 0);

      await _dragGrip(tester, 'block-edge-grip-start-grip-track-0', 2);

      // Cut 1 is the FIRST cut, so there is no predecessor to slide: the
      // head is directly in front of it and takes the 2 frames.
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

    testWidgets('an INNER panel\'s front grip takes the frames off the same '
        'panel, and the cut\'s head still absorbs them', (tester) async {
      await _openStoryboard(tester);
      expect(_divisionsOf(tester, 'cut-1'), [0, 5]);

      await _dragGrip(tester, 'block-edge-grip-start-grip-track-1', 2);

      final cut = _cutById(tester, 'cut-1');
      expect(cut.duration, 8);
      expect(cut.leadingGapFrames, 2);
      final row = storyboardLayerForCut(cut)!;
      expect(
        _divisionsOf(tester, 'cut-1'),
        [0, 5],
        reason: 'the panels IN FRONT of the grab keep their cut-local keys — '
            'on screen they translate, because the cut head moved with them',
      );
      expect(row.timeline[0]!.length, 5, reason: 'untouched');
      expect(row.timeline[5]!.length, 3, reason: 'the grabbed panel, 5 -> 3');
      expect(
        _cutById(tester, 'cut-2').leadingGapFrames,
        0,
        reason: 'the end held, so nothing behind the cut moved',
      );
    });

    testWidgets('the two edges of one boundary are two edits: the back grip '
        'grows the cut at its TAIL, the front grip shortens it at its HEAD', (
      tester,
    ) async {
      await _openStoryboard(tester);

      // Panel 0's trailing edge and panel 1's leading edge sit on the same
      // boundary. This is the pair R4 called "two handles, one thing" — and
      // the reason it is not: they move opposite ends of the cut.
      await _dragGrip(tester, 'block-edge-grip-end-grip-track-0', 2);
      expect(_divisionsOf(tester, 'cut-1'), [0, 7]);
      expect(_cutById(tester, 'cut-1').duration, 12);
      expect(_cutById(tester, 'cut-1').leadingGapFrames, 0);

      await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
      await tester.pumpAndSettle();

      await _dragGrip(tester, 'block-edge-grip-start-grip-track-1', 2);
      expect(_divisionsOf(tester, 'cut-1'), [0, 5]);
      expect(_cutById(tester, 'cut-1').duration, 8);
      expect(_cutById(tester, 'cut-1').leadingGapFrames, 2);
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

    testWidgets('on a LATER cut the glued predecessor slides wholesale and '
        'the head still empties', (tester) async {
      await _openStoryboard(tester);
      final firstDuration = _cutById(tester, 'cut-1').duration;

      await _dragGrip(tester, 'block-edge-grip-start-grip-track-2', 2);

      expect(
        _cutById(tester, 'cut-1').duration,
        firstDuration,
        reason: 'the predecessor MOVES, it does not resize',
      );
      expect(_cutById(tester, 'cut-1').leadingGapFrames, 2);
      expect(
        _cutById(tester, 'cut-2').leadingGapFrames,
        0,
        reason: 'no gap is torn open between the glued neighbours',
      );
      expect(_cutById(tester, 'cut-2').duration, 8);
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

    testWidgets('the storyboard row has NO start grips here (edge '
        'unification): the row\'s front edge is the cut\'s start on the '
        'strip, and every inner boundary is a trailing edge', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1500, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: _project())),
      );
      await tester.pumpAndSettle();

      final ids = timelineRowChromeIds(tester, 'cut-1-sb');
      // NO start grips at all (edge unification widened feedback #10's
      // at-zero rule): every boundary on a gapless row belongs to the
      // trailing edge on its left, so a front grip would only be the same
      // boundary's second handle — and the block-1 one used to push
      // block 0 off frame 0 (the ripple defect this removal retires).
      expect(ids, isNot(contains('block-edge-grip-start-cut-1-sb-0')));
      expect(ids, isNot(contains('block-edge-grip-start-cut-1-sb-1')));
      expect(ids, contains('block-edge-grip-end-cut-1-sb-0'));
      expect(ids, contains('block-edge-grip-end-cut-1-sb-1'));
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
