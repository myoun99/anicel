import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
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
import 'package:anicel/src/ui/theme/lane_curve_palette.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;
import 'package:anicel/src/ui/timeline/lane_graph_seats.dart'
    show LaneGraphLine;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// **I-89 ③ — an open header graph draws its lines.**
///
/// The mock (5판): the group's lanes the rail names — the selected, else the
/// stood, else all — solid, each number in its colour; every pin of another
/// group's dashed; a mark on every key; the same graph on the sheet, turned
/// on its side.
void main() {
  tearDown(debugClearValueControlPointers);

  testWidgets('it draws the lanes its seat names — the stood one, else the '
      'picked ones — and its own pins besides', (tester) async {
    final s = await _pump(tester);
    await _openTransform(tester);
    await _tap(tester, 'timeline-lane-group-graph-draw-$_transform');
    s.standOnRow(const LaneRowAddress(_drawId, 'position'));
    s.rowSelection.value = const [];
    await tester.pumpAndSettle();
    expect(_ids(_painter(tester).own), ['position']);

    s.rowSelection.value = const [
      LaneRowAddress(_drawId, 'rotation'),
      LaneRowAddress(_drawId, 'scale'),
    ];
    await tester.pumpAndSettle();
    expect(_ids(_painter(tester).own), ['scale', 'rotation']);

    await _tap(tester, 'timeline-lane-pin-draw-opacity');
    expect(_ids(_painter(tester).own), ['scale', 'rotation', 'opacity']);
    expect(_painter(tester).guests, isEmpty);
  });

  testWidgets('a pin of any other group is drawn as a guest — another '
      'row\'s, and a folded group\'s too', (tester) async {
    final s = await _pump(tester);
    await _openTransform(tester);
    await _tap(tester, 'timeline-lane-group-toggle-draw-$_blur');
    await _tap(tester, 'timeline-lane-toggle-cam');
    await _tap(tester, 'timeline-lane-group-graph-draw-$_transform');
    await _tap(tester, 'timeline-lane-pin-draw-$_blurWidth');
    await _tap(tester, 'timeline-lane-pin-cam-position');
    s.standOnRow(const LaneRowAddress(_drawId, 'position'));
    await tester.pumpAndSettle();

    List<(LayerId, String)> guests() => [
      for (final (:layer, :lane) in _painter(tester).guests)
        (layer.id, lane.laneId),
    ];
    expect(guests(), [(_drawId, _blurWidth), (_camId, 'position')]);

    await _tap(tester, 'timeline-lane-group-toggle-draw-$_blur');
    await _tap(tester, 'timeline-lane-toggle-cam');
    expect(
      find.byKey(ValueKey<String>('timeline-lane-pin-draw-$_blurWidth')),
      findsNothing,
      reason: '⛔전제: the Blur group is folded',
    );
    expect(guests(), [(_drawId, _blurWidth), (_camId, 'position')]);
  });

  testWidgets('each line in its colours, a guest dashed, and a mark on every '
      'key', (tester) async {
    final s = await _pump(tester);
    await _openTransform(tester);
    await _tap(tester, 'timeline-lane-group-toggle-draw-$_blur');
    await _tap(tester, 'timeline-lane-group-graph-draw-$_transform');
    await _tap(tester, 'timeline-lane-pin-draw-$_blurWidth');
    s.standOnRow(const LaneRowAddress(_drawId, 'position'));
    await tester.pumpAndSettle();

    final canvas = TestRecordingCanvas();
    _painter(tester).paint(canvas, tester.getSize(_picture('timeline')));
    final paints = [
      for (final call in canvas.invocations)
        if (call.invocation.memberName == #drawPath)
          call.invocation.positionalArguments[1] as Paint,
    ];
    final strokes = [
      for (final paint in paints)
        if (paint.style == PaintingStyle.stroke) paint,
    ];
    // A paint keeps its colour in floats, so it is read back as 8-bit.
    int ink(Paint paint) => paint.color.toARGB32();
    expect(ink(strokes.first), LaneCurvePalette.across.toARGB32());
    expect(ink(strokes[1]), LaneCurvePalette.down.toARGB32());
    expect(
      strokes.skip(2).map(ink).toSet(),
      {LaneCurvePalette.effectParameter(0).toARGB32()},
      reason: 'the guest\'s line',
    );
    expect(strokes.length - 2, greaterThan(1), reason: 'in dashes');
    expect(strokes.every((paint) => paint.strokeWidth == 2), isTrue);

    final marks = [
      for (final paint in paints)
        if (paint.style == PaintingStyle.fill) ink(paint),
    ];
    final mark = layerMarkColor(_layer.mark).toARGB32();
    expect(marks, List.filled(2 * 2 + 2, mark), reason: 'Position\'s two '
        'keys on each of its numbers, and the Blur\'s two');
  });

  testWidgets('the sheet draws the same graph, turned on its side', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _openTransform(tester);
    await _tap(tester, 'timeline-lane-group-graph-draw-$_transform');
    s.standOnRow(const LaneRowAddress(_drawId, 'scale'));
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();

    final painter = _painter(tester, grid: 'xsheet');
    expect(painter.axis, Axis.vertical);
    expect(_ids(painter.own), ['scale']);
  });

  testWidgets('the camera row\'s graph draws the camera\'s lanes', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _tap(tester, 'timeline-lane-toggle-cam');
    await _tap(tester, 'timeline-layer-graph-cam');
    s.standOnRow(const LayerRowAddress(_drawId));
    await tester.pumpAndSettle();

    final painter = _painter(tester, group: _cameraGroup);
    expect(_ids(painter.own), ['position', 'scale', 'rotation']);
    expect(painter.own.every((line) => line.layer.id == _camId), isTrue);
  });

  testWidgets('it draws only the frames its window shows, as a row of cells '
      'does, and a scroll moves the window by a repaint', (tester) async {
    final s = await _pump(tester, frames: 600);
    await _openTransform(tester);
    await _tap(tester, 'timeline-lane-group-graph-draw-$_transform');
    s.standOnRow(const LaneRowAddress(_drawId, 'position'));
    await tester.pumpAndSettle();

    final painter = _painter(tester);
    final window = painter.visibleFrameWindow();
    expect(
      window.endIndexExclusive,
      lessThan(600),
      reason: '⛔전제: the cut runs on past the window',
    );
    expect(window.startIndex, 0, reason: '⛔전제: the view starts at frame 0');
    var frames = painter.grid.geometry.value;
    final drawn = _drawnAlong(tester);
    expect(
      drawn.start,
      closeTo((frames.edgeAt(0) + frames.edgeAt(1)) / 2, 0.5),
      reason: 'from frame 0\'s middle — there is no time before it',
    );
    expect(drawn.end, closeTo(frames.edgeAt(window.endIndexExclusive), 0.5));

    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(
              const ValueKey<String>('timeline-frame-scroll-viewport'),
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    expect(
      tester.renderObject(_picture('timeline')).debugNeedsPaint,
      isTrue,
      reason: 'the scroll alone asks it to draw again',
    );
    await tester.pumpAndSettle();

    expect(identical(_painter(tester), painter), isTrue, reason: 'no rebuild');
    final moved = painter.visibleFrameWindow();
    frames = painter.grid.geometry.value;
    expect(moved.startIndex, greaterThan(window.endIndexExclusive));
    expect(moved.endIndexExclusive, frames.frameEndIndexExclusive);
    final after = _drawnAlong(tester);
    expect(after.start, closeTo(frames.edgeAt(moved.startIndex), 0.5));
    expect(after.end, closeTo(frames.edgeAt(moved.endIndexExclusive), 0.5));
  });

  testWidgets('the playhead\'s column runs down through the graph', (
    tester,
  ) async {
    await _pump(tester);
    await _openTransform(tester);
    await _tap(tester, 'timeline-lane-group-graph-draw-$_transform');

    final graph = tester.getRect(_graph('timeline'));
    final column = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-playhead-column')),
    );
    expect(column.top, lessThanOrEqualTo(graph.top));
    expect(column.bottom, greaterThanOrEqualTo(graph.bottom));
  });
}

const _drawId = LayerId('draw');
const _camId = LayerId('cam');
const _blurId = EffectId('blur');

String get _transform => transformGroupHeaderLane.laneId;
String get _blur => effectGroupLaneId(_blurId);
String get _blurWidth => effectLaneId(_blurId, 'blurX');
String get _transformGroup => laneGroupKey(_drawId, _transform);
String get _cameraGroup => laneGroupKey(_camId, _transform);

Finder _graph(String grid, {String? group}) => find.byKey(
  ValueKey<String>('$grid-lane-graph-${group ?? _transformGroup}'),
);

/// The graph's picture — what it lays out at its window, not the row it
/// reports.
Finder _picture(String grid, {String? group}) => find.descendant(
  of: _graph(grid, group: group),
  matching: find.byType(CustomPaint),
);

TimelineLaneGraphPainter _painter(
  WidgetTester tester, {
  String grid = 'timeline',
  String? group,
}) =>
    tester.widget<CustomPaint>(_picture(grid, group: group)).painter!
        as TimelineLaneGraphPainter;

/// How far along the frames the timeline graph's lines run, painted now.
({double start, double end}) _drawnAlong(WidgetTester tester) {
  final canvas = TestRecordingCanvas();
  _painter(tester).paint(canvas, tester.getSize(_picture('timeline')));
  final lines = [
    for (final call in canvas.invocations)
      if (call.invocation.memberName == #drawPath &&
          (call.invocation.positionalArguments[1] as Paint).style ==
              PaintingStyle.stroke)
        (call.invocation.positionalArguments[0] as Path).getBounds(),
  ];
  return (
    start: lines.map((line) => line.left).reduce(math.min),
    end: lines.map((line) => line.right).reduce(math.max),
  );
}

List<String> _ids(List<LaneGraphLine> lines) => [
  for (final (:lane, layer: _) in lines) lane.laneId,
];

CameraPose _pose(double x) =>
    CameraPose(center: CanvasPoint(x: x, y: x), zoom: 1.5);

final Layer _layer = Layer(
  id: _drawId,
  name: 'Drawing',
  frames: const [],
  transformTrack: TransformTrack.empty().copyWith(
    position: PropertyTrack<CanvasPoint>()
        .withKey(0, CanvasPoint(x: 100, y: 50))
        .withKey(8, CanvasPoint(x: 180, y: 10)),
    scale: PropertyTrack<CanvasPoint>()
        .withKey(0, CanvasPoint(x: 1, y: 1))
        .withKey(8, CanvasPoint(x: 2, y: 0.5)),
    rotation: PropertyTrack<double>().withKey(0, 0).withKey(8, 45),
    opacity: PropertyTrack<double>().withKey(0, 1).withKey(8, 0.25),
  ),
  effects: [
    LayerEffect(
      id: _blurId,
      kind: EffectKind.blur,
      parameters: {
        'blurX': EffectParameter(
          track: PropertyTrack<double>().withKey(0, 0).withKey(8, 16),
        ),
      },
    ),
  ],
);

Project _project(int frames) => Project(
  id: const ProjectId('graph-lines'),
  name: 'Graph Lines',
  createdAt: DateTime.utc(2026, 10, 11),
  tracks: [
    Track(
      id: const TrackId('t'),
      name: 'V',
      cuts: [
        Cut(
          id: const CutId('c'),
          name: 'C',
          duration: frames,
          canvasSize: const CanvasSize(width: 640, height: 360),
          camera: CutCamera(keyframes: {0: _pose(0), 8: _pose(80)}),
          layers: [
            _layer,
            Layer(
              id: _camId,
              name: 'Camera',
              kind: LayerKind.camera,
              frames: const [],
            ),
          ],
        ),
      ],
    ),
  ],
);

Future<EditorSessionManager> _pump(
  WidgetTester tester, {
  int frames = 12,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project(frames))),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -520),
  );
  await tester.pumpAndSettle();
  return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
}

/// The drawing row's lanes twirled open, and its Transform group.
Future<void> _openTransform(WidgetTester tester) async {
  await _tap(tester, 'timeline-lane-toggle-${_drawId.value}');
  await _tap(tester, 'timeline-lane-group-toggle-draw-$_transform');
}

Future<void> _tap(WidgetTester tester, String key) async {
  final button = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}
