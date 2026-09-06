import '../../models/layer_id.dart';
import '../../models/timeline_selection_kind.dart';
import '../../models/timeline_row_address.dart';
import '../timeline/property_lane_model.dart' show TimelineDisplayRow;
import '../timeline/timeline_row_span_resolver.dart'
    show resolveSelectionSpanRows;
import 'session_roles.dart';
import 'range_selections.dart';

/// The ROW SELECTION — the rows the user swept in the rail, the anchor the
/// sweep started from, and what folding a group does to it — as its own
/// object. The selection itself stays on the session: the UI reads it.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: one field of its own and two
/// session members touched. It names the roles it needs in its constructor.
class RowSelection {
  RowSelection({
    required SelectionAccess selection,
    required RangeSelections rangeSelections,
  }) : _selection = selection,
       _rangeSelections = rangeSelections;

  final RangeSelections _rangeSelections;

  final SelectionAccess _selection;

  /// Where the live row-select drag started; null between drags.
  TimelineRowAddress? _rowSelectionAnchor;

  bool rowIsSelected(TimelineRowAddress row) =>
      _selection.rowSelection.value.contains(row);

  /// A press that lands OUTSIDE the current selection starts a fresh one —
  /// the cells' rule, transposed (their range gesture's `isInSelection`).
  void beginRowSelection(TimelineRowAddress anchor) {
    _rangeSelections.claimSelection(TimelineSelectionKind.rows);
    _rowSelectionAnchor = anchor;
    _selection.rowSelection.value = [anchor];
  }

  /// Grows the live selection to [rowDelta] rows from its anchor, through
  /// the SAME law the cell span uses — the rail's own drawn row list, so a
  /// row that is visible is selectable and a new row kind needs no wiring.
  void updateRowSelection(List<TimelineDisplayRow> rows, int rowDelta) {
    final anchor = _rowSelectionAnchor;
    if (anchor == null) {
      return;
    }
    final span = resolveSelectionSpanRows(
      rows: rows,
      anchor: anchor,
      rowDelta: rowDelta,
    );
    if (span.isNotEmpty) {
      _selection.rowSelection.value = span;
    }
  }

  void endRowSelection() {
    _rowSelectionAnchor = null;
  }

  void clearRowSelection() {
    _rowSelectionAnchor = null;
    if (_selection.rowSelection.value.isNotEmpty) {
      _selection.rowSelection.value = const [];
    }
  }

  /// 🚨H6 (유저 2026-08-21) — THE FOLD LAW'S OTHER HALF.
  ///
  /// > 「이 앱의 특징은 **행이 보이는 곳만 조작**한다는 점임. 지금 레이어의
  /// > 프레임블록+fx행 선택범위하고 레이어 접고 펼치면 **fx행까지 선택한 게
  /// > 남아있는데**, 접을 때 **선택범위 바꿔서 사라진 건 선택 안 하게**
  /// > 되도록. 접고나서 이동할 때 fx행 반영 안 되는거 보니 **로직적으론 잘
  /// > 되있는거같고 선택범위 UI만** 그에 맞춰 제대로」
  ///
  /// ⛔The law above already SAID this — 「what disappears never keeps the
  /// selection」 — and only ever did it for the ONE standing row. The
  /// selection BAND kept its folded rows, so the band drew over rows that
  /// were no longer on screen while the verbs (correctly) ignored them:
  /// the user's own reading, that the logic was right and the UI was not.
  ///
  /// The swallower takes their place rather than the selection emptying —
  /// the same answer the standing row gets, for the same reason. A user
  /// who had rows selected still has rows selected after a fold.
  void foldRowSelection({
    required bool Function(TimelineRowAddress address) vanished,
    required TimelineRowAddress swallower,
  }) {
    final selection = _selection.rowSelection.value;
    if (selection.isEmpty) {
      return;
    }
    final kept = [
      for (final address in selection)
        if (!vanished(address)) address,
    ];
    if (kept.length == selection.length) {
      return;
    }
    _selection.rowSelection.value = kept.isEmpty
        ? [swallower]
        : (kept.contains(swallower) ? kept : [...kept, swallower]);
  }

  /// ㊵: the rows a drag on [movingId] carries because they are SELECTED.
  ///
  /// Empty unless the pressed row is itself in the selection — a drag that
  /// starts outside one is an ordinary single-row move, and ⑨ already made
  /// that press a fresh SELECT rather than a move. Only layer rows count:
  /// lanes and headers ride their layer, they do not re-order.
  Set<LayerId> rowSelectionCarriedBy(LayerId movingId) {
    final ids = <LayerId>{
      for (final row in _selection.rowSelection.value)
        if (row is LayerRowAddress) row.layerId,
    };
    return ids.contains(movingId) ? ids : const <LayerId>{};
  }
}
