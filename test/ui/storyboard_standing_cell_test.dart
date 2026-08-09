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

/// UI-R5 ③b: the storyboard wears the timeline's STANDING visual.
///
/// The band says what is SELECTED and the ring says where you STAND. The
/// storyboard drew the first and not the second, so the row every lane verb
/// takes as its subject was the one row that said nothing about it.
///
/// The oracle is the same sentence on every row kind: the ring IS the
/// intersection of the playhead column and the row you stand on. It is
/// measured against the row's own widget rather than against the panel's
/// row table, so a table that drifts out of step with the rows it mirrors
/// fails here instead of drawing the ring on a neighbour.
Cut _cut(String id, int duration) {
  return Cut(
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
    ],
  );
}

Project _project() {
  return Project(
    id: const ProjectId('sb-standing-project'),
    name: 'SB Standing',
    createdAt: DateTime.utc(2026, 8, 9),
    tracks: [
      Track(
        id: const TrackId('sb-track'),
        name: 'Video',
        cuts: [_cut('cut-1', 8), _cut('cut-2', 6)],
        seLayers: [
          Layer(
            id: const LayerId('se-row-1'),
            name: 'S1',
            kind: LayerKind.se,
            frames: [
              Frame(
                id: const FrameId('f-one'),
                duration: 3,
                name: 'One!',
                strokes: const [],
              ),
            ],
            timeline: const {
              1: TimelineExposure.drawing(FrameId('f-one'), length: 3),
            },
          ),
        ],
      ),
    ],
  );
}

void main() {
  Future<void> pumpStoryboard(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
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

  Rect ringRect(WidgetTester tester) => tester.getRect(
    find.byKey(const ValueKey<String>('storyboard-standing-cell')),
  );

  Rect playheadRect(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey<String>('storyboard-playhead')));

  void expectRingOnRow(WidgetTester tester, String rowKey, {String? reason}) {
    final ring = ringRect(tester);
    final row = tester.getRect(find.byKey(ValueKey<String>(rowKey)));
    final playhead = playheadRect(tester);
    expect(ring.left, moreOrLessEquals(playhead.left), reason: reason);
    expect(ring.width, moreOrLessEquals(playhead.width), reason: reason);
    expect(ring.top, moreOrLessEquals(row.top), reason: reason);
    expect(ring.height, moreOrLessEquals(row.height), reason: reason);
  }

  testWidgets('standing on the V row outlines the CUT the playhead is in — '
      'the same sentence the S row and the timeline speak', (tester) async {
    await pumpStoryboard(tester);
    // Nothing picked yet: the rail rests on the V row.
    final area = tester.getRect(
      find.byKey(
        const ValueKey<String>('storyboard-track-timeline-area-sb-track'),
      ),
    );
    final cellWidth = playheadRect(tester).width;
    final vRow = tester.getRect(
      find.byKey(const ValueKey<String>('storyboard-track-row-sb-track')),
    );

    // Frame 0 is inside cut-1 (frames 0..8), so the block is the cut.
    final outline = tester.getRect(
      find.byKey(const ValueKey<String>('storyboard-standing-block')),
    );
    expect(outline.left, moreOrLessEquals(area.left));
    expect(
      outline.width,
      moreOrLessEquals(8 * cellWidth),
      reason: 'cut-1 runs 8 frames, and the outline is the CUT block',
    );
    expect(outline.top, moreOrLessEquals(vRow.top));
    expect(outline.height, moreOrLessEquals(vRow.height));

    // Step into the SECOND cut: the outline moves with the block, exactly
    // as the S row's does.
    await tester.tapAt(
      Offset(area.left + 9.5 * cellWidth, vRow.top + vRow.height / 2),
    );
    await tester.pumpAndSettle();
    final second = tester.getRect(
      find.byKey(const ValueKey<String>('storyboard-standing-block')),
    );
    expect(second.left, moreOrLessEquals(area.left + 8 * cellWidth));
    expect(second.width, moreOrLessEquals(6 * cellWidth));
  });

  testWidgets('the V row you land on rings the cell the playhead crosses', (
    tester,
  ) async {
    await pumpStoryboard(tester);
    // Nothing picked yet: the rail rests on the V row.
    expectRingOnRow(
      tester,
      'storyboard-track-row-sb-track',
      reason: 'the ring belongs to the row the rail is resting on',
    );

    // Park the playhead off frame 0 so 'follows the cursor' is a claim with
    // something to fail: at the origin every wrong x is also the right one.
    final area = find.byKey(
      const ValueKey<String>('storyboard-track-timeline-area-sb-track'),
    );
    final areaRect = tester.getRect(area);
    final cell = playheadRect(tester).width;
    await tester.tapAt(
      Offset(areaRect.left + 5.5 * cell, areaRect.top + areaRect.height / 2),
    );
    await tester.pumpAndSettle();

    expect(
      playheadRect(tester).left,
      greaterThan(areaRect.left + cell),
      reason: 'the press really moved the playhead down the axis',
    );
    expectRingOnRow(tester, 'storyboard-track-row-sb-track');
  });

  testWidgets('standing on an S row takes the ring with it', (tester) async {
    await pumpStoryboard(tester);
    final vRing = ringRect(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('storyboard-se-label-sb-track-1'),
        ),
        matching: find.text('S1'),
      ),
    );
    await tester.pumpAndSettle();

    expectRingOnRow(tester, 'storyboard-se-row-0-1');
    expect(
      ringRect(tester).top,
      isNot(moreOrLessEquals(vRing.top)),
      reason: 'the ring really moved off the V row',
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-standing-cell')),
      findsOneWidget,
      reason: 'exactly one row is stood on, so exactly one ring is drawn',
    );
  });

  testWidgets('on an S row the BLOCK under the cursor is outlined, and the '
      'ring stands down inside it', (tester) async {
    await pumpStoryboard(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('storyboard-se-label-sb-track-1'),
        ),
        matching: find.text('S1'),
      ),
    );
    await tester.pumpAndSettle();

    final seRow = find.byKey(const ValueKey<String>('storyboard-se-row-0-1'));
    final rowRect = tester.getRect(seRow);
    final cell = playheadRect(tester).width;
    // Parked at frame 0 the row's only sound (frames 1..3) is elsewhere.
    expect(
      find.byKey(const ValueKey<String>('storyboard-standing-block')),
      findsNothing,
      reason: 'an empty cell is a ring, never an outline',
    );

    // Step onto frame 2, inside the block.
    await tester.tapAt(
      Offset(rowRect.left + 2.5 * cell, rowRect.top + rowRect.height / 2),
    );
    await tester.pumpAndSettle();

    final outline = tester.getRect(
      find.byKey(const ValueKey<String>('storyboard-standing-block')),
    );
    expect(outline.left, moreOrLessEquals(rowRect.left + 1 * cell));
    expect(
      outline.width,
      moreOrLessEquals(3 * cell),
      reason: 'the sound runs frames 1..3, and the outline is the BLOCK',
    );
    expect(outline.top, moreOrLessEquals(rowRect.top));
    expect(outline.height, moreOrLessEquals(rowRect.height));
    // The ring keeps its node — the row still says where you stand — but
    // paints nothing inside a block it would only double.
    expect(
      find.byKey(const ValueKey<String>('storyboard-standing-cell')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey<String>('storyboard-standing-cell')),
          )
          .child,
      isA<SizedBox>(),
      reason: 'the block outline is the standing visual there',
    );
  });

  Future<void> twirlOpenVLanes(WidgetTester tester) async {
    await tester.tap(
      find.byKey(
        const ValueKey<String>('storyboard-track-lane-toggle-sb-track'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'storyboard-lane-group-toggle-v-track:sb-track-transform-group',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the FADE row is the Opacity lane\'s row: standing on it rings '
      'there, not back on the V row', (tester) async {
    await pumpStoryboard(tester);
    await twirlOpenVLanes(tester);

    // The one V lane whose strip is not a key-marker band — it draws the
    // cut fades. Standing has to reach it anyway, or the ring answers for
    // a row the user is not on.
    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'storyboard-lane-label-v-track:sb-track-opacity',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expectRingOnRow(tester, 'storyboard-opacity-lane-row-0');
  });

  testWidgets('standing on a V LANE row rings the lane, not its track row', (
    tester,
  ) async {
    await pumpStoryboard(tester);
    await twirlOpenVLanes(tester);

    // Stand on the Position lane by pressing its band — the storyboard's
    // own press path (R5 ③a), through the real host wiring.
    final laneRow = find.byKey(
      const ValueKey<String>('storyboard-track-lane-row-0-position'),
    );
    final rowRect = tester.getRect(laneRow);
    await tester.tapAt(Offset(rowRect.left + 6, rowRect.center.dy));
    await tester.pumpAndSettle();

    expectRingOnRow(tester, 'storyboard-track-lane-row-0-position');
    expect(
      find.byKey(const ValueKey<String>('storyboard-standing-cell')),
      findsOneWidget,
    );
  });
}
