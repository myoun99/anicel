/// PURE construction of the cut a TVPaint clip lands (the .tvpp reader's
/// converted model). The session mints ids and does the IO/decoding
/// around it; this decides SHAPE, so the whole interpretation is testable
/// without a byte of pixel data — the same split [planCutFolderImport]
/// uses.
///
/// Two decisions worth naming, because both are load-bearing:
///
/// **One cel per DRAWING, not per block.** Blocks sharing a
/// [TvpExposureBlock.sourceIndex] re-expose one cel rather than minting a
/// copy — that is what the timesheet must read and what keeps a project
/// from carrying duplicate rasters.
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

import '../../core/path_names.dart';
import '../editing/default_cut_helpers.dart';
import '../../models/camera_pose.dart';
import '../../models/audio_clip.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/cut_camera.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/import/tvp_import_model.dart';
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_kind.dart';
import '../../models/media_asset.dart' show MediaFitMode;
import '../../models/timeline_exposure.dart';
import '../../models/timeline_repeat.dart';
import 'media_import_planner.dart' show ImportIdMint, PlannedCelBake;

/// One fully-formed cut, the cels to bake into it, and everything the
/// read could not carry over.
class TvpImportPlan {
  const TvpImportPlan({
    required this.cut,
    required this.bakes,
    required this.warnings,
  });

  final Cut cut;
  final List<PlannedCelBake> bakes;
  final List<String> warnings;
}

/// Builds the cut for [parsed]. [resolveFile] turns a block's file key
/// into something the session can read — for the .tvpp reader that is a
/// synthetic slot key resolved against the file bytes at bake time.
///
/// [fit] defaults to [MediaFitMode.none]: a clip's cels are already
/// the clip's exact size and the cut is created at that size, so 1:1 is
/// both correct and the only mode that copies bytes instead of resampling
/// them.
TvpImportPlan planTvpImport({
  required TvpImportClip parsed,
  required String Function(String relativePath) resolveFile,
  required ImportIdMint mint,
  MediaFitMode fit = MediaFitMode.none,
  String? cutName,
}) {
  final warnings = [...parsed.warnings];
  final cutId = mint.nextCutId();
  final canvasSize = CanvasSize(width: parsed.width, height: parsed.height);
  final duration = parsed.frameCount;

  final layers = <Layer>[];
  final bakes = <PlannedCelBake>[];

  // [TvpImportClip.layers] is already bottom-first, and Cut.layers
  // paints in list order (first = bottom), so this loop preserves the
  // stack as it stood in TVPaint.
  for (final source in parsed.layers) {
    final layerId = mint.nextLayerId();
    if (source.isFolder) {
      // Folder rows come straight from the file's layer tree. Members
      // link up in the fix-up pass below — the
      // folder row sits after them in this bottom-first list, so its id
      // does not exist yet while they are built.
      layers.add(
        Layer(
          id: layerId,
          name: source.name,
          frames: const [],
          timeline: SplayTreeMap<int, TimelineExposure>(),
          opacity: source.opacity,
          kind: LayerKind.folder,
        ),
      );
      continue;
    }
    final frames = <Frame>[];
    final timeline = SplayTreeMap<int, TimelineExposure>();
    // The drawing a block shows, keyed by the instance that owns it —
    // this map is what makes a repeat re-expose instead of duplicate.
    final celByInstance = <int, FrameId>{};
    // How many DRAWINGS have taken each name on this layer, so the second
    // one can be told from the first. See [_celNameFor].
    final takenNames = <String, int>{};

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
            name: _celNameFor(
              instanceName: block.name,
              taken: takenNames,
            ),
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
        breakdownOffsets: block.breakdownOffsets,
      );
    }

    // A layer with no blocks is a genuinely empty row in the project
    // file (nothing was hidden by an export option any more) — it keeps
    // its place in the stack and needs no warning.
    //
    // The behaviours are LIVE specs; their ghost exposures only exist
    // after [rederiveRunBehaviors] synthesizes them. An imported cut
    // never passes through a timeline edit, so the planner must run the
    // synthesis itself — H2 of the JSON era, resurfaced by 288: every H
    // layer wore its tag but held nothing.
    layers.add(
      rederiveRunBehaviors(
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
        cutFrameCount: duration,
      ),
    );
  }

  // Folder membership fix-up: parents sit AFTER their members in the
  // bottom-first list, so their ids only exist now.
  for (var i = 0; i < parsed.layers.length; i++) {
    final parentIndex = parsed.layers[i].parentIndex;
    if (parentIndex >= 0 && parentIndex < layers.length) {
      layers[i] = layers[i].copyWith(folderId: layers[parentIndex].id);
    }
  }

  // Sound tracks (only the .tvpp reader supplies these): each becomes an
  // SE row whose one block starts where the track's offset lands and runs
  // to the cut's end — the reference links, playback clamps to the file.
  for (final track in parsed.audioTracks) {
    final layerId = mint.nextLayerId();
    final frameId = mint.nextFrameId(layerId);
    final startFrame = (track.offsetSeconds * parsed.frameRate)
        .round()
        .clamp(0, math.max(0, duration - 1))
        .toInt();
    if (track.muted) {
      warnings.add('${fileNameOfPath(track.filePath)}: 트랙이 뮤트 상태였다 — 소리는 그대로 연결된다.');
    }
    layers.add(
      Layer(
        id: layerId,
        name: fileNameOfPath(track.filePath),
        kind: LayerKind.se,
        frames: [Frame(id: frameId, duration: 1, strokes: const [])],
        timeline: SplayTreeMap<int, TimelineExposure>.from({
          startFrame: TimelineExposure.drawing(
            frameId,
            length: math.max(1, duration - startFrame),
          ),
        }),
        audioClips: [
          AudioClip(
            filePath: track.filePath,
            frameId: frameId,
            gain: math.max(0, track.volume),
          ),
        ],
      ),
    );
  }

  final camera = planTvpCamera(
    camera: parsed.camera,
    frameCount: duration,
  );

  final defaultCut = createDefaultCut(
    cutId: cutId,
    name: cutName ?? parsed.clipName,
    layerId: mint.nextLayerId(),
    canvasSize: canvasSize,
  );
  final cut = importedCut(
    defaultCut: defaultCut,
    layers: layers,
    duration: duration,
  ).copyWith(camera: camera);

  return TvpImportPlan(cut: cut, bakes: bakes, warnings: warnings);
}

/// What to call the cel a drawing becomes: the instance name the animator
/// typed, or nothing. Trustworthy now that the source is the project
/// file — its name table only lists NAMED instances (measured live:
/// an unnamed instance simply has no entry) — the deleted JSON door
/// mixed typed names with TVPaint's own counting in one field.
///
/// [taken] disambiguates a real name used twice for DIFFERENT drawings:
/// the second becomes `3-1`, so the sheet still shows what the animator
/// wrote and the two drawings stay two — this app's law is that two cels
/// sharing a name in a layer are one drawing.
String? _celNameFor({
  required String instanceName,
  required Map<String, int> taken,
}) {
  if (instanceName.isEmpty) {
    return null;
  }
  final already = taken.update(
    instanceName,
    (count) => count + 1,
    ifAbsent: () => 0,
  );
  return already == 0 ? instanceName : '$instanceName-$already';
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
  required int frameCount,
}) {
  // `keyframes` is the gate: the .tvpp reader only fills either list
  // when the clip's `[cameradata]` carries authored keys.
  if (camera.keyframes.isEmpty || camera.positions.isEmpty) {
    return CutCamera.empty();
  }
  final source = camera.positions;
  // A STILL camera stays one key. The baked curve holds one pose per
  // frame either way, and the simplifier keeps both endpoints of any
  // track it walks — which turned TVPaint's single frame-1 key into a
  // key on the last frame too (288, hands-on).
  if (!camera.isAnimated) {
    final first = source.first;
    final index = (first.frame - 1).clamp(0, frameCount - 1);
    return CutCamera(
      keyframes: {index: _cameraPoseFor(first)},
    );
  }

  final byFrame = SplayTreeMap<int, CameraPose>();
  for (final pose in source) {
    // Poses number frames from 1, TVPaint-style.
    final index = pose.frame - 1;
    if (index < 0 || index >= frameCount) {
      continue;
    }
    byFrame.putIfAbsent(index, () => _cameraPoseFor(pose));
  }
  if (byFrame.isEmpty) {
    return CutCamera.empty();
  }

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
/// that half is a straight copy; the zoom is not.
///
/// 🚨The LAW (#965, re-measured 2026-08-27): the width the camera VIEWS
/// is `Camera.Width × scale` — the PROJECT camera rectangle resized by
/// TVPaint's zoom display. A bigger rectangle sees more and magnifies
/// less, so `scale` DIVIDES: [CameraPose.zoom] views `frameW / zoom`
/// canvas pixels and the import frame IS `Camera.Width`, hence
/// `zoom = 1 / scale` and the pose's own size drops out entirely.
///
/// The pose's `sizeX`/`sizeY` do NOT participate. The JSON-era poses
/// (#965) carried the PROJECT camera there, which made `viewed =
/// sizeX × scale` read like the law; the FILE's `camerasizex` is the
/// CLIP CANVAS instead (288 stores 2339×1653 — dumped 2026-08-27), a
/// coordinate-space record, not the framing. #1270 read that field as
/// the framing and flipped the law to `viewed = sizeX / scale`,
/// "confirmed" against 2339 / 2.071 ≈ 1129px — a number derived from
/// the same wrong reading, never measured. The hands-on truth (user
/// screenshots, 08-27): TVPaint's blue rectangle on 288 coincides with
/// the layout paper's 撮影フレーム box, 960 × 2.071 ≈ 1988px wide, while
/// the import framed 1129px — half the paper, visibly too tight.
CameraPose _cameraPoseFor(TvpCameraPose pose) {
  final scale = pose.scale.isFinite && pose.scale > 0 ? pose.scale : 1.0;
  final zoom = 1 / scale;
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
/// what every layer of every measured file carries. Modes with no
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
