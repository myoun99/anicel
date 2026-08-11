/// PURE construction of the cut a TVPaint JSON export lands. The session
/// mints ids and does the IO/decoding around it; this decides SHAPE, so
/// the whole interpretation is testable without a byte of pixel data —
/// the same split [planCutFolderImport] uses.
///
/// Two decisions worth naming, because both are load-bearing:
///
/// **One cel per DRAWING, not per block.** A `repeat` span replays
/// drawings that already exist, so the blocks it produces re-expose the
/// same cel rather than minting a copy. `test_ge2`'s BG is three drawings
/// shown nine times; it imports as three cels with nine exposures, which
/// is what the timesheet must read and what keeps the project from
/// carrying six duplicate rasters.
///
/// **Edge behaviours become live run behaviours, not baked frames.**
/// TVPaint's pre/post behaviour and Anicel's [TimelineRunBehavior] are
/// the same idea — the doc on [TimelineRunEdgeMode] says so outright
/// ("TVP-style N/H/R") — so a held BOOK layer arrives as one cel plus a
/// hold edge that refills itself when the cut length changes, not as 150
/// copies of the same drawing.
library;

import 'dart:collection';
import 'dart:math' as math;

import '../../controllers/default_cut_helpers.dart';
import '../../models/camera_pose.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/cut_camera.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/import/tvp_json_parse.dart';
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_kind.dart';
import '../../models/media_asset.dart' show MediaFitMode;
import '../../models/timeline_exposure.dart';
import '../../models/timeline_repeat.dart';
import 'media_import_planner.dart' show ImportIdMint, PlannedCelBake;

/// One fully-formed cut, the cels to bake into it, and everything the
/// read could not carry over.
class TvpJsonImportPlan {
  const TvpJsonImportPlan({
    required this.cut,
    required this.bakes,
    required this.warnings,
  });

  final Cut cut;
  final List<PlannedCelBake> bakes;
  final List<String> warnings;
}

/// Builds the cut for [parsed]. [resolveFile] turns a JSON-relative image
/// path into something the session can read (the export writes
/// `[003] D/[0004] D.png`, relative to the JSON's own folder).
///
/// [fit] defaults to [MediaFitMode.none]: the export's PNGs are already
/// the clip's exact size and the cut is created at that size, so 1:1 is
/// both correct and the only mode that copies bytes instead of resampling
/// them.
/// [cameraFrameSize] is the PROJECT's shooting frame
/// (`Project.cameraSize`). A cut import must never change it, so the
/// clip's own camera size is expressed through [CameraPose.zoom] instead.
TvpJsonImportPlan planTvpJsonImport({
  required TvpJsonParseResult parsed,
  required String Function(String relativePath) resolveFile,
  required ImportIdMint mint,
  required CanvasSize cameraFrameSize,
  MediaFitMode fit = MediaFitMode.none,
  String? cutName,
}) {
  final warnings = [...parsed.warnings];
  final cutId = mint.nextCutId();
  final canvasSize = CanvasSize(width: parsed.width, height: parsed.height);
  final duration = parsed.frameCount;

  final layers = <Layer>[];
  final bakes = <PlannedCelBake>[];

  // [TvpJsonParseResult.layers] is already bottom-first, and Cut.layers
  // paints in list order (first = bottom), so this loop preserves the
  // stack as it stood in TVPaint.
  for (final source in parsed.layers) {
    final layerId = mint.nextLayerId();
    final frames = <Frame>[];
    final timeline = SplayTreeMap<int, TimelineExposure>();
    // The drawing a block shows, keyed by the instance that owns it —
    // this map is what makes a repeat re-expose instead of duplicate.
    final celByInstance = <int, FrameId>{};

    for (final block in source.blocks) {
      var frameId = celByInstance[block.sourceIndex];
      if (frameId == null) {
        frameId = mint.nextFrameId(layerId);
        celByInstance[block.sourceIndex] = frameId;
        frames.add(
          Frame(
            id: frameId,
            duration: 1,
            strokes: const [],
            // The instance name is the cel number ("1", "1.5", "15a") —
            // or, on rows with no pixels, the label itself ("PAN",
            // "arisu,おはよ"). Both belong on the timesheet verbatim.
            name: block.name.isEmpty ? null : block.name,
          ),
        );
        if (block.file.isEmpty) {
          warnings.add(
            '${source.name}: the instance at frame ${block.start + 1} names '
            'no file — its cel stays empty.',
          );
        } else {
          bakes.add(
            PlannedCelBake(
              cutId: cutId,
              layerId: layerId,
              frameId: frameId,
              sourceFile: resolveFile(block.file),
              fit: fit,
            ),
          );
        }
      }
      timeline[block.start] = TimelineExposure.drawing(
        frameId,
        length: block.length,
      );
    }

    if (frames.isEmpty) {
      // With 「빈 사진 포함」 off, TVPaint omits every instance whose image
      // is blank — a layer that plainly HAS a timeline comes through with
      // an empty `link[]`. Keep the row so the stack still matches, and
      // say why it is bare.
      warnings.add(
        '${source.name}: no instances in the export — re-export with '
        '「빈 사진 포함」 (include empty images) on to get its timeline.',
      );
    }

    layers.add(
      Layer(
        id: layerId,
        name: source.name,
        frames: frames,
        timeline: timeline,
        isVisible: source.visible,
        opacity: source.opacity,
        blendMode: _blendModeFor(source, warnings),
        kind: LayerKind.animation,
        runBehaviors: _runBehaviorsFor(source, timeline),
      ),
    );
  }

  final camera = planTvpCamera(
    camera: parsed.camera,
    cameraFrameSize: cameraFrameSize,
    frameCount: duration,
    warnings: warnings,
  );

  final defaultCut = createDefaultCut(
    cutId: cutId,
    name: cutName ?? parsed.clipName,
    layerId: mint.nextLayerId(),
    canvasSize: canvasSize,
  );
  // Keep the fixtures (instruction + camera rows), replace the default
  // drawing layer with the imported stack.
  final fixtureLayers = [
    for (final layer in defaultCut.layers)
      if (layer.kind != LayerKind.animation) layer,
  ];
  final cut = defaultCut.copyWith(
    duration: duration,
    layers: layers.isEmpty ? defaultCut.layers : [...layers, ...fixtureLayers],
    camera: camera,
  );

  return TvpJsonImportPlan(cut: cut, bakes: bakes, warnings: warnings);
}

/// TVPaint's edge behaviour as a live run edge. `none` stores nothing —
/// the absence of a behaviour IS none ([TimelineRunEdgeMode] has no such
/// member on purpose).
///
/// The behaviour is carried even when the layer already reaches the cut
/// end and has no free space to fill: Anicel rederives the ghosts on
/// every duration change, so keeping it is what makes a held BOOK layer
/// still hold after the cut is lengthened.
/// The anchors come from the TIMELINE, not from the mint order: a layer
/// whose last block re-shows an earlier drawing (a repeat, or a linked
/// image) ends on a cel that was minted first, so `frames.last` would
/// name the wrong end of the run.
List<TimelineRunBehavior> _runBehaviorsFor(
  TvpLayer source,
  SplayTreeMap<int, TimelineExposure> timeline,
) {
  if (timeline.isEmpty) {
    return const [];
  }
  final firstCel = timeline[timeline.firstKey()]!.frameId!;
  final lastCel = timeline[timeline.lastKey()]!.frameId!;
  TimelineRunEdgeMode? modeFor(TvpEdgeBehavior behavior) => switch (behavior) {
    TvpEdgeBehavior.none => null,
    TvpEdgeBehavior.hold => TimelineRunEdgeMode.hold,
    // Ping-pong has no Anicel mode; the parser already warned.
    TvpEdgeBehavior.repeat || TvpEdgeBehavior.pingPong =>
      TimelineRunEdgeMode.repeat,
  };

  final behaviors = <TimelineRunBehavior>[];
  final pre = modeFor(source.preBehavior);
  if (pre != null) {
    behaviors.add(
      TimelineRunBehavior(
        anchorFrameId: firstCel,
        side: TimelineRunEdgeSide.start,
        mode: pre,
      ),
    );
  }
  final post = modeFor(source.postBehavior);
  if (post != null) {
    behaviors.add(
      TimelineRunBehavior(
        anchorFrameId: lastCel,
        side: TimelineRunEdgeSide.end,
        mode: post,
      ),
    );
  }
  return behaviors;
}

/// Deviations a straight line may have before the simplifier keeps the
/// frame as its own key. Sized to stay under a quarter canvas pixel on a
/// 2000px-ish canvas: position is already in canvas pixels; a 1e-4 zoom
/// error moves a 2000px span by 0.2px, and 0.01° swings a 1000px radius
/// by 0.17px.
const double _cameraPositionTolerance = 0.25;
const double _cameraZoomTolerance = 1e-4;
const double _cameraRotationTolerance = 0.01;

/// A key at least this often, so the simplifier's per-run rescan cannot
/// turn quadratic on a very long clip.
const int _cameraMaxRunFrames = 512;

/// The clip's camera as a [CutCamera].
///
/// **Built from the BAKED `positions`, not the authored `points`.**
/// TVPaint's own curve does not reach its keyframe values: in the
/// `edge_behaviors` fixture the key at frame 24 reads `y: 853.0` while the
/// baked curve TVPaint displayed ends at `y: 845.332`, and the first key's
/// value is only reached one frame late in `production_clip`. The animator
/// framed the move they SAW, so the baked curve is the truth and the keys
/// are a lossy summary of it.
///
/// A key on every frame would be unreadable on the timeline, so
/// [_simplifyCameraTrack] drops every frame a straight line between its
/// neighbours already reproduces: a linear pan collapses back to two keys,
/// a hold to one, and easing keeps exactly the keys it needs.
///
/// `angle` arrives NEGATED — the two apps count rotation opposite ways.
/// See [_cameraPoseFor] for the measurement that settled it.
CutCamera planTvpCamera({
  required TvpCamera camera,
  required CanvasSize cameraFrameSize,
  required int frameCount,
  required List<String> warnings,
}) {
  // 🚨 `points` is the gate, NOT `positions`. A clip whose camera was never
  // touched still exports a full `positions` array — and every pose in it
  // reads `x: 0, y: 0`, which is a placeholder and not a centre. The
  // `held_instances` fixture is exactly that shape; taking it literally
  // parks the camera on the canvas corner and shows one quadrant.
  if (camera.keyframes.isEmpty) {
    return CutCamera.empty();
  }
  final baked = camera.positions.isNotEmpty;
  final source = baked ? camera.positions : camera.keyframes;
  if (source.isEmpty) {
    return CutCamera.empty();
  }
  if (!baked) {
    warnings.add(
      'The export carries camera keys but no baked curve — the move is read '
      'as straight lines between them, which is not always what TVPaint '
      'showed.',
    );
  }

  final byFrame = SplayTreeMap<int, CameraPose>();
  for (final pose in source) {
    // The export numbers frames from 1.
    final index = pose.frame - 1;
    if (index < 0 || index >= frameCount) {
      continue;
    }
    byFrame.putIfAbsent(index, () => _cameraPoseFor(pose, cameraFrameSize));
  }
  if (byFrame.isEmpty) {
    return CutCamera.empty();
  }
  _warnOnShootingFrameMismatch(source.first, cameraFrameSize, warnings);

  final frames = byFrame.keys.toList();
  final poses = byFrame.values.toList();
  return CutCamera(
    keyframes: {
      for (final index in _simplifyCameraTrack(frames, poses))
        frames[index]: poses[index],
    },
  );
}

/// One TVPaint pose in Anicel's terms. [CameraPose.center] is the view
/// centre in canvas coordinates and TVPaint's `x`/`y` is the same thing, so
/// that half is a straight copy; the zoom is not, because TVPaint states
/// its framing as the camera's SIZE in clip pixels while Anicel states it
/// as canvas pixels per camera pixel against a PROJECT-wide frame.
CameraPose _cameraPoseFor(TvpCameraPose pose, CanvasSize frame) {
  final spanX = pose.sizeX > 0 ? pose.sizeX : frame.width.toDouble();
  final spanY = pose.sizeY > 0 ? pose.sizeY : frame.height.toDouble();
  final scale = pose.scale.isFinite && pose.scale > 0 ? pose.scale : 1.0;
  // Fit on the tighter axis when the two shooting frames disagree on
  // aspect: framing a little wider than TVPaint did is recoverable, a crop
  // through the drawing is not.
  final zoom = scale * math.min(frame.width / spanX, frame.height / spanY);
  return CameraPose(
    center: CanvasPoint(x: pose.x, y: pose.y),
    zoom: zoom.isFinite && zoom > 0 ? zoom : 1.0,
    // NEGATED — the two apps count rotation opposite ways. Measured on
    // `eased_camera`: its angle runs 0° → -7.67° over frames 1-15 and the
    // camera RECTANGLE on TVPaint's canvas turns clockwise across that
    // stretch, so TVPaint's negative is a clockwise camera.
    // [CameraPose.rotationDegrees] turns the view clockwise on POSITIVE.
    // Copying the sign through would mirror every rotating move.
    rotationDegrees: pose.angleDegrees.isFinite ? -pose.angleDegrees : 0,
  );
}

void _warnOnShootingFrameMismatch(
  TvpCameraPose pose,
  CanvasSize frame,
  List<String> warnings,
) {
  if (pose.sizeX <= 0 || pose.sizeY <= 0) {
    return;
  }
  final theirs = pose.sizeX / pose.sizeY;
  final ours = frame.width / frame.height;
  if ((theirs - ours).abs() <= 0.001) {
    return;
  }
  warnings.add(
    'The clip shoots ${pose.sizeX.round()}×${pose.sizeY.round()} but this '
    'project shoots ${frame.width}×${frame.height} — the camera is fitted to '
    'the tighter axis, so it frames a little wider than TVPaint did.',
  );
}

/// Indexes worth keeping: the ends, plus every frame a straight line
/// between the surrounding kept frames fails to reproduce.
List<int> _simplifyCameraTrack(List<int> frames, List<CameraPose> poses) {
  if (poses.length <= 2) {
    return [for (var i = 0; i < poses.length; i += 1) i];
  }
  final kept = <int>[0];
  var anchor = 0;
  for (var candidate = 2; candidate < poses.length; candidate += 1) {
    if (frames[candidate] - frames[anchor] > _cameraMaxRunFrames ||
        !_lineReproduces(frames, poses, anchor, candidate)) {
      kept.add(candidate - 1);
      anchor = candidate - 1;
    }
  }
  kept.add(poses.length - 1);
  return kept;
}

bool _lineReproduces(
  List<int> frames,
  List<CameraPose> poses,
  int from,
  int to,
) {
  final span = frames[to] - frames[from];
  if (span <= 0) {
    return false;
  }
  final start = poses[from];
  final end = poses[to];
  for (var middle = from + 1; middle < to; middle += 1) {
    final t = (frames[middle] - frames[from]) / span;
    final pose = poses[middle];
    double off(double a, double b, double actual) => (a + (b - a) * t - actual)
        .abs();
    if (off(start.center.x, end.center.x, pose.center.x) >
            _cameraPositionTolerance ||
        off(start.center.y, end.center.y, pose.center.y) >
            _cameraPositionTolerance ||
        off(start.zoom, end.zoom, pose.zoom) > _cameraZoomTolerance ||
        off(
              start.rotationDegrees,
              end.rotationDegrees,
              pose.rotationDegrees,
            ) >
            _cameraRotationTolerance) {
      return false;
    }
  }
  return true;
}

/// TVPaint's blending-mode NAME to Anicel's enum.
///
/// `Color` is TVPaint's NORMAL — not a hue/luminosity blend — and it is
/// what every layer of every measured export carries. Modes with no
/// Anicel formula fall back to normal and say so rather than picking a
/// lookalike.
LayerBlendMode _blendModeFor(TvpLayer source, List<String> warnings) {
  final key = source.blendingMode
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_()-]'), '');
  final mode = switch (key) {
    'color' || 'normal' => LayerBlendMode.normal,
    'add' || 'addgamma' => LayerBlendMode.add,
    'multiply' => LayerBlendMode.multiply,
    'screen' => LayerBlendMode.screen,
    'darken' => LayerBlendMode.darken,
    'lighten' => LayerBlendMode.lighten,
    'difference' => LayerBlendMode.difference,
    'exclusion' => LayerBlendMode.exclusion,
    'overlay' => LayerBlendMode.overlay,
    'softlight' => LayerBlendMode.softLight,
    'hardlight' => LayerBlendMode.hardLight,
    'burn' || 'colorburn' => LayerBlendMode.colorBurn,
    'dodge' || 'colordodge' => LayerBlendMode.colorDodge,
    _ => null,
  };
  if (mode == null) {
    warnings.add(
      '${source.name}: blending mode "${source.blendingMode}" has no Anicel '
      'equivalent — imported as normal.',
    );
    return LayerBlendMode.normal;
  }
  return mode;
}
