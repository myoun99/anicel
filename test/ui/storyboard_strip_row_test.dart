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
/// The bands above and below it are the CUT's, and the split between them
/// is hit-testing: a press on a band misses the strip's gesture and lands
/// on the cut's.
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
  });

  testWidgets('D30: the create affordance is the ACTIVE cut\'s — the first '
      'press on a no-layer cut\'s centre SELECTS, the next one creates', (
    tester,
  ) async {
    await _openStoryboard(tester);
    expect(requireCutBlock(tester, 'cut-3').hasStoryboardLayer, isFalse);
    expect(requireCutBlock(tester, 'cut-3').isActive, isFalse);

    // First press at cut-3's centre — the exact point a block-select tap
    // lands on. Cut-3 was NOT active, so its slot drew no affordance and
    // the press stays a SELECT: it activates the cut and creates nothing.
    await tester.tapAt(_stripPoint(tester, 25));
    await tester.pumpAndSettle();
    expect(requireCutBlock(tester, 'cut-3').isActive, isTrue);
    expect(
      requireCutBlock(tester, 'cut-3').hasStoryboardLayer,
      isFalse,
      reason: 'a select tap on a non-active cut must never create — the '
          'affordance belongs to the ACTIVE cut («액티브 컷에 없으면 생성»)',
    );

    // Now the slot draws the +. The same point creates.
    await tester.tapAt(_stripPoint(tester, 25));
    await tester.pumpAndSettle();
    expect(
      requireCutBlock(tester, 'cut-3').hasStoryboardLayer,
      isTrue,
      reason: 'gate and dispatch are the session\'s one add-layer pair — '
          'the drawn + is the pressable one',
    );
  });

  testWidgets('D30: a strip press OUTSIDE the affordance never creates', (
    tester,
  ) async {
    await _openStoryboard(tester);

    // Make cut-3 ACTIVE first (its affordance only exists then).
    await tester.tapAt(_stripPoint(tester, 21));
    await tester.pumpAndSettle();
    expect(requireCutBlock(tester, 'cut-3').isActive, isTrue);

    // Frame 21 is inside cut-3 but left of the centred 22px affordance.
    await tester.tapAt(_stripPoint(tester, 21));
    await tester.pumpAndSettle();

    expect(requireCutBlock(tester, 'cut-3').hasStoryboardLayer, isFalse);
  });

  testWidgets('D30: a SECONDARY-button press on the active cut\'s + never '
      'creates — the create runs under the press\'s own button gate', (
    tester,
  ) async {
    await _openStoryboard(tester);
    await tester.tapAt(_stripPoint(tester, 25));
    await tester.pumpAndSettle();
    expect(requireCutBlock(tester, 'cut-3').isActive, isTrue);

    final gesture = await tester.startGesture(
      _stripPoint(tester, 25),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(requireCutBlock(tester, 'cut-3').hasStoryboardLayer, isFalse);
  });

  testWidgets('D30: a press INSIDE the live cut selection is starting a '
      'move — it neither seeks nor creates, even over the active cut\'s +', (
    tester,
  ) async {
    await _openStoryboard(tester);
    // Activate cut-3 (its slot then draws the +).
    await tester.tapAt(_stripPoint(tester, 25));
    await tester.pumpAndSettle();
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

    await tester.tapAt(_stripPoint(tester, 25));
    await tester.pumpAndSettle();

    expect(requireCutBlock(tester, 'cut-3').hasStoryboardLayer, isFalse);
  });

  test('D30: a strip too narrow or too flat for the whole + holds NO '
      'affordance — a clamped block would light a + its frames cannot '
      'honour, and an unclamped box would paint over the neighbour', () {
    StoryboardCutBlockVisual visual({
      required double stripWidth,
      double stripHeight = 38,
    }) => StoryboardCutBlockVisual(
      cutId: const CutId('cut-x'),
      rect: Rect.fromLTWH(0, 0, stripWidth, 64),
      isActive: true,
      isRangeSelected: false,
      isHovered: false,
      title: '1',
      layerLabel: '',
      hasStoryboardLayer: false,
      total: null,
      thumbnails: const [],
      cells: const [],
      topBand: Rect.fromLTWH(0, 0, stripWidth, 13),
      strip: Rect.fromLTWH(0, 13, stripWidth, stripHeight),
      bottomBand: Rect.fromLTWH(0, 13 + stripHeight, stripWidth, 13),
    );

    expect(
      StoryboardCutBlocksPainter.createAffordanceRectOf(
        visual(stripWidth: 16),
      ),
      isNull,
    );
    expect(
      StoryboardCutBlocksPainter.createAffordanceRectOf(
        visual(stripWidth: 80, stripHeight: 8),
      ),
      isNull,
    );
    final affordance = StoryboardCutBlocksPainter.createAffordanceRectOf(
      visual(stripWidth: 80),
    );
    expect(affordance, isNotNull);
    expect(
      visual(stripWidth: 80).strip.expandToInclude(affordance!),
      visual(stripWidth: 80).strip,
      reason: 'the affordance never leaves its own strip',
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
