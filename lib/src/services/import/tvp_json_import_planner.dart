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

import '../../controllers/default_cut_helpers.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
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
TvpJsonImportPlan planTvpJsonImport({
  required TvpJsonParseResult parsed,
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

  if (parsed.camera.isAnimated) {
    // Parsed and carried on the result; APPLYING it needs the camera
    // layer's own coordinate contract, which is its own round.
    warnings.add(
      'The clip has camera work (${parsed.camera.keyframes.length} '
      'keyframes) — it is read but not applied yet.',
    );
  }

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
