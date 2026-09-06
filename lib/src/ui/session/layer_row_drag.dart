import '../../services/commands/reorder_track_command.dart';
import 'drags/row_order_drag.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/track_transform_lane_carrier.dart';
import '../timeline/layer_row_drag.dart' show LayerRowDragSubject;
import 'session_roles.dart';
import 'row_selection.dart';
import 'effects_and_fx.dart';
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
    required SessionInternals internals,
    required EffectsAndFx effectsAndFx,
    required RowSelection rowSelectionVerbs,
    required TrackSeDisplay trackSe,
  }) : _project = project,
       _changes = changes,
       _internals = internals,
       _effectsAndFx = effectsAndFx,
       _rowSelectionVerbs = rowSelectionVerbs,
       _trackSe = trackSe;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final SessionInternals _internals;
  final EffectsAndFx _effectsAndFx;
  final RowSelection _rowSelectionVerbs;
  final TrackSeDisplay _trackSe;

  /// The in-flight row-order drag ([RowOrderDrag]), or null. The plans, the
  /// caret labels and the four commit paths live on the drag class; these
  /// verbs are the session's unchanged face.
  RowOrderDrag? _rowOrderDrag;

  void beginLayerRowDrag(LayerRowDragSubject subject) {
    _rowOrderDrag = RowOrderDrag(
      subject: subject,
      channel: _internals.layerRowDrag,
      tracksNow: () => _project.repository.requireProject().tracks,
      effectChainOf: _effectsAndFx.effectChainOf,
      trackSeAnywhere: _trackSe.trackSeAnywhere,
      activeCutOrNull: () => _project.activeCutOrNull,
      isTrackSeLayerId: _project.isTrackSeLayerId,
      rowSelectionCarriedBy: _rowSelectionVerbs.rowSelectionCarriedBy,
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
  }) => _rowOrderDrag?.updateLayerRow(
    displayLayers,
    slot,
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
    _internals.attachFxConfirm.ask(
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
