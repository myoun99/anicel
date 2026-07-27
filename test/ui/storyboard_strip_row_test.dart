import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/canvas_size.dart';
import 'package:quick_animaker_v2/src/models/cut.dart';
import 'package:quick_animaker_v2/src/models/cut_id.dart';
import 'package:quick_animaker_v2/src/models/frame.dart';
import 'package:quick_animaker_v2/src/models/frame_id.dart';
import 'package:quick_animaker_v2/src/models/layer.dart';
import 'package:quick_animaker_v2/src/models/layer_id.dart';
import 'package:quick_animaker_v2/src/models/layer_kind.dart';
import 'package:quick_animaker_v2/src/models/project.dart';
import 'package:quick_animaker_v2/src/models/project_id.dart';
import 'package:quick_animaker_v2/src/models/timeline_exposure.dart';
import 'package:quick_animaker_v2/src/models/track.dart';
import 'package:quick_animaker_v2/src/models/track_id.dart';
import 'package:quick_animaker_v2/src/ui/home_page.dart';
import 'package:quick_animaker_v2/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:quick_animaker_v2/src/ui/storyboard_panel.dart';

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
/// panels at 0 and 4 (local).
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
}
