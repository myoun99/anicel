import '../../services/editing/default_layer_helpers.dart';
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/storyboard_coverage.dart';
import '../../services/commands/update_layer_fill_reference_command.dart';
import '../../services/commands/update_layer_timesheet_command.dart';
import '../../services/project_lookup.dart' show requireLayerAnywhere;
import '../timeline/layer_label_controls.dart' show layerKindShowsBlendControl;
import 'active_cut_controllers.dart';
import 'row_sweep.dart';
import 'session_roles.dart';
import 'storyboard_cursor.dart';

/// THE LAYER SWITCHES — a row's eye, its mute, its audio, its blend mode
/// (one row or many), the all-rows visibility and SE mute, and the
/// target-kind toggle. Each is a command over the layer controller; the
/// session stays the facade that names them.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP
/// cut, Round 6, 2026-09-03). Measured before cutting: nine host methods
/// whose only non-infrastructure fields were the layer controller and the
/// cut command coordinator. It names the roles it needs in its constructor.
class LayerSwitchVerbs {
  LayerSwitchVerbs({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required FrameIds frameIds,
    required ActiveCutControllers controllers,
    required SessionInternals internals,
    required StoryboardCursor storyboardCursor,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _frameIds = frameIds,
       _controllers = controllers,
       _internals = internals,
       _storyboardCursor = storyboardCursor;

  final StoryboardCursor _storyboardCursor;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final ActiveCutControllers _controllers;
  final SessionInternals _internals;

  void toggleLayerVisibility(LayerId layerId) {
    _controllers.layerController.toggleLayerVisibility(layerId);
    _changes.notifyChanged();
  }

  /// Silences/unsilences an SE row's sounds: playback and export skip
  /// muted layers' clips, waveforms keep displaying. An undoable edit, so
  /// the history listener re-uploads a live mix — no refresh of its own.
  void toggleLayerMuted(LayerId layerId) {
    _controllers.layerController.toggleLayerMuted(layerId);
    _changes.notifyChanged();
  }

  /// The SE row's track fader + pan — an undoable edit, like mute.
  void setLayerAudio({required LayerId layerId, double? gain, double? pan}) {
    _controllers.layerController.setLayerAudio(
      layerId: layerId,
      gain: gain,
      pan: pan,
    );
    _changes.notifyChanged();
  }

  /// R26 #30: the layer's composite blend — display state alongside the
  /// eye/static opacity (repo-direct, link-group mirrored).
  void setLayerBlendMode(LayerId layerId, LayerBlendMode blendMode) {
    _controllers.layerController.setLayerBlendMode(
      layerId: layerId,
      blendMode: blendMode,
    );
    _changes.notifyChanged();
  }

  /// R27 #6: the legend's BLEND bulk — the master opacity bar's rule for
  /// the mode. Only rows that actually composite take it (the camera and
  /// the sound/instruction rows have no blend), and only rows that would
  /// change are written, so a no-op pick costs nothing.
  void setBlendModeForLayers(Set<LayerId> layerIds, LayerBlendMode mode) {
    // ⛔ONE undo step for one blend pick, however many rows it lands on.
    final targets = [
      for (final layer in _project.layers)
        if (layerIds.contains(layer.id) &&
            layerKindShowsBlendControl(layer.kind) &&
            layer.blendMode != mode)
          layer.id,
    ];
    if (targets.isNotEmpty) {
      _controllers.layerController.setLayersBlendMode(
        layerIds: targets,
        blendMode: mode,
      );
      _changes.notifyChanged();
    }
  }

  /// Shows or hides every layer of the active cut.
  void setAllLayersVisibility(bool visible) {
    // ⛔ONE undo step for one legend press — the loop used to make one per
    // row, which is 유저's 「일괄로 버튼 조작하고 언두하면 바꼈던 레이어들
    // 다 한번에 언두되야하는데 안됨」 in the place it is easiest to hit.
    _controllers.layerController.setLayersVisible(
      layerIds: [
        for (final layer in _project.layers)
          if (layer.isVisible != visible) layer.id,
      ],
      visible: visible,
    );
    _changes.notifyChanged();
  }

  /// Mutes/unmutes every SE layer of the active cut.
  void setAllSeLayersMuted(bool muted) {
    _controllers.layerController.setLayersMuted(
      layerIds: [
        for (final layer in _project.layers)
          if (layer.kind == LayerKind.se && layer.muted != muted) layer.id,
      ],
      muted: muted,
    );
    _changes.notifyChanged();
  }

  /// The row as the project holds it THIS instant — the one lookup the
  /// three live reads below share (cut-owned rows and track fixtures
  /// alike).
  Layer _rowAnywhere(LayerId layerId) =>
      requireLayerAnywhere(_project.repository.requireProject(), layerId);

  /// Whether [layerId]'s TRANSFORM group is applied right now.
  ///
  /// 🚨A LIVE READ, like [isLayerEyeOn] and [isLayerOnTimesheet]: a lane row
  /// built at the last frame carries a stale `groupEnabled`, and the rail's
  /// bulk-drag has to spread what the press just set.
  bool isLayerTransformOn(LayerId layerId) =>
      _rowAnywhere(layerId).transformEnabled;

  /// Whether [layerId]'s own eye is on RIGHT NOW.
  ///
  /// 🚨A LIVE READ, for the same reason as [isLayerOnTimesheet]: a caller
  /// holding a [Layer] captured at build time reads the value the last frame
  /// had, and the rail's bulk-drag needs the one the press just set.
  bool isLayerEyeOn(LayerId layerId) => _rowAnywhere(layerId).isVisible;

  /// Whether [layerId] is on the timesheet RIGHT NOW.
  ///
  /// 🚨A LIVE READ, and that is the point. A caller holding a [Layer] it
  /// captured at build time reads the value the LAST FRAME had, which stays
  /// wrong for the whole length of a gesture that already toggled it. The
  /// rail's bulk-drag needs the live one: the button under the finger fires
  /// on the DOWN (유저 2026-08-30) and the sweep spreads what that set, so a
  /// snapshot sends it the other way — measured, on one rail in one gesture:
  /// the eye column read live and swept correctly, the sheet column read a
  /// captured layer and swept backwards.
  bool isLayerOnTimesheet(LayerId layerId) =>
      _rowAnywhere(layerId).onTimesheet;

  /// Flips whether [layerId] is recorded on the timesheet output. One undo
  /// step; no controller rebuild — the flag never affects rendering.
  ///
  /// ANYWHERE lookup and a nullable cut (B5③ 2026-08-17): the storyboard
  /// rail reaches this for TRACK fixtures — S rows and the transition row —
  /// whose flag is the layer's own and must flip from a gap too. The cut id
  /// is command bookkeeping the write never reads.
  void toggleLayerTimesheet(LayerId layerId) {
    final layer = _rowAnywhere(layerId);
    _project.cutCommandCoordinator.setLayerTimesheet(
      cutId: _project.activeCutOrNull?.id,
      layerId: layerId,
      onTimesheet: !layer.onTimesheet,
    );
    _changes.notifyChanged();
  }

  /// Flips the layer's FILL-reference flag (R20-C2, the CSP lighthouse) —
  /// what a fill then reads is its reference source's answer (I-36). One
  /// undo step; the display composite never changes.
  void toggleLayerFillReference(LayerId layerId) {
    final layer = _project.layers.firstWhere((layer) => layer.id == layerId);
    _project.cutCommandCoordinator.setLayerFillReference(
      cutId: _project.requireActiveCut.id,
      layerId: layerId,
      isFillReference: !layer.isFillReference,
    );
    _changes.notifyChanged();
  }

  // --- Legend bulk commands (R-toolbar round) -----------------------------
  //
  // One legend-flyout action sweeps every eligible layer of the active cut.
  // Semantics mirror the per-row toggles — and since 2026-08-29 that means
  // UNDOABLE for all of them (유저: 「눈을 껏다키든 뭐든 다 언두」). Every
  // bulk action lands as ONE entry, the way sheet/mark/fill-reference
  // already did.

  /// Turns the timesheet flag on/off for every eligible layer — one undo.
  /// Track-owned rows join the sweep: SE rows since the SE mark/sheet fix,
  /// and the transition row since D31 gave its flag a printed column —
  /// the flag commands resolve through the anywhere lookup.
  void setAllLayersOnTimesheet(bool onTimesheet) {
    final swept = sweepActiveCutRows(
      project: _project,
      description: onTimesheet
          ? 'Add all layers to timesheet'
          : 'Remove all layers from timesheet',
      rows: (cut) => [
        ...cut.layers,
        ..._selection.activeTrack.seLayers,
        _selection.activeTrack.transitionLayer,
      ],
      // The sweep writes the flag on exactly the rows that OWN a switch
      // ([layerCarriesTimesheetToggle], the one law) — it used to spell
      // only half of it, so it flipped folder rows nothing can read or
      // turn back, while D31's transition row and the SE rows keep their
      // place here because their kinds do print.
      commandFor: (cut, layer) =>
          layerCarriesTimesheetToggle(layer) &&
              layer.onTimesheet != onTimesheet
          ? UpdateLayerTimesheetCommand(
              repository: _project.repository,
              cutId: cut.id,
              layerId: layer.id,
              onTimesheet: onTimesheet,
            )
          : null,
    );
    if (swept) {
      _changes.notifyChanged();
    }
  }

  /// Drops the fill-reference flag from every layer — one undo (cut-owned
  /// layers, like the sheet sweep).
  void clearAllFillReferences() {
    final swept = sweepActiveCutRows(
      project: _project,
      description: 'Clear all fill references',
      rows: (cut) => cut.layers,
      commandFor: (cut, layer) => layer.isFillReference
          ? UpdateLayerFillReferenceCommand(
              repository: _project.repository,
              cutId: cut.id,
              layerId: layer.id,
              isFillReference: false,
            )
          : null,
    );
    if (swept) {
      _changes.notifyChanged();
    }
  }

  bool get canToggleTargetLayerKind {
    final targetLayer = _internals.targetLayerForKindToggle;
    // Only the animation ⇄ storyboard pair; other kinds have their own
    // toggles (SE) or are fixed (camera/instruction/attach rows).
    if (targetLayer == null ||
        isAttachedLayer(targetLayer) ||
        targetLayer.kind != LayerKind.animation &&
            targetLayer.kind != LayerKind.storyboard) {
      return false;
    }
    if (targetLayer.kind == LayerKind.storyboard) {
      return true;
    }

    return !_controllers.layerController.layers.any(
      (layer) =>
          layer.id != targetLayer.id && layer.kind == LayerKind.storyboard,
    );
  }

  void toggleTargetLayerKind() {
    final targetLayer = _internals.targetLayerForKindToggle;
    if (targetLayer == null ||
        _storyboardCursor.targetLayerStoryboardRefusal != null) {
      return;
    }

    final toStoryboard = targetLayer.kind != LayerKind.storyboard;
    final nextKind = toStoryboard ? LayerKind.storyboard : LayerKind.animation;

    // A storyboard row TILES its cut, so a row that becomes one is filled
    // to cover before it changes kind — otherwise its holes would show as
    // "X" cells in the timeline while the strip, which reads the coverage
    // rule, showed none. An empty row becomes a fresh blank panel, which
    // is what a new storyboard row is born as.
    if (toStoryboard) {
      final cut = _project.requireActiveCut;
      final filled = storyboardTimelineFilledToCover(
        timeline: targetLayer.timeline,
        cutDuration: cut.duration,
      );
      final covered = filled == null
          ? createStoryboardLayer(
              layerId: targetLayer.id,
              frameId: _frameIds.mintFrameId(targetLayer.id),
              cut: cut,
            ).copyWith(name: targetLayer.name)
          : targetLayer.copyWith(timeline: filled);
      if (covered != targetLayer) {
        _controllers.timelineController.commitLayerTimelineDrag(
          before: targetLayer,
          after: covered,
        );
      }
    }

    _project.cutCommandCoordinator.updateLayerKind(
      cutId: _project.requireActiveCut.id,
      layerId: targetLayer.id,
      kind: nextKind,
    );
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
  }
}
