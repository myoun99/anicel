part of '../editor_session_manager.dart';

/// The FRAME VERBS — the playhead's frame and what stands there: stepping
/// and flipping to a frame, the selected frame's name, duration and status
/// text, duplicating, renaming and linking it, and the pose sample the
/// canvas wraps the active layer in. Each reads the timeline controller;
/// the session stays the facade that names them.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP
/// cut, Round 6, 2026-09-03). Measured before cutting: nineteen host
/// methods whose only non-infrastructure field was the timeline
/// controller. It reaches the session through `_session`.
class _FrameVerbs {
  _FrameVerbs(this._session);

  final EditorSessionManager _session;

  /// The geometric pose sample the interactive canvas shows for [layerId]
  /// at the playhead — the draw-through wrap input. Null = identity (no
  /// transform work, fx bypassed, or no such layer), which skips the wrap:
  /// the ALWAYS-APPLIED rule (the active layer shows its transform too; the
  /// old edit-in-artwork-space rule is retired, R3 ⑩).
  LayerPoseSample? layerCanvasPoseSample(LayerId layerId) {
    final cut = _session.activeCutOrNull;
    if (cut == null) {
      return null;
    }
    for (final layer in cut.layers) {
      if (layer.id != layerId) {
        continue;
      }
      // An attach layer rides its BASE's transform (fx shared, W5): the
      // interactive view wraps in the base's pose so drawing on the attach
      // row lines up with the composite.
      final fxCarrier = isAttachedLayer(layer)
          ? (attachedBaseOf(layer, cut.layers) ?? layer)
          : layer;
      if (!fxCarrier.transformEnabled) {
        return null;
      }
      final pose = resolveLayerPoseAt(
        layer: fxCarrier,
        canvasSize: cut.canvasSize,
        frameIndex: _session.timelineController.currentFrameIndex,
      );
      if (pose == null) {
        return null;
      }
      return (
        pose: pose,
        anchorPoint: resolveLayerAnchorPointAt(
          layer: fxCarrier,
          frameIndex: _session.timelineController.currentFrameIndex,
        ),
      );
    }
    return null;
  }

  Frame? get selectedFrame {
    final layer = _session.activeLayer;
    if (layer == null) {
      return null;
    }

    return _session.timelineController.getSelectedFrameForLayer(layer);
  }

  bool get canCreateDrawingAtCurrentFrame {
    final layer = _session.activeLayer;
    // ⛔[layerKindTakesAuthoredCels], not `holdsDrawings`: the direction row
    // holds cels since R27 #16 and could not be given one (유저: 「프레임이
    // 없다고 뜨거든」).
    if (layer == null || !layerKindTakesAuthoredCels(layer.kind)) {
      return false;
    }
    // SYNCED attach rows (UI-R23 #7 v2): the ALWAYS-MIRROR invariant keeps
    // one own cel per base cel automatically — there is never anything
    // left to create by hand. FREE attach rows (UI-R21 #3) fall through
    // to the normal authoring path below.
    if (isSyncedAttachedLayer(layer)) {
      return false;
    }
    // A REFERENCE layer's picture comes from the library (any kind) —
    // nothing to author until rasterized. An IMAGE layer holds ONE cel by
    // definition — once it exists there is no second cel to create (paper
    // switching is cel NAMES + link banks, never another cel in the same
    // cut).
    if (layer.mediaReference != null) {
      return false;
    }
    if (layerKindHoldsSingleCel(layer.kind) && layer.frames.isNotEmpty) {
      return false;
    }

    return _session.timelineController.canCreateDrawingAt(
      layer: layer,
      frameIndex: _session.timelineController.currentFrameIndex,
    );
  }

  /// 🚨T2 복제 — 유저 확정 2026-08-13: 「복붙은 **선택**하고 붙여넣기가
  /// 기본이지만, **복제는 현재 액티브인 대상**을 상대로 적용하는 것」.
  ///
  /// ⛔So it is NOT on the shared pill: that pill's verbs ask what is
  /// selected, and this one deliberately does not. It lives inside the noun
  /// it copies, beside the layer's pair and the cut's.
  ///
  /// ★The logic is copy-then-paste in one press — 「로직은 복붙 통합 버튼과
  /// **똑같고** 그것을 독립복제 / 링크복제로 나눈 버전」 — so it goes through
  /// the same splice everything else does.
  ///
  /// ⚠️It lands at the block's END, not at the playhead. Standing in the
  /// middle of a hold and inserting there would split the block and put the
  /// copy INSIDE it, which for an independent duplicate is visibly wrong
  /// (`A P P P A A`) and for a linked one is only right by accident.
  ///
  /// ⛔The CLIPBOARD is not touched. A duplicate that clobbered what you had
  /// copied would be a second verb hiding inside the first.
  bool get canDuplicateActiveBlock {
    // The fifth active-row verb: it resolves its block with
    // [coveringDrawingBlockAt] on the active layer and has no band rung,
    // so a band naming other rows would splice a copy into a row the
    // user never swept — and shift that row's whole tail with it.
    //
    // ⛔This does not touch 유저 확정 2026-08-13 「복제는 현재 액티브인
    // 대상을 상대로 적용하는 것」: that ruling picks the verb's NOUN, and
    // the predicate is false whenever there is no band and whenever the
    // band covers the active row — every case the ruling describes.
    if (_session.bandNamesRowsThisPressWouldMiss) {
      return false;
    }
    final layer = _session.activeLayer;
    if (layer == null || !layerKindHoldsDrawings(layer.kind)) {
      return false;
    }
    // D22: a SINGLE-CEL (image) row's one block is pinned by the covering
    // normalization, so the duplicate never lands — but the independent
    // half MINTS a cel first, leaving a drawing no exposure references
    // and nothing on screen shows. A second cel is the one thing this
    // row's definition rules out.
    if (layerKindHoldsSingleCel(layer.kind)) {
      return false;
    }
    return coveringDrawingBlockAt(
          layer.timeline,
          _session.timelineController.currentFrameIndex,
        ) !=
        null;
  }

  void duplicateActiveBlock({required bool linked}) {
    final layer = _session.activeLayer;
    if (layer == null || !canDuplicateActiveBlock) {
      return;
    }
    final block = coveringDrawingBlockAt(
      layer.timeline,
      _session.timelineController.currentFrameIndex,
    );
    if (block == null) {
      return;
    }
    final clip = _session.timelineController.copyRunForLayer(
      layerId: layer.id,
      index: block.startIndex,
      count: block.endIndexExclusive - block.startIndex,
    );
    final bornFrames = <Frame>[];
    var placed = clip;
    if (!linked) {
      final minted = <FrameId, FrameId>{};
      final exposures = <int, TimelineExposure>{};
      for (final entry in clip.exposures.entries) {
        final sourceId = entry.value.frameId;
        if (sourceId == null) {
          continue;
        }
        final newId = minted.putIfAbsent(sourceId, () {
          final id = _session.mintFrameId(layer.id);
          final source = layer.frames
              .where((frame) => frame.id == sourceId)
              .firstOrNull;
          if (source != null) {
            // Unnamed, for the reason the independent paste is: a name is a
            // cel's identity inside the layer, and two cels claiming one is
            // a state no rename could produce.
            bornFrames.add(
              duplicateFrameContent(
                frame: source,
                newFrameId: id,
              ).copyWith(name: null),
            );
          }
          return id;
        });
        exposures[entry.key] = entry.value.copyWith(frameId: newId);
      }
      placed = TimelineClipRow(exposures: exposures, length: clip.length);
    }
    _session.timelineController.spliceRunsForLayers(
      runs: [
        (
          layerId: layer.id,
          index: block.endIndexExclusive,
          liftCount: 0,
          clip: placed,
          bornFrames: bornFrames,
        ),
      ],
      description: linked ? 'Link duplicate frames' : 'Duplicate frames',
    );
    _session.notifyChanged();
  }

  void shiftFrames(int delta, {TimelineRowAddress? currentRow}) {
    final scope = _session._frameShiftScope(currentRow: currentRow);
    if (scope == null || delta == 0) {
      return;
    }
    final edits = <({Layer before, Layer after})>[];
    for (final layerId in scope.layerIds) {
      // The COMMIT layer, never the display clone: a track-SE row's clone
      // is a projection and writing it back would drop the edit (the
      // clones are never written back).
      final before = _session.commitLayerById(layerId);
      if (before == null) {
        continue;
      }
      final anchor = _session._shiftAnchorFor(
        layerId,
        scope.anchorIndex,
        anchorIsGlobal: scope.anchorIsGlobal,
      );
      final after = before.copyWith(
        timeline: timelineShiftedFrom(
          before.timeline,
          anchorIndex: anchor,
          delta: delta,
        ),
      );
      if (after.timeline != before.timeline) {
        edits.add((before: before, after: after));
      }
    }
    if (edits.isEmpty) {
      return;
    }
    _session.timelineController.commitLayerTimelineDrags(edits);
    _session.refreshAfterCutCommand();
    _session.notifyChanged();
  }

  bool get canRenameFrameAtCurrentFrame {
    final layer = _session.activeLayer;
    if (layer == null) {
      return false;
    }

    return _session.timelineController.canRenameFrameAt(
      layer: layer,
      frameIndex: _session.timelineController.currentFrameIndex,
    );
  }

  /// Applies a rename to the currently selected frame.
  ///
  /// Returns `null` when the rename was applied (or was not possible). When the
  /// new [name] collides with another frame, returns that frame's id without
  /// mutating so the caller can offer to link instead (see [linkSelectedFrame]).
  /// SE rows are exempt from the collision rule — the same dialogue can
  /// legitimately repeat on a sheet, so duplicates just apply.
  FrameId? renameSelectedFrame(String name) {
    final layer = _session.activeLayer;
    final frame = selectedFrame;
    if (layer == null || frame == null || !canRenameFrameAtCurrentFrame) {
      return null;
    }

    final allowDuplicateName = layer.kind == LayerKind.se;
    if (!allowDuplicateName) {
      final conflictingFrameId = _session.timelineController
          .conflictingFrameIdForRename(
            layer: layer,
            frameId: frame.id,
            name: name,
          );
      if (conflictingFrameId != null) {
        return conflictingFrameId;
      }
    }

    _session.timelineController.renameFrameForLayer(
      layerId: layer.id,
      frameId: frame.id,
      name: name,
      allowDuplicateName: allowDuplicateName,
    );
    _session.notifyChanged();
    return null;
  }

  void linkSelectedFrame(FrameId targetFrameId) {
    final layer = _session.activeLayer;
    final frame = selectedFrame;
    if (layer == null || frame == null) {
      return;
    }

    _session.timelineController.linkFrameForLayer(
      layerId: layer.id,
      sourceFrameId: frame.id,
      targetFrameId: targetFrameId,
    );
    _session.notifyChanged();
  }

  int get currentFrameIndex => _session.timelineController.currentFrameIndex;

  /// Steps the playhead one frame back (flipping `,`) — a committed seek,
  /// clamped at the cut start.
  void selectPreviousFrame() {
    final current = _session.timelineController.currentFrameIndex;
    if (current <= 0) {
      return;
    }
    _session.selectFrameIndex(current - 1);
  }

  /// Steps the playhead one frame forward (flipping `.`), clamped at the
  /// cut's last frame.
  void selectNextFrame() {
    final cut = _session.activeCutOrNull;
    if (cut == null) {
      return; // Gap state: no cut axis to flip along.
    }
    final last = math.max(0, cut.duration - 1);
    final current = _session.timelineController.currentFrameIndex;
    if (current >= last) {
      return;
    }
    _session.selectFrameIndex(current + 1);
  }

  /// 🚨★★★플립이 **어디에 내리는가** — 한 곳에서 정한다.
  ///
  /// **프레임 축은 끝이 없다.** 타임라인은 스크롤된 만큼 종이를 깔고, 컷 끝은
  /// 경계선으로 표시하며 그 너머 칸은 흐리게 그린다 — 그러니 오른쪽으로는
  /// 바닥나지 않는다. 왼쪽은 **프레임 0 이 바닥**이고, 그래서 「다음 컷의 어느
  /// 행에 내리나」를 아무도 안 묻는다.
  ///
  /// ⛔F-44: 레이어 행은 이 법을 갖고 있었는데 **레인(fx) 행만
  /// [selectNextFrame] 을 불렀고**, 그건 `cut.duration - 1` 에서 멈춘다.
  /// 유저: 「fx 헤더, 멤버 행에 서있을때 화살표 플립으로 **컷 길이 넘어가는게
  /// 불가능** … 또 몇번째인지 모를 지긋지긋한 **통일미스**」. 맞았다.
  ///
  /// ⚠️[selectNextFrame]·[selectPreviousFrame] 은 **컷 안에 갇힌 한 프레임
  /// 이동**이고 그건 그것대로 옳다(플립이 아닌 호출자가 쓴다). 플립은 이쪽이다.
  void _flipToFrame(int landing) {
    final floored = landing < 0 ? 0 : landing;
    if (floored != _session.timelineController.currentFrameIndex) {
      _session.selectFrameIndex(floored);
    }
  }

  void flipRow({required bool forward}) {
    // 🚨F-13 (유저 2026-08-24): 「선택범위로 선택하고 취소되는 행동
    // 늘리고싶음. 지금 선택하고 플립등으로 프레임 이동하면 취소안되고 레이어
    // 이동하면 취소되는데, 플립하면 선택범위 취소되도록. 다만 룰러 스크럽시
    // 취소안되는건 그대로 남김」.
    //
    // The same clear [standOnRow] does, for the same reason: a flip is a
    // deliberate move to another column, so whatever was selected on the
    // old one is not what the next verb is about.
    //
    // ⛔It lives in the FLIP and not in [selectFrameIndex], which the ruler
    // scrub also goes through — 「룰러쪽 조작은 지금처럼 그대로 취소안되도록」.
    // Seeking is not the verb here; flipping is.
    _session.clearAllSelections();
    switch (_session.currentRow) {
      case TrackRowAddress(:final trackId):
        _session._flipCuts(trackId, forward: forward);
      case LayerRowAddress(:final layerId):
        final layer = _session.layerById(layerId) ?? _session.activeLayer;
        if (layer == null) {
          // No such layer to stand on — the playhead is parked in a GAP
          // (no cut, so no rows), or the stored row outlived its cut. The
          // row you are actually on is the TRACK, so walk cuts rather
          // than dead-ending: that is how a gap is stepped out of.
          _session._flipCuts(_session.selectedTrackId, forward: forward);
          return;
        }
        _flipBlocks(layer, forward: forward);
      case LaneRowAddress():
        // A lane's "blocks" would be its KEYS, but jumping key to key is
        // deferred by the user's own instruction — for now a property row
        // walks ONE FRAME, which is the same rule's other half ("a frame
        // where there are no blocks") rather than an exception written for
        // it. Attaching the key jump later changes this arm and nothing
        // else.
        // F-44: **같은 착지 규칙**을 쓴다 — 여기가 [selectNextFrame] 을 불러
        // 컷 끝에 갇혀 있던 자리다. 한 프레임 걷는 것은 그대로고, 그 한
        // 프레임이 어디에 내리는지를 이제 두 행이 같이 답한다.
        _flipToFrame(
          _session.timelineController.currentFrameIndex + (forward ? 1 : -1),
        );
    }
  }

  /// The layer-row half: the row's drawing blocks are its columns.
  ///
  /// It used to step between authored KEYS, which is why the directions
  /// disagreed. A key list has no entry for an uncovered frame, so a gap
  /// between two blocks was not a destination at all: forward jumped
  /// clean over it, and backward — which had no equivalent of forward's
  /// "escape past the block I am on" clause — jumped all the way to the
  /// previous block's head. Counting COLUMNS instead makes both
  /// directions the same sentence and puts the gap back on the axis.
  ///
  /// Past the cut's last frame is still THIS row's axis. The timeline's
  /// frame axis is endless: it papers whatever has been scrolled into
  /// existence, marks the cut end with its boundary line and draws the
  /// cells beyond it dimmed. So rightward never runs out without the
  /// flip having to leave — handing the landing to the track would drop
  /// the row being flipped, which is the one thing a layer row must not
  /// do. Leftward the cut's own frame 0 is the floor, which keeps
  /// "which row of the next cut do I land on?" a question nobody asks.
  void _flipBlocks(Layer layer, {required bool forward}) {
    if (_session.activeCutOrNull == null) {
      return; // Gap state: no cut axis — the TRACK row is the one to walk.
    }
    final current = _session.timelineController.currentFrameIndex;
    final next = flipColumnStep(
      frame: current,
      direction: forward ? 1 : -1,
      // A7① (2026-08-17): a HOLD is one flip unit — the column absorbs
      // hold-mode ghost tails/lead-ins into their owning run, so the flip
      // never lands inside a hold the HUD draws as empty. Repeat ghosts
      // stay their own columns; the merge lives HERE, in the flip's
      // column definition only (creation gates, painters and playback
      // keep reading raw coverage).
      columnAt: (frame) => holdMergedFlipColumnAt(layer, frame),
    );
    // 🚨F-21 (유저 2026-08-24): 「1번인덱스에 홀드인 블록하나 있을때
    // 중간인덱스, 5번인덱스인 상태에서 왼쪽 플립하면 인덱스 이동안함. 해당
    // 상황같은 이동할수없는 상황에서는 우선 1번인덱스로 이동하도록」.
    //
    // A hold that starts at frame 0 makes the WHOLE row one column, so a
    // leftward step from inside it asks for frame -1 and the guard below
    // refused — the flip did nothing at all, from anywhere in the row.
    // Falling to the axis's first frame is the honest answer: there is
    // nowhere further back, and where the column begins is somewhere.
    //
    // ⛔The clamp is HERE and not in [flipColumnStep], which is unbounded on
    // purpose — "callers clamp, because only they know which axis they were
    // counting on" is that function's own rule.
    _flipToFrame(next);
  }

  String? frameNameForLayer(Layer layer, int frameIndex) {
    if (layer.kind == LayerKind.camera) {
      // B4 (2026-08-17): the camera row's key summary no longer rides the
      // frame-name channel as a private ◆/■ text table. It is a
      // [transformUnionHeader] lane drawn by the shared lane key markers
      // ([timelineCameraUnionLane]) — the same code as the fx transform
      // header's union, which is what keeps its glyph a diamond mid-drag
      // and its size the one union constant. A camera layer has no cel
      // names, so the channel answers nothing here.
      return null;
    }
    // SYNCED attach mirrors PRINT THE BASE's cel name (UI-R24 #2 — the
    // name follows the owner; mirror cels are unnameable): the mirror row
    // reads 1ㅇㅇ----- exactly like its base.
    if (isSyncedAttachedLayer(layer)) {
      final base = attachedBaseOf(
        layer,
        _session.activeCutOrNull?.layers ?? const <Layer>[],
      );
      if (base != null) {
        return _session.timelineController
            .resolveFrameForLayer(layer: base, frameIndex: frameIndex)
            ?.name;
      }
    }
    return _session.timelineController
        .resolveFrameForLayer(layer: layer, frameIndex: frameIndex)
        ?.name;
  }

  int? get selectedEffectiveDuration {
    final layer = _session.activeLayer;
    if (layer == null || selectedFrame == null) {
      return null;
    }
    return _session.timelineController.effectiveDurationForLayerAt(
      layer: layer,
    );
  }

  String get currentFrameStatusText {
    return 'Frame: ${_session.timelineController.currentFrameIndex + 1}';
  }

  String currentFrameDisplayLabel(Layer? layer, Frame? frame) {
    if (layer == null) {
      return '-';
    }
    final frameIndex = _session.timelineController.currentFrameIndex;
    final frameName = frame?.name;
    final exposureState = _session.exposureStateForLayer(layer, frameIndex);
    return switch (exposureState) {
      TimelineCellExposureState.drawingStart =>
        frameName == null || frameName.isEmpty ? '○' : frameName,
      TimelineCellExposureState.held =>
        frameName == null || frameName.isEmpty ? '' : frameName,
      TimelineCellExposureState.markHeld =>
        frameName == null || frameName.isEmpty ? '●' : '$frameName ●',
      TimelineCellExposureState.uncovered => 'X',
      TimelineCellExposureState.markUncovered => '●',
    };
  }
}
