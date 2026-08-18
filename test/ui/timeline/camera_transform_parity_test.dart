import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/key_range_move.dart'
    show transformKeyHoldUnion;
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineFittedGlyphFontSize;
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart'
    show
        TimelineLaneKeyMarker,
        timelineLaneKeyMarkerSize,
        timelineLaneUnionKeyMarkerSize;
import 'package:anicel/src/ui/timeline/timeline_row_span_resolver.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

import 'timeline_cell_probe.dart';

/// 🚨B4 (2026-08-17, device report): the CAMERA row's timeline interactions
/// are THE SAME CODE as every other transform layer's — not similar, shared.
///
/// ① the union mark stays a DIAMOND through a real drag (it turned into the
///   paper-cell ○ mid-drag, because the summary rode a private text-glyph
///   table whose name channel lagged the preview);
/// ② camera MEMBER lanes move LIVE during a key drag (they were built from
///   the committed cut track instead of the preview-aware channel);
/// ③ the union mark's SIZE is the one shared constant
///   ([timelineLaneUnionKeyMarkerSize]) — camera and fx header alike;
/// ④ a selection anchored on an fx header/member extends OUTSIDE the group
///   freely, like every other anchor (유저, 다섯 번째: 「선택범위는 어떤
///   레이어를 건너든 자유롭게, 규칙 두지 말 것」).
const _drawId = LayerId('parity-draw');
const _camId = LayerId('parity-cam');

CameraPose _pose(double x) =>
    CameraPose(center: CanvasPoint(x: x, y: x), zoom: 1.5);

Project _project({CutCamera? camera, TransformTrack? drawTransform}) {
  return Project(
    id: const ProjectId('parity-project'),
    name: 'Parity Project',
    createdAt: DateTime.utc(2026, 8, 17),
    tracks: [
      Track(
        id: const TrackId('parity-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('parity-cut'),
            name: 'Parity Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            camera: camera ?? CutCamera.empty(),
            layers: [
              Layer(
                id: _drawId,
                name: 'Drawing',
                frames: const [],
                transformTrack: drawTransform,
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
}

Future<void> _pump(WidgetTester tester, Project project) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: HomePage(initialProject: project)));
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -520),
  );
  await tester.pumpAndSettle();
}

Finder _marker(LayerId layerId, String laneId, int frame) => find.byKey(
  ValueKey<String>('timeline-lane-key-${layerId.value}-$laneId-$frame'),
);

Future<void> _toggleLanes(WidgetTester tester, LayerId layerId) async {
  final toggle = find.byKey(
    ValueKey<String>('timeline-lane-toggle-${layerId.value}'),
  );
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

Future<void> _expandTransformGroup(WidgetTester tester, LayerId layerId) async {
  final toggle = find.byKey(
    ValueKey<String>(
      'timeline-lane-group-toggle-${layerId.value}-transform-group',
    ),
  );
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

void main() {
  const rowHeight = timelineLayerRowHeight; // 28 — every timeline row.
  const cellWidth = timelineFrameCellWidth; // 24 — the default zoom.

  group('B4-③ one metric law for every union mark', () {
    test('the union size is derived from the member size — one constant '
        'path, no second literal', () {
      expect(
        timelineLaneKeyMarkerSize(28, frameCellExtent: 24),
        (28 * 0.32).clamp(6.0, 11.0),
      );
      expect(
        timelineLaneUnionKeyMarkerSize(28, frameCellExtent: 24),
        (timelineLaneKeyMarkerSize(28, frameCellExtent: 24) * 1.5).clamp(
          6.0,
          28.0,
        ),
      );
    });

    // D39 (2026-08-18): the marks follow the ZOOM like block text and edge
    // grips do — the cross-derived base runs through the same fit law, so
    // a shrunken cell shrinks its diamond instead of wearing a fixed 13px
    // mark across three neighbours.
    test('D39: the marks shrink with the cell through the one fit law', () {
      // At the default cell nothing changes (the fit's knee is 14).
      expect(
        timelineLaneKeyMarkerSize(28, frameCellExtent: 24),
        timelineLaneKeyMarkerSize(28, frameCellExtent: 999),
      );
      // Below the knee the member follows the fit exactly...
      expect(
        timelineLaneKeyMarkerSize(28, frameCellExtent: 8),
        timelineFittedGlyphFontSize(
          (28 * 0.32).clamp(6.0, 11.0).toDouble(),
          8,
          crossExtent: 28,
        ),
      );
      // ...and the union keeps reading as half again the member (㉗),
      // riding ON the fitted size rather than re-inflating past the cell.
      expect(
        timelineLaneUnionKeyMarkerSize(28, frameCellExtent: 8),
        (timelineLaneKeyMarkerSize(28, frameCellExtent: 8) * 1.5).clamp(
          6.0,
          28.0,
        ),
      );
      expect(
        timelineLaneUnionKeyMarkerSize(28, frameCellExtent: 8),
        lessThan(timelineLaneUnionKeyMarkerSize(28, frameCellExtent: 24)),
      );
    });

    testWidgets('the camera union mark and the fx transform header union '
        'mark are the SAME widget at the SAME size', (tester) async {
      await _pump(
        tester,
        _project(
          camera: CutCamera(keyframes: {0: _pose(0)}),
          drawTransform: TransformTrack(keyframes: {0: _pose(0)}),
        ),
      );
      // The fx header's union shows on the collapsed Transform header once
      // the layer's lanes are twirled open.
      await _toggleLanes(tester, _drawId);

      final cameraMark = tester.widget<TimelineLaneKeyMarker>(
        _marker(_camId, transformGroupHeaderLane.laneId, 0),
      );
      final headerMark = tester.widget<TimelineLaneKeyMarker>(
        _marker(_drawId, transformGroupHeaderLane.laneId, 0),
      );
      expect(cameraMark.markerSize, headerMark.markerSize);
      expect(
        cameraMark.markerSize,
        timelineLaneUnionKeyMarkerSize(
          TimelineGridMetrics.defaults.layerRowHeight,
          frameCellExtent: TimelineGridMetrics.defaults.frameCellWidth,
        ),
      );
      expect(cameraMark.hold, isFalse);
      expect(headerMark.hold, isFalse);
    });

    testWidgets('the all-hold ■ law is ONE law: both union marks read '
        'transformKeyHoldUnion', (tester) async {
      final holdTrack = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(
          4,
          CanvasPoint(x: 1, y: 1),
          interpolation: PropertyKeyInterpolation.hold,
        ),
      );
      await _pump(
        tester,
        _project(
          camera: CutCamera.fromTrack(holdTrack),
          drawTransform: holdTrack,
        ),
      );
      await _toggleLanes(tester, _drawId);

      expect(transformKeyHoldUnion(holdTrack), {4});
      expect(
        tester
            .widget<TimelineLaneKeyMarker>(
              _marker(_camId, transformGroupHeaderLane.laneId, 4),
            )
            .hold,
        isTrue,
      );
      expect(
        tester
            .widget<TimelineLaneKeyMarker>(
              _marker(_drawId, transformGroupHeaderLane.laneId, 4),
            )
            .hold,
        isTrue,
      );
    });
  });

  group('B4-① the union mark stays a diamond through a REAL drag', () {
    testWidgets('camera row: mid-drag the mark is the shared diamond at the '
        'shifted frame — never the paper-cell ○', (tester) async {
      await _pump(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(0), 8: _pose(80)})),
      );

      // SELECT frames 8..9 on the camera row's cells (raw span — no
      // blocks; the drag has to clear the cells row's tap slop, so it
      // travels one cell).
      final cell8 = timelineCellCenter(tester, _camId.value, 8);
      await tester.dragFrom(
        cell8,
        const Offset(26, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      // MOVE: press inside the selection and drag +2 frames, holding the
      // pointer down — the device-reported moment the diamond became a ○.
      final gesture = await tester.startGesture(
        cell8,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(cellWidth, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(cellWidth, 0));
      await tester.pump();

      // MID-DRAG: the union mark rode to frame 10 and it is still the
      // SHARED diamond widget; the text channel never says ○ anywhere.
      expect(_marker(_camId, transformGroupHeaderLane.laneId, 10),
          findsOneWidget);
      expect(_marker(_camId, transformGroupHeaderLane.laneId, 8), findsNothing);
      expect(
        tester
            .widget<TimelineLaneKeyMarker>(
              _marker(_camId, transformGroupHeaderLane.laneId, 10),
            )
            .hold,
        isFalse,
        reason: 'a linear key reads as a diamond mid-drag',
      );
      for (var frame = 0; frame < 12; frame += 1) {
        expect(
          timelineCellModel(tester, _camId.value, frame).glyph,
          '',
          reason: 'frame $frame: the camera row prints no text glyph — the ○ '
              'path is dead',
        );
      }

      await gesture.up();
      await tester.pumpAndSettle();

      // The release commits where the preview promised.
      final session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
      expect(
        session.activeCutOrNull!.camera.track.keyframeAt(10),
        isNotNull,
      );
      expect(_marker(_camId, transformGroupHeaderLane.laneId, 10),
          findsOneWidget);
    });

    testWidgets('fx member lane: mid-drag the key is the same shared diamond '
        'at the shifted frame', (tester) async {
      await _pump(
        tester,
        _project(
          drawTransform: TransformTrack.empty().copyWith(
            position: PropertyTrack<CanvasPoint>()
                .withKey(0, CanvasPoint(x: 0, y: 0))
                .withKey(8, CanvasPoint(x: 9, y: 9)),
          ),
        ),
      );
      await _toggleLanes(tester, _drawId);
      await _expandTransformGroup(tester, _drawId);

      final key8 = tester.getCenter(_marker(_drawId, 'position', 8));
      await tester.dragFrom(
        key8,
        const Offset(4, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        key8,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(cellWidth, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(cellWidth, 0));
      await tester.pump();

      expect(_marker(_drawId, 'position', 10), findsOneWidget);
      expect(_marker(_drawId, 'position', 8), findsNothing);
      expect(
        tester
            .widget<TimelineLaneKeyMarker>(_marker(_drawId, 'position', 10))
            .hold,
        isFalse,
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(_marker(_drawId, 'position', 10), findsOneWidget);
    });
  });

  group('B4-② camera member lanes move LIVE during a key drag', () {
    testWidgets('the position lane\'s diamond follows the drag per step, '
        'pointer still down — and the row\'s union rides the same preview', (
      tester,
    ) async {
      await _pump(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(0), 8: _pose(80)})),
      );
      await _toggleLanes(tester, _camId);

      // SELECT the key at frame 8 on the position lane.
      final key8 = tester.getCenter(_marker(_camId, 'position', 8));
      await tester.dragFrom(
        key8,
        const Offset(4, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      // MOVE +2 frames and PUMP WITHOUT RELEASING — the device-reported
      // failure was exactly here: every other transform lane moved live
      // while the camera's sat still until the release.
      final gesture = await tester.startGesture(
        key8,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(cellWidth, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(cellWidth, 0));
      await tester.pump();

      expect(
        _marker(_camId, 'position', 10),
        findsOneWidget,
        reason: 'the camera member lane follows the drag LIVE',
      );
      expect(_marker(_camId, 'position', 8), findsNothing);
      expect(
        _marker(_camId, 'scale', 8),
        findsOneWidget,
        reason: 'only the selected lane moves',
      );
      expect(
        _marker(_camId, transformGroupHeaderLane.laneId, 10),
        findsOneWidget,
        reason: 'the row\'s union summary reads the same preview track',
      );

      await gesture.up();
      await tester.pumpAndSettle();

      final session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
      expect(
        session.activeCutOrNull!.camera.track.position.keyAt(10),
        isNotNull,
      );
      expect(session.activeCutOrNull!.camera.track.scale.keyAt(8), isNotNull);
    });
  });

  group('B4-④ selection ranges cross ANY rows freely, both directions', () {
    group('resolveLaneSpanEscalation (the pure law)', () {
      List<TimelineDisplayRow> rows() {
        final draw = Layer(id: _drawId, name: 'A', frames: const []);
        final cam = Layer(
          id: _camId,
          name: 'Cam',
          kind: LayerKind.camera,
          frames: const [],
        );
        return buildTimelineDisplayRows(
          layers: [draw, cam],
          expandedLayerIds: {_camId},
          lanesForLayer: (layer) => layer.id == _camId
              ? [
                  for (final laneId in ['position', 'scale', 'rotation'])
                    PropertyLaneRow(
                      laneId: laneId,
                      label: laneId,
                      keyedFrames: const {},
                    ),
                ]
              : const [],
        );
      }

      test('inside the anchor layer\'s own lane group the lane law keeps '
          'the drag', () {
        expect(
          resolveLaneSpanEscalation(
            rows: rows(),
            layerId: _camId,
            laneId: 'position',
            rowDelta: 0,
          ),
          isNull,
        );
        expect(
          resolveLaneSpanEscalation(
            rows: rows(),
            layerId: _camId,
            laneId: 'position',
            rowDelta: 2, // position → rotation, still the camera's lanes.
          ),
          isNull,
        );
      });

      test('leaving the group joins the cells law — head and swept rows off '
          'the display list, exactly what a cells anchor reports', () {
        final escalation = resolveLaneSpanEscalation(
          rows: rows(),
          layerId: _camId,
          laneId: 'position',
          rowDelta: -2, // up past the camera row onto the drawing row.
        )!;
        expect(escalation.headLayerId, _drawId);
        expect(escalation.headLaneId, isNull);
        expect(escalation.spanRows, [
          const LayerRowAddress(_drawId),
          const LayerRowAddress(_camId),
          const LaneRowAddress(_camId, 'position'),
        ]);
      });

      test('an off-screen anchor answers null — the lane law\'s clamp, '
          'never a crash', () {
        expect(
          resolveLaneSpanEscalation(
            rows: rows(),
            layerId: _drawId,
            laneId: 'position', // the drawing layer shows no lanes here.
            rowDelta: 1,
          ),
          isNull,
        );
      });
    });

    testWidgets('a REAL drag anchored on an fx member lane extends onto an '
        'outside layer (it used to stop dead at the group edge)', (
      tester,
    ) async {
      await _pump(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(0), 8: _pose(80)})),
      );
      await _toggleLanes(tester, _camId);

      final session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;

      // The rail reads camera-section-first here: [cam, cam lanes…,
      // transition clone, draw]. Drag DOWN from the camera's position lane
      // band, past its sibling lanes, onto the DRAWING layer's row — the
      // exact sweep that used to freeze at the lane group's edge.
      final gesture = await tester.startGesture(
        tester.getCenter(_marker(_camId, 'position', 8)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(4, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 2 * rowHeight));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 2 * rowHeight));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final cells = session.frameRangeSelection.value;
      expect(cells, isNotNull, reason: 'the drag joined the cells law');
      expect(
        cells!.coversRow(const LayerRowAddress(_drawId)),
        isTrue,
        reason: 'the span crossed onto the OUTSIDE layer freely',
      );
      expect(
        cells.coversRow(const LaneRowAddress(_camId, 'position')),
        isTrue,
        reason: 'the anchor lane row is in the swept run',
      );
      expect(
        session.laneRangeSelection.value,
        isNull,
        reason: 'one selection: the cells law owns the crossed span',
      );
    });

    testWidgets('and vice versa: a REAL drag anchored on an outside layer\'s '
        'cells crosses the fx lane rows freely', (tester) async {
      await _pump(
        tester,
        _project(camera: CutCamera(keyframes: {0: _pose(0), 8: _pose(80)})),
      );
      // Twirl the CAMERA's lanes open: the rail reads [cam, position,
      // scale, rotation, transition clone, draw].
      await _toggleLanes(tester, _camId);

      final session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;

      // Drag UP from the drawing layer's cells, across the transition
      // clone and the camera's three lane rows, onto the camera row.
      final gesture = await tester.startGesture(
        timelineCellCenter(tester, _drawId.value, 2),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(4, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -2 * rowHeight));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -2 * rowHeight));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -rowHeight));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final cells = session.frameRangeSelection.value;
      expect(cells, isNotNull);
      expect(
        cells!.coversRow(const LaneRowAddress(_camId, 'position')),
        isTrue,
        reason: 'the fx lane rows are swept, not stepped over',
      );
      expect(
        cells.coversRow(const LayerRowAddress(_camId)),
        isTrue,
        reason: 'and the span kept going to the row beyond the group',
      );
    });
  });
}
