// THE REFERENCE FX IS A FIXED GROUP (I-68). 🗣️유저 (I-68-Q1, 2026-10-10):
// 「참조fx만들고, 이 fx에는 헤더에 fx버튼 안둠 … 레이어의 fx버튼 꺼도 그 자리
// 유지되고 출력시에도 fx 적용 해제되있어도 유지됨 … 비슷한 다른 fx도
// 있었던것도같은데 있으면 통일」 — like the SE row's name tag: a field the
// row has, no switch. 10-10 (chat): 「담는값은 변형도구랑 같은거 공유」 —
// Position · Scale · Rotation in the transform lanes' own words, one value
// with no keys, written by laying the file again where it now stands.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/import/raster_cel_import.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/editing_stack_map.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/reference_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_provider.dart';

import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-i68-lanes');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  /// A session with a red 100×60 paper placed 1:1 as a reference on the
  /// default 2340×1654 canvas — its middle at (1170, 827).
  Future<(EditorSessionManager, Layer)> placed(WidgetTester tester) async {
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
    return (
      s,
      s.requireActiveCut.layers.firstWhere(
        (layer) => layer.mediaReference != null,
      ),
    );
  }

  List<PropertyLaneRow> lanesOf(
    EditorSessionManager s,
    Layer row, {
    bool expanded = true,
  }) => timelineLanesForLayer(
    layer: s.layerById(row.id)!,
    session: s,
    expandedGroupKeys: {
      if (expanded) laneGroupKey(row.id, referenceGroupLaneId),
    },
  );

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

  /// Lets a lay-again read and land, then the edit's own timers.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var tries = 0; tries < 100 && !done(); tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(minutes: 1));
  }

  Future<void> stopTheWarmer(
    WidgetTester tester,
    EditorSessionManager s,
  ) async {
    s.playbackRig.prerenderScheduler.cancel();
    await tester.pump();
  }

  testWidgets('🎯a row that shows a file has the group FIRST — before its '
      'effects and its transform — with no switch, its three members in '
      'the transform\'s own words, and no keys', (tester) async {
    final (s, row) = await placed(tester);

    final collapsed = lanesOf(s, row, expanded: false);
    expect(collapsed.first.laneId, referenceGroupLaneId);
    expect(collapsed.first.isGroupHeader, isTrue);
    expect(
      collapsed.first.groupEnabled,
      isNull,
      reason: '「헤더에 fx버튼 안둠」 — nothing to switch off',
    );
    expect(
      collapsed.where((lane) => laneIsReference(lane.laneId)),
      hasLength(1),
      reason: 'twirled shut, the header alone',
    );

    final open = lanesOf(s, row);
    expect([for (final lane in open.take(4)) lane.laneId], [
      referenceGroupLaneId,
      referencePositionLaneId,
      referenceScaleLaneId,
      referenceRotationLaneId,
    ]);
    final members = open.skip(1).take(3).toList();
    expect([for (final lane in members) lane.valueLabel!(0)], [
      '1170.00, 827.00',
      '100.00, 100.00%',
      '0.00°',
    ]);
    for (final lane in members) {
      expect(lane.keyedFrames, isEmpty, reason: '「키 없는 값 하나」');
      expect(lane.showsKeyNavigator, isFalse);
    }
    await stopTheWarmer(tester, s);
  });

  test('a row that does not show a file — or shows one whose cels are not '
      'made from it again — has no group', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final drawn = s.requireActiveCut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.animation,
    );
    final gif = Layer(
      id: const LayerId('gif'),
      name: 'gif',
      frames: [
        Frame(id: const FrameId('g1'), duration: 1, strokes: const []),
        Frame(id: const FrameId('g2'), duration: 1, strokes: const []),
      ],
      timeline: const {
        0: TimelineExposure.drawing(FrameId('g1'), length: 1),
        1: TimelineExposure.drawing(FrameId('g2'), length: 1),
      },
      mediaReference: MediaReference(
        assetPath: '/clips/a.gif',
        pose: TransformPose(center: CanvasPoint(x: 0, y: 0)),
        pictureSize: const CanvasSize(width: 10, height: 10),
      ),
    );
    s.repository.insertLayer(cutId: s.requireActiveCut.id, layer: gif);

    for (final row in [drawn, gif]) {
      expect(
        timelineLanesForLayer(
          layer: s.layerById(row.id)!,
          session: s,
          expandedGroupKeys: {laneGroupKey(row.id, referenceGroupLaneId)},
        ).where((lane) => laneIsReference(lane.laneId)),
        isEmpty,
        reason: row.name,
      );
    }
  });

  testWidgets('a value typed into Position lays the file again there — its '
      'value held on the canvas until the picture has landed — and ONE undo '
      'puts it back', (tester) async {
    final (s, row) = await placed(tester);

    s.laneVerbs.setLaneValueAt(
      row.id,
      referencePositionLaneId,
      0,
      '1210, 800',
      frameIsGlobal: false,
      description: 'Edit Position',
      scaleLinked: false,
    );
    final held = laneEditInFlight(s.dragPreview.value);
    expect(
      held?.row?.mediaReference?.pose.center,
      CanvasPoint(x: 1210, y: 800),
      reason: 'the value shows while its picture is made — not the old place',
    );

    await settle(
      tester,
      () => s.layerById(row.id)!.mediaReference!.pose.center.x == 1210,
    );
    expect(
      s.layerById(row.id)!.mediaReference!.pose.center,
      CanvasPoint(x: 1210, y: 800),
    );
    expect(shown(s, row), const ui.Rect.fromLTRB(1160, 770, 1260, 830));
    expect(
      s.dragPreview.value,
      isNull,
      reason: 'landed: the held value goes with it',
    );

    s.undo();
    expect(
      s.layerById(row.id)!.mediaReference!.pose.center,
      CanvasPoint(x: 1170, y: 827),
    );
    expect(shown(s, row), const ui.Rect.fromLTRB(1120, 797, 1220, 857));
    await tester.pump(const Duration(minutes: 1));
    await stopTheWarmer(tester, s);
  });

  testWidgets('Scale is typed as the transform lane\'s two — linked or not '
      '— and Rotation in degrees', (tester) async {
    final (s, row) = await placed(tester);

    s.laneVerbs.setLaneValueAt(
      row.id,
      referenceScaleLaneId,
      0,
      '200, 100%',
      frameIsGlobal: false,
      description: 'Edit Scale',
      scaleLinked: true,
    );
    await settle(
      tester,
      () => s.layerById(row.id)!.mediaReference!.pose.scaleX == 2,
    );
    expect(
      s.layerById(row.id)!.mediaReference!.pose.scale,
      CanvasPoint(x: 2, y: 2),
      reason: 'the chain carries the box left as it was shown',
    );

    s.laneVerbs.setLaneValueAt(
      row.id,
      referenceRotationLaneId,
      0,
      '30°',
      frameIsGlobal: false,
      description: 'Edit Rotation',
      scaleLinked: false,
    );
    await settle(
      tester,
      () => s.layerById(row.id)!.mediaReference!.pose.rotationDegrees == 30,
    );
    expect(s.layerById(row.id)!.mediaReference!.pose.rotationDegrees, 30);
    await stopTheWarmer(tester, s);
  });

  testWidgets('a scrub shows the picture where the value stands — its cel '
      'drawn moved from where it was laid — and writes nothing', (
    tester,
  ) async {
    final (s, row) = await placed(tester);
    final before = s.layerById(row.id)!;

    s.laneVerbs.previewLaneValueAt(
      row.id,
      referencePositionLaneId,
      0,
      '1270, 827',
      frameIsGlobal: false,
      scaleLinked: false,
    );

    expect(s.layerById(row.id), before, reason: 'nothing written');
    final cut = s.requireActiveCut;
    final map = EditingStackMap(
      opacityVerbs: s.opacityVerbs,
      project: s,
      cut: cut,
      stackCut: cutShowingDragPreview(cut, s.dragPreview.value),
      frameIndex: 0,
      activeLayerId: null,
      movieLaidAt: s.movieCels.laidAt,
    );
    final requests = [
      for (final node in map.mapTree(
        resolveCutFrameCompositeTree(
          cut: cutShowingDragPreview(cut, s.dragPreview.value),
          frameIndex: 0,
        ),
      ))
        if (node is CompositeLeaf<CanvasStackRow> &&
            node.payload is CanvasLayerImageRequest &&
            (node.payload as CanvasLayerImageRequest).frameKey.layerId ==
                row.id)
          node.payload as CanvasLayerImageRequest,
    ];
    final placement = requests.single.placement!;
    final moved = placement.apply(CanvasPoint(x: 1170, y: 827));
    expect(
      moved,
      CanvasPoint(x: 1270, y: 827),
      reason: 'the picture laid at x 1170 is drawn at the scrubbed 1270',
    );

    s.laneVerbs.endLaneEditPreview();
    expect(s.dragPreview.value, isNull);
    await stopTheWarmer(tester, s);
  });

  testWidgets('a cel whose picture was laid elsewhere — a movie\'s, while a '
      'move\'s own picture is decoded — is drawn moved from where it was '
      'laid', (tester) async {
    final (s, row) = await placed(tester);
    final cut = s.requireActiveCut;
    final laidLeft = TransformPose(center: CanvasPoint(x: 1070, y: 827));
    final map = EditingStackMap(
      opacityVerbs: s.opacityVerbs,
      project: s,
      cut: cut,
      stackCut: cut,
      frameIndex: 0,
      activeLayerId: null,
      movieLaidAt: (key) => key.layerId == row.id ? laidLeft : null,
    );
    final placement = [
      for (final node in map.mapTree(
        resolveCutFrameCompositeTree(cut: cut, frameIndex: 0),
      ))
        if (node is CompositeLeaf<CanvasStackRow> &&
            node.payload is CanvasLayerImageRequest &&
            (node.payload as CanvasLayerImageRequest).frameKey.layerId ==
                row.id)
          (node.payload as CanvasLayerImageRequest).placement,
    ].single!;

    expect(
      placement.apply(CanvasPoint(x: 1070, y: 827)),
      CanvasPoint(x: 1170, y: 827),
      reason: 'laid 100 to the left of where the row stands it',
    );
    await stopTheWarmer(tester, s);
  });

  testWidgets('the ◆ on a reference lane makes no key — it has none to make',
      (tester) async {
    final (s, row) = await placed(tester);
    final before = s.layerById(row.id)!;
    final canUndo = s.canUndo;

    s.laneVerbs.toggleLaneKeyAt(
      row.id,
      referencePositionLaneId,
      0,
      frameIsGlobal: false,
      description: 'Key Position',
    );

    expect(s.layerById(row.id), before);
    expect(s.canUndo, canUndo);
    await stopTheWarmer(tester, s);
  });

  test('pictureMoved is the move from one pose to the other, whatever the '
      'picture\'s size — and none from a collapsed one', () {
    final from = TransformPose(
      center: CanvasPoint(x: 100, y: 50),
      scaleX: 2,
      scaleY: 2,
    );
    final to = TransformPose(
      center: CanvasPoint(x: 300, y: 50),
      scaleX: 4,
      scaleY: 4,
      rotationDegrees: 90,
    );
    for (final size in const [
      CanvasSize(width: 10, height: 10),
      CanvasSize(width: 640, height: 360),
    ]) {
      final move = pictureMoved(from: from, to: to, picture: size)!;
      // The picture's own corner, where each pose lays it.
      final corner = picturePlacement(from, size).apply(
        CanvasPoint(x: 0, y: 0),
      );
      final expected = picturePlacement(to, size).apply(
        CanvasPoint(x: 0, y: 0),
      );
      final got = move.apply(corner);
      expect(got.x, closeTo(expected.x, 1e-9), reason: '$size');
      expect(got.y, closeTo(expected.y, 1e-9), reason: '$size');
    }
    expect(
      pictureMoved(
        from: from.copyWith(scaleX: 0),
        to: to,
        picture: const CanvasSize(width: 10, height: 10),
      ),
      isNull,
    );
  });
}
