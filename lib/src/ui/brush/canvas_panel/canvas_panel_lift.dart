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
  ///
  /// 🚨★★★**AND IT READS THE PICTURE HERE, THEN GIVES THE ROOM ITS FILE
  /// BACK.** The payload is consumed exactly once — the reading and the
  /// releasing are one act, so neither can be forgotten at one of the three
  /// endings. It was split before: the store's release only dropped the
  /// map entry, and a lift that ended by LANDING never read its payload at
  /// all, so a box that had been parked through a memory warning left a
  /// scratch file behind for the rest of the run.
  ///
  /// ⚠️The abandon path pays a decode it does not use, and that is the
  /// price of the two verbs being one. It costs anything at all only when
  /// a warning arrived while this very box was open.
  ({BitmapSurface? pixels, CanvasSelectionRegion? region})? _takeAnchor(
    int liftToken,
  ) {
    final coordinator = _state.widget._editableCoordinator;
    coordinator?.frameStore.releaseLiftedPixels(liftToken);
    final anchor = _liftAnchors.remove(liftToken);
    if (anchor == null) {
      return null;
    }
    // The cel as it stands is the post-erase surface the anchor was
    // measured against — the box has been floating over it all along.
    //
    // ⛔**THE SNAPSHOT'S OWN KEY, NOT THE ACTIVE ONE.** A cel change is one
    // of the three ways a lift ends, and it lands the stamp through
    // `_resetAll`: reading the ACTIVE cel there would measure this
    // anchor against a different drawing entirely.
    final surface = coordinator == null
        ? null
        : anchor.pixels.surfaceOver(
            coordinator.currentSurfaceOf(anchor.pixels.key),
          );
    anchor.pixels.drop();
    return (pixels: surface, region: anchor.region);
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
      final historyManager = _state.widget.historyManager;
      // ⚠️READING THE ANCHOR CAN NOW REFUSE, and「no entry」is the honest
      // answer to that. The pre-lift picture may be parked in the run's
      // 휘발성 room, and a payload that will not come back cannot be the
      // undo target — an entry built on the post-erase surface instead
      // would say the erase never happened. It joins the two cases that
      // already land raw rather than becoming a third shape.
      final preLiftSurface = preLift?.pixels;
      if (historyManager == null || preLift == null || preLiftSurface == null) {
        // Headless hosts (focused tests) or a lost anchor: land raw.
        coordinator.commitSourceStroke(
          sourceDabs: [stampDab],
          cacheInvalidationSink: _state.widget.cacheInvalidationSink,
        );
        return;
      }
      final doors = _selectionDoors();
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
          readRegion: doors.read,
          restoreRegion: doors.restore,
        ),
      );
    }

    if (_state.mounted) {
      _state._rebuild(run);
    } else {
      run();
    }
  }

  /// The selection doors a confirmed move's undo entry keeps for its whole
  /// life: read the live selection, put one back.
  ///
  /// 🚨★★★MADE HERE, AWAY FROM THE LANDING — AND THAT IS THE FIX, NOT A
  /// TIDY-UP (C-ipad-crash ①, 2026-09-15). A Dart closure keeps the whole
  /// SCOPE it was made in, not just the names it reads. Written inline in
  /// [handleLiftConfirmed], these two kept that call's `preLift` (the
  /// pre-lift picture) and `stampDab` (the landed stamp's RGBA) alive for as
  /// long as the entry stayed in the history — through parking, outside
  /// every budget, while [BrushLiftMoveHistoryCommand] nulled its own copies
  /// and reported zero. 🔬A VM heap snapshot after ten ×2 → ×0.5 transforms
  /// of a 2000×1400 picture: 526.9MB of stamps and 70MB of tiles held by
  /// nothing but this context — the user's 「반복시마다 약 150mb」.
  /// ⛔Nothing big may be in scope where a closure that outlives the call is
  /// made; a method whose only local is `this` cannot hold anything else.
  ({
    CanvasSelectionRegion? Function() read,
    void Function(CanvasSelectionRegion? region) restore,
  })
  _selectionDoors() => (
    read: () => _state.widget.selectionCommands?.region,
    restore: (region) => _state.widget.selectionCommands?.setRegion(region),
  );

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
      final surface = preLift.pixels;
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
