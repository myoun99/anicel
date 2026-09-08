part of '../brush_canvas_panel.dart';

/// THE LIFT — a selection lifted off the picture and what the panel
/// shows underneath it until it lands: the anchors of the lift, the
/// pre-landing surface held for the committed region, and the three ways
/// a lift ends (confirmed, reverted, landed).
///
/// 🚨A collaborator carved out of `_BrushCanvasPanelState` (the audit's SRP
/// cut, Round 6, 2026-09-03). Measured before cutting: two fields of its
/// own and five methods that are their only readers. It reaches the
/// panel through `_state`.
class _CanvasPanelLift {
  _CanvasPanelLift(this._state);

  final _BrushCanvasPanelState _state;

  /// Pre-lift surfaces by session token (R19 P3b): the immutable surface
  /// captured BEFORE a lift's erase — the confirm command's undo target
  /// and the revert's restore point. Reference-cheap.
  /// What a lift session found when it began: the pixels AND the selection.
  ///
  /// ⛔ONE record, not a second map beside this one. Both are anchored at the
  /// same instant and released at the same instant, and a parallel map would
  /// be one more place to forget to clear.
  ///
  /// 🚨★★★**AN [UndoSurfaceSnapshot], NOT A BARE SURFACE — because the
  /// bytes have to be nameable.** 유저 확정 2026-09-08 (`undo-41-hole-scope`
  /// = ①, Krita 식): the same pixels are budgeted and parkable the moment a
  /// confirm turns them into a history entry, and were budgeted by nothing
  /// at all while the box was open — a user who had not confirmed was held
  /// to LESS discipline than one who had. Measured: a whole-picture Ctrl+T
  /// on a 2340×1654 cel pins 17.5 MiB here, plus up to 17.5 MiB of GPU
  /// tile images the cache keys on the very tile objects this holds.
  ///
  /// 🔬What the pro tools do (조사 2026-09-08): Krita clears the source
  /// immediately exactly as we do, and the lifted pixels are a
  /// `KisPaintDevice` — a tiled document device — so the swapper spills
  /// them under pressure with no help from the transform tool at all
  /// (`tool_transform2/` contains no memory-pressure code). OpenToonz
  /// holds ours' shape instead — raw rasters on a global tool object,
  /// outside the image cache — and there a floating selection survives
  /// pressure while cold cels and undo die first.
  final Map<int, ({UndoSurfaceSnapshot pixels, CanvasSelectionRegion? region})>
  _liftAnchors = {};

  /// Takes an anchor back from BOTH of its holders.
  ///
  /// ⛔**NEVER `_liftAnchors.remove` ON ITS OWN.** The store is holding the
  /// same snapshot object so that a memory warning can park it, and a
  /// half-release would leave it parking pixels nobody will ever read
  /// again. There are three ways a lift ends and this is the one verb all
  /// three go through.
  ({UndoSurfaceSnapshot pixels, CanvasSelectionRegion? region})? _takeAnchor(
    int liftToken,
  ) {
    _state.widget._editableCoordinator?.frameStore.releaseLiftedPixels(
      liftToken,
    );
    return _liftAnchors.remove(liftToken);
  }

  /// The cel as it stood just before a lift session's landing committed —
  /// the base half of a composed stand-in.
  ///
  /// Captured at the call rather than read back, because by the time the
  /// selection layer asks, the commit has already replaced it. Consumed
  /// once; a stale one would compose the wrong artwork under the landing.
  ///
  /// 🚨 Released on the NEXT FRAME whether or not anyone consumed it, and
  /// that is not tidiness. Three ordinary endings land a stamp and never
  /// reach the composer — a tool switch that confirms from the unmounting
  /// layer's `dispose`, a cel change that lands the pending stamp through
  /// `_resetAll`, and a confirm with no ink to compose from — and a
  /// [BitmapSurface] holds every tile the landing replaced, whose pixels
  /// are NATIVE allocations plus their GPU images. On a whole-picture
  /// transform of a 2340×1654 cel that is tens of megabytes pinned for
  /// the rest of the session, which is the same "every edit pins its last
  /// generation" term [BitmapTileImageCache.retainedScopeLimit] exists to
  /// bound. The compose runs synchronously inside the same landing, so a
  /// post-frame release can never take it away early.
  BitmapSurface? _preLandingSurface;

  /// Captures the pre-landing cel and schedules its release, so the slot
  /// cannot outlive the landing that filled it.
  void _holdPreLandingSurface(BrushFrameEditingCoordinator coordinator) {
    _preLandingSurface = coordinator.currentSurfaceOf(
      coordinator.activeFrameKey,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preLandingSurface = null;
    });
  }

  /// Gives the tiles a landing just created a picture of themselves,
  /// composed from what the float is already showing.
  ///
  /// This is the answer to the same question the hold covers for, and it
  /// runs first: what it can seed leaves the pending set, so the float is
  /// clipped to a smaller region — or to nothing at all, which is the
  /// whole landing painted by the canvas on the frame it lands.
  ///
  /// Silent about coordinates it cannot answer for, deliberately: those
  /// keep the hold, which is today's behaviour and correct.
  void _composeCommittedRegionPictures(
    DirtyRegion landing,
    ProvisionalInkPainter paintInk,
  ) {
    final coordinator = _state.widget._editableCoordinator;
    final preSurface = _preLandingSurface;
    _preLandingSurface = null;
    if (coordinator == null || preSurface == null) {
      return;
    }
    final postSurface = coordinator.currentSurfaceOf(
      coordinator.activeFrameKey,
    );
    if (identical(postSurface, preSurface) ||
        postSurface.tileSize != preSurface.tileSize) {
      return;
    }
    final coords = tileCoordsIn(
      landing.tileRange(tileSize: postSurface.tileSize),
    );
    // Under the probe because it is the one part of a confirm whose cost
    // scales with the LANDING rather than with the change: a whole-canvas
    // stamp is every tile of the cel, at a `toImageSync` each.
    final activeKey = coordinator.activeFrameKey;
    labProbe(
      'confirm.composeStandIns',
      () => seedProvisionalTilePictures(
        preSurface: preSurface,
        postSurface: postSurface,
        coords: coords,
        ink: paintInk,
        // The cel's lineage. Only the synchronous-upload path inside
        // reaches the bucket, but it puts TRUTH there, and truth in the
        // null bucket is the shared-tin defect the float once had.
        staleScope: (activeKey.layerId, activeKey.frameId),
      ),
    );
  }

  /// R16-① confirm: lands the floating stamp and adopts the whole move
  /// session (raw lift + landed stamp) into app history as ONE undo
  /// entry — a surface-snapshot command whose undo target is the exact
  /// pre-lift picture (R19 P3b).
  void handleLiftConfirmed(int liftToken, BrushDab stampDab) {
    final coordinator = _state.widget._editableCoordinator;
    final preLift = _takeAnchor(liftToken);
    if (coordinator == null) {
      return;
    }
    // The setState rebuilds the interactive view onto the post-confirm
    // surface (R17-①b: without it the landed stamp stayed invisible —
    // white hole at the origin, nothing at the destination — until an
    // unrelated rebuild). Mounted guard: the layer's unmount path
    // confirms post-frame, possibly after this panel went with it.
    void run() {
      // The base the landing is about to be blended onto, for the
      // composed stand-ins the layer asks for immediately after this.
      _holdPreLandingSurface(coordinator);
      final historyManager = _state.widget.historyManager;
      // ⚠️READING THE ANCHOR CAN NOW REFUSE, and「no entry」is the honest
      // answer to that. The pre-lift picture may be parked in the run's
      // 휘발성 room, and a payload that will not come back cannot be the
      // undo target — an entry built on the post-erase surface instead
      // would say the erase never happened. It joins the two cases that
      // already land raw rather than becoming a third shape.
      final preLiftSurface = preLift?.pixels.surface;
      if (historyManager == null || preLift == null || preLiftSurface == null) {
        // Headless hosts (focused tests) or a lost anchor: land raw.
        coordinator.commitSourceStroke(
          sourceDabs: [stampDab],
          cacheInvalidationSink: _state.widget.cacheInvalidationSink,
        );
        return;
      }
      historyManager.execute(
        BrushLiftMoveHistoryCommand(
          coordinator: coordinator,
          frameKey: coordinator.activeFrameKey,
          preLiftSurface: preLiftSurface,
          stampDab: stampDab,
          cacheInvalidationSink: _state.widget.cacheInvalidationSink,
          // 🚨THE SELECTION TRAVELS WITH THE PIXELS. 유저 2026-08-27: 「언두
          // 하면 그림만 돌리는게아니라 선택도 이전 선택으로 되돌리기」 — a
          // transform moves the outline as much as the drawing, and one
          // confirm has to come back as one undo.
          regionBefore: preLift.region,
          readRegion: () => _state.widget.selectionCommands?.region,
          restoreRegion: (region) =>
              _state.widget.selectionCommands?.setRegion(region),
        ),
      );
    }

    if (_state.mounted) {
      _state._rebuild(run);
    } else {
      run();
    }
  }

  /// REVERT of a session (R17-①): the pre-lift surface snapshot restores
  /// the picture byte-exactly; nothing lands in history.
  void handleLiftReverted(int liftToken) {
    final coordinator = _state.widget._editableCoordinator;
    final preLift = _takeAnchor(liftToken);
    if (coordinator == null || preLift == null) {
      return;
    }
    void run() {
      // ⚠️AND HERE A REFUSAL COSTS MORE THAN AN UNDO DOES — the picture
      // stays erased and the floating pixels are gone, because the erase
      // was committed when the lift began. 유저 확정 2026-09-08
      // (`undo-41-hole-scope` = (가)): 「되돌리기도 조건이 이상한 상황일
      // 뿐인거니까」 — the payload only refuses when something outside the
      // app removed a file we wrote this run, which is the same wager the
      // parked undo payloads already make, and the alternative to making
      // it is holding the bytes through a memory warning.
      final surface = preLift.pixels.surface;
      if (surface == null) {
        return;
      }
      coordinator.restoreSurfaceSnapshot(
        coordinator.activeFrameKey,
        surface,
        cacheInvalidationSink: _state.widget.cacheInvalidationSink,
      );
    }

    if (_state.mounted) {
      _state._rebuild(run);
    } else {
      run();
    }
  }

  /// Raw landing of the floating stamp (no history entry) — the abandon
  /// fallback so a reset never loses the float's pixels. The base surface
  /// is the post-erase state throughout the session, so landing is a
  /// plain stamp commit.
  void handleLiftLanded(int liftToken, BrushDab stampDab) {
    final coordinator = _state.widget._editableCoordinator;
    _takeAnchor(liftToken);
    if (coordinator == null) {
      return;
    }
    void run() {
      _holdPreLandingSurface(coordinator);
      coordinator.commitSourceStroke(
        sourceDabs: [stampDab],
        cacheInvalidationSink: _state.widget.cacheInvalidationSink,
      );
    }

    if (_state.mounted) {
      _state._rebuild(run);
    } else {
      run();
    }
  }
}
