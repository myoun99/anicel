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
import 'package:quick_animaker_v2/src/ui/storyboard_layer_policy.dart';
import 'package:quick_animaker_v2/src/ui/storyboard_panel.dart';

import 'timeline/timeline_row_chrome_probe.dart';

/// The cut block has no edge grips of its own any more: a cut edge is always
/// ON the strip. The first panel's leading edge trims the cut's start, the
/// last panel's trailing edge is the cut's length, and every edge between
/// two panels moves a DIVISION. One shape of grip; where it sits decides
/// what it re-times.
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
  testWidgets('the row hangs its grips on the PANELS, one per boundary', (
    tester,
  ) async {
    await _openStoryboard(tester);

    // Panels in track order: cut 1's two, then one each for cuts 2 and 3.
    // Only the first panel of a cut carries a START grip — inside a cut the
    // panels touch, so ordinal 1 has no start facing ordinal 0's end.
    expect(
      timelineRowChromeIds(tester, _trackId.value, prefix: 'storyboard'),
      <String>[
        'block-edge-grip-start-grip-track-0',
        'block-edge-grip-end-grip-track-0',
        'block-edge-grip-end-grip-track-1',
        'block-edge-grip-start-grip-track-2',
        'block-edge-grip-end-grip-track-2',
        'block-edge-grip-start-grip-track-3',
        'block-edge-grip-end-grip-track-3',
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

  testWidgets('an edge BETWEEN two panels moves the division — the cut keeps '
      'its length and no other block shifts', (tester) async {
    await _openStoryboard(tester);
    expect(_divisionsOf(tester, 'cut-1'), [0, 5]);

    await _dragGrip(tester, 'block-edge-grip-end-grip-track-0', 2);

    expect(_divisionsOf(tester, 'cut-1'), [0, 7]);
    expect(_cutById(tester, 'cut-1').duration, 10);
    // The cell lengths follow, because coverage derives them from the keys.
    final layer = storyboardLayerForCut(_cutById(tester, 'cut-1'))!;
    expect(layer.timeline[0]!.length, 7);
    expect(layer.timeline[7]!.length, 3);
  });

  testWidgets('the division drag is ONE undo step', (tester) async {
    await _openStoryboard(tester);

    await _dragGrip(tester, 'block-edge-grip-end-grip-track-0', 2);
    expect(_divisionsOf(tester, 'cut-1'), [0, 7]);

    await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
    await tester.pumpAndSettle();

    expect(_divisionsOf(tester, 'cut-1'), [0, 5]);
  });

  testWidgets('the LAST panel\'s trailing edge is still the cut\'s LENGTH', (
    tester,
  ) async {
    await _openStoryboard(tester);

    await _dragGrip(tester, 'block-edge-grip-end-grip-track-1', 3);

    expect(_cutById(tester, 'cut-1').duration, 13);
    expect(_divisionsOf(tester, 'cut-1'), [0, 5]);
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

  testWidgets('ANY cut\'s divisions drag, not only the active one\'s — the '
      'edge reads its cut rather than the active-cut lookup', (tester) async {
    await _openStoryboard(tester);
    // Cut 1 is the active one; cut 3's row is not reachable through the
    // active-cut layer lookup at all.
    expect(_divisionsOf(tester, 'cut-3'), [0, 3]);

    await _dragGrip(tester, 'block-edge-grip-end-grip-track-3', -1);

    expect(_divisionsOf(tester, 'cut-3'), [0, 2]);
    expect(_divisionsOf(tester, 'cut-1'), [0, 5]);
  });
}
