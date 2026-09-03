import '../../models/layer.dart';
import '../../models/layer_id.dart';

/// Which layer stands after [deletedLayerId] leaves [beforeLayers]: the row
/// that takes the deleted one's index, the row above it when it was the
/// last, and nothing when the list empties or never held it.
///
/// Lived in the session manager until 2026-09-03 (the audit's Round 6); it
/// is a law over a layer list and touches nothing of the session's.
LayerId? stableLayerIdAfterDeleting({
  required List<Layer> beforeLayers,
  required LayerId deletedLayerId,
}) {
  final deletedIndex = beforeLayers.indexWhere(
    (layer) => layer.id == deletedLayerId,
  );
  if (deletedIndex == -1) {
    return null;
  }

  final remainingLayers = beforeLayers
      .where((layer) => layer.id != deletedLayerId)
      .toList(growable: false);
  if (remainingLayers.isEmpty) {
    return null;
  }
  if (deletedIndex < remainingLayers.length) {
    return remainingLayers[deletedIndex].id;
  }
  return remainingLayers[deletedIndex - 1].id;
}

/// Which layer stands after a list change: a layer the change inserted
/// wins, an active layer the change removed hands off by
/// [stableLayerIdAfterDeleting], and otherwise the active layer keeps its
/// place.
LayerId? preferredLayerAfterLayerListChange({
  required List<Layer> beforeLayers,
  required List<Layer> afterLayers,
  required LayerId? previousActiveLayerId,
}) {
  final afterIds = afterLayers.map((layer) => layer.id).toSet();
  final beforeIds = beforeLayers.map((layer) => layer.id).toSet();
  final insertedLayers = afterLayers
      .where((layer) => !beforeIds.contains(layer.id))
      .toList(growable: false);
  if (insertedLayers.isNotEmpty) {
    return insertedLayers.first.id;
  }

  if (previousActiveLayerId != null &&
      !afterIds.contains(previousActiveLayerId)) {
    return stableLayerIdAfterDeleting(
      beforeLayers: beforeLayers,
      deletedLayerId: previousActiveLayerId,
    );
  }

  return previousActiveLayerId;
}
