import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryButton;
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
import 'package:anicel/src/ui/storyboard_panel.dart';

import 'storyboard_cut_block_probe.dart';

/// The STRIP is a row of its own, and a cut-owned one: it speaks its cut's
/// local axis, which is why a drag on it cannot leave the cut it started
/// in. That is the "clip to the anchor cut" rule arriving as arithmetic
/// instead of as a guard.
///
/// The outer bands are the CUT's, and the split between them and the conte
/// blocks — their own bands and the strip — is hit-testing: a press on a
/// cut band misses the strip's gesture and lands on the cut's.
const _trackId = TrackId('strip-track');

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

double _pixelsPerFrame(WidgetTester tester) =>
    tester.widget<StoryboardPanel>(find.byType(StoryboardPanel)).pixelsPerFrame;

Rect _cutRowRect(WidgetTester tester) {
  final row = find.byKey(
    ValueKey<String>('storyboard-track-timeline-area-${_trackId.value}'),
  );
  return tester.getTopLeft(row) & tester.getSize(row);
}

/// A point on the STRIP band over [globalFrame].
Offset _stripPoint(WidgetTester tester, int globalFrame) {
  final rect = _cutRowRect(tester);
  return Offset(
    rect.left + (globalFrame + 0.5) * _pixelsPerFrame(tester),
    rect.top + rect.height / 2,
  );
}

/// A point on the TOP band over [globalFrame] — the cut's own area.
Offset _bandPoint(WidgetTester tester, int globalFrame) {
  final rect = _cutRowRect(tester);
  return Offset(
    rect.left + (globalFrame + 0.5) * _pixelsPerFrame(tester),
    rect.top + StoryboardCutBlocksPainter.bandHeight / 2,
  );
}

/// A point on the CONTE BLOCKS' top band over [globalFrame] — a conte
/// block's name band, or the create button of a cut with no storyboard
/// layer (유저 2026-09-26: 「콘티블록 상단띠 전면을 생성버튼으로」).
Offset _conteBandPoint(WidgetTester tester, int globalFrame) {
  final rect = _cutRowRect(tester);
  return Offset(
    rect.left + (globalFrame + 0.5) * _pixelsPerFrame(tester),
    rect.top + StoryboardCutBlocksPainter.bandHeight * 1.5,
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
  testWidgets('a drag on the strip selects the cut\'s PANELS, on the cut\'s '
      'own axis', (tester) async {
    await _openStoryboard(tester);

    await _drag(tester, _stripPoint(tester, 1), _stripPoint(tester, 6));

    final panel = tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));
    final selection = panel.stripSelect!.selection.value!;
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
    await _drag(tester, _stripPoint(tester, 1), _stripPoint(tester, 17));

    final panel = tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));
    final selection = panel.stripSelect!.selection.value!;
    expect(selection.layerId, const LayerId('cut-1-sb'));
    expect(selection.endIndexExclusive, 10);
  });

  testWidgets('the anchor cut is the one PRESSED, not the one that was '
      'active: pressing cut 2 makes it the subject', (tester) async {
    await _openStoryboard(tester);

    await _drag(tester, _stripPoint(tester, 11), _stripPoint(tester, 12));

    final panel = tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));
    final selection = panel.stripSelect!.selection.value!;
    expect(selection.layerId, const LayerId('cut-2-sb'));
    // Local [0,4) — cut 2's first panel, snapped whole.
    expect(selection.startIndex, 0);
    expect(selection.endIndexExclusive, 4);
  });

  testWidgets('a press on a BAND is the cut\'s, not the strip\'s — the two '
      'are split by where the pointer is and nothing else', (tester) async {
    await _openStoryboard(tester);

    await _drag(tester, _bandPoint(tester, 1), _bandPoint(tester, 6));

    final panel = tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));
    // The CUT selection took it; the strip's stayed empty.
    expect(panel.cutSelect!.selectedRange.value, isNotNull);
    expect(panel.stripSelect!.selection.value, isNull);
  });

  testWidgets('🗣️a drag on a CONTE BLOCK\'s band is its panels\', not the '
      'cut\'s — the conte block is its bands and its picture (유저 2026-09-26: '
      '「내부에 콘티블록 있으면 콘티블록의 띠도 생겨서」)', (tester) async {
    await _openStoryboard(tester);

    await _drag(tester, _conteBandPoint(tester, 1), _conteBandPoint(tester, 6));

    final panel = tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));
    expect(
      panel.stripSelect!.selection.value?.layerId,
      const LayerId('cut-1-sb'),
    );
    expect(
      panel.cutSelect!.selectedRange.value,
      isNull,
      reason: '↩️the band was the cut\'s while every band was',
    );
  });

  testWidgets('a drag that starts INSIDE the selection slides the panels — '
      'and on a row that tiles its cut, sliding means reordering', (
    tester,
  ) async {
    await _openStoryboard(tester);
    // Take cut 1's first panel [0,5), then drag from inside it past the
    // midpoint of the second.
    await _drag(tester, _stripPoint(tester, 1), _stripPoint(tester, 2));
    expect(
      tester
          .widget<StoryboardPanel>(find.byType(StoryboardPanel))
          .stripSelect!
          .selection
          .value!
          .endIndexExclusive,
      5,
    );

    await _drag(tester, _stripPoint(tester, 2), _stripPoint(tester, 8));

    final layer = tester
        .widget<StoryboardPanel>(find.byType(StoryboardPanel))
        .project
        .tracks
        .single
        .cuts
        .first
        .layers
        .firstWhere((layer) => layer.id == const LayerId('cut-1-sb'));
    // The two panels swapped and the row still tiles [0,10) exactly: with
    // no free space to re-time into, the only move a gapless row has is a
    // reorder, which is why its panels can never leave the cut.
    expect(layer.timeline.keys, [0, 5]);
    expect(layer.timeline[0]!.frameId, const FrameId('cut-1-5'));
    expect(layer.timeline[5]!.frameId, const FrameId('cut-1-0'));
  });

  testWidgets('the two selections stay mutually exclusive: taking one on '
      'the strip drops the cut run', (tester) async {
    await _openStoryboard(tester);
    await _drag(tester, _bandPoint(tester, 1), _bandPoint(tester, 6));
    expect(
      tester
          .widget<StoryboardPanel>(find.byType(StoryboardPanel))
          .cutSelect!
          .selectedRange
          .value,
      isNotNull,
    );

    await _drag(tester, _stripPoint(tester, 1), _stripPoint(tester, 2));

    final panel = tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));
    expect(panel.stripSelect!.selection.value, isNotNull);
    expect(panel.cutSelect!.selectedRange.value, isNull);
  });

  testWidgets('D30: the strip selection draws the timeline\'s ONE band at '
      'the selected panels', (tester) async {
    await _openStoryboard(tester);

    await _drag(tester, _stripPoint(tester, 1), _stripPoint(tester, 6));
    final band = find.byKey(
      const ValueKey<String>('storyboard-strip-range-selection'),
    );
    expect(band, findsOneWidget, reason: 'the strip band was MISSING — the '
        'selection had no visual of its own on this panel');

    // The selection snapped to the whole cut-1 span [0,10): the band's
    // rect covers exactly those frames.
    final rowRect = _cutRowRect(tester);
    final ppf = _pixelsPerFrame(tester);
    final bandRect = tester.getRect(band);
    expect(bandRect.left, moreOrLessEquals(rowRect.left, epsilon: 1));
    expect(bandRect.width, moreOrLessEquals(10 * ppf, epsilon: 1));
    // Across, it wraps the conte blocks — their bands and the picture —
    // inside the cut's own bands (↩️the strip alone).
    const cutBand = StoryboardCutBlocksPainter.bandHeight;
    expect(bandRect.top, moreOrLessEquals(rowRect.top + cutBand));
    expect(bandRect.bottom, moreOrLessEquals(rowRect.bottom - cutBand));
    // And square, as the conte blocks it selects are (F-26: the band takes
    // the shape of what it selects; ↩️round while each panel was).
    final decoration = tester
        .widget<DecoratedBox>(
          find.descendant(of: band, matching: find.byType(DecoratedBox)),
        )
        .decoration;
    expect((decoration as BoxDecoration).borderRadius, BorderRadius.zero);
  });

  /// 🚨H13 (유저 2026-08-22) — 「스토리보드레이어 추가버튼, **액티브컷에만
  /// 띄우는게아니라 그런 규칙 두지말고** 그냥 다른 컷블록도 없으면 띄우도록」
  ///
  /// ⚠️This test used to assert the opposite ("the first press SELECTS, the
  /// next one creates"), which is the rule the user struck. D30's REAL
  /// guard — the press layer judging the PRE-press snapshot — is untouched
  /// and still pinned below; what went is the disagreement between what was
  /// drawn and what was pressable.
  testWidgets('H13: every layerless cut wears the +, active or not — one '
      'press on the drawn + creates', (tester) async {
    await _openStoryboard(tester);
    expect(requireCutBlock(tester, 'cut-3').hasStoryboardLayer, isFalse);
    expect(
      requireCutBlock(tester, 'cut-3').isActive,
      isFalse,
      reason: 'the premise: cut-3 is layerless AND not the active cut',
    );

    // One press on cut-3's conte top band — its + is drawn there.
    await tester.tapAt(_conteBandPoint(tester, 25));
    await tester.pumpAndSettle();
    expect(
      requireCutBlock(tester, 'cut-3').hasStoryboardLayer,
      isTrue,
      reason: 'the + was on screen before the press, so pressing it means '
          'what it says — no second press to earn the affordance first',
    );
    expect(
      requireCutBlock(tester, 'cut-3').isActive,
      isTrue,
      reason: 'and the press still takes the cut, as a press on any block does',
    );
  });

  testWidgets('D30: a strip press OUTSIDE the affordance never creates', (
    tester,
  ) async {
    await _openStoryboard(tester);

    // The strip's centre is where the + stood until 2026-09-26; the button
    // is the conte top band now, so a press on the strip selects the cut and
    // nothing more — twice over, to show the miss is not a "first press
    // earns it" rung (H13 retired that).
    await tester.tapAt(_stripPoint(tester, 25));
    await tester.pumpAndSettle();
    expect(requireCutBlock(tester, 'cut-3').isActive, isTrue);

    await tester.tapAt(_stripPoint(tester, 25));
    await tester.pumpAndSettle();

    expect(requireCutBlock(tester, 'cut-3').hasStoryboardLayer, isFalse);
  });

  testWidgets('D30: a SECONDARY-button press on the + never creates — the '
      'create runs under the press\'s own button gate', (tester) async {
    await _openStoryboard(tester);
    // No priming press: cut-3 wears its + from the first frame (H13), so
    // the secondary button is the only thing this test varies.
    final gesture = await tester.startGesture(
      _conteBandPoint(tester, 25),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(requireCutBlock(tester, 'cut-3').hasStoryboardLayer, isFalse);
  });

  testWidgets('D30: a press INSIDE the live cut selection is starting a '
      'move — it neither seeks nor creates, even over a drawn +', (
    tester,
  ) async {
    await _openStoryboard(tester);
    // No priming press: cut-3 wears its + from the first frame (H13), so a
    // press that lands on it while a selection is live is the only thing
    // being varied here.
    // Take a cut-run selection covering cut-3 on the BAND (the cut's own
    // handle).
    await _drag(tester, _bandPoint(tester, 21), _bandPoint(tester, 28));
    expect(
      tester
          .widget<StoryboardPanel>(find.byType(StoryboardPanel))
          .cutSelect!
          .selectedRange
          .value,
      isNotNull,
    );

    await tester.tapAt(_conteBandPoint(tester, 25));
    await tester.pumpAndSettle();

    expect(requireCutBlock(tester, 'cut-3').hasStoryboardLayer, isFalse);
  });

  test('D30: the + is a layerless block\'s WHOLE conte top band — narrow or '
      'flat, it is there as long as the band is, and never past its block', () {
    StoryboardCutBlockVisual visual({
      required double width,
      double stripHeight = 44,
      bool hasStoryboardLayer = false,
    }) => StoryboardCutBlockVisual(
      cutId: const CutId('cut-x'),
      rect: Rect.fromLTWH(0, 0, width, 52 + stripHeight),
      isActive: true,
      isRangeSelected: false,
      isHovered: false,
      title: '1',
      layerLabel: '',
      hasStoryboardLayer: hasStoryboardLayer,
      total: null,
      thumbnails: const [],
      cells: const [],
      topBand: Rect.fromLTWH(0, 0, width, 13),
      innerTopBand: Rect.fromLTWH(0, 13, width, 13),
      strip: Rect.fromLTWH(0, 26, width, stripHeight),
      innerBottomBand: Rect.fromLTWH(0, 26 + stripHeight, width, 13),
      bottomBand: Rect.fromLTWH(0, 39 + stripHeight, width, 13),
      cutLabel: Colors.white,
      conteLabel: null,
    );

    // ↩️A 22px square centred in the strip until 2026-09-26, gone from a
    // strip narrower or flatter than it; the band holds its + however
    // narrow (the word narrows, B) and at the V row's floor, where the
    // strip is gone.
    for (final block in [
      visual(width: 16),
      visual(width: 80, stripHeight: 0),
      visual(width: 80),
    ]) {
      expect(
        StoryboardCutBlocksPainter.createAffordanceRectOf(block),
        block.innerTopBand,
      );
    }
    expect(
      StoryboardCutBlocksPainter.createAffordanceRectOf(visual(width: 0)),
      isNull,
      reason: 'no band, no button',
    );
    expect(
      StoryboardCutBlocksPainter.createAffordanceRectOf(
        visual(width: 80, hasStoryboardLayer: true),
      ),
      isNull,
      reason: 'a cut with a storyboard layer has its conte blocks there',
    );
  });

  testWidgets('D27: a no-layer cut\'s semantics label carries no leftover '
      'joiner spaces', (tester) async {
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
}
