// THE REFERENCE FX IS A FIXED GROUP (I-68). 🗣️유저 (I-68-Q1, 2026-10-10):
// 「참조fx만들고, 이 fx에는 헤더에 fx버튼 안둠 … 레이어의 fx버튼 꺼도 그 자리
// 유지되고 출력시에도 fx 적용 해제되있어도 유지됨 … 비슷한 다른 fx도
// 있었던것도같은데 있으면 통일」 — like the SE row's name tag: a field the
// row has, no switch. 10-10 (chat): 「담는값은 변형도구랑 같은거 공유」 —
// Position · Scale · Rotation in the transform lanes' own words. 10-17
// (F-374): 「참조fx도 똑같이 fx로서 법 통일. 지금 움직여도 키
// 안생긴다거나 그런 각종 fx관련 싹 통일. 언두도 가능하게 … 리셋버튼도
// 안먹힘」 — keyed, undone and reset as a transform's lanes are; F-374-Q1
// 「트랜스폼처럼 화면에서 옮긴다」 — the canvas moves the picture from where
// its file was laid, and the file is not laid again. ↩️One value with no
// keys, written by laying the file again where it now stood; then keys,
// and the file laid again where they stood it still.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_resize_anchor.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart'
    show LayerPlacement, pictureMoved, picturePlacement;
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/editing_stack_map.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/ui/timeline/lane_row_slice.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/reference_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_provider.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart'
    show transformLaneKeyFrames;

import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-i68-lanes');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  /// A session with a red 100×60 paper placed 1:1 as a reference on the
  /// default 2340×1654 canvas — its middle at (1170, 827) — or on [canvas],
  /// fitted to it by [fit].
  Future<(EditorSessionManager, Layer)> placed(
    WidgetTester tester, {
    CanvasSize? canvas,
    MediaFitMode fit = MediaFitMode.none,
  }) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.playbackRig.prerenderScheduler.beginInputHold();
    await tester.runAsync(() async {
      if (canvas != null) {
        s.cutVerbs.resizeActiveCutCanvas(canvas);
      }
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
          fit: fit,
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

  MediaReference referenceOf(EditorSessionManager s, Layer row) =>
      s.layerById(row.id)!.mediaReference!;

  /// [input] typed into [row]'s reference [laneId] at frame 0.
  void typed(
    EditorSessionManager s,
    Layer row,
    String laneId,
    String input, {
    bool scaleLinked = false,
  }) => s.laneVerbs.setLaneValueAt(
    row.id,
    laneId,
    0,
    input,
    frameIsGlobal: false,
    description: 'Edit value',
    scaleLinked: scaleLinked,
  );

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

  Future<void> stopTheWarmer(
    WidgetTester tester,
    EditorSessionManager s,
  ) async {
    s.playbackRig.prerenderScheduler.cancel();
    await tester.pump();
  }

  /// Where the editing canvas's stack draws [row]'s cel at frame 0 of the
  /// cut stood in — a movie's picture decoded where [movieLaidAt] says.
  LayerPlacement stackPlacementOf(
    EditorSessionManager s,
    Layer row, {
    TransformPose? Function(BrushFrameKey key)? movieLaidAt,
  }) {
    final cut = s.requireActiveCut;
    final map = EditingStackMap(
      opacityVerbs: s.opacityVerbs,
      project: s,
      cut: cut,
      stackCut: cut,
      frameIndex: 0,
      activeLayerId: null,
      movieLaidAt: movieLaidAt ?? (_) => null,
      plugins: null,
    );
    return [
      for (final node in map.mapTree(
        resolveCutFrameCompositeTree(cut: cut, frameIndex: 0),
      ))
        if (node is CompositeLeaf<CanvasStackRow> &&
            node.payload is CanvasLayerImageRequest &&
            (node.payload as CanvasLayerImageRequest).frameKey.layerId ==
                row.id)
          (node.payload as CanvasLayerImageRequest).placement,
    ].single!;
  }

  testWidgets('🎯a row that shows a file has the group FIRST — before its '
      'effects and its transform — with no switch, its three members in '
      'the transform\'s own words, unkeyed as it was placed', (tester) async {
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
      '0x+0.00°',
    ]);
    for (final lane in members) {
      expect(lane.keyedFrames, isEmpty, reason: 'unkeyed as it was placed');
      expect(
        lane.showsKeyNavigator,
        isTrue,
        reason: 'a transform lane\'s navigator, as every fx\'s (F-374)',
      );
    }
    await stopTheWarmer(tester, s);
  });

  /// A GIF row whose cels do not say which picture of the file each is, so
  /// none of them can be made from it again.
  Layer unsaidGif() => Layer(
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

  test('a row that does not show a file — or shows one with a cel that does '
      'not say which picture of it it is, so is not made from it again — '
      'has no group', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final drawn = s.requireActiveCut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.animation,
    );
    final gif = unsaidGif();
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

  testWidgets('🎯a value typed into Position KEYS the fx at the playhead — '
      'written at once, nothing held on the canvas — and the canvas moves '
      'the picture there, its file NOT laid again: ONE undo puts it back',
      (tester) async {
    final (s, row) = await placed(tester);
    final before = s.layerById(row.id)!;

    typed(s, row, referencePositionLaneId, '1210, 800');

    final keyed = referenceOf(s, row);
    expect(
      transformLaneKeyFrames(keyed.fx, 'position'),
      {0},
      reason: '「지금 움직여도 키 안생긴다」 — a key, as a transform lane\'s '
          'value makes',
    );
    expect(keyed.poseAt(0).center, CanvasPoint(x: 1210, y: 800));
    expect(
      keyed.pose,
      before.mediaReference!.pose,
      reason: 'where it was placed stays — the value an unkeyed lane holds',
    );
    expect(
      s.dragPreview.value,
      isNull,
      reason: 'written, so there is nothing to hold meanwhile',
    );
    expect(
      lanesOf(s, row)[1].valueLabel!(0),
      '1210.00, 800.00',
      reason: 'the lane reads the key it made',
    );

    // Time for a read of the file to land, had the edit started one.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(minutes: 1));
    expect(
      referenceOf(s, row).laid,
      before.mediaReference!.laid,
      reason: '「굳이 다시 그릴필요도없고」 — the file stays where it was laid',
    );
    expect(shown(s, row), const ui.Rect.fromLTRB(1120, 797, 1220, 857));
    expect(
      referenceMoveAt(
        s.layerById(row.id)!,
        0,
      )!.apply(CanvasPoint(x: 1170, y: 827)),
      CanvasPoint(x: 1210, y: 800),
      reason: 'the canvas moves the picture where the key stands it',
    );

    s.undo();
    expect(
      s.layerById(row.id),
      before,
      reason: 'its own step from the moment it was written — 「언두도 '
          '가능하게」',
    );
    await stopTheWarmer(tester, s);
  });

  testWidgets('Scale is typed as the transform lane\'s two — linked or not '
      '— and Rotation in degrees, each a key at the playhead', (tester) async {
    final (s, row) = await placed(tester);

    typed(s, row, referenceScaleLaneId, '200, 100%', scaleLinked: true);
    expect(
      referenceOf(s, row).poseAt(0).scale,
      CanvasPoint(x: 2, y: 2),
      reason: 'the chain carries the box left as it was shown',
    );

    typed(s, row, referenceRotationLaneId, '30°');
    final keyed = referenceOf(s, row);
    expect(keyed.poseAt(0).rotationDegrees, 30);
    expect(transformLaneKeyFrames(keyed.fx, 'scale'), {0});
    expect(transformLaneKeyFrames(keyed.fx, 'rotation'), {0});
    await stopTheWarmer(tester, s);
  });

  testWidgets('a paper placed at twice its size reads a linked Scale '
      'against the 200% it shows — not a layer\'s unkeyed 100%', (
    tester,
  ) async {
    final (s, row) = await placed(
      tester,
      canvas: const CanvasSize(width: 200, height: 120),
      fit: MediaFitMode.contain,
    );
    expect(
      row.mediaReference!.pose.scale,
      CanvasPoint(x: 2, y: 2),
      reason: '⛔전제: contained at twice its size',
    );

    typed(s, row, referenceScaleLaneId, '300, 200%', scaleLinked: true);

    expect(
      referenceOf(s, row).poseAt(0).scale,
      CanvasPoint(x: 3, y: 3),
      reason: 'down was left as shown, so the chain carries it',
    );
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
      plugins: null,
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

    // Every step reaches the channel: a preview that compared equal to the
    // last would be dropped, and the canvas would stop following the hand.
    s.laneVerbs.previewLaneValueAt(
      row.id,
      referencePositionLaneId,
      0,
      '1300, 827',
      frameIsGlobal: false,
      scaleLinked: false,
    );
    expect(
      laneEditInFlight(
        s.dragPreview.value,
      )?.row?.mediaReference?.poseAt(0).center,
      CanvasPoint(x: 1300, y: 827),
    );

    s.laneVerbs.endLaneEditPreview();
    expect(s.dragPreview.value, isNull);
    await stopTheWarmer(tester, s);
  });

  testWidgets('🎯the ◆ on a reference lane keys it where it stands — as a '
      'transform lane\'s does (F-374) — one undo, and again takes the key '
      'away', (tester) async {
    final (s, row) = await placed(tester);
    // Grown to the right, the paper stays where it was placed: the
    // canvas's middle is x 1470 now, the paper's 1170.
    s.cutVerbs.resizeActiveCutCanvas(
      const CanvasSize(width: 2940, height: 1654),
      anchor: CanvasResizeAnchor.centerLeft,
    );
    final before = s.layerById(row.id)!;
    void diamond() => s.laneVerbs.toggleLaneKeyAt(
      row.id,
      referencePositionLaneId,
      0,
      frameIsGlobal: false,
      description: 'Key Position',
    );

    diamond();
    final keyed = referenceOf(s, row);
    expect(transformLaneKeyFrames(keyed.fx, 'position'), {0});
    expect(
      keyed.poseAt(0).center,
      CanvasPoint(x: 1170, y: 827),
      reason: 'frozen where the paper stands — not where an unkeyed layer '
          'stands, in the canvas\'s middle',
    );
    expect(
      keyed.poseAt(0),
      keyed.laid,
      reason: 'keyed where it stands: nothing moves, nothing is laid again',
    );
    s.undo();
    expect(s.layerById(row.id), before);

    s.redo();
    diamond();
    expect(referenceOf(s, row).fx.isEmpty, isTrue);
    await stopTheWarmer(tester, s);
  });

  testWidgets('🎯the group\'s Reset puts the fx back where its file was '
      'PLACED — not in the middle of the canvas — one undo '
      '(「참조fx에서 리셋버튼도 안먹힘」)', (tester) async {
    final (s, row) = await placed(tester);
    // Grown to the right, the paper stays where it was placed: the
    // canvas's middle is x 1470 now, the paper's 1170.
    s.cutVerbs.resizeActiveCutCanvas(
      const CanvasSize(width: 2940, height: 1654),
      anchor: CanvasResizeAnchor.centerLeft,
    );
    typed(s, row, referencePositionLaneId, '1210, 800');

    expect(s.laneVerbs.resetLaneGroup(row.id, referenceGroupLaneId), isTrue);

    expect(referenceOf(s, row).poseAt(0).center, CanvasPoint(x: 1170, y: 827));
    expect(
      transformLaneKeyFrames(referenceOf(s, row).fx, 'position'),
      {0},
      reason: 'AE\'s reset puts the value back and deletes no key',
    );
    expect(
      referenceMoveAt(s.layerById(row.id)!, 0),
      isNull,
      reason: 'back where its file was laid: nothing to move',
    );

    s.undo();
    expect(referenceOf(s, row).poseAt(0).center, CanvasPoint(x: 1210, y: 800));
    await stopTheWarmer(tester, s);
  });

  testWidgets('🎯a span over the row\'s own Position and its reference fx\'s '
      'is ONE group: Create keys both, a move slides both, Delete takes '
      'both — each one undo', (tester) async {
    final (s, row) = await placed(tester);
    final span = TimelineLaneSelection(
      layerId: row.id,
      laneId: 'position',
      startIndex: 0,
      endIndexExclusive: 1,
      laneIds: const ['position', referencePositionLaneId],
    );
    void keysAt(Set<int> frames, String why) {
      expect(
        transformLaneKeyFrames(s.layerById(row.id)!.transformTrack, 'position'),
        frames,
        reason: 'its own Position $why',
      );
      expect(
        transformLaneKeyFrames(referenceOf(s, row).fx, 'position'),
        frames,
        reason: 'its reference fx\'s $why',
      );
    }

    s.laneVerbs.createLaneKeysForSelection(span);
    keysAt({0}, 'keyed');
    s.undo();
    keysAt({}, 'both undone at once');
    s.redo();

    s.laneRangeSelection.value = span;
    expect(s.laneMove.beginLaneRangeMoveDrag(), isTrue);
    s.laneMove.updateLaneRangeMoveDrag(frameDelta: 2);
    s.laneMove.endLaneRangeMoveDrag();
    keysAt({2}, 'slid');
    s.undo();
    keysAt({0}, 'both slid back at once');

    expect(s.laneVerbs.removeLaneKeysForSelection(span), isTrue);
    keysAt({}, 'deleted');
    s.undo();
    keysAt({0}, 'both given back at once');
    await stopTheWarmer(tester, s);
  });

  testWidgets('a span over the group\'s header keys all three of its members '
      '— the header stands for them, as the transform\'s does', (
    tester,
  ) async {
    final (s, row) = await placed(tester);

    s.laneVerbs.createLaneKeysForSelection(
      TimelineLaneSelection(
        layerId: row.id,
        laneId: referenceGroupLaneId,
        startIndex: 0,
        endIndexExclusive: 1,
      ),
    );

    final reference = referenceOf(s, row);
    for (final lane in ['position', 'scale', 'rotation']) {
      expect(transformLaneKeyFrames(reference.fx, lane), {0}, reason: lane);
    }
    expect(
      reference.poseAt(0),
      reference.pose,
      reason: 'frozen where it was placed',
    );
    await stopTheWarmer(tester, s);
  });

  testWidgets('🎯a row of a cut NOT stood in is keyed where it is — the '
      'session left where it stands, one undo (I-89-Q23)', (tester) async {
    final (s, row) = await placed(tester);
    final home = s.activeCutId!;
    s.cutVerbs.createCut();
    final cuts = s.repository.requireProject().tracks.first.cuts;
    final other = cuts.firstWhere((cut) => cut.id != home).id;
    s.selectCut(other);
    Layer rowAtHome() => s.repository
        .requireProject()
        .tracks
        .first
        .cuts
        .firstWhere((cut) => cut.id == home)
        .layers
        .firstWhere((layer) => layer.id == row.id);
    final before = rowAtHome();

    typed(s, row, referencePositionLaneId, '1210, 800');

    expect(
      transformLaneKeyFrames(rowAtHome().mediaReference!.fx, 'position'),
      {0},
    );
    expect(s.activeCutId, other, reason: 'the session stays where it stood');

    s.undo();
    expect(rowAtHome(), before, reason: 'the key, one undo');
    await stopTheWarmer(tester, s);
  });

  test('a reference lane\'s row stands on the reference: a transform edit '
      'leaves it as it was, an edit of its pose or its keys gives a new one',
      () {
    final reference = MediaReference(
      assetPath: '/paper.png',
      pose: TransformPose(center: CanvasPoint(x: 50, y: 30)),
      pictureSize: const CanvasSize(width: 100, height: 60),
    );
    final row = Layer(
      id: const LayerId('paper'),
      name: 'paper',
      frames: const [],
      mediaReference: reference,
    );
    final keyed = row.copyWith(
      transformTrack: row.transformTrack.copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(
          0,
          CanvasPoint(x: 1, y: 1),
        ),
      ),
    );
    final reposed = row.copyWith(
      mediaReference: reference.copyWith(
        pose: TransformPose(center: CanvasPoint(x: 60, y: 30)),
      ),
    );
    final rekeyed = row.copyWith(
      mediaReference: reference.copyWith(
        fx: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>().withKey(
            0,
            CanvasPoint(x: 60, y: 30),
          ),
        ),
      ),
    );

    for (final laneId in referenceLaneSelectionOrder) {
      expect(
        identical(laneRowSlice(row, laneId), laneRowSlice(keyed, laneId)),
        isTrue,
        reason: '$laneId does not rebuild for a transform key',
      );
      for (final (edited, what) in [
        (reposed, 'its pose'),
        (rekeyed, 'its keys'),
      ]) {
        expect(
          identical(laneRowSlice(row, laneId), laneRowSlice(edited, laneId)),
          isFalse,
          reason: '$laneId rebuilds for $what',
        );
      }
    }
  });

  testWidgets('a cel whose picture was laid elsewhere — a movie\'s, while a '
      'move\'s own picture is decoded — is drawn moved from where it was '
      'laid', (tester) async {
    final (s, row) = await placed(tester);
    final laidLeft = TransformPose(center: CanvasPoint(x: 1070, y: 827));
    final placement = stackPlacementOf(
      s,
      row,
      movieLaidAt: (key) => key.layerId == row.id ? laidLeft : null,
    );

    expect(
      placement.apply(CanvasPoint(x: 1070, y: 827)),
      CanvasPoint(x: 1170, y: 827),
      reason: 'laid 100 to the left of where the row stands it',
    );
    await stopTheWarmer(tester, s);
  });

  testWidgets('a still laid elsewhere than its row stands it is drawn — and '
      'placed for the pen, the pick and the marquee — moved from where the '
      'committed row lays its file', (tester) async {
    final (s, row) = await placed(tester);
    s.repository.updateLayer(
      layerId: row.id,
      update: (layer) => layer.copyWith(
        mediaReference: layer.mediaReference!.copyWith(
          laid: TransformPose(center: CanvasPoint(x: 1070, y: 827)),
        ),
      ),
    );
    final cut = s.requireActiveCut;
    final committed = cut.layers.byId(row.id)!;

    expect(
      stackPlacementOf(s, row).apply(CanvasPoint(x: 1070, y: 827)),
      CanvasPoint(x: 1170, y: 827),
      reason: 'laid 100 to the left of where the row stands it',
    );
    expect(
      layerPlacementAt(
        cut: cut,
        layer: committed,
        frameIndex: 0,
      )!.apply(CanvasPoint(x: 1070, y: 827)),
      CanvasPoint(x: 1170, y: 827),
    );
    await stopTheWarmer(tester, s);
  });

  test('an fx that moves over the cut moves the picture each frame from '
      'where its file is laid', () {
    final reference = MediaReference(
      assetPath: '/paper.png',
      pose: TransformPose(center: CanvasPoint(x: 100, y: 50)),
      pictureSize: const CanvasSize(width: 100, height: 60),
      fx: TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>()
            .withKey(0, CanvasPoint(x: 100, y: 50))
            .withKey(10, CanvasPoint(x: 300, y: 50)),
      ),
    );
    final row = Layer(
      id: const LayerId('paper'),
      name: 'paper',
      frames: const [],
      mediaReference: reference,
    );

    expect(
      referenceMoveAt(row, 0),
      isNull,
      reason: 'it stands where its file is laid',
    );
    expect(
      referenceMoveAt(row, 10)!.apply(CanvasPoint(x: 100, y: 50)),
      CanvasPoint(x: 300, y: 50),
    );
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
