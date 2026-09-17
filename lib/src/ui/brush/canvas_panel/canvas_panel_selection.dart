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

  /// Whether the selection layer is mounted: a selecting tool, over content
  /// that takes tool input ([BrushCanvasPanel.toolInputEnabled]). The deck
  /// mounts the layer on it and the idle ants paint on its negation, so a
  /// selection stays drawn by one or the other while playback plays.
  bool get selectionLayerMounted =>
      _state.widget.toolInputEnabled &&
      canvasToolSelects(_state.widget.brushToolState.tool);

  /// The region to paint when no selection layer is mounted (null while
  /// one is — it draws its own, session state included).
  CanvasSelectionRegion? get idleSelectionRegion {
    if (selectionLayerMounted) {
      return null;
    }
    return _state.widget.selectionCommands?.region;
  }

  int _liftTokenSeq = 0;

  /// Lifts [region]'s pixels out of the cel (R19 pixel model): the stamp
  /// comes back to float and the cel it came from shows the hole — **while
  /// the document keeps every byte it had**.
  ///
  /// 🚨★★★**THE ERASE IS NOT COMMITTED ANY MORE** (유저 2026-09-17, which
  /// REVERSED the 09-08 answer to `undo-41-hole-scope`: 「원본은 남기되,
  /// 일시적으로 구멍 픽셀 잘라내고 플로트 띄운단거지? … 그 방식대로
  /// 구조/근본적으로 작업 가자」). It used to land in the cel the moment the
  /// pixels were lifted, and everything that made that survivable — the
  /// pre-lift snapshot, the lift anchors, the store's budget exception, the
  /// revert path, a history command of its own — existed to take it back.
  /// ⇒ The session shows [BrushFrameEditingCoordinator.deriveSurfaceWith]'s
  /// answer instead: the same pixels the erase would have written, held by
  /// the session and dropped with it.
  ///
  /// 🎯**And that is what let the timeline move again.** A committed erase
  /// means leaving the frame leaves a HOLE behind, which is why a seek, a
  /// row press and a cut switch were all refused while a box was open
  /// (F-116·F-86, 유저: 「타임라인쪽 조작이 안먹힘」). With nothing written
  /// there is nothing to leave behind, so there is nothing to refuse.
  ///
  /// ⚠️The 09-08 card blocked this on a PLATFORM fact — an image hole needs
  /// a synchronous upload, which was Impeller-only while Windows was Skia.
  /// That expired on 09-16 (every platform is Impeller now), and this route
  /// needs no upload at all: the hole is a surface, not a paint-time punch,
  /// so there is no `saveLayer` and no `dstOut` over the layers below.
  ///
  /// Null when the shape covers no pixels.
  ///
  /// 🪦Two things stood at the end of this until 2026-09-11, both about the
  /// frame the lift opens on (F-68 ②, 「그림의 일부가 1프레임 이상한곳에
  /// 생겼다가 사라짐 … 매번 다른데」): the cel's stale-fallback bucket forgot
  /// the coordinates the lift took whole, and the erased tiles were seeded
  /// with the pre-lift picture cut by the erase's own bytes. From then until
  /// 2026-09-17 the commit funnel announced both surfaces of every edit and
  /// the painter composed each new tile from its predecessor plus the diff
  /// (M5: with that on and both of these off, every lift pin stayed green)
  /// — and the answer carried the pre-lift surface so the float's tiles had
  /// predecessors too. A tile pictures itself inside the paint now, the
  /// erased ones and the float's alike, so nothing is announced, composed
  /// or carried.
  ({int liftToken, BrushDab stampDab})? handleSelectionLift(
    CanvasSelectionRegion region,
  ) {
    final coordinator = _state.widget._editableCoordinator;
    if (coordinator == null) {
      return null;
    }
    final lift = buildSelectionLiftDabs(
      region: region,
      surface: coordinator.currentSurfaceOf(coordinator.activeFrameKey),
      liftId: '${DateTime.now().microsecondsSinceEpoch}',
      options:
          _state.widget.selectionMaskOptions?.value ??
          SelectionMaskOptions.none,
    );
    if (lift == null) {
      return null;
    }
    // ⛔THE SAME DABS THE CONFIRM WILL LAND, through the same materialize:
    // the hole the user sees and the erase the commit writes cannot drift
    // apart at the mask's edge, because they are one computation.
    final holed = coordinator.deriveSurfaceWith([lift.eraseDab]);
    if (holed == null) {
      return null;
    }
    final token = ++_liftTokenSeq;
    _state._lift.openSession(
      token: token,
      holed: holed,
      eraseDab: lift.eraseDab,
      key: coordinator.activeFrameKey,
    );
    _state._rebuild(() {});
    return (liftToken: token, stampDab: lift.stampDab);
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
    final pixels = data.strokePixels;
    final bounds = data.strokeBounds;
    final clipped = pixels == null || bounds == null
        // No live raster (programmatic strokes, a redo replaying dabs):
        // the dabs are rasterized first so the clip has bytes to work on
        // — the one door a fill's promotion takes too (`promoteFillDab`).
        ? clipDabsToSelection(
            dabs: data.sourceDabs,
            canvasSize: _state.widget.canvasSize,
            tileSize: _state.widget._editableCoordinator == null
                ? BitmapSurface(canvasSize: _state.widget.canvasSize).tileSize
                : _state.widget._editableCoordinator!
                      .currentSurfaceOf(
                        _state.widget._editableCoordinator!.activeFrameKey,
                      )
                      .tileSize,
            region: region,
          )
        : clipStrokePixelsToSelection(
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
