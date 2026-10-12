import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerLaneToggleSlotWidth;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

import '../../helpers/app_icon_button_probe.dart';

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
      find.byKey(const ValueKey<String>('timeline-layer-graph-draw')),
      findsNothing,
    );

    await _tap(tester, 'timeline-layer-graph-cam');

    expect(_graphs(s), [laneGroupKey(_camId, _transform)]);
    expect(_isOn(tester, 'timeline-layer-graph-cam'), isTrue);
  });

  testWidgets('a header\'s button ends its name, where a layer row\'s name '
      'ends; the camera row\'s ends its own, a fold slot short, the path '
      'button before it — and no legend heads a graph', (tester) async {
    await _pump(tester);
    await _openLanes(tester, _drawId);

    Rect rectOf(String key) =>
        tester.getRect(find.byKey(ValueKey<String>(key)));
    final cameraRow = rectOf('timeline-layer-row-cam');
    final cameraName = rectOf('timeline-layer-name-cam');
    final camera = rectOf('timeline-layer-graph-cam');
    final header = rectOf(_headerGraph('timeline', _transform));

    // 유저 2026-10-12: 「추가로 공간 만드는게아니라 이름공간을 줄여서
    // 오른쪽정렬로」 — out of the name, at its end. [twirl][name][graph]
    // [reset][fx] — the mock's header.
    expect(
      rectOf('timeline-lane-label-draw-$_transform').right - header.right,
      moreOrLessEquals(cameraRow.right - cameraName.right, epsilon: 0.5),
      reason: 'a header\'s ends its name where a layer row\'s name ends',
    );
    expect(
      camera.right,
      moreOrLessEquals(
        cameraName.right - layerLaneToggleSlotWidth,
        epsilon: 0.5,
      ),
      reason: 'a layer row\'s name ends in its fold slot, whatever the row '
          'folds (F-29)',
    );
    expect(
      rectOf('timeline-layer-camera-path-cam').right,
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
    final from = find.byKey(
      ValueKey<String>(_headerGraph('timeline', _transform)),
    );
    final to = find.byKey(ValueKey<String>(_headerGraph('timeline', _blur)));
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
      'from either edge of it, a fold slot further in than a header\'s — '
      'and from the fold slot past it, nothing', (tester) async {
    // No effect: the Transform header is the one header under the camera
    // row, and the window is tall enough to keep it in view while the
    // camera's group opens above it.
    final s = await _pump(tester, blur: false, height: 1600);
    await _openLanes(tester, _drawId);
    final header = find.byKey(
      ValueKey<String>(_headerGraph('timeline', _transform)),
    );
    final rowHeight = tester
        .getRect(find.byKey(const ValueKey<String>('timeline-layer-row-cam')))
        .height;

    /// From [across] on the camera row DOWN to the Transform header, a row
    /// at a time, the header read again at each step: a press opens what
    /// it opens below its row — the camera's group with its graph (㉙) —
    /// and every row under it moves.
    Future<void> sweepFrom(double Function(Rect button) across) async {
      final button = tester.getRect(
        find.byKey(const ValueKey<String>('timeline-layer-graph-cam')),
      );
      expect(
        button.center.dy,
        lessThan(tester.getCenter(header).dy),
        reason: '⛔전제: the camera row stands above the headers',
      );
      var at = Offset(across(button), button.center.dy);
      final gesture = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
      );
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

    final both = {
      laneGroupKey(_camId, _transform),
      laneGroupKey(_drawId, _transform),
    };
    await sweepFrom((button) => button.left + 1);
    expect(_graphs(s).toSet(), both);
    await sweepFrom((button) => button.right - 1);
    expect(_graphs(s), isEmpty);

    // ⛔Not from the fold slot, where a header's button stands a row over:
    // the column is where ITS row lays the button.
    await sweepFrom((button) => button.right + 2);
    expect(_graphs(s), isEmpty);
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

Project _project({bool blur = true}) => Project(
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
  bool blur = true,
  double height = 1200,
}) async {
  await tester.binding.setSurfaceSize(Size(1400, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project(blur: blur))),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -520),
  );
  await tester.pumpAndSettle();
  return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
}

Future<void> _openLanes(WidgetTester tester, LayerId id) =>
    _tap(tester, 'timeline-lane-toggle-${id.value}');

Future<void> _tap(WidgetTester tester, String key) async {
  final button = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

List<String> _graphs(EditorSessionManager s) =>
    s.railView.laneGraphs.value.open.keys.toList();

bool _isOn(WidgetTester tester, String key) =>
    tester.appIconButton(find.byKey(ValueKey<String>(key))).isSelected;
