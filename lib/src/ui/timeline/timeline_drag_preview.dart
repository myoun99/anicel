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
import '../../models/track.dart';
import '../../models/track_id.dart';
import '../../models/track_transitions.dart';
import '../../models/transform_track.dart';
import '../../services/project_repository.dart';
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

  /// Track-owned rows only (UI-R7 #7 — the SE rows, and the transition row
  /// since 2026-09-25): the GLOBAL-axis form of the dragged layer.
  /// [previewLayer] carries the active-cut display clone for the timeline
  /// row gates; the storyboard's track-global strips render THIS one. Null
  /// for cut-owned layers (both forms are the same).
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

  /// Track-owned moves only (C2 2026-08-17 — the SE rows, and the
  /// transition row since 2026-09-25): the GLOBAL-axis form of each moved
  /// track-owned layer — the same second form [ExposureEdgeDragPreview] has
  /// always carried for its edge drags, so the storyboard's track-global
  /// strips follow a MOVE live exactly as they follow a comma drag.
  /// [previewLayers] keeps the active-cut display clones for the timeline
  /// row gates; cut-owned layers appear only there (both forms are the
  /// same).
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

/// A LANE EDIT in flight (F-195): one row's keyed values as the release
/// would leave them — a value scrubbed on a lane's label, a canvas handle
/// dragged, a key range slid along a lane.
///
/// 유저 2026-09-27: 「카메라레이어든 트랜스폼이든 fx든 다 편집이 실시간으로
/// 화면에 보이도록. 레이어에서 값편집이든 캔버스에서 편집이든」. Each of those
/// held its value in the widget being dragged — a label's text, a handle's
/// offset, a box's zoom, the camera frame's pose — and nothing else saw it
/// until the release. The value in flight lives HERE, and whatever shows the
/// row reads it: every panel's lane labels and key markers (the row gates),
/// the editing canvas's picture and pose, the handles, the camera frame.
///
/// ⛔ITS OWN VARIANT, not a [BlockMoveDragPreview] (which carried the lane
/// moves until F-195): the lane verbs drop only their own preview
/// (`LaneVerbs.endLaneEditPreview`), and the camera takes a lane edit's
/// track straight off it (`Camera.activeCutCameraTrack`).
/// ↩️It was split off so the canvas could follow a lane edit and NOT a block
/// move — the row being drawn on shows the cel the brush holds, so a canvas
/// following a block move showed half of it. 유저 2026-09-28 answered
/// 「따라가게 — 끄는 동안 캔버스도 바뀐다」 (canvas-follows-block-moves): the
/// canvas follows every drag now ([cutShowingDragPreview]) and stands that
/// row down as an image while a drag moves its cel (`EditingStackMap`).
///
/// Exactly one subject is set — a ROW ([row], with [globalRow] for a
/// track-owned one), a V TRACK's chain ([trackId]) or the open cut's CAMERA
/// ([cameraCutId]) — because a lane lives on exactly one of them.
class LaneEditPreview extends TimelineDragPreview {
  /// [row] as the open cut shows it — a track-owned row's cut-local display
  /// clone, whose [globalRow] is the track's own (the pair
  /// `TrackSeDisplay.previewFormsOf` decides).
  const LaneEditPreview.row({required Layer this.row, this.globalRow})
    : trackId = null,
      trackEffects = null,
      cameraCutId = null,
      cameraTrack = null,
      cameraMarkerLayer = null;

  /// A V track's EFFECT chain — all a track row's lanes edit.
  const LaneEditPreview.track({
    required TrackId this.trackId,
    required List<LayerEffect> this.trackEffects,
  }) : row = null,
       globalRow = null,
       cameraCutId = null,
       cameraTrack = null,
       cameraMarkerLayer = null;

  /// [cameraCutId]'s camera track. The camera row's lanes are built from
  /// the CUT, not from the row's Layer, so a clone of the row rides along
  /// ([cameraMarkerLayer]) only to trip that row's gate — a FRESH one per
  /// step, since the gate compares identities (the P3b-2 contract).
  const LaneEditPreview.camera({
    required CutId this.cameraCutId,
    required TransformTrack this.cameraTrack,
    this.cameraMarkerLayer,
  }) : row = null,
       globalRow = null,
       trackId = null,
       trackEffects = null;

  final Layer? row;
  final Layer? globalRow;
  final TrackId? trackId;
  final List<LayerEffect>? trackEffects;
  final CutId? cameraCutId;
  final TransformTrack? cameraTrack;
  final Layer? cameraMarkerLayer;

  @override
  bool operator ==(Object other) =>
      other is LaneEditPreview &&
      other.row == row &&
      other.globalRow == globalRow &&
      other.trackId == trackId &&
      listEquals(other.trackEffects, trackEffects) &&
      other.cameraCutId == cameraCutId &&
      other.cameraTrack == cameraTrack &&
      identical(other.cameraMarkerLayer, cameraMarkerLayer);

  @override
  int get hashCode => Object.hash(
    row,
    globalRow,
    trackId,
    trackEffects == null ? null : Object.hashAll(trackEffects!),
    cameraCutId,
    cameraTrack,
    identityHashCode(cameraMarkerLayer),
  );
}

/// The lane edit in flight on [preview]'s channel, or null.
LaneEditPreview? laneEditInFlight(TimelineDragPreview? preview) =>
    preview is LaneEditPreview ? preview : null;

/// [layers] as they show while [preview] is in flight: every row the drag
/// previews in the form a timeline row paints ([timelineDragPreviewLayerFor]
/// — a track-owned row's cut-local clone), every other row as it is. The
/// same list back when the drag touches none of them.
///
/// ★ONE substitution for every drag — a block, a comma, several rows, a file
/// pushing its neighbours, a lane value. The canvas asking a function of its
/// own is how it came to follow the lane edits alone.
List<Layer> layersShowingDragPreview(
  List<Layer> layers,
  TimelineDragPreview? preview,
) => preview == null
    ? layers
    : _layersShowing(
        layers,
        (layerId) => timelineDragPreviewLayerFor(preview, layerId),
      );

/// The same for a track's OWN rows on the global axis (its SE rows, its
/// transition row): each previewed row in its GLOBAL form
/// ([timelineDragPreviewGlobalLayerFor]).
List<Layer> globalLayersShowingDragPreview(
  List<Layer> layers,
  TimelineDragPreview? preview,
) => preview == null
    ? layers
    : _layersShowing(
        layers,
        (layerId) => timelineDragPreviewGlobalLayerFor(preview, layerId),
      );

List<Layer> _layersShowing(
  List<Layer> layers,
  Layer? Function(LayerId layerId) shownFor,
) {
  List<Layer>? shown;
  for (var i = 0; i < layers.length; i++) {
    final row = shownFor(layers[i].id);
    if (row != null && !identical(row, layers[i])) {
      (shown ??= List.of(layers))[i] = row;
    }
  }
  return shown ?? layers;
}

/// [cut] as the editing canvas shows it while [preview] is in flight — the
/// rows the drag previews substituted in ([layersShowingDragPreview]).
/// Display only: the repository never sees it. [cut] itself when the drag
/// touches none of its rows.
///
/// ⛔Not the camera. The picture and the pen's space read no camera; the
/// camera's readers (its frame on the canvas, its lanes, its marks) take the
/// one camera answer, `Camera.activeCutCameraTrack`, which reads this
/// channel itself — a second camera here would be a copy nobody reads.
Cut cutShowingDragPreview(Cut cut, TimelineDragPreview? preview) {
  final layers = layersShowingDragPreview(cut.layers, preview);
  return identical(layers, cut.layers) ? cut : cut.copyWith(layers: layers);
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

/// [drawn] as its release will leave the rows: the project it previews,
/// settled the way the write settles it
/// ([ProjectRepository.settledAsWritten]), every row that pass derived
/// again joining the drag's own.
///
/// 🗣️F-227: the のりしろ holds and the conte start an O.L asks of the cuts
/// it joins belong to the write, which reads them off the new layout.
/// Every verb that re-lays the cuts — a front edge, a red end line or the
/// comma it rides, a move — previews through here, or the hand shows one
/// thing and the release another.
CutTrimDragPreview cutTrimPreviewAsReleased(
  ProjectRepository repository,
  CutTrimDragPreview drawn,
) {
  final draft = _projectWithCutTrimPreview(repository.requireProject(), drawn);
  final derived = _rowsDerivedAgain(
    draft,
    repository.settledAsWritten(draft),
  );
  return derived.isEmpty
      ? drawn
      : CutTrimDragPreview(
          previewDurations: drawn.previewDurations,
          previewGaps: drawn.previewGaps,
          previewOrder: drawn.previewOrder,
          previewLayers: {...drawn.previewLayers, ...derived},
        );
}

/// The cut rows [settled] holds as other instances than [draft] does. The
/// settle maps tracks and cuts in place, so the two walk side by side.
Map<LayerId, Layer> _rowsDerivedAgain(Project draft, Project settled) {
  final derived = <LayerId, Layer>{};
  for (var t = 0; t < settled.tracks.length; t += 1) {
    final drafted = draft.tracks[t].cuts;
    final cuts = settled.tracks[t].cuts;
    for (var c = 0; c < cuts.length; c += 1) {
      if (identical(cuts[c], drafted[c])) {
        continue;
      }
      final before = {for (final layer in drafted[c].layers) layer.id: layer};
      for (final layer in cuts[c].layers) {
        if (!identical(layer, before[layer.id])) {
          derived[layer.id] = layer;
        }
      }
    }
  }
  return derived;
}

/// A movie-end drag in flight (UI-R20 #3): the previewed TRAILING GAP —
/// the storyboard's end line, its grip and its ruler's end line all read it
/// through `timelineCutEndPreviewFrameCount`, so the three follow the pointer
/// live together (F-18).
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
  if (preview is LaneEditPreview) {
    // The camera row's marker, as for a block move: its lanes re-derive
    // through the session's camera track, which reads this same preview.
    if (preview.cameraMarkerLayer?.id == layerId) {
      return preview.cameraMarkerLayer;
    }
    return preview.row?.id == layerId ? preview.row : null;
  }
  return null;
}

/// The EFFECT chain [preview] shows for [trackId]'s V row, or null when it
/// does not touch that track — a block move carrying the chain's keys, or a
/// lane edit of one of its values.
List<LayerEffect>? timelineDragPreviewTrackEffectsFor(
  TimelineDragPreview? preview,
  TrackId trackId,
) => switch (preview) {
  BlockMoveDragPreview(:final previewTrackEffects) =>
    previewTrackEffects?[trackId],
  LaneEditPreview(trackId: final edited, :final trackEffects)
      when edited == trackId =>
    trackEffects,
  _ => null,
};

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
  if (preview is LaneEditPreview && preview.row?.id == layerId) {
    return preview.globalRow;
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
      for (final track in project.tracks) _trackWithCutTrimPreview(track, trim),
    ],
  );
  return trim.previewLayers.isEmpty
      ? resized
      : _projectWithLayersSubstituted(resized, trim.previewLayers);
}

/// One track under a cut edge drag — and its transition row carried the way
/// the release will carry it (`TransitionsRideTheCuts`, 유저 2026-08-10:
/// 「움직일때만 앵커로서 앞 컷에 앵커」 · 2026-09-30: 「경계를 따라간다」): the
/// same function, so an O.L follows the boundary it crosses under the hand
/// rather than jumping there on release.
Track _trackWithCutTrimPreview(Track track, CutTrimDragPreview trim) {
  final moved = track.copyWith(
    cuts: _previewOrdered(track.cuts, trim.previewOrder[track.id])
        .map(
          (cut) =>
              trim.previewDurations.containsKey(cut.id) ||
                  trim.previewGaps.containsKey(cut.id)
              ? cut.copyWith(
                  duration: trim.previewDurations[cut.id] ?? cut.duration,
                  leadingGapFrames:
                      trim.previewGaps[cut.id] ?? cut.leadingGapFrames,
                )
              : cut,
        )
        .toList(growable: false),
  );
  return moved.copyWith(
    transitionLayer: transitionRowFollowingItsCuts(before: track, after: moved),
  );
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
    case final LaneEditPreview edit:
      // The edited row, its track's chain or its cut's camera — reaching the
      // project views the way a block move's rows and camera keys do.
      final row = edit.row;
      final withRow = row == null
          ? project
          : _projectWithLayersSubstituted(project, {row.id: row});
      final trackId = edit.trackId;
      final trackEffects = edit.trackEffects;
      if (trackId != null && trackEffects != null) {
        return updateTrackById(
              withRow,
              trackId,
              (track) => track.copyWith(effects: trackEffects),
            ) ??
            withRow;
      }
      final cutId = edit.cameraCutId;
      final cameraTrack = edit.cameraTrack;
      if (cutId == null || cameraTrack == null) {
        return withRow;
      }
      return updateCutAnywhere(
            withRow,
            cutId,
            (cut) => cut.copyWith(camera: CutCamera.fromTrack(cameraTrack)),
          ) ??
          withRow;
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
              if (cut.layers.any(
                (layer) => previewLayers.containsKey(layer.id),
              ))
                cut.copyWith(
                  layers: [
                    for (final layer in cut.layers)
                      previewLayers[layer.id] ?? layer,
                  ],
                )
              else
                cut,
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
    this.slice,
  });

  /// What of the layer this row SHOWS: a preview rebuilds the row only when
  /// this answer changes (by identity) or the silhouette moves —
  /// `SlicedListenableBuilder`'s rule for a row. A lane row answers with its own lane (`laneRowSlice`), so a
  /// value scrubbed on one lane stops rebuilding every other row of its
  /// layer (F-195). Null = the whole layer, which is every row's answer
  /// until it states a narrower one.
  final Object Function(Layer layer)? slice;

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

  /// The cells a hovering file would author on this row
  /// ([timelineDragSilhouetteFor]) — the OTHER thing a row draws from the
  /// preview, so the other thing that rebuilds it.
  ///
  /// 🚨Watched only the row's preview LAYER, the gate kept a silhouette that
  /// came with no preview row off the screen: a sound over an SE row's empty
  /// cell and a file over a reference row (I-47) hand over the span alone,
  /// because nothing on the row moves — and the row never rebuilt to draw it.
  ({int startIndex, int endIndexExclusive})? _silhouette;

  @override
  void initState() {
    super.initState();
    widget.dragPreview?.addListener(_handlePreviewChanged);
    _previewLayer = _resolvePreviewLayer();
    _silhouette = _resolveSilhouette();
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
    _silhouette = _resolveSilhouette();
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

  /// Track-global hosts draw no silhouette ([timelineDragSilhouetteFor] is
  /// the active-cut rows' question).
  ({int startIndex, int endIndexExclusive})? _resolveSilhouette() =>
      widget.useGlobalForm
      ? null
      : timelineDragSilhouetteFor(widget.dragPreview?.value, widget.layer.id);

  void _handlePreviewChanged() {
    final next = _resolvePreviewLayer();
    final silhouette = _resolveSilhouette();
    if (identical(next, _previewLayer) && silhouette == _silhouette) {
      return;
    }
    final slice = widget.slice;
    final shown = _previewLayer ?? widget.layer;
    final silhouetteMoved = silhouette != _silhouette;
    // Held either way, so any rebuild from elsewhere builds the newest.
    _previewLayer = next;
    _silhouette = silhouette;
    if (!silhouetteMoved &&
        slice != null &&
        identical(slice(next ?? widget.layer), slice(shown))) {
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.rowBuilder(context, _previewLayer ?? widget.layer);
  }
}
