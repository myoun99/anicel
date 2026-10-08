import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kDoubleTapTimeout, kSecondaryButton;
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
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show timelineRowPaperExtent;
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineRangeSelectionBandDecorationAt;
import 'package:anicel/src/ui/timeline/timeline_double_tap.dart';

import 'storyboard_conte_row_probe.dart';
import 'storyboard_cut_block_probe.dart';

/// THE CONTE ROW is a row of its own, under the V row (I-73, 유저
/// 2026-10-08: 「우선 v행은 지금처럼 보여주는건 그대로 보여줘 … 컷 선택만
/// 되도록. 그러고 v행 아래에 콘티행 만들어서 거기서」 · 「띠 둘만 이사로
/// 가자」).
///
/// Its blocks are a cut's own: it speaks the cut's axis, which is why a
/// drag on it cannot leave the cut it started in — the "clip to the anchor
/// cut" rule arriving as arithmetic instead of as a guard. The V row above
/// it is the CUT's alone: its bands and its pictures alike.
///
/// ↩️The panels lay INSIDE the cut block — a picture strip between two bands
/// of their own — and the split between them and the cut's bands was
/// hit-testing within one row (「The STRIP is a row of its own」, said of a
/// slot of the V row).
const _trackId = TrackId('strip-track');
final _conteRow = LayerRowAddress(trackConteRowId(_trackId));

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

/// Cut 1 covers [0,10) with panels at 0 and 5; cut 2 covers [10,20) with
/// panels at 0 and 4 (local); cut 3 covers [20,30) with NO storyboard
/// layer (the D30 create affordance's home).
Project _project() => Project(
  id: const ProjectId('strip-project'),
  name: 'Strip',
  createdAt: DateTime.utc(2026, 7, 27),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [
        _cut('cut-1', 10, {0: 5, 5: 5}),
        _cut('cut-2', 10, {0: 4, 4: 6}),
        Cut(
          id: const CutId('cut-3'),
          name: 'cut-3',
          duration: 10,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: [
            Layer(
              id: const LayerId('cut-3-cel'),
              name: 'A',
              frames: const [],
              timeline: const {},
            ),
          ],
        ),
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

StoryboardPanel _panel(WidgetTester tester) =>
    tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));

double _pixelsPerFrame(WidgetTester tester) => _panel(tester).pixelsPerFrame;

/// The cut the panel is handed as active — a cut block no longer wears it
/// (F-212).
CutId? _activeCut(WidgetTester tester) => _panel(tester).activeCutId;

EditorSessionManager _session(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

Cut _cutOf(WidgetTester tester, String id) => _panel(
  tester,
).project.tracks.single.cuts.firstWhere((cut) => cut.id == CutId(id));

bool _hasConteLayer(WidgetTester tester, String cutId) => _cutOf(
  tester,
  cutId,
).layers.any((layer) => layer.kind == LayerKind.storyboard);

Rect _cutRowRect(WidgetTester tester) {
  final row = find.byKey(
    ValueKey<String>('storyboard-track-timeline-area-${_trackId.value}'),
  );
  return tester.getTopLeft(row) & tester.getSize(row);
}

Rect _conteRowRect(WidgetTester tester) =>
    conteRowRect(tester, _trackId.value);

/// A point on the CONTE ROW over [globalFrame] — a panel, the create button
/// of a cut with no conte layer, or an empty stretch.
Offset _contePoint(WidgetTester tester, int globalFrame) {
  final rect = _conteRowRect(tester);
  return Offset(
    rect.left + (globalFrame + 0.5) * _pixelsPerFrame(tester),
    rect.center.dy,
  );
}

/// A point on the V row's PICTURES over [globalFrame].
Offset _picturePoint(WidgetTester tester, int globalFrame) {
  final rect = _cutRowRect(tester);
  return Offset(
    rect.left + (globalFrame + 0.5) * _pixelsPerFrame(tester),
    rect.top + rect.height / 2,
  );
}

/// A point on the V row's TOP band over [globalFrame] — the cut's name.
Offset _bandPoint(WidgetTester tester, int globalFrame) {
  final rect = _cutRowRect(tester);
  return Offset(
    rect.left + (globalFrame + 0.5) * _pixelsPerFrame(tester),
    rect.top + StoryboardCutBlocksPainter.bandHeight / 2,
  );
}

Future<void> _drag(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await tester.startGesture(
    from,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('the row', () {
    testWidgets('stands directly under the V row, one row tall, on the same '
        'frames', (tester) async {
      await _openStoryboard(tester);

      final cuts = _cutRowRect(tester);
      final conte = _conteRowRect(tester);
      expect(conte.top, cuts.bottom);
      expect(conte.left, cuts.left);
      expect(conte.height, 30);
    });

    testWidgets('draws each cut\'s panels at the cut\'s own place, as ONE '
        'row of blocks on the track\'s axis', (tester) async {
      await _openStoryboard(tester);

      // Cut 1 [0,10): 0·5 and 5·5. Cut 2 [10,20): 0·4 and 4·6, ten frames
      // in. Cut 3 has no conte layer, so the row holds nothing over it.
      expect(conteRowBlocks(tester, _trackId.value), {
        0: 5,
        5: 5,
        10: 4,
        14: 6,
      });
      final shown = conteRowShown(tester, _trackId.value);
      expect(shown.id, trackConteRowId(_trackId));
      expect(shown.kind, LayerKind.storyboard);
      expect(
        shown.timeline[14]!.frameId,
        const FrameId('cut-2-4'),
        reason: 'a block shows its own cut\'s drawing',
      );
    });

    testWidgets('a cut with no conte layer wears the + over its WHOLE '
        'stretch of the row, in the block\'s own shape — and no other '
        'stretch wears one', (tester) async {
      await _openStoryboard(tester);
      final ppf = _pixelsPerFrame(tester);

      final plates = conteCreatePlates(tester, _trackId.value);

      expect(plates, hasLength(1), reason: 'cut 3 alone has no conte layer');
      expect(plates.single.left, moreOrLessEquals(20 * ppf));
      expect(plates.single.right, moreOrLessEquals(30 * ppf));
      expect(plates.single.top, 0);
      expect(
        plates.single.height,
        timelineRowPaperExtent(_conteRowRect(tester).height),
        reason: 'the paper a block of this row stands on, short of the seam',
      );
    });

    testWidgets('its cells are held to the cuts that HAVE a conte layer: no '
        'timesheet X over a cut without one, or past the last cut', (
      tester,
    ) async {
      await _openStoryboard(tester);
      final ppf = _pixelsPerFrame(tester);
      final clip = conteCellsClip(tester, _trackId.value);
      bool shows(int frame) => clip.contains(Offset((frame + 0.5) * ppf, 15));

      expect(shows(3), isTrue, reason: 'cut 1');
      expect(shows(19), isTrue, reason: 'cut 2, to its last frame');
      expect(
        shows(20),
        isFalse,
        reason: 'cut 3 has no conte layer: its first cell is an empty run\'s '
            'start to the row\'s painter, and would wear the X',
      );
      expect(shows(34), isFalse, reason: 'past the last cut');
      expect(
        conteRowPainter(tester, _trackId.value).cellModelAt(20).glyph,
        'X',
        reason: '⛔전제: the painter does write it there — the clip is what '
            'keeps it off the row',
      );
    });
  });

  testWidgets('a drag on the conte row selects the cut\'s PANELS, on the '
      'cut\'s own axis', (tester) async {
    await _openStoryboard(tester);

    await _drag(tester, _contePoint(tester, 1), _contePoint(tester, 6));

    final selection = _panel(tester).stripSelect!.selection.value!;
    // Cut 1's panels are [0,5) and [5,10) in LOCAL frames: the drag took
    // both, snapped whole.
    expect(selection.layerId, const LayerId('cut-1-sb'));
    expect(selection.startIndex, 0);
    expect(selection.endIndexExclusive, 10);
  });

  testWidgets('the drag CANNOT leave its cut: a sweep into the next one '
      'stops at the anchor cut\'s end', (tester) async {
    await _openStoryboard(tester);

    // Start in cut 1, sweep well into cut 2 (which begins at global 10).
    await _drag(tester, _contePoint(tester, 1), _contePoint(tester, 17));

    final selection = _panel(tester).stripSelect!.selection.value!;
    expect(selection.layerId, const LayerId('cut-1-sb'));
    expect(selection.endIndexExclusive, 10);
  });

  testWidgets('the anchor cut is the one PRESSED, not the one that was '
      'active: pressing cut 2 makes it the subject', (tester) async {
    await _openStoryboard(tester);

    await _drag(tester, _contePoint(tester, 11), _contePoint(tester, 12));

    final selection = _panel(tester).stripSelect!.selection.value!;
    expect(selection.layerId, const LayerId('cut-2-sb'));
    // Local [0,4) — cut 2's first panel, snapped whole.
    expect(selection.startIndex, 0);
    expect(selection.endIndexExclusive, 4);
  });

  testWidgets('a selection is its own cut\'s: a press on ANOTHER cut\'s '
      'panel, at a frame the selection covers by number, is a press '
      'outside it', (tester) async {
    await _openStoryboard(tester);
    // Cut 1's first panel: its own frames [0,5).
    await _drag(tester, _contePoint(tester, 1), _contePoint(tester, 2));
    expect(
      _panel(tester).stripSelect!.selection.value!.layerId,
      const LayerId('cut-1-sb'),
      reason: 'the premise',
    );

    // Cut 2 begins at global 10, so global 11 is its own frame 1 — a NUMBER
    // cut 1's selection covers. It is not inside that selection, and what
    // tells the two apart is the PRESS: outside lets the selection go there
    // and then, inside waits to see whether the hand moves it.
    final press = await tester.startGesture(
      _contePoint(tester, 11),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(
      _panel(tester).stripSelect!.selection.value,
      isNull,
      reason: 'let go at the press, before it is a tap or a drag',
    );

    await press.moveTo(_contePoint(tester, 16));
    await tester.pump();
    await press.up();
    await tester.pumpAndSettle();
    final selection = _panel(tester).stripSelect!.selection.value!;
    expect(selection.layerId, const LayerId('cut-2-sb'));
    expect(selection.startIndex, 0);
    expect(
      selection.endIndexExclusive,
      10,
      reason: 'both of cut 2\'s panels, [0,4) and [4,10), snapped whole',
    );
  });

  testWidgets('a tap on a panel drops the panels\' selection', (tester) async {
    await _openStoryboard(tester);
    await _drag(tester, _contePoint(tester, 1), _contePoint(tester, 2));
    expect(
      _panel(tester).stripSelect!.selection.value,
      isNotNull,
      reason: 'the premise',
    );

    await tester.tapAt(_contePoint(tester, 7), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(_panel(tester).stripSelect!.selection.value, isNull);
  });

  // 🗣️I-73 (유저 2026-10-08): 「선택도 내부 콘티쪽 조작해도 지금
  // 콘티블록이 선택되는데 그게아니라 컷 선택만 되도록」 — drawn in the
  // proposal that answer took as 「어디를 잡아도 컷입니다. 칸에 서지 않고,
  // 안쪽을 끌어도 컷이 선택됩니다」. ↩️The pictures and the conte blocks'
  // bands were the panels' (유저 2026-09-26: 「내부에 콘티블록 있으면
  // 콘티블록의 띠도 생겨서」), and only the cut's own two bands the cut's.
  for (final (where, point) in [
    ('its band', _bandPoint),
    ('its pictures', _picturePoint),
  ]) {
    testWidgets('🗣️a drag on a cut block is the CUT\'s, on $where', (
      tester,
    ) async {
      await _openStoryboard(tester);

      await _drag(tester, point(tester, 1), point(tester, 6));

      expect(_panel(tester).cutSelect!.selectedRange.value, isNotNull);
      expect(_panel(tester).stripSelect!.selection.value, isNull);
    });
  }

  testWidgets('a drag that starts INSIDE the selection slides the panels — '
      'and on a row that tiles its cut, sliding means reordering', (
    tester,
  ) async {
    await _openStoryboard(tester);
    // Take cut 1's first panel [0,5), then drag from inside it past the
    // midpoint of the second.
    await _drag(tester, _contePoint(tester, 1), _contePoint(tester, 2));
    expect(_panel(tester).stripSelect!.selection.value!.endIndexExclusive, 5);

    await _drag(tester, _contePoint(tester, 2), _contePoint(tester, 8));

    final layer = _cutOf(
      tester,
      'cut-1',
    ).layers.firstWhere((layer) => layer.id == const LayerId('cut-1-sb'));
    // The two panels swapped and the row still tiles [0,10) exactly: with
    // no free space to re-time into, the only move a gapless row has is a
    // reorder, which is why its panels can never leave the cut.
    expect(layer.timeline.keys, [0, 5]);
    expect(layer.timeline[0]!.frameId, const FrameId('cut-1-5'));
    expect(layer.timeline[5]!.frameId, const FrameId('cut-1-0'));
  });

  // ↩️F-203 (유저 2026-09-28: 「v행 선택범위로 선택…하고 컷 잡아끌때 띠만
  // 잡아야 반응하는상황? 그냥 컷 어디 잡아끌든 컷 움직이게」) had the panels'
  // gesture stand down inside a selected run, because the conte blocks lay
  // over the cut block. They lie under it now, on a row the run does not
  // cover — so a sweep there is the panels', under the very run.
  testWidgets('the two selections stay mutually exclusive: taking one on '
      'the conte row drops the cut run — under the run itself', (tester) async {
    await _openStoryboard(tester);
    await _drag(tester, _bandPoint(tester, 1), _bandPoint(tester, 6));
    expect(_panel(tester).cutSelect!.selectedRange.value, isNotNull);

    await _drag(tester, _contePoint(tester, 1), _contePoint(tester, 2));

    expect(_panel(tester).stripSelect!.selection.value, isNotNull);
    expect(_panel(tester).cutSelect!.selectedRange.value, isNull);
  });

  testWidgets('🚨F-203: with a cut run selected, a drag on its PICTURES '
      'slides the run like a drag on the cut\'s own band', (tester) async {
    await _openStoryboard(tester);
    // Cut 2 [10,20) as a run, taken on its band.
    await _drag(tester, _bandPoint(tester, 11), _bandPoint(tester, 18));
    int startOfCut2() => buildStoryboardTimelineLayout(
      _panel(tester).project,
    ).firstWhere((entry) => entry.cutId == const CutId('cut-2')).startFrame;
    expect(_panel(tester).cutSelect!.selectedRange.value, isNotNull);
    expect(startOfCut2(), 10, reason: '⛔전제');

    // Past cut 3, grabbed in the middle of cut 2. On this gapless row the
    // same drag on the cut's own band lands cut 2 at 27 (a shorter one does
    // not move it at all).
    await _drag(tester, _picturePoint(tester, 16), _picturePoint(tester, 33));

    expect(
      startOfCut2(),
      27,
      reason: '🚨the run did not move as the band drag moves it',
    );
    expect(
      _panel(tester).stripSelect!.selection.value,
      isNull,
      reason: 'no panel selection was taken',
    );
  });

  testWidgets('D30: the panels\' selection draws the timeline\'s ONE band at '
      'the selected panels', (tester) async {
    await _openStoryboard(tester);

    await _drag(tester, _contePoint(tester, 1), _contePoint(tester, 6));
    final band = find.byKey(
      const ValueKey<String>('storyboard-strip-range-selection'),
    );
    expect(band, findsOneWidget, reason: 'the band was MISSING — the '
        'selection had no visual of its own on this panel');

    // The selection snapped to the whole cut-1 span [0,10): the band's
    // rect covers exactly those frames.
    final rowRect = _conteRowRect(tester);
    final ppf = _pixelsPerFrame(tester);
    final bandRect = tester.getRect(band);
    expect(bandRect.left, moreOrLessEquals(rowRect.left, epsilon: 1));
    expect(bandRect.width, moreOrLessEquals(10 * ppf, epsilon: 1));
    // Across, it is the conte row's own height (↩️the conte blocks' slot
    // inside the cut's two bands).
    expect(bandRect.top, moreOrLessEquals(rowRect.top));
    expect(bandRect.bottom, moreOrLessEquals(rowRect.bottom));
    // And round, as the frame blocks it selects are (F-26: the band takes
    // the shape of what it selects; ↩️square while a conte block lay inside
    // its cut's plate).
    final decoration = tester
        .widget<DecoratedBox>(
          find.descendant(of: band, matching: find.byType(DecoratedBox)),
        )
        .decoration;
    expect(
      (decoration as BoxDecoration).borderRadius,
      timelineRangeSelectionBandDecorationAt(
        cellExtent: ppf,
        crossExtent: rowRect.height,
      ).borderRadius,
    );
    expect(decoration.borderRadius, isNot(BorderRadius.zero));
  });

  testWidgets('a panel selection made of a cut that does not start the '
      'track is drawn where that cut stands', (tester) async {
    await _openStoryboard(tester);

    // Cut 2's second panel: local [4,10), the track's [14,20).
    await _drag(tester, _contePoint(tester, 16), _contePoint(tester, 17));

    final selection = _panel(tester).stripSelect!.selection.value!;
    expect((selection.startIndex, selection.endIndexExclusive), (4, 10));
    final rowRect = _conteRowRect(tester);
    final ppf = _pixelsPerFrame(tester);
    final bandRect = tester.getRect(
      find.byKey(const ValueKey<String>('storyboard-strip-range-selection')),
    );
    expect(bandRect.left, moreOrLessEquals(rowRect.left + 14 * ppf));
    expect(bandRect.width, moreOrLessEquals(6 * ppf));
  });

  /// 🚨H13 (유저 2026-08-22) — 「스토리보드레이어 추가버튼, **액티브컷에만
  /// 띄우는게아니라 그런 규칙 두지말고** 그냥 다른 컷블록도 없으면 띄우도록」
  ///
  /// ⚠️This test used to assert the opposite ("the first press SELECTS, the
  /// next one creates"), which is the rule the user struck. D30's REAL
  /// guard — the press judging the snapshot the + was drawn from — is
  /// untouched and still pinned below; what went is the disagreement between
  /// what was drawn and what was pressable.
  testWidgets('H13: every layerless cut wears the +, active or not — one '
      'press on the drawn + creates', (tester) async {
    await _openStoryboard(tester);
    expect(_hasConteLayer(tester, 'cut-3'), isFalse);
    expect(
      _activeCut(tester),
      isNot(const CutId('cut-3')),
      reason: 'the premise: cut-3 is layerless AND not the active cut',
    );

    // One press on cut-3's stretch of the conte row — its + is drawn there.
    await tester.tapAt(_contePoint(tester, 25));
    await tester.pumpAndSettle();
    expect(
      _hasConteLayer(tester, 'cut-3'),
      isTrue,
      reason: 'the + was on screen before the press, so pressing it means '
          'what it says — no second press to earn the affordance first',
    );
    expect(
      _activeCut(tester),
      const CutId('cut-3'),
      reason: 'and the press still takes the cut, as a press on any block does',
    );
    expect(
      conteCreatePlates(tester, _trackId.value),
      isEmpty,
      reason: 'the button gives way to the block it made',
    );
    expect(conteRowBlocks(tester, _trackId.value)[20], 10);
  });

  testWidgets('D30: the + is the conte row\'s — a press on the cut block '
      'above it never creates', (tester) async {
    await _openStoryboard(tester);

    // The cut block's pictures are where the + stood until 2026-09-26, and
    // its inner band until I-73: a press there selects the cut and nothing
    // more — twice over, to show the miss is not a "first press earns it"
    // rung (H13 retired that).
    await tester.tapAt(_picturePoint(tester, 25));
    await tester.pumpAndSettle();
    expect(_activeCut(tester), const CutId('cut-3'));

    await tester.tapAt(_picturePoint(tester, 25));
    await tester.pumpAndSettle();

    expect(_hasConteLayer(tester, 'cut-3'), isFalse);
  });

  testWidgets('D30: a press on a cut that HAS a conte layer creates nothing '
      '— on its panels or anywhere else', (tester) async {
    await _openStoryboard(tester);
    int conteLayersOf(String cutId) => _cutOf(
      tester,
      cutId,
    ).layers.where((layer) => layer.kind == LayerKind.storyboard).length;

    await tester.tapAt(_contePoint(tester, 3));
    await tester.pumpAndSettle();

    expect(conteLayersOf('cut-1'), 1);
    expect(_hasConteLayer(tester, 'cut-3'), isFalse);
  });

  testWidgets('D30: a SECONDARY-button press on the + never creates — the '
      'create runs under the press\'s own button gate', (tester) async {
    await _openStoryboard(tester);
    // No priming press: cut-3 wears its + from the first frame (H13), so
    // the secondary button is the only thing this test varies.
    final gesture = await tester.startGesture(
      _contePoint(tester, 25),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_hasConteLayer(tester, 'cut-3'), isFalse);
  });

  // ↩️「a press INSIDE the live cut selection is starting a move — it neither
  // seeks nor creates, even over a drawn +」: true while the + stood inside
  // the cut block, where a selected run covered it. The run covers the V row
  // and not this one.
  testWidgets('the + answers under a selected cut run: the run is the V '
      'row\'s, and the + is not on it', (tester) async {
    await _openStoryboard(tester);
    await _drag(tester, _bandPoint(tester, 21), _bandPoint(tester, 28));
    expect(_panel(tester).cutSelect!.selectedRange.value, isNotNull);

    await tester.tapAt(_contePoint(tester, 25));
    await tester.pumpAndSettle();

    expect(_hasConteLayer(tester, 'cut-3'), isTrue);
  });

  testWidgets('D27: a cut\'s semantics label carries no leftover joiner '
      'spaces', (tester) async {
    await _openStoryboard(tester);
    final painter = cutBlocksPainter(tester, trackId: _trackId.value);
    for (final node in painter.semanticsBuilder(const Size(1500, 64))) {
      final label = node.properties.label!;
      expect(label.trim(), label, reason: 'edge space in "$label"');
      expect(
        label.contains('  '),
        isFalse,
        reason: 'double space in "$label"',
      );
    }
  });

  group('standing', () {
    testWidgets('🗣️a press on a panel stands on the CONTE ROW, in the cut '
        'under it, and seats the timeline on that cut\'s conte layer', (
      tester,
    ) async {
      await _openStoryboard(tester);

      await tester.tapAt(_contePoint(tester, 16));
      await tester.pumpAndSettle();

      final session = _session(tester);
      expect(session.selectedRow, _conteRow);
      expect(session.storyboardStandingRow, _conteRow);
      expect(_activeCut(tester), const CutId('cut-2'));
      expect(session.activeLayerId, const LayerId('cut-2-sb'));
      expect(session.editingGlobalFrame, 16);
    });

    testWidgets('🗣️a press on a cut block stands on the CUT and seats no row '
        'of it: the timeline stays on the row it was on (↩️it moved to the '
        'cut\'s conte layer)', (tester) async {
      await _openStoryboard(tester);
      final session = _session(tester);
      // Cut 1's cel layer in hand, by the timeline's own pick.
      const cel = LayerId('cut-1-cel');
      session.standOnRow(const LayerRowAddress(cel));
      await tester.pumpAndSettle();
      expect(session.activeLayerId, cel, reason: '⛔전제');

      await tester.tapAt(_picturePoint(tester, 3));
      await tester.pumpAndSettle();

      expect(session.selectedRow, const TrackRowAddress(_trackId));
      expect(_activeCut(tester), const CutId('cut-1'));
      expect(
        session.activeLayerId,
        cel,
        reason: '🗣️유저 2026-10-08: 「컷에 설때는 예전처럼 마지막에 섯던 '
            '행에 서있는채로 그대로. 콘티행에 서야 콘티행에 서도록」',
      );
    });

    testWidgets('the conte row\'s label picks the row, where the playhead '
        'stands', (tester) async {
      await _openStoryboard(tester);
      await tester.tapAt(_picturePoint(tester, 16));
      await tester.pumpAndSettle();
      expect(_session(tester).selectedRow, const TrackRowAddress(_trackId));

      await tester.tap(
        find.byKey(
          ValueKey<String>('storyboard-conte-label-${_trackId.value}'),
        ),
      );
      await tester.pumpAndSettle();

      final session = _session(tester);
      expect(session.selectedRow, _conteRow);
      expect(session.editingGlobalFrame, 16);
      expect(session.activeLayerId, const LayerId('cut-2-sb'));
      // …and it is the one row the rail lights.
      const lit = ValueKey<String>('storyboard-selected-row');
      expect(find.byKey(lit), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(
            ValueKey<String>('storyboard-conte-label-${_trackId.value}'),
          ),
          matching: find.byKey(lit),
        ),
        findsOneWidget,
      );
    });
  });

  group('🗣️F-255 — a block opens its name on a double click', () {
    // 유저 2026-10-01: 「이름변경 입구 확대. 지금 프레임블록이랑 레이어라벨
    // 더블클릭하면 이름편집인데 콘티블록이나 컷블록에도 통일적용」 — the
    // frame blocks' same-cell double tap, on the cut block and on the conte
    // row's blocks.
    setUp(TimelineDoubleTapGate.reset);

    Future<void> clickTwice(
      WidgetTester tester,
      Offset first, [
      Offset? second,
    ]) async {
      await tester.tapAt(first, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(second ?? first, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
    }

    final cutName = find.byKey(const ValueKey<String>('rename-cut-dialog'));
    final frameName = find.byKey(
      const ValueKey<String>('rename-frame-dialog'),
    );

    Cut cutOf(WidgetTester tester, String id) => _session(tester).repository
        .requireProject()
        .tracks
        .single
        .cuts
        .firstWhere((cut) => cut.id == CutId(id));

    // ↩️The cut's own two bands alone were its paper, and its pictures the
    // conte blocks' (I-73, 유저 2026-10-08: 「컷 선택만 되도록」).
    for (final (where, point) in [
      ('its band', _bandPoint),
      ('its pictures', _picturePoint),
    ]) {
      testWidgets('a CUT block, on $where: the name of the cut under the '
          'click — whichever cut was in hand', (tester) async {
        await _openStoryboard(tester);
        expect(_activeCut(tester), const CutId('cut-1'), reason: '⛔전제');

        await clickTwice(tester, point(tester, 13));

        expect(cutName, findsOneWidget);
        expect(frameName, findsNothing);
        await tester.enterText(
          find.byKey(const ValueKey<String>('rename-cut-text-field')),
          'B',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('rename-cut-confirm-button')),
        );
        await tester.pumpAndSettle();
        expect(cutOf(tester, 'cut-2').name, 'B');
        expect(cutOf(tester, 'cut-1').name, 'cut-1');
      });
    }

    testWidgets('a CONTE block: the name of the drawing it shows — the '
        'frame block\'s own editor, on the cell it is', (tester) async {
      await _openStoryboard(tester);
      final field = find.byKey(
        const ValueKey<String>('rename-frame-text-field'),
      );
      Future<void> nameIt(String name) async {
        await tester.enterText(field, name);
        await tester.tap(
          find.byKey(const ValueKey<String>('rename-frame-ok-button')),
        );
        await tester.pumpAndSettle();
        await tester.pump(kDoubleTapTimeout * 2);
      }

      // The cut's FIRST panel is named first, so the name the editor opens
      // with says which block it opened.
      await clickTwice(tester, _contePoint(tester, 11));
      await nameIt('HEAD');

      // Global 16 is cut 2's local 6: its second panel, [4, 10).
      await clickTwice(tester, _contePoint(tester, 16));

      expect(frameName, findsOneWidget);
      expect(cutName, findsNothing);
      expect(
        tester.widget<TextField>(field).controller?.text,
        '',
        reason: 'the block clicked is the one in hand when the editor '
            'opens — not the head of its cut',
      );
      await nameIt('B2');
      final row = cutOf(
        tester,
        'cut-2',
      ).layers.firstWhere((layer) => layer.id == const LayerId('cut-2-sb'));
      expect(
        {for (final frame in row.frames) frame.id.value: frame.name},
        {'cut-2-0': 'HEAD', 'cut-2-4': 'B2'},
      );
      expect(
        _session(tester).storyboardStandingRow,
        _conteRow,
        reason: 'the panel still stands on the conte row it was clicked on',
      );
      // …and the row prints the names where the frame blocks print theirs:
      // at each block's head.
      final painter = conteRowPainter(tester, _trackId.value);
      expect(painter.cellModelAt(10).glyph, 'HEAD');
      expect(painter.cellModelAt(14).glyph, 'B2');
      expect(painter.cellModelAt(0).glyph, '', reason: 'unnamed, no mark');
    });

    testWidgets('a cut with NO conte layer is all the cut\'s paper — its '
        'pictures open the cut\'s name', (tester) async {
      await _openStoryboard(tester);

      await clickTwice(tester, _picturePoint(tester, 28));

      expect(cutName, findsOneWidget);
      expect(frameName, findsNothing);
    });

    testWidgets('🚨two clicks on DIFFERENT frames of one block are two '
        'seeks, never an editor — on either row', (tester) async {
      await _openStoryboard(tester);

      await clickTwice(tester, _bandPoint(tester, 12), _bandPoint(tester, 14));
      expect(cutName, findsNothing);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 100));

      await clickTwice(
        tester,
        _contePoint(tester, 15),
        _contePoint(tester, 17),
      );
      expect(frameName, findsNothing);
      expect(cutName, findsNothing);
    });

    testWidgets('🚨the two rows do not answer for each other: a click on '
        'the cut block and one on the conte block under it are two '
        'clicks', (tester) async {
      await _openStoryboard(tester);

      // Frame 3 of cut 1, which starts the track: the track's frame 3 and
      // the cut's own are one number, so only the ROW tells the two cells
      // apart.
      final onTheCut = _picturePoint(tester, 3);
      final onThePanel = _contePoint(tester, 3);
      await clickTwice(tester, onTheCut, onThePanel);
      expect(cutName, findsNothing);
      expect(frameName, findsNothing);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 100));

      await clickTwice(tester, onThePanel, onTheCut);
      expect(cutName, findsNothing);
      expect(frameName, findsNothing);
    });

    testWidgets('the cut\'s LOWER band is the cut\'s too', (tester) async {
      await _openStoryboard(tester);
      final row = _cutRowRect(tester);

      await clickTwice(
        tester,
        Offset(
          row.left + 13.5 * _pixelsPerFrame(tester),
          row.bottom - StoryboardCutBlocksPainter.bandHeight / 2,
        ),
      );

      expect(cutName, findsOneWidget);
      expect(frameName, findsNothing);
    });

    testWidgets('a double click past the last cut opens nothing — on either '
        'row', (tester) async {
      await _openStoryboard(tester);

      await clickTwice(tester, _bandPoint(tester, 34));
      expect(cutName, findsNothing);
      expect(frameName, findsNothing);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 100));

      await clickTwice(tester, _contePoint(tester, 34));
      expect(cutName, findsNothing);
      expect(frameName, findsNothing);
    });

    // A press inside a selected run stands nowhere — it may be the start of
    // a move — so the double click it begins lands on its block itself, as
    // a frame block's double tap picks its cell before it opens it.
    testWidgets('🚨inside a selected RUN the double click still opens the '
        'block under it — the cut in hand is not the one renamed', (
      tester,
    ) async {
      await _openStoryboard(tester);
      // Cuts 1 and 2 as one run, taken from cut 1: cut 1 stays in hand.
      await _drag(tester, _bandPoint(tester, 1), _bandPoint(tester, 16));
      expect(_activeCut(tester), const CutId('cut-1'), reason: '⛔전제');
      await tester.pump(kDoubleTapTimeout * 2);

      await clickTwice(tester, _bandPoint(tester, 13));

      expect(cutName, findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey<String>('rename-cut-text-field')),
            )
            .controller
            ?.text,
        'cut-2',
      );
    });

    testWidgets('🚨a conte block under a selected run opens its own '
        'drawing\'s name, in its own cut', (tester) async {
      await _openStoryboard(tester);
      await _drag(tester, _bandPoint(tester, 1), _bandPoint(tester, 16));
      expect(_activeCut(tester), const CutId('cut-1'), reason: '⛔전제');
      await tester.pump(kDoubleTapTimeout * 2);

      await clickTwice(tester, _contePoint(tester, 16));

      expect(frameName, findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey<String>('rename-frame-text-field')),
        'B2',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('rename-frame-ok-button')),
      );
      await tester.pumpAndSettle();
      Layer rowOf(String cutId) => cutOf(
        tester,
        cutId,
      ).layers.firstWhere((layer) => layer.id == LayerId('$cutId-sb'));
      expect(
        {for (final frame in rowOf('cut-2').frames) frame.id.value: frame.name},
        {'cut-2-0': null, 'cut-2-4': 'B2'},
      );
      expect(
        [for (final frame in rowOf('cut-1').frames) frame.name],
        [null, null],
        reason: 'the cut that was in hand is untouched',
      );
    });

    // 유저 (InstantTapRegion): 「아무것도 안 했는데 300ms나 반응성 느려지는
    // 거잖아」. A double tap on a row makes every ARENA tap of that row wait
    // out its window; measured with the double tap above and the range
    // gesture's tap still on the arena, this click took 300ms to drop the
    // run, where it had taken none.
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
      testWidgets('🚨the double click costs the single one nothing: a '
          '${kind.name} click inside a selected run drops it at once', (
        tester,
      ) async {
        await _openStoryboard(tester);
        await _drag(tester, _bandPoint(tester, 1), _bandPoint(tester, 6));
        expect(_panel(tester).cutSelect!.selectedRange.value, isNotNull);
        await tester.pump(kDoubleTapTimeout * 2);

        await tester.tapAt(_bandPoint(tester, 3), kind: kind);
        await tester.pump();

        expect(
          _panel(tester).cutSelect!.selectedRange.value,
          isNull,
          reason: 'not after the double-tap window',
        );
        await tester.pumpAndSettle();
      });
    }

    testWidgets('🚨…and a press the drag carried is no click, however short '
        '— a run slid less than a tap\'s slop stays selected', (tester) async {
      await _openStoryboard(tester);
      await _drag(tester, _bandPoint(tester, 11), _bandPoint(tester, 18));
      final run = _panel(tester).cutSelect!.selectedRange.value;
      expect(run, isNotNull);

      // One frame's worth, inside the run: a drag from its first pixel, and
      // nine of them — under the twelve a release may travel and still be a
      // tap ([InstantTapRegion.travelSlop]).
      final from = _bandPoint(tester, 14);
      await _drag(tester, from, from + const Offset(9, 0));

      expect(
        _panel(tester).cutSelect!.selectedRange.value,
        run,
        reason: 'a slide that went nowhere is still a slide',
      );
    });
  });
}
