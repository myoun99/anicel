import 'package:flutter/foundation.dart' show ValueNotifier;

import '../../models/attached_layer_resolve.dart';
import '../../models/transform_track.dart';
import '../../models/cut_id.dart';
import '../../models/layer_folder.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/track_id.dart';
import '../../models/transition_geometry.dart';
import '../../services/cut_frame_composite_plan.dart';
import 'active_cut_controllers.dart';
import 'session_roles.dart';
import 'transitions.dart';

/// The OPACITY VERBS — a layer's, several layers' and a track's opacity:
/// what the stack shows, the preview while a slider moves and the commit
/// when it lets go, and the editing fade of the active cut — as their own
/// object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: the rest reads it in two places
/// (the editing canvas stack asking what the stack shows).
class OpacityVerbs {
  OpacityVerbs({
    required ProjectAccess project,
    required ChangeSink changes,
    required ActiveCutControllers controllers,
    required Transitions transitions,
  }) : _project = project,
       _changes = changes,
       _controllers = controllers,
       _transitions = transitions;

  final Transitions _transitions;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final ActiveCutControllers _controllers;

  /// Live opacity-drag preview: per-move values ride this notifier into
  /// the editing canvas only (the dragged FieldSlider echoes locally)
  /// WITHOUT a session notify — the old per-move repo write rebuilt every
  /// panel per pointer move and made the slider feel heavy. Release
  /// commits ONE write + notify. The legend's master bar previews a SET of
  /// rows through the same channel.
  ///
  /// ARCH-session-state: declared by the verbs that write it, as the onion
  /// skin and the frame scrub declare theirs — the session held it and
  /// handed it back through `SessionInternals`.
  final ValueNotifier<({Set<LayerId> layerIds, double opacity})?> dragPreview =
      ValueNotifier(null);

  /// The live V-row opacity drag (per the drag-verb rule): per-move
  /// preview, ONE write on release.
  final ValueNotifier<({TrackId trackId, double opacity})?> trackDragPreview =
      ValueNotifier(null);

  /// The master bar's LAST committed value — the bar rests on this, not a
  /// live average (UI-R6 #2).
  double lastMasterOpacity = 1.0;

  /// ⚠️Both previews: the track's was declared beside the layer's and
  /// never released with it — the session's list named only one.
  void dispose() {
    dragPreview.dispose();
    trackDragPreview.dispose();
  }

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
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return 1;
    }
    final static = trackStaticOpacityForCut(cut.id);
    final start = _project.activeCutGlobalStartFrame;
    return static *
        cutTransitionRampAt(
          cutStart: start,
          cutEnd: start + cut.duration,
          spans: _transitions.activeTrackTransitionSpans,
          globalFrame:
              start +
              (frameIndex ?? _controllers.timelineController.currentFrameIndex),
        );
  }

  /// The track's static opacity as everything should READ it — the live
  /// drag value while one is in flight, the stored value otherwise. The
  /// composite surfaces call the [forCut] form.
  double trackStaticOpacity(TrackId trackId) {
    final dragging = trackDragPreview.value;
    if (dragging != null && dragging.trackId == trackId) {
      return dragging.opacity;
    }
    return _project.trackById(trackId)?.opacity ?? 1.0;
  }

  double trackStaticOpacityForCut(CutId cutId) {
    final owner = _project.trackOwningCut(cutId);
    return owner == null ? 1.0 : trackStaticOpacity(owner.id);
  }

  void previewTrackOpacity(TrackId trackId, double opacity) {
    trackDragPreview.value = (
      trackId: trackId,
      opacity: opacity.clamp(0.0, 1.0).toDouble(),
    );
  }

  void commitTrackOpacity(TrackId trackId, double opacity) {
    trackDragPreview.value = null;
    _project.cutCommandCoordinator.updateTrackDisplay(
      trackId: trackId,
      opacity: opacity.clamp(0.0, 1.0).toDouble(),
      description: 'Track opacity',
    );
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
  }

  void setLayerOpacity({required LayerId layerId, required double opacity}) {
    _controllers.layerController.setLayerOpacity(
      layerId: layerId,
      opacity: opacity,
    );
    _changes.notifyChanged();
  }

  void previewLayerOpacity(LayerId layerId, double opacity) {
    dragPreview.value = (
      layerIds: {layerId},
      opacity: opacity.clamp(0.0, 1.0).toDouble(),
    );
  }

  void commitLayerOpacity(LayerId layerId, double opacity) {
    dragPreview.value = null;
    setLayerOpacity(layerId: layerId, opacity: opacity);
  }

  /// The master-bar preview/commit (R4 #6): [layerIds] = the rows the rail
  /// currently DISPLAYS (filter-passing), computed by the grid. Camera
  /// stays untouched (its slider is the camera-view dim).
  void previewLayersOpacity(Set<LayerId> layerIds, double opacity) {
    dragPreview.value = (
      layerIds: layerIds,
      opacity: opacity.clamp(0.0, 1.0).toDouble(),
    );
  }

  void commitLayersOpacity(Set<LayerId> layerIds, double opacity) {
    dragPreview.value = null;
    final clamped = opacity.clamp(0.0, 1.0).toDouble();
    lastMasterOpacity = clamped;
    // ⛔ONE undo step for one bar drag. The drag itself never reaches here
    // — `previewLayersOpacity` holds it in a notifier and only the release
    // commits — so this is one entry per gesture, not per frame.
    _controllers.layerController.setLayersOpacity(
      layerIds: [
        for (final layer in _project.layers)
          if (layerIds.contains(layer.id) &&
              layer.kind.hasPictureOpacity &&
              layer.opacity != clamped)
            layer.id,
      ],
      opacity: clamped,
    );
    _changes.notifyChanged();
  }

  /// Resets every opacity-bearing layer back to fully opaque. The camera
  /// row's slider is the camera-view DIM (a host notifier), not layer
  /// opacity — it stays untouched.
  void resetAllLayersOpacity() => setAllLayersOpacity(1.0);

  /// Sets every picture-opacity layer's opacity to [opacity] (the legend's
  /// numeric bulk set). Camera stays untouched (its slider is the dim).
  void setAllLayersOpacity(double opacity) {
    final clamped = opacity.clamp(0.0, 1.0).toDouble();
    _controllers.layerController.setLayersOpacity(
      layerIds: [
        for (final layer in _project.layers)
          if (layer.kind.hasPictureOpacity && layer.opacity != clamped)
            layer.id,
      ],
      opacity: clamped,
    );
    _changes.notifyChanged();
  }
}
