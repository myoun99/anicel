part of '../editor_session_manager.dart';

/// The OPACITY VERBS — a layer's, several layers' and a track's opacity:
/// what the stack shows, the preview while a slider moves and the commit
/// when it lets go, and the editing fade of the active cut — as their own
/// object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: the rest reads it in two places
/// (the editing canvas stack asking what the stack shows).
class _OpacityVerbs {
  _OpacityVerbs(this._session);

  final EditorSessionManager _session;

  /// The display opacity the editing stack (and the interactive view's
  /// dimming) uses for [layer]: the shared composite semantics — an attach
  /// layer multiplies its own static opacity with its BASE's animated
  /// Opacity sample (fx shared), a regular layer with its own.
  /// The active row's opacity for a view that draws it ALONE — the
  /// interactive canvas during a ruler scrub, where nothing else composites
  /// it and no folder buffer stands above it.
  ///
  /// 🚨THIS IS NOT `entry.opacity`, and the two must not be unified. An
  /// entry's opacity is BUFFER-RELATIVE: inside a buffering folder it is
  /// 1.0, because the folder node applies the folder's share once to the
  /// composed buffer. A standalone draw has no such buffer, so it needs the
  /// whole chain folded in — which is why the folder factor is here and not
  /// there.
  ///
  /// It used to stop at the row's own opacity, so scrubbing the ruler showed
  /// a row inside a half-opacity folder at FULL row opacity while every
  /// other row honoured the folder. Same shape as the rest of this round:
  /// the active row answered a question differently from everyone else.
  double stackLayerOpacity(Layer layer, List<Layer> layers, int frameIndex) {
    final base = isAttachedLayer(layer) ? attachedBaseOf(layer, layers) : null;
    final fxCarrier = base ?? layer;
    var opacity = layer.opacity;
    // The animated Opacity is a TRANSFORM property, so its own group's
    // switch decides it — not the row master (R8).
    if (fxCarrier.transformEnabled) {
      opacity *= resolveOpacityTrackAt(
        fxCarrier.transformTrack.opacity,
        frameIndex,
      );
    }
    for (final folder in layers.ancestryOf(layer.folderId)) {
      opacity *= resolveFolderOpacityAt(folder: folder, frameIndex: frameIndex);
    }
    return opacity.clamp(0.0, 1.0).toDouble();
  }

  /// The fade the editing canvas (and the scrub preview) shows at
  /// [frameIndex] (default: the playhead).
  ///
  /// The animated half is the TRANSITION row's now (an F.O span thins the cut
  /// toward its end), so this is the track's STATIC opacity times the cut's
  /// own transition ramp. R9 #21 still holds for the static half: it is not an
  /// fx, so the fx bypass does not touch it.
  ///
  /// 🚨The RAMP, not [cutOpacityAt]. That one also answers the compositor's
  /// material question — 0 outside the cut's media range — and the playhead
  /// is unclamped (T12), so standing past the end line handed the fade wash
  /// a 0 and the wash painted an opaque backdrop plate over the paper and
  /// every drawing under it: 「캔버스가 용지나 그림이 사라짐」, with the
  /// paper's antialiased edge peeking past the plate as the stray white
  /// outline. Standing somewhere is not compositing a playlist; the frames
  /// past the end line are ordinary space and only a covering span may thin
  /// them.
  double activeCutEditingFadeOpacity({int? frameIndex}) {
    final cut = _session.activeCutOrNull;
    if (cut == null) {
      return 1;
    }
    final static = trackStaticOpacityForCut(cut.id);
    final start = _session.activeCutGlobalStartFrame;
    return static *
        cutTransitionRampAt(
          cutStart: start,
          cutEnd: start + cut.duration,
          spans: _session.activeTrackTransitionSpans,
          globalFrame:
              start +
              (frameIndex ?? _session.timelineController.currentFrameIndex),
        );
  }

  /// The track's static opacity as everything should READ it — the live
  /// drag value while one is in flight, the stored value otherwise. The
  /// composite surfaces call the [forCut] form.
  double trackStaticOpacity(TrackId trackId) {
    final dragging = _session.trackOpacityDragPreview.value;
    if (dragging != null && dragging.trackId == trackId) {
      return dragging.opacity;
    }
    return _session.trackById(trackId)?.opacity ?? 1.0;
  }

  double trackStaticOpacityForCut(CutId cutId) {
    final owner = _session.trackOwningCut(cutId);
    return owner == null ? 1.0 : trackStaticOpacity(owner.id);
  }

  void previewTrackOpacity(TrackId trackId, double opacity) {
    _session.trackOpacityDragPreview.value = (
      trackId: trackId,
      opacity: opacity.clamp(0.0, 1.0).toDouble(),
    );
  }

  void commitTrackOpacity(TrackId trackId, double opacity) {
    _session.trackOpacityDragPreview.value = null;
    _session.cutCommandCoordinator.updateTrackDisplay(
      trackId: trackId,
      opacity: opacity.clamp(0.0, 1.0).toDouble(),
      description: 'Track opacity',
    );
    _session.refreshAfterCutCommand();
    _session.notifyChanged();
  }

  void setLayerOpacity({required LayerId layerId, required double opacity}) {
    _session.layerController.setLayerOpacity(
      layerId: layerId,
      opacity: opacity,
    );
    _session.notifyChanged();
  }

  void previewLayerOpacity(LayerId layerId, double opacity) {
    _session.opacityDragPreview.value = (
      layerIds: {layerId},
      opacity: opacity.clamp(0.0, 1.0).toDouble(),
    );
  }

  void commitLayerOpacity(LayerId layerId, double opacity) {
    _session.opacityDragPreview.value = null;
    setLayerOpacity(layerId: layerId, opacity: opacity);
  }

  /// The master-bar preview/commit (R4 #6): [layerIds] = the rows the rail
  /// currently DISPLAYS (filter-passing), computed by the grid. Camera
  /// stays untouched (its slider is the camera-view dim).
  void previewLayersOpacity(Set<LayerId> layerIds, double opacity) {
    _session.opacityDragPreview.value = (
      layerIds: layerIds,
      opacity: opacity.clamp(0.0, 1.0).toDouble(),
    );
  }

  void commitLayersOpacity(Set<LayerId> layerIds, double opacity) {
    _session.opacityDragPreview.value = null;
    final clamped = opacity.clamp(0.0, 1.0).toDouble();
    _session.lastMasterOpacity = clamped;
    // ⛔ONE undo step for one bar drag. The drag itself never reaches here
    // — `previewLayersOpacity` holds it in a notifier and only the release
    // commits — so this is one entry per gesture, not per frame.
    _session.layerController.setLayersOpacity(
      layerIds: [
        for (final layer in _session.layers)
          if (layerIds.contains(layer.id) &&
              layerKindHasPictureOpacity(layer.kind) &&
              layer.opacity != clamped)
            layer.id,
      ],
      opacity: clamped,
    );
    _session.notifyChanged();
  }

  /// Resets every opacity-bearing layer back to fully opaque. The camera
  /// row's slider is the camera-view DIM (a host notifier), not layer
  /// opacity — it stays untouched.
  void resetAllLayersOpacity() => setAllLayersOpacity(1.0);

  /// Sets every picture-opacity layer's opacity to [opacity] (the legend's
  /// numeric bulk set). Camera stays untouched (its slider is the dim).
  void setAllLayersOpacity(double opacity) {
    final clamped = opacity.clamp(0.0, 1.0).toDouble();
    _session.layerController.setLayersOpacity(
      layerIds: [
        for (final layer in _session.layers)
          if (layerKindHasPictureOpacity(layer.kind) &&
              layer.opacity != clamped)
            layer.id,
      ],
      opacity: clamped,
    );
    _session.notifyChanged();
  }
}
