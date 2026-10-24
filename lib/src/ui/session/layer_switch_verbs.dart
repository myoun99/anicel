import '../../services/editing/default_layer_helpers.dart';
import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/storyboard_coverage.dart';
import '../../models/track_transitions.dart' show cutTransitionHandlesIn;
import '../../services/commands/update_layer_clip_command.dart';
import '../../services/commands/update_layer_timesheet_command.dart';
import '../../services/project_lookup.dart'
    show layerAnywhereOrNull, requireLayerAnywhere, rowTwirlsOf;
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
    required StoryboardCursor storyboardCursor,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _frameIds = frameIds,
       _controllers = controllers,
       _storyboardCursor = storyboardCursor;

  final StoryboardCursor _storyboardCursor;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final ActiveCutControllers _controllers;

  void toggleLayerVisibility(LayerId layerId) {
    _controllers.layerController.toggleLayerVisibility(layerId);
    _changes.notifyChanged();
  }

  /// The row's property-lane twirl, and [laneId]'s group inside it — the
  /// row's own, undone as its fold is (F-360). ⚠️No session notify: the
  /// rails read them off the document ([RailView.readFolds]), which every
  /// history change re-reads — as they heard the view's sets before.
  void toggleLayerLanes(LayerId layerId) =>
      _controllers.layerController.twirls.toggleLayerLanes(layerId);

  void setLayerLaneGroupExpanded(
    LayerId layerId,
    String laneId, {
    required bool expanded,
  }) => _controllers.layerController.twirls.setLayerLaneGroupExpanded(
    layerId,
    laneId,
    expanded: expanded,
  );

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

  /// R26 #30: the layer's composite blend — an undoable edit, and its link
  /// group's (`LayerController.setLayerBlendMode`).
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
    //
    // Rows are found ANYWHERE, as every other row button finds them
    // (`SessionRowButtonPresses`): the storyboard's one conte head is some
    // cut's row, pressed under whichever cut is active (I-73). ↩️It walked
    // the active cut's rows, which was every row a blend chip stood on.
    final project = _project.repository.requireProject();
    final targets = [
      for (final id in layerIds)
        if (layerAnywhereOrNull(project, id) case final layer?
            when layerKindShowsBlendControl(layer.kind) &&
                layer.blendMode != mode)
          id,
    ];
    if (targets.isNotEmpty) {
      _controllers.layerController.setLayersBlendMode(
        layerIds: targets,
        blendMode: mode,
      );
      _changes.notifyChanged();
    }
  }

  /// Shows or hides every layer of the active cut — but the camera, whose
  /// eye is the camera view ([LayerKind.hasPictureEye], F-363-Q2).
  void setAllLayersVisibility(bool visible) {
    // ⛔ONE undo step for one legend press — the loop used to make one per
    // row, which is 유저's 「일괄로 버튼 조작하고 언두하면 바꼈던 레이어들
    // 다 한번에 언두되야하는데 안됨」 in the place it is easiest to hit.
    _controllers.layerController.setLayersVisible(
      layerIds: [
        for (final layer in _project.layers)
          if (layer.kind.hasPictureEye && layer.isVisible != visible) layer.id,
      ],
      visible: visible,
    );
    _changes.notifyChanged();
  }

  /// The row as the project holds it THIS instant — the one lookup the
  /// live reads below share (cut-owned rows and track fixtures alike).
  Layer _rowAnywhere(LayerId layerId) =>
      requireLayerAnywhere(_project.repository.requireProject(), layerId);

  /// Whether [layerId]'s property lanes are twirled down right now — the
  /// row's own (F-360), and a V row's, by its lane carrier, its track's
  /// ([rowTwirlsOf]).
  ///
  /// 🚨A LIVE READ, like [isLayerEyeOn]: the legend's twirl-all turns row
  /// after row as ONE step, and the rail's sets are read back off the
  /// document only when the step lands ([RailView.readFolds]) — while a
  /// press spread across the selection may already have turned the next
  /// row, which a stale read would turn back.
  bool isLayerLanesOpen(LayerId layerId) =>
      rowTwirlsOf(_project.repository.requireProject(), layerId)
          ?.lanesExpanded ??
      false;

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

  /// Flips the layer's clip to the layer below (I-92) — one undo step.
  /// ↩️It was the fill's reference flag (R20-C2), which the display
  /// composite never read.
  void toggleLayerClip(LayerId layerId) {
    final layer = _project.layers.firstWhere((layer) => layer.id == layerId);
    _project.cutCommandCoordinator.setLayerClip(
      cutId: _project.requireActiveCut.id,
      layerId: layerId,
      clipsToBelow: !layer.clipsToBelow,
    );
    _changes.notifyChanged();
  }

  // --- Legend bulk commands (R-toolbar round) -----------------------------
  //
  // One legend-flyout action sweeps every eligible layer of the active cut.
  // Semantics mirror the per-row toggles — and since 2026-08-29 that means
  // UNDOABLE for all of them (유저: 「눈을 껏다키든 뭐든 다 언두」). Every
  // bulk action lands as ONE entry, the way sheet/mark/clip
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

  /// Releases every layer's clip — one undo (cut-owned
  /// layers, like the sheet sweep).
  void clearAllClips() {
    final swept = sweepActiveCutRows(
      project: _project,
      description: 'Release all clipping',
      rows: (cut) => cut.layers,
      commandFor: (cut, layer) => layer.clipsToBelow
          ? UpdateLayerClipCommand(
              repository: _project.repository,
              cutId: cut.id,
              layerId: layer.id,
              clipsToBelow: false,
            )
          : null,
    );
    if (swept) {
      _changes.notifyChanged();
    }
  }

  bool get canToggleTargetLayerKind {
    final targetLayer = _selection.activeLayer;
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

    // The cut's ONE conte ([holdsSingletonOfKind]) — the target is not a
    // storyboard row here, so it cannot be the one found.
    return !holdsSingletonOfKind(
      _controllers.layerController.layers,
      LayerKind.storyboard,
    );
  }

  void toggleTargetLayerKind() {
    final targetLayer = _selection.activeLayer;
    if (targetLayer == null ||
        _storyboardCursor.targetLayerStoryboardRefusal != null) {
      return;
    }

    final toStoryboard = targetLayer.kind != LayerKind.storyboard;
    final nextKind = toStoryboard ? LayerKind.storyboard : LayerKind.animation;

    // A storyboard row TILES its cut, so a row that becomes one is filled
    // to cover before it changes kind — otherwise its holes would show as
    // "X" cells in the timeline while the strip, which reads the coverage
    // rule, showed none. An empty row takes a fresh blank panel, which is
    // what a new storyboard row is born with.
    //
    // ↩️It took a whole new storyboard row's place (#752), the row's name
    // carried over and nothing else — what the row wears went, its label
    // first (F-424). The panel is the birth's; the row stays the row.
    if (toStoryboard) {
      final cut = _project.requireActiveCut;
      final filled = storyboardTimelineFilledToCover(
        timeline: targetLayer.timeline,
        cutDuration: cut.duration,
        // The row's drawings stay where they are in the cut's frames; its
        // panels take the conte's timing from where the conte starts in
        // them — after the のりしろ an arriving O.L asks for (F-227).
        conteStart: cutTransitionHandlesIn(
          _project.repository.requireProject(),
          cut.id,
        ).head,
      );
      final blank = filled == null
          ? coveringCelFor(
              frameId: _frameIds.mintFrameId(targetLayer.id),
              cutDuration: cut.duration,
            )
          : null;
      final covered = blank == null
          ? targetLayer.copyWith(timeline: filled)
          : targetLayer.copyWith(
              frames: [blank.frame],
              timeline: blank.timeline,
            );
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
