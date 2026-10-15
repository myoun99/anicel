// A REFERENCE ROW'S BOX STANDS ON ITS FILE (I-68). 🗣️유저 2026-10-10:
// 「참조 행에서 이동(변형) 도구로 끌면 참조 fx 의 위치값이 바뀐다 — 카메라
// 틀을 끌면 카메라 위치가 바뀌는 것과 같은 방식, 레이어 트랜스폼은 따로
// 남는다」 · 「변형으로 크기 줄였으면 같은값만큼 다른용지도 줄어들게」 ·
// I-68-Q1 「레이어의 fx버튼 꺼도 그 자리 유지」.
//
// The box frames the PICTURE where the reference's pose lays it, and each
// grab writes that pose: the inside its centre, a corner its scale, outside
// its turn — shown while the hand moves, the file laid again on release.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/row_transform_box.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/reference_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-i68-box');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  /// The editing canvas over a session whose red 100×60 paper stands 1:1
  /// in the middle of the default 2340×1654 canvas — (1170, 827) — with the
  /// paper's row active.
  Future<(EditorSessionManager, Layer, ValueNotifier<BrushToolState>)>
  onTheCanvas(WidgetTester tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.playbackRig.prerenderScheduler.beginInputHold();
    await tester.runAsync(() async {
      final red = await writeSolidPng(
        tempDir,
        'red.png',
        width: 100,
        height: 60,
        rgba: 0xFF0000FF,
      );
      expect(
        await s.importDoors.importImageFile(
          path: red,
          destination: ImportDestination.activeCutLayer,
          copyIntoProject: false,
          fit: MediaFitMode.none,
        ),
        isTrue,
      );
    });
    final row = s.requireActiveCut.layers.firstWhere(
      (layer) => layer.mediaReference != null,
    );
    final tool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final cameraView = ValueNotifier<bool>(false);
    final cameraDim = ValueNotifier<double>(0.5);
    addTearDown(tool.dispose);
    addTearDown(cameraView.dispose);
    addTearDown(cameraDim.dispose);
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorCanvasArea(
            session: s,
            brushToolState: tool,
            cameraViewEnabled: cameraView,
            cameraDimOpacity: cameraDim,
          ),
        ),
      ),
    );
    s.selectLayer(row.id);
    await tester.pump();
    return (s, row, tool);
  }

  RowTransformBox? boxOf(WidgetTester tester) {
    final found = find.byType(RowTransformBox);
    return found.evaluate().isEmpty
        ? null
        : tester.widget<RowTransformBox>(found);
  }

  ui.Rect? shown(EditorSessionManager s, Layer row) {
    final cut = s.requireActiveCut;
    final surface = s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      s.brushFrameKeyForCut(cut, row.id, row.frames.single.id),
    );
    final box = surface == null ? null : bitmapSurfaceContentBounds(surface);
    return box == null
        ? null
        : ui.Rect.fromLTRB(
            box.left.toDouble(),
            box.top.toDouble(),
            box.rightExclusive.toDouble(),
            box.bottomExclusive.toDouble(),
          );
  }

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var tries = 0; tries < 100 && !done(); tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  /// The test's own epilogue: the edit's timers run out, the warmer they
  /// woke stopped after them.
  Future<void> wrapUp(WidgetTester tester, EditorSessionManager s) async {
    await tester.pump(const Duration(minutes: 1));
    s.playbackRig.prerenderScheduler.cancel();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  void expectPoint(CanvasPoint actual, CanvasPoint expected) {
    expect(actual.x, closeTo(expected.x, 1e-6));
    expect(actual.y, closeTo(expected.y, 1e-6));
  }

  testWidgets('🎯standing on the group, the box frames the PICTURE where its '
      'pose lays it — and stands so with the row\'s transform switched off',
      (tester) async {
    final (s, row, _) = await onTheCanvas(tester);
    expect(boxOf(tester), isNull, reason: 'standing on nothing that asks');

    s.standOnRow(LaneRowAddress(row.id, referenceGroupLaneId));
    await tester.pump();
    final box = boxOf(tester)!;
    final corners = box.corners;
    expectPoint(corners[0], CanvasPoint(x: 1120, y: 797));
    expectPoint(corners[1], CanvasPoint(x: 1220, y: 797));
    expectPoint(corners[2], CanvasPoint(x: 1220, y: 857));
    expectPoint(corners[3], CanvasPoint(x: 1120, y: 857));
    expect(box.cross, isNull, reason: 'its pivot is the picture\'s middle');

    s.effectsAndFx.toggleLayerTransformFx(row.id);
    await tester.pump();
    expect(
      boxOf(tester),
      isNotNull,
      reason: '「레이어의 fx버튼 꺼도 그 자리 유지」 — the reference fx has no switch',
    );
    await wrapUp(tester, s);
  });

  testWidgets('the move tool on the row brings the box and writes the '
      'reference fx — while a transform lane brings the layer\'s own',
      (tester) async {
    final (s, row, tool) = await onTheCanvas(tester);
    tool.value = tool.value.copyWith(tool: CanvasTool.move);
    s.standOnRow(LayerRowAddress(row.id));
    await tester.pump();

    boxOf(tester)!.move!.committed(CanvasPoint(x: 1200, y: 827));
    await settle(
      tester,
      () => s.layerById(row.id)!.mediaReference!.pose.center.x == 1200,
    );
    expect(
      s.layerById(row.id)!.mediaReference!.pose.center,
      CanvasPoint(x: 1200, y: 827),
    );
    expect(
      s.layerById(row.id)!.transformTrack.position.isEmpty,
      isTrue,
      reason: '「레이어 트랜스폼은 따로 남는다」',
    );
    await tester.pump(const Duration(minutes: 1));

    s.standOnRow(LaneRowAddress(row.id, transformGroupHeaderLane.laneId));
    await tester.pump();
    boxOf(tester)!.move!.committed(CanvasPoint(x: 1300, y: 827));
    await tester.pump();
    expect(
      s.layerById(row.id)!.transformTrack.position.isEmpty,
      isFalse,
      reason: 'standing on the transform, the box is the layer\'s',
    );
    expect(
      s.layerById(row.id)!.mediaReference!.pose.center,
      CanvasPoint(x: 1200, y: 827),
    );
    await wrapUp(tester, s);
  });

  testWidgets('a drag shows the picture where the hand is — nothing written '
      '— and the release lays the file there, ONE undo', (tester) async {
    final (s, row, _) = await onTheCanvas(tester);
    s.standOnRow(LaneRowAddress(row.id, referenceGroupLaneId));
    await tester.pump();
    final before = s.layerById(row.id)!;

    boxOf(tester)!.move!.changed(CanvasPoint(x: 1250, y: 900));
    expect(
      laneEditInFlight(s.dragPreview.value)?.row?.mediaReference?.pose.center,
      CanvasPoint(x: 1250, y: 900),
    );
    expect(s.layerById(row.id), before, reason: 'a drag writes nothing');

    boxOf(tester)!.move!.committed(CanvasPoint(x: 1250, y: 900));
    await settle(
      tester,
      () => s.layerById(row.id)!.mediaReference!.pose.center.x == 1250,
    );
    expect(shown(s, row), const ui.Rect.fromLTRB(1200, 870, 1300, 930));

    s.undo();
    expect(shown(s, row), const ui.Rect.fromLTRB(1120, 797, 1220, 857));
    await wrapUp(tester, s);
  });

  testWidgets('a row moved by its own transform: the box stands where the '
      'canvas shows the picture, and a drag lands back through the row — '
      'in the file\'s own place under it', (tester) async {
    final (s, row, _) = await onTheCanvas(tester);
    s.laneVerbs.updateLayerTransformTrack(
      row.id,
      TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(
          0,
          CanvasPoint(x: 1270, y: 827),
        ),
      ),
    );
    s.standOnRow(LaneRowAddress(row.id, referenceGroupLaneId));
    await tester.pump();

    final box = boxOf(tester)!;
    expectPoint(box.corners[0], CanvasPoint(x: 1220, y: 797));
    expectPoint(box.pose.center, CanvasPoint(x: 1270, y: 827));

    box.move!.committed(CanvasPoint(x: 1300, y: 827));
    await settle(
      tester,
      () => s.layerById(row.id)!.mediaReference!.pose.center.x == 1200,
    );
    expect(
      s.layerById(row.id)!.mediaReference!.pose.center,
      CanvasPoint(x: 1200, y: 827),
      reason: 'the row\'s own move taken back off — where the file stands '
          'in the row',
    );
    await wrapUp(tester, s);
  });

  testWidgets('a corner scales the reference fx, outside turns it — the '
      'pose\'s own two scales and turn', (tester) async {
    final (s, row, _) = await onTheCanvas(tester);
    s.standOnRow(LaneRowAddress(row.id, referenceGroupLaneId));
    await tester.pump();

    final scale = boxOf(tester)!.scale! as RowBoxTwoScales;
    scale.landing.committed(CanvasPoint(x: 2, y: 2));
    await settle(
      tester,
      () => s.layerById(row.id)!.mediaReference!.pose.scaleX == 2,
    );
    expect(
      s.layerById(row.id)!.mediaReference!.pose.scale,
      CanvasPoint(x: 2, y: 2),
    );
    expect(shown(s, row), const ui.Rect.fromLTRB(1070, 767, 1270, 887));
    await tester.pump(const Duration(minutes: 1));

    boxOf(tester)!.turn!.committed(90);
    await settle(
      tester,
      () => s.layerById(row.id)!.mediaReference!.pose.rotationDegrees == 90,
    );
    expect(s.layerById(row.id)!.mediaReference!.pose.rotationDegrees, 90);
    expect(
      shown(s, row),
      const ui.Rect.fromLTRB(1110, 727, 1230, 927),
      reason: 'a 200×120 picture stood on its side, about its middle',
    );
    await wrapUp(tester, s);
  });
}
