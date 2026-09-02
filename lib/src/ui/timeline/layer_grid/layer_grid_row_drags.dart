part of '../layer_timeline_grid.dart';

/// THE ROW DRAGS — a layer row and an effect row made draggable in the
/// rail — as their own object.
///
/// 🚨A collaborator carved out of `_LayerTimelineGridState` (the audit's
/// SRP cut, 2026-09-02). It reaches the State through `_state`.
class _LayerGridRowDrags {
  _LayerGridRowDrags(this._state);

  final _LayerTimelineGridState _state;

  /// The slot is this row's place among the layer rows ON SCREEN, and the
  /// list handed to the policy is those rows' layers — see [layerRowsOf]
  /// for why it cannot be [TimelineDisplayRow.layerIndex] and
  /// `widget.layers` (F-31).
  Widget _draggable(TimelineDisplayRow row, Widget child) {
    final hooks = _state.widget.hooks.rowDragHooks;
    // 🚨A5-4 (유저 2026-08-22): 「카메라·트랜지션 = **드래그 불가**」 —
    // 그런데 F-16: **선택은 된다.** 두 레일이 각자 적던 그 판단은 이제
    // [unmovableRowSelectTarget] 하나가 답한다.
    final unmovable = unmovableRowSelectTarget(
      kind: row.layer.kind,
      layerId: row.layer.id,
      rowExtent: _state._metrics.layerRowHeight,
      axis: Axis.horizontal,
      hooks: hooks,
      onSelectCrossed: (rowDelta) => _state.widget.hooks.onRowSelectionSpan
          ?.call(_state._dragRows, rowDelta),
      child: child,
    );
    if (unmovable != null) {
      return unmovable;
    }
    final caret = LayerRowCaret.of(_state._dragRows, row.layer.id);
    if (caret == null) {
      return child;
    }
    return LayerRowDragTarget(
      subject: LayerRowSubject(row.layer.id),
      slotBefore: caret.slot,
      rowExtent: _state._metrics.layerRowHeight,
      axis: Axis.horizontal,
      hooks: hooks,
      onGripTaken: () => _state._heldDragRow = row.address,
      onGripReleased: () {
        if (_state._heldDragRow == row.address) {
          _state._heldDragRow = null;
        }
      },
      isLastRow: caret.isLastRow,
      onCrossed: hooks == null
          ? (_, _, _) {}
          : (steps, onRow, inRow) {
              // R5 #15: ON a row wins over the gap beside it — that is the
              // whole point of the middle band. The row it names is read
              // from the DISPLAY list, so which way this rail runs stays
              // the surface's business as it already is for slots.
              final slot = caret.slotFor(steps);
              final target = caret.onRowLayer(onRow);
              if (target != null) {
                hooks.onRowTarget(caret.layers, slot, target.id);
                return;
              }
              hooks.onUpdate(
                caret.layers,
                slot,
                pointerInRow: caret.onRowLayer(inRow)?.id,
              );
            },
      // ⑨: the SELECT half of the same drag. It counts in the rail's own
      // DISPLAY rows (`_dragRows`) rather than in the layer list the caret
      // uses — the span must be able to stop on a lane row, which the layer
      // list does not contain.
      onSelectCrossed: hooks?.onSelectBegin == null
          ? null
          : (rowDelta) => _state.widget.hooks.onRowSelectionSpan?.call(
              _state._dragRows,
              rowDelta,
            ),
      child: child,
    );
  }

  /// An fx header, made draggable: grabbing it re-orders the layer's effect
  /// CHAIN. The Transform group header is never wrapped — it is not a chain
  /// member, it is where the chain ends.
  Widget _effectDraggable(TimelineDisplayRow row, Widget child) {
    final hooks = _state.widget.hooks.rowDragHooks;
    final lane = row.lane;
    if (hooks == null || lane == null) {
      return child;
    }
    // 🚨B4-3 (유저, 몇 번째인지 세지 않겠다고 했다) — **EVERY ROW JOINS A
    // SELECTION.**
    //
    // > 「행의 **다른 fx끼리 넘어서 선택범위가 불가능.** 그 너머의 다른 행
    // > 선택해야 그때서야 가능. **이런 다른규칙 삭제좀하자고.**」
    //
    // ⛔The span resolver never had a rule about lanes — it is a plain slice
    // of the drawn row list. What was missing is WIRING: a lane row that is
    // not an fx chain header got no drag target at all, and the one that IS
    // a header was given `onCrossed` and never `onSelectCrossed`, which is
    // the only thing that grows a selection during a drag. So a span
    // anchored on a lane simply never updated, and a span anchored anywhere
    // else could not stop on one.
    //
    // ★A lane row cannot be RE-ORDERED unless it heads a chain, but every
    // row can be SELECTED. Those are two questions, and only the first one
    // ever needed an answer here.
    final parsed = parseEffectLaneId(lane.laneId);
    if (!lane.isGroupHeader || parsed == null || parsed.parameterId != null) {
      return _state._laneSelectOnlyTarget(row, lane.laneId, hooks, child);
    }
    final headers = effectHeaderRowsOf(_state._dragRows, row.layer.id);
    final slot = headers.indexWhere((h) => h.effectId == parsed.effectId);
    if (slot < 0) {
      return _state._laneSelectOnlyTarget(row, lane.laneId, hooks, child);
    }
    final displayEffects = [for (final header in headers) header.effectId];
    final myRowIndex = headers[slot].rowIndex;
    return LayerRowDragTarget(
      subject: EffectRowSubject(row.layer.id, parsed.effectId),
      slotBefore: slot,
      rowExtent: _state._metrics.layerRowHeight,
      axis: Axis.horizontal,
      hooks: hooks,
      onGripTaken: () => _state._heldDragRow = row.address,
      onGripReleased: () {
        if (_state._heldDragRow == row.address) {
          _state._heldDragRow = null;
        }
      },
      isLastRow: slot == headers.length - 1,
      // An fx chain has no "inside a row" to drop into — an effect holds
      // nothing — so the on-row band is ignored here and the caret stays
      // the only answer (R5 #15).
      onCrossed: (steps, _, _) => hooks.onEffectUpdate(
        row.layer.id,
        displayEffects,
        slotForSteps(
          slot,
          rowStepsBetween(
            [for (final header in headers) header.rowIndex],
            myRowIndex,
            steps,
          ),
          headers.length,
        ),
      ),
      // B4-3: the SELECT half, the same one every layer row already had.
      onSelectCrossed: hooks.onSelectBegin == null
          ? null
          : (rowDelta) => _state.widget.hooks.onRowSelectionSpan?.call(
              _state._dragRows,
              rowDelta,
            ),
      child: child,
    );
  }
}
