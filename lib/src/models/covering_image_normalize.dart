import 'cut.dart';
import 'layer.dart';
import 'layer_kind.dart';
import 'timeline_exposure.dart';

/// [cut] with every IMAGE layer's stored timeline normalized to ONE block
/// covering the whole cut — the covering grammar
/// ([layerKindCoversWithoutGaps]) kept true in STORAGE, not by derivation.
///
/// The storyboard row absorbs cut-length changes at read time (its
/// coverage is derived); the image row has no derived reader — the
/// timeline grid, the composite and every thumbnail paint its STORED
/// exposures — so the store itself must follow the cut. Running as a
/// repository-write normalization (the always-mirror precedent) covers
/// every duration path at once: trims, strip drags, undo/redo replay,
/// file load.
///
/// Pure adds/rewrites of the single entry; a layer with no cel yet stays
/// empty (nothing to hold). Identity-preserving on no-ops so unchanged
/// cuts pass through untouched.
Cut cutWithCoveringImageRows(Cut cut) {
  List<Layer>? nextLayers;
  final duration = cut.duration < 1 ? 1 : cut.duration;
  for (var i = 0; i < cut.layers.length; i += 1) {
    final layer = cut.layers[i];
    if (!layerKindHoldsSingleCel(layer.kind) || layer.frames.isEmpty) {
      continue;
    }
    // The cel the row holds: whatever the timeline names first, else the
    // first cel object (a fresh row whose timeline was never written).
    final firstEntry = layer.timeline.isEmpty
        ? null
        : layer.timeline[layer.timeline.firstKey()];
    final celId =
        (firstEntry != null && firstEntry.isDrawing
            ? firstEntry.frameId
            : null) ??
        layer.frames.first.id;
    final covered =
        layer.timeline.length == 1 &&
        layer.timeline.containsKey(0) &&
        firstEntry != null &&
        firstEntry.isDrawing &&
        firstEntry.frameId == celId &&
        firstEntry.length == duration &&
        !firstEntry.ghost;
    if (covered) {
      continue;
    }
    // Rebuild THROUGH the first entry when one exists (copyWith keeps its
    // entry-carried metadata — inbetween dots — across duration changes;
    // the storyboard fill follows the same discipline).
    final entry = firstEntry != null && firstEntry.isDrawing && !firstEntry.ghost
        ? firstEntry.copyWith(frameId: celId, length: duration)
        : TimelineExposure.drawing(celId, length: duration);
    (nextLayers ??= [...cut.layers])[i] = layer.copyWith(
      timeline: {0: entry},
    );
  }
  return nextLayers == null ? cut : cut.copyWith(layers: nextLayers);
}
