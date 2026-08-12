import 'dart:io';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/import/tvp_csv_parse.dart';
import 'package:anicel/src/models/import/tvp_json_parse.dart';
import 'package:anicel/src/models/layer.dart';
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

  TvpCsvNames csvFixture(String name) => parseTvpCsv(
    File('test/fixtures/tvpaint/$name.csv').readAsStringSync(),
  );

  TvpJsonImportPlan planFixture(
    String name, {
    CanvasSize cameraFrameSize = defaultProjectCameraSize,
    TvpCsvNames? names,
  }) => planTvpJsonImport(
    parsed: fixture(name),
    resolveFile: (relative) => '/export/$relative',
    mint: mint(),
    cameraFrameSize: cameraFrameSize,
    names: names,
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
      // Unnamed without a CSV — the JSON's `1, 2, 3` here is TVPaint's own
      // counting and there is nothing in the file to tell it from names
      // somebody typed. See the naming group below.
      expect(d.frames.map((frame) => frame.name), [null, null, null]);
    });

    // The JSON's `instance-name` is never a name. TVPaint fills it with an
    // ordinal when the animator left the instance alone, and writes what
    // they typed when they did not — one field, no flag. Measured on three
    // real exports: a clip with nothing named came through as `1..10` per
    // layer, and in another the SAME layer holds five ordinals and one
    // typed name that happen to collide on `5`.
    //
    // Since a shared name in a layer means a shared DRAWING here, copying
    // that field in is how a layer of ten drawings becomes one. The CSV
    // export is the only thing that separates them, and without it nothing
    // is named at all.
    group('cel names come from the CSV or from nowhere', () {
      test('no CSV: every cel is unnamed, and the import says why', () {
        final plan = planFixture('edge_behaviors');
        for (final layer in plan.cut.layers) {
          for (final frame in layer.frames) {
            expect(frame.name, isNull, reason: layer.name);
          }
        }
        expect(
          plan.warnings.any((warning) => warning.contains('No CSV')),
          isTrue,
          reason: 'silently unnamed would read as a bug in the export',
        );
      });

      test('with the CSV: named cels keep their name, unnamed stay '
          'unnamed', () {
        final plan = planFixture(
          'edge_behaviors',
          names: csvFixture('edge_behaviors'),
        );
        Layer layer(String name) =>
            plan.cut.layers.firstWhere((layer) => layer.name == name);

        // The CSV writes the LAYER's own name where an instance has none.
        expect(layer('TAP').frames.single.name, isNull);
        expect(layer('B').frames.single.name, isNull);
        expect(layer('C').frames.map((frame) => frame.name), [
          null,
          null,
          null,
        ]);
        // And the cel's name where it has one.
        expect(layer('D').frames.map((frame) => frame.name), ['1', '2', '3']);
        expect(layer('E').frames.single.name, '1');
      });

      test('one name on two DIFFERENT drawings is split, not merged', () {
        // Layer A's first two drawings are both called `3` in the CSV —
        // a real thing animators do. Left alone they would be one drawing
        // under this app's law, so the second takes a suffix: the sheet
        // still shows what was written and the drawings stay two.
        final plan = planFixture(
          'edge_behaviors',
          names: csvFixture('edge_behaviors'),
        );
        final a = plan.cut.layers.firstWhere((layer) => layer.name == 'A');
        expect(a.frames.map((frame) => frame.name), ['3', '3-1', '5']);
        expect(
          a.frames.map((frame) => frame.id).toSet(),
          hasLength(3),
          reason: 'three drawings, whatever they are called',
        );
      });

      test('a CSV for another clip is refused, and names nothing', () {
        // Two separate exports: nothing stops a stale CSV sitting beside a
        // re-exported clip, and misnaming cels after somebody else's
        // drawings is worse than leaving them blank.
        final plan = planFixture(
          'edge_behaviors',
          names: csvFixture('named_and_unnamed'),
        );
        for (final layer in plan.cut.layers) {
          for (final frame in layer.frames) {
            expect(frame.name, isNull);
          }
        }
        expect(
          plan.warnings.any((warning) => warning.contains('not the same')),
          isTrue,
        );
      });
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

    test('a plan carries the SPEC and derives no ghosts — filling the cells '
        'is the repository door\'s job', () {
      // Where this belongs is the whole lesson of the bug it fixes. A run
      // behaviour does not cover anything by itself; the ghosts come from
      // `rederiveRunBehaviors`, and the paths that bring a cut in from
      // outside used not to run it — so an imported hold printed `H` on
      // the property tag while the cells after it read empty.
      //
      // The fix went to `ProjectRepository.insertCut`, so a plan STILL
      // has no ghosts and that is correct. Deriving here as well would
      // put the same rule in two places and invite them to drift.
      final plan = planFixture('edge_behaviors');
      for (final layer in plan.cut.layers) {
        expect(
          layer.timeline.values.any((entry) => entry.ghost),
          isFalse,
          reason: '${layer.name} is a plan, not a placed cut',
        );
      }
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

  group('eased_camera.json — rotation, zoom and a shaped curve', () {
    test('every baked frame comes back, curve shape and all', () {
      final parsed = fixture('eased_camera');
      final plan = planFixture('eased_camera');
      expect(parsed.camera.positions, hasLength(24));

      for (final baked in parsed.camera.positions) {
        final resolved = resolveCameraPoseAt(
          camera: plan.cut.camera,
          canvasSize: plan.cut.canvasSize,
          frameIndex: baked.frame - 1,
        );
        expect(resolved.center.x, closeTo(baked.x, 0.25),
            reason: 'frame ${baked.frame} x');
        expect(resolved.center.y, closeTo(baked.y, 0.25),
            reason: 'frame ${baked.frame} y');
        // The clip shoots the project's own frame, so the fit is 1 and
        // the zoom is the scale INVERTED: `scale` resizes the camera
        // rectangle, and a rectangle twice as wide sees twice as much at
        // half the magnification. This used to read `closeTo(baked.scale)`
        // — the implementation's belief restated as its own proof, which
        // is why an inverted zoom move sat here unnoticed.
        expect(resolved.zoom, closeTo(1 / baked.scale, 1e-4),
            reason: 'frame ${baked.frame} zoom');
        // NEGATED: TVPaint's negative angle is a clockwise camera, and
        // CameraPose turns the view clockwise on positive.
        expect(resolved.rotationDegrees, closeTo(-baked.angleDegrees, 0.01),
            reason: 'frame ${baked.frame} angle');
      }
    });

    test('the camera turns the way TVPaint turned it', () {
      final plan = planFixture('eased_camera');
      double angleAt(int frameIndex) => resolveCameraPoseAt(
        camera: plan.cut.camera,
        canvasSize: plan.cut.canvasSize,
        frameIndex: frameIndex,
      ).rotationDegrees;

      // Measured in TVPaint by the user: across frames 1-15 the camera
      // RECTANGLE on the canvas turns clockwise, and from 15 to 24 it
      // turns back the other way. CameraPose turns the view clockwise on
      // POSITIVE, so the imported track must climb and then fall — the
      // opposite of TVPaint's own numbers, which fall and then climb.
      expect(angleAt(0), closeTo(0, 1e-9));
      expect(
        angleAt(14),
        greaterThan(angleAt(0)),
        reason: 'frames 1-15 turn clockwise',
      );
      expect(
        angleAt(23),
        lessThan(angleAt(14)),
        reason: 'frames 15-24 turn back anticlockwise',
      );
    });

    test('a shaped curve keeps every frame it cannot straighten', () {
      final plan = planFixture('eased_camera');
      // 🚨This read 13 while the zoom was TVPaint's `scale` copied
      // through. The zoom is `1 / scale` now — the correct reading, see
      // `_cameraPoseFor` — and a reciprocal bends what used to be
      // straight: the stretches that folded into one key no longer lie on
      // a line within the tolerance, so this eased move keeps a key per
      // frame.
      //
      // Correct, and worth knowing: an eased ZOOM lands denser on the
      // timeline than an eased pan. Nothing else changes — a linear pan
      // still folds to two keys (see the edge_behaviors group), which is
      // what says the simplifier is alive.
      expect(plan.cut.camera.keyframes.length, 24);
    });

    test('rotation and zoom follow the BAKED curve, not the authored key — '
        'the key at frame 7 reads 0° and scale 1.0, and TVPaint showed '
        'neither', () {
      final parsed = fixture('eased_camera');
      final authored = parsed.camera.keyframes.firstWhere(
        (pose) => pose.frame == 7,
      );
      expect(authored.angleDegrees, 0.0);
      expect(authored.scale, 1.0);

      final shown = resolveCameraPoseAt(
        camera: planFixture('eased_camera').cut.camera,
        canvasSize: const CanvasSize(width: 2150, height: 1518),
        frameIndex: 6,
      );
      expect(shown.rotationDegrees, closeTo(3.2856, 0.01));
      // The baked scale here is 0.9193 — a rectangle shrunk to 92%, which
      // is a view magnified by its reciprocal.
      expect(shown.zoom, closeTo(1 / 0.9193, 1e-3));
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
      // Unnamed: this fixture is JSON-only, and the JSON's `1, 2, 3` is
      // TVPaint's counting rather than anything the animator wrote.
      expect(bg.frames.map((frame) => frame.name), [null, null, null]);
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

  // The one axis no fixture presses: a camera the animator RESIZED.
  //
  // Three fixtures carry `scale: 1.0`, where multiplying and dividing by
  // it agree, and `eased_camera` only wanders between 0.80 and 1.05. The
  // numbers here are from a real clip that broke: a 16:9 camera built at
  // 960×540 and stretched out to a 2340×1654 layout sheet.
  group('a camera the animator resized', () {
    CutCamera cameraFrom({
      required double sizeX,
      required double sizeY,
      required double scale,
    }) {
      final pose =
          '{"frame":1,"x":1170.0,"y":827.0,"angle":0.0,"scale":$scale,'
          '"sizeX":$sizeX,"sizeY":$sizeY}';
      final json =
          '{"version":{"major":5,"minor":1},"project":{"camera":'
          '{"width":${sizeX.round()},"height":${sizeY.round()}},'
          '"clip":{"name":"c","width":2340,"height":1654,"framerate":24.0,'
          '"image-count":2,"camera":{"points":[$pose],'
          '"positions":[$pose]},"layers":[]}}}';
      return planTvpJsonImport(
        parsed: parseTvpJson(json),
        resolveFile: (relative) => relative,
        mint: mint(),
        cameraFrameSize: defaultProjectCameraSize,
      ).cut.camera;
    }

    /// How much of the CLIP the camera sees, in clip pixels — the number
    /// the animator can check against the frame they drew.
    double framedWidth(CutCamera camera) =>
        defaultProjectCameraSize.width / camera.keyframeAt(0)!.zoom;

    test('a stretched camera frames what it was stretched to', () {
      // 960 × 2.158795 = 2072.4 of a 2340-wide sheet: 89% of it, which is
      // the frame drawn on the layout. Read as a 4.3× magnification it
      // framed 445px — 19%, a thumbnail in the middle of the drawing.
      final camera = cameraFrom(sizeX: 960, sizeY: 540, scale: 2.158795);
      expect(framedWidth(camera), closeTo(960 * 2.158795, 0.5));
      expect(
        framedWidth(camera) / 2340,
        closeTo(0.886, 0.005),
        reason: 'the sheet is 2340 wide and the camera covers 89% of it',
      );
    });

    test('scale moves the zoom the OTHER way', () {
      // The direction on its own, so an inverted move cannot hide behind
      // a right-looking magnitude: a bigger rectangle sees more.
      final wide = cameraFrom(sizeX: 960, sizeY: 540, scale: 2.0);
      final tight = cameraFrom(sizeX: 960, sizeY: 540, scale: 0.5);
      final plain = cameraFrom(sizeX: 960, sizeY: 540, scale: 1.0);

      expect(wide.keyframeAt(0)!.zoom, lessThan(plain.keyframeAt(0)!.zoom));
      expect(tight.keyframeAt(0)!.zoom, greaterThan(plain.keyframeAt(0)!.zoom));
      expect(framedWidth(wide), closeTo(framedWidth(plain) * 2, 0.5));
      expect(framedWidth(tight), closeTo(framedWidth(plain) / 2, 0.5));
    });

    test('an untouched camera is unaffected — scale 1 is the identity', () {
      // What every existing fixture exercises, kept explicit so the fix
      // is visibly a no-op there.
      final camera = cameraFrom(sizeX: 1920, sizeY: 1080, scale: 1.0);
      expect(camera.keyframeAt(0)!.zoom, closeTo(1.0, 1e-9));
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

    /// What a clip warned about, minus the standing notice that no CSV
    /// came with it. Every clip here is JSON-only and each of these tests
    /// is about something else — but they still say "and nothing ELSE",
    /// which is the half worth keeping.
    List<String> warningsOf(TvpJsonImportPlan result) => [
      for (final warning in result.warnings)
        if (!warning.startsWith('No CSV')) warning,
    ];

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
        warningsOf(result).single,
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
      expect(warningsOf(result).single, contains('Shade'));
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
      expect(warningsOf(result), isEmpty);
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
