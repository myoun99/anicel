import '../../models/camera_pose.dart';
import '../../models/canvas_point.dart';
import '../../models/transform_track.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/property_track.dart'
    show PropertyKey, PropertyKeyInterpolation;
import '../../models/timeline_frame_range.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track_transform_lane_carrier.dart';
import '../../services/camera_pose_resolver.dart';
import '../../services/cut_frame_composite_plan.dart';
import '../timeline/effect_lane_editing.dart'
    show
        effectLaneKeyFrames,
        effectsWithGroupReset,
        effectsWithLaneKeyRemoved,
        effectsWithLaneKeyToggled,
        effectsWithLaneKeysInterpolated,
        effectsWithLaneRangeNamed;
import '../timeline/effect_lane_policy.dart'
    show effectLaneDisplayOrder, parseEffectLaneId;
import '../timeline/transform_lane_editing.dart'
    show
        transformLaneKeyFrames,
        transformTrackWithGroupReset,
        transformTrackWithLaneKeyRemoved,
        transformTrackWithLaneKeyToggled,
        transformTrackWithLaneKeysInterpolated,
        transformTrackWithLaneRangeNamed;
import '../timeline/se_name_tag_lane_policy.dart'
    show seNameTagGroupLaneId, seNameTagLaneDisplayOrder;
import '../timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane, transformLaneDisplayOrder;
import 'active_cut_controllers.dart';
import 'session_roles.dart';
import 'effects_and_fx.dart';

/// The LANE VERBS — what a verb on a transform or effect lane acts on (the
/// targets, the range, the layer and frame behind a lane row), the keys it
/// creates, names, links and removes for the selection, and the commits
/// that write a lane back — as their own object.
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
  }) : _project = project,
       _selection = selection,
       _timeline = timeline,
       _controllers = controllers,
       _internals = internals,
       _effectsAndFx = effectsAndFx;

  final EffectsAndFx _effectsAndFx;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final TimelineAccess _timeline;
  final ActiveCutControllers _controllers;
  final SessionInternals _internals;

  /// Names (or un-names, with null) one TRANSFORM lane KEY — the twin of
  /// [_effectsAndFx.setEffectKeyName], under the same contract: true means [name] was
  /// ALREADY taken in that lane's naming space and NOTHING was written, so
  /// the caller can offer to join instead (see [linkTransformKeyName]).
  ///
  /// The naming space is (link group, property). A transform carries no
  /// shared id the way an effect chain does — 겸용 siblings are different
  /// [LayerId]s holding the same part — so the group stands in for the
  /// effect id, and Rotation's "A" still cannot collide with Position's.
  bool setTransformKeyName({
    required LayerId layerId,
    required TransformPropertyId property,
    required int frameIndex,
    required String? name,
  }) {
    final cutId = _timeline.editingSession.activeCutId;
    final layer = _project.layerById(layerId);
    if (cutId == null || layer == null) {
      return false;
    }
    final track = layer.transformTrack;
    if (!transformLaneHasKeyAt(track, property, frameIndex) ||
        transformLaneKeyName(track, property, frameIndex) == name) {
      return false;
    }
    if (name != null &&
        _project.cutCommandCoordinator.transformTrackHoldingName(
              cutId: cutId,
              layerId: layerId,
              property: property,
              name: name,
            ) !=
            null) {
      return true;
    }
    _internals.updateLayerTransformTrack(
      layerId,
      transformTrackWithKeyName(track, property, frameIndex, name),
      description: name == null ? 'Unname key' : 'Name key',
    );
    return false;
  }

  /// Joins [name] on a transform lane, ADOPTING the value that name already
  /// holds — the answer to the "합칠까요?" [setTransformKeyName] raises, and
  /// the same pull [_effectsAndFx.linkEffectKeyName] does.
  void linkTransformKeyName({
    required LayerId layerId,
    required TransformPropertyId property,
    required int frameIndex,
    required String name,
  }) {
    final cutId = _timeline.editingSession.activeCutId;
    final layer = _project.layerById(layerId);
    if (cutId == null || layer == null) {
      return;
    }
    final holder = _project.cutCommandCoordinator.transformTrackHoldingName(
      cutId: cutId,
      layerId: layerId,
      property: property,
      name: name,
    );
    var next = layer.transformTrack;
    if (holder != null) {
      // Adopt BEFORE naming: the value arrives on a still-unnamed key, so
      // the write that follows carries a rename and nothing else — which
      // is what keeps the joining key from imposing its own number.
      next = transformTrackAdoptingName(
        next,
        holder,
        property,
        frameIndex,
        name,
      );
    }
    _internals.updateLayerTransformTrack(
      layerId,
      transformTrackWithKeyName(next, property, frameIndex, name),
      description: 'Name key',
    );
  }

  /// The transform track that ALREADY holds [name] in this lane's naming
  /// space, or null when the name is free there.
  ///
  /// A LAYER row's space spans its 겸용 link group. A camera row's and a V
  /// row's do not: a camera track belongs to its cut and a V track is held
  /// once, so there is no second use site for a name to reach.
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
    if (cutId == null ||
        layer.kind == LayerKind.camera ||
        trackIdOfTransformLaneCarrier(layer.id) != null) {
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
    return _project.isTrackSeLayerId(layerId)
        ? _project.trackSeGlobalLayerById(layerId)
        : _project.layerById(layerId);
  }

  /// The playhead as [layerId]'s own lanes key it — the frame half of
  /// [_laneVerbLayerFor]. A track-SE row is on the global axis, so the
  /// cut-local cursor has to be translated before it can name a key.
  int _laneVerbFrameFor(LayerId layerId) =>
      _controllers.timelineController.currentFrameIndex +
      (_project.isTrackSeLayerId(layerId)
          ? _project.activeCutGlobalStartFrame
          : 0);

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
      final reads = <String, ({Set<int> frames, double? adopted})>{};
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
            : _project.cutCommandCoordinator.namedEffectKeyValueInSpace(
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
    final canvasSize = _project.requireActiveCut.canvasSize;
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
    final isCamera = layer.kind == LayerKind.camera;
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
            : transformTrackWithLaneKeyToggled(
                value,
                laneId: laneId,
                frameIndex: frame,
                resolvedPose: _laneResolvedPose(layer, frame),
                resolvedAnchorPoint: isCamera
                    ? null
                    : _internals.layerAnchorPointAtFrame(layer, frame),
                resolvedOpacity: isCamera
                    ? 1
                    : _internals.layerOpacityAtFrame(layer, frame),
              ),
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
