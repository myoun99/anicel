import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/media_asset.dart' show MediaFitMode;
import '../../models/timeline_exposure.dart';
import '../layer_pose_matrix.dart' show LayerPlacement, picturePlacement;
import '../photoshop/psd_reader.dart';
import 'media_import_planner.dart' show ImportIdMint;
import 'raster_cel_import.dart' show fitPose;
import '../../models/import/import_warning.dart';

/// EXPAND: a Photoshop stack becomes our stack.
///
/// The other half of the PSD import — MERGE hands the composite to the
/// still-image path and is done; this one keeps the structure and gives up
/// what the composite had baked into it (adjustments, layer effects).
///
/// Everything the file says that we can hold is held: group nesting, names,
/// opacity, blend, the eye. Photoshop's own pass-through folder is not even
/// a translation — [LayerBlendMode.passThrough] is our folder default and
/// means the same thing.
///
/// Into a cut that is there already, the whole document lands inside ONE
/// folder named after the file. That is what makes "expanded PSD" a thing
/// you can point at there: undo takes it, a later re-import replaces it,
/// and nobody has to reason about which of forty rows came from where.
///
/// A NEW cut made of the document is that thing already — the cut is the
/// file — so its rows stand in it as the file has them, under no folder the
/// file does not have (🗣️유저 2026-10-20, F-422: 「새 컷으로 만들기 해도
/// psd의 파일이름폴더가 타임라인에 생기는데 안생기도록. 레이어에 임포트할때만
/// 생기도록」). ↩️A new cut held the file's folder too.
///
/// Pure: it decides the tree and the rectangles, and never touches a pixel.
/// The pixels are the service's half, which is what makes every rule here
/// testable without an engine.

/// The part of a layer's picture that is drawn, in the layer's own pixels.
typedef PsdLayerCrop = ({int left, int top, int width, int height});

/// Where one expanded layer's picture goes.
class PsdLayerPlacement {
  const PsdLayerPlacement({
    required this.sourceIndex,
    required this.layerId,
    required this.frameId,
    required this.rect,
    required this.crop,
  });

  /// Index into [PsdDocument.layers] — the record whose pixels these are.
  final int sourceIndex;
  final LayerId layerId;
  final FrameId frameId;

  /// Canvas-space destination of [crop], already carrying the document's
  /// fit.
  final ui.Rect rect;

  /// The part of the layer inside the document — the only part Photoshop
  /// shows (F-307).
  final PsdLayerCrop crop;
}

class PsdExpandPlan {
  const PsdExpandPlan({
    required this.layers,
    required this.placements,
    required this.warnings,
  });

  /// Bottom-first, the order a cut stores: each folder row sits directly
  /// above the contiguous run of its members.
  final List<Layer> layers;

  final List<PsdLayerPlacement> placements;
  final List<ImportWarning> warnings;
}

/// Photoshop's four-character blend codes. Everything absent from this map
/// arrives as [LayerBlendMode.normal] with the layer named in a warning:
/// silently drawing "linear burn" as normal is a picture that is wrong in a
/// way nobody can see the reason for.
const Map<String, LayerBlendMode> psdBlendModes = {
  'pass': LayerBlendMode.passThrough,
  'norm': LayerBlendMode.normal,
  'dark': LayerBlendMode.darken,
  'mul ': LayerBlendMode.multiply,
  'idiv': LayerBlendMode.colorBurn,
  'lite': LayerBlendMode.lighten,
  'scrn': LayerBlendMode.screen,
  'div ': LayerBlendMode.colorDodge,
  'lddg': LayerBlendMode.add,
  'over': LayerBlendMode.overlay,
  'sLit': LayerBlendMode.softLight,
  'hLit': LayerBlendMode.hardLight,
  'diff': LayerBlendMode.difference,
  'smud': LayerBlendMode.exclusion,
};

/// Plans [document]'s expansion into [canvas].
///
/// [duration] is the cut's length: an expanded layer is a PICTURE layer, so
/// its one cel is held across the whole thing. [newCut]: the stack makes a
/// cut of its own, and stands in it unwrapped.
PsdExpandPlan planPsdExpansion({
  required PsdDocument document,
  required String displayName,
  required CutId cutId,
  required int duration,
  required CanvasSize canvas,
  required MediaFitMode fit,
  required ImportIdMint mint,
  required bool newCut,
}) {
  final warnings = <ImportWarning>[...document.warnings];
  final held = duration < 1 ? 1 : duration;

  // The document's own fit carries every layer: each sits inside it at its
  // stored offset, on the same scales. Fitting each layer to the canvas on
  // its own would scatter a stack that lines up.
  // ↩️The layers took the document's WIDTH ratio along both axes, which a
  // stretch to another aspect is not: they stood off the composite by the
  // difference, down the page. Each axis has its own scale now (I-68 — the
  // fit is a pose).
  final documentSize = CanvasSize(
    width: document.width,
    height: document.height,
  );
  final onCanvas = picturePlacement(
    fitPose(picture: documentSize, canvas: canvas, fit: fit),
    documentSize,
  );

  final rootId = newCut ? null : mint.nextLayerId();
  final layers = <Layer>[];
  final placements = <PsdLayerPlacement>[];

  // Bottom-first, Photoshop brackets a group with a hidden record BELOW its
  // members and the folder row itself ABOVE them — which is our order
  // exactly, so the walk is one pass with a stack of open groups.
  final openGroups = <LayerId>[];
  LayerId? enclosing() => openGroups.isEmpty ? rootId : openGroups.last;

  for (var index = 0; index < document.layers.length; index += 1) {
    final source = document.layers[index];
    switch (source.role) {
      case PsdLayerRole.groupClose:
        openGroups.add(mint.nextLayerId());
      case PsdLayerRole.groupOpen:
        final id = openGroups.isEmpty ? mint.nextLayerId() : openGroups.removeLast();
        _sayNotApplied(source, warnings);
        layers.add(
          Layer(
            id: id,
            name: source.name,
            kind: LayerKind.folder,
            frames: const [],
            timeline: SplayTreeMap<int, TimelineExposure>(),
            isVisible: source.visible,
            opacity: source.opacity / 255,
            blendMode: _blendFor(source, warnings),
            folderId: enclosing(),
            // A folder shown closed comes in closed (F-306).
            collapsed: source.collapsed,
          ),
        );
      case PsdLayerRole.raster:
        final adjustment = source.adjustmentKey;
        if (adjustment != null) {
          // An adjustment cannot be reproduced without Photoshop's colour
          // maths, and reproducing it would also flatten everything under
          // it. The composite already has it applied — which is why MERGE
          // exists — so this says what was lost and where, in every
          // decoder's one word for a kind it does not carry.
          warnings.add(unsupportedLayerKind(source.name));
          continue;
        }
        if (source.clipping) {
          warnings.add(clippingNotApplied(source.name));
        }
        _sayNotApplied(source, warnings);
        final layerId = mint.nextLayerId();
        final frameId = mint.nextFrameId(layerId);
        layers.add(
          Layer(
            id: layerId,
            name: source.name,
            kind: LayerKind.image,
            frames: [
              Frame(id: frameId, duration: held, strokes: const []),
            ],
            timeline: SplayTreeMap<int, TimelineExposure>.from({
              0: TimelineExposure.drawing(frameId, length: held),
            }),
            isVisible: source.visible,
            opacity: source.opacity / 255,
            blendMode: _blendFor(source, warnings),
            folderId: enclosing(),
          ),
        );
        final crop = _insideTheDocument(source, document);
        if (source.hasPixels && crop != null) {
          placements.add(
            PsdLayerPlacement(
              sourceIndex: index,
              layerId: layerId,
              frameId: frameId,
              rect: _onTheCanvas(onCanvas, source, crop),
              crop: crop,
            ),
          );
        }
    }
  }

  // A group whose closing bracket the file never wrote: rather than drop
  // its members, the folder is created here so the tree still closes.
  while (openGroups.isNotEmpty) {
    layers.add(
      Layer(
        id: openGroups.removeLast(),
        name: displayName,
        kind: LayerKind.folder,
        frames: const [],
        timeline: SplayTreeMap<int, TimelineExposure>(),
        folderId: enclosing(),
      ),
    );
  }

  // The root goes last: the folder row sits above everything it holds.
  if (rootId != null) {
    layers.add(
      Layer(
        id: rootId,
        name: displayName,
        kind: LayerKind.folder,
        frames: const [],
        timeline: SplayTreeMap<int, TimelineExposure>(),
      ),
    );
  }

  return PsdExpandPlan(
    layers: layers,
    placements: placements,
    warnings: warnings,
  );
}

/// Names [source] where Photoshop keeps something of it that no row here
/// does, in every decoder's words for them — a group as much as a layer,
/// since either can wear them: layer effects that are on (the stack is the
/// layers' own pixels, and an effect is drawn by Photoshop on top of them —
/// F-306, they used to fall away without a word), a mask that is on and was
/// not baked into its pixels, a lock (10-17).
void _sayNotApplied(PsdLayer source, List<ImportWarning> warnings) {
  if (source.hasLayerEffects) {
    warnings.add(layerEffectsNotApplied(source.name));
  }
  if (source.hasUnbakedMask) {
    warnings.add(layerMaskNotApplied(source.name));
  }
  if (source.locked) {
    warnings.add(lockNotImported(source.name));
  }
}

/// The part of [source] inside [document], in the layer's own pixels — or
/// null when none of it is.
///
/// F-307 (유저 2026-10-06): 「포토샵으로 열면 문제없는데 … 黒枠라는 레이어가
/// 캔버스크기보다 더 위아래로 그림이 더 많은 상태로 임포트됬음」. A layer may
/// hold pixels past the document's edges, and Photoshop shows none of them;
/// a cel keeps its pixels out onto the pasteboard, where the canvas shows
/// them. Measured on the user's file: a frame layer 199px above the
/// document and 536px below it, and ten more layers past an edge. So only
/// what Photoshop shows is drawn.
PsdLayerCrop? _insideTheDocument(PsdLayer source, PsdDocument document) {
  final left = math.max(0, -source.left);
  final top = math.max(0, -source.top);
  final right = math.min(source.width, document.width - source.left);
  final bottom = math.min(source.height, document.height - source.top);
  if (right <= left || bottom <= top) {
    return null;
  }
  return (left: left, top: top, width: right - left, height: bottom - top);
}

/// The canvas rect [onCanvas] lays [source]'s [crop] over — the document's
/// own pixels from the layer's offset. A fit never turns a picture, so its
/// two corners say where the rest went.
ui.Rect _onTheCanvas(
  LayerPlacement onCanvas,
  PsdLayer source,
  PsdLayerCrop crop,
) {
  final left = (source.left + crop.left).toDouble();
  final top = (source.top + crop.top).toDouble();
  final topLeft = onCanvas.apply(CanvasPoint(x: left, y: top));
  final bottomRight = onCanvas.apply(
    CanvasPoint(x: left + crop.width, y: top + crop.height),
  );
  return ui.Rect.fromLTRB(topLeft.x, topLeft.y, bottomRight.x, bottomRight.y);
}

LayerBlendMode _blendFor(PsdLayer source, List<ImportWarning> warnings) {
  final mapped = psdBlendModes[source.blendKey];
  if (mapped != null) {
    return mapped;
  }
  warnings.add(
    ImportWarning(
      'psdBlend',
      '{name}: blend mode "{mode}" has no equivalent — set to normal.',
      {'name': source.name, 'mode': source.blendKey.trim()},
    ),
  );
  return LayerBlendMode.normal;
}
