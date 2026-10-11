import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show OffsetLayer, RenderAbstractViewport, RenderParagraph;
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
import 'package:anicel/src/ui/layout/device_grid_scroll_controller.dart'
    show ScrollStill;
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
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
    expect(_tags('timeline'), findsNothing, reason: 'no guest to name');
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
    expect(
      _marks(tester),
      2 * 2,
      reason: 'Position\'s keys at 0 and 8, on each of its numbers',
    );

    final scroll = _frameScroll(tester, 'timeline-frame-scroll-viewport');
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
    expect(_marks(tester), 0, reason: 'its keys are out of the window now');
  });

  testWidgets('a guest is named at the view\'s end — 「layer · lane」 and '
      'its pin — and stays there as the view scrolls', (tester) async {
    _atAFractionalRatio(tester);
    final s = await _pump(tester, frames: 600);
    await _pinTheBlur(tester, s);

    final tags = _tags('timeline');
    final guest = _painter(tester).guests.single;
    final name = find.descendant(
      of: tags,
      matching: find.text('Drawing · ${guest.lane.label}'),
    );
    expect(name, findsOneWidget);
    expect(
      find.descendant(of: tags, matching: find.byIcon(Icons.push_pin)),
      findsOneWidget,
    );
    expect(
      tester.renderObject<RenderParagraph>(name).didExceedMaxLines,
      isTrue,
      reason: 'a name longer than the view has room for ends in an ellipsis',
    );

    const viewport = 'timeline-frame-scroll-viewport';
    final view = tester.getRect(find.byKey(const ValueKey<String>(viewport)));
    final scroll = _frameScroll(tester, viewport);
    void expectAtTheViewsEnd(String when) {
      final rect = tester.getRect(tags);
      final graph = tester.getRect(_graph('timeline'));
      final seen = '$when — view $view, graph $graph, tags $rect, offset '
          '${scroll.position.pixels}';
      expect(rect.right, moreOrLessEquals(view.right - 8), reason: seen);
      expect(rect.left, greaterThanOrEqualTo(view.left + 8), reason: seen);
      expect(rect.top, moreOrLessEquals(graph.top + 6), reason: seen);
    }

    expectAtTheViewsEnd('at the start');
    await _scrollMovesTheTagsLayer(
      tester,
      grid: 'timeline',
      viewport: viewport,
      scroll: scroll.position,
    );
    for (final to in [1234.37, scroll.position.maxScrollExtent]) {
      scroll.position.jumpTo(to);
      await tester.pump();
      expectAtTheViewsEnd('scrolled to $to');
    }
    // The window taken to a screen of another ratio: they land on its grid
    // as the content does.
    tester.view.devicePixelRatio = 1.25;
    await tester.pump();
    scroll.position.jumpTo(2345.61);
    await tester.pump();
    expectAtTheViewsEnd('at a ratio of 1.25');
  });

  testWidgets('they stay at the view\'s end while the panel is resized', (
    tester,
  ) async {
    _atAFractionalRatio(tester);
    final s = await _pump(tester, frames: 600);
    await _pinTheBlur(tester, s);
    const viewport = ValueKey<String>('timeline-frame-scroll-viewport');
    _frameScroll(tester, viewport.value).position.jumpTo(1234.37);
    await tester.pump();

    for (final width in [1520.0, 1680.0, 1400.0]) {
      await tester.binding.setSurfaceSize(Size(width, 1200));
      await tester.pump();
      final view = tester.getRect(find.byKey(viewport));
      expect(
        tester.getRect(_tags('timeline')).right,
        moreOrLessEquals(view.right - 8),
        reason: '$width wide — view $view',
      );
    }
  });

  testWidgets('the sheet names them at its view\'s end too, turned on its '
      'side: the bottom right — the tags themselves upright', (tester) async {
    _atAFractionalRatio(tester);
    // Longer than the graph is wide: the sheet bounds them by the graph.
    const layerName = 'A drawing whose name runs on past any sheet graph';
    final s = await _pump(
      tester,
      frames: 600,
      tall: true,
      layerName: layerName,
    );
    await _pinTheBlur(tester, s);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();

    final tags = _tags('xsheet');
    final guest = _painter(tester, grid: 'xsheet').guests.single;
    final name = find.descendant(
      of: tags,
      matching: find.text('$layerName · ${guest.lane.label}'),
    );
    expect(
      name,
      findsOneWidget,
      reason: 'it reads across, as the timeline\'s does',
    );
    expect(
      tester.renderObject<RenderParagraph>(name).didExceedMaxLines,
      isTrue,
      reason: 'a name wider than the graph ends in an ellipsis',
    );
    const viewport = 'xsheet-frame-vertical-viewport';
    final view = tester.getRect(find.byKey(const ValueKey<String>(viewport)));
    final scroll = _frameScroll(tester, viewport);
    void expectAtTheViewsEnd(String when) {
      final rect = tester.getRect(tags);
      final graph = tester.getRect(_graph('xsheet'));
      final seen = '$when — view $view, graph $graph, tags $rect, offset '
          '${scroll.position.pixels}';
      expect(rect.bottom, moreOrLessEquals(view.bottom - 8), reason: seen);
      expect(rect.right, moreOrLessEquals(graph.right - 6), reason: seen);
      expect(rect.left, greaterThanOrEqualTo(graph.left + 6), reason: seen);
    }

    expectAtTheViewsEnd('at the start');
    await _scrollMovesTheTagsLayer(
      tester,
      grid: 'xsheet',
      viewport: viewport,
      scroll: scroll.position,
    );
    for (final to in [1234.37, scroll.position.maxScrollExtent]) {
      scroll.position.jumpTo(to);
      await tester.pump();
      expectAtTheViewsEnd('scrolled to $to');
    }
  });

  testWidgets('in a view too narrow for any name, a tag keeps its dash and '
      'its pin whole', (tester) async {
    final s = await _pump(tester, frames: 600, width: 1040);
    await _pinTheBlur(tester, s);

    final view = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
    );
    expect(
      view.width,
      lessThan(2 * 8 + 14 + 2 * 6 + 16 + 2 * 8),
      reason: '⛔전제: the view leaves less than a tag\'s dash and pin',
    );
    expect(tester.takeException(), isNull, reason: 'its row did not overflow');
    expect(
      tester.getRect(_tags('timeline')).left,
      moreOrLessEquals(view.left + 8),
      reason: 'it starts in the view and runs out past its end',
    );
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

/// A graph's guest tags, on the drawing's Transform graph.
Finder _tags(String grid) => find.byKey(
  ValueKey<String>('$grid-lane-graph-guests-$_transformGroup'),
);

/// The scrollable under a grid's frame [viewport].
ScrollableState _frameScroll(WidgetTester tester, String viewport) =>
    tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(ValueKey<String>(viewport)),
            matching: find.byType(Scrollable),
          )
          .first,
    );

/// The graph's picture — what it lays out at its window, not the row it
/// reports — of the paints in it, the one its painter draws.
Finder _picture(String grid, {String? group}) => find.descendant(
  of: _graph(grid, group: group),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint && widget.painter is TimelineLaneGraphPainter,
  ),
);

TimelineLaneGraphPainter _painter(
  WidgetTester tester, {
  String grid = 'timeline',
  String? group,
}) =>
    tester.widget<CustomPaint>(_picture(grid, group: group)).painter!
        as TimelineLaneGraphPainter;

/// How many key marks the timeline graph draws, painted now.
int _marks(WidgetTester tester) {
  final canvas = TestRecordingCanvas();
  _painter(tester).paint(canvas, tester.getSize(_picture('timeline')));
  return [
    for (final call in canvas.invocations)
      if (call.invocation.memberName == #drawPath &&
          (call.invocation.positionalArguments[1] as Paint).style ==
              PaintingStyle.fill)
        call,
  ].length;
}

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

Project _project(int frames, String layerName) => Project(
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
            _layer.copyWith(name: layerName),
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

/// A device ratio with a fraction, so the device-grid landing the content
/// wears is not the identity (「이음매 테스트는 소수 배율에서」).
void _atAFractionalRatio(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.5;
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A small step of [scroll] moves [grid]'s guest tags by their layer, as a
/// ruler follows its cells (a-scroll-moves-a-layer): nothing of them is
/// painted again or laid out — and the picture the compositor makes of the
/// frames' [viewport] has them where the render tree lays them.
Future<void> _scrollMovesTheTagsLayer(
  WidgetTester tester, {
  required String grid,
  required String viewport,
  required ScrollPosition scroll,
}) async {
  final box = tester.renderObject(
    find.ancestor(of: _tags(grid), matching: find.byType(ScrollStill)),
  );
  final painted = box.debugLayer!.firstChild;
  scroll.jumpTo(scroll.pixels + 3.37);
  expect(box.debugNeedsPaint, isFalse, reason: 'the step paints no tag');
  expect(box.debugNeedsLayout, isFalse, reason: 'and lays nothing out');
  await tester.pump();
  expect(
    identical(box.debugLayer!.firstChild, painted),
    isTrue,
    reason: 'their picture is the one painted before the step — their '
        'layer moved it',
  );
  await _expectTheCompositorShowsTheTags(
    tester,
    grid: grid,
    viewport: viewport,
    axis: scroll.axis,
  );
}

/// Where the compositor puts the end of [grid]'s guest tags along the
/// frames — their hairline, crossed at its middle — in the picture of the
/// frames' [viewport], against where the render tree lays it. The move is
/// their layer's, so a pin that read only the render tree would pass a
/// layer the scene never moved. Their end: the timeline's start stands
/// under the playhead's column, which washes it.
Future<void> _expectTheCompositorShowsTheTags(
  WidgetTester tester, {
  required String grid,
  required String viewport,
  required Axis axis,
}) async {
  final port = _firstViewportUnder(tester, viewport);
  final ratio = tester.view.devicePixelRatio;
  final picture = await tester.runAsync(() async {
    final image = await (port.debugLayer! as OffsetLayer).toImage(
      Offset.zero & port.size,
      pixelRatio: ratio,
    );
    final bytes = (await image.toByteData())!;
    final (width, height) = (image.width, image.height);
    image.dispose();
    return (bytes: bytes, width: width, height: height);
  });
  final (:bytes, :width, :height) = picture!;
  final along = axis == Axis.horizontal;
  final tags = tester.getRect(_tags(grid));
  final end =
      port.globalToLocal(along ? tags.centerRight : tags.bottomCenter) *
      ratio;
  final across = (along ? end.dy : end.dx).floor();
  final edge = along ? end.dx : end.dy;
  bool isGround(int at) {
    final i = (along ? across * width + at : at * width + across) * 4;
    const ground = AppColors.surface;
    bool near(int byte, double channel) =>
        (bytes.getUint8(i + byte) - (channel * 255).round()).abs() < 8;
    return near(0, ground.r) && near(1, ground.g) && near(2, ground.b);
  }

  // From inside the tag's own ground, in its padding at that end, to the
  // first pixel that is not that ground: its hairline.
  final from = (edge - 3 * ratio).round();
  expect(isGround(from), isTrue, reason: 'the tag\'s ground stands there');
  var first = from;
  final last = (along ? width : height) - 1;
  while (first < last && isGround(first)) {
    first += 1;
  }
  expect(
    first,
    closeTo(edge - ratio, 1.5),
    reason: 'its hairline starts there',
  );
}

/// The viewport the frames scroll in under [key] — the timeline's
/// [Viewport], the sheet's [SingleChildScrollView]'s own.
RenderBox _firstViewportUnder(WidgetTester tester, String key) {
  RenderBox? found;
  void visit(RenderObject child) {
    if (found != null) {
      return;
    }
    if (child is RenderAbstractViewport) {
      found = child as RenderBox;
      return;
    }
    child.visitChildren(visit);
  }

  visit(tester.renderObject(find.byKey(ValueKey<String>(key))));
  return found!;
}

/// [tall]: a surface twice as tall, the dock at its cap of half of it —
/// the sheet stands the rail up as its header (~490px), and under 1200px
/// the frames are left 48px. [width] narrows the frames' view with it, and
/// [layerName] names the drawing.
Future<EditorSessionManager> _pump(
  WidgetTester tester, {
  int frames = 12,
  bool tall = false,
  double width = 1400,
  String layerName = 'Drawing',
}) async {
  await tester.binding.setSurfaceSize(Size(width, tall ? 2400 : 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project(frames, layerName))),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    Offset(0, tall ? -1200 : -520),
  );
  await tester.pumpAndSettle();
  return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
}

/// The drawing's Transform graph open and stood on its Position, with the
/// Blur's width pinned to it: one guest.
Future<void> _pinTheBlur(WidgetTester tester, EditorSessionManager s) async {
  await _openTransform(tester);
  await _tap(tester, 'timeline-lane-group-toggle-draw-$_blur');
  await _tap(tester, 'timeline-lane-group-graph-draw-$_transform');
  await _tap(tester, 'timeline-lane-pin-draw-$_blurWidth');
  s.standOnRow(const LaneRowAddress(_drawId, 'position'));
  await tester.pumpAndSettle();
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
