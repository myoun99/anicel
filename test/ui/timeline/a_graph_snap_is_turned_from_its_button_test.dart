import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/text/app_strings.dart' show AppText;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import 'package:anicel/src/ui/widgets/app_icon_button.dart'
    show AppIconButtonFace;

import '../../helpers/named_finders.dart';

/// **graph-key-drag-snaps — a header graph's snap, turned from its button
/// (AE's Snap in its graph editor), in the app.**
///
/// What the snap does to a key carried is the picture's to answer
/// (`a_carried_key_snaps_where_the_graph_says_test`); here, the button that
/// turns it, what the timeline hands the graph to snap by, and a key carried
/// with it on, written.
void main() {
  tearDown(debugClearValueControlPointers);

  testWidgets('the snap button turns the graph\'s snap on and off, its face '
      'on while it is on — off on a graph opened anew, as AE\'s starts', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    bool on() => s.railView.laneGraphs.value.open[_transformGroup]!.snap;
    AppIconButtonFace face() => tester.widget<AppIconButtonFace>(_snapButton);
    expect(on(), isFalse);
    expect(face().isSelected, isFalse);
    expect(face().tooltip, AppText.strings.laneGraphSnap);
    expect(_picture(tester).snap, isFalse);

    await _tapTheSnap(tester);
    expect(on(), isTrue);
    expect(face().isSelected, isTrue);
    expect(face().tooltip, AppText.strings.laneGraphSnapOn);
    expect(_picture(tester).snap, isTrue, reason: 'the picture told');

    await _tapTheSnap(tester);
    expect(on(), isFalse);
  });

  testWidgets('the graph snaps by the timeline\'s playhead, as it moves, and '
      'by the cut\'s end', (tester) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    final frames = _picture(tester).frameAxis;
    expect(frames.frameCount, 48);

    s.selectFrameIndex(13);
    await tester.pumpAndSettle();
    expect(frames.playhead!.value, 13);
  });

  testWidgets('with the snap on, a key carried down beside another key\'s '
      'mark takes that key\'s value — written so, in one undo', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    final undoable = s.historyManager.canUndo;
    final first = _keyOnScreen(tester, 0);
    final carried = _keyOnScreen(tester, 8);
    // Four pixels above the mark of the key on 0, which holds 0.
    final down = Offset(0, first.dy - carried.dy - 4);
    expect(down.dy, greaterThan(20), reason: '⛔전제: well above it');

    await _carry(tester, carried, down);
    expect(
      _rotationAt(s, 8),
      isNot(closeTo(0, 1e-6)),
      reason: '⛔전제: the snap off — where the hand is',
    );
    s.undo();
    expect(_rotationAt(s, 8), 45, reason: '⛔전제');

    await _tapTheSnap(tester);
    await _carry(tester, _keyOnScreen(tester, 8), down);
    expect(_keyedFrames(s), [0, 8]);
    expect(_rotationAt(s, 8), closeTo(0, 1e-9));
    s.undo();
    expect(_rotationAt(s, 8), 45);
    expect(s.historyManager.canUndo, undoable);
  });
}

Finder get _snapButton =>
    find.byKey(ValueKey<String>('timeline-lane-graph-snap-$_transformGroup'));

/// A tap on the graph's snap button.
Future<void> _tapTheSnap(WidgetTester tester) async {
  await tester.tap(_snapButton);
  await tester.pumpAndSettle();
}

/// A press on the key at [at], carried [by] and let go.
Future<void> _carry(WidgetTester tester, Offset at, Offset by) async {
  final gesture = await tester.startGesture(
    at,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveBy(by);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

const _drawId = LayerId('draw');

String get _transformGroup =>
    laneGroupKey(_drawId, transformGroupHeaderLane.laneId);

TransformTrack _transformOf(EditorSessionManager s) =>
    s.requireActiveCut.layers.byId(_drawId)!.transformTrack;

List<int> _keyedFrames(EditorSessionManager s) => [
  ..._transformOf(s).rotation.keys.keys,
]..sort();

double _rotationAt(EditorSessionManager s, int frame) =>
    _transformOf(s).rotation.keys[frame]!.value;

Finder get _pictureFinder => find.descendant(
  of: find.byKey(ValueKey<String>('timeline-lane-graph-$_transformGroup')),
  matching: find.byType(LaneGraphPicture),
);

LaneGraphPicture _picture(WidgetTester tester) =>
    tester.widget<LaneGraphPicture>(_pictureFinder);

/// Where the graph marks its lane's key on [frame], on the screen.
Offset _keyOnScreen(WidgetTester tester, int frame) {
  final paint = find.descendant(
    of: _pictureFinder,
    matching: find.byType(CustomPaint),
  );
  final painter =
      tester.widget<CustomPaint>(paint).painter! as TimelineLaneGraphPainter;
  final box = tester.renderObject<RenderBox>(paint);
  final key = painter
      .keysIn(box.size)
      .singleWhere((key) => key.frame == frame);
  return box.localToGlobal(key.at);
}

/// The drawing's lanes twirled open and its Transform graph with them, its
/// Rotation stood on — the one lane the graph then draws — pulled taller
/// than it opens, as `a_graph_key_is_picked_and_carried_test` pulls it.
Future<void> _openTheGraph(WidgetTester tester, EditorSessionManager s) async {
  await _tapNamed(tester, 'timeline-lane-toggle-${_drawId.value}');
  await _tapNamed(
    tester,
    'timeline-lane-group-toggle-draw-${transformGroupHeaderLane.laneId}',
  );
  await _tapNamed(
    tester,
    'timeline-lane-group-graph-draw-${transformGroupHeaderLane.laneId}',
  );
  SessionRowButtonPresses(s).resizeLaneGraph(_transformGroup, 320);
  s.standOnRow(const LaneRowAddress(_drawId, 'rotation'));
  await tester.pumpAndSettle();
}

Future<void> _tapNamed(WidgetTester tester, String name) async {
  final button = find.named(name);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// The app over a cut 48 frames long, its drawing's Rotation keyed 0 on
/// frame 0 and 45 on 8.
Future<EditorSessionManager> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project)),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -520),
  );
  await tester.pumpAndSettle();
  return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
}

final _project = Project(
  id: const ProjectId('graph-snap'),
  name: 'Graph Snap',
  createdAt: DateTime.utc(2026, 10, 30),
  tracks: [
    Track(
      id: const TrackId('t'),
      name: 'V',
      cuts: [
        Cut(
          id: const CutId('c'),
          name: 'C',
          duration: 48,
          canvasSize: const CanvasSize(width: 640, height: 360),
          camera: CutCamera.empty(),
          layers: [
            Layer(
              id: _drawId,
              name: 'Drawing',
              frames: const [],
              transformTrack: TransformTrack.empty().copyWith(
                rotation: PropertyTrack<double>()
                    .withKey(0, 0)
                    .withKey(8, 45),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
