part of '../editor_canvas_area.dart';

/// ONE BUILD OF THE INTERACTIVE CANVAS — what the playhead's row shows
/// (the layer stack in a cut, the parked stack in a gap), the pose and
/// selection the manipulators work on, the fade wash past the cut's end,
/// the SE name tags, and the brush host with every verb the canvas
/// answers to.
///
/// 🚨A collaborator carved out of `_EditorCanvasAreaState` (the audit's
/// cognitive cut, Round 6, 2026-09-03): `_buildInteractiveCanvas` was 492
/// lines scoring 77 on the meter. Constructed PER BUILD; it reaches the
/// state through `_state`.
class _InteractiveCanvasBuild {
  _InteractiveCanvasBuild(this._state);

  final _EditorCanvasAreaState _state;

  /// The held-tool road (PEN-7a, I-15) over this canvas's tool channel —
  /// the same [TemporaryTool] the shell's held keys switch through.
  TemporaryTool get _temporaryTool => TemporaryTool(
    memory: _state._toolHold,
    current: () => _state.widget.brushToolState.value,
    change: _state.widget.onBrushToolStateChanged,
  );

  late final bool _isPlaybackActive;
  late final bool _inGap;
  late final bool _cameraOverlayVisible;
  late final ({
    List<CompositeNode<CanvasStackRow>> nodes,
    double activeLayerOpacity,
    List<ResolvedLayerEffect> activeSourceEffects,
  })
  _layerStack;
  late final BrushEditorSelection? _selection;
  late final LayerPoseSample? _interactivePose;
  late final CanvasSize _canvasSize;
  late final double _cutFadeOpacity;
  late final bool _showFadeWash;
  late final Cut? _activeCutForTags;
  late final List<ResolvedSeNameTag> _seNameTags;
  late final Layer? _activeLayer;
  late final bool _canPoseActiveLayer;
  late final Rect? _fitFocusRect;

  Widget buildInteractiveCanvas(
    EditorSessionManager session, {
    required bool isCameraLayerActive,
    required bool showCameraOverlay,
  }) {
    _isPlaybackActive = session.playbackRig.playback.isActive;
    // 🚨★★★ #26 (2026-08-15): A RULER SCRUB IS NOT A SECOND DISPLAY MODE.
    // 「그냥 액티브레이어급으로 그냥 원본 보여주게하고싶어 … 그냥 항상 full」
    //
    // A scrub used to swap the whole viewport to the composite-cache preview
    // — playback's display machinery — and every piece of editing chrome
    // below carried a `!isScrubbing` so it would not draw over a foreign
    // picture. That is the ENTIRE reason those gates existed, so removing
    // the stand-in removes them: PLAYBACK is the one thing that replaces the
    // canvas, and a scrub just moves the playhead the canvas already
    // follows (`_FrameRetargetScope`).
    // R16-⑥ (user semantics): a gap has NO cut — the canvas shows a
    // paperless VOID: no editable cel, no layer content, no paper.
    _inGap = !_isPlaybackActive && session.editingPlayheadInGap;
    // The camera overlay authors the ACTIVE cut's pose — with no cut (a
    // gap parking) there is nothing to author and reading the pose would
    // throw (requireActiveCut).
    //
    // It survives a SCRUB (only `_isPlaybackActive` gates the overlay builder),
    // and that is the whole answer to the ruler-drag framing: the overlay was
    // never the missing half — the track stack's crop was the extra one.
    _cameraOverlayVisible =
        showCameraOverlay && session.activeCutOrNull != null;
    _layerStack = _inGap
        ? (
            nodes: const <CompositeNode<CanvasStackRow>>[],
            activeLayerOpacity: 1.0,
            activeSourceEffects: const <ResolvedLayerEffect>[],
          )
        : session.editingCanvas.stack;
    // T12 field probe (no-op while the Input Inspector is hidden, and it
    // prints only when one of the four answers CHANGES — a line per build
    // would bury the inspector's five-note window in a single scrub).
    //
    // 유저 실기: 컷 끝 너머로 가면 용지와 그림이 사라지고 흰 외곽선만 남는다.
    // The SESSION was measured and is right there (`past_cut_end_is_ordinary_test`
    // pins `_inGap == false`, a non-empty stack and an unchanged duration in
    // all three arrangements), so the disagreement is between what the
    // session answers and what reaches the screen — and only the device can
    // say which. These are the four values the paper hangs on, in order:
    // if `gap` is true the session decided there is no cut here after all;
    // if `nodes` is 0 with `gap` false the plan came back empty; and if all
    // four look right while the paper is gone, the fault is below this
    // widget, in the painting.
    //
    // ⚠️NOT behind an `assert`: the builds the user actually reports from are
    // release ones, and an assert-gated probe is exactly the probe that is
    // missing when it is needed. The visibility flag is the guard instead, so
    // a hidden inspector costs one bool read and never builds the string —
    // the same shape the pan recogniser's probes use.
    _state._noteCanvasProbe(session, _inGap, _layerStack);
    _selection = _inGap
        ? null
        : isCameraLayerActive
        ? session.camera.cameraBackdropSelection
        : session.editingCanvas.activeBrushEditorSelection;
    // The layer shown in the interactive view draws POSED (always-applied
    // transforms, active layer included) with draw-through input.
    _interactivePose = _selection == null
        ? null
        : session.frameVerbs.layerCanvasPoseSample(_selection.layerId);
    // There is no CUT-level pose to compose in: the V row's transform is gone,
    // so the only pose the editing canvas wraps is the active LAYER's.
    //
    // Gap state (no active cut, UI-R9 #3): the void keeps a stable stage
    // geometry — the camera frame size stands in for the missing cut.
    _canvasSize =
        session.activeCutOrNull?.canvasSize ?? session.camera.cameraFrameSize;
    // The cut FADE still follows the cursor (R9-C: fx ALWAYS reflects — dark
    // faded frames are worked with fx off). It is the track's static opacity
    // times the TRANSITION row's ramp now.
    _cutFadeOpacity = session.opacityVerbs.activeCutEditingFadeOpacity();
    _showFadeWash = !_isPlaybackActive && _cutFadeOpacity < 1;
    // The SE rows' on-canvas name tags (R5b, §6-z15) — the editing
    // canvas's copy of what playback and export draw. Playback renders its
    // own (through the frame painter), so this stands down there exactly
    // like the other editing chrome.
    //
    // 🚨F-90 (유저 2026-09-12): 「스토리보드패널, 룰러 드래그 하는동안 se의
    // 네임태그가 캔버스에 존재했던게 다음 컷이나 갭부분까지 남아있음. 안남아있도록
    // 비디오트랙이나 se트랙이나 법 하나로 통일」. The parked content — the track
    // stack a scrub shows past the cut's territory, or a gap — draws the tags
    // of the frame IT shows, the way it draws that frame's picture. These are
    // the ACTIVE cut's at its own cursor, so over the parked picture they were
    // the frame the drag had left. They stand down wherever the picture is not
    // this canvas's: [_inGap] asks exactly that, for the content swap below.
    _activeCutForTags = session.activeCutOrNull;
    _seNameTags = _isPlaybackActive || _inGap || _activeCutForTags == null
        ? const <ResolvedSeNameTag>[]
        : session.seEntries.seNameTagsForCutFrame(
            _activeCutForTags,
            session.currentFrameIndex,
          );
    // R5 #10: WHAT IS SELECTED IS WHAT YOU CAN GRAB.
    //
    // The crosshair used to answer to "the row's lanes are twirled open",
    // which is not a statement about intent at all: opening a row to read a
    // Blur radius put a Position handle on the artwork, and standing on
    // Opacity left that handle there, still moving Position. The standing
    // LANE declares its manipulators now, and a lane that declares none
    // (Opacity, every effect parameter) draws none.
    final activeLayer = _activeLayer = session.activeLayer;
    _canPoseActiveLayer =
        !_isPlaybackActive &&
        !isCameraLayerActive &&
        activeLayer != null &&
        // The gizmo COMMITS a transform track, so the row must actually
        // author one. Every non-camera kind used to, and the camera was
        // covered above — until R6b's adjustment row, which twirls open
        // for its effect lanes while owning no transform at all, and whose
        // commit path throws by design.
        activeLayer.kind.hasLayerTransform &&
        layerKindShowsFxToggle(activeLayer.kind) &&
        // R8: the TRANSFORM group's switch, not the row master — a row
        // with a colour effect off still has a pose to drag.
        session.effectsAndFx.isLayerTransformFxEnabled(activeLayer.id);
    // Camera mode retargets the Fit button at the camera frame's bounds —
    // fitting the cut canvas there framed the wrong rectangle.
    _fitFocusRect = isCameraLayerActive
        ? cameraFrameBoundsInCanvas(
            pose: session.camera.cameraPoseAtCurrentFrame,
            cameraFrameSize: session.camera.cameraFrameSize,
          )
        : null;
    return RepaintBoundary(
      // D13: the actuation gate's navigation region — the canvas PANEL's
      // rect (viewport gestures, zoom buttons, panbars), measured by the
      // gate at event time. Attached here so the region is exactly what
      // the panel lays out, splitter drags and resizes included.
      key: _state.widget.navigationRegionKey,
      // 🚨ONE CANVAS PER PROJECT (I-7). The region key above is the
      // WINDOW's — one GlobalKey for every project — and a GlobalKey
      // carries its element, and every State under it, to wherever it is
      // next built. The canvas area around this is made again per project
      // (`_CanvasAreaKey`), yet the host under this key rode across: it had
      // taken the FIRST project's drawing store once, and a stroke drawn in
      // the next tab went into that store (measured, 2026-09-26). Keyed by
      // the project it draws, the host is made again with the tab.
      child: KeyedSubtree(
        key: ObjectKey(session),
        child: KeyedSubtree(
          key: const ValueKey<String>('main-canvas-brush-host-container'),
          // The tool-state boundary (R18 UI-2): a tool switch rebuilds ONLY
          // the host config — and since H40 ② a setting tweak not even that
          // (below) — every session-derived value above (layer stacks, poses,
          // onion requests) is captured and reused, and the host's element
          // keeps all its state.
          //
          // The STANDING ROW rides the same boundary, SUBSCRIBED rather than
          // read at build time: it is published without a session notify (the
          // claim fires on pointer-down, inside gestures whose contract is
          // silence until release), so a canvas that read it above would go
          // on taking strokes after the user stepped onto a property lane.
          //
          // 🚨H40 ② (2026-09-24): the BRUSH rides it SLICED — the tool and its
          // shape ([BrushCanvasPanel.structureOf]) are the whole of what this
          // config is built from. A size, a flow, a colour used to rebuild the
          // host and the panel under it, relaying out the panel's shell for
          // numbers it does not show; the panel hears those for itself now,
          // and the verbs here read the brush when they run.
          child: SlicedValueListenableBuilder<
            BrushToolState,
            (CanvasTool, CanvasShapeKind?)
          >(
            valueListenable: _state.widget.brushToolState,
            slice: BrushCanvasPanel.structureOf,
            builder: (context, _) => ListenableBuilder(
              listenable: Listenable.merge([
                session.currentRowListenable,
                // D12: the playing cut's identity — fires once per cut
                // crossing (never per tick), and only the host CONFIG
                // changes, like everything else on this boundary.
                _state._playbackFitCut,
              ]),
              builder: (context, _) => _host(
                context,
                session,
                isCameraLayerActive: isCameraLayerActive,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The brush host for the row the playhead stands on, rebuilt on every
  /// notify of the listenables merged above: the manipulator gates read
  /// the standing row HERE (it is published without a session notify),
  /// and every verb the canvas answers to is wired to the session.
  Widget _host(
    BuildContext context,
    EditorSessionManager session, {
    required bool isCameraLayerActive,
  }) {
    final activeLayer = _activeLayer;
    // A `final` local: the null check inside it promotes `activeLayer`
    // for the gates below, which a field never could.
    final canPoseActiveLayer = _canPoseActiveLayer && activeLayer != null;
    final tool = _state.widget.brushToolState.value.tool;
    // D12 × R6q2 (유저 확정 08-18): playback fit is the CAMERA
    // VIEW's — toggle ON frames the camera's output frame at the
    // origin (the painter's frameRect) for as long as it plays;
    // toggle OFF never fits at all (the user's framing is the
    // framing).
    //
    // ★ONE condition, TWO props, so they can never disagree: while
    // playback frames the view, the panel is handed playback's own
    // view object AND the rect to resolve it against. See
    // [_playbackViewport] for why this is a swap and not a write.
    final playbackFraming = _state._playbackFramingRect();
    // INSIDE the builder, deliberately: the standing row is
    // published without a session notify, so a manipulator gate
    // computed above would answer the row you left. Same trap the
    // stroke gate two lines down was written to avoid.
    final standing = session.currentRowListenable.value;
    final showPositionGizmo =
        canPoseActiveLayer &&
        standing is LaneRowAddress &&
        standing.layerId == activeLayer.id &&
        canvasManipulatorsForLane(
          standing.laneId,
        ).contains(CanvasManipulator.transformBox);
    // The box frames the layer's INK, so a blank cel has no box —
    // the crosshair still answers for Position there. Resolved
    // only when something will use it: the scan is memoized on the
    // surface, but asking at all costs a frame lookup.
    final boundsRect = showPositionGizmo
        ? session.layerContentBoundsAt(activeLayer, session.currentFrameIndex)
        : null;
    final transformBoxBounds = boundsRect == null
        ? null
        : Rect.fromLTRB(
            boundsRect.left.toDouble(),
            boundsRect.top.toDouble(),
            boundsRect.rightExclusive.toDouble(),
            boundsRect.bottomExclusive.toDouble(),
          );
    final showAnchorGizmo =
        canPoseActiveLayer &&
        standing is LaneRowAddress &&
        standing.layerId == activeLayer.id &&
        canvasManipulatorsForLane(
          standing.laneId,
        ).contains(CanvasManipulator.anchorPoint);
    final frame = _HostFrame(
      session: session,
      tool: tool,
      activeLayer: activeLayer,
      showPositionGizmo: showPositionGizmo,
      transformBoxBounds: transformBoxBounds,
      showAnchorGizmo: showAnchorGizmo,
      isCameraLayerActive: isCameraLayerActive,
    );
    return MainCanvasBrushHost(
      rowAcceptsStrokes: _EditorCanvasAreaState._rowAcceptsStrokes(
        session.currentRowListenable.value,
      ),
      // MERGED canvas: we own the live-stroke overlay, so the
      // layer stack can paint the active layer inside the
      // composite tree and a folder's group buffer can enclose
      // the layer being drawn on. Playback swaps the whole viewport
      // content, so merged mode stands down there (no underlay
      // builder, no active painter).
      activeStrokeOverlayModel: _isPlaybackActive
          ? null
          : _state._activeStrokeOverlay,
      // 🚨F-116-b / F-164: which cels a transform confirm lands on. The
      // panel does not know the session, and this is the layer that does —
      // so the LADDER is handed down rather than a second walk being
      // written where it could drift from the pixel verbs'.
      //
      // 🗣️유저: 「몇 행에 걸쳐서 적용하던 동시적용은 가능하게 … 여러프레임
      // 확정가능하게」. ⚠️With no range live this answers 「the cel you stand
      // on」, which is why nothing downstream has a case for 「many」.
      transformTargetKeys: session.cells.pixelVerbCellKeys,
      // …each through its OWN row's placement, the one the pixel verbs
      // restate an outline through (a-marquee-on-a-posed-row ④).
      cellPlacementOf: session.cells.placementOf,
      // Camera mode still needs artwork on screen: fall
      // back to the first drawn layer at the playhead.
      selection: _selection,
      // 🚨F-171: where the editing stack stands before the first cel — the
      // cel a press would make, through the SAME gates a stroke target
      // answers. The camera's backdrop and a gap make no cel.
      standingFrameKeyOf: _inGap || isCameraLayerActive
          ? null
          : () {
              final layerId = session.activeLayerId;
              return layerId == null
                  ? null
                  : session.editingCanvas
                        .brushEditorSelectionFor(
                          session.autoFrame.frameIdForNextCel(layerId),
                        )
                        ?.toBrushFrameKey();
            },
      canvasSize: _canvasSize,
      // The cut's guides reach the stroke pipeline through here;
      // the panel maps them into the active layer's artwork space
      // before the view sees them.
      guides: session.cutVerbs.activeCutGuides,
      frameStore: session.renderCaches.brushFrameStore,
      cacheInvalidationSink: session.renderCaches.cacheInvalidationHub,
      // The pixel verbs are pressed on the timeline and write cel
      // surfaces; every surface write goes through this coordinator.
      onCoordinatorChanged: (coordinator) =>
          session.pixelEditingCoordinator = coordinator,
      historyManager: session.historyManager,
      // ⛔The notifier ITSELF. Null in it means "not framed yet",
      // which the panel resolves to the identity at read time — so
      // an untouched canvas re-derives "one artwork pixel per
      // device pixel" every time the effective ratio moves, with
      // nothing stored to go stale. And because the panel writes
      // into this same object, panning no longer round-trips
      // through a `setState` here.
      viewportController: playbackFraming == null
          ? _state._canvasViewport
          : _state._playbackViewport,
      // 유저 R2 #14: the pill takes the corner AWAY from the tool
      // strip — the strip is where the hand already is.
      brushToolState: _state.widget.brushToolState,
      fitFocusRect: _fitFocusRect,
      unframedFit: playbackFraming,
      viewCommands: _state.widget.canvasViewCommands,
      selectionCommands: _state.widget.canvasSelectionCommands,
      cutPieceSlot: _state.widget.cutPieceSlot,
      lastStroke: _state.widget.lastStroke,
      // R13-3: a live stroke holds the prerender warmer — composite
      // warming never shares the UI/raster threads with drawing.
      onStrokeInputActiveChanged: session.setBrushInputActive,
      // The canvas hands the session its stroke lander so a SAVE can land
      // the pen before it snapshots — the same registration shape
      // `onCoordinatorChanged` above uses.
      onStrokeLanderChanged: (lander) =>
          session.liveStrokeLanding.lander = lander,
      // R15-⑤: _selection drags block seeks/cut switches entirely.
      onSelectionInteractionChanged: (active) => active
          ? session.beginSelectionInteraction()
          : session.endSelectionInteraction(),
      // 🚨ONE ANSWER TO 「이 프레스 밑에 셀이 없다」 (I-10 + R26 #35),
      // because two callers ask it now: the interactive view, which
      // stands down on an empty cel, and the shell listener above it
      // for a project that has no editing stack yet.
      //
      // ⛔The TOOL first, and HERE rather than at either caller: the
      // eyedropper reads a colour and the _selection tools mark
      // nothing, so neither wants a block made underneath — and
      // neither earns a 「no frame here」 notice either.
      //
      // Then make the block if the toggle and the row allow it —
      // every one of those gates already lives inside
      // `beginAutoFrameForStroke`, so nothing re-asks them — and
      // otherwise say WHY at the cursor, which only the shell can
      // answer because the refusal is a SECTION question.
      onPressNeedsCel: () {
        return _state._pressNeedsCel(tool, session);
      },
      onStrokeNeedsCel: () => _state._strokeNeedsCel(session),
      takeStrokePrefixCommand: session.autoFrame.takeAutoFrameForStroke,
      onAutoFrameSettled: session.autoFrame.flushAutoFrameForStroke,
      // P5 eyedropper. Picks NEVER switch tools (R11-②): the
      // eyedropper stays armed until the user changes tools,
      // Alt-picks keep the painting tool.
      // R28 #6: the reference is a SETTING — display (the visible
      // composite) or the active layer alone. Either way the
      // sampler maps through a posed layer's inverse (R28 #7), so
      // a transformed layer picks what the screen shows instead of
      // silently reading as paper.
      // Lazy: only reachable with an editable _selection, which a
      // gap state never offers (requireActiveCut = backstop).
      sampleColorAt: (point) => sampleCompositeColor(
        cut: session.requireActiveCut,
        frameIndex: session.currentFrameIndex,
        surfaceResolver: session.brushSurfaceForLayerFrame,
        point: point,
        paperColor: session.projectSettings.projectBackground.paintedArgb,
        source:
            _state.widget.eyedropperSource?.value ??
            CanvasReadSource.display,
        activeLayerId: session.activeLayer?.id,
      ),
      // BOTH stage colors are PROJECT data now (R3b): they go out
      // in exports, so they undo with everything else — the
      // pasteboard's app-state era (R28 #9) survives only as the
      // new-project default.
      //
      // ⛔The floor no longer READS them here. It used to, and being
      // the only host that did is exactly how the timesheet, conte,
      // envelope and viewer ended up on hard black: `CanvasStageColors`
      // says it once for all of them (유저, R4 #2). The COMMIT
      // handlers stay — this is still where the pill's swatches are
      // wired, and writing is not the same question as reading.
      paperColor: session.projectSettings.projectBackground.argb,
      // F-114: a pick is a plane that is there; 「없음」 takes it away and
      // keeps its colour for the next pick.
      paperNone: session.projectSettings.projectBackground.none,
      onPaperColorChanged: (argb) =>
          session.projectSettings.setProjectBackground(ProjectBackground.color(argb)),
      onPaperNone: () => session.projectSettings.setProjectBackground(
        ProjectBackground.color(
          session.projectSettings.projectBackground.argb,
          none: true,
        ),
      ),
      onPasteboardColorChanged: session.projectSettings.setPasteboardColor,
      onPasteboardNone: session.projectSettings.setPasteboardNone,
      onBackdropColorChanged: session.projectSettings.setProjectBackdrop,
      onBackdropNone: session.projectSettings.setProjectBackdropNone,
      onEyedropperPick: (color) => _state.widget.onBrushToolStateChanged?.call(
        _state.widget.brushToolState.value.copyWith(color: color),
      ),
      // PEN-7a: the mapped hold temporarily switches the TOOL —
      // the user's design: reuse the one tool-switch path so the
      // cursor, panels and per-tool settings memory all follow.
      // Release springs back (default) or keeps the switched
      // tool, per the mapping. I-15: a held KEY switches through
      // the same [TemporaryTool] from the shell.
      onTemporaryToolHold: _temporaryTool.hold,
      onTemporaryToolRelease: _temporaryTool.release,
      // PEN-7b: the control-mode touch slots — the flip funnel
      // comes from the shell; the brush-size drag lands here
      // (this widget owns the tool state channel).
      onInvokeAction: _state.widget.onInvokeAction,
      onBrushSizeDragStart: () => _state._brushSizeDragStartSize =
          _state.widget.brushToolState.value.size,
      onBrushSizeDragUpdate: _state._dragBrushSize,
      onBrushSizeDragEnd: () => _state._brushSizeDragStartSize = null,
      flipHud: _state.widget.flipHud,
      // P6 fill: the flood region as ONE mask dab; the panel commits it
      // through the stroke funnel onto the active layer's frame.
      selectionMaskOptions: _state.widget.selectionMaskOptions,
      transformOptions: _state.widget.transformOptions,
      fillDabAt: (point, color, symmetry) => buildFillDab(
        cut: session.requireActiveCut,
        frameIndex: session.currentFrameIndex,
        surfaceResolver: session.brushSurfaceForLayerFrame,
        point: point,
        color: color,
        // TP1: the FILL has its own opacity now — the strip's bar
        // writes the fill's field, not the brush's.
        opacity: _state.widget.brushToolState.value.activeOpacity,
        options: _state.widget.fillOptions?.value ?? const FloodFillOptions(),
        paperColor: session.projectSettings.projectBackground.paintedArgb,
        // The 「현재」 of the fill's reference source (I-36) — the same
        // layer the eyedropper's reads, above.
        activeLayerId: session.activeLayer?.id,
        // The seed arrives through the draw-through wrap, in the posed
        // layer's artwork — the raster is laid in the same space (I-36).
        space: _interactivePose,
        // The same guide the brush obeys, handed down by the view
        // that read it — a symmetry that replicates strokes
        // replicates fills.
        symmetry: symmetry,
        // Extended fills refuse OPEN regions (the flood reached
        // the pasteboard apron wall) — say why nothing filled.
        onOpenRegion: () => showAppNotice(
          _state.context,
          title: AppText.strings.commonNotice,
          message: AppText.strings.noticeFillRegionOpen,
        ),
      ),
      // The SHAPE fill's dab. No cut, no frame, no surfaces: a
      // drawn outline is filled whatever is under it, so it never
      // reads the picture — which is why this line is short and
      // the one above is not.
      shapeFillDabFor: (shape, color) => buildShapeFillDab(
        shape: shape,
        color: color,
        opacity: _state.widget.brushToolState.value.activeOpacity,
        options: _state.widget.fillOptions?.value ?? const FloodFillOptions(),
      ),
      // Layers below/above the active one composite around the
      // interactive view from the layer image cache — this is what makes
      // the other layers (and their visibility/opacity) visible while
      // editing. During playback the composite covers everything. Under
      // an active CUT pose (R9-B) the paper splits out of the wrap: the
      // canvas is the static stage, only the content rides the pose.
      viewportUnderlayBuilder: _isPlaybackActive
          ? null
          : (context, viewport, activeSurfacePainter, floatOverlay) =>
                _underlay(
                  context,
                  viewport,
                  activeSurfacePainter,
                  floatOverlay,
                  frame,
                ),
      interactiveContentOpacity: _layerStack.activeLayerOpacity,
      // The CPU half of the row you are drawing on — see
      // [EditingCanvas.stack].
      activeSourceEffects: _layerStack.activeSourceEffects,
      interactiveContentPose: _interactivePose,
      // The playback view renders the camera framing itself; the editing
      // overlay would show a stale playhead pose on top of it. A scrub
      // keeps the CAMERA overlay only — the preview is the current view
      // moving through time, so the frame stays visible and rides the
      // cursor.
      // The ABOVE-layers stack is gone from here: the merged
      // underlay paints the whole tree in one picture now, which is
      // the only way a group buffer can span the active layer. What
      // is left in the overlay is chrome.
      viewportOverlayBuilder:
          (_cameraOverlayVisible ||
                  showPositionGizmo ||
                  showAnchorGizmo ||
                  _showFadeWash ||
                  session.cutVerbs.activeCutGuides.isNotEmpty ||
                  _seNameTags.isNotEmpty) &&
              !_isPlaybackActive
          ? (context, viewport) => _overlayStack(context, viewport, frame)
          : null,
      // 🚨T28-c: while playback owns the content a press only stops it, so no
      // tool takes the press — the same flag swaps the content in below.
      toolInputEnabled: !_isPlaybackActive,
      contentOverride: _isPlaybackActive
          // The streamer rides ON the picture (REC1-E): the ADR
          // scribe belongs over the projection, never in a side
          // panel. Constant two-child Stack (the overlay shrinks
          // itself) — the sibling-count rule.
          ? (context, viewport) => _state._playbackContent(session, viewport)
          // The parked state (no active cut): the multitrack
          // display path — every covered track's composite stacks
          // where the void used to be, in its own CANVAS space (the
          // crop is playback's). An uncovered frame still shows the
          // void (the stack view renders nothing there).
          : _inGap
          ? (context, viewport) =>
                _state._buildTrackStackView(session, viewport)
          : null,
    );
  }

  /// What is painted UNDER the interactive canvas: the paper and the
  /// composite tree with the active layer inside it (the parked stack in a
  /// gap), with onion skins when the row shows them.
  Widget _underlay(
    BuildContext context,
    CanvasViewport viewport,
    BitmapSurfacePainter? activeSurfacePainter,
    SelectionFloatOverlay floatOverlay,
    _HostFrame frame,
  ) {
    final below = CanvasLayerStackView(
      // MERGED: the whole tree, active layer included, so
      // a folder's group buffer encloses the layer being
      // drawn on. Onion ghosts (P2) sit above the other
      // layers and directly UNDER the active drawing;
      // playback and scrubs never reach here, so they
      // auto-hide. A gap parking shows the VOID (R16-⑥):
      // no ghosts either.
      nodes: _EditorCanvasAreaState._stackNodesWithGhosts(
        _layerStack.nodes,
        _inGap ? const [] : frame.session.onionSkin.onionSkinCanvasRequests(),
      ),
      activeSurfacePainter: activeSurfacePainter,
      // TS1: the _selection's float draws in the active
      // layer's slot, so the rows above it occlude the live
      // preview the way they occlude the landed pixels.
      floatOverlay: floatOverlay,
      imageCache: frame.session.renderCaches.layerFrameImageCache,
      // The census cannot reach a widget State; the session can be reached.
      onBufferBytes: (bytes) =>
          frame.session.renderCaches.canvasBufferBytes = bytes,
      canvasSize: _canvasSize,
      viewport: viewport,
      // R16-⑥: no cut in a gap — no paper (per-cut papers
      // make anything else confusing; the void is the truth).
      paintPaper: !_inGap,
      paperBackground: frame.session.projectSettings.projectBackground,
    );
    // The paper-stays-put split under a cut pose went with
    // the V row's transform: nothing poses the whole cut on
    // the editing canvas, so the layers draw straight.
    return below;
  }

  /// What is stacked OVER the canvas inside the viewport: the guides and
  /// their edit layer, the SE name tags, the fade wash past the cut's end,
  /// the camera overlay, and the transform box / position / anchor gizmos
  /// the standing row admits.
  Widget _overlayStack(
    BuildContext context,
    CanvasViewport viewport,
    _HostFrame frame,
  ) {
    return Stack(
      children: [
        // Guides are EDITING scaffolding: they are drawn
        // here and nowhere else — playback, thumbnails and
        // export never see them, the way a ruler never
        // prints. Under the camera frame and the gizmos,
        // which are chrome about the shot rather than about
        // the drawing.
        if (frame.session.cutVerbs.activeCutGuides.isNotEmpty)
          _state._guideOverlay(
            frame.session,
            viewport,
            _canvasSize,
            frame.tool,
            context,
          ),
        // The handle layer mounts ONLY for the guide tool,
        // so it never stands between the brush and the cel.
        if (frame.tool == CanvasTool.guide)
          _state._guideEditLayer(frame.session, viewport),
        if (_seNameTags.isNotEmpty)
          _state._seNameTagOverlay(viewport, _canvasSize, _seNameTags, context),
        if (_showFadeWash)
          _state._cutFadeWash(
            viewport,
            _canvasSize,
            frame.session,
            _cutFadeOpacity,
            context,
          ),
        if (_cameraOverlayVisible)
          _state._cameraOverlay(
            frame.session,
            viewport,
            frame.isCameraLayerActive,
          ),
        if (frame.showPositionGizmo && frame.transformBoxBounds != null)
          _state._transformBox(
            frame.transformBoxBounds!,
            frame.session,
            frame.activeLayer!,
            _canvasSize,
            viewport,
          ),
        if (frame.showPositionGizmo)
          _state._positionGizmo(frame.session, frame.activeLayer!, viewport),
        if (frame.showAnchorGizmo)
          _state._anchorGizmo(frame.session, frame.activeLayer!, viewport),
      ],
    );
  }
}

/// What one build of the brush host settled before wiring the host: the
/// session it wires, the tool, the active layer, the manipulator gates the
/// standing row answered, and whether the camera row is active. The overlay
/// and underlay builders read it instead of a dozen captured locals.
class _HostFrame {
  const _HostFrame({
    required this.session,
    required this.tool,
    required this.activeLayer,
    required this.showPositionGizmo,
    required this.transformBoxBounds,
    required this.showAnchorGizmo,
    required this.isCameraLayerActive,
  });

  final EditorSessionManager session;

  /// The TOOL and not the brush: this build reruns for the tool and its
  /// shape alone ([BrushCanvasPanel.structureOf], H40 ②), so a size or a
  /// colour held here would be the one from the last tool switch.
  final CanvasTool tool;

  /// Non-null whenever [showPositionGizmo] or [showAnchorGizmo] is true:
  /// both gates include the null check.
  final Layer? activeLayer;
  final bool showPositionGizmo;
  final Rect? transformBoxBounds;
  final bool showAnchorGizmo;
  final bool isCameraLayerActive;
}
