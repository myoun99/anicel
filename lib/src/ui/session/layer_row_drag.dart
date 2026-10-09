import '../../services/commands/reorder_track_command.dart';
import '../../services/editing/active_cut_helpers.dart' show trackIdOfCut;
import 'drags/row_order_drag.dart';
import '../../models/conte_group.dart'
    show conteGroupOf, conteHeadAt, conteRowAtSeat, conteSeatOf;
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track_conte_row.dart'
    show trackConteRowId, trackConteRowOf;
import '../../models/track_id.dart';
import '../../models/track_transform_lane_carrier.dart';
import 'package:flutter/foundation.dart';

import '../../models/media_asset.dart'
    show MediaAssetKind, mediaAssetKindForPath;
import '../timeline/layer_drop_policy.dart' show newRowInsertionForSlot;
import '../timeline/layer_row_drag.dart'
    show
        ConteSeatRowSubject,
        LayerRowDragState,
        LayerRowDragSubject,
        LayerRowSubject,
        MediaPlacementSubject;
import 'attach_fx_confirm.dart';
import 'session_roles.dart';
import 'row_selection.dart';
import 'effects_and_fx.dart';
import 'standing.dart';
import 'track_se_display.dart';

/// The LAYER ROW DRAG — picking a row up in the rail and dropping it on
/// another row, a track or an effect lane — as its own object: the order
/// drag in flight and the steps of it. The preview the rail paints stays on
/// the session: the UI reads it.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: one field of its own and eight
/// session members touched. It names the roles it needs in its constructor.
class LayerRowDrag {
  LayerRowDrag({
    required ProjectAccess project,
    required ChangeSink changes,
    required AttachFxConfirmController attachFxConfirm,
    required EffectsAndFx effectsAndFx,
    required RowSelection rowSelectionVerbs,
    required TrackSeDisplay trackSe,
    required Standing standing,
  }) : _project = project,
       _changes = changes,
       _attachFxConfirm = attachFxConfirm,
       _effectsAndFx = effectsAndFx,
       _rowSelectionVerbs = rowSelectionVerbs,
       _trackSe = trackSe,
       _standing = standing;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final AttachFxConfirmController _attachFxConfirm;
  final EffectsAndFx _effectsAndFx;
  final RowSelection _rowSelectionVerbs;
  final TrackSeDisplay _trackSe;

  /// Where the rows a conte row's drag re-addressed are followed to
  /// ([Standing.followMovedRows]).
  final Standing _standing;

  /// A storyboard CONTE row's drag in flight (🗣️F-322, 유저 2026-10-09:
  /// 「선택범위 드래그로 어태치 조정」 · 「드래그로 어태치 순서이동」): the cut it
  /// is made in, and the track whose conte rows it moves. Null for every
  /// other drag.
  ///
  /// The rail's conte row is ONE row over every cut, and a seat's rows move
  /// together — the structure law carries a re-order made in one cut to the
  /// others (I-73-one-head-Q2). So the drag is the timeline's drag of that
  /// seat's row in one cut ([_seatMovedIn]): the rows the rail hands it are
  /// that cut's rows at their seats, and what the rail sees held is still
  /// its own row ([RowOrderDrag]'s `drawnAs`).
  ({CutId cutId, TrackId trackId})? _conteSeatDrag;

  /// The in-flight row-order drag ([RowOrderDrag]), or null. The plans, the
  /// caret labels and the four commit paths live on the drag class; these
  /// verbs are the session's unchanged face.
  RowOrderDrag? _rowOrderDrag;

  /// The row drag in flight, as the rails draw it. A notifier rather than a
  /// session notify: a drag moves per pointer step, and the only things
  /// that change are the caret and the lifted row's opacity.
  final ValueNotifier<LayerRowDragState?> inFlight =
      ValueNotifier<LayerRowDragState?>(null);

  void beginLayerRowDrag(LayerRowDragSubject subject) {
    final seat = subject is ConteSeatRowSubject
        ? _seatMovedIn(subject.rowId)
        : null;
    if (subject is ConteSeatRowSubject && seat == null) {
      return; // No cut holds a row at the seat: there is nothing to move.
    }
    _conteSeatDrag = seat == null
        ? null
        : (cutId: seat.cutId, trackId: seat.trackId);
    _rowOrderDrag = RowOrderDrag(
      subject: seat == null ? subject : LayerRowSubject(seat.layerId),
      drawnAs: seat == null ? null : subject,
      channel: inFlight,
      tracksNow: () => _project.repository.requireProject().tracks,
      effectChainOf: _effectsAndFx.effectChainOf,
      trackSeAnywhere: _trackSe.trackSeAnywhere,
      activeCutOrNull: seat == null
          ? () => _project.activeCutOrNull
          : () => _project.cutById(seat.cutId),
      isTrackSeLayerId: _project.isTrackSeLayerId,
      rowSelectionCarriedBy: seat == null
          ? _rowSelectionVerbs.rowSelectionCarriedBy
          : (movingId) => _seatsCarriedBy(seat.cutId, movingId),
      trackIdOfTransformLaneCarrier: trackIdOfTransformLaneCarrier,
      mountModeFor: _project.cutCommandCoordinator.mountModeFor,
      commitTrackReorder:
          ({required fromIndex, required toIndex, required trackName}) {
            _project.historyManager.execute(
              ReorderTrackCommand(
                repository: _project.repository,
                fromIndex: fromIndex,
                toIndex: toIndex,
                trackName: trackName,
              ),
            );
            _changes.notifyChanged();
          },
      commitTrackEffects: (trackId, effects) => _effectsAndFx
          .updateTrackEffects(trackId, effects, description: 'Reorder effects'),
      commitLayerEffects:
          ({required cutId, required layerId, required effects}) {
            _project.cutCommandCoordinator.updateLayerEffects(
              cutId: cutId,
              layerId: layerId,
              effects: effects,
              description: 'Reorder effects',
            );
            _changes.refreshAfterCutCommand(preferredActiveLayerId: layerId);
            _changes.notifyChanged();
          },
      commitSeOrder: ({required trackId, required order}) {
        _project.cutCommandCoordinator.setTrackSeOrder(
          trackId: trackId,
          order: order,
        );
        _changes.notifyChanged();
      },
      commitPlacement:
          ({
            required cutId,
            required plan,
            required subjectLayerId,
            required movedIds,
          }) {
            _project.cutCommandCoordinator.setLayerPlacement(
              cutId: cutId,
              order: plan.order,
              folderIds: plan.folderIds,
              movedIds: movedIds,
              // What the caret promised: the move AND the attach change it
              // named, as one undo step because it was one gesture.
              attach: plan.attach,
              description: 'Move layer',
            );
            _changes.refreshAfterCutCommand(
              preferredActiveLayerId: subjectLayerId,
            );
            _changes.notifyChanged();
          },
    );
  }

  void updateTrackRowDrag(int slot) => _rowOrderDrag?.updateTrackRow(slot);

  void updateEffectRowDrag(
    LayerId layerId,
    List<EffectId> displayEffects,
    int slot,
  ) => _rowOrderDrag?.updateEffectRow(layerId, displayEffects, slot);

  void updateLayerRowDrag(
    List<Layer> displayLayers,
    int slot, {
    LayerId? pointerInRow,
  }) {
    final seat = _conteSeatDrag;
    if (seat == null) {
      _rowOrderDrag?.updateLayerRow(
        displayLayers,
        slot,
        pointerInRow: pointerInRow,
      );
      return;
    }
    final cut = _project.cutById(seat.cutId);
    final rows = cut == null ? null : _seatRowsIn(cut, displayLayers);
    if (cut == null || rows == null) {
      return;
    }
    _rowOrderDrag?.updateLayerRow(
      rows,
      slot,
      pointerInRow: pointerInRow == null
          ? null
          : _seatRowIn(cut, pointerInRow)?.id,
    );
  }

  void updateLayerRowDropOnRow(
    List<Layer> displayLayers,
    int slot,
    LayerId targetId,
  ) {
    // A conte group's rows hold nothing to drop into (its base carries its
    // riders already), so a conte row's drag takes the caret alone.
    if (_conteSeatDrag != null) {
      updateLayerRowDrag(displayLayers, slot);
      return;
    }
    _rowOrderDrag?.updateLayerRowDropOnRow(displayLayers, slot, targetId);
  }

  void endLayerRowDrag() {
    final drag = _rowOrderDrag;
    if (drag == null) {
      return;
    }
    final seat = _conteSeatDrag;
    _conteSeatDrag = null;
    void land() {
      final before = seat == null ? null : _seatsOf(seat.cutId);
      drag.commit();
      if (seat != null && before != null) {
        _standing.followMovedRows(_seatsMoved(seat, before));
      }
    }

    // ⚠️Asked BEFORE the commit, because committing is what destroys the fx
    // — and asked off the PLAN, so a drop that mounts nothing never opens a
    // dialog no matter what the dragged rows carry.
    final losing = drag.fxLostByThisDrop();
    if (losing.isEmpty) {
      _rowOrderDrag = null;
      land();
      return;
    }
    // The drag stays held until the answer arrives: nothing is committed and
    // nothing is discarded while the question is on screen.
    _attachFxConfirm.ask(
      rowNames: [for (final layer in losing) layer.name],
      answer: (proceed) {
        _rowOrderDrag = null;
        if (proceed) {
          land();
        } else {
          drag.cancel();
        }
      },
    );
  }

  void cancelLayerRowDrag() {
    _rowOrderDrag?.cancel();
    _rowOrderDrag = null;
    _conteSeatDrag = null;
  }

  /// The cut a storyboard conte row's drag is made in, and its row at the
  /// seat: the cut the session stands in, where it holds one — the
  /// timeline's own row, so the move shows there as it would have — else
  /// the first cut of the row's track that does (the row's head,
  /// [conteHeadAt]). Null while no cut holds a row at the seat.
  ({CutId cutId, TrackId trackId, LayerId layerId})? _seatMovedIn(
    LayerId rowId,
  ) {
    final address = trackConteRowOf(rowId);
    if (address == null) {
      return null;
    }
    final project = _project.repository.requireProject();
    final active = _project.activeCutOrNull;
    if (active != null &&
        trackIdOfCut(project, active.id) == address.trackId) {
      if (conteRowAtSeat(active, address.seat) case final row?) {
        return (cutId: active.id, trackId: address.trackId, layerId: row.id);
      }
    }
    for (final track in project.tracks) {
      if (track.id == address.trackId) {
        final head = conteHeadAt(track.cuts, address.seat);
        return head == null
            ? null
            : (cutId: head.cut.id, trackId: track.id, layerId: head.row.id);
      }
    }
    return null;
  }

  /// [cut]'s row at the seat the conte row [rowId] names, or null.
  Layer? _seatRowIn(Cut cut, LayerId rowId) =>
      switch (trackConteRowOf(rowId)) {
        final address? => conteRowAtSeat(cut, address.seat),
        null => null,
      };

  /// [displayLayers] — a storyboard rail's conte rows — as [cut]'s rows at
  /// their seats; null when the cut holds no row at one of them: its slots
  /// would not be the rail's, and a group shaped otherwise is left as it is
  /// (the structure law's own answer).
  List<Layer>? _seatRowsIn(Cut cut, List<Layer> displayLayers) {
    final rows = <Layer>[];
    for (final shown in displayLayers) {
      final row = _seatRowIn(cut, shown.id);
      if (row == null) {
        return null;
      }
      rows.add(row);
    }
    return rows;
  }

  /// The rows a conte row's drag carries because they are SELECTED: the
  /// selected conte rows, as [cutId]'s rows at their seats — when [movingId]
  /// is one of them ([RowSelection.rowSelectionCarriedBy]'s rule).
  Set<LayerId> _seatsCarriedBy(CutId cutId, LayerId movingId) {
    final cut = _project.cutById(cutId);
    if (cut == null) {
      return const {};
    }
    final carried = <LayerId>{
      for (final row in _rowSelectionVerbs.rowSelection.value)
        if (row.owningLayerId case final rowId?)
          if (row is LayerRowAddress)
            if (_seatRowIn(cut, rowId) case final layer?) layer.id,
    };
    return carried.contains(movingId) ? carried : const {};
  }

  /// [cutId]'s conte group as each row's seat.
  Map<LayerId, int>? _seatsOf(CutId cutId) {
    final cut = _project.cutById(cutId);
    return cut == null
        ? null
        : {for (final entry in conteGroupOf(cut)) entry.row.id: entry.seat};
  }

  /// The conte rows a landed drag re-addressed: each row of the group whose
  /// seat changed, from its old seat's row to its new one's.
  Map<LayerId, LayerId> _seatsMoved(
    ({CutId cutId, TrackId trackId}) drag,
    Map<LayerId, int> before,
  ) {
    final cut = _project.cutById(drag.cutId);
    if (cut == null) {
      return const {};
    }
    return {
      for (final entry in before.entries)
        if (conteSeatOf(cut, entry.key) case final seat?)
          if (seat != entry.value)
            trackConteRowId(drag.trackId, seat: entry.value):
                trackConteRowId(drag.trackId, seat: seat),
    };
  }

  /// A file from the pool standing over the layer area at the gap [slot] of
  /// [displayLayers]: the caret a moved row raises, raised for the new row
  /// the drop would make — where [newRowInsertionForSlot] says one may go
  /// (「레이어 영역(가로선) → 새 레이어」).
  ///
  /// ⛔Never for a SOUND: round 6 sends a sound from the layer area to the
  /// SE rows by their rule (「소리파일: 추천대로 통일」), so a line at the
  /// pointer would promise a place the sound does not go.
  void showPlacementCaret(List<Layer> displayLayers, int slot, String path) {
    final cut = _project.activeCutOrNull;
    final legal =
        cut != null &&
        mediaAssetKindForPath(path) != MediaAssetKind.audio &&
        newRowInsertionForSlot(
              stack: cut.layers,
              displayRows: displayLayers,
              slot: slot,
            ) !=
            null;
    if (!legal) {
      clearPlacementCaret();
      return;
    }
    inFlight.value = LayerRowDragState(
      subject: const MediaPlacementSubject(),
      caretSlot: slot,
      legal: true,
    );
  }

  /// The file left the layer area, or was let go: its caret goes — and
  /// only its caret, never a row drag's.
  void clearPlacementCaret() {
    if (inFlight.value?.subject is MediaPlacementSubject) {
      inFlight.value = null;
    }
  }
}
