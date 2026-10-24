import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
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
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show
        layerGraphSlotWidth,
        layerLaneToggleSlotWidth,
        layerRailColumnWidthsAtOne;
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart'
    show noOptionalRailColumns;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/rail_column_swipe.dart'
    show railSwipeColumns;
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';

/// **I-89 ③ — a header graph turns from its own button, and from no other.**
///
/// 🗣️유저 2026-10-10: 「그래프누르면 해당 fx에서만 작동하도록」 · 「그래프를
/// 누른 레일만 상태변경」 — the button sits on each group's header and on the
/// camera row (㉙), never on a toolbar. What a press DOES is the session's
/// and is pinned there (`a_linked_row_folds_as_one_test`); this is the rail
/// handing each button the key of the group it heads, at the end of its
/// row's name, on both grids.
void main() {
  // The claim set is global: a sweep's pointer left claimed would read the
  // next case's press as already handled.
  tearDown(debugClearValueControlPointers);

  testWidgets('a header\'s button turns ITS group\'s graph — the Transform '
      'header Transform\'s, the effect header the effect\'s', (tester) async {
    final s = await _pump(tester);
    await _openLanes(tester, _drawId);
    expect(_graphs(s), isEmpty, reason: '⛔전제');

    await _tap(tester, _headerGraph('timeline', _transform));
    expect(_graphs(s), [laneGroupKey(_drawId, _transform)]);
    expect(_isOn(tester, _headerGraph('timeline', _transform)), isTrue);
    expect(
      _isOn(tester, _headerGraph('timeline', _blur)),
      isFalse,
      reason: 'the other group\'s button reads its own group',
    );

    await _tap(tester, _headerGraph('timeline', _blur));
    expect(_graphs(s).toSet(), {
      laneGroupKey(_drawId, _transform),
      laneGroupKey(_drawId, _blur),
    });
  });

  testWidgets('the CAMERA row carries the button — its group is the row '
      '(㉙) — and a drawing row does not: its groups\' headers do', (
    tester,
  ) async {
    final s = await _pump(tester);
    expect(
      find.named('timeline-layer-graph-draw'),
      findsNothing,
    );

    await _tap(tester, 'timeline-layer-graph-cam');

    expect(_graphs(s), [laneGroupKey(_camId, _transform)]);
    expect(_isOn(tester, 'timeline-layer-graph-cam'), isTrue);
  });

  testWidgets('a header\'s button ends its name, where a layer row\'s name '
      'ends; the camera row\'s ends its own — it folds nothing — the path '
      'button before it — and no legend heads a graph', (tester) async {
    await _pump(tester);
    await _openLanes(tester, _drawId);

    Rect rectOf(String key) =>
        tester.getRect(find.byKey(ValueKey<String>(key)));
    Rect rectNamed(String name) => tester.getRect(find.named(name));
    final cameraRow = rectNamed('timeline-layer-row-cam');
    final cameraName = rectNamed('timeline-layer-name-cam');
    final camera = rectNamed('timeline-layer-graph-cam');
    final header = rectNamed(_headerGraph('timeline', _transform));

    // 유저 2026-10-12: 「추가로 공간 만드는게아니라 이름공간을 줄여서
    // 오른쪽정렬로」 — out of the name, at its end. [twirl][name][graph]
    // [reset][fx] — the mock's header.
    expect(
      rectOf('timeline-lane-label-draw-$_transform').right - header.right,
      moreOrLessEquals(cameraRow.right - cameraName.right, epsilon: 0.5),
      reason: 'a header\'s ends its name where a layer row\'s name ends',
    );
    // 🗣️F-454 (유저 2026-10-23): 「카메라 레이어는 현재 어태치레이어
    // 존재안하니 … 그 자리에 그래프버튼,그왼쪽에 경로버튼」.
    expect(
      camera.right,
      moreOrLessEquals(cameraName.right, epsilon: 0.5),
      reason: 'a row that folds nothing ends its name with its own last '
          'button. ↩️It stood a fold slot short (F-29)',
    );
    expect(
      camera.right,
      moreOrLessEquals(header.right, epsilon: 0.5),
      reason: 'so the camera\'s button stands where a header\'s does',
    );
    expect(
      rectNamed('timeline-layer-camera-path-cam').right,
      moreOrLessEquals(camera.left, epsilon: 0.5),
    );
    expect(
      find.byKey(const ValueKey<String>('legend-layer')),
      findsOneWidget,
      reason: 'LIVENESS: the legend is up',
    );
    expect(
      find.byKey(const ValueKey<String>('legend-graph')),
      findsNothing,
      reason: '「레전드에 있는 그래프버튼 삭제」',
    );
  });

  testWidgets('a swipe from one header\'s button turns the next header\'s '
      'on too — read LIVE, a build before the grid hears of the press — '
      'and passes the lanes between, which head none', (tester) async {
    final s = await _pump(tester);
    await _openLanes(tester, _drawId);
    await _tap(tester, 'timeline-lane-group-toggle-draw-$_blur');
    final from = find.named(_headerGraph('timeline', _transform));
    final to = find.named(_headerGraph('timeline', _blur));
    final rowHeight = tester
        .getRect(
          find.byKey(
            ValueKey<String>('timeline-lane-label-draw-$_transform'),
          ),
        )
        .height;
    // UP, from Transform to the effect above it: the press opens its own
    // group BELOW it, so the rows the sweep goes on to stay where they
    // were.
    final rows =
        ((tester.getCenter(from).dy - tester.getCenter(to).dy) / rowHeight)
            .round();
    expect(rows, 3, reason: '⛔전제: the effect\'s two lanes lie between');

    // ⛔No frame between the press and the first step: the sweep starts
    // from what the button did on the down, before the grid rebuilds.
    final gesture = await tester.startGesture(
      tester.getCenter(from),
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 1; step <= rows; step += 1) {
      await gesture.moveBy(Offset(0, -rowHeight));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_graphs(s).toSet(), {
      laneGroupKey(_drawId, _transform),
      laneGroupKey(_drawId, _blur),
    });
  });

  testWidgets('a swipe from the camera row\'s button sweeps the column too — '
      'from either edge of it — and from past it, nothing', (tester) async {
    // No effect: the Transform header is the one header under the camera
    // row, and the panel is tall enough to keep it in view while the
    // camera's group opens above it.
    final s = await _pump(tester, blur: false, height: 610);
    await _openLanes(tester, _drawId);

    await _sweepFromTheCamerasGraph(tester, (button) => button.left + 1);
    expect(_graphs(s).toSet(), _bothTransforms);
    await _sweepFromTheCamerasGraph(tester, (button) => button.right - 1);
    expect(_graphs(s), isEmpty);

    // ⛔Not from past its far edge: the column is the button's slot.
    await _sweepFromTheCamerasGraph(tester, (button) => button.right + 2);
    expect(_graphs(s), isEmpty);
  });

  // 🗣️F-454 (유저 2026-10-23): 「카메라 레이어는 현재 어태치레이어
  // 존재안하니(나중에 추가될 가능성) 그 자리에 그래프버튼,그왼쪽에 경로버튼」
  // — and once it has one, the fold takes the far end, as on every row.
  testWidgets('a camera row that FOLDS ends its name with the twirl, the '
      'graph and the path before it — and the sweep starts from where its '
      'graph stands', (tester) async {
    final s = await _pump(
      tester,
      blur: false,
      height: 610,
      cameraFolds: true,
    );
    await _openLanes(tester, _drawId);
    Rect rectNamed(String name) => tester.getRect(find.named(name));
    final twirl = rectNamed('timeline-attach-twirl-cam');
    final graph = rectNamed('timeline-layer-graph-cam');

    expect(
      twirl.right,
      moreOrLessEquals(
        rectNamed('timeline-layer-name-cam').right,
        epsilon: 0.5,
      ),
    );
    expect(graph.right, moreOrLessEquals(twirl.left, epsilon: 0.5));
    expect(
      rectNamed('timeline-layer-camera-path-cam').right,
      moreOrLessEquals(graph.left, epsilon: 0.5),
    );

    await _sweepFromTheCamerasGraph(tester, (button) => button.left + 1);
    expect(
      _graphs(s).toSet(),
      _bothTransforms,
      reason: 'the column a twirl further in, where this row lays it',
    );
  });

  test('the button\'s band is its slot to the pixel, each row\'s own way '
      'short of the trailing run — not one either side', () {
    // Through the pointer a band a little too wide cannot be seen: the name
    // before it and the fold twirl after it claim their own presses. The
    // band is asked here instead, where it is made, as the lane pin's is.
    final columns = railSwipeColumns<int>(
      crossExtent: 400,
      leadingOrigin: 0,
      columns: layerRailColumnWidthsAtOne,
      optionalColumns: noOptionalRailColumns,
      graph: (
        toggle: (valueOf: (_) => false, toggle: (_) {}),
        after: (row) => row * layerLaneToggleSlotWidth,
      ),
    );
    final header = columns.single.bandAt(0);
    final layerRow = columns.single.bandAt(1);
    expect(header.end - header.start, layerGraphSlotWidth);
    expect(layerRow.end - layerRow.start, layerGraphSlotWidth);
    expect(layerRow.end, header.end - layerLaneToggleSlotWidth);
  });

  testWidgets('the X-sheet\'s stood-up headers carry the same buttons', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _openLanes(tester, _drawId);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();

    await _tap(tester, _headerGraph('xsheet', _transform));
    await _tap(tester, 'xsheet-layer-graph-cam');

    expect(_graphs(s).toSet(), {
      laneGroupKey(_drawId, _transform),
      laneGroupKey(_camId, _transform),
    });
    expect(
      find.byType(TimelineLayerControlsHeader),
      findsOneWidget,
      reason: 'LIVENESS: the sheet\'s corner is up',
    );
    expect(
      find.byKey(const ValueKey<String>('legend-graph')),
      findsNothing,
      reason: 'and heads no graph: the button is a row\'s own',
    );
  });
}

const _drawId = LayerId('draw');
const _camId = LayerId('cam');
const _blurId = EffectId('blur');

String get _transform => transformGroupHeaderLane.laneId;
String get _blur => effectGroupLaneId(_blurId);

String _headerGraph(String grid, String laneId) =>
    '$grid-lane-group-graph-draw-$laneId';

/// Both Transform graphs, the camera's and the drawing's.
final _bothTransforms = {
  laneGroupKey(_camId, _transform),
  laneGroupKey(_drawId, _transform),
};

/// From [across] on the camera row's graph button DOWN to the Transform
/// header, a row at a time, the header read again at each step: a press
/// opens what it opens below its row — the camera's group with its graph
/// (㉙) — and every row under it moves.
Future<void> _sweepFromTheCamerasGraph(
  WidgetTester tester,
  double Function(Rect button) across,
) async {
  final header = find.named(_headerGraph('timeline', _transform));
  final rowHeight = tester
      .getRect(find.named('timeline-layer-row-cam'))
      .height;
  final button = tester.getRect(find.named('timeline-layer-graph-cam'));
  expect(
    button.center.dy,
    lessThan(tester.getCenter(header).dy),
    reason: '⛔전제: the camera row stands above the headers',
  );
  var at = Offset(across(button), button.center.dy);
  final gesture = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
  for (var step = 0; step < 40; step += 1) {
    final gap = tester.getCenter(header).dy - at.dy;
    if (gap.abs() < rowHeight / 2) {
      break;
    }
    final move = Offset(0, gap.clamp(-rowHeight, rowHeight));
    await gesture.moveBy(move);
    at += move;
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// [cameraFolds]: a row rides the camera, so the camera row folds it.
Project _project({bool blur = true, bool cameraFolds = false}) => Project(
  id: const ProjectId('header-graph'),
  name: 'Header Graph',
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
          camera: CutCamera.empty(),
          layers: [
            Layer(
              id: _drawId,
              name: 'Drawing',
              frames: const [],
              effects: [
                if (blur) LayerEffect(id: _blurId, kind: EffectKind.blur),
              ],
            ),
            if (cameraFolds)
              Layer(
                id: const LayerId('rider'),
                name: 'Rider',
                frames: const [],
                attachedToLayerId: _camId,
                attachedPlacement: AttachedPlacement.below,
                attachedMode: AttachedMode.free,
              ),
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

/// The timeline tab alone ([pumpTimelineHost]), [height] tall — the graph
/// and its button are the panel's. The app's window of 1400 × 1200 laid it
/// 870 × 546.
Future<EditorSessionManager> _pump(
  WidgetTester tester, {
  bool blur = true,
  double height = 546,
  bool cameraFolds = false,
}) => pumpTimelineHost(
  tester,
  _project(blur: blur, cameraFolds: cameraFolds),
  surface: Size(870, height),
);

Future<void> _openLanes(WidgetTester tester, LayerId id) =>
    _tap(tester, 'timeline-lane-toggle-${id.value}');

Future<void> _tap(WidgetTester tester, String name) async {
  final button = find.named(name);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

List<String> _graphs(EditorSessionManager s) =>
    s.railView.laneGraphs.value.open.keys.toList();

bool _isOn(WidgetTester tester, String name) =>
    tester.appIconButton(find.named(name)).isSelected;
