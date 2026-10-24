import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
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
import 'package:anicel/src/ui/text/app_strings.dart' show AppText;
import 'package:anicel/src/ui/timeline/lane_graph.dart'
    show LaneGraph, laneGraphFoldedExtent, laneGraphOpeningRows;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane, transformLaneDisplayOrder;
import 'package:anicel/src/ui/widgets/app_icon_button.dart'
    show AppIconButtonFace;

import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';

/// **I-89 ③D — a header graph is enlarged over every other row.**
///
/// The mock (5판): its tools' last button gives the panel to the graph —
/// 「크게 보기는 다른 행을 얇은 띠로 접어 패널 대부분을 이 그래프에
/// 줍니다」. The graph stands as far as the view lets one, a shut group's
/// lanes thin to strips that keep their keys, another open graph thins to
/// one empty strip, and every header and layer row stands as it was.
void main() {
  tearDown(debugClearValueControlPointers);

  testWidgets('enlarged, it stands the view less its header\'s row, and '
      'every other lane folds to a thin strip', (tester) async {
    final s = await _pump(tester);
    await _openEverything(tester);
    await _tap(tester, _enlarge('timeline', _draw));

    expect(_enlarged(s), {_group(_draw)});
    final row = _rowExtent(tester);
    final view = _viewOf(tester, _rowsScroll(tester));
    expect(
      tester.getRect(_graph('timeline', _draw)).height,
      moreOrLessEquals(view.height - row),
      reason: 'its header and it fill the view',
    );
    for (final lane in transformLaneDisplayOrder) {
      expect(
        tester.getRect(_label('timeline', _side, lane)).height,
        moreOrLessEquals(laneGraphFoldedExtent),
        reason: 'a shut group\'s $lane: its own thin strip',
      );
    }
    expect(
      find.descendant(
        of: _label('timeline', _side, 'position'),
        matching: find.text('Position'),
      ),
      findsNothing,
      reason: 'the strip\'s rail is emptied',
    );
    expect(
      _graph('timeline', _more),
      findsNothing,
      reason: 'another open graph draws nothing in its strip',
    );
    expect(
      tester.getRect(_label('timeline', _more, 'anchor-point')).height,
      moreOrLessEquals(laneGraphFoldedExtent),
      reason: 'ONE strip, its first lane\'s',
    );
    expect(_label('timeline', _more, 'position'), findsNothing);
    for (final layer in [_more, _side, _draw]) {
      expect(
        tester.getRect(_label('timeline', layer, _transform)).height,
        moreOrLessEquals(row),
        reason: 'every header stands',
      );
      expect(
        tester.getRect(_cells(layer)).height,
        moreOrLessEquals(row),
        reason: 'every layer row stands',
      );
    }
  });

  testWidgets('a folded lane keeps its keys, inside its strip', (
    tester,
  ) async {
    await _pump(tester);
    await _openEverything(tester);
    await _tap(tester, _enlarge('timeline', _draw));

    final strip = tester.getRect(
      find.named('timeline-row-${_side.value}-position'),
    );
    expect(strip.height, moreOrLessEquals(laneGraphFoldedExtent));
    final key = find.byKey(
      ValueKey<String>('timeline-lane-key-${_side.value}-position-0'),
    );
    expect(key, findsWidgets, reason: 'the mock keeps a thinned lane\'s keys');
    final mark = tester.getRect(key.first);
    expect(mark.top, greaterThanOrEqualTo(strip.top - 0.01));
    expect(mark.bottom, lessThanOrEqualTo(strip.bottom + 0.01));
  });

  testWidgets('a folded lane is still its row: pressed, it is stood on', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _openEverything(tester);
    await _tap(tester, _enlarge('timeline', _draw));

    await tester.tap(_label('timeline', _side, 'scale'));
    await tester.pumpAndSettle();
    expect(
      s.currentRow,
      const LaneRowAddress(_side, 'scale'),
      reason: 'the mock wires a thinned lane\'s rail as it was',
    );
  });

  testWidgets('its button wears the glyph that lets it back, on, and '
      'pressed again lets every row back', (tester) async {
    final s = await _pump(tester);
    await _openEverything(tester);
    final row = _rowExtent(tester);
    await _reach(tester, _enlarge('timeline', _draw));
    expect(_face(tester, _draw).isSelected, isFalse);
    expect(_face(tester, _draw).tooltip, AppText.strings.laneGraphEnlarge);
    expect(
      find.descendant(
        of: _enlarge('timeline', _draw),
        matching: find.byIcon(Icons.open_in_full),
      ),
      findsOneWidget,
    );

    await _tap(tester, _enlarge('timeline', _draw));
    expect(_face(tester, _draw).isSelected, isTrue);
    expect(_face(tester, _draw).tooltip, AppText.strings.laneGraphEnlargeOn);
    expect(
      find.descendant(
        of: _enlarge('timeline', _draw),
        matching: find.byIcon(Icons.close_fullscreen),
      ),
      findsOneWidget,
    );

    await _tap(tester, _enlarge('timeline', _draw));
    expect(_enlarged(s), isEmpty);
    expect(
      tester.getRect(_label('timeline', _side, 'position')).height,
      moreOrLessEquals(row),
    );
    expect(_graph('timeline', _more), findsOneWidget);
    await _reach(tester, _graph('timeline', _draw));
    expect(
      tester.getRect(_graph('timeline', _draw)).height,
      moreOrLessEquals(laneGraphOpeningRows * row),
    );
  });

  testWidgets('a graph turned on while another is enlarged opens folded, '
      'its tools with it', (tester) async {
    final s = await _pump(tester);
    await _openEverything(tester);
    await _tap(tester, _enlarge('timeline', _draw));
    await _tap(tester, _graphButton(_side));

    expect(s.railView.laneGraphs.value.open, contains(_group(_side)));
    expect(_enlarged(s), {_group(_draw)});
    expect(_graph('timeline', _side), findsNothing);
    expect(_enlarge('timeline', _side), findsNothing);
    expect(
      tester.getRect(_label('timeline', _side, 'anchor-point')).height,
      moreOrLessEquals(laneGraphFoldedExtent),
    );
    expect(_label('timeline', _side, 'position'), findsNothing);
  });

  testWidgets('its graph shut lets it back', (tester) async {
    final s = await _pump(tester);
    await _openEverything(tester);
    await _tap(tester, _enlarge('timeline', _draw));
    await _tap(tester, _graphButton(_more));
    expect(
      _enlarged(s),
      {_group(_draw)},
      reason: 'another graph shut leaves it',
    );

    await _tap(tester, _graphButton(_draw));
    expect(_enlarged(s), isEmpty);
    await _tap(tester, _graphButton(_draw));
    final row = _rowExtent(tester);
    await _reach(tester, _graph('timeline', _draw));
    expect(
      tester.getRect(_graph('timeline', _draw)).height,
      moreOrLessEquals(laneGraphOpeningRows * row),
      reason: 'it opens again as it was before it was enlarged',
    );
  });

  testWidgets('pulled, its grip stops where an enlarged graph stands', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _openEverything(tester);
    final row = _rowExtent(tester);
    final view = _viewOf(tester, _rowsScroll(tester));

    final gesture = await _grab(tester, _draw);
    await gesture.moveBy(const Offset(0, 3000));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      s.railView.laneGraphs.value.open[_group(_draw)]?.extent,
      moreOrLessEquals(view.height - row),
    );
  });

  testWidgets('a graph kept taller than the view lets one is drawn at the '
      'most, and keeps what it was told', (tester) async {
    final s = await _pump(tester);
    await _openEverything(tester);
    final graphs = s.railView.laneGraphs;
    graphs.value = graphs.value.copyWith(
      open: {...graphs.value.open, _group(_draw): const LaneGraph(extent: 5000)},
    );
    await tester.pumpAndSettle();

    final view = _viewOf(tester, _rowsScroll(tester));
    final row = _rowExtent(tester);
    await _reach(tester, _graph('timeline', _draw));
    expect(
      tester.getRect(_graph('timeline', _draw)).height,
      moreOrLessEquals(view.height - row),
    );
    expect(graphs.value.open[_group(_draw)]?.extent, 5000);
  });

  testWidgets('the panel resized, it stands the new view less its header\'s '
      'row', (tester) async {
    await _pumpApp(tester);
    await _openEverything(tester);
    await _tap(tester, _enlarge('timeline', _draw));
    final row = _rowExtent(tester);
    final before = _viewOf(tester, _rowsScroll(tester)).height;

    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, 120),
    );
    await tester.pumpAndSettle();
    final view = _viewOf(tester, _rowsScroll(tester));
    expect(view.height, lessThan(before - 60), reason: '⛔전제: it shrank');
    await _reach(tester, _graph('timeline', _draw));
    expect(
      tester.getRect(_graph('timeline', _draw)).height,
      moreOrLessEquals(view.height - row),
    );
  });

  testWidgets('on the sheet it is enlarged across, the columns\' view less '
      'its header\'s column', (tester) async {
    await _pump(tester, tall: true);
    await _openEverything(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
    await _tap(tester, _enlarge('xsheet', _draw));

    final column = tester
        .getRect(
          find.named('xsheet-column-${_draw.value}-cells'),
        )
        .width;
    final view = _viewOf(tester, _columnsScroll(tester));
    expect(
      tester.getRect(_graph('xsheet', _draw)).width,
      moreOrLessEquals(view.width - column),
    );
    expect(
      tester
          .getRect(
            find.named('xsheet-column-${_side.value}-position'),
          )
          .width,
      moreOrLessEquals(laneGraphFoldedExtent),
    );
    expect(_graph('xsheet', _more), findsNothing);
    expect(
      tester.getRect(_label('xsheet', _more, 'anchor-point')).width,
      moreOrLessEquals(laneGraphFoldedExtent),
      reason: 'another graph: ONE strip, its first lane\'s header',
    );
    expect(
      _label('xsheet', _more, 'position'),
      findsNothing,
      reason: 'a row of no extent builds no header',
    );
  });
}

/// Top to bottom: another open graph, a shut group, and the graph that is
/// enlarged — every row above it in view however thin they fold.
const _more = LayerId('more');
const _side = LayerId('side');
const _draw = LayerId('draw');

String get _transform => transformGroupHeaderLane.laneId;
String _group(LayerId layer) => laneGroupKey(layer, _transform);

/// The groups whose graphs stand enlarged.
Set<String> _enlarged(EditorSessionManager s) => {
  for (final MapEntry(:key, value: graph)
      in s.railView.laneGraphs.value.open.entries)
    if (graph.enlarged) key,
};

Finder _graph(String grid, LayerId layer) =>
    find.byKey(ValueKey<String>('$grid-lane-graph-${_group(layer)}'));

Finder _enlarge(String grid, LayerId layer) =>
    find.byKey(ValueKey<String>('$grid-lane-graph-enlarge-${_group(layer)}'));

Finder _graphButton(LayerId layer) =>
    find.named('timeline-lane-group-graph-${layer.value}-$_transform');

Finder _label(String grid, LayerId layer, String lane) =>
    find.byKey(ValueKey<String>('$grid-lane-label-${layer.value}-$lane'));

Finder _cells(LayerId layer) => find.named('timeline-row-${layer.value}-cells');

AppIconButtonFace _face(WidgetTester tester, LayerId layer) =>
    tester.widget<AppIconButtonFace>(_enlarge('timeline', layer));

/// A row's extent on the timeline, read off a layer row's cells.
double _rowExtent(WidgetTester tester) =>
    tester.getRect(_cells(_more)).height;

/// A press on [layer]'s graph grip where the view shows it — a mouse, as
/// on the desk.
Future<TestGesture> _grab(WidgetTester tester, LayerId layer) async {
  final finder = find.byKey(
    ValueKey<String>('timeline-lane-graph-grip-${_group(layer)}'),
  );
  await _reach(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final grip = tester.getRect(finder);
  final view = tester.getRect(
    find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
  );
  final gesture = await tester.startGesture(
    Offset(view.left + 40, grip.center.dy),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  return gesture;
}

/// The timeline's rows' scroll — along the layers.
ScrollPosition _rowsScroll(WidgetTester tester) => tester
    .stateList<ScrollableState>(
      find.ancestor(
        of: find.byKey(
          const ValueKey<String>('timeline-frame-rows-scroll-body'),
        ),
        matching: find.byType(Scrollable),
      ),
    )
    .firstWhere((scroll) => scroll.position.axis == Axis.vertical)
    .position;

/// The sheet's columns' scroll — along the layers.
ScrollPosition _columnsScroll(WidgetTester tester) => tester
    .stateList<ScrollableState>(
      find.ancestor(
        of: find.named('xsheet-column-${_draw.value}-cells'),
        matching: find.byType(Scrollable),
      ),
    )
    .firstWhere((scroll) => scroll.position.axis == Axis.horizontal)
    .position;

/// Where the scroll [position] stands on the screen.
Rect _viewOf(WidgetTester tester, ScrollPosition position) {
  final box =
      position.context.notificationContext!.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Every layer's lanes and Transform group twirled open, and the graphs of
/// [_more] and [_draw] with them.
Future<void> _openEverything(WidgetTester tester) async {
  for (final layer in [_more, _side, _draw]) {
    await _tap(tester, 'timeline-lane-toggle-${layer.value}');
    await _tap(tester, 'timeline-lane-group-toggle-${layer.value}-$_transform');
  }
  for (final layer in [_more, _draw]) {
    await _tap(tester, _graphButton(layer));
  }
}

/// [button] pressed where the view shows it, and the rows back at their
/// start after — where every row above the enlarged graph stands in view,
/// however thin it folds.
Future<void> _tap(WidgetTester tester, Object button) async {
  final finder = button is Finder ? button : find.named(button as String);
  await _reach(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  _layersScroll(tester)?.jumpTo(0);
  await tester.pumpAndSettle();
}

/// The rows walked down until [finder] is built — a row out of the window
/// is not.
Future<void> _reach(WidgetTester tester, Finder finder) async {
  final scroll = _layersScroll(tester);
  while (finder.evaluate().isEmpty &&
      scroll != null &&
      scroll.pixels < scroll.maxScrollExtent) {
    scroll.jumpTo(scroll.pixels + 100);
    await tester.pumpAndSettle();
  }
}

/// The scroll along the layers of whichever grid is up — null before
/// either is.
ScrollPosition? _layersScroll(WidgetTester tester) {
  if (find
      .byKey(const ValueKey<String>('timeline-frame-rows-scroll-body'))
      .evaluate()
      .isNotEmpty) {
    return _rowsScroll(tester);
  }
  if (find
      .named('xsheet-column-${_draw.value}-cells')
      .evaluate()
      .isNotEmpty) {
    return _columnsScroll(tester);
  }
  return null;
}

/// The timeline tab alone ([pumpTimelineHost]), as the app's window of 1400 ×
/// 1200 laid it — the graph's view is the panel's. [tall]: as one twice as
/// tall did, room for the sheet, which stands the rail up as its header.
Future<EditorSessionManager> _pump(
  WidgetTester tester, {
  bool tall = false,
}) => pumpTimelineHost(
  tester,
  _project(),
  surface: Size(870, tall ? 610 : 546),
);

/// The app, its dock pulled up for room — where the panel is resized by the
/// hand.
Future<EditorSessionManager> _pumpApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project())),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -520),
  );
  await tester.pumpAndSettle();
  return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
}

Layer _keyed(LayerId id) => Layer(
  id: id,
  name: id.value,
  frames: const [],
  transformTrack: TransformTrack.empty().copyWith(
    position: PropertyTrack<CanvasPoint>()
        .withKey(0, CanvasPoint(x: 100, y: 50))
        .withKey(8, CanvasPoint(x: 180, y: 10)),
  ),
);

Project _project() => Project(
  id: const ProjectId('graph-enlarge'),
  name: 'Graph Enlarge',
  createdAt: DateTime.utc(2026, 10, 11),
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
          // The list runs bottom up.
          layers: [_keyed(_draw), _keyed(_side), _keyed(_more)],
        ),
      ],
    ),
  ],
);
