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
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show timelineRowPaperExtent;
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineBlockCornerRadiusAt;
import 'package:anicel/src/ui/timeline/timeline_row_edit_chrome.dart'
    show TimelineRowChromeResolver, TimelineRowGripTarget;

import 'storyboard_conte_row_probe.dart';
import 'storyboard_cut_block_probe.dart';
import 'timeline/timeline_row_chrome_probe.dart';

/// A PANEL's edges are on the conte row, where the panel is a block: the
/// first panel's leading edge is the cut's, the last one's trailing edge is
/// its length. EVERY leading edge is a rolling edit with the block in front
/// of it — the panel before it, or at a cut's first panel the previous
/// cut's last panel — so the lengths trade and nothing else moves (I-21:
/// one lead edge law with the frame axis). EVERY trailing edge — inner and
/// last alike — is its panel's comma: the later panels ripple along glued
/// and the cut's length rides the row end (edge unification; the division
/// verb is gone). One shape of grip; where it sits decides what it
/// re-times.
///
/// 🗣️I-73 (유저 2026-10-08): 「띠 둘만 이사로 가자. 여기서 그럼 v행에
/// 콘티블록 위치의 칸마다 있던 엣지는 어떻게하지? 그냥 없는게 심플한거같긴
/// 한데」 — the V row hangs nothing at a panel's place. Each CUT block wears
/// its own two edges in its plate's corners (the proposal the answer took:
/// 「V 행의 엣지: 컷의 양 끝만. 썸네일 사이는 구분선만」), and they begin the
/// verbs the conte row's first and last grips begin: one edit, two doors.
/// ↩️The cut block had no grips of its own besides its panels' while the
/// panels stood inside it — in a conte block's corners, or the plate's for
/// a cut with none (유저 2026-09-26); the plate's for every cut from
/// 2026-09-25, and #757 had put them on the picture strip before that.
const _trackId = TrackId('grip-track');

/// The chrome slot each row's grips are painted in.
const _conteRow = 'storyboard';
const _vRow = 'storyboard-plate';

/// A PANEL's grip, by its ordinal on the conte row — named for the row.
String _panelGrip(String edge, int ordinal) =>
    'block-edge-grip-$edge-${trackConteRowId(_trackId).value}-$ordinal';

/// A CUT's grip, by its ordinal on the V row — named for the track.
String _cutGrip(String edge, int ordinal) =>
    'block-edge-grip-$edge-${_trackId.value}-$ordinal';

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

/// [_project] with its middle cut stripped of its storyboard layer — the
/// cut the conte row holds no panel of.
Project _mixedProject() => Project(
  id: const ProjectId('grip-project'),
  name: 'Grips',
  createdAt: DateTime.utc(2026, 7, 27),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [
        _cut('cut-1', 10, {0: 5, 5: 5}),
        Cut(
          id: const CutId('cut-2'),
          name: 'cut-2',
          duration: 10,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: [
            Layer(
              id: const LayerId('cut-2-cel'),
              name: 'A',
              frames: const [],
              timeline: const {},
            ),
          ],
        ),
        _cut('cut-3', 6, {0: 3, 3: 3}),
      ],
    ),
  ],
);

Future<void> _openStoryboard(WidgetTester tester, {Project? project}) async {
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
    MaterialApp(home: HomePage(initialProject: project ?? _project())),
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

/// Drags the chrome target [id] of [row]'s slot by [frames] whole frames.
Future<void> _dragGrip(
  WidgetTester tester,
  String id,
  int frames, {
  String row = _conteRow,
}) async {
  final gesture = await tester.startGesture(
    timelineRowChromeCenter(tester, _trackId.value, id, prefix: row),
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

/// The two doors onto ONE cut edge: the panel's grip on the conte row and
/// the cut's own on the V row. [panel] and [cut] are the grips' ordinals.
typedef _Door = ({String name, String row, String Function(String edge) grip});

List<_Door> _doors({required int panel, required int cut}) => [
  (
    name: 'the conte row',
    row: _conteRow,
    grip: (edge) => _panelGrip(edge, panel),
  ),
  (name: 'the V row', row: _vRow, grip: (edge) => _cutGrip(edge, cut)),
];

void main() {
  testWidgets('EVERY panel hangs a leading grip — the two edges of one '
      'boundary name two edits, not one', (tester) async {
    await _openStoryboard(tester);

    // Panels in track order: cut 1's two, cut 2's one, cut 3's two.
    // Panel 1 is INTERIOR to cut 1 and hangs a front grip all the same
    // (user's rule 2026-08-02). It is not the impersonation P5 #8 shipped:
    // panel 0's BACK grip grows the cut at its tail, and panel 1's FRONT
    // grip trades frames with panel 0 inside a cut that keeps its length
    // (I-21). Same boundary, two different edits.
    expect(
      timelineRowChromeIds(tester, _trackId.value, prefix: _conteRow),
      <String>[
        for (var ordinal = 0; ordinal < 5; ordinal += 1) ...[
          _panelGrip('start', ordinal),
          _panelGrip('end', ordinal),
        ],
      ],
    );
  });

  testWidgets('🗣️the V row hangs each CUT\'s two edges and nothing at a '
      'panel\'s place (유저 2026-10-08: 「v행에 콘티블록 위치의 칸마다 있던 '
      '엣지는 … 그냥 없는게 심플한거같긴한데」)', (tester) async {
    await _openStoryboard(tester);

    expect(
      timelineRowChromeIds(tester, _trackId.value, prefix: _vRow),
      <String>[
        for (var ordinal = 0; ordinal < 3; ordinal += 1) ...[
          _cutGrip('start', ordinal),
          _cutGrip('end', ordinal),
        ],
      ],
      reason: '↩️a cut with conte blocks had none of its own (유저 '
          '2026-09-26: 「컷블록의 엣지만 삭제」) while they stood inside it',
    );
  });

  testWidgets('a panel\'s edges sit in its own block\'s corners on the '
      'conte row, and a cut\'s in its plate\'s — whether or not the cut has '
      'a conte layer', (tester) async {
    await _openStoryboard(tester, project: _mixedProject());

    final vRow = tester.getRect(
      find.byKey(
        ValueKey<String>('storyboard-track-timeline-area-${_trackId.value}'),
      ),
    );
    final conteRow = conteRowRect(tester, _trackId.value);
    const band = StoryboardCutBlocksPainter.bandHeight;
    // Panels in track order: cut 1's two and cut 3's two — cut 2 has none.
    expect(
      timelineRowChromeIds(tester, _trackId.value, prefix: _conteRow),
      <String>[
        for (var ordinal = 0; ordinal < 4; ordinal += 1) ...[
          _panelGrip('start', ordinal),
          _panelGrip('end', ordinal),
        ],
      ],
      reason: 'the panels\' edges, on the conte row',
    );
    expect(
      timelineRowChromeIds(tester, _trackId.value, prefix: _vRow),
      <String>[
        for (var ordinal = 0; ordinal < 3; ordinal += 1) ...[
          _cutGrip('start', ordinal),
          _cutGrip('end', ordinal),
        ],
      ],
      reason: 'every cut\'s, on its plate — the layerless one\'s among them',
    );

    Rect grip(String id, String row) =>
        timelineRowChromeGlobalRect(tester, _trackId.value, id, prefix: row);
    // I-43: the grip is its triangle's box, in the block's corners — the
    // end edge's at the top, the start edge's at the bottom. On the plate
    // it is a band deep, never over the pictures (I-52; ↩️half the paper).
    for (var cut = 0; cut < 3; cut += 1) {
      final end = grip(_cutGrip('end', cut), _vRow);
      final start = grip(_cutGrip('start', cut), _vRow);
      expect(end.top, moreOrLessEquals(vRow.top), reason: 'cut $cut');
      expect(end.height, moreOrLessEquals(band), reason: 'cut $cut');
      expect(start.bottom, moreOrLessEquals(vRow.bottom), reason: 'cut $cut');
      expect(start.height, moreOrLessEquals(band), reason: 'cut $cut');
    }
    // On the conte row it is the timeline row's own: half the block's
    // paper, which stops short of the row's seam (I-44).
    final paper = timelineRowPaperExtent(conteRow.height);
    for (var panel = 0; panel < 4; panel += 1) {
      final end = grip(_panelGrip('end', panel), _conteRow);
      final start = grip(_panelGrip('start', panel), _conteRow);
      expect(end.top, moreOrLessEquals(conteRow.top), reason: 'panel $panel');
      expect(end.height, moreOrLessEquals(paper / 2), reason: 'panel $panel');
      expect(
        start.bottom,
        moreOrLessEquals(conteRow.top + paper),
        reason: 'panel $panel',
      );
      expect(
        start.height,
        moreOrLessEquals(paper / 2),
        reason: 'panel $panel',
      );
    }
  });

  test('a resolver over the same blocks but another paper is another '
      'resolver', _sameBlocksOtherPaper);

  testWidgets('a triangle takes the corner of the paper it stands in — the '
      'plate\'s round on the V row, the frame block\'s on the conte row', (
    tester,
  ) async {
    await _openStoryboard(tester, project: _mixedProject());

    TimelineRowGripTarget grip(String id, String row) =>
        timelineRowChromeTarget(tester, _trackId.value, id, prefix: row)
            as TimelineRowGripTarget;
    // The corner a frame block wears on this row at this zoom — ↩️square
    // while a conte block lay inside its cut's plate (유저 2026-09-26:
    // 「블록이 모서리 둥근건 블록 자체」); a panel is a block itself here.
    final block = timelineBlockCornerRadiusAt(
      cellExtent: _pixelsPerFrame(tester),
      crossExtent: timelineRowPaperExtent(
        conteRowRect(tester, _trackId.value).height,
      ),
    ).x;
    expect(block, greaterThan(0), reason: '⛔전제: a round block');
    for (var panel = 0; panel < 4; panel += 1) {
      for (final edge in ['start', 'end']) {
        expect(
          grip(_panelGrip(edge, panel), _conteRow).paperCorner,
          block,
          reason: 'panel $panel\'s $edge edge',
        );
      }
    }
    // The plate's own corner, as its painter rounds it (F-219).
    final plate = cutBlocksPainter(tester).plateCorner.x;
    expect(plate, greaterThan(0), reason: '⛔전제: a round plate');
    for (var cut = 0; cut < 3; cut += 1) {
      for (final edge in ['start', 'end']) {
        expect(
          grip(_cutGrip(edge, cut), _vRow).paperCorner,
          plate,
          reason: 'cut $cut\'s $edge edge',
        );
      }
    }

    // And the painter draws by it: the ink follows the plate's round.
    Path inkOf(String row, TimelineRowGripTarget target) {
      final laid = _PathSpy();
      timelineRowChromePainter(tester, _trackId.value, prefix: row)!.paint(
        laid,
        tester.getSize(timelineRowChromeFinder(_trackId.value, prefix: row)),
      );
      return laid.paths.firstWhere(
        (path) => target.rect.inflate(1).contains(path.getBounds().center),
      );
    }

    for (var cut = 0; cut < 3; cut += 1) {
      final plateEnd = grip(_cutGrip('end', cut), _vRow);
      // A point well inside the round's reach at whatever the law gives
      // this zoom (the round crosses the diagonal at ~0.29 of its radius).
      expect(
        inkOf(_vRow, plateEnd).contains(
          plateEnd.rect.topRight.translate(-plate / 6, plate / 6),
        ),
        isFalse,
        reason: 'cut $cut: the plate\'s own round takes the tip',
      );
      // Halfway down the right leg: inside the triangle a band deep
      // (I-52), and inside the round.
      expect(
        inkOf(_vRow, plateEnd).contains(
          plateEnd.rect.topRight.translate(-1, plateEnd.rect.height / 2),
        ),
        isTrue,
        reason: '⛔전제: the ink is there, inside the round',
      );
    }
  });

  testWidgets('an edge BETWEEN two panels is that panel\'s COMMA (edge '
      'unification): the later panel ripples along glued and the cut\'s '
      'length rides the row end', (tester) async {
    await _openStoryboard(tester);
    expect(_divisionsOf(tester, 'cut-1'), [0, 5]);

    await _dragGrip(tester, _panelGrip('end', 0), 2);

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

    await _dragGrip(tester, _panelGrip('end', 0), 2);
    expect(_divisionsOf(tester, 'cut-1'), [0, 7]);
    expect(_cutById(tester, 'cut-1').duration, 12);

    await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
    await tester.pumpAndSettle();

    expect(_divisionsOf(tester, 'cut-1'), [0, 5]);
    expect(_cutById(tester, 'cut-1').duration, 10);
  });

  for (final door in _doors(panel: 1, cut: 0)) {
    testWidgets('the LAST panel\'s trailing edge is still the cut\'s LENGTH '
        '— and the stored comma moves with it (feedback #9), from '
        '${door.name}', (tester) async {
      await _openStoryboard(tester);

      await _dragGrip(tester, door.grip('end'), 3, row: door.row);

      expect(_cutById(tester, 'cut-1').duration, 13);
      expect(_divisionsOf(tester, 'cut-1'), [0, 5]);
      // The edge is the ROW's edge: the last cell's stored comma grew by
      // the same 3 the cut did, so store and coverage stay one picture.
      final layer = storyboardLayerForCut(_cutById(tester, 'cut-1'))!;
      expect(layer.timeline[5]!.length, 8);
    });
  }

  for (final door in _doors(panel: 2, cut: 1)) {
    testWidgets('a cut with ONE panel keeps exactly the two grips it had: '
        'the new rule\'s degenerate case is the old behaviour, from '
        '${door.name}', (tester) async {
      await _openStoryboard(tester);

      await _dragGrip(tester, door.grip('end'), 4, row: door.row);

      expect(_cutById(tester, 'cut-2').duration, 14);
      expect(_divisionsOf(tester, 'cut-2'), [0]);
    });
  }

  for (final door in _doors(panel: 4, cut: 2)) {
    testWidgets('the LAST cut\'s trailing edge is reachable: the movie-end '
        'handle no longer sits on top of it, from ${door.name}', (
      tester,
    ) async {
      await _openStoryboard(tester);

      // Cut 3 ends where the movie does, so its trailing edge grip and the
      // end-line handle share a frame. The handle is grabbed from the
      // empty side of the line now, which leaves the grip its own pixels.
      await _dragGrip(tester, door.grip('end'), 2, row: door.row);

      expect(_cutById(tester, 'cut-3').duration, 8);
    });
  }

  testWidgets('a cut with NO conte layer trims by its own two edges',
      (tester) async {
    await _openStoryboard(tester, project: _mixedProject());

    await _dragGrip(tester, _cutGrip('end', 1), 4, row: _vRow);
    expect(_cutById(tester, 'cut-2').duration, 14);

    await _dragGrip(tester, _cutGrip('start', 1), 2, row: _vRow);
    expect(
      _cutById(tester, 'cut-2').duration,
      12,
      reason: 'the lead edge is one verb for every cut (R10 R4)',
    );
    expect(
      _cutById(tester, 'cut-1').duration,
      12,
      reason: 'the block in front took the frames (I-21)',
    );
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

    await _dragGrip(tester, _panelGrip('end', 3), -1);

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
    for (final door in _doors(panel: 0, cut: 0)) {
      testWidgets('the cut loses frames off its front, its END holds, and '
          'the emptiness lands at the head of the film — whether or not '
          'the cut has been drawn on, from ${door.name}', (tester) async {
        await _openStoryboard(tester);
        final firstStart = _cutById(tester, 'cut-1').leadingGapFrames;
        expect(firstStart, 0);

        await _dragGrip(tester, door.grip('start'), 2, row: door.row);

        // Cut 1's first panel is the FIRST block of the film, so there is
        // no block in front to trade with: the head is directly in front
        // of it and takes the 2 frames.
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
        expect(row.timeline[0]!.length, 3, reason: 'the first panel, 5 -> 3');
        expect(row.timeline[3]!.length, 5, reason: 'the other one, untouched');
      });
    }

    testWidgets('an INNER panel\'s front grip trades with the panel in front: '
        'that one grows, this one shrinks, and the cut keeps its length', (
      tester,
    ) async {
      await _openStoryboard(tester);
      expect(_divisionsOf(tester, 'cut-1'), [0, 5]);

      await _dragGrip(tester, _panelGrip('start', 1), 2);

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
      await _dragGrip(tester, _panelGrip('end', 0), 2);
      expect(_divisionsOf(tester, 'cut-1'), [0, 7]);
      expect(_cutById(tester, 'cut-1').duration, 12);
      expect(_cutById(tester, 'cut-1').leadingGapFrames, 0);

      await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
      await tester.pumpAndSettle();

      await _dragGrip(tester, _panelGrip('start', 1), 2);
      expect(_divisionsOf(tester, 'cut-1'), [0, 7]);
      expect(_cutById(tester, 'cut-1').duration, 10);
      expect(_cutById(tester, 'cut-1').leadingGapFrames, 0);
    });

    testWidgets('ONE undo restores the cut length and the head together', (
      tester,
    ) async {
      await _openStoryboard(tester);

      await _dragGrip(tester, _panelGrip('start', 0), 2);
      expect(_cutById(tester, 'cut-1').duration, 8);
      expect(_cutById(tester, 'cut-1').leadingGapFrames, 2);

      await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
      await tester.pumpAndSettle();

      expect(_cutById(tester, 'cut-1').duration, 10);
      expect(_cutById(tester, 'cut-1').leadingGapFrames, 0);
    });

    for (final door in _doors(panel: 2, cut: 1)) {
      testWidgets('on a LATER cut the block in front is the previous cut\'s '
          'LAST panel: it grows, this cut shrinks, and nothing else moves, '
          'from ${door.name}', (tester) async {
        await _openStoryboard(tester);

        await _dragGrip(tester, door.grip('start'), 2, row: door.row);

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
    }
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

/// The same blocks on a plate of other bands hang their triangles elsewhere
/// — so the row must not keep the old resolver. (↩️Or of another CORNER,
/// while the plate's corner was handed in beside its bands; the grips read
/// the block law's themselves now, which is the plate's.)
void _sameBlocksOtherPaper() {
  TimelineRowChromeResolver resolver({double band = 13}) =>
      TimelineRowChromeResolver(
        gripBlocks: const [
          (
            ordinal: 0,
            startIndex: 0,
            endIndexExclusive: 5,
            startGrip: true,
            endGrip: true,
          ),
          (
            ordinal: 1,
            startIndex: 5,
            endIndexExclusive: 10,
            startGrip: true,
            endGrip: true,
          ),
        ],
        gripIdScope: 'track',
        layer: null,
        baseLayer: null,
        crossAxisExtent: 64,
        axis: Axis.horizontal,
        includeRunEdges: false,
        gripBand: band,
      );
  final row = resolver();
  expect(row.matches(resolver()), isTrue);
  expect(
    row.matches(resolver(band: 20)),
    isFalse,
    reason: 'bands of another depth hang the triangles elsewhere (I-52)',
  );
}

/// Every path a painter fills, as it filled it.
class _PathSpy implements Canvas {
  final paths = <Path>[];

  @override
  void drawPath(Path path, Paint paint) => paths.add(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
