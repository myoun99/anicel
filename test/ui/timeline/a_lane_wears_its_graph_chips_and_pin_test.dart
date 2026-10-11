import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/key_mark.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart'
    show VerticalWritingText;
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/theme/lane_curve_palette.dart';
import 'package:anicel/src/ui/timeline/lane_graph.dart';
import 'package:anicel/src/ui/timeline/lane_graph_seats.dart' show lanePinOf;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerLanePinSlotWidth, layerRailColumnWidthsAtOne;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/rail_column_swipe.dart'
    show railSwipeColumns;
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart'
    show timelineFrameCellWidth;
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

import '../../helpers/app_icon_button_probe.dart';

/// **I-89 ③ — a lane on a rail that carries header graphs: its curve's
/// chips before its name, its pin before its value.**
///
/// The mock (5판): a seated lane wears its curve's colours while its graph
/// draws it, and its name fades while it does not; every lane with a curve
/// wears a pin, AE's graph editor set. ⛔없다가 생기는 UI 금지 — the two
/// slots are kept on every lane, so nothing moves when they fill.
void main() {
  tearDown(debugClearValueControlPointers);

  test('a lane wears a pin when it draws a curve, and no other row does', () {
    final layer = Layer(id: _drawId, name: 'Drawing', frames: const []);
    PropertyLaneRow lane(String laneId, {required bool curve}) =>
        PropertyLaneRow(
          laneId: laneId,
          label: laneId,
          keyMarks: const {},
          curve: curve
              ? (
                  parts: const [LaneCurvePalette.across],
                  at: (_) => const [0.0],
                )
              : null,
        );
    expect(
      lanePinOf(layer, lane('rotation', curve: true)),
      laneGroupKey(_drawId, 'rotation'),
    );
    expect(lanePinOf(layer, lane('blend', curve: false)), isNull);
    expect(lanePinOf(layer, null), isNull, reason: 'the layer\'s own row');
  });

  testWidgets('the pin stands in one column whether a chain stands before '
      'it or not', (tester) async {
    await _pump(tester);
    await _openTransform(tester);
    expect(
      find.byKey(const ValueKey<String>('timeline-lane-value-link-draw-scale')),
      findsOneWidget,
      reason: '⛔전제: Scale wears its chain',
    );

    double insetOf(String laneId) =>
        tester.getTopRight(_cell('timeline', laneId)).dx -
        tester.getCenter(find.byKey(ValueKey(_pin('timeline', laneId)))).dx;
    expect(insetOf('scale'), moreOrLessEquals(insetOf('position')));
    expect(insetOf('rotation'), moreOrLessEquals(insetOf('position')));
  });

  testWidgets('a seated lane wears its chips while its graph draws it and '
      'fades while it does not — its name stays where it stood', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _openTransform(tester);
    final before = tester.getTopLeft(_name(tester, 'position')).dx;

    await _tap(tester, 'timeline-lane-group-graph-draw-$_transform');
    s.standOnRow(const LaneRowAddress(_drawId, 'position'));
    s.rowSelection.value = const [];
    await tester.pumpAndSettle();

    expect(_chips(tester, 'position'), 2, reason: 'across and down');
    expect(_chips(tester, 'scale'), 0);
    expect(
      _alpha(tester, 'scale') / _alpha(tester, 'position'),
      moreOrLessEquals(AppColors.offAlpha, epsilon: 0.01),
    );
    expect(tester.getTopLeft(_name(tester, 'position')).dx, before);

    // The selection, where it holds the group's lanes, wins over standing.
    s.rowSelection.value = const [
      LaneRowAddress(_drawId, 'scale'),
      LaneRowAddress(_drawId, 'rotation'),
    ];
    await tester.pumpAndSettle();
    expect(_chips(tester, 'position'), 0);
    expect(_chips(tester, 'scale'), 2);
    expect(_chips(tester, 'rotation'), 1);

    // And a pinned lane is drawn besides.
    await _tap(tester, _pin('timeline', 'opacity'));
    expect(_chips(tester, 'opacity'), 1);
  });

  testWidgets('a lane\'s pin pins it to every graph — and a swipe from it '
      'pins the lanes it crosses', (tester) async {
    final s = await _pump(tester);
    await _openTransform(tester);

    await _tap(tester, _pin('timeline', 'position'));
    expect(_pinned(s), {laneGroupKey(_drawId, 'position')});
    expect(
      tester
          .appIconButton(find.byKey(ValueKey(_pin('timeline', 'position'))))
          .isSelected,
      isTrue,
    );
    await _tap(tester, _pin('timeline', 'position'));
    expect(_pinned(s), isEmpty);

    final from = tester.getCenter(
      find.byKey(ValueKey(_pin('timeline', 'position'))),
    );
    final rowHeight = tester.getRect(_cell('timeline', 'position')).height;
    // ⛔No frame between the press and the first step — the pin is read
    // live, as the graph's button is.
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 1; step <= 2; step += 1) {
      await gesture.moveBy(Offset(0, rowHeight));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_pinned(s), {
      for (final lane in ['position', 'scale', 'rotation'])
        laneGroupKey(_drawId, lane),
    });
  });

  testWidgets('the pin\'s sweep band is its own slot, edge to edge', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _openTransform(tester);
    final pin = tester.getRect(
      find.byKey(ValueKey(_pin('timeline', 'position'))),
    );
    final rowHeight = tester.getRect(_cell('timeline', 'position')).height;

    Future<void> sweepFrom(double x) async {
      final gesture = await tester.startGesture(
        Offset(x, pin.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(Offset(0, rowHeight));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await sweepFrom(pin.left + 1);
    expect(_pinned(s), {
      laneGroupKey(_drawId, 'position'),
      laneGroupKey(_drawId, 'scale'),
    }, reason: 'from the edge the name stands at');
    await sweepFrom(pin.right - 1);
    expect(_pinned(s), isEmpty, reason: 'from the edge the value stands at');

    // ⛔And no slack past either edge: the name a press stands on is before
    // it, and the gap before the value after. Each read on its own — two
    // sweeps that both pinned would toggle each other back to nothing.
    await sweepFrom(pin.left - 2);
    expect(_pinned(s), isEmpty, reason: 'not from the name before it');
    await sweepFrom(pin.right + 2);
    expect(_pinned(s), isEmpty, reason: 'nor from the gap after it');
  });

  test('the pin\'s band is its slot to the pixel — not one either side', () {
    // Through the pointer a band a little too wide cannot be seen: the name
    // before it and the value after it claim their own presses. The band is
    // asked here instead, where it is made.
    final columns = railSwipeColumns<int>(
      crossExtent: 300,
      leadingOrigin: 0,
      columns: layerRailColumnWidthsAtOne,
      optionalColumns: (graph: true, onion: false, blend: false),
      lanePin: (toggle: (valueOf: (_) => false, toggle: (_) {}), inset: 40),
    );
    expect(columns.single.bandAt(0), (
      start: 260 - layerLanePinSlotWidth,
      end: 260.0,
    ));
  });

  testWidgets('the sheet\'s lane columns wear the pin, swept across them as '
      'down the rail', (tester) async {
    final s = await _pump(tester);
    await _openTransform(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
    final position = find.byKey(ValueKey(_pin('xsheet', 'position')));
    await tester.ensureVisible(position);
    await tester.pumpAndSettle();
    final from = tester.getCenter(position);
    final step =
        tester.getCenter(find.byKey(ValueKey(_pin('xsheet', 'scale')))) - from;
    expect(step.dy, moreOrLessEquals(0), reason: '⛔전제: one row of pins');

    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(step);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_pinned(s), {
      laneGroupKey(_drawId, 'position'),
      laneGroupKey(_drawId, 'scale'),
    });
  });

  testWidgets('the sheet\'s lane columns wear their chips as the rail\'s '
      'rows do, and the pin\'s band is its slot there too', (tester) async {
    final s = await _pump(tester);
    await _openTransform(tester);
    await _tap(tester, 'timeline-lane-group-graph-draw-$_transform');
    s.standOnRow(const LaneRowAddress(_drawId, 'position'));
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
    final position = find.byKey(ValueKey(_pin('xsheet', 'position')));
    await tester.ensureVisible(position);
    await tester.pumpAndSettle();

    expect(_chips(tester, 'position', grid: 'xsheet'), 2);
    expect(_chips(tester, 'scale', grid: 'xsheet'), 0);

    final pin = tester.getRect(position);
    final step =
        tester.getCenter(find.byKey(ValueKey(_pin('xsheet', 'scale')))).dx -
        pin.center.dx;
    Future<void> sweepFrom(double y) async {
      final gesture = await tester.startGesture(
        Offset(pin.center.dx, y),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(Offset(step, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await sweepFrom(pin.top + 1);
    expect(_pinned(s), {
      laneGroupKey(_drawId, 'position'),
      laneGroupKey(_drawId, 'scale'),
    });
    await sweepFrom(pin.bottom - 1);
    expect(_pinned(s), isEmpty);
  });

  testWidgets('a stood-up column pays its pin and chips LAST — carrying them '
      'sheds nothing it showed before they came', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final layer = Layer(id: _drawId, name: 'Drawing', frames: const []);
    // Scale: a value, a navigator and a chain — every control the column
    // paid before the graph's came.
    final lane = PropertyLaneRow(
      laneId: 'scale',
      label: 'Scale',
      keyMarks: const {0: KeyMark.linear},
      valueLabel: (_) => '100.0, 100.0',
      linkable: true,
      curve: (
        parts: const [LaneCurvePalette.across, LaneCurvePalette.down],
        at: (_) => const [100.0, 100.0],
      ),
    );
    final changes = ValueNotifier<int>(0);
    addTearDown(changes.dispose);
    final edit = PropertyLaneEditCallbacks(
      onToggleKeyAt: (_, _, _) {},
      valueLink: (changes: changes, isOn: () => true, toggle: () {}),
    );
    final seat = TimelineGraphSeat(
      groupKey: laneGroupKey(_drawId, _transform),
      graph: const LaneGraph(),
      lanes: const ['scale'],
      picked: const [],
      pinned: const [],
    );

    const value = 'xsheet-lane-value-draw-scale';
    const navigator = 'xsheet-lane-key-toggle-draw-scale';
    const link = 'xsheet-lane-value-link-draw-scale';
    const pin = 'xsheet-lane-pin-draw-scale';
    const chip = 'xsheet-lane-chip-draw-scale-0';
    const keys = [value, navigator, link, pin, chip];

    /// The least room the name got at any height.
    var leastName = double.infinity;

    /// Each control that showed in a column and was gone from a taller one —
    /// all but the navigator. ⚠️The navigator is asked of the value SHOWING
    /// (the gate pays the value first, 2026-08-08): since the value turned,
    /// as long as the rail's value cell is wide (10-11), it stands in a
    /// column too short for the value and makes way when the value comes —
    /// reported on the card of the round that turned it (board:
    /// tool-settings-panel-tidy).
    final wentAgain = <String>[];

    /// The shortest column, from 60 up, that shows each of [keys].
    Future<Map<String, double?>> firstShown({required bool graphs}) async {
      final first = <String, double?>{for (final key in keys) key: null};
      for (var height = 60.0; height <= 480; height += 1) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: TimelineLaneControlsRow(
                  axis: Axis.vertical,
                  keyPrefix: 'xsheet',
                  layer: layer,
                  lane: lane,
                  laneEdit: edit,
                  metrics: XSheetTimelineGrid.defaultMetrics,
                  width: XSheetTimelineGrid.defaultMetrics.layerRowHeight,
                  height: height,
                  optionalColumns: (graph: graphs, onion: false, blend: false),
                  laneGraphVerbs: (
                    toggle: (_) {},
                    togglePin: (_) {},
                    plot: (_, _) {},
                    resize: (_, _) {},
                  ),
                  seat: graphs ? seat : null,
                ),
              ),
            ),
          ),
        );
        for (final key in keys) {
          final shown = find.byKey(ValueKey<String>(key)).evaluate();
          if (first[key] == null && shown.isNotEmpty) {
            first[key] = height;
          } else if (key != navigator && first[key] != null && shown.isEmpty) {
            wentAgain.add('$key at $height${graphs ? ', graphs' : ''}');
          }
        }
        leastName = math.min(
          leastName,
          tester
              .getSize(
                find.descendant(
                  of: _cell('xsheet', 'scale'),
                  matching: find.byType(VerticalWritingText),
                ),
              )
              .height,
        );
      }
      return first;
    }

    final without = await firstShown(graphs: false);
    final carried = await firstShown(graphs: true);

    expect(
      leastName,
      greaterThanOrEqualTo(2 * timelineFrameCellWidth),
      reason: 'the name is paid first: whatever else stands, it keeps its '
          'floor of two frame rows',
    );
    expect(
      wentAgain,
      isEmpty,
      reason: 'what a column grew to show stays as it grows on',
    );
    expect(without[pin], isNull);
    expect(without[chip], isNull);
    for (final key in [value, navigator, link]) {
      expect(carried[key], without[key], reason: key);
    }
    expect(carried[link], greaterThan(carried[navigator]!));
    expect(carried[pin], greaterThan(carried[link]!));
    expect(carried[chip], greaterThan(carried[pin]!));
  });
}

const _drawId = LayerId('draw');

String get _transform => transformGroupHeaderLane.laneId;

String _pin(String grid, String laneId) => '$grid-lane-pin-draw-$laneId';

Finder _cell(String grid, String laneId) =>
    find.byKey(ValueKey<String>('$grid-lane-label-draw-$laneId'));

/// The lane's name, as its row prints it.
Finder _name(WidgetTester tester, String laneId) {
  final cell = _cell('timeline', laneId);
  final row = tester.widget<TimelineLaneControlsRow>(
    find.ancestor(of: cell, matching: find.byType(TimelineLaneControlsRow)),
  );
  return find.descendant(of: cell, matching: find.text(row.lane.label));
}

double _alpha(WidgetTester tester, String laneId) =>
    tester.widget<Text>(_name(tester, laneId)).style!.color!.a;

int _chips(
  WidgetTester tester,
  String laneId, {
  String grid = 'timeline',
}) => [
  for (var part = 0; part < 2; part += 1)
    ...find
        .byKey(ValueKey<String>('$grid-lane-chip-draw-$laneId-$part'))
        .evaluate(),
].length;

Set<String> _pinned(EditorSessionManager s) =>
    s.railView.laneGraphs.value.pinned;

Project _project() => Project(
  id: const ProjectId('lane-pins'),
  name: 'Lane Pins',
  createdAt: DateTime.utc(2026, 10, 11),
  tracks: [
    Track(
      id: const TrackId('t'),
      name: 'V',
      cuts: [
        Cut(
          id: const CutId('c'),
          name: 'C',
          duration: 12,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: [Layer(id: _drawId, name: 'Drawing', frames: const [])],
        ),
      ],
    ),
  ],
);

Future<EditorSessionManager> _pump(WidgetTester tester) async {
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
