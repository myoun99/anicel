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
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

import '../../helpers/named_finders.dart';

const _drawId = LayerId('draw');

String get _transformGroup =>
    laneGroupKey(_drawId, transformGroupHeaderLane.laneId);

/// 🗣️F-514 (유저 2026-10-30): 「fx 그래프 조절하려고 선택범위 작동시 프레임
/// 칸에 선택범위가 작동해버림. 스샷참고. 이건 발생안하는게 의도라고 생각함.
/// 맞나? 잘 모르니 맡김」 — a graph's picks are a lane selection, as the
/// user settled (I-3-Q3), and the graph shows them itself: no band is laid
/// over it, where it draws no cells.
void main() {
  final band = find.byKey(
    const ValueKey<String>('timeline-lane-range-selection'),
  );

  Future<void> pick(WidgetTester tester, EditorSessionManager s) async {
    s.updateLaneRangeSelectionDrag(
      layerId: _drawId,
      laneId: 'rotation',
      anchorIndex: 2,
      headIndex: 9,
      spanLaneIds: const ['rotation'],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('🎯what is picked in an open graph lays no band over it, and '
      'stands picked', (tester) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);

    await pick(tester, s);

    expect(band, findsNothing);
    expect(s.laneRangeSelection.value?.spanLaneIds, contains('rotation'));
  });

  testWidgets('with the graph shut, the same lanes wear their band', (
    tester,
  ) async {
    final s = await _pump(tester);
    await _openTheGraph(tester, s);
    await pick(tester, s);

    await _tapNamed(
      tester,
      'timeline-lane-group-graph-draw-${transformGroupHeaderLane.laneId}',
    );

    expect(band, findsOneWidget);
  });
}

Future<void> _openTheGraph(
  WidgetTester tester,
  EditorSessionManager s,
) async {
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

Project _project() => Project(
  id: const ProjectId('graph-picks'),
  name: 'Graph picks',
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
                rotation: PropertyTrack<double>().withKey(0, 0).withKey(8, 45),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
