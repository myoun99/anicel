// 🗣️attach-rows-lose-the-base-move-when-it-bakes-Q1 (유저 2026-11-11
// 「어태치 줄도 같이 옮겨 놓는다」 — 「참조말고도 기준fx 구울떄랑
// 같은규칙으로 동작하면됨」): a row attached to a reference row wears its
// reference fx's move (F-578 ⑨). Where RASTERIZE cannot carry the move as
// the row's keys and bakes the picture into the row's cels where it shows
// (F-374-Q7 ②③), the attach row is baked with it, drawn wearing the move —
// as an fx RASTERIZE bakes the rows riding the row it bakes (I-120 ②b) —
// so it stays where it showed, and one undo brings both back — a file of
// its own baked so too (-Q3), wearing none of its own reference fx (-Q4).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_layer_mount.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/fx_basis.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_asset.dart' show MediaFitMode;
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';
import 'package:anicel/src/ui/timeline/rasterize_reference_rows.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

import '../../helpers/a_canvas_standing_on_a_frame.dart'
    show opensTheEnginesScreens;
import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

void main() {
  opensTheEnginesScreens();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-attach-bake');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  Layer current(EditorSessionManager s, LayerId id) =>
      s.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

  /// [name], a [width]×[height] picture of [rgba], placed 1:1 as a
  /// reference in [s]'s cut — in the middle of the canvas.
  Future<void> placedFile(
    EditorSessionManager s,
    String name, {
    required int width,
    required int height,
    required int rgba,
  }) async => expect(
    await s.importDoors.importImageFile(
      path: await writeSolidPng(
        tempDir,
        name,
        width: width,
        height: height,
        rgba: rgba,
      ),
      destination: ImportDestination.activeCutLayer,
      copyIntoProject: false,
      fit: MediaFitMode.none,
    ),
    isTrue,
  );

  /// A session with a red 100×60 paper placed 1:1 as a reference on the
  /// default canvas — its middle at (1170, 827) — and a blue 20×20 sheet
  /// placed in the middle above it and attached to it: a reference row of
  /// its own [file], or one rasterized by keys — a drawing row whose cel
  /// holds the picture.
  Future<({EditorSessionManager s, LayerId paper, LayerId sheet})> placed(
    WidgetTester tester, {
    bool file = false,
  }) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.playbackRig.prerenderScheduler.beginInputHold();
    await tester.runAsync(() async {
      await placedFile(
        s,
        'paper.png',
        width: 100,
        height: 60,
        rgba: 0xFF0000FF,
      );
      await placedFile(
        s,
        'sheet.png',
        width: 20,
        height: 20,
        rgba: 0x0000FFFF,
      );
    });
    LayerId showing(String name) => s.requireActiveCut.layers
        .firstWhere((l) => l.mediaReference?.assetPath.endsWith(name) ?? false)
        .id;
    final paper = showing('paper.png');
    final sheet = showing('sheet.png');
    if (!file) {
      s.editingCanvas.rasterizeLayerReferences([sheet]);
      expect(current(s, sheet).mediaReference, isNull, reason: 'premise');
    }
    s.cutCommandCoordinator.setLayerAttachment(
      cutId: s.requireActiveCut.id,
      attach: LayerAttachDrop(
        mounts: [
          (layerId: sheet, baseId: paper, placement: AttachedPlacement.above),
        ],
      ),
    );
    return (s: s, paper: paper, sheet: sheet);
  }

  /// The box the screen shows the sheet's ink in at [frame]: every pixel
  /// solidly blue, as [ExportFrameRenderer] draws the cut.
  Future<ui.Rect?> sheetAt(EditorSessionManager s, int frame) async {
    final image = await ExportFrameRenderer(session: s).renderComposite(
      ExportFrameTask(cut: s.requireActiveCut, frameIndex: frame),
      ExportSizeMode.canvas,
    );
    final width = image.width;
    final bytes = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    image.dispose();
    final rgba = bytes!.buffer.asUint8List();
    double? left;
    double? top;
    double? right;
    double? bottom;
    for (var i = 0; i < rgba.length ~/ 4; i += 1) {
      if (rgba[i * 4 + 2] > 200 && rgba[i * 4] < 60) {
        final x = (i % width).toDouble();
        final y = (i ~/ width).toDouble();
        left = left == null || x < left ? x : left;
        top = top == null || y < top ? y : top;
        right = right == null || x + 1 > right ? x + 1 : right;
        bottom = bottom == null || y + 1 > bottom ? y + 1 : bottom;
      }
    }
    return left == null ? null : ui.Rect.fromLTRB(left, top!, right!, bottom!);
  }

  /// A context under an app, for a verb that puts a window up.
  Future<BuildContext> hostedContext(WidgetTester tester) async {
    late BuildContext hosted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hosted = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return hosted;
  }

  /// RASTERIZE pressed on [paper]'s reference header, waited out.
  Future<void> rasterized(
    WidgetTester tester,
    EditorSessionManager s,
    LayerId paper,
  ) async {
    final context = await hostedContext(tester);
    unawaited(rasterizeReferenceRows(context, s, [current(s, paper)]));
    await tester.pump();
    await settleAsync(
      tester,
      () =>
          find
              .byKey(const ValueKey<String>('reference-rasterize-progress'))
              .evaluate()
              .isEmpty &&
          current(s, paper).mediaReference == null,
      step: const Duration(milliseconds: 20),
    );
  }

  /// [frames] of the sheet as the screen shows them.
  Future<List<ui.Rect?>> shown(
    WidgetTester tester,
    EditorSessionManager s,
    List<int> frames,
  ) async => (await tester.runAsync(
    () async => [for (final frame in frames) await sheetAt(s, frame)],
  ))!;

  /// Each box of [after] where [before] has its own, a pixel either way.
  Matcher standsAsIt(List<ui.Rect?> before) => pairwiseCompare<
    ui.Rect?,
    ui.Rect?
  >(before, (was, now) {
    if (was == null || now == null) {
      return false;
    }
    return (was.left - now.left).abs() <= 1 &&
        (was.top - now.top).abs() <= 1 &&
        (was.right - now.right).abs() <= 1 &&
        (was.bottom - now.bottom).abs() <= 1;
  }, 'the box it showed in, a pixel either way');

  /// [sheet] without the mirrors of cels [paper] no longer holds: the empty
  /// cels a write gives a synced row for each new cel of its base, which
  /// stay when those cels go — 「orphan links stay untouched by design」
  /// (`cutWithReconciledAttachedMirrors`: the cel comes back with them).
  Layer orphansDropped(Layer sheet, Layer paper) {
    final cels = {for (final cel in paper.frames) cel.id};
    final links = {
      for (final MapEntry(:key, :value) in sheet.baseFrameLinks.entries)
        if (cels.contains(key)) key: value,
    };
    final mirrors = sheet.baseFrameLinks.values.toSet();
    return sheet.copyWith(
      baseFrameLinks: links,
      frames: [
        for (final cel in sheet.frames)
          if (links.containsValue(cel.id) || !mirrors.contains(cel.id)) cel,
      ],
    );
  }

  final squashed = TransformTrack.empty().copyWith(
    scale: PropertyTrack<CanvasPoint>().withKey(0, CanvasPoint(x: 1, y: 0.5)),
  );

  /// The paper held at a [turn] of its fx's under its own [track].
  void posed(
    EditorSessionManager s,
    LayerId paper, {
    TransformTrack? track,
    required PropertyTrack<double> turn,
  }) {
    final coordinator = s.cutCommandCoordinator;
    if (track != null) {
      coordinator.updateLayerTransformTrack(
        cutId: s.requireActiveCut.id,
        layerId: paper,
        transformTrack: track,
      );
    }
    coordinator.updateLayerReferenceFx(
      layerId: paper,
      fx: TransformTrack.empty().copyWith(rotation: turn),
    );
  }

  /// The way RASTERIZE lets [paper] go.
  ({bool bakes, bool framed}) wayOf(EditorSessionManager s, LayerId paper) {
    final way = s.cutCommandCoordinator.referenceLetGoOf(
      cutId: s.requireActiveCut.id,
      layerId: paper,
    );
    return (bakes: way.bakes, framed: way.framed);
  }

  for (final (file, sheetIs) in [
    (false, 'a drawn sheet'),
    (true, 'a sheet of its own file (🗣️-Q3 「같이 래스터화해 굽는다」)'),
  ]) {
    testWidgets('🎯a paper squashed by its row under a turn of its fx bakes '
        'in place — $sheetIs attached to it stays where it showed, a '
        'drawing now, and ONE undo gives both back', (tester) async {
      final (:s, :paper, :sheet) = await placed(tester, file: file);
      posed(
        s,
        paper,
        track: squashed,
        turn: PropertyTrack<double>().withKey(0, 30),
      );
      expect(wayOf(s, paper), (bakes: true, framed: false), reason: 'premise');
      final before = await shown(tester, s, [0]);
      final rows = [current(s, paper), current(s, sheet)];
      expect(before.single, isNotNull, reason: 'premise: the sheet shows');

      await rasterized(tester, s, paper);

      expect(await shown(tester, s, [0]), standsAsIt(before));
      expect(current(s, sheet).mediaReference, isNull);
      s.undo();
      expect([current(s, paper), current(s, sheet)], rows);
      await tester.pumpAndSettle();
      s.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('🎯a turn of its fx that moves under the squash bakes a cel a '
        'frame — $sheetIs stays where it showed on every one, its cels '
        'parted with the paper\'s, and ONE undo gives both back', (
      tester,
    ) async {
      final (:s, :paper, :sheet) = await placed(tester, file: file);
      posed(
        s,
        paper,
        track: squashed,
        turn: PropertyTrack<double>().withKey(0, 0).withKey(12, 60),
      );
      expect(wayOf(s, paper), (bakes: true, framed: true), reason: 'premise');
      const frames = [0, 6, 12];
      final before = await shown(tester, s, frames);
      final rows = [current(s, paper), current(s, sheet)];

      await rasterized(tester, s, paper);

      expect(await shown(tester, s, frames), standsAsIt(before));
      final baked = current(s, sheet);
      final cels = {for (final cel in current(s, paper).frames) cel.id};
      expect(baked.mediaReference, isNull);
      expect(baked.frames, hasLength(cels.length));
      expect(
        cels.containsAll(baked.baseFrameLinks.keys),
        isTrue,
        reason: 'no link to a cel the paper no longer holds',
      );
      s.undo();
      final paperBack = current(s, paper);
      expect([
        paperBack,
        orphansDropped(current(s, sheet), paperBack),
      ], rows);
      await tester.pumpAndSettle();
      s.playbackRig.prerenderScheduler.cancel();
    });
  }

  testWidgets('🎯a paper read by the block whose fx moves bakes a cel a '
      'frame — the sheet stays where it showed on every one', (tester) async {
    final (:s, :paper, sheet: _) = await placed(tester);
    s.laneVerbs.setLaneGroupBasis(
      paper,
      transformGroupHeaderLane.laneId,
      FxBasis.block,
      description: 'Basis',
    );
    posed(
      s,
      paper,
      turn: PropertyTrack<double>().withKey(0, 0).withKey(12, 60),
    );
    expect(wayOf(s, paper), (bakes: true, framed: true), reason: 'premise');
    const frames = [0, 6, 12];
    final before = await shown(tester, s, frames);

    await rasterized(tester, s, paper);

    expect(await shown(tester, s, frames), standsAsIt(before));
    await tester.pumpAndSettle();
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯a 겸용 copy that shows the paper elsewhere parts its cel — '
      'the sheet on the paper stays where it showed', (tester) async {
    final (:s, :paper, sheet: _) = await placed(tester);
    final copy = s.cutCommandCoordinator.linkDuplicateLayer(
      cutId: s.requireActiveCut.id,
      layerId: paper,
      insertionIndex: 0,
    );
    posed(
      s,
      copy,
      track: squashed,
      turn: PropertyTrack<double>().withKey(0, 30),
    );
    expect(wayOf(s, paper), (bakes: true, framed: true), reason: 'premise');
    final before = await shown(tester, s, [0]);

    await rasterized(tester, s, paper);

    expect(await shown(tester, s, [0]), standsAsIt(before));
    await tester.pumpAndSettle();
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯a sheet of its own file holding keys of its own reference '
      'fx wears none of them — baked where the paper\'s move stood it, '
      'riding the paper still (🗣️attach-rows-lose-the-base-move-when-it-'
      'bakes-Q4 「어태치줄의 참조fx는없앰」)', (tester) async {
    final (:s, :paper, :sheet) = await placed(tester, file: true);
    posed(
      s,
      paper,
      track: squashed,
      turn: PropertyTrack<double>().withKey(0, 30),
    );
    s.cutCommandCoordinator.updateLayerReferenceFx(
      layerId: sheet,
      fx: TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>()
            .withKey(0, CanvasPoint(x: 1170, y: 827))
            .withKey(12, CanvasPoint(x: 1194, y: 827)),
      ),
    );
    expect(wayOf(s, paper), (bakes: true, framed: false), reason: 'premise');
    const frames = [0, 6, 12];
    final before = await shown(tester, s, frames);
    expect(before.toSet(), hasLength(1), reason: 'its keys move it nowhere');

    await rasterized(tester, s, paper);

    expect(await shown(tester, s, frames), standsAsIt(before));
    final baked = current(s, sheet);
    expect(baked.attachedMode, AttachedMode.synced);
    expect(baked.mediaReference, isNull);
    await tester.pumpAndSettle();
    s.playbackRig.prerenderScheduler.cancel();
  });
}
