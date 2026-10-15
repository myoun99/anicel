import '../../models/conte_group.dart'
    show conteGroupOf, conteHeadFamilyAt, conteRowAtSeat;
import '../../models/cut.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/project.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track_conte_row.dart';
import '../../models/track_id.dart';

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
/// wins, an active layer the change removed hands off — to [handBackTo]
/// where it is still there, by [stableLayerIdAfterDeleting] otherwise —
/// and otherwise the active layer keeps its place.
///
/// [handBackTo] is the row an undo's edit found the user on (F-350): the
/// undo of a new row hands the stand back to the row it was added from.
LayerId? preferredLayerAfterLayerListChange({
  required List<Layer> beforeLayers,
  required List<Layer> afterLayers,
  required LayerId? previousActiveLayerId,
  LayerId? handBackTo,
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
    if (handBackTo != null && afterIds.contains(handBackTo)) {
      return handBackTo;
    }
    return stableLayerIdAfterDeleting(
      beforeLayers: beforeLayers,
      deletedLayerId: previousActiveLayerId,
    );
  }

  return previousActiveLayerId;
}

/// A storyboard CONTE ROW — or a lane of one — once [before] became
/// [after]: on the seat its rows went to. Every other row comes back as it
/// is; null once its rows are all gone ([conteRowHandedOff]).
///
/// 🗣️F-322: a conte row's address is its SEAT, and an edit that adds,
/// deletes or re-orders its group's rows — or undoes one — puts them on
/// other seats. What stood on the row, or held it selected, follows its
/// rows there, as a timeline row is followed by its id. ↩️Only the rail's
/// drag followed them, so a delete that pulled the seats in left the stand
/// and the selection on a seat their rows had left.
///
/// It goes where the first of them still in a conte group went, in its
/// track's cut order — the row that speaks for it (`conteHeadAt`). A seat
/// no cut held (the conte's own, on a track with no conte yet) has no rows
/// to follow, so it stays.
TimelineRowAddress? conteRowAfterChange(
  TimelineRowAddress row, {
  required Project before,
  required Project after,
}) {
  final conte = _conteRowOf(row);
  if (conte == null) {
    return row;
  }
  final shown = conteHeadFamilyAt(_cutsOf(before, conte.trackId), conte.seat);
  if (shown.isEmpty) {
    return row;
  }
  final seats = _conteSeatsIn(after, conte.trackId);
  for (final layerId in shown) {
    if (seats[layerId] case final seat?) {
      final moved = trackConteRowId(conte.trackId, seat: seat);
      return row is LaneRowAddress
          ? LaneRowAddress(moved, row.laneId)
          : LayerRowAddress(moved);
    }
  }
  return null;
}

/// Where a stand on [row] goes once its rows are all gone
/// ([conteRowAfterChange] null): to the row the timeline's delete hands
/// off to ([stableLayerIdAfterDeleting]) in the group of the cut that spoke
/// for it, among the rows still there — or to the conte's own seat where
/// none is left.
LayerRowAddress conteRowHandedOff(
  TimelineRowAddress row, {
  required Project before,
  required Project after,
}) {
  final conte = _conteRowOf(row)!;
  final seats = _conteSeatsIn(after, conte.trackId);
  for (final cut in _cutsOf(before, conte.trackId)) {
    final gone = conteRowAtSeat(cut, conte.seat);
    if (gone == null) {
      continue;
    }
    final heir = stableLayerIdAfterDeleting(
      // The group in its cut's stack order, bottom first — the order the
      // timeline's hand-off reads a stack in.
      beforeLayers: [
        for (final entry in conteGroupOf(cut).reversed)
          if (entry.row.id == gone.id || seats.containsKey(entry.row.id))
            entry.row,
      ],
      deletedLayerId: gone.id,
    );
    return LayerRowAddress(
      trackConteRowId(conte.trackId, seat: seats[heir] ?? 0),
    );
  }
  return LayerRowAddress(trackConteRowId(conte.trackId));
}

({TrackId trackId, int seat})? _conteRowOf(TimelineRowAddress row) =>
    switch (row) {
      LayerRowAddress(:final layerId) || LaneRowAddress(:final layerId) =>
        trackConteRowOf(layerId),
      TrackRowAddress() => null,
    };

/// Every row of [trackId]'s conte groups in [project], and its seat.
Map<LayerId, int> _conteSeatsIn(Project project, TrackId trackId) => {
  for (final cut in _cutsOf(project, trackId))
    for (final entry in conteGroupOf(cut)) entry.row.id: entry.seat,
};

List<Cut> _cutsOf(Project project, TrackId trackId) {
  for (final track in project.tracks) {
    if (track.id == trackId) {
      return track.cuts;
    }
  }
  return const [];
}
