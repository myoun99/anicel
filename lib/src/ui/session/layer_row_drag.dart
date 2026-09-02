part of '../editor_session_manager.dart';

/// The LAYER ROW DRAG — picking a row up in the rail and dropping it on
/// another row, a track or an effect lane — as its own object: the order
/// drag in flight and the steps of it. The preview the rail paints stays on
/// the session: the UI reads it.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: one field of its own and eight
/// session members touched. It reaches the session through `_session`.
class _LayerRowDrag {
  _LayerRowDrag(this._session);

  final EditorSessionManager _session;

  /// The in-flight row-order drag ([RowOrderDrag]), or null. The plans, the
  /// caret labels and the four commit paths live on the drag class; these
  /// verbs are the session's unchanged face.
  RowOrderDrag? _rowOrderDrag;

  void beginLayerRowDrag(LayerRowDragSubject subject) {
    _rowOrderDrag = RowOrderDrag(
      subject: subject,
      channel: _session.layerRowDrag,
      tracksNow: () => _session._repository.requireProject().tracks,
      effectChainOf: _session._effectsAndFx._effectChainOf,
      trackSeAnywhere: _session._trackSeAnywhere,
      activeCutOrNull: () => _session.activeCutOrNull,
      isTrackSeLayerId: _session.isTrackSeLayerId,
      rowSelectionCarriedBy: _session._rowSelection.rowSelectionCarriedBy,
      trackIdOfTransformLaneCarrier: trackIdOfTransformLaneCarrier,
      mountModeFor: _session._cutCommandCoordinator.mountModeFor,
      commitTrackReorder:
          ({required fromIndex, required toIndex, required trackName}) {
            _session._historyManager.execute(
              ReorderTrackCommand(
                repository: _session._repository,
                fromIndex: fromIndex,
                toIndex: toIndex,
                trackName: trackName,
              ),
            );
            _session._notifyChanged();
          },
      commitTrackEffects: (trackId, effects) => _session.updateTrackEffects(
        trackId,
        effects,
        description: 'Reorder effects',
      ),
      commitLayerEffects:
          ({required cutId, required layerId, required effects}) {
            _session._cutCommandCoordinator.updateLayerEffects(
              cutId: cutId,
              layerId: layerId,
              effects: effects,
              description: 'Reorder effects',
            );
            _session._refreshAfterCutCommand(preferredActiveLayerId: layerId);
            _session._notifyChanged();
          },
      commitSeOrder: ({required trackId, required order}) {
        _session._cutCommandCoordinator.setTrackSeOrder(
          trackId: trackId,
          order: order,
        );
        _session._notifyChanged();
      },
      commitPlacement:
          ({
            required cutId,
            required plan,
            required subjectLayerId,
            required movedIds,
          }) {
            _session._cutCommandCoordinator.setLayerPlacement(
              cutId: cutId,
              order: plan.order,
              folderIds: plan.folderIds,
              movedIds: movedIds,
              // What the caret promised: the move AND the attach change it
              // named, as one undo step because it was one gesture.
              attach: plan.attach,
              description: 'Move layer',
            );
            _session._refreshAfterCutCommand(
              preferredActiveLayerId: subjectLayerId,
            );
            _session._notifyChanged();
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
    String? noticeLabel,
    LayerId? pointerInRow,
  }) => _rowOrderDrag?.updateLayerRow(
    displayLayers,
    slot,
    noticeLabel: noticeLabel,
    pointerInRow: pointerInRow,
  );

  void updateLayerRowDropOnRow(
    List<Layer> displayLayers,
    int slot,
    LayerId targetId,
  ) => _rowOrderDrag?.updateLayerRowDropOnRow(displayLayers, slot, targetId);

  void endLayerRowDrag() {
    final drag = _rowOrderDrag;
    if (drag == null) {
      return;
    }
    // ⚠️Asked BEFORE the commit, because committing is what destroys the fx
    // — and asked off the PLAN, so a drop that mounts nothing never opens a
    // dialog no matter what the dragged rows carry.
    final losing = drag.fxLostByThisDrop();
    if (losing.isEmpty) {
      _rowOrderDrag = null;
      drag.commit();
      return;
    }
    // The drag stays held until the answer arrives: nothing is committed and
    // nothing is discarded while the question is on screen.
    _session.attachFxConfirm.ask(
      rowNames: [for (final layer in losing) layer.name],
      answer: (proceed) {
        _rowOrderDrag = null;
        if (proceed) {
          drag.commit();
        } else {
          drag.cancel();
        }
      },
    );
  }

  void cancelLayerRowDrag() {
    _rowOrderDrag?.cancel();
    _rowOrderDrag = null;
  }
}
