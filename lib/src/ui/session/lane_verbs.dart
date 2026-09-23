import '../../models/camera_pose.dart';
import '../../models/canvas_point.dart';
import '../../models/transform_track.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/property_track.dart'
    show PropertyKey, PropertyKeyInterpolation;
import '../../models/se_name_tag.dart' show SeNameTag;
import '../../models/timeline_frame_range.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track_transform_lane_carrier.dart';
import '../../services/camera_pose_resolver.dart';
import '../../services/cut_frame_composite_plan.dart';
import '../timeline/effect_lane_editing.dart'
    show
        effectLaneKeyFrames,
        effectsWithEnabledToggled,
        effectsWithGroupReset,
        effectsWithLaneKeyRemoved,
        effectsWithLaneKeyToggled,
        effectsWithLaneKeysInterpolated,
        effectsWithLaneRangeNamed,
        effectsWithLaneValueEdited,
        effectsWithRemoved;
import '../timeline/effect_lane_policy.dart'
    show effectLaneDisplayOrder, parseEffectLaneId;
import '../timeline/transform_lane_editing.dart'
    show
        transformLaneKeyFrames,
        transformTrackWithGroupReset,
        transformTrackWithLaneKeyRemoved,
        transformTrackWithLaneKeyToggled,
        transformTrackWithLaneKeysInterpolated,
        transformTrackWithLaneRangeNamed,
        transformTrackWithLaneValueEdited;
import '../timeline/se_name_tag_lane_editing.dart'
    show seNameTagWithLaneKeyToggled, seNameTagWithLaneValueEdited;
import '../timeline/se_name_tag_lane_policy.dart'
    show laneIsSeNameTag, seNameTagGroupLaneId, seNameTagLaneDisplayOrder;
import '../timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane, transformLaneDisplayOrder;
import '../timeline/timeline_drag_preview.dart'
    show timelineDragPreviewGlobalLayerFor;
import 'active_cut_controllers.dart';
import 'session_roles.dart';
import 'effects_and_fx.dart';

/// The LANE VERBS — what a verb on a transform or effect lane acts on (the
/// targets, the range, the layer and frame behind a lane row), the keys it
/// creates, names, links and removes for the selection, and the commits
/// that write a lane back — as their own object.
///
/// 🚨★★★ONE PROJECTION, BOTH WAYS (F-102, 2026-09-15). 유저: 「글로벌트랙은
/// fx든뭐던 로컬에선 글로벌을 투영해서 보여주도록? 물론 로컬에서도 조작은
/// 가능하지만. 그걸 바탕으로 근본 구조적으로 해결해줘」. A row the TRACK owns
/// is shown in a cut as a projection of the track's row: every write to its
/// keys — the lane navigator's ◆, a typed value, a canvas handle's drag, from
/// either panel — lands on the row the project holds ([laneVerbLayerFor],
/// [_laneVerbFrameAt]), and every value the cut shows is read off that same
/// row at that same frame ([laneValueSourceAt]).
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: no field of its own and eighteen
/// session members touched. It names the roles it needs in its constructor.
class LaneVerbs {
  LaneVerbs({
    required ProjectAccess project,
    required SelectionAccess selection,
    required TimelineAccess timeline,
    required ActiveCutControllers controllers,
    required SessionInternals internals,
    required EffectsAndFx effectsAndFx,
    required ChangeSink changes,
  }) : _project = project,
       _selection = selection,
       _timeline = timeline,
       _controllers = controllers,
       _internals = internals,
       _effectsAndFx = effectsAndFx,
       _changes = changes;

  final EffectsAndFx _effectsAndFx;
  final ChangeSink _changes;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final TimelineAccess _timeline;
  final ActiveCutControllers _controllers;
  final SessionInternals _internals;

  /// The transform track that ALREADY holds [name] in this lane's naming
  /// space, or null when the name is free there.
  ///
  /// A LAYER row's space spans its 겸용 link group — the camera row's too,
  /// since it keeps the transform law (F-84, 2026-09-11). A V row's does
  /// not: a V track is held once, so there is no second use site for a name
  /// to reach.
  /// [excludeFrames] are the keys a RANGE rename is about to name: they are
  /// the ones joining, so they must not be found as the holder.
  TransformTrack? _laneTransformHoldingName(
    Layer layer,
    TransformPropertyId property,
    String name, {
    Set<int> excludeFrames = const {},
  }) {
    final track = _laneTransformTrackOf(layer);
    if (transformLaneUsesName(
      track,
      property,
      name,
      excludeFrames: excludeFrames,
    )) {
      return track;
    }
    final cutId = _timeline.editingSession.activeCutId;
    if (cutId == null || trackIdOfTransformLaneCarrier(layer.id) != null) {
      return null;
    }
    return _project.cutCommandCoordinator.transformTrackHoldingName(
      cutId: cutId,
      layerId: layer.id,
      property: property,
      name: name,
      excludeFramesOnSource: excludeFrames,
    );
  }

  /// The lane-selection create (UI-R25 #3): a key frozen at the resolved
  /// The lanes a VERB acts on for a span (R9 #20): a GROUP HEADER stands
  /// for its members.
  ///
  /// #20 took the header's special case out of SELECTION — a header is a
  /// row and a drag selects the rows it drew over. This is the separate,
  /// and separately true, statement that a row's verbs act on what the row
  /// SHOWS: the header band paints its members' key union, so a move that
  /// grabs it moves those keys ("한번에 잡아 이동"). Keeping the two apart
  /// is the whole of #20 — one used to be doing the other's job.
  List<String> laneVerbTargets(
    List<String> spanLaneIds, {
    List<LayerEffect> effects = const [],
  }) {
    final targets = <String>[];
    void add(String laneId) {
      if (!targets.contains(laneId)) {
        targets.add(laneId);
      }
    }

    for (final laneId in spanLaneIds) {
      if (laneId == transformGroupHeaderLane.laneId) {
        transformLaneDisplayOrder.forEach(add);
        continue;
      }
      // The name-tag header stands for its seven members, exactly as the
      // transform header does (한번에 잡아 이동).
      if (laneId == seNameTagGroupLaneId) {
        seNameTagLaneDisplayOrder.forEach(add);
        continue;
      }
      final address = parseEffectLaneId(laneId);
      if (address != null && address.parameterId == null) {
        for (final effect in effects) {
          if (effect.id == address.effectId) {
            effectLaneDisplayOrder(effect).forEach(add);
            break;
          }
        }
        continue;
      }
      add(laneId);
    }
    return targets;
  }

  /// The LANE range a verb should act on, or null when the subject is not
  /// a property row (R10 #19).
  ///
  /// A live lane SPAN wins; otherwise the row you are standing on, as a
  /// one-frame span at the playhead. Expressing the standing case as a
  /// span is what makes Add and Delete need no second code path — the
  /// group header's whole-member expansion and the effect-lane branch
  /// come along either way.
  TimelineLaneSelection? get laneVerbRange {
    final span = _selection.laneRangeSelection.value;
    if (span != null) {
      return span;
    }
    // 🚨㉙ → F-17/F-84: the CAMERA row IS its transform group header — its
    // band already draws the members' union (B4) — and 유저 2026-09-11:
    // 「트랜스폼이나 카메라나 똑같으니까 법 싹 하나로 통일해줘」. So a band on
    // the camera row ALONE is a header span, and standing on it stands on
    // the header: every lane verb (name, type, add, delete) reaches the
    // camera's keys through the one path the fx header's take.
    final cells = _selection.frameRangeSelection.value;
    if (cells != null &&
        cells.spanLayerIds.length == 1 &&
        _isCameraRow(cells.spanLayerIds.single)) {
      return TimelineLaneSelection(
        layerId: cells.spanLayerIds.single,
        laneId: transformGroupHeaderLane.laneId,
        startIndex: cells.startIndex,
        endIndexExclusive: cells.endIndexExclusive,
      );
    }
    return switch (_internals.currentRow) {
      LaneRowAddress(:final layerId, :final laneId) => _standingSpan(
        layerId,
        laneId,
      ),
      // A band that also holds other rows claims the press as CELLS.
      LayerRowAddress(:final layerId)
          when cells == null && _isCameraRow(layerId) =>
        _standingSpan(layerId, transformGroupHeaderLane.laneId),
      _ => null,
    };
  }

  /// The row you are STANDING on, as a one-frame span at the playhead.
  TimelineLaneSelection _standingSpan(LayerId layerId, String laneId) {
    final frame = _laneVerbFrameFor(layerId);
    return TimelineLaneSelection(
      layerId: layerId,
      laneId: laneId,
      startIndex: frame,
      endIndexExclusive: frame + 1,
    );
  }

  bool _isCameraRow(LayerId layerId) =>
      laneVerbLayerFor(layerId)?.kind == LayerKind.camera;

  /// The transform track a LANE row edits: the CAMERA row's lanes live on
  /// the cut's camera, every other row's on the layer itself.
  ///
  /// R10 R3: the lane-verb family read `layer.transformTrack` flat, so Add
  /// and Delete silently missed the camera row — which only showed once
  /// the Frame ▾ menu became the delete key's home and had to answer for
  /// the lane the marker's context menu used to.
  TransformTrack _laneTransformTrackOf(Layer layer) =>
      layer.kind == LayerKind.camera
      ? (_project.activeCutOrNull?.camera.track ?? layer.transformTrack)
      : layer.transformTrack;

  /// The layer a LANE verb READS and WRITES.
  ///
  /// ★A track-owned SE row answers with the GLOBAL layer, never the cut's
  /// display clone (user, 2026-08-09: **"글로벌 트랙이 메인이고 컷
  /// 타임라인 내부에서는 그걸 알기 쉽게 보여주기만 할 뿐"**). The lane
  /// selection is stated on that same global axis, so a span that runs
  /// past the cut edge still reaches every key it covers — reading the
  /// clone could only ever have touched the keys the current cut happens
  /// to show.
  ///
  /// This is the axis rule the frame-shift verbs already follow
  /// (`BlockShift.shiftLayerFor`, UI-R18 #1), now said once more for the lane
  /// family. R5 #8's window conversion on the way OUT retires with it:
  /// what goes in was global to begin with.
  /// ★And a V TRACK's own lane rows answer with a CARRIER layer — the
  /// track's transform and chain wearing the carrier id, the very shape
  /// the rails already draw those rows with ([_vLaneCarrier]). Without it
  /// the verbs looked the carrier up as a layer, found nothing, and
  /// reported "no keys here": Delete then fell through to the CEL path and
  /// removed the active layer's drawing instead. The commit funnels below
  /// send it home to the track.
  Layer? laneVerbLayerFor(LayerId layerId) {
    final carrierTrackId = trackIdOfTransformLaneCarrier(layerId);
    if (carrierTrackId != null) {
      final track = _project.trackById(carrierTrackId);
      return track == null
          ? null
          : Layer(
              id: layerId,
              name: 'V',
              frames: const [],
              // No transform of its own any more; the V row's lane carrier
              // exists for the EFFECT chain alone.
              effects: track.effects,
            );
    }
    return _project.commitLayerById(layerId);
  }

  /// The playhead as [layerId]'s own lanes key it — the frame half of
  /// [laneVerbLayerFor]. A track-SE row is on the global axis, so the
  /// cut-local cursor has to be translated before it can name a key.
  int _laneVerbFrameFor(LayerId layerId) => _laneVerbFrameAt(
    layerId,
    _controllers.timelineController.currentFrameIndex,
    frameIsGlobal: false,
  );

  /// [frameIndex] as [layerId]'s own lanes key it. [frameIsGlobal] names
  /// the axis the caller holds: the timeline panel's rails and playhead
  /// speak CUT-LOCAL frames, the storyboard's rails global ones — and only
  /// a track-SE row, whose keys live on the global axis, tells the two
  /// apart.
  int _laneVerbFrameAt(
    LayerId layerId,
    int frameIndex, {
    required bool frameIsGlobal,
  }) => frameIndex + (frameIsGlobal ? 0 : _project.rowAxisOffset(layerId));

  /// The READ half of the projection: the row a lane on [shown] resolves
  /// its VALUES against, and the frame [frameIndex] — on [shown]'s own rail —
  /// names there.
  ///
  /// A track-SE row's rail shows the cut-local clone, and the clone holds
  /// only the keys inside the cut (a key index is never negative), so its
  /// value at a cut frame is read off the TRACK's row at the global frame —
  /// where a key an earlier cut made still holds it. A drag in flight is read
  /// in its global form, so the value column follows the hand. Every other
  /// row resolves against [shown] itself, which may be a preview, on its own
  /// frames.
  ({Layer layer, int frame}) laneValueSourceAt(Layer shown, int frameIndex) {
    final global = _project.isTrackSeLayerId(shown.id)
        ? timelineDragPreviewGlobalLayerFor(
                _internals.dragPreview.value,
                shown.id,
              ) ??
              _project.trackSeGlobalLayerById(shown.id)
        : null;
    if (global == null) {
      return (layer: shown, frame: frameIndex);
    }
    return (
      layer: global,
      frame: _laneVerbFrameAt(shown.id, frameIndex, frameIsGlobal: false),
    );
  }

  /// The lane navigator's ◆ on [laneId] of [layerId] at [frameIndex]: a key
  /// frozen at the value the lane resolves there, or the key there taken
  /// away — one undo. [frameIsGlobal]: see [_laneVerbFrameAt].
  ///
  /// 🚨★★★F-102 (2026-09-15): both panels keyed through copies of this body
  /// in their hosts, and the timeline's read the row it was SHOWN. For a
  /// track-SE row that is the cut-local clone, which had dropped every key
  /// made in an earlier cut — so keying S1 in cut 2 froze the default and,
  /// written back through the cut window, erased cut 1's key (유저 09-12:
  /// 「컷1에서 se의 트랜스폼으로 포지션 조정했는데, 그게 다른 컷2에서 값이
  /// 안바뀌어 있고 초기값인 상태로 보임」). [laneVerbLayerFor] reads the row
  /// the project holds, so there is nothing to put back.
  void toggleLaneKeyAt(
    LayerId layerId,
    String laneId,
    int frameIndex, {
    required bool frameIsGlobal,
    required String description,
  }) => _editLaneAt(
    layerId,
    laneId,
    frameIndex,
    frameIsGlobal: frameIsGlobal,
    description: description,
    nameTag: (tag, frame) =>
        seNameTagWithLaneKeyToggled(tag, laneId: laneId, frameIndex: frame),
    effects: (effects, frame) =>
        effectsWithLaneKeyToggled(effects, laneId: laneId, frameIndex: frame),
    transform: (layer, track, frame) =>
        _transformTrackWithKeyToggled(layer, track, laneId, frame),
  );

  /// A value typed or scrubbed into [laneId] of [layerId] at [frameIndex] —
  /// one undo, on the row and at the frame [toggleLaneKeyAt] takes.
  void setLaneValueAt(
    LayerId layerId,
    String laneId,
    int frameIndex,
    String input, {
    required bool frameIsGlobal,
    required String description,
  }) => _editLaneAt(
    layerId,
    laneId,
    frameIndex,
    frameIsGlobal: frameIsGlobal,
    description: description,
    nameTag: (tag, frame) => seNameTagWithLaneValueEdited(
      tag,
      laneId: laneId,
      frameIndex: frame,
      input: input,
    ),
    effects: (effects, frame) => effectsWithLaneValueEdited(
      effects,
      laneId: laneId,
      frameIndex: frame,
      input: input,
    ),
    transform: (layer, track, frame) => transformTrackWithLaneValueEdited(
      track,
      laneId: laneId,
      frameIndex: frame,
      input: input,
    ),
  );

  /// The ONE dispatch behind [toggleLaneKeyAt] and [setLaneValueAt]: which
  /// of a row's three keyed families [laneId] names, the row and frame to
  /// edit it on, and the funnel that family commits through.
  void _editLaneAt(
    LayerId layerId,
    String laneId,
    int frameIndex, {
    required bool frameIsGlobal,
    required String description,
    required SeNameTag? Function(SeNameTag tag, int frame) nameTag,
    required List<LayerEffect>? Function(List<LayerEffect> effects, int frame)
    effects,
    required TransformTrack? Function(
      Layer layer,
      TransformTrack track,
      int frame,
    )
    transform,
  }) {
    final layer = laneVerbLayerFor(layerId);
    if (layer == null) {
      return;
    }
    final frame = _laneVerbFrameAt(
      layerId,
      frameIndex,
      frameIsGlobal: frameIsGlobal,
    );
    // R5 #7: the name tag is a fixed FIELD on the row, so it commits
    // through its own funnel — not the transform track, not the chain.
    if (laneIsSeNameTag(laneId)) {
      final next = nameTag(layer.seNameTag ?? const SeNameTag(), frame);
      if (next != null) {
        _commitLaneSeNameTag(layer, next, description: description);
      }
      return;
    }
    if (parseEffectLaneId(laneId) != null) {
      final next = effects(layer.effects, frame);
      if (next != null) {
        _commitLaneEffects(layer, next, description: description);
      }
      return;
    }
    final next = transform(layer, _laneTransformTrackOf(layer), frame);
    if (next != null) {
      _commitLaneTransformTrack(layer, next, description: description);
    }
  }

  /// A canvas handle's drag landing on [layerId]'s transform: [edit] writes
  /// ONE key at the playhead (the AE rule), committed as one undo.
  ///
  /// 🚨F-102: the handles wrote the ACTIVE row back as they found it, and a
  /// track-SE row's active row is its cut-local clone — so in any cut but
  /// the first, a drag put cut-local keys on the global axis and erased the
  /// keys of earlier cuts. [edit] is handed the track the project holds and
  /// the playhead on that track's own axis.
  void editLayerTransformAtPlayhead(
    LayerId layerId,
    TransformTrack Function(TransformTrack track, int frameIndex) edit, {
    required String description,
  }) {
    final layer = laneVerbLayerFor(layerId);
    if (layer == null) {
      return;
    }
    _commitLaneTransformTrack(
      layer,
      edit(_laneTransformTrackOf(layer), _laneVerbFrameFor(layerId)),
      description: description,
    );
  }

  /// An effect header's eyeball (R6): [effectId] switched on or off in
  /// [layerId]'s chain, one undo — read off the row the project holds, like
  /// every other write to the chain.
  void toggleLaneEffectEnabled(
    LayerId layerId,
    EffectId effectId, {
    required String description,
  }) {
    final layer = laneVerbLayerFor(layerId);
    if (layer == null) {
      return;
    }
    final next = effectsWithEnabledToggled(layer.effects, effectId);
    if (next != null) {
      _commitLaneEffects(layer, next, description: description);
    }
  }

  /// A group header's switch, whichever group the header names: the
  /// Transform group's is the row's own field (R8), an effect's is that
  /// effect's eyeball (R6), and a group with no switch does nothing.
  ///
  /// One dispatch for every rail that draws a header. The timeline host held
  /// it alone, so the storyboard's S rows had no switch to press (F-101).
  void toggleLaneGroupEnabled(
    LayerId layerId,
    String headerLaneId, {
    required String description,
  }) {
    if (headerLaneId == transformGroupHeaderLane.laneId) {
      _effectsAndFx.toggleLayerTransformFx(layerId);
      return;
    }
    final effectId = parseEffectLaneId(headerLaneId)?.effectId;
    if (effectId != null) {
      toggleLaneEffectEnabled(layerId, effectId, description: description);
    }
  }

  /// [track] with [laneId]'s key at [frame] toggled — a new one frozen at
  /// the value [layer] resolves there. What the navigator's ◆ and the range
  /// Create both write.
  TransformTrack? _transformTrackWithKeyToggled(
    Layer layer,
    TransformTrack track,
    String laneId,
    int frame,
  ) {
    final isCamera = layer.kind == LayerKind.camera;
    return transformTrackWithLaneKeyToggled(
      track,
      laneId: laneId,
      frameIndex: frame,
      resolvedPose: _laneResolvedPose(layer, frame),
      resolvedAnchorPoint: isCamera
          ? null
          : _internals.layerAnchorPointAtFrame(layer, frame),
      resolvedOpacity: isCamera
          ? 1
          : _internals.layerOpacityAtFrame(layer, frame),
    );
  }

  /// The lane path's NAME TAG commit — the third funnel, beside
  /// [_commitLaneTransformTrack] and [_commitLaneEffects]. The coordinator
  /// finds an SE row wherever it lives, so the tag goes home as it is.
  void _commitLaneSeNameTag(
    Layer layer,
    SeNameTag tag, {
    required String description,
  }) {
    _project.cutCommandCoordinator.setSeNameTag(
      layerId: layer.id,
      seNameTag: tag,
      description: description,
    );
    _changes.notifyChanged();
  }

  void _commitLaneTransformTrack(
    Layer layer,
    TransformTrack track, {
    required String description,
  }) {
    if (layer.kind == LayerKind.camera) {
      _internals.updateActiveCutCameraTrack(track, description: description);
      return;
    }
    // A V row's carrier has no transform to go home to any more: the row's
    // lanes are its EFFECT chain alone, so a transform commit here would be
    // writing where nothing reads.
    if (trackIdOfTransformLaneCarrier(layer.id) != null) {
      return;
    }
    // No window conversion: [laneVerbLayerFor] hands these verbs the
    // GLOBAL layer for a track-SE row, so the track they edited is already
    // on the axis it belongs to. Converting here would shift it twice.
    _internals.updateLayerTransformTrack(
      layer.id,
      track,
      description: description,
    );
  }

  /// The lane path's EFFECT commit — the twin of [_commitLaneTransformTrack].
  ///
  /// A funnel rather than three call sites: Add, Delete and Reset all
  /// commit chains read off the same layer, and which axis that layer is
  /// on is exactly the kind of step that gets remembered in two places out
  /// of three.
  void _commitLaneEffects(
    Layer layer,
    List<LayerEffect> effects, {
    required String description,
  }) {
    final carrierTrackId = trackIdOfTransformLaneCarrier(layer.id);
    if (carrierTrackId != null) {
      _effectsAndFx.updateTrackEffects(
        carrierTrackId,
        effects,
        description: description,
      );
      return;
    }
    _effectsAndFx.updateLayerEffects(
      layer.id,
      effects,
      description: description,
    );
  }

  /// Folds [step] over [laneIds] from [start] and hands the result to
  /// [commit] ONCE, when any lane changed — one undo for the whole span.
  /// Returns whether anything was committed.
  bool _commitLaneFold<T>(
    T start,
    Iterable<String> laneIds,
    T? Function(T value, String laneId) step, {
    required void Function(T value) commit,
  }) {
    final next = _foldedEdits(start, laneIds, step);
    if (next != null) {
      commit(next);
    }
    return next != null;
  }

  /// The lanes a verb may act on for [layer]. The CAMERA row draws only
  /// position/scale/rotation ([timelineLanesForLayer] builds its lanes
  /// without anchor and opacity), so a GROUP-header span — which expands
  /// to every transform lane — must not key two lanes that row has no way
  /// to show, move or delete.
  List<String> _laneVerbTargetsFor(Layer layer, List<String> targets) {
    if (layer.kind != LayerKind.camera) {
      return targets;
    }
    return targets
        .where((laneId) => laneId != 'anchor-point' && laneId != 'opacity')
        .toList();
  }

  /// The value a lane verb freezes at [frameIndex]. The camera's pose does
  /// not live on the camera pseudo-layer — its own transform track is
  /// permanently empty — so reading [_timeline.layerPoseAtFrame] there froze the
  /// canvas-centre identity pose and snapped the camera mid-move.
  CameraPose _laneResolvedPose(Layer layer, int frameIndex) {
    if (layer.kind != LayerKind.camera) {
      return _timeline.layerPoseAtFrame(layer, frameIndex);
    }
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return _timeline.layerPoseAtFrame(layer, frameIndex);
    }
    return resolveCameraPoseAt(
      camera: cut.camera,
      canvasSize: cut.canvasSize,
      frameIndex: frameIndex,
    );
  }

  /// Removes every key the range covers on every spanned lane — the
  /// mirror of [createLaneKeysForSelection], one undo. Returns whether
  /// anything was there to remove.
  bool removeLaneKeysForSelection(TimelineLaneSelection lane) {
    final scope = _laneVerbScope(lane);
    if (scope == null) {
      return false;
    }
    final layer = scope.layer;
    if (scope.effectLanes) {
      return _commitLaneFold(
        layer.effects,
        scope.targets,
        (effects, laneId) => _foldedEdits(
          effects,
          effectLaneKeyFrames(effects, laneId).where(lane.contains),
          (value, frame) => effectsWithLaneKeyRemoved(
            value,
            laneId: laneId,
            frameIndex: frame,
          ),
        ),
        commit: (effects) =>
            _commitLaneEffects(layer, effects, description: 'Delete keys'),
      );
    }
    return _commitLaneFold(
      _laneTransformTrackOf(layer),
      _laneVerbTargetsFor(layer, scope.targets),
      (track, laneId) => _foldedEdits(
        track,
        transformLaneKeyFrames(track, laneId).where(lane.contains),
        (value, frame) => transformTrackWithLaneKeyRemoved(
          value,
          laneId: laneId,
          frameIndex: frame,
        ),
      ),
      commit: (track) =>
          _commitLaneTransformTrack(layer, track, description: 'Delete keys'),
    );
  }

  /// What every lane verb settles first: the row the lane range names (an
  /// attach row stands down), the lanes the verb targets, and whether those
  /// are EFFECT lanes (parameter tracks) or the layer's own TRANSFORM lanes.
  ({Layer layer, List<String> targets, bool effectLanes})? _laneVerbScope(
    TimelineLaneSelection lane,
  ) {
    final layer = laneVerbLayerFor(lane.layerId);
    if (layer == null || isAttachedLayer(layer)) {
      return null;
    }
    final targets = laneVerbTargets(lane.spanLaneIds, effects: layer.effects);
    return (
      layer: layer,
      targets: targets,
      effectLanes: targets.any((laneId) => parseEffectLaneId(laneId) != null),
    );
  }

  /// The keys the LANE RANGE covers, one entry per key. Empty when the
  /// range holds no key at all.
  ///
  /// The naming gates and the key window's TYPE all read this, so "can I
  /// name here", "what do they already say" and "what type are they"
  /// cannot disagree about which keys the range covers.
  List<PropertyKey<Object?>> _laneRangeKeys() {
    final lane = laneVerbRange;
    if (lane == null) {
      return const [];
    }
    final scope = _laneVerbScope(lane);
    if (scope == null) {
      return const [];
    }
    final layer = scope.layer;
    final targets = scope.targets;
    final keys = <PropertyKey<Object?>>[];
    if (scope.effectLanes) {
      for (final laneId in targets) {
        final address = parseEffectLaneId(laneId);
        final parameterId = address?.parameterId;
        if (address == null || parameterId == null) {
          continue;
        }
        for (final effect in layer.effects) {
          if (effect.id != address.effectId) {
            continue;
          }
          final track = effect.parameters[parameterId]?.track;
          if (track == null) {
            continue;
          }
          for (final entry in track.keys.entries) {
            if (lane.contains(entry.key)) {
              keys.add(entry.value);
            }
          }
        }
      }
      return keys;
    }
    final track = _laneTransformTrackOf(layer);
    for (final laneId in _laneVerbTargetsFor(layer, targets)) {
      final property = transformPropertyOfLaneId(laneId);
      if (property == null) {
        continue;
      }
      for (final frame in transformLaneKeyFrames(track, laneId)) {
        final key = transformLaneKeyAt(track, property, frame);
        if (key != null && lane.contains(frame)) {
          keys.add(key);
        }
      }
    }
    return keys;
  }

  /// The names the range's keys carry — null for an unnamed one.
  Set<String?> _laneRangeKeyNames() => {
    for (final key in _laneRangeKeys()) key.name,
  };

  /// Whether the lane range has a key to name — Edit Instance's gate on a
  /// property row.
  bool get canNameLaneKeys => _laneRangeKeyNames().isNotEmpty;

  /// The name the range's keys AGREE on, or null when they disagree (or
  /// none is named) — what the rename dialog opens with.
  ///
  /// Same rule the group header shows (user 2026-07-30: "내부 이름이 전부
  /// 같으면 그 이름, 다르면 …"), said once so the field and the header
  /// cannot drift.
  String? get laneKeyNameForSelection {
    final names = _laneRangeKeyNames();
    return names.length == 1 ? names.first : null;
  }

  /// The TYPE the range's keys agree on, or null when they disagree — what
  /// the key window's type opens with, by the rule the name above follows
  /// (and the ○ the group header draws where its members disagree).
  PropertyKeyInterpolation? get laneKeyInterpolationForSelection {
    final kinds = {for (final key in _laneRangeKeys()) key.interpolation};
    return kinds.length == 1 ? kinds.first : null;
  }

  /// Names every key the LANE RANGE covers, on every lane it spans — the
  /// range form of [setLaneKeyName], committed as ONE undo step.
  ///
  /// Scope is [laneVerbRange]'s, the same one Add and Delete Key take: a
  /// live lane span, or the row you are STANDING on as a one-frame span at
  /// the playhead. Expressing the single key as a one-frame span is what
  /// makes this the ONLY naming path the UI needs (user 2026-08-10:
  /// "선택범위로 통하는 조작이 모두 다른것들이랑 동일한 로직").
  ///
  /// ★The covered keys of ONE lane end up at ONE value, which is the point
  /// rather than a side effect: a name MEANS "same value", so asking for
  /// one name across five keys is asking for exactly that. Lanes stay
  /// separate spaces, so a span across a whole pose leaves Position and
  /// Rotation each with their own single value.
  ///
  /// Returns true when [name] is ALREADY taken OUTSIDE the range and
  /// NOTHING was written — the caller asks ONCE for the whole range and
  /// then calls [linkLaneKeyNamesForSelection].
  ///
  /// [interpolation], when given, lands on the same keys in the same undo
  /// step — the key window's TYPE (F-17, 유저 2026-09-01: 「이름변경이랑
  /// 오른쪽에 유니언 타입 변경 두개 존재하도록」).
  bool setLaneKeyNamesForSelection(
    String? name, {
    PropertyKeyInterpolation? interpolation,
  }) => _writeLaneKeysForSelection(
    names: true,
    name: name,
    interpolation: interpolation,
    adopt: false,
  );

  /// Joins [name] across the range, ADOPTING the value it already holds —
  /// the answer to the "합칠까요?" [setLaneKeyNamesForSelection] raises.
  void linkLaneKeyNamesForSelection(
    String name, {
    PropertyKeyInterpolation? interpolation,
  }) => _writeLaneKeysForSelection(
    names: true,
    name: name,
    interpolation: interpolation,
    adopt: true,
  );

  /// The TYPE alone, on the keys the range covers — what the key window
  /// still owes when its name stood down (a taken name the user chose not
  /// to join): the type was confirmed in the same window.
  void setLaneKeyInterpolationsForSelection(
    PropertyKeyInterpolation interpolation,
  ) => _writeLaneKeysForSelection(
    names: false,
    interpolation: interpolation,
    adopt: false,
  );

  /// The shared body: walks the spanned lanes, and stops at the FIRST lane
  /// whose name is taken unless [adopt] says the user already agreed.
  /// Stopping before any commit is what makes the confirmation honest —
  /// nothing is half-written while the dialog is up.
  ///
  /// [names] false leaves every name as it is: the TYPE alone.
  bool _writeLaneKeysForSelection({
    required bool names,
    String? name,
    PropertyKeyInterpolation? interpolation,
    required bool adopt,
  }) {
    final lane = laneVerbRange;
    if (lane == null) {
      return false;
    }
    final scope = _laneVerbScope(lane);
    if (scope == null) {
      return false;
    }
    final layer = scope.layer;
    final cutId = _timeline.editingSession.activeCutId;
    final asked = names ? name : null;
    final preferred = _laneVerbFrameFor(lane.layerId);
    final why = !names
        ? 'Set key type'
        : name == null
        ? 'Unname keys'
        : 'Name keys';

    // Every lane is READ before any is written — the keys it covers, and
    // what already holds the name — so a taken name stops the verb while
    // the range is still untouched.
    if (scope.effectLanes) {
      final reads =
          <String, ({Set<int> frames, PropertyKey<double>? adopted})>{};
      for (final laneId in scope.targets) {
        final address = parseEffectLaneId(laneId);
        final parameterId = address?.parameterId;
        if (address == null || parameterId == null) {
          continue;
        }
        final frames = effectLaneKeyFrames(
          layer.effects,
          laneId,
        ).where(lane.contains).toSet();
        if (frames.isEmpty) {
          continue;
        }
        final adopted = asked == null || cutId == null
            ? null
            : _project.cutCommandCoordinator.namedEffectKeyInSpace(
                cutId: cutId,
                layerId: layer.id,
                effectId: address.effectId,
                parameterId: parameterId,
                name: asked,
                excludeFramesOnSource: frames,
              );
        if (adopted != null && !adopt) {
          return true;
        }
        reads[laneId] = (frames: frames, adopted: adopted);
      }
      _commitLaneFold(
        layer.effects,
        reads.keys,
        (effects, laneId) {
          final read = reads[laneId]!;
          final named = !names
              ? null
              : effectsWithLaneRangeNamed(
                  effects,
                  laneId: laneId,
                  frames: read.frames,
                  name: name,
                  adopted: read.adopted,
                  preferredFrame: preferred,
                );
          final typed = interpolation == null
              ? null
              : effectsWithLaneKeysInterpolated(
                  named ?? effects,
                  laneId: laneId,
                  frames: read.frames,
                  interpolation: interpolation,
                );
          return typed ?? named;
        },
        commit: (effects) =>
            _commitLaneEffects(layer, effects, description: why),
      );
      return false;
    }

    final track = _laneTransformTrackOf(layer);
    final reads = <String, ({Set<int> frames, TransformTrack? holder})>{};
    for (final laneId in _laneVerbTargetsFor(layer, scope.targets)) {
      final property = transformPropertyOfLaneId(laneId);
      if (property == null) {
        continue;
      }
      final frames = transformLaneKeyFrames(
        track,
        laneId,
      ).where(lane.contains).toSet();
      if (frames.isEmpty) {
        continue;
      }
      final holder = asked == null
          ? null
          : _laneTransformHoldingName(
              layer,
              property,
              asked,
              excludeFrames: frames,
            );
      if (holder != null && !adopt) {
        return true;
      }
      reads[laneId] = (frames: frames, holder: holder);
    }
    _commitLaneFold(
      track,
      reads.keys,
      (value, laneId) {
        final read = reads[laneId]!;
        final named = !names
            ? null
            : transformTrackWithLaneRangeNamed(
                value,
                laneId: laneId,
                frames: read.frames,
                name: name,
                adoptFrom: read.holder,
                preferredFrame: preferred,
              );
        final typed = interpolation == null
            ? null
            : transformTrackWithLaneKeysInterpolated(
                named ?? value,
                laneId: laneId,
                frames: read.frames,
                interpolation: interpolation,
              );
        return typed ?? named;
      },
      commit: (value) =>
          _commitLaneTransformTrack(layer, value, description: why),
    );
    return false;
  }

  /// AE's group Reset (R5, user 2026-08-09): puts a GROUP HEADER's members
  /// back to their defaults without deleting a single key.
  ///
  /// Scope is [laneVerbRange]'s, the same one Add and Delete Key take —
  /// the playhead alone, or a live lane-range selection. What differs is
  /// what a span MEANS here: "선택범위에서 작동하면 선택한 키들 리셋", so a
  /// span resets the keys it covers and authors none, while the playhead
  /// case must write one on an animated lane (nothing else can make the
  /// value THERE the default). An unkeyed lane is left alone either way —
  /// it already sits at its default, and keying it would turn a static
  /// property into an animated one behind the user's back.
  ///
  /// [headerLaneId] names the group: the transform header resets the
  /// transform track, an `fx-group:` header its own effect.
  bool resetLaneGroup(LayerId layerId, String headerLaneId) {
    final layer = laneVerbLayerFor(layerId);
    if (layer == null || isAttachedLayer(layer)) {
      return false;
    }
    final span = _selection.laneRangeSelection.value;
    // A span covering this very group is the only one that scopes the
    // reset: standing elsewhere with a selection alive on another row must
    // not silently retarget it.
    final scoped =
        span != null &&
        span.layerId == layerId &&
        span.spanLaneIds.contains(headerLaneId);
    final frames = scoped
        ? [for (var i = span.startIndex; i < span.endIndexExclusive; i += 1) i]
        : [_laneVerbFrameFor(layerId)];

    if (parseEffectLaneId(headerLaneId) != null) {
      final effects = effectsWithGroupReset(
        layer.effects,
        laneId: headerLaneId,
        frameIndexes: frames,
        keyedFramesOnly: scoped,
      );
      if (effects == null) {
        return false;
      }
      _commitLaneEffects(layer, effects, description: 'Reset group');
      return true;
    }
    if (headerLaneId != transformGroupHeaderLane.laneId) {
      return false;
    }
    // A gap has no canvas for the unkeyed pose to sit in the middle of, so
    // there is nothing for a transform reset to reset TO. The storyboard's S
    // rows reach this with no cut open since F-101; an effect's reset above
    // needs no canvas and still runs there.
    final canvasSize = _project.activeCutOrNull?.canvasSize;
    if (canvasSize == null) {
      return false;
    }
    final next = transformTrackWithGroupReset(
      _laneTransformTrackOf(layer),
      frameIndexes: frames,
      identity: layerIdentityPose(canvasSize),
      defaultAnchorPoint: CanvasPoint(
        x: canvasSize.width / 2,
        y: canvasSize.height / 2,
      ),
      keyedFramesOnly: scoped,
    );
    if (next == null) {
      return false;
    }
    _commitLaneTransformTrack(layer, next, description: 'Reset group');
    return true;
  }

  /// Whether [laneVerbRange] holds a key to delete.
  bool get laneVerbRangeHasKeys {
    final lane = laneVerbRange;
    // The same layer the verb will act on, or the answer is about a
    // different set of keys than the one Delete is about to remove: a
    // track-SE row's clone holds only this cut's, on this cut's numbers,
    // and the span is stated globally.
    final layer = lane == null ? null : laneVerbLayerFor(lane.layerId);
    if (lane == null || layer == null || isAttachedLayer(layer)) {
      return false;
    }
    final targets = _laneVerbTargetsFor(
      layer,
      laneVerbTargets(lane.spanLaneIds, effects: layer.effects),
    );
    return targets.any(
      (laneId) => parseEffectLaneId(laneId) != null
          ? effectLaneKeyFrames(layer.effects, laneId).any(lane.contains)
          : transformLaneKeyFrames(
              _laneTransformTrackOf(layer),
              laneId,
            ).any(lane.contains),
    );
  }

  /// Whether the one Delete has something to take from [laneVerbRange]: a key
  /// under it, or — on a live RANGE — an fx header it names (F-87).
  bool get laneVerbRangeHasSomethingToDelete {
    final lane = laneVerbRange;
    return laneVerbRangeHasKeys ||
        (lane != null && _effectsNamedByHeaderRange(lane).isNotEmpty);
  }

  /// 🚨F-87 — THE ONE DELETE ON A LANE ROW (유저 2026-09-12: 「공용 삭제버튼을
  /// 서있는곳 위치에 따라 나누도록. 트랜스폼 헤더에 서있으면 지금처럼 해당 키
  /// 삭제 그대로 두는데, 키가 없을때 삭제하면 레이어의 프레임이 삭제됨. 이런거
  /// 없도록. 법 최대한 하나로 통일 / 그리고 fx 헤더 선택범위로 선택한채로
  /// 삭제누르면 해당 fx 삭제」).
  ///
  /// A lane row is the press's subject the way a cell band is. A live RANGE
  /// over an fx header removes that effect, its keys with it; every other lane
  /// in the span loses the keys the range covers; with nothing to take the
  /// press does nothing — never the cel of the layer the lane belongs to.
  /// Standing on a header is not a range: it takes the keys at the playhead,
  /// as it always did. One undo for the whole press.
  void deleteForLaneSelection(TimelineLaneSelection lane) {
    final removed = _effectsNamedByHeaderRange(lane);
    if (removed.isEmpty) {
      removeLaneKeysForSelection(lane);
      return;
    }
    final layer = laneVerbLayerFor(lane.layerId)!;
    _project.historyManager.runAsOneStep('Delete', () {
      var effects = layer.effects;
      for (final effectId in removed) {
        effects = effectsWithRemoved(effects, effectId) ?? effects;
      }
      _commitLaneEffects(layer, effects, description: 'Remove effect');
      // The removed effects' header lanes resolve to nothing now, so the
      // same span takes only the keys on the lanes that are left.
      removeLaneKeysForSelection(lane);
    });
  }

  /// The effects a live lane RANGE names by their HEADER rows — none for the
  /// span of the row being stood on, which is not a range.
  List<EffectId> _effectsNamedByHeaderRange(TimelineLaneSelection lane) {
    if (_selection.laneRangeSelection.value == null) {
      return const [];
    }
    final layer = laneVerbLayerFor(lane.layerId);
    if (layer == null || isAttachedLayer(layer)) {
      return const [];
    }
    final ids = <EffectId>[];
    for (final laneId in lane.spanLaneIds) {
      final address = parseEffectLaneId(laneId);
      if (address == null || address.parameterId != null) {
        continue;
      }
      if (layer.effects.any((effect) => effect.id == address.effectId)) {
        ids.add(address.effectId);
      }
    }
    return ids;
  }

  /// value on every unkeyed frame of the range — one undo.
  void createLaneKeysForSelection(TimelineLaneSelection lane) {
    final scope = _laneVerbScope(lane);
    if (scope == null) {
      return;
    }
    final layer = scope.layer;
    final frames = [
      for (
        var frame = lane.startIndex;
        frame < lane.endIndexExclusive;
        frame += 1
      )
        if (frame >= 0) frame,
    ];
    // R6: an EFFECT-lane selection freezes keys on the effect chain
    // instead — same rule, same single undo.
    if (scope.effectLanes) {
      _commitLaneFold(
        layer.effects,
        scope.targets,
        (effects, laneId) => _foldedEdits(
          effects,
          frames,
          (value, frame) => effectLaneKeyFrames(value, laneId).contains(frame)
              ? null
              : effectsWithLaneKeyToggled(
                  value,
                  laneId: laneId,
                  frameIndex: frame,
                ),
        ),
        commit: (effects) =>
            _commitLaneEffects(layer, effects, description: 'Create keys'),
      );
      return;
    }
    // R26 #3: a multi-lane span freezes keys on EVERY spanned lane —
    // still one undo.
    _commitLaneFold(
      _laneTransformTrackOf(layer),
      _laneVerbTargetsFor(layer, scope.targets),
      (track, laneId) => _foldedEdits(
        track,
        frames,
        (value, frame) => transformLaneKeyFrames(value, laneId).contains(frame)
            ? null
            : _transformTrackWithKeyToggled(layer, value, laneId, frame),
      ),
      commit: (track) =>
          _commitLaneTransformTrack(layer, track, description: 'Create keys'),
    );
  }
}

/// [start] with [step] applied for each of [items] in turn, or null when no
/// step changed it — a step answers null when it leaves the value alone.
///
/// ⛔THE LANE-KEY VERBS FOLD THIS WAY. Create, Delete and the key window's
/// name/type write each walked their lanes and frames with the same
/// accumulate-and-flag loop, once per family (effect chain, transform
/// track), and the clone scan named the third copy when the window's TYPE
/// arrived (F-17, 2026-09-11).
T? _foldedEdits<T, I>(
  T start,
  Iterable<I> items,
  T? Function(T value, I item) step,
) {
  T? result;
  for (final item in items) {
    result = step(result ?? start, item) ?? result;
  }
  return result;
}
