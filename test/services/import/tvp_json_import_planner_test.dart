import 'dart:io';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/import/tvp_json_parse.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart' show defaultProjectCameraSize;
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/services/camera_pose_resolver.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/services/import/tvp_json_import_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// The cut a TVPaint export lands, planned without touching a pixel.
void main() {
  ImportIdMint mint() {
    var layers = 0;
    var frames = 0;
    var cuts = 0;
    return ImportIdMint(
      nextLayerId: () => LayerId('layer-${++layers}'),
      nextFrameId: (layerId) => FrameId('${layerId.value}-cel-${++frames}'),
      nextCutId: () => CutId('cut-${++cuts}'),
    );
  }

  TvpJsonParseResult fixture(String name) =>
      parseTvpJson(File('test/fixtures/tvpaint/$name.json').readAsStringSync());

  TvpJsonImportPlan planFixture(
    String name, {
    CanvasSize cameraFrameSize = defaultProjectCameraSize,
  }) => planTvpJsonImport(
    parsed: fixture(name),
    resolveFile: (relative) => '/export/$relative',
    mint: mint(),
    cameraFrameSize: cameraFrameSize,
  );

  group('edge_behaviors.json', () {
    test('the cut takes the clip size, length and name', () {
      final plan = planFixture('edge_behaviors');
      expect(plan.cut.duration, 24);
      expect(plan.cut.canvasSize.width, 2150);
      expect(plan.cut.canvasSize.height, 1518);
      expect(plan.cut.name, 'クリップ_001');
    });

    test('a linear pan collapses back to the two keys that describe it', () {
      // This clip's camera steps 1073→1084.5 in x and 669→845.33 in y at a
      // constant rate across all 24 frames. The export lists 24 baked
      // poses; the track that reproduces them needs two.
      final plan = planFixture('edge_behaviors');
      expect(plan.cut.camera.keyframes.keys, [0, 23]);
      final first = plan.cut.camera.keyframeAt(0)!;
      expect(first.center.x, closeTo(1073, 1e-6));
      expect(first.center.y, closeTo(669, 1e-6));
      expect(
        plan.cut.camera.keyframeAt(23)!.center.y,
        closeTo(845.332, 0.01),
        reason: "the BAKED end, not the authored key's 853.0 — TVPaint "
            'never showed 853',
      );
      expect(
        first.zoom,
        closeTo(1.0, 1e-9),
        reason: 'this clip shoots 1920×1080, the project default',
      );
    });

    test('the stack keeps TVPaint\'s order, bottom-first, with the cut '
        'fixtures on top', () {
      final plan = planFixture('edge_behaviors');
      final imported = [
        for (final layer in plan.cut.layers)
          if (layer.kind == LayerKind.animation) layer.name,
      ];
      expect(
        imported,
        ['A', 'B', 'C', 'D', 'E', 'TAP'],
        reason: 'TAP is position 1 in TVPaint (the top), and Cut.layers '
            'paints first-to-last',
      );
      expect(
        plan.cut.layers.length,
        imported.length + 2,
        reason: 'the instruction and camera fixture rows survive',
      );
    });

    test('three instances three commas apart become three cels with three '
        'exposures', () {
      final plan = planFixture('edge_behaviors');
      final d = plan.cut.layers.firstWhere((layer) => layer.name == 'D');
      expect(d.frames, hasLength(3));
      expect(d.timeline.keys, [0, 3, 6]);
      expect(d.timeline.values.map((entry) => entry.length), [3, 3, 3]);
      expect(d.frames.map((frame) => frame.name), ['1', '2', '3']);
    });

    test('edge behaviours become run behaviours anchored on the run', () {
      final plan = planFixture('edge_behaviors');
      final a = plan.cut.layers.firstWhere((layer) => layer.name == 'A');
      expect(a.runBehaviors, hasLength(1));
      expect(a.runBehaviors.single.side, TimelineRunEdgeSide.end);
      expect(a.runBehaviors.single.mode, TimelineRunEdgeMode.hold);
      expect(
        a.runBehaviors.single.anchorFrameId,
        a.frames.last.id,
        reason: 'an end edge hangs off the last block of the run',
      );

      final d = plan.cut.layers.firstWhere((layer) => layer.name == 'D');
      expect(d.runBehaviors.single.mode, TimelineRunEdgeMode.repeat);

      final c = plan.cut.layers.firstWhere((layer) => layer.name == 'C');
      expect(
        c.runBehaviors,
        isEmpty,
        reason: 'none is the ABSENCE of a behaviour, never a stored one',
      );
    });

    test('a layer covering the whole clip still carries its hold — the '
        'behaviour is live, so lengthening the cut must keep holding', () {
      final plan = planFixture('edge_behaviors');
      final tap = plan.cut.layers.firstWhere((layer) => layer.name == 'TAP');
      expect(tap.timeline.values.single.length, 24);
      expect(tap.runBehaviors.single.mode, TimelineRunEdgeMode.hold);
    });

    test('one bake per drawing, resolved through the caller\'s path', () {
      final plan = planFixture('edge_behaviors');
      expect(plan.bakes, hasLength(12));
      expect(
        plan.bakes.map((bake) => bake.sourceFile),
        contains('/export/[003] D/[0004] D.png'),
      );
      for (final bake in plan.bakes) {
        expect(bake.cutId, plan.cut.id);
      }
    });
  });

  group('held_instances.json', () {
    test('a clip whose camera was never touched gets NO camera — its baked '
        'poses are a 0,0 placeholder, not a centre', () {
      // This export carries `points: []` and three positions that all read
      // x: 0, y: 0. Taken literally that parks the camera on the canvas
      // corner and shows one quadrant; the empty key list is what says
      // "no camera work".
      final parsed = fixture('held_instances');
      expect(parsed.camera.keyframes, isEmpty);
      expect(parsed.camera.positions, isNotEmpty);
      expect(parsed.camera.positions.first.x, 0);

      final plan = planFixture('held_instances');
      expect(plan.cut.camera.isEmpty, isTrue);
      final pose = resolveCameraPoseAt(
        camera: plan.cut.camera,
        canvasSize: plan.cut.canvasSize,
        frameIndex: 0,
      );
      expect(
        pose.center.x,
        plan.cut.canvasSize.width / 2,
        reason: "the cut falls back to Anicel's own centred default",
      );
      expect(pose.center.y, plan.cut.canvasSize.height / 2);
    });
  });

  group('production_clip.json', () {
    test('a repeated pattern re-exposes its cels instead of duplicating '
        'them', () {
      final plan = planFixture('production_clip');
      final bg = plan.cut.layers.firstWhere((layer) => layer.name == 'BG');
      expect(
        bg.frames,
        hasLength(3),
        reason: 'nine blocks, three drawings',
      );
      expect(bg.timeline, hasLength(9));
      expect(
        bg.timeline.values.map((entry) => entry.frameId).toSet(),
        bg.frames.map((frame) => frame.id).toSet(),
        reason: 'every exposure points at one of the three cels',
      );
      expect(bg.frames.map((frame) => frame.name), ['1', '2', '3']);
    });

    test('the bake list is one entry per exported image — 43, the file '
        'count of the export folder', () {
      expect(planFixture('production_clip').bakes, hasLength(43));
    });

    test('held gaps arrive as long exposures, not as repeated cels', () {
      final plan = planFixture('production_clip');
      final layer = plan.cut.layers.firstWhere((layer) => layer.name == 'b_W');
      expect(layer.frames, hasLength(5));
      expect(layer.timeline.keys, [0, 13, 16, 19, 156]);
      expect(
        layer.timeline.values.map((entry) => entry.length),
        [13, 3, 3, 137, 3],
      );
    });

    test('the camera reproduces every baked frame TVPaint showed, from a '
        'handful of keys', () {
      const shootingFrame = CanvasSize(width: 1075, height: 759);
      final parsed = fixture('production_clip');
      final plan = planFixture(
        'production_clip',
        cameraFrameSize: shootingFrame,
      );

      expect(
        plan.cut.camera.keyframes.length,
        lessThan(10),
        reason: '159 baked frames, but the move is a ramp and a hold',
      );
      // The contract is not the key COUNT — it is that resolving the track
      // gives back what TVPaint displayed, frame for frame.
      for (final baked in parsed.camera.positions) {
        final resolved = resolveCameraPoseAt(
          camera: plan.cut.camera,
          canvasSize: plan.cut.canvasSize,
          frameIndex: baked.frame - 1,
        );
        expect(
          resolved.center.x,
          closeTo(baked.x, 0.25),
          reason: 'frame ${baked.frame} x',
        );
        expect(
          resolved.center.y,
          closeTo(baked.y, 0.25),
          reason: 'frame ${baked.frame} y',
        );
        expect(resolved.zoom, closeTo(1.0, 1e-9),
            reason: 'the clip shoots exactly this project frame');
      }
    });

    test('a shooting frame that differs becomes a zoom, and says so', () {
      // The clip shoots 1075×759; this project shoots 1920×1080. Fitting on
      // the tighter axis (height) keeps the whole TVPaint frame visible.
      final plan = planFixture('production_clip');
      final pose = resolveCameraPoseAt(
        camera: plan.cut.camera,
        canvasSize: plan.cut.canvasSize,
        frameIndex: 0,
      );
      expect(pose.zoom, closeTo(1080 / 759, 1e-9));
      expect(
        plan.warnings.where((warning) => warning.contains('shoots')),
        hasLength(1),
      );
    });

    test('opacity and visibility ride along', () {
      final plan = planFixture('production_clip');
      for (final layer in plan.cut.layers) {
        if (layer.kind != LayerKind.animation) {
          continue;
        }
        expect(layer.opacity, 1.0, reason: layer.name);
        expect(layer.isVisible, isTrue, reason: layer.name);
        expect(layer.blendMode, LayerBlendMode.normal, reason: layer.name);
      }
    });
  });

  group('synthetic clips', () {
    String clip(String layers) =>
        '{"version":{"major":5,"minor":1},"project":{"camera":{"width":10,'
        '"height":10},"clip":{"name":"c","width":10,"height":10,'
        '"framerate":24.0,"image-count":6,'
        '"camera":{"points":[],"positions":[]},"layers":[$layers]}}}';

    TvpJsonImportPlan plan(String layers) => planTvpJsonImport(
      parsed: parseTvpJson(clip(layers)),
      resolveFile: (relative) => relative,
      mint: mint(),
      cameraFrameSize: defaultProjectCameraSize,
    );

    test('a layer whose link[] is empty keeps its row and names the export '
        'setting that would have filled it', () {
      final result = plan(
        '{"name":"SE","position":1,"visible":true,"opacity":255,"start":0,'
        '"end":5,"pre-behavior":0,"post-behavior":0,'
        '"blending-mode":"Color","link":[],"repeat":[]}',
      );
      final se = result.cut.layers.firstWhere((layer) => layer.name == 'SE');
      expect(se.frames, isEmpty);
      expect(se.timeline, isEmpty);
      expect(
        result.warnings.single,
        contains('빈 사진 포함'),
      );
    });

    test('an unmapped blending mode falls back to normal and says so', () {
      final result = plan(
        '{"name":"L","position":1,"visible":true,"opacity":255,"start":0,'
        '"end":0,"pre-behavior":0,"post-behavior":0,'
        '"blending-mode":"Shade","link":[{"instance-index":0,'
        '"instance-name":"1","file":"a.png","images":[0]}],"repeat":[]}',
      );
      final layer = result.cut.layers.firstWhere((layer) => layer.name == 'L');
      expect(layer.blendMode, LayerBlendMode.normal);
      expect(result.warnings.single, contains('Shade'));
    });

    test('a named blending mode maps rather than falling back', () {
      final result = plan(
        '{"name":"L","position":1,"visible":true,"opacity":128,"start":0,'
        '"end":0,"pre-behavior":0,"post-behavior":0,'
        '"blending-mode":"Multiply","link":[{"instance-index":0,'
        '"instance-name":"1","file":"a.png","images":[0]}],"repeat":[]}',
      );
      final layer = result.cut.layers.firstWhere((layer) => layer.name == 'L');
      expect(layer.blendMode, LayerBlendMode.multiply);
      expect(layer.opacity, closeTo(128 / 255, 1e-9));
      expect(result.warnings, isEmpty);
    });

    test('a hidden layer stays hidden', () {
      final result = plan(
        '{"name":"L","position":1,"visible":false,"opacity":255,"start":0,'
        '"end":0,"pre-behavior":0,"post-behavior":0,'
        '"blending-mode":"Color","link":[{"instance-index":0,'
        '"instance-name":"1","file":"a.png","images":[0]}],"repeat":[]}',
      );
      expect(
        result.cut.layers.firstWhere((layer) => layer.name == 'L').isVisible,
        isFalse,
      );
    });

    test('an end edge anchors on the cel the run ENDS on, not the last cel '
        'minted', () {
      final result = plan(
        '{"name":"L","position":1,"visible":true,"opacity":255,"start":0,'
        '"end":5,"pre-behavior":0,"post-behavior":3,'
        '"blending-mode":"Color","link":[{"instance-index":0,'
        '"instance-name":"1","file":"a.png","images":[0,4]},'
        '{"instance-index":2,"instance-name":"2","file":"b.png",'
        '"images":[2]}],"repeat":[]}',
      );
      final layer = result.cut.layers.firstWhere((layer) => layer.name == 'L');
      // Blocks: 0-1 shows "1", 2-3 shows "2", 4-5 shows "1" again — so
      // the run ends on the cel that was minted FIRST.
      expect(layer.frames, hasLength(2));
      expect(layer.timeline.keys, [0, 2, 4]);
      expect(
        layer.runBehaviors.single.anchorFrameId,
        layer.frames.first.id,
        reason: 'the last block re-shows the first drawing',
      );
      expect(
        layer.runBehaviors.single.anchorFrameId,
        isNot(layer.frames.last.id),
        reason: 'anchoring on frames.last would name the wrong end',
      );
    });

    test('a pre-behavior fills the lead-in from the FIRST block', () {
      final result = plan(
        '{"name":"L","position":1,"visible":true,"opacity":255,"start":2,'
        '"end":5,"pre-behavior":3,"post-behavior":0,'
        '"blending-mode":"Color","link":[{"instance-index":2,'
        '"instance-name":"1","file":"a.png","images":[2]},'
        '{"instance-index":4,"instance-name":"2","file":"b.png",'
        '"images":[4]}],"repeat":[]}',
      );
      final layer = result.cut.layers.firstWhere((layer) => layer.name == 'L');
      expect(layer.runBehaviors.single.side, TimelineRunEdgeSide.start);
      expect(layer.runBehaviors.single.mode, TimelineRunEdgeMode.hold);
      expect(layer.runBehaviors.single.anchorFrameId, layer.frames.first.id);
      expect(layer.timeline.keys, [2, 4]);
    });
  });
}
