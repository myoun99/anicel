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
import 'package:quick_animaker_v2/src/models/timeline_row_address.dart';
import 'package:quick_animaker_v2/src/models/track.dart';
import 'package:quick_animaker_v2/src/models/track_id.dart';
import 'package:quick_animaker_v2/src/ui/home_page.dart';
import 'package:quick_animaker_v2/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:quick_animaker_v2/src/ui/storyboard_panel.dart';

/// The storyboard's S rows select like every other frame-axis row.
///
/// They are TRACK-owned, so their selection is stated on the track's global
/// axis — the cut-local display clone the timeline shows is windowed to the
/// active cut, which is why a sound two cuts away could never be addressed
/// by the cut-local selection at all.
const _trackId = TrackId('se-range-track');
const _seLayerId = LayerId('se-range-1');

Cut _cut(String id, int duration) => Cut(
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

/// Cut 1 covers [0,8), cut 2 covers [8,14). The S row carries one sound at
/// [2,5) and another at [9,12) — one per cut, so a selection can be made
/// on the cut that is NOT active.
Project _project() => Project(
  id: const ProjectId('se-range-project'),
  name: 'SE range',
  createdAt: DateTime.utc(2026, 7, 26),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [_cut('cut-1', 8), _cut('cut-2', 6)],
      seLayers: [
        Layer(
          id: _seLayerId,
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(
              id: const FrameId('se-one'),
              duration: 3,
              name: 'One!',
              strokes: const [],
            ),
            Frame(
              id: const FrameId('se-two'),
              duration: 3,
              name: 'Two!',
              strokes: const [],
            ),
          ],
          timeline: const {
            2: TimelineExposure.drawing(FrameId('se-one'), length: 3),
            9: TimelineExposure.drawing(FrameId('se-two'), length: 3),
          },
        ),
      ],
    ),
  ],
);

Future<void> _openStoryboard(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 700));
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

Offset _seRowPoint(WidgetTester tester, int globalFrame) {
  final row = find.byKey(const ValueKey<String>('storyboard-se-row-0-1'));
  final topLeft = tester.getTopLeft(row);
  return Offset(
    topLeft.dx + (globalFrame + 0.5) * _pixelsPerFrame(tester),
    topLeft.dy + tester.getSize(row).height / 2,
  );
}

/// A range drag on the S row, PEN-driven: the shared gesture stands down
/// for finger drags (those scroll), exactly as it does on every other row.
Future<void> _dragSeRow(
  WidgetTester tester, {
  required int fromFrame,
  required int toFrame,
}) async {
  final gesture = await tester.startGesture(
    _seRowPoint(tester, fromFrame),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(_seRowPoint(tester, toFrame));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a drag on an S row selects a frame range, snapped to whole '
      'sounds', (tester) async {
    await _openStoryboard(tester);

    await _dragSeRow(tester, fromFrame: 3, toFrame: 4);

    final selection = tester
        .widget<StoryboardPanel>(find.byType(StoryboardPanel))
        .seSelect!
        .selectedRange
        .value!;
    expect(selection.anchorRow, const LayerRowAddress(_seLayerId));
    // The drag touched the middle of the [2,5) sound: the snap took it
    // whole, exactly as it does for a timeline exposure block.
    expect(selection.startFrame, 2);
    expect(selection.endFrameExclusive, 5);
  });

  testWidgets('the range reaches a sound in ANOTHER cut — the axis is the '
      "track's, not the active cut's", (tester) async {
    await _openStoryboard(tester);

    // Cut 1 is active; frame 10 lives in cut 2, where a cut-local index
    // could not address the sound at all.
    await _dragSeRow(tester, fromFrame: 3, toFrame: 10);

    final selection = tester
        .widget<StoryboardPanel>(find.byType(StoryboardPanel))
        .seSelect!
        .selectedRange
        .value!;
    expect(selection.startFrame, 2);
    expect(selection.endFrameExclusive, 12);
  });

  testWidgets('an S-row selection takes the highlight OFF the cut row: one '
      'selection, several rows', (tester) async {
    await _openStoryboard(tester);
    // Paint a CUT selection first, on the row above.
    final cutRow = find.byKey(
      ValueKey<String>('storyboard-track-timeline-area-${_trackId.value}'),
    );
    final cutRowTopLeft = tester.getTopLeft(cutRow);
    // The cut's own handle is its BAND: the block's middle is the strip,
    // which belongs to the cut's panels.
    final cutRowY =
        cutRowTopLeft.dy + StoryboardCutBlocksPainter.bandHeight / 2;
    final cutGesture = await tester.startGesture(
      Offset(cutRowTopLeft.dx + 1.5 * _pixelsPerFrame(tester), cutRowY),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await cutGesture.moveTo(
      Offset(cutRowTopLeft.dx + 3.5 * _pixelsPerFrame(tester), cutRowY),
    );
    await tester.pump();
    await cutGesture.up();
    await tester.pumpAndSettle();

    final panel = tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));
    expect(
      panel.cutSelect!.selectedRange.value!.anchorRow,
      TrackRowAddress(_trackId),
    );

    await _dragSeRow(tester, fromFrame: 3, toFrame: 4);

    // ONE selection object: taking it on the S row is what took it off the
    // cut row, so no second highlight can survive anywhere.
    final after = tester
        .widget<StoryboardPanel>(find.byType(StoryboardPanel))
        .cutSelect!
        .selectedRange
        .value!;
    expect(after.anchorRow, const LayerRowAddress(_seLayerId));
    expect(after.coversRow(TrackRowAddress(_trackId)), isFalse);
  });

  testWidgets('a plain tap clears it', (tester) async {
    await _openStoryboard(tester);
    await _dragSeRow(tester, fromFrame: 3, toFrame: 4);

    await tester.tapAt(_seRowPoint(tester, 6));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<StoryboardPanel>(find.byType(StoryboardPanel))
          .seSelect!
          .selectedRange
          .value,
      isNull,
    );
  });
}
