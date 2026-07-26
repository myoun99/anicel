import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../models/attached_layer_resolve.dart';
import '../../models/camera_pose.dart';
import '../../models/cut.dart';
import '../../models/cut_camera.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/project.dart';
import '../../models/track_id.dart';

/// The scoped edit-drag preview channel.
///
/// Edge-grip drags (exposure commas, storyboard cut trims) publish their
/// per-step preview HERE — a value-only notifier, never a session notify —
/// so only the widgets that render the dragged thing rebuild per step. The
/// repository stays untouched until the release commits ONE undoable
/// command (the audio-slide R5-⑧ precedent, generalized). This is also the
/// substrate a future cross-layer block drag rides: its ghost/drop preview
/// is one more [TimelineDragPreview] variant.
sealed class TimelineDragPreview {
  const TimelineDragPreview();
}

/// An exposure/instruction edge drag in flight: [previewLayer] is the
/// drag-start snapshot with the cumulative delta applied (idempotent — the
/// session recomputes it per step).
class ExposureEdgeDragPreview extends TimelineDragPreview {
  const ExposureEdgeDragPreview({
    required this.previewLayer,
    this.globalPreviewLayer,
  });

  final Layer previewLayer;

  /// Track-SE drags only (UI-R7 #7): the GLOBAL-axis form of the dragged
  /// layer. [previewLayer] carries the active-cut display clone for the
  /// timeline row gates; the storyboard's track-global SE strips render
  /// THIS one. Null for cut-owned layers (both forms are the same).
  final Layer? globalPreviewLayer;

  LayerId get layerId => previewLayer.id;

  @override
  bool operator ==(Object other) =>
      other is ExposureEdgeDragPreview &&
      other.previewLayer == previewLayer &&
      other.globalPreviewLayer == globalPreviewLayer;

  @override
  int get hashCode => Object.hash(previewLayer, globalPreviewLayer);
}

/// A whole-block move drag in flight (R10-④b): the affected layers with
/// the block relocated — one entry for a same-layer slide, two when the
/// block is crossing onto another layer. Published only while the current
/// pointer position resolves to a LEGAL landing (otherwise the channel
/// clears and the block shows at its committed spot).
class BlockMoveDragPreview extends TimelineDragPreview {
  const BlockMoveDragPreview({
    required this.previewLayers,
    this.cameraCutId,
    this.cameraKeyframes,
    this.cameraMarkerLayer,
  });

  final Map<LayerId, Layer> previewLayers;

  /// KEY-RANGE moves (P3b-2): the previewed CAMERA keyframes for
  /// [cameraCutId] ride along when the selection spans the camera row.
  /// The cells resolve them through the session (exposureStateForLayer
  /// consults the drag's preview keys); [cameraMarkerLayer] is a fresh
  /// clone per step whose only job is tripping the camera row's gate.
  final CutId? cameraCutId;
  final Map<int, CameraPose>? cameraKeyframes;
  final Layer? cameraMarkerLayer;

  @override
  bool operator ==(Object other) =>
      other is BlockMoveDragPreview &&
      mapEquals(other.previewLayers, previewLayers) &&
      other.cameraCutId == cameraCutId &&
      mapEquals(other.cameraKeyframes, cameraKeyframes) &&
      identical(other.cameraMarkerLayer, cameraMarkerLayer);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      previewLayers.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    cameraCutId,
    cameraKeyframes == null
        ? null
        : Object.hashAllUnordered(
            cameraKeyframes!.entries.map((e) => Object.hash(e.key, e.value)),
          ),
    identityHashCode(cameraMarkerLayer),
  );
}

/// A storyboard cut edge drag in flight: the involved cuts' previewed
/// durations (end trims), leading gaps (start slides / gap consumption)
/// and — when a move drag reaches into a neighbour — the previewed ORDER
/// of a track's cuts.
class CutTrimDragPreview extends TimelineDragPreview {
  const CutTrimDragPreview({
    required this.previewDurations,
    this.previewGaps = const {},
    this.previewOrder = const {},
  });

  final Map<CutId, int> previewDurations;
  final Map<CutId, int> previewGaps;

  /// Per track, the cut sequence as the release would leave it. A move
  /// drag resolves to gaps OR to an order, never both: re-timing and
  /// reordering are the two outcomes of one rule (see [planCutMove]).
  final Map<TrackId, List<CutId>> previewOrder;

  @override
  bool operator ==(Object other) =>
      other is CutTrimDragPreview &&
      mapEquals(other.previewDurations, previewDurations) &&
      mapEquals(other.previewGaps, previewGaps) &&
      _orderEquals(other.previewOrder, previewOrder);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      previewDurations.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      previewGaps.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      previewOrder.entries.map(
        (e) => Object.hash(e.key, Object.hashAll(e.value)),
      ),
    ),
  );

  static bool _orderEquals(
    Map<TrackId, List<CutId>> a,
    Map<TrackId, List<CutId>> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (!listEquals(entry.value, b[entry.key])) {
        return false;
      }
    }
    return true;
  }
}

/// A movie-end drag in flight (UI-R20 #3): the previewed TRAILING GAP —
/// the storyboard substitutes it into its project view so the end line
/// (and the ruler's content end) follow the pointer live.
class MovieEndDragPreview extends TimelineDragPreview {
  const MovieEndDragPreview({required this.trailingFrames});

  final int trailingFrames;

  @override
  bool operator ==(Object other) =>
      other is MovieEndDragPreview && other.trailingFrames == trailingFrames;

  @override
  int get hashCode => trailingFrames.hashCode;
}

/// The preview layer for [layerId], or null when [preview] does not target
/// it.
Layer? timelineDragPreviewLayerFor(
  TimelineDragPreview? preview,
  LayerId layerId,
) {
  if (preview is ExposureEdgeDragPreview && preview.layerId == layerId) {
    return preview.previewLayer;
  }
  if (preview is BlockMoveDragPreview) {
    // The camera MARKER (P3b-2): a fresh clone per step trips the camera
    // row's gate; the cells re-derive through the session's preview keys.
    if (preview.cameraMarkerLayer?.id == layerId) {
      return preview.cameraMarkerLayer;
    }
    return preview.previewLayers[layerId];
  }
  return null;
}

/// The GLOBAL-axis preview layer for [layerId] (track-global hosts — the
/// storyboard SE strips), or null when [preview] does not target it or
/// carries no global form.
Layer? timelineDragPreviewGlobalLayerFor(
  TimelineDragPreview? preview,
  LayerId layerId,
) {
  if (preview is ExposureEdgeDragPreview && preview.layerId == layerId) {
    return preview.globalPreviewLayer;
  }
  return null;
}

/// [cuts] resequenced to [order], ignoring ids the track no longer holds
/// and keeping any cut the order forgot at the end (the preview must never
/// make a cut disappear).
List<Cut> _previewOrdered(List<Cut> cuts, List<CutId>? order) {
  if (order == null || order.isEmpty) {
    return cuts;
  }
  final byId = {for (final cut in cuts) cut.id: cut};
  final resequenced = <Cut>[
    for (final id in order)
      if (byId.remove(id) case final Cut cut) cut,
  ];
  return [
    ...resequenced,
    for (final cut in cuts)
      if (byId.containsKey(cut.id)) cut,
  ];
}

/// A project snapshot with an in-flight drag preview substituted in —
/// the storyboard panel renders THIS during a drag so its blocks follow
/// the pointer while the repository stays untouched.
Project projectWithTimelineDragPreview(
  Project project,
  TimelineDragPreview? preview,
) {
  switch (preview) {
    case null:
      return project;
    case CutTrimDragPreview(
      :final previewDurations,
      :final previewGaps,
      :final previewOrder,
    ):
      return project.copyWith(
        tracks: [
          for (final track in project.tracks)
            track.copyWith(
              cuts: _previewOrdered(track.cuts, previewOrder[track.id])
                  .map(
                    (cut) =>
                        previewDurations.containsKey(cut.id) ||
                            previewGaps.containsKey(cut.id)
                        ? cut.copyWith(
                            duration: previewDurations[cut.id] ?? cut.duration,
                            leadingGapFrames:
                                previewGaps[cut.id] ?? cut.leadingGapFrames,
                          )
                        : cut,
                  )
                  .toList(growable: false),
            ),
        ],
      );
    case ExposureEdgeDragPreview(:final previewLayer):
      return _projectWithLayersSubstituted(project, {
        previewLayer.id: previewLayer,
      });
    case BlockMoveDragPreview(
      :final previewLayers,
      :final cameraCutId,
      :final cameraKeyframes,
    ):
      final substituted = _projectWithLayersSubstituted(project, previewLayers);
      if (cameraCutId == null || cameraKeyframes == null) {
        return substituted;
      }
      // The camera keys' preview reaches the project views too (the
      // storyboard/sheet substitution precedent).
      return substituted.copyWith(
        tracks: [
          for (final track in substituted.tracks)
            track.copyWith(
              cuts: [
                for (final cut in track.cuts)
                  cut.id == cameraCutId
                      ? cut.copyWith(
                          camera: CutCamera(keyframes: cameraKeyframes),
                        )
                      : cut,
              ],
            ),
        ],
      );
    case MovieEndDragPreview(:final trailingFrames):
      return project.copyWith(trailingFrames: trailingFrames);
  }
}

Project _projectWithLayersSubstituted(
  Project project,
  Map<LayerId, Layer> previewLayers,
) {
  return project.copyWith(
    tracks: [
      for (final track in project.tracks)
        track.copyWith(
          cuts: [
            for (final cut in track.cuts)
              cut.layers.any((layer) => previewLayers.containsKey(layer.id))
                  ? cut.copyWith(
                      layers: [
                        for (final layer in cut.layers)
                          previewLayers[layer.id] ?? layer,
                      ],
                    )
                  : cut,
          ],
        ),
    ],
  );
}

/// Wraps one grid row (or X-sheet column) so an edge drag rebuilds ONLY
/// the dragged layer's row: the gate listens to the preview channel and
/// re-runs [rowBuilder] with the preview layer substituted while its layer
/// is the drag target — every other row's gate stays silent. Full visual
/// fidelity (block visuals, SE writing, grips) comes for free because the
/// row builds from the substituted layer.
class TimelineDragPreviewRowGate extends StatefulWidget {
  const TimelineDragPreviewRowGate({
    super.key,
    required this.dragPreview,
    required this.layer,
    required this.rowBuilder,
    this.useGlobalForm = false,
  });

  /// The session's preview channel; null renders the base row untouched
  /// (grids hosted without a session, e.g. focused widget tests).
  final ValueListenable<TimelineDragPreview?>? dragPreview;

  /// The row's repository layer (the base when no drag targets it).
  final Layer layer;

  /// Track-global hosts (the storyboard SE strips) pass true: the gate
  /// resolves the GLOBAL-axis preview form instead of the active-cut
  /// display clone (UI-R7 #7).
  final bool useGlobalForm;

  final Widget Function(BuildContext context, Layer layer) rowBuilder;

  @override
  State<TimelineDragPreviewRowGate> createState() =>
      _TimelineDragPreviewRowGateState();
}

class _TimelineDragPreviewRowGateState
    extends State<TimelineDragPreviewRowGate> {
  Layer? _previewLayer;

  @override
  void initState() {
    super.initState();
    widget.dragPreview?.addListener(_handlePreviewChanged);
    _previewLayer = _resolvePreviewLayer();
  }

  @override
  void didUpdateWidget(covariant TimelineDragPreviewRowGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.dragPreview, widget.dragPreview)) {
      oldWidget.dragPreview?.removeListener(_handlePreviewChanged);
      widget.dragPreview?.addListener(_handlePreviewChanged);
    }
    // A parent rebuild mid-drag (or an element re-match after the row
    // window scrolled) must re-derive against the new layer identity.
    _previewLayer = _resolvePreviewLayer();
  }

  @override
  void dispose() {
    widget.dragPreview?.removeListener(_handlePreviewChanged);
    super.dispose();
  }

  Layer? _resolvePreviewLayer() {
    if (widget.useGlobalForm) {
      return timelineDragPreviewGlobalLayerFor(
        widget.dragPreview?.value,
        widget.layer.id,
      );
    }
    final direct = timelineDragPreviewLayerFor(
      widget.dragPreview?.value,
      widget.layer.id,
    );
    if (direct != null) {
      return direct;
    }
    // SYNCED attach rows mirror their BASE live (UI-R20 #8): while a
    // drag previews the base, re-derive the mirrored display timeline
    // from the previewed base so the attach row follows the pointer, not
    // just the release commit. FREE attach rows own their timeline — a
    // base drag must never overwrite it (UI-R21 #3).
    if (!isSyncedAttachedLayer(widget.layer)) {
      return null;
    }
    final baseId = widget.layer.attachedToLayerId;
    if (baseId != null) {
      final previewBase = timelineDragPreviewLayerFor(
        widget.dragPreview?.value,
        baseId,
      );
      if (previewBase != null) {
        return attachedDisplayLayer(attached: widget.layer, base: previewBase);
      }
    }
    return null;
  }

  void _handlePreviewChanged() {
    final next = _resolvePreviewLayer();
    if (identical(next, _previewLayer)) {
      return;
    }
    if (next == null && _previewLayer == null) {
      return;
    }
    setState(() => _previewLayer = next);
  }

  @override
  Widget build(BuildContext context) {
    return widget.rowBuilder(context, _previewLayer ?? widget.layer);
  }
}
