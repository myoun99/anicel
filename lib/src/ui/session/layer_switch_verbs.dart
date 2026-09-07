import '../../services/editing/default_layer_helpers.dart';
import '../../models/attached_layer_resolve.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/storyboard_coverage.dart';
import '../timeline/layer_label_controls.dart' show layerKindShowsBlendControl;
import 'active_cut_controllers.dart';
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
    required ChangeSink changes,
    required FrameIds frameIds,
    required ActiveCutControllers controllers,
    required SessionInternals internals,
    required StoryboardCursor storyboardCursor,
  }) : _project = project,
       _changes = changes,
       _frameIds = frameIds,
       _controllers = controllers,
       _internals = internals,
       _storyboardCursor = storyboardCursor;

  final StoryboardCursor _storyboardCursor;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final ActiveCutControllers _controllers;
  final SessionInternals _internals;

  void toggleLayerVisibility(LayerId layerId) {
    _controllers.layerController.toggleLayerVisibility(layerId);
    _changes.notifyChanged();
  }

  /// Silences/unsilences an SE row's sounds (the mute button — view state
  /// like visibility, not undoable): playback and export skip muted
  /// layers' clips, waveforms keep displaying.
  void toggleLayerMuted(LayerId layerId) {
    _controllers.layerController.toggleLayerMuted(layerId);
    _changes.refreshLiveAudioSchedule();
    _changes.notifyChanged();
  }

  /// The SE row's track fader + pan (mix state like mute, repo-direct).
  void setLayerAudio({required LayerId layerId, double? gain, double? pan}) {
    _controllers.layerController.setLayerAudio(
      layerId: layerId,
      gain: gain,
      pan: pan,
    );
    _changes.refreshLiveAudioSchedule();
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
