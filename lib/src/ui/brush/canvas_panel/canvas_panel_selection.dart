part of '../brush_canvas_panel.dart';

/// The SELECTION SEAT — what the panel does with the selection layer:
/// recording its changes into history, answering the idle region, a
/// lift, and clipping a stroke to it — as its own object.
///
/// 🚨A collaborator carved out of `_BrushCanvasPanelState` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: three State members shared.
/// It reaches the State through `_state`.
class _CanvasPanelSelection {
  _CanvasPanelSelection(this._state);

  final _BrushCanvasPanelState _state;

  /// One undoable selection step (R11-⑧) — the layer's marquee commits and
  /// the channel's layer-less Ctrl+D both land here, so a selection change
  /// is recorded the same way whatever tool is armed. Null while this
  /// panel has no history host (focused tests apply directly).
  void Function(CanvasSelectionRegion? before, CanvasSelectionRegion? after)?
  get recordSelectionChange {
    final history = _state.widget.historyManager;
    final commands = _state.widget.selectionCommands;
    if (history == null || commands == null) {
      return null;
    }
    return (before, after) => history.execute(
      SelectionShapeHistoryCommand(
        channel: commands,
        before: before,
        after: after,
      ),
    );
  }

  void bindSelectionHistoryRecorder() {
    _state.widget.selectionCommands?.regionHistoryRecorder =
        recordSelectionChange;
  }

  void handleSelectionChannelChanged() {
    if (!_state.mounted) {
      return;
    }
    // The channel pings on EVERY selection mutation, including each step
    // of a marquee/move drag. Those all happen with a selection tool
    // armed, where the mounted layer draws and this panel has nothing to
    // redraw — so the guard keeps the notify structure (R27 #7/#20) out
    // of the drag loop and only rebuilds when the ants this panel owns
    // actually change.
    final next = idleSelectionRegion;
    if (next == _state._paintedIdleRegion) {
      return;
    }
    _state._rebuild(_state._syncIdleAnts);
  }

  /// The region to paint when no selection layer is mounted (null while
  /// one is — it draws its own, session state included).
  CanvasSelectionRegion? get idleSelectionRegion {
    if (canvasToolSelects(_state.widget.brushToolState.tool)) {
      return null;
    }
    return _state.widget.selectionCommands?.region;
  }

  int _liftTokenSeq = 0;

  /// Lifts [region]'s pixels out of the cel (R19 pixel model): the erase
  /// lands raw, the stamp comes back to float. Null when the shape covers
  /// no pixels.
  ///
  /// `preLift` is the surface the lift copied from — the predecessor of
  /// every tile the float built from this stamp will have (F-68), so the
  /// float can draw on its first frame. The erased tiles need nothing
  /// from here: the commit funnel announces both surfaces, and the painter
  /// composes them from their predecessors like any other edit.
  ({int liftToken, BrushDab stampDab, BitmapSurface preLift})?
  handleSelectionLift(CanvasSelectionRegion region) {
    final coordinator = _state.widget._editableCoordinator;
    if (coordinator == null) {
      return null;
    }
    final preLift = coordinator.currentSurfaceOf(coordinator.activeFrameKey);
    final lift = buildSelectionLiftDabs(
      region: region,
      surface: preLift,
      liftId: '${DateTime.now().microsecondsSinceEpoch}',
      options:
          _state.widget.selectionMaskOptions?.value ??
          SelectionMaskOptions.none,
    );
    if (lift == null) {
      return null;
    }
    final outcome = coordinator.commitSourceStroke(
      sourceDabs: [lift.eraseDab],
      cacheInvalidationSink: _state.widget.cacheInvalidationSink,
    );
    if (outcome == null) {
      return null;
    }
    final token = ++_liftTokenSeq;
    // ⚠️READ THE POST-ERASE SURFACE FIRST, because the anchor is measured
    // against it: an [UndoSurfaceSnapshot] owes only the tiles the live
    // surface no longer holds, and here that is exactly the set the erase
    // rebuilt. Everything else the anchor names is a tile the cel still
    // has, and holding it costs nothing.
    final after = coordinator.currentSurfaceOf(coordinator.activeFrameKey);
    final held = UndoSurfaceSnapshot(
      key: coordinator.activeFrameKey,
      snapshot: preLift,
      sharedWith: after,
    );
    // ⛔THE TOOL KEEPS THE LIFETIME, THE STORE KEEPS THE DISCIPLINE — one
    // object, held by both. Without this the pixels are outside every
    // budget for as long as the box stays open; see the store's own
    // paragraph on [BrushFrameStore.holdLiftedPixels].
    coordinator.frameStore.holdLiftedPixels(token, held);
    _state._lift._liftAnchors[token] = (
      pixels: held,
      // The selection as the session finds it — captured at the same instant
      // as the pixels, so undo can put both back exactly as they were.
      region: _state.widget.selectionCommands?.region,
    );
    _state._rebuild(() {});
    // 🪦Two things stood here until 2026-09-11, both about the frame the
    // lift opens on (F-68 ②, 「그림의 일부가 1프레임 이상한곳에 생겼다가
    // 사라짐 … 매번 다른데」): the cel's stale-fallback bucket forgot the
    // coordinates the lift took whole, and the erased tiles were seeded
    // with the pre-lift picture cut by the erase's own bytes. The commit
    // funnel now announces both surfaces of every edit and the painter
    // composes each new tile from its predecessor plus the diff — with
    // that on and both of these off, every lift pin stayed green (M5).
    return (liftToken: token, stampDab: lift.stampDab, preLift: preLift);
  }

  /// R26 #18 ("선택하고 그리면 선택 내부만 그려진다"): a stroke that lands
  /// with a live selection is CLIPPED to it before it reaches the commit.
  ///
  /// The clip runs on the stroke's own straight-alpha buffer, where alpha
  /// 0 is every commit kernel's "leave the destination alone" input — so
  /// one pass covers brush, eraser, fill and every brush blend mode with
  /// no per-mode branches. Null return = the whole stroke fell outside
  /// the selection and there is nothing to commit.
  BrushStrokeCommitData? clipStrokeToSelection(BrushStrokeCommitData data) {
    final region = _state.widget.selectionCommands?.region;
    if (region == null) {
      return data;
    }
    if (data.promotedTiles != null) {
      // The stroke was pre-blended THROUGH the selection mask (R28): the
      // promoted tiles are already clipped, and re-deriving them here
      // would throw away the finished pixels to rasterize the dabs again.
      // An empty list means the whole stroke fell outside the selection.
      return data.promotedTiles!.isEmpty ? null : data;
    }
    var pixels = data.strokePixels;
    var bounds = data.strokeBounds;
    if (pixels == null || bounds == null) {
      // No live raster (programmatic strokes, a redo replaying dabs):
      // rasterize the coverage first so the clip has bytes to work on.
      final rasterized = rasterizeStrokeForClipping(
        dabs: data.sourceDabs,
        canvasSize: _state.widget.canvasSize,
        tileSize: _state.widget._editableCoordinator == null
            ? BitmapSurface(canvasSize: _state.widget.canvasSize).tileSize
            : _state.widget._editableCoordinator!
                  .currentSurfaceOf(
                    _state.widget._editableCoordinator!.activeFrameKey,
                  )
                  .tileSize,
      );
      if (rasterized == null) {
        return null;
      }
      pixels = rasterized.pixels;
      bounds = rasterized.bounds;
    }
    final clipped = clipStrokePixelsToSelection(
      pixels: pixels,
      bounds: bounds,
      region: region,
    );
    if (clipped == null) {
      return null;
    }
    return BrushStrokeCommitData(
      sourceDabs: data.sourceDabs,
      strokePixels: clipped.pixels,
      strokeBounds: clipped.bounds,
      blendMode: data.blendMode,
      strokeOpacity: data.strokeOpacity,
    );
  }
}
