part of '../editor_session_manager.dart';

/// THE LAYER SWITCHES — a row's eye, its mute, its audio, its blend mode
/// (one row or many), the all-rows visibility and SE mute, and the
/// target-kind toggle. Each is a command over the layer controller; the
/// session stays the facade that names them.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP
/// cut, Round 6, 2026-09-03). Measured before cutting: nine host methods
/// whose only non-infrastructure fields were the layer controller and the
/// cut command coordinator. It reaches the session through `_session`.
class _LayerSwitchVerbs {
  _LayerSwitchVerbs(this._session);

  final EditorSessionManager _session;

  void toggleLayerVisibility(LayerId layerId) {
    _session._layerController.toggleLayerVisibility(layerId);
    _session._notifyChanged();
  }

  /// Silences/unsilences an SE row's sounds (the mute button — view state
  /// like visibility, not undoable): playback and export skip muted
  /// layers' clips, waveforms keep displaying.
  void toggleLayerMuted(LayerId layerId) {
    _session._layerController.toggleLayerMuted(layerId);
    _session._refreshLiveAudioSchedule();
    _session._notifyChanged();
  }

  /// The SE row's track fader + pan (mix state like mute, repo-direct).
  void setLayerAudio({required LayerId layerId, double? gain, double? pan}) {
    _session._layerController.setLayerAudio(
      layerId: layerId,
      gain: gain,
      pan: pan,
    );
    _session._refreshLiveAudioSchedule();
    _session._notifyChanged();
  }

  /// R26 #30: the layer's composite blend — display state alongside the
  /// eye/static opacity (repo-direct, link-group mirrored).
  void setLayerBlendMode(LayerId layerId, LayerBlendMode blendMode) {
    _session._layerController.setLayerBlendMode(
      layerId: layerId,
      blendMode: blendMode,
    );
    _session._notifyChanged();
  }

  /// R27 #6: the legend's BLEND bulk — the master opacity bar's rule for
  /// the mode. Only rows that actually composite take it (the camera and
  /// the sound/instruction rows have no blend), and only rows that would
  /// change are written, so a no-op pick costs nothing.
  void setBlendModeForLayers(Set<LayerId> layerIds, LayerBlendMode mode) {
    // ⛔ONE undo step for one blend pick, however many rows it lands on.
    final targets = [
      for (final layer in _session.layers)
        if (layerIds.contains(layer.id) &&
            layerKindShowsBlendControl(layer.kind) &&
            layer.blendMode != mode)
          layer.id,
    ];
    if (targets.isNotEmpty) {
      _session._layerController.setLayersBlendMode(
        layerIds: targets,
        blendMode: mode,
      );
      _session._notifyChanged();
    }
  }

  /// Shows or hides every layer of the active cut.
  void setAllLayersVisibility(bool visible) {
    // ⛔ONE undo step for one legend press — the loop used to make one per
    // row, which is 유저's 「일괄로 버튼 조작하고 언두하면 바꼈던 레이어들
    // 다 한번에 언두되야하는데 안됨」 in the place it is easiest to hit.
    _session._layerController.setLayersVisible(
      layerIds: [
        for (final layer in _session.layers)
          if (layer.isVisible != visible) layer.id,
      ],
      visible: visible,
    );
    _session._notifyChanged();
  }

  /// Mutes/unmutes every SE layer of the active cut.
  void setAllSeLayersMuted(bool muted) {
    _session._layerController.setLayersMuted(
      layerIds: [
        for (final layer in _session.layers)
          if (layer.kind == LayerKind.se && layer.muted != muted) layer.id,
      ],
      muted: muted,
    );
    _session._notifyChanged();
  }

  bool get canToggleTargetLayerKind {
    final targetLayer = _session._targetLayerForKindToggle;
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

    return !_session._layerController.layers.any(
      (layer) =>
          layer.id != targetLayer.id && layer.kind == LayerKind.storyboard,
    );
  }

  void toggleTargetLayerKind() {
    final targetLayer = _session._targetLayerForKindToggle;
    if (targetLayer == null || _session.targetLayerStoryboardRefusal != null) {
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
      final cut = _session.requireActiveCut;
      final filled = storyboardTimelineFilledToCover(
        timeline: targetLayer.timeline,
        cutDuration: cut.duration,
      );
      final covered = filled == null
          ? createStoryboardLayer(
              layerId: targetLayer.id,
              frameId: FrameId(_session._nextFrameId(targetLayer.id)),
              cut: cut,
            ).copyWith(name: targetLayer.name)
          : targetLayer.copyWith(timeline: filled);
      if (covered != targetLayer) {
        _session._timelineController.commitLayerTimelineDrag(
          before: targetLayer,
          after: covered,
        );
      }
    }

    _session._cutCommandCoordinator.updateLayerKind(
      cutId: _session.requireActiveCut.id,
      layerId: targetLayer.id,
      kind: nextKind,
    );
    _session._refreshAfterCutCommand();
    _session._notifyChanged();
  }
}
