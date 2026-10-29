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
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/layout/device_grid_scroll_controller.dart'
    show ScrollStill;
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/theme/lane_curve_palette.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;
import 'package:anicel/src/ui/timeline/lane_graph.dart' show LaneGraphMode;
import 'package:anicel/src/ui/timeline/lane_graph_seats.dart'
    show LaneGraphLine;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/timeline_lane_graph.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show TimelineLaneKeyMarker;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import 'package:anicel/src/ui/widgets/pill_strip.dart' show Pill;

import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';
import '../../helpers/timeline_zoom.dart';

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
    await _tapNamed(tester, 'timeline-lane-group-graph-draw-$_transform');
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

    await _tapNamed(tester, 'timeline-lane-pin-draw-opacity');
    expect(_ids(_painter(tester).own), ['scale', 'rotation', 'opacity']);
    expect(_painter(tester).guests, isEmpty);
    expect(_tags('timeline'), findsNothing, reason: 'no guest to name');
  });

  testWidgets('a pin of any other group is drawn as a guest — another '
      'row\'s, and a folded group\'s too', (tester) async {
    final s = await _pump(tester);
    await _openTransform(tester);
    await _tapNamed(tester, 'timeline-lane-group-toggle-draw-$_blur');
    await _tapNamed(tester, 'timeline-lane-toggle-cam');
    await _tapNamed(tester, 'timeline-lane-group-graph-draw-$_transform');
    await _tapNamed(tester, 'timeline-lane-pin-draw-$_blurWidth');
    await _tapNamed(tester, 'timeline-lane-pin-cam-position');
    s.standOnRow(const LaneRowAddress(_drawId, 'position'));
    await tester.pumpAndSettle();

    List<(LayerId, String)> guests() => [
      for (final (:layer, :lane, reach: _) in _painter(tester).guests)
        (layer.id, lane.laneId),
    ];
    expect(guests(), [(_drawId, _blurWidth), (_camId, 'position')]);

    await _tapNamed(tester, 'timeline-lane-group-toggle-draw-$_blur');
    await _tapNamed(tester, 'timeline-lane-toggle-cam');
    expect(
      find.named('timeline-lane-pin-draw-$_blurWidth'),
      findsNothing,
      reason: '⛔전제: the Blur group is folded',
    );
    expect(guests(), [(_drawId, _blurWidth), (_camId, 'position')]);
  });

  testWidgets('each line in its colours, a guest dashed, and a mark on every '
      'key', (tester) async {
    final s = await _pump(tester);
    await _openTransform(tester);
    await _tapNamed(tester, 'timeline-lane-group-toggle-draw-$_blur');
    await _tapNamed(tester, 'timeline-lane-group-graph-draw-$_transform');
    await _tapNamed(tester, 'timeline-lane-pin-draw-$_blurWidth');
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

  // 🗣️F-367-Q3 (유저 2026-10-17): 「레인 멤버 키와 같은 크기」 — every line
  // a graph draws is a member lane.
  testWidgets('a key\'s mark is as big as its member lane marks it — at every '
      'zoom', (tester) async {
    final s = await _pump(tester);
    await _openTransform(tester);
    await _tapNamed(tester, 'timeline-lane-group-toggle-draw-$_blur');
    await _tapNamed(tester, 'timeline-lane-group-graph-draw-$_transform');
    s.standOnRow(const LaneRowAddress(_drawId, 'position'));
    await tester.pumpAndSettle();

    // The Blur's width, its group's graph shut: a member lane marking its
    // key at 0 itself.
    Size memberMark() => tester
        .widget<TimelineLaneKeyMarker>(
          find.byKey(ValueKey<String>('timeline-lane-key-draw-$_blurWidth-0')),
        )
        .markerSize;
    // Each key's mark as drawn — the whole of its box, whatever its shape,
    // to a float's precision: a path keeps its points in floats.
    List<Size> graphMarks() {
      final canvas = TestRecordingCanvas();
      _painter(tester).paint(canvas, tester.getSize(_picture('timeline')));
      return [
        for (final call in canvas.invocations)
          if (call.invocation.memberName == #drawPath &&
              (call.invocation.positionalArguments[1] as Paint).style ==
                  PaintingStyle.fill)
            (call.invocation.positionalArguments[0] as Path).getBounds().size,
      ];
    }

    // Zoomed in, a frame's cell is wider than a lane's row is tall and the
    // row is the tighter of the two; zoomed out, the cell is.
    final seen = <Size>{};
    for (final (step, zoom) in [32.0, 24.0, 16.0].indexed) {
      await zoomTimelineTo(tester, zoom);
      final member = memberMark();
      seen.add(member);
      final marks = graphMarks();
      expect(marks, hasLength(2 * 2), reason: '⛔전제: Position\'s keys');
      for (final mark in marks) {
        expect(
          mark,
          within(distance: 1e-3, from: member),
          reason: 'zoom step $step',
        );
      }
    }
    expect(seen, hasLength(3), reason: '⛔전제: the zoom moved the marks');
  });

  testWidgets('an edit in flight shows in it as its rows show it — its own '
      'lane\'s and a guest\'s — and goes with it', (tester) async {
    final s = await _pump(tester);
    await _pinTheBlur(tester, s);
    List<double> own() => _painter(tester).own.single.lane.curve!.at(8);
    List<double> guest() => _painter(tester).guests.single.lane.curve!.at(8);
    expect(own(), [180, 10]);
    expect(guest(), [16]);

    s.laneVerbs.previewLaneValueAt(
      _drawId,
      'position',
      8,
      '300, 200',
      frameIsGlobal: false,
      scaleLinked: false,
    );
    await tester.pump();
    expect(own(), [300, 200], reason: 'the stood lane, as the drag shows it');

    s.laneVerbs.previewLaneValueAt(
      _drawId,
      _blurWidth,
      8,
      '30',
      frameIsGlobal: false,
      scaleLinked: false,
    );
    await tester.pump();
    expect(guest(), [30], reason: 'the pin, as the drag shows it');

    s.laneVerbs.endLaneEditPreview();
    await tester.pump();
    expect(own(), [180, 10]);
    expect(guest(), [16]);
  });

  testWidgets('the sheet draws the same graph, turned on its side', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _openTransform(tester);
    await _tapNamed(tester, 'timeline-lane-group-graph-draw-$_transform');
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
    await _tapNamed(tester, 'timeline-lane-toggle-cam');
    await _tapNamed(tester, 'timeline-layer-graph-cam');
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
    await _tapNamed(tester, 'timeline-lane-group-graph-draw-$_transform');
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
    var frames = painter.frameAxis.geometry.value;
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
    frames = painter.frameAxis.geometry.value;
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
      final tools = tester.getRect(_tools('timeline'));
      final seen = '$when — view $view, graph $graph, tags $rect, tools '
          '$tools, offset ${scroll.position.pixels}';
      expect(rect.right, moreOrLessEquals(view.right - 8), reason: seen);
      expect(
        rect.left,
        moreOrLessEquals(tools.right + 8),
        reason: 'the room the tools leave them, all of it — $seen',
      );
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
      'its pin whole, and the tools their enlarge button', (tester) async {
    // 1040 → 680 (I-89 Q1, 2026-10-12): the rail is 519 again, and a
    // window's region never opens narrower than 640 by itself — so a
    // window under that. 680 → 622 (F-409, 2026-10-20): the names gave a
    // third up and the rail is 461, so the view kept its forty. 622
    // → 530 (heavy-tests-timeline, 2026-10-25): the panel's own width,
    // which that window laid between its side docks.
    final s = await _pump(tester, frames: 600, width: 530);
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
    final enlarge = tester.getRect(
      find.byKey(
        ValueKey<String>('timeline-lane-graph-enlarge-$_transformGroup'),
      ),
    );
    expect(
      enlarge.width,
      greaterThanOrEqualTo(20),
      reason: 'the pills give their width up, and then the pen — the '
          'enlarge button none of its own',
    );
    expect(
      enlarge.right,
      lessThanOrEqualTo(tester.getRect(_tools('timeline')).right),
    );
    expect(
      tester.getRect(_tools('timeline')).right,
      moreOrLessEquals(view.right - 6),
      reason: 'no wider than the view, kept off its end as off its start',
    );
    expect(
      tester.getRect(_tags('timeline')).left,
      moreOrLessEquals(tester.getRect(_tools('timeline')).right + 8),
      reason: 'it starts after the tools and runs out past the view\'s end',
    );
  });

  testWidgets('its tools stand at the view\'s start, the values plotted — '
      'and 속도 plots how fast each number changes, from still at the foot '
      'to its fastest at the top, marking no key; 값 brings the values '
      'back', (tester) async {
    final s = await _pump(tester);
    await _openTransform(tester);
    await _tapNamed(tester, 'timeline-lane-group-graph-draw-$_transform');
    s.standOnRow(const LaneRowAddress(_drawId, 'position'));
    await tester.pumpAndSettle();

    final view = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
    );
    final graph = tester.getRect(_graph('timeline'));
    final tools = tester.getRect(_tools('timeline'));
    expect(tools.left, moreOrLessEquals(view.left + 6));
    expect(tools.top, moreOrLessEquals(graph.top + 6));
    expect(_plots(tester, LaneGraphMode.value), isTrue);
    expect(_plots(tester, LaneGraphMode.speed), isFalse);
    final extent = tester.getSize(_picture('timeline')).height;
    bool spansThePadding(Rect line) =>
        (line.top - 16).abs() < 0.5 &&
        (line.bottom - (extent - 16)).abs() < 0.5;
    expect(
      _strokes(tester).any(spansThePadding),
      isFalse,
      reason: '⛔전제: a value line keeps its spare inside the padding',
    );

    await _tap(tester, _plot('timeline', LaneGraphMode.speed));
    expect(
      s.railView.laneGraphs.value.open[_transformGroup]!.mode,
      LaneGraphMode.speed,
    );
    expect(_painter(tester).mode, LaneGraphMode.speed);
    expect(_plots(tester, LaneGraphMode.speed), isTrue);
    expect(_plots(tester, LaneGraphMode.value), isFalse);
    // Position runs from its key on 0 to its key on 8 at an even speed
    // (sides linear), and stands after it.
    final speeds = _strokes(tester);
    expect(speeds, hasLength(1), reason: 'I-89-Q5 B: a point\'s one speed');
    expect(speeds.every(spansThePadding), isTrue, reason: '$speeds');
    expect(_marks(tester), 0, reason: 'the speed graph marks no key');

    await _tap(tester, _plot('timeline', LaneGraphMode.value));
    expect(_painter(tester).mode, LaneGraphMode.value);
    expect(_marks(tester), 2 * 2);
  });

  testWidgets('on the sheet its tools stand at the top right — the '
      'timeline\'s top left turned a quarter clockwise', (tester) async {
    final s = await _pump(tester, tall: true);
    await _openTransform(tester);
    await _tapNamed(tester, 'timeline-lane-group-graph-draw-$_transform');
    s.standOnRow(const LaneRowAddress(_drawId, 'position'));
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();

    final view = tester.getRect(
      find.byKey(const ValueKey<String>('xsheet-frame-vertical-viewport')),
    );
    final graph = tester.getRect(_graph('xsheet'));
    final tools = tester.getRect(_tools('xsheet'));
    expect(tools.top, moreOrLessEquals(view.top + 6));
    expect(tools.right, moreOrLessEquals(graph.right - 6));

    await _tap(tester, _plot('xsheet', LaneGraphMode.speed));
    expect(_painter(tester, grid: 'xsheet').mode, LaneGraphMode.speed);
  });

  testWidgets('the playhead\'s column runs down through the graph', (
    tester,
  ) async {
    await _pump(tester);
    await _openTransform(tester);
    await _tapNamed(tester, 'timeline-lane-group-graph-draw-$_transform');

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
String get _blurWidth => effectLaneId(_blurId, 'blurriness');
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

/// Where each of the timeline graph's lines runs, painted now.
List<Rect> _strokes(WidgetTester tester) {
  final canvas = TestRecordingCanvas();
  _painter(tester).paint(canvas, tester.getSize(_picture('timeline')));
  return [
    for (final call in canvas.invocations)
      if (call.invocation.memberName == #drawPath &&
          (call.invocation.positionalArguments[1] as Paint).style ==
              PaintingStyle.stroke)
        (call.invocation.positionalArguments[0] as Path).getBounds(),
  ];
}

/// How far along the frames the timeline graph's lines run, painted now.
({double start, double end}) _drawnAlong(WidgetTester tester) {
  final lines = _strokes(tester);
  return (
    start: lines.map((line) => line.left).reduce(math.min),
    end: lines.map((line) => line.right).reduce(math.max),
  );
}

/// The drawing's Transform graph's tools on [grid].
Finder _tools(String grid) => find.descendant(
  of: _graph(grid),
  matching: find.byType(LaneGraphTools),
);

/// The key of the pill on [grid]'s Transform graph that plots [mode].
String _plot(String grid, LaneGraphMode mode) =>
    '$grid-lane-graph-plot-${mode.name}-$_transformGroup';

/// Whether the timeline graph's pill for [mode] is the one chosen.
bool _plots(WidgetTester tester, LaneGraphMode mode) => tester
    .widget<Pill>(find.byKey(ValueKey<String>(_plot('timeline', mode))))
    .selected;

List<String> _ids(List<LaneGraphLine> lines) => [
  for (final (:lane, layer: _, reach: _) in lines) lane.laneId,
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
        'blurriness': EffectParameter(
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
  final across = partAcross(axis, end).floor();
  final edge = partAlong(axis, end);
  bool isGround(int at) {
    final i = (along ? across * width + at : at * width + across) * 4;
    final ground = AppColors.surface;
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

/// The timeline tab alone ([pumpTimelineHost]). [tall]: as a window twice as
/// tall laid it — the sheet stands the rail up as its header (~490px), and
/// the shorter one leaves the frames 48px. [width] is the panel's — the view
/// narrows with it, as it did in the app's window of 1400, which laid the
/// panel 870 wide between its side docks — and [layerName] names the
/// drawing.
Future<EditorSessionManager> _pump(
  WidgetTester tester, {
  int frames = 12,
  bool tall = false,
  double width = 870,
  String layerName = 'Drawing',
}) => pumpTimelineHost(
  tester,
  _project(frames, layerName),
  surface: Size(width, tall ? 610 : 546),
);

/// The drawing's Transform graph open and stood on its Position, with the
/// Blur's width pinned to it: one guest.
Future<void> _pinTheBlur(WidgetTester tester, EditorSessionManager s) async {
  await _openTransform(tester);
  await _tapNamed(tester, 'timeline-lane-group-toggle-draw-$_blur');
  await _tapNamed(tester, 'timeline-lane-group-graph-draw-$_transform');
  await _tapNamed(tester, 'timeline-lane-pin-draw-$_blurWidth');
  s.standOnRow(const LaneRowAddress(_drawId, 'position'));
  await tester.pumpAndSettle();
}

/// The drawing row's lanes twirled open, and its Transform group.
Future<void> _openTransform(WidgetTester tester) async {
  await _tapNamed(tester, 'timeline-lane-toggle-${_drawId.value}');
  await _tapNamed(tester, 'timeline-lane-group-toggle-draw-$_transform');
}

Future<void> _tap(WidgetTester tester, String key) =>
    _tapFound(tester, find.byKey(ValueKey<String>(key)));

Future<void> _tapNamed(WidgetTester tester, String name) =>
    _tapFound(tester, find.named(name));

Future<void> _tapFound(WidgetTester tester, Finder button) async {
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}
