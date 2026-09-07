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
}
