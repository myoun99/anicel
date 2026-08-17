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
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_double_tap.dart';

/// 🚨C2 (2026-08-17): a storyboard SE block MOVE previews LIVE — mid-drag,
/// pointer still down, the strip renders the block at its previewed spot,
/// exactly as the timeline rows do and exactly as this same strip already
/// follows an EDGE drag. The gap was the channel: the move published no
/// GLOBAL form, and the storyboard's row gate resolves only global forms.
/// Every gesture here is REAL input.
const _trackId = TrackId('semove-track');
const _seLayerId = LayerId('semove-se');

const double _ppf = 8;

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

Project _project() => Project(
  id: const ProjectId('semove-project'),
  name: 'SE Move Live',
  createdAt: DateTime.utc(2026, 8, 17),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [_cut('cut-1', 10), _cut('cut-2', 6)],
      seLayers: [
        Layer(
          id: _seLayerId,
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(
              id: const FrameId('semove-sound'),
              duration: 5,
              name: 'Bang!',
              strokes: const [],
            ),
          ],
          timeline: {
            1: const TimelineExposure.drawing(
              FrameId('semove-sound'),
              length: 5,
            ),
          },
        ),
      ],
    ),
  ],
);

Future<void> _openStoryboard(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 800));
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

Track _track(WidgetTester tester) => tester
    .widget<StoryboardPanel>(find.byType(StoryboardPanel))
    .project
    .tracks
    .single;

const String _seRowKey = 'storyboard-se-row-0-1';

Offset _rowPoint(WidgetTester tester, double dx) {
  final row = find.byKey(const ValueKey<String>(_seRowKey));
  final topLeft = tester.getTopLeft(row);
  return Offset(topLeft.dx + dx, topLeft.dy + tester.getSize(row).height / 2);
}

Finder _paperAt(int startFrame) =>
    find.byKey(ValueKey<String>('storyboard-se-paper-$_seLayerId-$startFrame'));

void main() {
  setUp(TimelineCellDoubleTapGate.reset);

  testWidgets('a REAL mouse drag inside the selection slides the sound — '
      'LIVE mid-drag on the track-global strip, one commit on release', (
    tester,
  ) async {
    await _openStoryboard(tester);
    expect(_track(tester).seLayers.single.timeline.keys, [1]);

    // SELECT the 1..6 block with a body drag.
    var gesture = await tester.startGesture(
      _rowPoint(tester, 2.5 * _ppf),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StoryboardPanel>(find.byType(StoryboardPanel))
          .seSelect
          ?.selectedRange
          .value,
      isNotNull,
      reason: 'the body drag selected the sound',
    );

    // MOVE: press inside the selection, pull +2 frames, hold the pointer.
    gesture = await tester.startGesture(
      _rowPoint(tester, 3.5 * _ppf),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(_ppf, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(_ppf, 0));
    await tester.pump();

    // MID-DRAG, pointer still down: the block renders at its previewed
    // start. This is the C2 pin — the storyboard used to sit still here
    // (its gate resolves GLOBAL preview forms, and the move published
    // none) while the timeline followed the same drag live.
    expect(
      _paperAt(3),
      findsOneWidget,
      reason: 'the move previews LIVE on the storyboard SE strip',
    );
    expect(_paperAt(1), findsNothing);
    expect(
      _track(tester).seLayers.single.timeline.keys,
      [1],
      reason: 'nothing commits while the pointer is down',
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      _track(tester).seLayers.single.timeline.keys,
      [3],
      reason: 'the release commits the slide to the GLOBAL layer',
    );
    expect(_paperAt(3), findsOneWidget);
  });
}
