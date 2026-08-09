import 'cut_id.dart';
import 'layer.dart';
import 'layer_id.dart';
import 'layer_kind.dart';
import 'track_id.dart';

/// Fixture layers: the timesheet's two SE rows (S1·S2) live on the TRACK
/// (global frame axis — sounds may cross cut boundaries), the camera-work
/// instruction row (CAM 1) on each cut. New tracks/cuts create them;
/// [withEnsuredTrackSeLayers] / [withEnsuredSectionLayers] backfill older
/// files on load. Deletion floors (SE ≥ 2, instruction ≥ 1) live in the
/// session and command guards.

/// The legacy cut-scoped SE id (pre-track files); kept for the migration
/// and its fixtures.
LayerId seLayerIdForCut(CutId cutId, int slot) =>
    LayerId('${cutId.value}-se-$slot');

LayerId seLayerIdForTrack(TrackId trackId, int slot) =>
    LayerId('${trackId.value}-se-$slot');

Layer createTrackSeLayer({required TrackId trackId, required int slot}) {
  return Layer(
    id: seLayerIdForTrack(trackId, slot),
    name: 'S$slot',
    frames: const [],
    timeline: const {},
    kind: LayerKind.se,
  );
}

/// Backfills the track's SE floor: at least two SE rows. Existing layers
/// are never touched; missing rows append with the first free S-name.
List<Layer> withEnsuredTrackSeLayers(TrackId trackId, List<Layer> seLayers) {
  if (seLayers.length >= 2) {
    return seLayers;
  }
  final usedIds = seLayers.map((layer) => layer.id).toSet();
  final result = List<Layer>.of(seLayers);
  var slot = 1;
  while (result.length < 2) {
    while (usedIds.contains(seLayerIdForTrack(trackId, slot))) {
      slot += 1;
    }
    result.add(
      createTrackSeLayer(
        trackId: trackId,
        slot: slot,
      ).copyWith(name: nextSeLayerName(result)),
    );
    usedIds.add(seLayerIdForTrack(trackId, slot));
  }
  return result;
}

LayerId transitionLayerIdForTrack(TrackId trackId) =>
    LayerId('${trackId.value}-transitions');

/// The track's ONE transition row (O.L / F.I / F.O …), keyed on the global
/// frame axis like the SE rows beside it.
///
/// ★ ONE row, not a list, and the singleton is load-bearing:
/// [validateInstructionCoverage] already refuses overlapping spans within a
/// layer, so a single row makes "at most one transition per cut boundary"
/// fall out of an invariant that was already enforced — two spans
/// straddling the same boundary would have to overlap.
Layer createTrackTransitionLayer(TrackId trackId) {
  return Layer(
    id: transitionLayerIdForTrack(trackId),
    name: 'TR',
    frames: const [],
    timeline: const {},
    kind: LayerKind.transition,
  );
}

LayerId instructionLayerIdForCut(CutId cutId) =>
    LayerId('${cutId.value}-instructions');

Layer createSeLayer({required CutId cutId, required int slot}) {
  return Layer(
    id: seLayerIdForCut(cutId, slot),
    name: 'S$slot',
    frames: const [],
    timeline: const {},
    kind: LayerKind.se,
  );
}

Layer createInstructionLayer({required CutId cutId, String name = 'CAM 1'}) {
  return Layer(
    id: instructionLayerIdForCut(cutId),
    name: name,
    frames: const [],
    timeline: const {},
    kind: LayerKind.instruction,
  );
}

/// Names an additional instruction row: CAM 2, CAM 3, … skipping names the
/// cut already uses.
String nextInstructionLayerName(List<Layer> layers) {
  final usedNames = layers.map((layer) => layer.name).toSet();
  var index = 1;
  while (true) {
    final name = 'CAM $index';
    if (!usedNames.contains(name)) {
      return name;
    }
    index += 1;
  }
}

/// Names a new TEXT row: T1, T2, … skipping names the cut already uses
/// (the SE scheme's grammar in the drawing section).
String nextTextLayerName(List<Layer> layers) {
  final usedNames = layers.map((layer) => layer.name).toSet();
  var index = 1;
  while (true) {
    final name = 'T$index';
    if (!usedNames.contains(name)) {
      return name;
    }
    index += 1;
  }
}

/// Names a new ADJUSTMENT row: FX1, FX2, … skipping names the cut already
/// uses (R6b). The row's job is its effect chain, so the name is a label,
/// not a cel address.
String nextAdjustmentLayerName(List<Layer> layers) {
  final usedNames = layers.map((layer) => layer.name).toSet();
  var index = 1;
  while (true) {
    final name = 'FX$index';
    if (!usedNames.contains(name)) {
      return name;
    }
    index += 1;
  }
}

/// A fresh ADJUSTMENT row (R6b): no cels, no timeline, no transform — an
/// empty effect chain the user then fills. It filters everything below it
/// in its scope, and until an effect is added that is nothing at all.
Layer createAdjustmentLayer({required LayerId id, required String name}) {
  return Layer(
    id: id,
    name: name,
    frames: const [],
    timeline: const {},
    kind: LayerKind.adjustment,
    // Nothing of its own prints on the sheet.
    onTimesheet: false,
  );
}

/// Names an additional SE row: S1, S2, S3, … skipping names the cut
/// already uses (S1 selected + Add Layer → S3 when S1·S2 exist).
String nextSeLayerName(List<Layer> layers) {
  final usedNames = layers.map((layer) => layer.name).toSet();
  var index = 1;
  while (true) {
    final name = 'S$index';
    if (!usedNames.contains(name)) {
      return name;
    }
    index += 1;
  }
}

/// Backfills the instruction fixture a cut is expected to carry: at least
/// one instruction row. (SE rows moved to the track — see
/// [withEnsuredTrackSeLayers]; the track migration lifts legacy per-cut SE
/// layers.) Existing layers are never touched; the missing fixture is
/// inserted before the camera layer. Idempotent — a cut that already meets
/// the floor comes back unchanged (same list instance).
List<Layer> withEnsuredSectionLayers(CutId cutId, List<Layer> layers) {
  final hasInstruction = layers.any(
    (layer) => layer.kind == LayerKind.instruction,
  );
  if (hasInstruction) {
    return layers;
  }

  final usedIds = layers.map((layer) => layer.id).toSet();
  final additions = <Layer>[];

  if (!hasInstruction) {
    var id = instructionLayerIdForCut(cutId);
    var suffix = 2;
    while (usedIds.contains(id)) {
      id = LayerId('${instructionLayerIdForCut(cutId).value}-$suffix');
      suffix += 1;
    }
    additions.add(
      createInstructionLayer(
        cutId: cutId,
        name: nextInstructionLayerName(layers),
      ).copyWith(id: id),
    );
  }

  final cameraIndex = layers.cameraIndex;
  final result = List<Layer>.of(layers);
  result.insertAll(cameraIndex < 0 ? result.length : cameraIndex, additions);
  return result;
}
