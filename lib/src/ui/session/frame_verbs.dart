import '../../models/attached_layer_resolve.dart';
import '../../models/audio_clip.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/cut.dart' show Cut;
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_coverage.dart';
import '../../models/flip_column_step.dart';
import '../../models/timeline_row_address.dart';
import '../../services/cut_frame_composite_plan.dart';
import '../../services/layer_pose_paint.dart';
import '../../models/working_panel.dart';
import '../timeline/timeline_cell_exposure_state.dart';
import 'active_cut_controllers.dart';
import 'independent_clip_mint.dart';
import 'render_caches.dart';
import 'session_roles.dart';
import 'track_axis_walk.dart';

/// The FRAME VERBS — the playhead's frame and what stands there: stepping
/// and flipping to a frame, the selected frame's name, duration and status
/// text, duplicating, renaming and linking it, and the pose sample the
/// canvas wraps the active layer in. Each reads the timeline controller;
/// the session stays the facade that names them.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP
/// cut, Round 6, 2026-09-03). Measured before cutting: nineteen host
/// methods whose only non-infrastructure field was the timeline
/// controller. It names the roles it needs in its constructor.
class FrameVerbs {
  FrameVerbs({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required FrameIds frameIds,
    required TimelineAccess timeline,
    required ActiveCutControllers controllers,
    required SessionInternals internals,
    required RenderCaches renderCaches,
    required TrackAxisWalk trackAxis,
    required WorkingPanel Function() workingPanel,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _frameIds = frameIds,
       _timeline = timeline,
       _controllers = controllers,
       _internals = internals,
       _renderCaches = renderCaches,
       _trackAxis = trackAxis,
       _workingPanel = workingPanel;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final TimelineAccess _timeline;
  final ActiveCutControllers _controllers;
  final SessionInternals _internals;
  final RenderCaches _renderCaches;

  /// The TRACK's axis, walked — the storyboard's rows and a gap's steps.
  final TrackAxisWalk _trackAxis;

  /// The panel being worked in ([Standing.workingPanel]): the storyboard's
  /// rows walk the track's axis, the timeline's the cut's.
  final WorkingPanel Function() _workingPanel;

  /// The placement the interactive canvas shows [layerId] with at the
  /// playhead — the draw-through wrap input, and so the space the pen, the
  /// fill's seed and the held pick are in. Null = identity (no transform
  /// work, fx bypassed, or no such layer), which skips the wrap: the
  /// ALWAYS-APPLIED rule (the active layer shows its transform too; the old
  /// edit-in-artwork-space rule is retired, R3 ⑩).
  ///
  /// It is [layerPlacementAt] — the one the stack paints the row with — so a
  /// row inside a posed folder takes the pen where it shows.
  LayerPoseSample? layerCanvasPoseSample(LayerId layerId) =>
      _atThePlayhead(layerId, layerPlacementAt);

  /// Where [layerId]'s OWN pose lives on the canvas at the playhead — the
  /// placement of the folders above it ([layerParentPlacementAt]). Null =
  /// the canvas itself. What the gizmos that edit that pose stand in.
  LayerPoseSample? layerParentPlacement(LayerId layerId) =>
      _atThePlayhead(layerId, layerParentPlacementAt);

  /// [placement] asked of [layerId]'s row in the open cut at the playhead —
  /// null with no cut open or no such row.
  LayerPoseSample? _atThePlayhead(
    LayerId layerId,
    LayerPoseSample? Function({
      required Cut cut,
      required Layer layer,
      required int frameIndex,
    })
    placement,
  ) {
    final cut = _project.activeCutOrNull;
    final layer = cut?.layers.byId(layerId);
    return cut == null || layer == null
        ? null
        : placement(
            cut: cut,
            layer: layer,
            frameIndex: _controllers.timelineController.currentFrameIndex,
          );
  }

  Frame? get selectedFrame {
    final layer = _selection.activeLayer;
    if (layer == null) {
      return null;
    }

    return _controllers.timelineController.getSelectedFrameForLayer(layer);
  }

  bool get canCreateDrawingAtCurrentFrame {
    final layer = _selection.activeLayer;
    // ⛔[LayerKind.takesAuthoredCels], not `holdsDrawings`: the direction row
    // holds cels since R27 #16 and could not be given one (유저: 「프레임이
    // 없다고 뜨거든」).
    if (layer == null || !layer.kind.takesAuthoredCels) {
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
    if (layer.kind.holdsSingleCel && layer.frames.isNotEmpty) {
      return false;
    }

    return _controllers.timelineController.canCreateDrawingAt(
      layer: layer,
      frameIndex: _controllers.timelineController.currentFrameIndex,
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
    if (_selection.bandNamesRowsThisPressWouldMiss) {
      return false;
    }
    final layer = _selection.activeLayer;
    // ⛔[LayerKind.takesAuthoredCels], not `holdsDrawings`: a direction
    // row's block is its span (R27), and 「복사든 뭐든 싹다」 was this
    // button sitting dark over it.
    if (layer == null || !layer.kind.takesAuthoredCels) {
      return false;
    }
    // D22: a SINGLE-CEL (image) row's one block is pinned by the covering
    // normalization, so the duplicate never lands — but the independent
    // half MINTS a cel first, leaving a drawing no exposure references
    // and nothing on screen shows. A second cel is the one thing this
    // row's definition rules out.
    if (layer.kind.holdsSingleCel) {
      return false;
    }
    return coveringDrawingBlockAt(
          layer.timeline,
          _controllers.timelineController.currentFrameIndex,
        ) !=
        null;
  }

  void duplicateActiveBlock({required bool linked}) {
    final layer = _selection.activeLayer;
    if (layer == null || !canDuplicateActiveBlock) {
      return;
    }
    final block = coveringDrawingBlockAt(
      layer.timeline,
      _controllers.timelineController.currentFrameIndex,
    );
    if (block == null) {
      return;
    }
    final clip = _controllers.timelineController.copyRunForLayer(
      layerId: layer.id,
      index: block.startIndex,
      count: block.endIndexExclusive - block.startIndex,
    );
    var bornFrames = const <Frame>[];
    var bornSounds = const <AudioClip>[];
    var placed = clip;
    var minted = const <FrameId, FrameId>{};
    if (!linked) {
      final independent = mintIndependentClip(
        clip: clip,
        from: [(cels: layer.frames, sounds: layer.audioClips)],
        namesAreIdentity: layer.kind.celNameIsIdentity,
        mint: () => _frameIds.mintFrameId(layer.id),
      );
      placed = independent.clip;
      bornFrames = independent.born;
      bornSounds = independent.bornSounds;
      minted = independent.minted;
    }
    _controllers.timelineController.spliceRunsForLayers(
      runs: [
        (
          layerId: layer.id,
          index: block.endIndexExclusive,
          liftCount: 0,
          clip: placed,
          bornFrames: bornFrames,
          bornSounds: bornSounds,
        ),
      ],
      description: linked ? 'Link duplicate frames' : 'Duplicate frames',
    );
    final cut = _project.activeCutOrNull;
    if (cut != null) {
      final store = _renderCaches.brushFrameStore;
      carryBakedPictures(
        internals: _internals,
        store: store,
        cut: cut,
        to: layer.id,
        minted: minted,
        pictureOf: (source) => store.bakedSurfaceOrNull(
          _internals.brushFrameKeyForCut(cut, layer.id, source),
        ),
      );
    }
    _changes.notifyChanged();
  }

  bool get canRenameFrameAtCurrentFrame {
    final layer = _selection.activeLayer;
    // 🚨A direction row's cels have no names to edit (유저 2026-09-12:
    // 「이름으로 링크 안됨은 안해도됨. 링크는 해도되게 해서 법을 최대한
    // 통일하되 이름을 안보이게, 수정못하게 해서 링크를 애초에 불가능하도록.
    // 이름없으면 독립적인거니까」) — so the link law stays the one every row
    // keeps, and a name that can never be typed can never link two spans.
    if (layer == null || layer.kind.spansRideBlocks) {
      return false;
    }

    return _controllers.timelineController.canRenameFrameAt(
      layer: layer,
      frameIndex: _controllers.timelineController.currentFrameIndex,
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
    final layer = _selection.activeLayer;
    final frame = selectedFrame;
    if (layer == null || frame == null || !canRenameFrameAtCurrentFrame) {
      return null;
    }

    final allowDuplicateName = !layer.kind.celNameIsIdentity;
    if (!allowDuplicateName) {
      final conflictingFrameId = _controllers.timelineController
          .conflictingFrameIdForRename(
            layer: layer,
            frameId: frame.id,
            name: name,
          );
      if (conflictingFrameId != null) {
        return conflictingFrameId;
      }
    }

    _controllers.timelineController.renameFrameForLayer(
      layerId: layer.id,
      frameId: frame.id,
      name: name,
      allowDuplicateName: allowDuplicateName,
    );
    _changes.notifyChanged();
    return null;
  }

  void linkSelectedFrame(FrameId targetFrameId) {
    final layer = _selection.activeLayer;
    final frame = selectedFrame;
    if (layer == null || frame == null) {
      return;
    }

    _controllers.timelineController.linkFrameForLayer(
      layerId: layer.id,
      sourceFrameId: frame.id,
      targetFrameId: targetFrameId,
    );
    _changes.notifyChanged();
  }

  int get currentFrameIndex =>
      _controllers.timelineController.currentFrameIndex;

  /// Steps the playhead one frame back (flipping `,`) — a committed seek.
  void selectPreviousFrame() {
    _stepOneFrame(forward: false);
  }

  /// Steps the playhead one frame forward (flipping `.`).
  void selectNextFrame() {
    _stepOneFrame(forward: true);
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
  /// ↩️**뒤집혔다 — F-148** (유저 2026-09-16: 「컨트롤+화살표로 1프레임 이동이
  /// **안먹힐때가 있는듯**. 로직 싹 점검하고 **법 통일할거 통일해서
  /// 근본/구조적해결**」). 여기엔 「[selectNextFrame]·[selectPreviousFrame] 은
  /// 컷 안에 갇힌 한 프레임 이동이고 그건 그것대로 옳다(플립이 아닌 호출자가
  /// 쓴다)」고 적혀 있었는데, **그 「호출자」가 유저의 Ctrl+화살표와 `,`·`.`
  /// 였다.** 걷기는 이 축 위의 한 걸음이고 축은 하나다 — 🧪컷의 마지막
  /// 프레임에서 세 행 전부 제자리였다(2026-09-17). 걷기는 이제
  /// [_stepOneFrame] 을 통해 같은 착지로 온다.
  void _flipToFrame(int landing) {
    final floored = landing < 0 ? 0 : landing;
    if (floored != _controllers.timelineController.currentFrameIndex) {
      _selection.selectFrameIndex(floored);
    }
  }

  /// 🚨★★★**한 프레임을 걷는다** — Ctrl+화살표와 `,`·`.`, 그리고 블록이 없는
  /// 행의 플립까지 전부 여기로 온다 (F-148).
  ///
  /// ⛔**축을 먼저 정하고, 그 축 위에서 잰다.** 컷 위에 서 있으면 컷 지역
  /// 프레임이고, 갭에 서 있으면 그런 축이 없으니 **전역 프레임**이다 — 컷 지역
  /// 인덱스는 갭에서 0 이라 그걸로 재면 걸음이 어디로도 가지 않는다.
  /// [TrackAxisWalk.flipPanels] 가 「잰 축 위에 내린다」고 적어 둔 그 규칙의
  /// 나머지 절반이다.
  ///
  /// The storyboard's rows ALL live on the track's axis, so while it is the
  /// panel being worked in a step is a track frame too: Ctrl+→ on its V row
  /// crosses into the next cut the way its flip does.
  void _stepOneFrame({required bool forward}) {
    if (_workingPanel() == WorkingPanel.storyboard ||
        _project.activeCutOrNull == null) {
      _trackAxis.stepOneFrame(forward: forward);
      return;
    }
    _flipToFrame(
      _controllers.timelineController.currentFrameIndex + (forward ? 1 : -1),
    );
  }

  /// Steps one BLOCK along the current row (Ctrl+`,` back, Ctrl+`.`
  /// forward). R10 #13, the user's flip rule: `flip_column_step.dart`.
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
    //
    // ⚠️The TIMELINE's four, not the marquee (F-86, 유저 2026-09-12: 「뭘
    // 하든 안사라지도록. 다른 컷 가도」). F-13's rule is about the SELECTION
    // RANGE on the sheet; the artwork's marquee is a tool in hand, and a
    // flip is a move to another column, not a 선택 해제.
    _selection.clearTimelineSelections();
    switch (_internals.currentRow) {
      case TrackRowAddress(:final trackId):
        _trackAxis.flipPanels(trackId, forward: forward);
      case LayerRowAddress(:final layerId)
          when _workingPanel() == WorkingPanel.storyboard:
        // The panel being worked in is the one whose row this is — and an S
        // row or the transition row stands on BOTH panels under one address.
        _trackAxis.flipTrackRow(layerId, forward: forward);
      case LayerRowAddress(:final layerId):
        final layer = _project.layerById(layerId) ?? _selection.activeLayer;
        if (layer == null) {
          // No such layer to stand on — the playhead is parked in a GAP
          // (no cut, so no rows), or the stored row outlived its cut. The
          // row you are actually on is the TRACK, so walk its panels rather
          // than dead-ending: that is how a gap is stepped out of.
          _trackAxis.flipPanels(_selection.selectedTrackId, forward: forward);
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
        // 컷 끝에 갇혀 있던 자리다. F-148: 이제 [selectNextFrame] 자신이 그
        // 착지로 오므로, 한 프레임을 걷는 입구는 [_stepOneFrame] 하나다.
        _stepOneFrame(forward: forward);
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
    if (_project.activeCutOrNull == null) {
      return; // Gap state: no cut axis — the TRACK row is the one to walk.
    }
    final current = _controllers.timelineController.currentFrameIndex;
    final next = flipColumnStep(
      frame: current,
      direction: forward ? 1 : -1,
      columnAt: (frame) => flipColumnOfRow(layer, frame),
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
    //
    // 🚨F-147 (유저 2026-09-16): 「기준레이어 엣지 움직일때 어태치 동기
    // 레이어의 해당 프레임블록의 프레임이름이 엣지 움직일때만 1로보이는 상황
    // 발생 … 해당 관련로직 싹 점검」. The CEL used to be read off the
    // committed base at [frameIndex], while the row paints [layer] — which a
    // drag derives from the PREVIEWED base. Dragging 4's lead edge into the
    // 1 before it put 4's start over a committed 1, and the mirror printed
    // that. The cel is the one [layer] shows; only its NAME is the base's.
    if (isSyncedAttachedLayer(layer)) {
      final base = attachedBaseOf(
        layer,
        _project.activeCutOrNull?.layers ?? const <Layer>[],
      );
      if (base != null) {
        final shown = _controllers.timelineController.resolveFrameIdForLayer(
          layer: layer,
          frameIndex: frameIndex,
        );
        final baseCel = shown == null
            ? null
            : attachedBaseFrameIdOf(layer, shown);
        return baseCel == null ? null : base.frameById(baseCel)?.name;
      }
    }
    return _controllers.timelineController
        .resolveFrameForLayer(layer: layer, frameIndex: frameIndex)
        ?.name;
  }

  int? get selectedEffectiveDuration {
    final layer = _selection.activeLayer;
    if (layer == null || selectedFrame == null) {
      return null;
    }
    return _controllers.timelineController.effectiveDurationForLayerAt(
      layer: layer,
    );
  }

  String get currentFrameStatusText {
    return 'Frame: ${_controllers.timelineController.currentFrameIndex + 1}';
  }

  String currentFrameDisplayLabel(Layer? layer, Frame? frame) {
    if (layer == null) {
      return '-';
    }
    final frameIndex = _controllers.timelineController.currentFrameIndex;
    final celNumber = frame?.celNumber;
    final exposureState = _timeline.exposureStateForLayer(layer, frameIndex);
    return switch (exposureState) {
      TimelineCellExposureState.drawingStart => celNumberOrMark(frame?.name),
      TimelineCellExposureState.held => celNumber ?? '',
      TimelineCellExposureState.markHeld =>
        celNumber == null ? inbetweenMark : '$celNumber $inbetweenMark',
      TimelineCellExposureState.uncovered => 'X',
      TimelineCellExposureState.markUncovered => inbetweenMark,
    };
  }
}
