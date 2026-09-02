part of '../brush_canvas_panel.dart';

/// The SHELL BARS — the strip bars and the bottom bar around the canvas,
/// memoised so a viewport drag does not rebuild them, and the zoom and
/// rotate verbs their buttons call — as their own object.
///
/// 🚨A collaborator carved out of `_BrushCanvasPanelState` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: fourteen members of its
/// own. It reaches the State through `_state`.
class _CanvasPanelShellBars {
  _CanvasPanelShellBars(this._state);

  final _BrushCanvasPanelState _state;

  void readStageColors() {
    final scope = CanvasStageColors.maybeOf(_state.context);
    _state._stageBackdropArgb =
        _state.widget.backdropArgb ??
        scope?.backdropArgb ??
        defaultProjectBackdropArgb;
    _state._stagePasteboardArgb =
        _state.widget.pasteboardColor ??
        scope?.pasteboardArgb ??
        AppWorkspaceColors.defaultPasteboardArgb;
    _state._stagePasteboardMargin =
        _state.widget.pasteboardMargin ??
        scope?.pasteboardMargin ??
        defaultProjectPasteboardMargin;
  }

  /// R13-3 shell memo: the panbars/zoom-rotate bar are a Material button
  /// forest that used to reconstruct on EVERY panel rebuild (each committed
  /// seek, tool switch, drag-preview notify). Their inputs are only the
  /// viewport geometry — memo by token, reuse the identical instances so
  /// the element tree prunes the whole subtree.
  /// ★TWO tokens, not one (유저, R3 #14: 프로그램 창 자체를 크기 조절하면 뭔가
  /// 느린데). The panbars are geometry and DO depend on the viewport's size;
  /// the pill does not read it at all. Sharing one token meant every frame
  /// of a window resize rebuilt the pill — thirteen icon buttons with their
  /// tooltips, overlay portals and gesture detectors — for a number it
  /// ignores.
  ({CanvasViewport viewport, Size viewportSize, CanvasSize canvasSize})?
  _panbarsToken;

  ({
    double zoom,
    CanvasSize canvasSize,
    bool rotation,
    bool floor,
    int paper,
    int pasteboard,
    int backdrop,
    Object? host,
  })?
  _pillToken;

  Widget? _memoRightStripBar;

  Widget? _memoHorizontalStripBar;

  Widget? _memoBottomBar;

  void _ensureShellBars() {
    final viewportSize = _state._resolvedEditorViewportSize();
    final panbarsToken = (
      viewport: _state._viewport,
      viewportSize: viewportSize,
      canvasSize: _state.widget.canvasSize,
    );
    final pillToken = (
      // ⛔NOT the whole viewport — and since 2026-08-13 not "everything the
      // pill shows" either, because most of what it showed now lives one
      // tap away in the settings list. The rule that replaced it is
      // narrower and holds in both places: THIS TOKEN CARRIES WHAT THE BAR
      // CAPTURES, AND NOTHING IT READS THROUGH A SIGNAL.
      //
      // Rotation and the two flips left with the controls that lit them.
      // Their row is a [PanelFlyoutRow] over `liveViewport`: it rebuilds on
      // that notifier while the list is open, and reads `liveViewport.value`
      // when the list opens. A copy here would be a slower way of asking
      // the same object. (Measured: dragging the rotation readout inside
      // the open list moves the angle with this token untouched.)
      //
      // The three surface colours did NOT follow them out, and the
      // difference IS the rule. They arrive as widget fields, so the list's
      // entries close over whatever they were when the bar was last built.
      // Measured by mutation — drop `paper` from this token, change the
      // paper while the list is CLOSED, and it opens on yesterday's colour.
      // That is the same stale swatch, and the same picker seeded with the
      // stale value, that put them in this token to begin with.
      // ⚠️Neither does the token help while the list is OPEN: that is a
      // `showMenu` route holding entries it already built. Also measured.
      //
      // ⚠️A pan moves nothing that is left, which is the point: `_setViewport`
      // runs a panel `setState` per `PointerMove`, so carrying the whole
      // viewport threw the pill away on every frame of every pan and rebuilt
      // thirteen icon buttons with their tooltips, overlay portals, ink and
      // gesture detectors (유저, R4 후속).
      //
      // ★This is the SAME defect the note below already records about the
      // panel title, one field over: the cure had been applied to the field
      // that got caught rather than to the rule.
      //
      // ⚠️So the bar can be handed a stale `viewport` object while the memo
      // holds. That is safe only because `zoom` is now the ONLY thing it
      // reads off it; a second read added without adding it here brings
      // back a stale readout.
      zoom: _state._viewport.zoom,
      canvasSize: _state.widget.canvasSize,
      rotation: _state.widget.allowViewRotation,
      // WHICH BAR this is — flat on the floor, folded anywhere else. It
      // cannot change without this panel being rebuilt, but a memo that
      // did not carry it would be a memo that outlives the answer.
      floor: _state._onFloor,
      // The swatches the SETTINGS LIST carries (they were in the pill until
      // 2026-08-13). They were missing from this token once, and the pill
      // went on painting yesterday's paper colour until an unrelated pan or
      // resize happened to invalidate the memo — and tapping the swatch
      // opened the picker seeded with the stale value. Moving them behind
      // the gear did not retire that lesson, it only moved where the stale
      // value would show up.
      paper: _state.widget.paperColor,
      pasteboard: _state._stagePasteboardArgb,
      backdrop: _state._stageBackdropArgb,
      host: _state.widget.bottomBarHostToken,
      // ⛔ The panel TITLE is deliberately absent — and now unreachable, so
      // it cannot come back by accident (R2 #12 took the readout off every
      // canvas panel). Keeping the history because the shape of the bug is
      // worth recognising elsewhere: none of these bars showed the title,
      // but it sat in this token and read
      // "Project: … · Cut: … · Layer: … · Frame: <label>", so every step
      // that changed the frame label threw the memo away and rebuilt the
      // whole bar — 13 icon buttons with their tooltips, overlay portals,
      // ink and gesture detectors. Measured at 391 widget rebuilds a step,
      // against 24 for the panel's own spine.
      //
      // ⚠️ The dev fixture UNDERSTATES it. Two unnamed cels share a frame
      // label, so it only bit when the playhead crossed "no cel ↔ cel";
      // in a real cut every cel is named, and the label — so the bar —
      // changed on EVERY flip step.
    );
    // A host contribution without a token can't be memoized (see
    // [bottomBarHostToken]) — rebuild rather than serve a stale bar.
    final memoizable =
        (_state.widget.bottomBarLeading.isEmpty &&
            _state.widget.bottomBarSettings.isEmpty) ||
        _state.widget.bottomBarHostToken != null;
    if (panbarsToken != _panbarsToken || _memoRightStripBar == null) {
      _panbarsToken = panbarsToken;
      _memoRightStripBar = CanvasViewportVerticalScrollbar(
        viewport: _state._viewport,
        editorViewportSize: viewportSize,
        canvasSize: _state.widget.canvasSize,
        onViewportChanged: _setViewportDuringPanbarDrag,
        onViewportChangeEnd: _state._syncViewportParent,
      );
      _memoHorizontalStripBar = CanvasViewportHorizontalScrollbar(
        viewport: _state._viewport,
        editorViewportSize: viewportSize,
        canvasSize: _state.widget.canvasSize,
        onViewportChanged: _setViewportDuringPanbarDrag,
        onViewportChangeEnd: _state._syncViewportParent,
      );
    }
    if (memoizable && pillToken == _pillToken && _memoBottomBar != null) {
      return;
    }
    _pillToken = pillToken;
    _memoBottomBar = _CanvasViewportBottomBar(
      onFloor: _state._onFloor,
      leading: _state.widget.bottomBarLeading,
      hostSettings: _state.widget.bottomBarSettings,
      viewport: _state._viewport,
      liveViewport: _state._viewportNotifier,
      canvasSize: _state.widget.canvasSize,
      paperColor: _state.widget.paperColor,
      onPaperColorChanged: _state.widget.onPaperColorChanged,
      pasteboardColor: _state._stagePasteboardArgb,
      onPasteboardColorChanged: _state.widget.onPasteboardColorChanged,
      backdropColor: _state._stageBackdropArgb,
      onBackdropColorChanged: _state.widget.onBackdropColorChanged,
      // Read when a picker opens, so the memoized bar does not have to be
      // rebuilt every time the brush colour moves.
      currentColorOf: () => _state.widget.brushToolState.color,
      onViewportChanged: _setViewportDuringPanbarDrag,
      onViewportChangeEnd: _state._syncViewportParent,
      onZoomSet: _setZoomFromLabel,
      onZoomIn: _zoomInFromBar,
      onZoomOut: _zoomOutFromBar,
      onFit: _state._fitToView,
      onReset: _state._resetView,
      onRotateCcw: _state.widget.allowViewRotation ? _rotateCcwFromBar : null,
      onRotateCw: _state.widget.allowViewRotation ? _rotateCwFromBar : null,
      onRotateReset: _state.widget.allowViewRotation
          ? _state._resetRotation
          : null,
      onRotateByDrag: _state.widget.allowViewRotation
          ? _state._rotateByDrag
          : null,
      onFlipHorizontal: _state.widget.allowViewRotation
          ? _state._toggleFlipHorizontal
          : null,
      onFlipVertical: _state.widget.allowViewRotation
          ? _state._toggleFlipVertical
          : null,
    );
  }

  Widget memoizedRightStripBar() {
    _ensureShellBars();
    return _memoRightStripBar!;
  }

  Widget memoizedHorizontalStripBar() {
    _ensureShellBars();
    return _memoHorizontalStripBar!;
  }

  Widget memoizedBottomBar() {
    _ensureShellBars();
    return _memoBottomBar!;
  }

  void _rotateCcwFromBar() => _state._rotateAroundCenter(-15);

  void _rotateCwFromBar() => _state._rotateAroundCenter(15);

  void _setViewportDuringPanbarDrag(CanvasViewport viewport) {
    _state._rebuild(() => _state._viewport = viewport.clamped());
  }

  void _zoomInFromBar() => _state._zoomAroundCenter(1.25);

  void _zoomOutFromBar() => _state._zoomAroundCenter(0.8);

  /// Absolute-zoom twin of [_state._zoomAroundCenter] — the readout's drag is
  /// 1%/px and its double-tap types a percent, and both of those are
  /// absolute.
  void _setZoomFromLabel(double zoom) {
    _state._zoomToAroundCenter(zoom);
  }
}
