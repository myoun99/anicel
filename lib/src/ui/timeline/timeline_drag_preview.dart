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
import '../../services/project_tree_editor.dart';
import '../listenable_rebind.dart';
import '../collection_equality.dart';

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
///
/// R4b's per-track transform preview (`previewTrackTransforms`) was declared
/// here in 2026-08 and nothing ever produced or painted it; it went on
/// 2026-09-03. When the storyboard's continuous lane rows get their preview,
/// it comes back with its producer and its painter together.
class BlockMoveDragPreview extends TimelineDragPreview {
  const BlockMoveDragPreview({
    required this.previewLayers,
    this.previewGlobalLayers = const {},
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
      mapOfListsEquals(other.previewTrackEffects, previewTrackEffects) &&
      other.cameraCutId == cameraCutId &&
      mapEquals(other.cameraKeyframes, cameraKeyframes) &&
      identical(other.cameraMarkerLayer, cameraMarkerLayer);

  @override
  int get hashCode => Object.hash(
    mapHash(previewLayers),
    mapHash(previewGlobalLayers),
    mapOfListsHash(previewTrackEffects),
    cameraCutId,
    mapHash(cameraKeyframes),
    identityHashCode(cameraMarkerLayer),
  );
}

/// A FILE from the pool held over the timeline — 「끄는 동안 보이는 것은
/// 놓았을 때 생길 것이다」 (미디어 배치 라운드 2d-2).
///
/// 🚨★★★**THE SILHOUETTE IS NOT A SECOND DRAWING OF A DROP. IT IS THIS
/// CHANNEL.** A file being dragged and a block being dragged show the same
/// thing through the same code: the rows come back from the same planner
/// ([planDrawingRangeMove]), ride the same [TimelineDragPreviewRowGate], and
/// the blocks in the way push LIVE exactly as they do for a block drag
/// (유저 2026-09-12, Q1: 「블록 드래그와 같게 — 밀림까지 실시간」, with
/// 「최대한 법 하나로 통일하면서 기존에있는거 잘 쓰면서」). ⛔A preview of a
/// drop that computed its own push would be that second law.
///
/// What is NEW is MARKED, not drawn by a second painter: [silhouette] names
/// the cells this drop would author, and the row paints those as not-there-
/// yet. Everything else in [previewLayers] is a real cell that moved.
class MediaPlacementPreview extends TimelineDragPreview {
  const MediaPlacementPreview({
    this.previewLayers = const {},
    this.silhouette,
    this.silhouetteRow,
    this.silhouetteSlot,
  });

  /// The rows as the release would leave them — the pushed neighbours
  /// included, since the push is the landing's own plan.
  final Map<LayerId, Layer> previewLayers;

  /// The cells [previewLayers] gained, so the row can paint the ones that
  /// do not exist yet differently from the ones that merely moved.
  final ({LayerId layerId, int startIndex, int endIndexExclusive})? silhouette;

  /// The row this drop would ADD, drawn in the gap the rail's caret marks
  /// (유저 2026-09-12, Q2: 「목업대로 — 실루엣 행을 끼운다」). Null when the
  /// file is over a row rather than between two.
  final Layer? silhouetteRow;

  /// Which gap of the LAYER rows [silhouetteRow] stands in.
  ///
  /// 🚨★★★**DRAWN, NEVER COUNTED.** The gap under the pointer is counted on
  /// the rows WITHOUT this one, and the insert happens where the rows are
  /// BUILT — after the list the entrance reads. Count the inserted row and
  /// every row below it shifts by one under a still pointer, so the gap it
  /// came from is no longer the gap it is over: the caret would jump a row
  /// per pixel. That is the cost the decision named (「포인터를 조금만
  /// 움직여도 선이 한 줄 건너뛰는 떨림」), and this is where it is paid off.
  final int? silhouetteSlot;

  @override
  bool operator ==(Object other) =>
      other is MediaPlacementPreview &&
      mapEquals(other.previewLayers, previewLayers) &&
      other.silhouette == silhouette &&
      other.silhouetteRow == silhouetteRow &&
      other.silhouetteSlot == silhouetteSlot;

  @override
  int get hashCode => Object.hash(
    mapHash(previewLayers),
    silhouette,
    silhouetteRow,
    silhouetteSlot,
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
    this.previewLayers = const {},
  });

  final Map<CutId, int> previewDurations;
  final Map<CutId, int> previewGaps;

  /// Rows re-keyed by the same drag. The storyboard row and its cut's
  /// LENGTH are one thing (design D): shrinking the cut's first panel
  /// shortens the cut, and the row's later divisions come left with it, so
  /// one drag previews both or the picture tears in half mid-drag.
  final Map<LayerId, Layer> previewLayers;

  /// Per track, the cut sequence as the release would leave it. A reorder
  /// carries [previewGaps] too: the gaps stay with their positions, so the
  /// resequenced cuts read the position gaps by their new occupants (see
  /// [planCutMove]).
  final Map<TrackId, List<CutId>> previewOrder;

  @override
  bool operator ==(Object other) =>
      other is CutTrimDragPreview &&
      mapEquals(other.previewDurations, previewDurations) &&
      mapEquals(other.previewGaps, previewGaps) &&
      mapEquals(other.previewLayers, previewLayers) &&
      mapOfListsEquals(other.previewOrder, previewOrder);

  @override
  int get hashCode => Object.hash(
    mapHash(previewDurations),
    mapHash(previewGaps),
    mapOfListsHash(previewOrder),
  );
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
  if (preview is MediaPlacementPreview) {
    // A file held over a row: the row it would land on, pushed neighbours
    // and all. The silhouette cells are IN this layer — what marks them
    // apart is [MediaPlacementPreview.silhouette], read where the row
    // paints, not a second layer to resolve here.
    return preview.previewLayers[layerId];
  }
  if (preview is CutTrimDragPreview) {
    // A storyboard row re-keyed by its cut's edge drag (feedback #5/#9):
    // the timeline row follows the same one preview the strip renders.
    return preview.previewLayers[layerId];
  }
  return null;
}

/// The cells [preview] would AUTHOR on [layerId] — not there yet, and
/// painted as such — or null where this row gains none.
({int startIndex, int endIndexExclusive})? timelineDragSilhouetteFor(
  TimelineDragPreview? preview,
  LayerId layerId,
) {
  if (preview is! MediaPlacementPreview) {
    return null;
  }
  final span = preview.silhouette;
  return span == null || span.layerId != layerId
      ? null
      : (startIndex: span.startIndex, endIndexExclusive: span.endIndexExclusive);
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

/// A CUT EDGE drag's preview substituted into [project]: the trimmed
/// durations and leading gaps, the cuts in the order the release would
/// leave them, and the rows the same drag re-keyed.
///
/// ⚠️Its own function because the dispatch below is a FLAT one — one arm per
/// preview kind, each a line or two — and this arm alone builds a project.
/// Inlined it read as though cut trims were the subject and every other
/// preview an afterthought, and it carried the body past the round's sixty
/// lines when the placement preview joined the switch.
Project _projectWithCutTrimPreview(Project project, CutTrimDragPreview trim) {
  final resized = project.copyWith(
    tracks: [
      for (final track in project.tracks)
        track.copyWith(
          cuts: _previewOrdered(track.cuts, trim.previewOrder[track.id])
              .map(
                (cut) =>
                    trim.previewDurations.containsKey(cut.id) ||
                        trim.previewGaps.containsKey(cut.id)
                    ? cut.copyWith(
                        duration:
                            trim.previewDurations[cut.id] ?? cut.duration,
                        leadingGapFrames:
                            trim.previewGaps[cut.id] ?? cut.leadingGapFrames,
                      )
                    : cut,
              )
              .toList(growable: false),
        ),
    ],
  );
  return trim.previewLayers.isEmpty
      ? resized
      : _projectWithLayersSubstituted(resized, trim.previewLayers);
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
    case final CutTrimDragPreview trim:
      return _projectWithCutTrimPreview(project, trim);
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
      return updateCutAnywhere(
            substituted,
            cameraCutId,
            (cut) =>
                cut.copyWith(camera: CutCamera(keyframes: cameraKeyframes)),
          ) ??
          substituted;
    case MediaPlacementPreview(:final previewLayers):
      // The pushed rows reach the project views the same way a move's do.
      // ⛔The silhouette ROW is not substituted here: it is not a row of
      // this project, and a view that treated it as one would let a drag
      // that never lands leave a layer behind.
      return _projectWithLayersSubstituted(project, previewLayers);
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
    rebindListener(
      oldWidget.dragPreview,
      widget.dragPreview,
      _handlePreviewChanged,
    );
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
