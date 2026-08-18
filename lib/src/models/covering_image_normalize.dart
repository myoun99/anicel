import 'cut.dart';
import 'layer.dart';
import 'layer_kind.dart';
import 'timeline_exposure.dart';
import 'timeline_repeat.dart';

/// [cut] with every IMAGE layer's stored timeline normalized to the D22
/// form: ONE real 1-frame block at index 0 plus a FIXED end-side HOLD
/// ([TimelineRunBehavior]) whose ghosts fill to the cut boundary — 「블록은
/// 1칸 + 성질 hold 고정」 (유저 2026-08-17). One picture simply exists
/// throughout, and the row SAYS so: a single cell, then the dim hold
/// dashes every other row uses for the same statement.
///
/// The storyboard row absorbs cut-length changes at read time (its
/// coverage is derived); the image row has no derived reader — the
/// timeline grid, the composite and every thumbnail paint its STORED
/// exposures — so the store itself must follow the cut. Running as a
/// repository-write normalization (the always-mirror precedent) covers
/// every duration path at once: trims, strip drags, undo/redo replay,
/// file load. Because the ghost pass (`_withDerivedRunEdges`) only runs
/// on specific verbs, THIS normalization derives its own ghosts inline
/// ([rederiveRunBehaviors] — identity-preserving when nothing changed),
/// so any write leaves the image row fully shaped: real cell + hold
/// ghosts, no matter which verb wrote.
///
/// Coverage is unchanged: `exposedFrameIdAt` resolves ghost cells to
/// their anchor, so playback, thumbnails and the composite still show
/// the picture on every frame. Old covering-form files reshape on their
/// first write. A layer with no cel yet stays empty (nothing to hold).
/// Identity-preserving on no-ops so unchanged cuts pass through
/// untouched.
Cut cutWithCoveringImageRows(Cut cut) {
  List<Layer>? nextLayers;
  final duration = cut.duration < 1 ? 1 : cut.duration;
  for (var i = 0; i < cut.layers.length; i += 1) {
    final layer = cut.layers[i];
    if (!layerKindHoldsSingleCel(layer.kind) || layer.frames.isEmpty) {
      continue;
    }
    // The cel the row holds: the first NON-GHOST drawing the timeline
    // names, else the first cel object (a fresh row whose timeline was
    // never written).
    TimelineExposure? firstReal;
    for (final entry in layer.timeline.entries) {
      if (!entry.value.ghost) {
        firstReal = entry.value;
        break;
      }
    }
    final celId =
        (firstReal != null && firstReal.isDrawing ? firstReal.frameId : null) ??
        layer.frames.first.id;
    final holdSpec = TimelineRunBehavior(
      anchorFrameId: celId,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.hold,
    );
    var realCount = 0;
    for (final entry in layer.timeline.values) {
      if (!entry.ghost) {
        realCount += 1;
      }
    }
    final zeroEntry = layer.timeline[0];
    final shaped =
        realCount == 1 &&
        zeroEntry != null &&
        !zeroEntry.ghost &&
        zeroEntry.isDrawing &&
        zeroEntry.frameId == celId &&
        zeroEntry.length == 1;
    final specced =
        layer.runBehaviors.length == 1 && layer.runBehaviors.first == holdSpec;

    var next = layer;
    if (!shaped || !specced) {
      // Rebuild THROUGH the first real entry when one exists (copyWith
      // keeps its entry-carried metadata — inbetween dots — across
      // duration changes). Ghosts are dropped here; the derive below
      // re-synthesizes them from the fixed spec.
      final entry = firstReal != null && firstReal.isDrawing && !firstReal.ghost
          ? firstReal.copyWith(frameId: celId, length: 1)
          : TimelineExposure.drawing(celId, length: 1);
      next = layer.copyWith(timeline: {0: entry}, runBehaviors: [holdSpec]);
    }
    final derived = rederiveRunBehaviors(next, cutFrameCount: duration);
    if (identical(derived, layer)) {
      continue;
    }
    (nextLayers ??= [...cut.layers])[i] = derived;
  }
  return nextLayers == null ? cut : cut.copyWith(layers: nextLayers);
}
