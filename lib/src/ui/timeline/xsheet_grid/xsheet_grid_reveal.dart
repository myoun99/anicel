part of '../xsheet_timeline_grid.dart';

/// REVEALING A SELECTION — scrolling the sheet so the selection is on
/// screen, and whether a row's frame is inside it — as its own object.
///
/// 🚨A collaborator carved out of `_XSheetTimelineGridState` (the audit's
/// SRP cut, 2026-09-02). It reaches the State through `_state`.
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

  void _revealSelection() {
    final cell = _state._metrics.frameCellWidth;
    if (_state._frameScrollController.hasClients && cell > 0) {
      jumpToReveal(_state._frameScrollController, (
        start: _state.widget.hooks.frameCursor.value * cell,
        extent: cell,
        margin: cell,
      ));
    }
    final columnWidth = _state._metrics.layerRowHeight;
    final activeId = _state.widget.hooks.activeLayerId;
    if (!_state._layerScrollController.hasClients ||
        activeId == null ||
        columnWidth <= 0) {
      return;
    }
    final at = _state._dragRows.indexWhere(
      (row) => !row.isLane && row.layer.id == activeId,
    );
    if (at < 0) {
      return;
    }
    jumpToReveal(_state._layerScrollController, (
      start: at * columnWidth,
      extent: columnWidth,
      margin: columnWidth,
    ));
  }
}
