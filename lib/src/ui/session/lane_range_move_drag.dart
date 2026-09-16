import 'drags/lane_range_move_drag.dart';
import '../../models/layer.dart';
import '../../models/transform_track.dart';
import '../../models/layer_kind.dart';
import '../../models/se_name_tag.dart';
import '../../models/timeline_frame_range.dart';
import '../../models/track_transform_lane_carrier.dart';
import '../timeline/timeline_drag_preview.dart';
import 'session_roles.dart';
import 'lane_verbs.dart';
import 'effects_and_fx.dart';

/// The LANE RANGE MOVE DRAG — sliding a selected range of a transform,
/// effect or camera lane along the frames — as its own object: the subject
/// the drag holds, why a drag was refused, the camera lane preview, and the
/// steps of it.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: three fields of its own and
/// fourteen session members touched. It names the roles it needs in
/// its constructor.
class LaneRangeMoveDragVerbs {
  LaneRangeMoveDragVerbs({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required SessionInternals internals,
    required LaneVerbs laneVerbs,
    required EffectsAndFx effectsAndFx,
    required ({Layer shown, Layer? global}) Function(Layer row) previewFormsOf,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _internals = internals,
       _laneVerbs = laneVerbs,
       _effectsAndFx = effectsAndFx,
       _previewFormsOf = previewFormsOf;

  final EffectsAndFx _effectsAndFx;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final SessionInternals _internals;
  final LaneVerbs _laneVerbs;

  /// What the open cut shows of a row — the preview's two forms, the pair
  /// `TrackSeDisplay.previewFormsOf` decides.
  ///
  /// 🚨★★★THE FUNCTION, NOT THE OBJECT (2026-09-16). Two reasons, and the
  /// second is why the first was not enough:
  /// ⛔Taking the VALUE closed a cycle four links long — `trackSe` builds
  ///   `transitions`, `transitions` takes `camera`, `camera` takes
  ///   `laneMove` — so `laneMove` holding `trackSe` made every one of them
  ///   build the next forever, and the first lane-move test died with a
  ///   bare `Stack Overflow`. The session's `late final` members are built
  ///   on first touch, so a value argument is an ORDER constraint.
  /// ⛔Taking a `TrackSeDisplay Function()` fixed the ORDER and left the
  ///   IMPORT: this file still named the class, and
  ///   `no_import_cycles_test` read the same four files as a loop. Asking
  ///   for the one method it calls needs no import at all — the record it
  ///   returns is made of `Layer`, which this file already speaks.
  final ({Layer shown, Layer? global}) Function(Layer row) _previewFormsOf;

  /// The lane range move in flight, or null (UI-R23 #3 part 2). ⛔The only
  /// thing this class keeps about one: the drag-start snapshot and the last
  /// valid shifted payload live on the object and die with the gesture.
  LaneRangeMoveDrag? _laneMoveDrag;

  /// Resolves WHAT a lane selection edits — see [LaneMoveSubject], which
  /// carries the answer and the doc for why there is one resolver.
  ///
  /// ⛔It stays HERE rather than moving with the drag: it reaches into
  /// tracks, layers and the cut's camera, which is this class's map of the
  /// project, not a gesture's.
  LaneMoveSubject? _laneMoveSubjectFor(TimelineLaneSelection selection) {
    // The V TRACK's own lanes (R4b, the carrier route).
    final carrierTrackId = trackIdOfTransformLaneCarrier(selection.layerId);
    if (carrierTrackId != null) {
      final track = _project.trackById(carrierTrackId);
      if (track == null) {
        return null;
      }
      // EFFECT lanes only: the V row has no transform of its own, so a
      // transform key range on it has nothing to move and says so.
      return LaneMoveSubject(
        transformTrack: TransformTrack.empty(),
        effects: track.effects,
        commitTransform: (_) {},
        commitEffects: (next) => _effectsAndFx.updateTrackEffects(
          track.id,
          next,
          description: _laneMoveWhy,
        ),
        previewTransform: (_) => const BlockMoveDragPreview(previewLayers: {}),
        previewEffects: (next) => BlockMoveDragPreview(
          previewLayers: const {},
          previewTrackEffects: {track.id: next},
        ),
      );
    }
    final layer = _laneVerbs.laneVerbLayerFor(selection.layerId);
    if (layer == null || isAttachedLayer(layer)) {
      return null;
    }
    // A CAMERA row's transform lanes ride the CUT's camera track; its fx
    // lanes are still its own. The two answers live in one subject because
    // which one applies is the lane's question, not the row's.
    final isCamera = layer.kind == LayerKind.camera;
    final cameraTrack = isCamera
        ? _project.activeCutOrNull?.camera.track
        : null;
    if (isCamera && cameraTrack == null) {
      return null;
    }
    final isSe = layer.kind == LayerKind.se;
    return LaneMoveSubject(
      transformTrack: cameraTrack ?? layer.transformTrack,
      effects: layer.effects,
      // The name-tag arm (C①): armed only on SE rows (the commit verb
      // throws elsewhere). The subject layer is GLOBAL for track-SE rows
      // ([LaneVerbs.laneVerbLayerFor]), so the commit goes to the coordinator
      // as it is.
      // ↩️It had to go there DIRECTLY: `setSeNameTagForLayer` converted
      // cut-local input on the way in, and routing through it would have
      // shifted track-SE keys twice. F-102 retired that verb — nothing
      // converts on the way in any more.
      seNameTag: isSe ? (layer.seNameTag ?? const SeNameTag()) : null,
      commitSeNameTag: isSe
          ? (next) {
              _project.cutCommandCoordinator.setSeNameTag(
                layerId: layer.id,
                seNameTag: next,
                description: _laneMoveWhy,
              );
              _changes.notifyChanged();
            }
          : null,
      previewSeNameTag: isSe
          ? (next) => _previewOfRow(layer.copyWith(seNameTag: next))
          : null,
      commitTransform: isCamera
          ? (next) => _internals.updateActiveCutCameraTrack(
              next,
              description: _laneMoveWhy,
            )
          : (next) => _internals.updateLayerTransformTrack(
              layer.id,
              next,
              description: _laneMoveWhy,
            ),
      commitEffects: (next) => _effectsAndFx.updateLayerEffects(
        layer.id,
        next,
        description: _laneMoveWhy,
      ),
      previewTransform: isCamera
          // The camera's lanes are built from the SESSION (the cut owns the
          // track, not the row's layer), so its preview is a session field
          // the lane provider reads — see [activeCutCameraTrack]. The
          // marker layer is here only to trip the row's preview gate, the
          // P3b-2 trick — and it must be a FRESH CLONE per step (the P3b-2
          // contract): the gate compares identities, so handing it the
          // repository instance tripped nothing and the camera's rows sat
          // still for the whole drag (B4-②).
          ? (next) => BlockMoveDragPreview(
              previewLayers: const {},
              cameraMarkerLayer: _project.layerById(layer.id)?.copyWith(),
            )
          : (next) => _previewOfRow(layer.copyWith(transformTrack: next)),
      previewEffects: (next) => _previewOfRow(layer.copyWith(effects: next)),
      onPreviewTransform: isCamera
          ? (next) => _cameraLaneTrackPreview = next
          : null,
    );
  }

  /// The step's preview of [row] — the subject row as this step leaves it,
  /// on its OWN axis.
  ///
  /// ⛔ONE for all three arms (transform, effects, name tag). The name-tag
  /// arm was fixed alone (d524af02) and the other two went on publishing
  /// the GLOBAL row into the channel that carries the cut's display clones
  /// — so on any non-first cut every diamond of a moving track-SE row sat a
  /// cut's start to the right for the length of the drag, and the lane's
  /// value column, which reads the global form, did not follow the hand at
  /// all. `TrackSeDisplay.previewFormsOf` decides the pair.
  BlockMoveDragPreview _previewOfRow(Layer row) {
    final forms = _previewFormsOf(row);
    return BlockMoveDragPreview(
      previewLayers: {row.id: forms.shown},
      previewGlobalLayers: {row.id: ?forms.global},
    );
  }

  static const String _laneMoveWhy = 'Move lane keys';

  /// Starts moving the current lane selection; false when there is none or
  /// it covers no keys on ANY spanned lane (nothing to move).
  bool beginLaneRangeMoveDrag() {
    final selection = _selection.laneRangeSelection.value;
    if (selection == null) {
      return false;
    }
    final subject = _laneMoveSubjectFor(selection);
    if (subject == null) {
      return false;
    }
    // ⚠️Assigned only on SUCCESS: a refused begin must not touch a drag
    // already in flight.
    final drag = LaneRangeMoveDrag.begin(
      selection: selection,
      subject: subject,
      laneVerbTargets: _laneVerbs.laneVerbTargets,
      preview: _internals.dragPreview,
      selectionChannel: _selection.laneRangeSelection,
      clearCameraPreview: () => _cameraLaneTrackPreview = null,
    );
    if (drag == null) {
      return false;
    }
    _laneMoveDrag = drag;
    return true;
  }

  /// A lane-move drag step: shifts EVERY spanned lane's ranged keys by
  /// [frameDelta] (R26 #3 — one rigid group, all-or-nothing across lanes)
  /// and previews via [_internals.dragPreview]. A blocked landing HOLDS the last valid
  /// preview (UI-R23 #10 — no snap-back).
  void updateLaneRangeMoveDrag({required int frameDelta}) =>
      _laneMoveDrag?.update(frameDelta: frameDelta);

  /// Commits the lane move as ONE undo step; the selection stays on the
  /// landed span.
  void endLaneRangeMoveDrag() {
    final drag = _laneMoveDrag;
    _laneMoveDrag = null;
    drag?.commit();
  }

  /// Drops an in-flight lane-move preview, restoring the selection.
  void cancelLaneRangeMoveDrag() {
    final drag = _laneMoveDrag;
    _laneMoveDrag = null;
    drag?.cancel();
  }

  /// The CAMERA lane move's in-flight track (see [LaneMoveSubject]).
  ///
  /// A camera row's transform lanes are built from the CUT, not from the
  /// row's own Layer, so the preview cannot ride the layer channel the way
  /// every other row's does — it is parked here and [activeCutCameraTrack]
  /// hands it out. Exactly the shape [Camera.showCameraKeysDragPreview] already uses
  /// for the camera ROW's block move (P3b-2).
  TransformTrack? _cameraLaneTrackPreview;

  /// What [Camera.activeCutCameraTrack] reads first: the lane move's
  /// in-flight camera track, null while no camera lane is moving.
  TransformTrack? get cameraLaneTrackPreview => _cameraLaneTrackPreview;
}
