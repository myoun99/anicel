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

  /// Whether the run that plays is drawn on THIS canvas
  /// ([_EditorCanvasAreaState._playsOnTheCanvas]): the picture stays — the
  /// rows' images, at the frame the run moved the playhead to — and the
  /// editing goes, as it goes under any run.
  late final bool _canvasPlays;
  late final bool _inGap;
  late final bool _cameraOverlayVisible;
  late final ({
    List<CompositeNode<CanvasStackRow>> nodes,
    double activeLayerOpacity,
    List<ResolvedLayerEffect> activeSourceEffects,
  })
  _layerStack;
  late final BrushEditorSelection? _selection;
  late final LayerPlacement? _interactivePose;
  late final CanvasSize _canvasSize;
  late final Layer? _activeLayer;
  late final bool _canPoseActiveLayer;
  late final Rect? _fitFocusRect;

  /// The cel the interactive view stands on and the pose it draws it in —
  /// asked by the build and by the area's drag slice
  /// (`_EditorCanvasAreaState._panelShows`), so the two cannot disagree
  /// about what the panel is handed.
  static ({BrushEditorSelection? selection, LayerPlacement? pose})
  standingOf(
    EditorSessionManager session, {
    required bool inGap,
    required bool isCameraLayerActive,
  }) {
    final selection = inGap
        ? null
        : isCameraLayerActive
        ? session.camera.cameraBackdropSelection
        : session.editingCanvas.activeBrushEditorSelection;
    // The layer shown in the interactive view draws POSED (always-applied
    // transforms, active layer included) with draw-through input.
    return (
      selection: selection,
      pose: selection == null
          ? null
          : session.frameVerbs.layerCanvasPoseSample(selection.layerId),
    );
  }

  Widget buildInteractiveCanvas(
    EditorSessionManager session, {
    required bool isCameraLayerActive,
    required bool showCameraOverlay,
  }) {
    _isPlaybackActive = session.playbackRig.playback.isActive;
    _canvasPlays = _state._playsOnTheCanvas;
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
    _inGap = !_isPlaybackActive && session.editingSession.playheadInGap;
    // The camera overlay authors the ACTIVE cut's pose — with no cut (a
    // gap parking) there is nothing to author (↩️ nor would reading the pose
    // throw: `displayedCameraPose` is null there).
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
        : _canvasPlays
        ? session.editingCanvas.playingStack
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
    final standing = standingOf(
      session,
      inGap: _inGap,
      isCameraLayerActive: isCameraLayerActive,
    );
    _selection = standing.selection;
    _interactivePose = standing.pose;
    // There is no CUT-level pose to compose in: the V row's transform is gone,
    // so the only pose the editing canvas wraps is the active LAYER's.
    //
    // Gap state (no active cut, UI-R9 #3): the void keeps a stable stage
    // geometry — the camera frame size stands in for the missing cut.
    _canvasSize =
        session.activeCutOrNull?.canvasSize ?? session.camera.cameraFrameSize;
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
                session.standing.currentRowListenable,
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
    final standing = session.standing.currentRowListenable.value;
    final standingLane =
        canPoseActiveLayer &&
            standing is LaneRowAddress &&
            standing.layerId == activeLayer.id
        ? standing.laneId
        : null;
    final manipulators = standingLane == null
        ? const <CanvasManipulator>{}
        : canvasManipulatorsForLane(standingLane);
    final boxGrabbable = manipulators.contains(CanvasManipulator.transformBox);
    final crossGrabbable = manipulators.contains(
      CanvasManipulator.anchorPoint,
    );
    // The box frames the layer's INK — or, on a blank cel, the canvas
    // (the transform tool's own rule, [CanvasSelectionShape.wholePicture]),
    // which stands in for the picture under the cross as well (F-387).
    // Resolved only when something will use it: the scan is memoized on
    // the surface, but asking at all costs a frame lookup.
    final inkBounds = (boxGrabbable || crossGrabbable) && activeLayer != null
        ? session.renderCaches.layerContentBoundsAt(
            activeLayer,
            session.currentFrameIndex,
          )
        : null;
    // An effect that draws its own picture declares ITS box (F-477), and a
    // point its cross (I-132-Q12 b) — on its own switch, as the
    // transform's box is on the transform's ([effectBoxedOn]).
    final effectBox =
        activeLayer != null &&
            standing is LaneRowAddress &&
            standing.layerId == activeLayer.id
        ? effectBoxedOn(activeLayer.effects, standing.laneId)
        : null;
    final frame = _HostFrame(
      session: session,
      tool: tool,
      activeLayer: activeLayer,
      boxGrabbable: boxGrabbable,
      inkBounds: inkBounds,
      crossGrabbable: crossGrabbable,
      effectBox: effectBox,
      referenceBox:
          effectBox == null &&
          _referenceBoxShown(activeLayer, standing, tool),
      isCameraLayerActive: isCameraLayerActive,
      pathLane: switch (standingLane) {
        final lane? => switch (transformPropertyOfLaneId(lane)) {
          final property? when walksAPath(property) => property,
          _ => null,
        },
        null => null,
      },
    );
    return MainCanvasBrushHost(
      rowAcceptsStrokes: _EditorCanvasAreaState._standingRowTakesStrokes(
        session,
      ),
      toolCursorsEnabled: _EditorCanvasAreaState._standingRowIsDrawn(session),
      // MERGED canvas: we own the live-stroke overlay, so the
      // layer stack can paint the active layer inside the
      // composite tree and a folder's group buffer can enclose
      // the layer being drawn on. A run draws on nothing, so
      // merged mode stands down while one plays: the composite
      // view has no underlay at all, and a run the canvas plays
      // draws every row as an image (no active painter).
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
      // on」, which is why nothing downstream has a case for 「many」 — and
      // a FOLDER stands for the drawing rows inside it (I-37-Q1 「변형만」).
      transformTargetKeys: session.pixelVerbs.transformCellKeys,
      // …each through its OWN row's placement, the one the pixel verbs
      // restate an outline through (a-marquee-on-a-posed-row ④).
      cellPlacementOf: session.pixelVerbs.placementOf,
      // I-37: stood on a folder, a transform takes up every drawing row
      // inside it — the same ladder's answer at the playhead.
      transformCelsUnderfoot: session.pixelVerbs.transformCelsUnderfoot,
      // F-293: the cut tool's stamp lands where 픽셀 붙여넣기 lands — the
      // ground is read by the one that reads it for the paste.
      pieceGround: session.pixelVerbs.pieceGround,
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
          session.pixelEditing.coordinator = coordinator,
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
      textCommands: _state.widget.canvasTextCommands,
      textToolOptions: _state.widget.textToolOptions,
      cutPieceSlot: _state.widget.cutPieceSlot,
      lastStroke: _state.widget.lastStroke,
      // R13-3: a live stroke holds the prerender warmer — composite
      // warming never shares the UI/raster threads with drawing.
      onStrokeInputActiveChanged: session.setCanvasStroke,
      // The canvas holds up, in the session's hand, what a SAVE lands
      // before it snapshots — counted, not the last word ([ViewHand]:
      // a view built anew comes up before the old one goes down).
      strokeLander: session.liveStrokeLanding.lander,
      // A selection drag holds the prerender's warming. ↩️F-196: it also
      // blocked seeks and cut switches (R15-⑤) — only a stroke does now.
      onSelectionInteractionChanged: (active) => active
          ? session.beginSelectionInteraction()
          : session.endSelectionInteraction(),
      // 🚨ONE ANSWER TO 「이 프레스 밑에 셀이 없다」 (I-10 + R26 #35),
      // because two callers ask it now: the interactive view, which
      // stands down on an empty cel, and the panel's tool entrance for a
      // press no layer under it hears (`_CanvasPanelTap.pressNoLayerHears`).
      //
      // ⛔The TOOL first, and HERE rather than at either caller: the
      // eyedropper reads a colour and the _selection tools mark
      // nothing, so neither wants a block made underneath — and
      // neither earns a 「no frame here」 notice either.
      //
      // Then make the block if the row, the toggle and the layer
      // allow it — the row in `_strokeNeedsCel` (H19's question is
      // the shell's; ↩️F-196: it was missing, and a lane's press made
      // a block), the rest inside `beginAutoFrameForStroke`, so
      // nothing re-asks them — and
      // otherwise say WHY at the cursor, which only the shell can
      // answer because the refusal is a SECTION question.
      onPressNeedsCel: () {
        return _state._pressNeedsCel(tool, session);
      },
      // 🗣️I-113: a held cell is a place a mark makes its own cel, as the ＋
      // does there, when the toggle is on — the auto frame's own answer,
      // asked at the press.
      markMakesItsOwnCel: () => session.autoFrame.markMakesItsOwnCel,
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
        surfaceResolver: session.renderCaches.brushSurfaceForLayerFrame,
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
      // ↩️F-272 put those panels back on black — on purpose, in one
      // place (`BrushCanvasPanel.canvasBase`).
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
      // Behind the canvas size's wait window: each cuts every picture past
      // the wall it moves (F-432).
      onPasteboardSizeChanged: (size) => unawaited(
        resizeBehindTheWaitWindow(
          context,
          () => session.projectSettings.setPasteboardSize(size),
          title: AppText.strings.pasteboardTitle,
          ahead: (report) => session.projectSettings.cutPasteboardAhead(
            size: size,
            report: report,
          ),
        ),
      ),
      onPasteboardInUseChanged: (inUse) => unawaited(
        resizeBehindTheWaitWindow(
          context,
          () => session.projectSettings.setPasteboardInUse(inUse),
          title: AppText.strings.pasteboardTitle,
          ahead: (report) => session.projectSettings.cutPasteboardAhead(
            inUse: inUse,
            report: report,
          ),
        ),
      ),
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
          _state.widget.brushToolState.value.activeSize,
      onBrushSizeDragUpdate: _state._dragBrushSize,
      onBrushSizeDragEnd: () => _state._brushSizeDragStartSize = null,
      flipHud: _state.widget.flipHud,
      leftPill: _state.widget.leftPill,
      // P6 fill: the flood region as stamp pieces; the panel commits them
      // through the stroke funnel onto the active layer's frame.
      selectionMaskOptions: _state.widget.selectionMaskOptions,
      transformOptions: _state.widget.transformOptions,
      fillDabsAt: (point, color, symmetry) => buildFillDabs(
        cut: session.requireActiveCut,
        frameIndex: session.currentFrameIndex,
        surfaceResolver: session.renderCaches.brushSurfaceForLayerFrame,
        point: point,
        color: color,
        // TP1: the FILL has its own opacity now — the strip's bar
        // writes the fill's field, not the brush's.
        opacity: _state.widget.brushToolState.value.activeOpacity,
        options: _state.widget.fillOptions?.value ?? const FloodFillOptions(),
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
        // The apron reaches as far as the pasteboard does (I-109).
        pasteboardReach: session.repository.requireProject().pasteboardReach,
      ),
      // The SHAPE fill's pieces. No cut, no frame, no surfaces: a
      // drawn outline is filled whatever is under it, so it never
      // reads the picture — which is why this line is short and
      // the one above is not.
      shapeFillDabsFor: (area, color) => buildRegionFillDabs(
        region: area,
        color: color,
        opacity: _state.widget.brushToolState.value.activeOpacity,
        options: _state.widget.fillOptions?.value ?? const FloodFillOptions(),
      ),
      // Layers below/above the active one composite around the
      // interactive view from the layer image cache — this is what makes
      // the other layers (and their visibility/opacity) visible while
      // editing. A run the canvas plays is drawn HERE too, every row an
      // image; the whole film, on the track stack, covers everything. Under an
      // active CUT pose (R9-B) the paper splits out of the wrap: the canvas
      // is the static stage, only the content rides the pose.
      viewportUnderlayBuilder: _isPlaybackActive && !_canvasPlays
          ? null
          : (context, viewport, activeSurfacePainter, floats) => _underlay(
              context,
              viewport,
              activeSurfacePainter,
              floats,
              frame,
            ),
      interactiveContentOpacity: _layerStack.activeLayerOpacity,
      // The CPU half of the row you are drawing on — see
      // [EditingCanvas.stack].
      activeSourceEffects: _layerStack.activeSourceEffects,
      interactiveContentPose: _interactivePose,
      // The track stack renders the camera framing itself; the editing
      // overlay would show a stale playhead pose on top of it. A scrub
      // keeps the CAMERA overlay — the preview is the current view moving
      // through time, so the frame stays visible and rides the cursor —
      // and a run the canvas plays keeps what the picture has
      // ([_overlayStack]).
      // The ABOVE-layers stack is gone from here: the merged
      // underlay paints the whole tree in one picture now, which is
      // the only way a group buffer can span the active layer. What
      // is left in the overlay is chrome.
      // Always there while editing, whatever it holds: what it shows moves
      // with a drag it hears for itself ([_overlay]), and a slot that came
      // and went with the SE tags or the fade would be the area's to rebuild
      // for every drag that moved them.
      viewportOverlayBuilder: _isPlaybackActive && !_canvasPlays
          ? null
          : (context, viewport) => _overlay(context, viewport, frame),
      // F-222: the standing row's box, over every tool — always there while
      // editing, whatever it holds, for the overlay's reason above. A RUN
      // puts its layer here instead, whatever draws it: the clock's ticker,
      // the press that stops it, the bar, and the streamer the ADR scribe
      // rides on the picture (REC1-E) — over the picture's overlay, which a
      // fade's wash must not cover ([_EditorCanvasAreaState._runLayer]).
      viewportControlsBuilder: _isPlaybackActive
          ? (context, viewport) => _state._runLayer(session)
          : (context, viewport) => _controls(context, viewport, frame),
      // 🚨T28-c: while playback owns the content a press only stops it, so no
      // tool takes the press — the same flag swaps the content in below.
      toolInputEnabled: !_isPlaybackActive,
      // A run the canvas plays builds no interactive view: the picture is
      // the underlay's, the press is the run's, and nothing is drawn on.
      contentOverride: _canvasPlays
          ? (context, viewport) => const SizedBox.expand()
          // ALL-CUTS playback watches the whole stage: the frame is the
          // track stack on the clock's global axis (R3a) — a selected-track
          // gap shows what the OTHER tracks hold there instead of the void.
          : _isPlaybackActive
          ? (context, viewport) => _state._buildTrackStackView(
              session,
              viewport,
              ofTheRun: true,
            )
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

  /// A part of the canvas that follows a drag on its own: [build] again,
  /// alone, for each step that changes a row it could show
  /// ([_EditorCanvasAreaState._rowsShownBy]), inside its own [TickLayer] —
  /// and for each frame a run the canvas plays steps the playhead to, which
  /// the area leaves to it ([_FrameRetargetScope]).
  ///
  /// 🚨canvas-wakes-for-what-it-shows: the whole canvas AREA used to be
  /// rebuilt for a drag step, under the panel content's LayoutBuilder — so a
  /// step relaid out and repainted all of it (measured 09-29: layout was
  /// the largest share of a step, ahead of build and paint) for a picture
  /// and some chrome.
  ///
  /// ⚠️The run's builder is there standing still too, answering nothing: a
  /// builder that came and went with the run would remount what it holds at
  /// the run's start and its end — the stack view's images with it.
  Widget _followingDragAndRun(
    EditorSessionManager session,
    WidgetBuilder build,
  ) => TickLayer(
    child: SlicedValueListenableBuilder<TimelineDragPreview?, _DragAsShown>(
      valueListenable: session.dragPreview,
      slice: (preview) => _EditorCanvasAreaState._rowsShownBy(session, preview),
      builder: (context, _) => SlicedValueListenableBuilder<int, int?>(
        valueListenable: session.editingFrameCursor,
        slice: (frame) => _canvasPlays ? frame : null,
        builder: (context, _) => build(context),
      ),
    ),
  );

  /// What is painted UNDER the interactive canvas: the paper and the
  /// composite tree with the active layer inside it (the parked stack in a
  /// gap), with onion skins when the row shows them — seen through the
  /// camera while a run plays here with the camera view on ([CameraShot]).
  /// It follows a drag, and a run the canvas plays, itself
  /// ([_followingDragAndRun]), so the tree is asked afresh at each of its
  /// builds.
  Widget _underlay(
    BuildContext context,
    CanvasViewport viewport,
    BitmapSurfacePainter? activeSurfacePainter,
    CanvasFloats floats,
    _HostFrame frame,
  ) => _followingDragAndRun(frame.session, (context) {
    final session = frame.session;
    final look = _look(session);
    final shot = _shotAt(session, look, viewport);
    final project = session.repository.requireProject();
    return CameraShot(
      view: viewport,
      shot: shot,
      canvasSize: _canvasSize,
      background: session.projectSettings.projectBackground,
      pasteboardColor: stageColorOnScreen(project.pasteboardArgb),
      pasteboardNone: project.pasteboardNone,
      pasteboardReach: project.pasteboardReach,
      // The view the frame is drawn through: the camera's, while a run
      // plays here through it ([CanvasLook.frameViewThrough]).
      child: _stackView(
        shot?.frameView ?? viewport,
        activeSurfacePainter,
        floats,
        frame,
      ),
    );
  });

  /// How this canvas shows a cut's frame ([CanvasLook]) — through the camera
  /// while a run plays here, a cut's or the film's, with the camera view on
  /// (the camera view is playback's crop alone: a canvas that stands or is
  /// scrubbed shows the camera's frame OVER it).
  CanvasLook _look(EditorSessionManager session) => CanvasLook(
    camera: _isPlaybackActive && _state.widget.cameraViewEnabled.value
        ? (
            poseOf: session.camera.cameraPoseForCut,
            frameSize: session.camera.cameraFrameSize,
          )
        : null,
  );

  /// The camera a run playing here is seen through, at the frame the canvas
  /// shows — null for a canvas seen through none ([CanvasLook.camera]).
  CameraShotAt? _shotAt(
    EditorSessionManager session,
    CanvasLook look,
    CanvasViewport viewport,
  ) {
    final camera = look.camera;
    final cut = session.activeCutOrNull;
    if (camera == null || cut == null) {
      return null;
    }
    final frameIndex = session.currentFrameIndex;
    return (
      pose: camera.poseOf(cut, frameIndex),
      frameSize: camera.frameSize,
      frameView: look.frameViewThrough(viewport, cut, frameIndex),
    );
  }

  Widget _stackView(
    CanvasViewport viewport,
    BitmapSurfacePainter? activeSurfacePainter,
    CanvasFloats floats,
    _HostFrame frame,
  ) {
    final session = frame.session;
    final cut = session.activeCutOrNull;
    if (cut == null) {
      // R16-⑥: a gap parking has no cut — the void.
      return const SizedBox.expand();
    }
    final rig = session.playbackRig;
    final standing = !_canvasPlays;
    // R16-⑥: no cut in a gap — no paper (per-cut papers make anything else
    // confusing; the void is the truth). Standing, the pictures the warmer
    // lays ahead of it: the frame with its ghosts in place, or the frame and
    // the ghosts over it. No ghosts in a run: a ghost is editing
    // scaffolding, as a guide is, and the film has none.
    final shown = standingPicturesOf(
      cut,
      session.currentFrameIndex,
      session.onionSkin.settings.value.placement,
      paintPaper: !_inGap,
    );
    final frameShown = standing
        ? shown.frame
        : (
            cut: cut,
            frameIndex: session.currentFrameIndex,
            paintPaper: !_inGap,
            ghosts: FrameGhosts.none,
          );
    // MERGED: the whole tree, active layer included, so a folder's group
    // buffer encloses the layer being drawn on — asked afresh at each
    // build: a drag in flight, a run's step ([_followingDragAndRun]).
    final nodes = _inGap
        ? const <CompositeNode<CanvasStackRow>>[]
        : !standing
        ? session.editingCanvas.playingStack.nodes
        : frameShown.ghosts == FrameGhosts.inPlace
        ? session.editingCanvas.stackWithItsGhosts.nodes
        : session.editingCanvas.stack.nodes;
    // 🚨ONE VIEW, STANDING AND PLAYING (one-picture-per-frame ②-3): the
    // canvas standing on a frame and a run playing it show the frame's one
    // picture, through the same view — pressing Play changes nothing on the
    // screen and makes nothing again. The paper-stays-put split under a cut
    // pose went with the V row's transform: nothing poses the whole cut on
    // the editing canvas, so the layers draw straight.
    final drawnLive = _celsDrawnLive(nodes);
    final picture = FramePictureView(
      run: (
        landings: rig.prerenderScheduler.landings,
        pictures: rig.framePictures,
      ),
      picture: frameShown,
      nodes: nodes,
      viewport: viewport,
      // Standing, the canvas draws the row a pen is on live — TS1: the
      // selection's float in that row's slot, so the rows above it occlude
      // the live preview the way they occlude the landed pixels, and a
      // folder's lifted rows each in its own (I-37) — and makes the frame it
      // stands on at once. A RUN draws nothing live and waits for each frame
      // whole, made ahead of the playhead.
      live: standing
          ? (
              activeSurfacePainter: activeSurfacePainter,
              floatOverlay: floats.liveRow,
              liftedRows: floats.liftedRows,
            )
          : null,
      laysWhatItMisses: standing,
      wholeFrames: !standing,
      // The cel you were drawing is a ghost in this picture on the frame you
      // step to, where the ghosts lie in place.
      drawnLive: drawnLive,
    );
    final over = shown.over;
    return DeviceGridProbe(
      child: Stack(
        fit: StackFit.expand,
        children: [
          picture,
          // ⛔Standing with no ghost too: the cel the canvas drew live is read
          // off the widget the next build replaces ([FramePictureView.
          // drawnLive]) — mounted with the step, the ghosts' view would show
          // the cel you just drew a frame late. ↩️Mounted in a run too, with
          // nothing drawn live, while the ghosts were stacked from their
          // rows' images, which a stack of none made nothing of; a picture
          // view is asked its frame at every step of the run.
          if (standing && over != null)
            _ghostsOver(
              session,
              over,
              _inGap ? const [] : rig.framePictures.stackOf(over),
              viewport,
              drawnLive: drawnLive,
            ),
        ],
      ),
    );
  }

  /// The cels [nodes] draw live: their active rows'.
  static Set<BrushFrameKey> _celsDrawnLive(
    List<CompositeNode<CanvasStackRow>> nodes,
  ) => {
    for (final node in preorderNodes(nodes))
      if (node case CompositeLeaf(
        payload: CanvasActiveLayerRow(frameKey: final cel?),
      ))
        cel,
  };

  /// 🚨WHERE THEY LIE ON TOP (`OnionSkinPlacement.onTop`), THE ONION GHOSTS
  /// LIE OVER THE FRAME'S ONE PICTURE — over its paper and every row, at
  /// their tint and opacity as before (one-picture-per-frame-Q1 = a, 유저
  /// 2026-10-24 「한 장 위에 얹는다」), and a scrub shows them as it crosses
  /// frames. In place, they are in the frame's picture itself
  /// (`EditingCanvas.stackWithItsGhosts`, onion-ghosts-in-place).
  ///
  /// 🚨THE GHOSTS ARE ONE PICTURE TOO, made and drawn as the frame's is
  /// ([FramePictureView]): composed once at the canvas's own resolution,
  /// whatever the zoom, and laid through the view as the frame's picture is
  /// — the paper left to the picture under them. A pan or a zoom composes
  /// nothing again; a step makes the next ghosts' picture at once, drawn as
  /// they stand meanwhile. ↩️They were stacked from their rows' images,
  /// asked at the display's level — a half or a quarter of each row kept
  /// per zoom — and composed again into a buffer at each paint, until those
  /// were the last pictures kept per zoom (②-5b-1, 유저 2026-10-25
  /// 「원본기준으로 해서 쓸데없는 소재 없애고 거기서 극한 최적화 해야지」).
  ///
  /// ↩️They sat directly UNDER the active drawing, inside the folder and
  /// adjustment around it — and, for a day, in what clips to a base (I-92)
  /// — placed by `stackNodesWithGhosts`: no room for that between the rows
  /// of one picture, so a ghost is not cut by a clip's base either.
  ///
  /// 🚨STACKED AS THE WARMER STACKS THEM ([FramePictures.stackOf]): the
  /// pictures it lays ahead of a scrub are the ones the scrub stands on.
  Widget _ghostsOver(
    EditorSessionManager session,
    DemandedPicture ghosts,
    List<CompositeNode<CanvasStackRow>> nodes,
    CanvasViewport viewport, {
    required Set<BrushFrameKey> drawnLive,
  }) => FramePictureView(
    run: (
      landings: session.playbackRig.prerenderScheduler.landings,
      pictures: session.playbackRig.framePictures,
    ),
    picture: ghosts,
    nodes: nodes,
    viewport: viewport,
    laysWhatItMisses: true,
    wholeFrames: false,
    drawnLive: drawnLive,
  );

  /// What is stacked OVER the canvas inside the viewport: the guides and
  /// their edit layer, the SE name tags, the fade wash past the cut's end
  /// and the camera's frame. The row's box is not here — it sits over the
  /// tools ([_controls]). It follows a drag, and a run the canvas plays,
  /// itself ([_followingDragAndRun]): the tags, the fade and the frame are
  /// asked afresh at each of its builds.
  Widget _overlay(
    BuildContext context,
    CanvasViewport viewport,
    _HostFrame frame,
  ) => _followingDragAndRun(
    frame.session,
    (context) => _overlayStack(context, viewport, frame),
  );

  Widget _overlayStack(
    BuildContext context,
    CanvasViewport viewport,
    _HostFrame frame,
  ) {
    final session = frame.session;
    final fade = _fadeShown(session);
    final seNameTags = _seNameTagsShown(session);
    // A RUN shows the film: what is over the picture is what the picture
    // has — its SE tags and its fade — and none of the chrome about editing
    // it, the way playback has never drawn a guide or the camera's frame.
    final editing = !_isPlaybackActive;
    final shot = _shotAt(session, _look(session), viewport);
    return _inTheCamerasFrame(
      context,
      viewport,
      shot,
      Stack(
        children: [
          // Guides are EDITING scaffolding: they are drawn
          // here and nowhere else — playback, thumbnails and
          // export never see them, the way a ruler never
          // prints. Under the camera frame and the gizmos,
          // which are chrome about the shot rather than about
          // the drawing.
          if (editing && frame.session.cutVerbs.activeCutGuides.isNotEmpty)
            _state._guideOverlay(
              frame.session,
              viewport,
              _canvasSize,
              frame.tool,
              context,
            ),
          // The handle layer mounts ONLY for the guide tool,
          // so it never stands between the brush and the cel.
          if (editing && frame.tool == CanvasTool.guide)
            _state._guideEditLayer(frame.session, viewport),
          if (seNameTags.isNotEmpty)
            _state._seNameTagOverlay(
              shot?.frameView ?? viewport,
              _canvasSize,
              seNameTags,
              context,
            ),
          if (fade != null)
            _state._cutFadeWash(
              viewport,
              _canvasSize,
              frame.session,
              fade.opacity,
              fade.veils,
              context,
              throughCamera: shot != null,
            ),
          if (frame.pathLane case final property? when editing)
            _state._rowPath(frame, property, viewport, _canvasSize),
          if (editing) _state._cameraPath(frame, viewport),
          if (editing && _cameraOverlayVisible)
            _state._cameraOverlay(frame.session, viewport),
        ],
      ),
    );
  }

  /// [over] — what is over the picture — in the camera's frame, seen
  /// through the camera with it: the tags ride the projection, the fade
  /// thins the frame, and nothing of either shows past it ([CameraShot]).
  /// The clip is there either way, cutting nothing without a [shot], for
  /// the reason the shot is.
  Widget _inTheCamerasFrame(
    BuildContext context,
    CanvasViewport viewport,
    CameraShotAt? shot,
    Widget over,
  ) => ShotClip(
    // Cut as the picture under it is: a fade that thins the frame thins
    // every pixel the picture shows.
    outline: shot == null
        ? null
        : cameraFrameOnScreen(
            viewport,
            shot.frameSize,
            EffectiveDevicePixelRatio.of(context),
          ),
    child: over,
  );

  /// The standing row's box, over every tool
  /// ([BrushCanvasPanel.viewportControlsBuilder]): the camera's while the
  /// camera row is active, an SE row's name tag, or the active layer's while
  /// its standing lane declares one. It follows a drag itself
  /// ([_followingDragAndRun]), as the overlay does.
  ///
  /// ⚠️What is adjusted on the canvas — its canvas (I-79) or the camera's
  /// frame (I-80) — stands in the row's box's place while it is open: its
  /// handles are the edges then, and a row's box under them would take the
  /// presses that are theirs.
  ///
  /// The camera path settings say which handles of a path a box wears
  /// (`_EditorCanvasAreaState._pathTangents`), whichever row's box it is.
  Widget _controls(
    BuildContext context,
    CanvasViewport viewport,
    _HostFrame frame,
  ) => ListenableBuilder(
    listenable: Listenable.merge([
      frame.session.canvasAdjust,
      CameraPathSettings.settings,
    ]),
    builder: (context, _) =>
        _canvasAdjust(context, viewport, frame) ??
        _followingDragAndRun(
          frame.session,
          (context) => _rowBox(viewport, frame),
        ),
  );

  /// What is adjusted on the canvas, when it is open on the cut this canvas
  /// shows — the camera's frame where the camera stands at this frame — and
  /// a canvas left open on a cut the canvas no longer shows is let go of.
  Widget? _canvasAdjust(
    BuildContext context,
    CanvasViewport viewport,
    _HostFrame frame,
  ) {
    final session = frame.session;
    final adjust = session.canvasAdjust;
    if (!adjust.isOpen) {
      return null;
    }
    if (!adjust.isOpenOn(session.activeCutOrNull?.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => adjust.end());
      return null;
    }
    void land() => landCanvasAdjust(context, session);
    return switch (adjust.draft) {
      CameraSizeDraft() => _state._atTheCameraPose(
        session,
        (pose) => CameraAdjustLayer(
          adjust: adjust,
          pose: pose,
          viewport: viewport,
          pasteboard: session.pasteboardOf(_canvasSize),
          onLand: land,
        ),
      ),
      _ => CanvasAdjustLayer(
        adjust: adjust,
        viewport: viewport,
        pasteboard: session.pasteboardOf(_canvasSize),
        onLand: land,
      ),
    };
  }

  /// Whether [layer]'s REFERENCE FX box stands on the canvas (I-68): on a
  /// row that shows a file whose pictures are made from it again, standing
  /// on that group's lanes — or holding the move tool on the row anywhere
  /// but its transform lanes, which declare the layer's own box (유저
  /// 2026-10-10 「참조 행에서 이동(변형) 도구로 끌면 참조 fx 의 값이 바뀐다
  /// … 레이어 트랜스폼은 따로 남는다」).
  ///
  /// ⛔Not the transform switch's: the reference fx has none, and stands
  /// with it off (I-68-Q1 「레이어의 fx버튼 꺼도 그 자리 유지」).
  bool _referenceBoxShown(
    Layer? layer,
    TimelineRowAddress? standing,
    CanvasTool tool,
  ) {
    if (_isPlaybackActive ||
        layer == null ||
        referenceRedrawFor(layer) == null) {
      return false;
    }
    final lane = standing is LaneRowAddress && standing.layerId == layer.id
        ? standing.laneId
        : null;
    if (laneIsReference(lane)) {
      return true;
    }
    return tool == CanvasTool.move &&
        canvasManipulatorsForLane(lane).isEmpty;
  }

  Widget _rowBox(CanvasViewport viewport, _HostFrame frame) {
    if (frame.isCameraLayerActive && _cameraOverlayVisible) {
      return _state._cameraBox(frame, viewport, _canvasSize);
    }
    if (frame.referenceBox) {
      return _state._referenceBox(frame, viewport, _canvasSize);
    }
    if (frame.effectBox != null) {
      return _state._effectBox(frame, viewport, _canvasSize);
    }
    final layer = frame.activeLayer;
    if (layer == null || !(frame.boxGrabbable || frame.crossGrabbable)) {
      return const SizedBox.shrink();
    }
    return _state._layerBox(
      frame,
      viewport,
      _canvasSize,
      picture: layer.kind == LayerKind.se
          ? _EditorCanvasAreaState._sePicture(
              frame.session,
              layer,
              _seNameTagsShown(frame.session),
              _canvasSize,
            )
          : _EditorCanvasAreaState._layerPicture(
              frame,
              frame.session.pasteboardOf(_canvasSize),
            ),
    );
  }

  /// The cut FADE still follows the cursor (R9-C: fx ALWAYS reflects — dark
  /// faded frames are worked with fx off). It is the track's static opacity
  /// times the TRANSITION row's ramp now. F-192: and the screens one-sided
  /// transitions lay over it — the same veils the playback and the export
  /// paint. Null when neither dims this frame.
  ///
  /// ⛔And null in the gap parking. The fade is the ACTIVE cut's, so it
  /// stands down where the picture is not this canvas's — the parked track
  /// stack, which carries every cut's share itself. F-90's law for the SE
  /// tags below, said of the fade: a scrub out of the cut's territory
  /// washed the parked O.L with the cut's own stale fade (F-227).
  ({double opacity, List<TransitionVeil> veils})? _fadeShown(
    EditorSessionManager session,
  ) {
    if (_inGap) {
      return null;
    }
    final opacity = session.opacityVerbs.activeCutEditingFadeOpacity();
    final veils = session.opacityVerbs.activeCutEditingVeils();
    return opacity < 1 || veils.isNotEmpty
        ? (opacity: opacity, veils: veils)
        : null;
  }

  /// The SE rows' on-canvas name tags (R5b, §6-z15) — the editing
  /// canvas's copy of what playback and export draw. Playback renders its
  /// own (through the frame painter), so this stands down there exactly
  /// like the other editing chrome (no overlay while it plays).
  ///
  /// 🚨F-90 (유저 2026-09-12): 「스토리보드패널, 룰러 드래그 하는동안 se의
  /// 네임태그가 캔버스에 존재했던게 다음 컷이나 갭부분까지 남아있음. 안남아있도록
  /// 비디오트랙이나 se트랙이나 법 하나로 통일」. The parked content — the track
  /// stack a scrub shows past the cut's territory, or a gap — draws the tags
  /// of the frame IT shows, the way it draws that frame's picture. These are
  /// the ACTIVE cut's at its own cursor, so over the parked picture they were
  /// the frame the drag had left. They stand down wherever the picture is not
  /// this canvas's: [_inGap] asks exactly that, for the underlay's content
  /// swap.
  List<ResolvedSeNameTag> _seNameTagsShown(EditorSessionManager session) {
    final cut = session.activeCutOrNull;
    if (_inGap || cut == null) {
      return const [];
    }
    return session.seEntries.seNameTagsForCutFrame(
      cut,
      session.currentFrameIndex,
      // The tag follows a drag on its row while it moves — a lane edit
      // (F-195), its lines moved or stretched.
      preview: session.dragPreview.value,
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
    required this.boxGrabbable,
    required this.inkBounds,
    required this.crossGrabbable,
    required this.effectBox,
    required this.referenceBox,
    required this.isCameraLayerActive,
    required this.pathLane,
  });

  final EditorSessionManager session;

  /// The TOOL and not the brush: this build reruns for the tool and its
  /// shape alone ([BrushCanvasPanel.structureOf], H40 ②), so a size or a
  /// colour held here would be the one from the last tool switch.
  final CanvasTool tool;

  /// Non-null whenever [boxGrabbable] or [crossGrabbable] is true: both
  /// gates include the null check.
  final Layer? activeLayer;

  /// The standing lane declares the box (position, scale, rotation) and the
  /// cross (the anchor point) — R5 #10, what is selected is what you grab.
  final bool boxGrabbable;
  final bool crossGrabbable;

  /// The active row's reference fx box stands on the canvas (I-68) — the
  /// file it shows, where its reference says (`_referenceBoxShown`).
  final bool referenceBox;

  /// The effect of the active row the canvas's box drives, and the lane
  /// whose keys it moves — a cel number's letters, while its header or
  /// where it stands is stood on (F-477), a point's cross while its lane
  /// or its header is (I-132-Q12 b) — [effectBoxedOn]; null on every other
  /// lane.
  final ({LayerEffect effect, String lane})? effectBox;

  /// The active layer's ink at the playhead, while [boxGrabbable] or
  /// [crossGrabbable] — null on a cel that shows nothing.
  final ({int left, int top, int rightExclusive, int bottomExclusive})?
  inkBounds;
  final bool isCameraLayerActive;

  /// The active layer's lane one stands on, where its keys walk a path —
  /// its position or its anchor point — and the box that moves its keys
  /// is: its path is drawn, and its handles worked (I-89-Q9). Null on any
  /// other lane.
  final TransformPropertyId? pathLane;

  /// Which presses on the canvas the row's box takes: every one, or its
  /// cross, corners and a path's knobs alone ([RowTransformBox.presses]).
  ///
  /// 🗣️F-222-box-Q4 「선택 · 잘라내기만 빼고 모든 도구」: standing on the
  /// row, the box takes the empty canvas under every tool but the two that
  /// draw an area on it — a selection is not stopped by the kind of row
  /// you stand on.
  RowBoxPresses get boxPresses =>
      tool == CanvasTool.select || tool == CanvasTool.cut
      ? RowBoxPresses.handles
      : RowBoxPresses.viewport;
}
