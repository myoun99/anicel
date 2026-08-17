import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../models/attached_layer_resolve.dart';
import '../../models/camera_pose.dart';
import '../../models/cut.dart';
import '../../models/cut_camera.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/project.dart';
import '../../models/track_id.dart';
import '../../models/transform_track.dart';

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
    this.previewGlobalLayers = const {},
    this.previewTrackTransforms,
    this.previewTrackEffects,
    this.cameraCutId,
    this.cameraKeyframes,
    this.cameraMarkerLayer,
  });

  final Map<LayerId, Layer> previewLayers;

  /// Track-SE moves only (C2 2026-08-17): the GLOBAL-axis form of each
  /// moved track-SE layer — the same second form [ExposureEdgeDragPreview]
  /// has always carried for its edge drags, so the storyboard's
  /// track-global SE strips follow a MOVE live exactly as they follow a
  /// comma drag. [previewLayers] keeps the active-cut display clones for
  /// the timeline row gates; cut-owned layers appear only there (both
  /// forms are the same).
  final Map<LayerId, Layer> previewGlobalLayers;

  /// A V-track LANE key move in flight (R4b): the previewed
  /// [Track.transformTrack] per track — the storyboard's continuous lane
  /// rows render this form while the drag rides the carrier route.
  final Map<TrackId, TransformTrack>? previewTrackTransforms;

  /// The same, for a V-track's EFFECT chain. The V row's fx lanes could not
  /// be key-moved at all before 2026-08-08 — the move path looked at a
  /// track's transform and never at its effects, so the drag answered
  /// "nothing to move" and refused in silence — so there was nothing to
  /// preview either.
  final Map<TrackId, List<LayerEffect>>? previewTrackEffects;

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
      mapEquals(other.previewGlobalLayers, previewGlobalLayers) &&
      mapEquals(other.previewTrackTransforms, previewTrackTransforms) &&
      _trackEffectsEqual(other.previewTrackEffects, previewTrackEffects) &&
      other.cameraCutId == cameraCutId &&
      mapEquals(other.cameraKeyframes, cameraKeyframes) &&
      identical(other.cameraMarkerLayer, cameraMarkerLayer);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      previewLayers.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      previewGlobalLayers.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    previewTrackTransforms == null
        ? null
        : Object.hashAllUnordered(
            previewTrackTransforms!.entries.map(
              (e) => Object.hash(e.key, e.value),
            ),
          ),
    previewTrackEffects == null
        ? null
        : Object.hashAllUnordered(
            previewTrackEffects!.entries.map(
              (e) => Object.hash(e.key, Object.hashAll(e.value)),
            ),
          ),
    cameraCutId,
    cameraKeyframes == null
        ? null
        : Object.hashAllUnordered(
            cameraKeyframes!.entries.map((e) => Object.hash(e.key, e.value)),
          ),
    identityHashCode(cameraMarkerLayer),
  );

  /// `mapEquals` compares the LISTS by identity, which a rebuilt chain
  /// never satisfies — the preview would then read as changed on every
  /// step whose keys did not actually move.
  static bool _trackEffectsEqual(
    Map<TrackId, List<LayerEffect>>? a,
    Map<TrackId, List<LayerEffect>>? b,
  ) {
    if (a == null || b == null) {
      return a == b;
    }
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

/// A storyboard cut edge drag in flight: the involved cuts' previewed
/// durations (end trims), leading gaps (start slides / gap consumption)
/// and — when a move drag reaches into a neighbour — the previewed ORDER
/// of a track's cuts.
class CutTrimDragPreview extends TimelineDragPreview {
  const CutTrimDragPreview({
    required this.previewDurations,
    this.previewGaps = const {},
    this.previewOrder = const {},
    this.previewLayers = const {},
  });

  final Map<CutId, int> previewDurations;
  final Map<CutId, int> previewGaps;

  /// Rows re-keyed by the same drag. The storyboard row and its cut's
  /// LENGTH are one thing (design D): shrinking the cut's first panel
  /// shortens the cut, and the row's later divisions come left with it, so
  /// one drag previews both or the picture tears in half mid-drag.
  final Map<LayerId, Layer> previewLayers;

  /// Per track, the cut sequence as the release would leave it. A move
  /// drag resolves to gaps OR to an order, never both: re-timing and
  /// reordering are the two outcomes of one rule (see [planCutMove]).
  final Map<TrackId, List<CutId>> previewOrder;

  @override
  bool operator ==(Object other) =>
      other is CutTrimDragPreview &&
      mapEquals(other.previewDurations, previewDurations) &&
      mapEquals(other.previewGaps, previewGaps) &&
      mapEquals(other.previewLayers, previewLayers) &&
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
  if (preview is CutTrimDragPreview) {
    // A storyboard row re-keyed by its cut's edge drag (feedback #5/#9):
    // the timeline row follows the same one preview the strip renders.
    return preview.previewLayers[layerId];
  }
  return null;
}

/// The GLOBAL-axis preview layer for [layerId] (track-global hosts — the
/// storyboard SE strips), or null when [preview] does not target it or
/// carries no global form.
///
/// C2 (2026-08-17): a BLOCK MOVE answers here too. The storyboard SE rows
/// resolve every drag through this one function, and the move used to be
/// the one drag with no global form — so an edge drag followed the hand
/// live while a move sat still until release, on the same row.
Layer? timelineDragPreviewGlobalLayerFor(
  TimelineDragPreview? preview,
  LayerId layerId,
) {
  if (preview is ExposureEdgeDragPreview && preview.layerId == layerId) {
    return preview.globalPreviewLayer;
  }
  if (preview is BlockMoveDragPreview) {
    return preview.previewGlobalLayers[layerId];
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
      :final previewLayers,
    ):
      final resized = project.copyWith(
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
      return previewLayers.isEmpty
          ? resized
          : _projectWithLayersSubstituted(resized, previewLayers);
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
