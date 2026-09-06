part of '../editor_session_manager.dart';

/// The LANE VERBS — what a verb on a transform or effect lane acts on (the
/// targets, the range, the layer and frame behind a lane row), the keys it
/// creates, names, links and removes for the selection, and the commits
/// that write a lane back — as their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: no field of its own and eighteen
/// session members touched. It reaches the session through `_session`.
class _LaneVerbs {
  _LaneVerbs(this._session);

  final EditorSessionManager _session;

  /// Names (or un-names, with null) one TRANSFORM lane KEY — the twin of
  /// [_session.setEffectKeyName], under the same contract: true means [name] was
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
    final cutId = _session.editingSession.activeCutId;
    final layer = _session.layerById(layerId);
    if (cutId == null || layer == null) {
      return false;
    }
    final track = layer.transformTrack;
    if (!transformLaneHasKeyAt(track, property, frameIndex) ||
        transformLaneKeyName(track, property, frameIndex) == name) {
      return false;
    }
    if (name != null &&
        _session.cutCommandCoordinator.transformTrackHoldingName(
              cutId: cutId,
              layerId: layerId,
              property: property,
              name: name,
            ) !=
            null) {
      return true;
    }
    _session.updateLayerTransformTrack(
      layerId,
      transformTrackWithKeyName(track, property, frameIndex, name),
      description: name == null ? 'Unname key' : 'Name key',
    );
    return false;
  }

  /// Joins [name] on a transform lane, ADOPTING the value that name already
  /// holds — the answer to the "합칠까요?" [setTransformKeyName] raises, and
  /// the same pull [_session.linkEffectKeyName] does.
  void linkTransformKeyName({
    required LayerId layerId,
    required TransformPropertyId property,
    required int frameIndex,
    required String name,
  }) {
    final cutId = _session.editingSession.activeCutId;
    final layer = _session.layerById(layerId);
    if (cutId == null || layer == null) {
      return;
    }
    final holder = _session.cutCommandCoordinator.transformTrackHoldingName(
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
    _session.updateLayerTransformTrack(
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
    final cutId = _session.editingSession.activeCutId;
    if (cutId == null ||
        layer.kind == LayerKind.camera ||
        trackIdOfTransformLaneCarrier(layer.id) != null) {
      return null;
    }
    return _session.cutCommandCoordinator.transformTrackHoldingName(
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
  List<String> _laneVerbTargets(
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
    final span = _session.laneRangeSelection.value;
    if (span != null) {
      return span;
    }
    if (_session.currentRow case LaneRowAddress(
      :final layerId,
      :final laneId,
    )) {
      final frame = _laneVerbFrameFor(layerId);
      return TimelineLaneSelection(
        layerId: layerId,
        laneId: laneId,
        startIndex: frame,
        endIndexExclusive: frame + 1,
      );
    }
    return null;
  }

  /// The transform track a LANE row edits: the CAMERA row's lanes live on
  /// the cut's camera, every other row's on the layer itself.
  ///
  /// R10 R3: the lane-verb family read `layer.transformTrack` flat, so Add
  /// and Delete silently missed the camera row — which only showed once
  /// the Frame ▾ menu became the delete key's home and had to answer for
  /// the lane the marker's context menu used to.
  TransformTrack _laneTransformTrackOf(Layer layer) =>
      layer.kind == LayerKind.camera
      ? (_session.activeCutOrNull?.camera.track ?? layer.transformTrack)
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
  /// ([_session._shiftLayerFor], UI-R18 #1), now said once more for the lane
  /// family. R5 #8's window conversion on the way OUT retires with it:
  /// what goes in was global to begin with.
  /// ★And a V TRACK's own lane rows answer with a CARRIER layer — the
  /// track's transform and chain wearing the carrier id, the very shape
  /// the rails already draw those rows with ([_vLaneCarrier]). Without it
  /// the verbs looked the carrier up as a layer, found nothing, and
  /// reported "no keys here": Delete then fell through to the CEL path and
  /// removed the active layer's drawing instead. The commit funnels below
  /// send it home to the track.
  Layer? _laneVerbLayerFor(LayerId layerId) {
    final carrierTrackId = trackIdOfTransformLaneCarrier(layerId);
    if (carrierTrackId != null) {
      final track = _session.trackById(carrierTrackId);
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
    return _session.isTrackSeLayerId(layerId)
        ? _session.trackSeGlobalLayerById(layerId)
        : _session.layerById(layerId);
  }

  /// The playhead as [layerId]'s own lanes key it — the frame half of
  /// [_laneVerbLayerFor]. A track-SE row is on the global axis, so the
  /// cut-local cursor has to be translated before it can name a key.
  int _laneVerbFrameFor(LayerId layerId) =>
      _session.timelineController.currentFrameIndex +
      (_session.isTrackSeLayerId(layerId)
          ? _session.activeCutGlobalStartFrame
          : 0);

  void _commitLaneTransformTrack(
    Layer layer,
    TransformTrack track, {
    required String description,
  }) {
    if (layer.kind == LayerKind.camera) {
      _session.updateActiveCutCameraTrack(track, description: description);
      return;
    }
    // A V row's carrier has no transform to go home to any more: the row's
    // lanes are its EFFECT chain alone, so a transform commit here would be
    // writing where nothing reads.
    if (trackIdOfTransformLaneCarrier(layer.id) != null) {
      return;
    }
    // No window conversion: [_laneVerbLayerFor] hands these verbs the
    // GLOBAL layer for a track-SE row, so the track they edited is already
    // on the axis it belongs to. Converting here would shift it twice.
    _session.updateLayerTransformTrack(
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
      _session.updateTrackEffects(
        carrierTrackId,
        effects,
        description: description,
      );
      return;
    }
    _session.updateLayerEffects(layer.id, effects, description: description);
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
  /// permanently empty — so reading [_session.layerPoseAtFrame] there froze the
  /// canvas-centre identity pose and snapped the camera mid-move.
  CameraPose _laneResolvedPose(Layer layer, int frameIndex) {
    if (layer.kind != LayerKind.camera) {
      return _session.layerPoseAtFrame(layer, frameIndex);
    }
    final cut = _session.activeCutOrNull;
    if (cut == null) {
      return _session.layerPoseAtFrame(layer, frameIndex);
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
    final targets = scope.targets;
    if (scope.effectLanes) {
      var effects = layer.effects;
      var changed = false;
      for (final laneId in targets) {
        for (final frame in effectLaneKeyFrames(effects, laneId).toList()) {
          if (!lane.contains(frame)) {
            continue;
          }
          final next = effectsWithLaneKeyRemoved(
            effects,
            laneId: laneId,
            frameIndex: frame,
          );
          if (next != null) {
            effects = next;
            changed = true;
          }
        }
      }
      if (changed) {
        _commitLaneEffects(layer, effects, description: 'Delete keys');
      }
      return changed;
    }
    var track = _laneTransformTrackOf(layer);
    var changed = false;
    for (final laneId in _laneVerbTargetsFor(layer, targets)) {
      for (final frame in transformLaneKeyFrames(track, laneId).toList()) {
        if (!lane.contains(frame)) {
          continue;
        }
        final next = transformTrackWithLaneKeyRemoved(
          track,
          laneId: laneId,
          frameIndex: frame,
        );
        if (next != null) {
          track = next;
          changed = true;
        }
      }
    }
    if (changed) {
      _commitLaneTransformTrack(layer, track, description: 'Delete keys');
    }
    return changed;
  }

  /// What every lane verb settles first: the row the lane range names (an
  /// attach row stands down), the lanes the verb targets, and whether those
  /// are EFFECT lanes (parameter tracks) or the layer's own TRANSFORM lanes.
  ({Layer layer, List<String> targets, bool effectLanes})? _laneVerbScope(
    TimelineLaneSelection lane,
  ) {
    final layer = _laneVerbLayerFor(lane.layerId);
    if (layer == null || isAttachedLayer(layer)) {
      return null;
    }
    final targets = _laneVerbTargets(lane.spanLaneIds, effects: layer.effects);
    return (
      layer: layer,
      targets: targets,
      effectLanes: targets.any((laneId) => parseEffectLaneId(laneId) != null),
    );
  }

  /// The names the LANE RANGE's keys carry — one entry per key, null for an
  /// unnamed one. Empty when the range holds no key at all.
  ///
  /// Both naming gates read this, so "can I name here" and "what do they
  /// already say" cannot disagree about which keys the range covers.
  Set<String?> _laneRangeKeyNames() {
    final lane = laneVerbRange;
    if (lane == null) {
      return const {};
    }
    final scope = _laneVerbScope(lane);
    if (scope == null) {
      return const {};
    }
    final layer = scope.layer;
    final targets = scope.targets;
    final names = <String?>{};
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
              names.add(entry.value.name);
            }
          }
        }
      }
      return names;
    }
    final track = _laneTransformTrackOf(layer);
    for (final laneId in _laneVerbTargetsFor(layer, targets)) {
      final property = transformPropertyOfLaneId(laneId);
      if (property == null) {
        continue;
      }
      for (final frame in transformLaneKeyFrames(track, laneId)) {
        if (lane.contains(frame)) {
          names.add(transformLaneKeyName(track, property, frame));
        }
      }
    }
    return names;
  }

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
  bool setLaneKeyNamesForSelection(String? name) =>
      _writeLaneKeyNamesForSelection(name, adopt: false);

  /// Joins [name] across the range, ADOPTING the value it already holds —
  /// the answer to the "합칠까요?" [setLaneKeyNamesForSelection] raises.
  void linkLaneKeyNamesForSelection(String name) =>
      _writeLaneKeyNamesForSelection(name, adopt: true);

  /// The shared body: walks the spanned lanes, and stops at the FIRST lane
  /// whose name is taken unless [adopt] says the user already agreed.
  /// Stopping before any commit is what makes the confirmation honest —
  /// nothing is half-written while the dialog is up.
  bool _writeLaneKeyNamesForSelection(String? name, {required bool adopt}) {
    final lane = laneVerbRange;
    if (lane == null) {
      return false;
    }
    final scope = _laneVerbScope(lane);
    if (scope == null) {
      return false;
    }
    final layer = scope.layer;
    final cutId = _session.editingSession.activeCutId;
    final targets = scope.targets;
    final preferred = _laneVerbFrameFor(lane.layerId);
    final why = name == null ? 'Unname keys' : 'Name keys';

    if (scope.effectLanes) {
      var effects = layer.effects;
      var changed = false;
      for (final laneId in targets) {
        final address = parseEffectLaneId(laneId);
        final parameterId = address?.parameterId;
        if (address == null || parameterId == null) {
          continue;
        }
        final frames = effectLaneKeyFrames(
          effects,
          laneId,
        ).where(lane.contains).toSet();
        if (frames.isEmpty) {
          continue;
        }
        double? adopted;
        if (name != null && cutId != null) {
          adopted = _session.cutCommandCoordinator.namedEffectKeyValueInSpace(
            cutId: cutId,
            layerId: layer.id,
            effectId: address.effectId,
            parameterId: parameterId,
            name: name,
            excludeFramesOnSource: frames,
          );
          if (adopted != null && !adopt) {
            return true;
          }
        }
        final next = effectsWithLaneRangeNamed(
          effects,
          laneId: laneId,
          frames: frames,
          name: name,
          adopted: adopted,
          preferredFrame: preferred,
        );
        if (next != null) {
          effects = next;
          changed = true;
        }
      }
      if (changed) {
        _commitLaneEffects(layer, effects, description: why);
      }
      return false;
    }

    var track = _laneTransformTrackOf(layer);
    var changed = false;
    for (final laneId in _laneVerbTargetsFor(layer, targets)) {
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
      TransformTrack? holder;
      if (name != null) {
        holder = _laneTransformHoldingName(
          layer,
          property,
          name,
          excludeFrames: frames,
        );
        if (holder != null && !adopt) {
          return true;
        }
      }
      final next = transformTrackWithLaneRangeNamed(
        track,
        laneId: laneId,
        frames: frames,
        name: name,
        adoptFrom: holder,
        preferredFrame: preferred,
      );
      if (next != null) {
        track = next;
        changed = true;
      }
    }
    if (changed) {
      _commitLaneTransformTrack(layer, track, description: why);
    }
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
    final layer = _laneVerbLayerFor(layerId);
    if (layer == null || isAttachedLayer(layer)) {
      return false;
    }
    final span = _session.laneRangeSelection.value;
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
    final canvasSize = _session.requireActiveCut.canvasSize;
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
    final layer = lane == null ? null : _laneVerbLayerFor(lane.layerId);
    if (lane == null || layer == null || isAttachedLayer(layer)) {
      return false;
    }
    final targets = _laneVerbTargetsFor(
      layer,
      _laneVerbTargets(lane.spanLaneIds, effects: layer.effects),
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
    final targets = scope.targets;
    // R6: an EFFECT-lane selection freezes keys on the effect chain
    // instead — same rule, same single undo.
    if (scope.effectLanes) {
      var effects = layer.effects;
      var effectsChanged = false;
      for (final laneId in targets) {
        for (
          var frame = lane.startIndex;
          frame < lane.endIndexExclusive;
          frame += 1
        ) {
          if (frame < 0 ||
              effectLaneKeyFrames(effects, laneId).contains(frame)) {
            continue;
          }
          final next = effectsWithLaneKeyToggled(
            effects,
            laneId: laneId,
            frameIndex: frame,
          );
          if (next != null) {
            effects = next;
            effectsChanged = true;
          }
        }
      }
      if (effectsChanged) {
        _commitLaneEffects(layer, effects, description: 'Create keys');
      }
      return;
    }
    var track = _laneTransformTrackOf(layer);
    final isCamera = layer.kind == LayerKind.camera;
    var changed = false;
    // R26 #3: a multi-lane span freezes keys on EVERY spanned lane —
    // still one undo.
    for (final laneId in _laneVerbTargetsFor(layer, targets)) {
      for (
        var frame = lane.startIndex;
        frame < lane.endIndexExclusive;
        frame += 1
      ) {
        if (frame < 0 ||
            transformLaneKeyFrames(track, laneId).contains(frame)) {
          continue;
        }
        final next = transformTrackWithLaneKeyToggled(
          track,
          laneId: laneId,
          frameIndex: frame,
          resolvedPose: _laneResolvedPose(layer, frame),
          resolvedAnchorPoint: isCamera
              ? null
              : _session.layerAnchorPointAtFrame(layer, frame),
          resolvedOpacity: isCamera
              ? 1
              : _session.layerOpacityAtFrame(layer, frame),
        );
        if (next != null) {
          track = next;
          changed = true;
        }
      }
    }
    if (changed) {
      _commitLaneTransformTrack(layer, track, description: 'Create keys');
    }
  }
}
