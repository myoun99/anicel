import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_section_defaults.dart'
    show createTrackTransitionLayer;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_double_tap.dart';

/// 🚨C1 (2026-08-17): the storyboard's TRANSITION blocks MOVE by the frame
/// blocks' own grammar — select the span, then a drag starting inside the
/// selection slides it, previewing LIVE and committing ONE undo on release.
/// The move half used to refuse outright (`onMoveBegin: false`) on the CUT
/// timeline's read-only reasoning, but this rail is the global axis the
/// spans live on — their one authoring surface, where the edges already
/// drag. Every gesture here is REAL input.
const _trackId = TrackId('tmove-track');

/// The storyboard's resting zoom — 8px a frame.
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
  id: const ProjectId('tmove-project'),
  name: 'Transition Move',
  createdAt: DateTime.utc(2026, 8, 17),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [_cut('cut-1', 10), _cut('cut-2', 6)],
      transitionLayer: createTrackTransitionLayer(_trackId).copyWith(
        instructions: {
          2: const InstructionEvent(instructionId: 'ol', length: 5),
        },
      ),
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

String get _rowKey => 'storyboard-transition-row-${_trackId.value}';

Offset _rowPoint(WidgetTester tester, double dx) {
  final row = find.byKey(ValueKey<String>(_rowKey));
  final topLeft = tester.getTopLeft(row);
  return Offset(topLeft.dx + dx, topLeft.dy + tester.getSize(row).height / 2);
}

Finder _paperAt(WidgetTester tester, int startFrame) {
  final transitionId = _track(tester).transitionLayer.id;
  return find.byKey(
    ValueKey<String>('storyboard-transition-paper-$transitionId-$startFrame'),
  );
}

/// SELECT the 2..7 span with a REAL body drag (the parity-proven gesture).
Future<void> _selectSpan(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    _rowPoint(tester, 3.5 * _ppf),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveBy(const Offset(12, 0));
  await tester.pump();
  await gesture.moveBy(const Offset(12, 0));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  setUp(TimelineCellDoubleTapGate.reset);

  testWidgets('a REAL mouse drag starting INSIDE the selection MOVES the '
      'span — live mid-drag, committed once on release', (tester) async {
    await _openStoryboard(tester);
    expect(_track(tester).transitionLayer.instructions.keys, [2]);

    await _selectSpan(tester);
    final selection = tester
        .widget<StoryboardPanel>(find.byType(StoryboardPanel))
        .seSelect
        ?.selectedRange
        .value;
    expect(selection, isNotNull, reason: 'the body drag selected the span');

    // MOVE: press inside the selection, pull +2 frames, hold the pointer.
    final gesture = await tester.startGesture(
      _rowPoint(tester, 4.5 * _ppf),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(_ppf, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(_ppf, 0));
    await tester.pump();

    // MID-DRAG, pointer still down: the strip renders the span at its
    // PREVIEWED start — the row's own preview channel, the edge drags'.
    expect(
      _paperAt(tester, 4),
      findsOneWidget,
      reason: 'the move previews LIVE on the transition strip',
    );
    expect(_paperAt(tester, 2), findsNothing);
    expect(
      _track(tester).transitionLayer.instructions.keys,
      [2],
      reason: 'nothing commits while the pointer is down',
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      _track(tester).transitionLayer.instructions.keys,
      [4],
      reason: 'the release commits the slide',
    );
    expect(_track(tester).transitionLayer.instructions[4]!.length, 5);
    expect(_paperAt(tester, 4), findsOneWidget);
  });

  testWidgets('the move is ONE undo step: undo puts the span back where it '
      'was', (tester) async {
    await _openStoryboard(tester);
    await _selectSpan(tester);

    final gesture = await tester.startGesture(
      _rowPoint(tester, 4.5 * _ppf),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(_ppf, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(_ppf, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_track(tester).transitionLayer.instructions.keys, [4]);

    await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
    await tester.pumpAndSettle();

    expect(_track(tester).transitionLayer.instructions.keys, [2]);
  });

  testWidgets('a drag OUTSIDE the selection still selects — the move took '
      'its press, not the row', (tester) async {
    await _openStoryboard(tester);
    await _selectSpan(tester);

    // Press on the empty tail (frame 9), well outside the 2..7 span.
    final gesture = await tester.startGesture(
      _rowPoint(tester, 9.5 * _ppf),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      _track(tester).transitionLayer.instructions.keys,
      [2],
      reason: 'an outside drag never slides the span',
    );
    final selection = tester
        .widget<StoryboardPanel>(find.byType(StoryboardPanel))
        .seSelect
        ?.selectedRange
        .value;
    expect(selection, isNotNull);
    expect(selection!.startFrame, greaterThanOrEqualTo(9));
  });
}
