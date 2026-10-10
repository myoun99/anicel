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
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;
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
/// handing each button the key of the group it heads, in one column, on
/// both grids.
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

  testWidgets('the legend, a header and the camera row put the button in '
      'ONE column, left of the reset', (tester) async {
    await _pump(tester);
    await _openLanes(tester, _drawId);

    final legend = find.byKey(const ValueKey<String>('legend-graph'));
    final header = find.byKey(
      ValueKey<String>(_headerGraph('timeline', _transform)),
    );
    final camera = find.byKey(
      const ValueKey<String>('timeline-layer-graph-cam'),
    );
    // From each row's RIGHT edge, as the fx column is measured: the rows do
    // not share a left origin, and the trailing run is anchored right.
    double trailingInsetOf(Finder control, Finder row) =>
        tester.getTopRight(row).dx - tester.getCenter(control).dx;
    final cameraInset = trailingInsetOf(
      camera,
      find.byKey(const ValueKey<String>('timeline-layer-row-cam')),
    );

    expect(
      trailingInsetOf(
        header,
        find.byKey(
          ValueKey<String>('timeline-lane-label-draw-$_transform'),
        ),
      ),
      moreOrLessEquals(cameraInset, epsilon: 0.5),
    );
    expect(
      trailingInsetOf(
        legend,
        find.ancestor(
          of: legend,
          matching: find.byType(TimelineLayerControlsHeader),
        ),
      ),
      moreOrLessEquals(cameraInset, epsilon: 0.5),
      reason: 'the heading stands over its column',
    );
    // [twirl][name][graph][reset][fx] — the mock's header.
    final reset = find.byKey(
      ValueKey<String>('timeline-lane-group-reset-draw-$_transform'),
    );
    expect(
      tester.getCenter(header).dx,
      lessThan(tester.getCenter(reset).dx),
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

    final gesture = await tester.startGesture(
      tester.getCenter(from),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
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
      find.byKey(const ValueKey<String>('legend-graph')),
      findsOneWidget,
      reason: 'the sheet\'s corner heads the column too',
    );
  });

  testWidgets('the storyboard rail carries no graph column yet — its camera '
      'row\'s graph is a later round (I-89 ③)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('legend-layer')),
      findsOneWidget,
      reason: 'LIVENESS: the legend is up',
    );
    expect(find.byKey(const ValueKey<String>('legend-graph')), findsNothing);
  });
}

const _drawId = LayerId('draw');
const _camId = LayerId('cam');
const _blurId = EffectId('blur');

String get _transform => transformGroupHeaderLane.laneId;
String get _blur => effectGroupLaneId(_blurId);

String _headerGraph(String grid, String laneId) =>
    '$grid-lane-group-graph-draw-$laneId';

Project _project() => Project(
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
              effects: [LayerEffect(id: _blurId, kind: EffectKind.blur)],
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
