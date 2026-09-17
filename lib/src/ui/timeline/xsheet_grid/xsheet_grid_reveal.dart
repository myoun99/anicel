part of '../xsheet_timeline_grid.dart';

/// SCROLLING THE SHEET TO THE CURSOR — bringing a selection back on screen,
/// turning the page under a playing playhead, and whether a row's frame is
/// inside the window — as its own object.
///
/// 🚨A collaborator carved out of `_XSheetTimelineGridState` (the audit's
/// SRP cut, 2026-09-02). It reaches the State through `_state`.
///
/// ⚠️TWO LAWS LIVE HERE, AND THEY ARE NOT THE SAME ONE (F-110): a selection
/// walk moves the least it can and keeps a neighbour in sight; a playback
/// page stands the playhead at the start of the window and does nothing at
/// all until it leaves. Both are written once in `timeline_edge_auto_pan`
/// and asked of THIS surface's axes here.
class _XSheetGridReveal {
  _XSheetGridReveal(this._state);

  final _XSheetTimelineGridState _state;

  /// R5: the same reveal the rail does, asked of THIS surface's axes — the
  /// frame runs down here and the columns run across, so one tick lands on
  /// two different controllers without either side knowing the other's.
  void handleRevealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_state.mounted) {
        _revealSelection();
      }
    });
  }

  /// ★And it asks the SAME row walk the rail does now
  /// ([indexOfDisplayRow], round 8's grid unification). The sheet used to
  /// look for the active layer's own column and nothing else, so a
  /// selection standing on a LANE column scrolled to the layer beside it —
  /// the rail had honoured the current-row address since R10 #19.
  void _revealSelection() => revealSelectionOnBothAxes(
    (
      controller: _state._frameScrollController,
      extent: _state._metrics.frameCellWidth,
      at: _state.widget.hooks.frameCursor.value,
    ),
    (
      controller: _state._layerScrollController,
      extent: _state._metrics.layerRowHeight,
      at: indexOfDisplayRow(
        _state._dragRows,
        current: _state.widget.hooks.currentRowHooks?.currentRow.value,
        activeLayerId: _state.widget.hooks.activeLayerId,
      ),
    ),
  );

  /// F-110: the frame axis — which runs DOWN here — turns a PAGE when
  /// playback carries the playhead out of the window (유저 2026-09-12:
  /// 「넘어가면 룰러가 왼쪽에 오도록 스크롤바 한번만 이동」; on this surface
  /// the same law reads as the playhead row coming to the top).
  ///
  /// ⛔The COLUMNS do not move. A cut plays down one row, so a playback tick
  /// says nothing about which column the sheet should stand on, and the
  /// reveal's second axis has nothing to answer with.
  void handlePlaybackPage() {
    if (_state.widget.hooks.playbackFrame?.value == null) {
      return;
    }
    pageToPlayhead((
      controller: _state._frameScrollController,
      extent: _state._metrics.frameCellWidth,
      at: _state.widget.hooks.frameCursor.value,
    ));
  }
}
