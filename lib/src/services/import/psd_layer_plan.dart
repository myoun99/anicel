import 'dart:collection';
import 'dart:ui' as ui;

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
import '../photoshop/psd_reader.dart';
import 'media_import_planner.dart' show ImportIdMint;
import 'raster_cel_import.dart' show placementRectFor;

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
/// The whole document lands inside ONE folder named after the file. That is
/// what makes "expanded PSD" a thing you can point at: undo takes it, a
/// later re-import replaces it, and nobody has to reason about which of
/// forty rows came from where.
///
/// Pure: it decides the tree and the rectangles, and never touches a pixel.
/// The pixels are the service's half, which is what makes every rule here
/// testable without an engine.

/// Where one expanded layer's picture goes.
class PsdLayerPlacement {
  const PsdLayerPlacement({
    required this.sourceIndex,
    required this.layerId,
    required this.frameId,
    required this.rect,
  });

  /// Index into [PsdDocument.layers] — the record whose pixels these are.
  final int sourceIndex;
  final LayerId layerId;
  final FrameId frameId;

  /// Canvas-space destination, already carrying the document's fit.
  final ui.Rect rect;
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
  final List<String> warnings;
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
/// its one cel is held across the whole thing.
PsdExpandPlan planPsdExpansion({
  required PsdDocument document,
  required String displayName,
  required CutId cutId,
  required int duration,
  required CanvasSize canvas,
  required MediaFitMode fit,
  required ImportIdMint mint,
}) {
  final warnings = <String>[...document.warnings];
  final held = duration < 1 ? 1 : duration;

  // The document's own rectangle carries the fit; every layer sits inside
  // it at its stored offset, scaled by the same factor. Fitting each layer
  // to the canvas on its own would scatter a stack that lines up.
  final documentRect = placementRectFor(
    sourceWidth: document.width,
    sourceHeight: document.height,
    canvas: canvas,
    fit: fit,
  );
  final scale = document.width == 0
      ? 1.0
      : documentRect.width / document.width;

  final rootId = mint.nextLayerId();
  final layers = <Layer>[];
  final placements = <PsdLayerPlacement>[];

  // Bottom-first, Photoshop brackets a group with a hidden record BELOW its
  // members and the folder row itself ABOVE them — which is our order
  // exactly, so the walk is one pass with a stack of open groups.
  final openGroups = <LayerId>[];
  LayerId enclosing() => openGroups.isEmpty ? rootId : openGroups.last;

  for (var index = 0; index < document.layers.length; index += 1) {
    final source = document.layers[index];
    switch (source.role) {
      case PsdLayerRole.groupClose:
        openGroups.add(mint.nextLayerId());
      case PsdLayerRole.groupOpen:
        final id = openGroups.isEmpty ? mint.nextLayerId() : openGroups.removeLast();
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
          ),
        );
      case PsdLayerRole.raster:
        final adjustment = source.adjustmentKey;
        if (adjustment != null) {
          // An adjustment cannot be reproduced without Photoshop's colour
          // maths, and reproducing it would also flatten everything under
          // it. The composite already has it applied — which is why MERGE
          // exists — so this says what was lost and where.
          warnings.add('${source.name}: adjustment layer not applied.');
          continue;
        }
        if (source.clipping) {
          warnings.add('${source.name}: clipping mask not applied.');
        }
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
        if (source.hasPixels) {
          placements.add(
            PsdLayerPlacement(
              sourceIndex: index,
              layerId: layerId,
              frameId: frameId,
              rect: ui.Rect.fromLTWH(
                documentRect.left + source.left * scale,
                documentRect.top + source.top * scale,
                source.width * scale,
                source.height * scale,
              ),
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
  layers.add(
    Layer(
      id: rootId,
      name: displayName,
      kind: LayerKind.folder,
      frames: const [],
      timeline: SplayTreeMap<int, TimelineExposure>(),
    ),
  );

  return PsdExpandPlan(
    layers: layers,
    placements: placements,
    warnings: warnings,
  );
}

LayerBlendMode _blendFor(PsdLayer source, List<String> warnings) {
  final mapped = psdBlendModes[source.blendKey];
  if (mapped != null) {
    return mapped;
  }
  warnings.add(
    '${source.name}: blend mode "${source.blendKey.trim()}" has no '
    'equivalent — set to normal.',
  );
  return LayerBlendMode.normal;
}
