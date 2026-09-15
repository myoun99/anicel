import 'package:flutter/foundation.dart';

import '../../models/layer_id.dart';
import '../../models/timeline_selection_kind.dart';
import '../../models/timeline_row_address.dart';
import '../timeline/property_lane_model.dart' show TimelineDisplayRow;
import '../timeline/timeline_row_span_resolver.dart'
    show resolveSelectionSpanRows;
import 'session_roles.dart';
import 'range_selections.dart';

/// The fold law's one body ([Standing.handOffOnFold]) as a collaborator that
/// cannot hold the standing takes it: [vanished] names what a fold took off
/// the screen, [swallower] where the row selection and the row you stand on
/// go instead.
typedef FoldHandOff =
    void Function({
      required TimelineRowAddress swallower,
      required bool Function(TimelineRowAddress address) vanished,
    });

/// The ROW SELECTION — the rows the user swept in the rail, the anchor the
/// sweep started from, and what folding a group does to it — as its own
/// object — the NOTIFIER included: it owns the selection now, and the
/// session plays [SelectionAccess.rowSelection] by handing this one out.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: one field of its own and two
/// session members touched. It names the roles it needs in its constructor.
class RowSelection {
  RowSelection({
    required RangeSelections rangeSelections,
  }) : _rangeSelections = rangeSelections;

  final RangeSelections _rangeSelections;


  /// Where the live row-select drag started; null between drags.
  TimelineRowAddress? _rowSelectionAnchor;

  /// ⑨ (user, 2026-08-12): 「레이어에도 선택 시스템 — 첫 드래그가 선택
  /// (1개/여러 개), 그 다음이 드래그. 타임라인 프레임과 **완전히 같은 순서**」.
  ///
  /// The rail's ROW selection: what the row verbs act on. Separate from
  /// [SessionInternals.currentRow] on purpose — standing is where the frame
  /// verbs aim, this is a set the row verbs sweep — and separate from the
  /// frame range, whose rows are the cells the selection covers rather than
  /// the rows themselves.
  ///
  /// Addresses, not layers, so every drawn row kind can be in it (뿌리 A):
  /// what a row IS never decides whether it can be selected, only what the
  /// edit then does to it.
  final ValueNotifier<List<TimelineRowAddress>> rowSelection =
      ValueNotifier<List<TimelineRowAddress>>(const []);

  void dispose() => rowSelection.dispose();

  bool rowIsSelected(TimelineRowAddress row) =>
      rowSelection.value.contains(row);

  /// A press that lands OUTSIDE the current selection starts a fresh one —
  /// the cells' rule, transposed (their range gesture's `isInSelection`).
  void beginRowSelection(TimelineRowAddress anchor) {
    _rangeSelections.claimSelection(TimelineSelectionKind.rows);
    _rowSelectionAnchor = anchor;
    rowSelection.value = [anchor];
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
      rowSelection.value = span;
    }
  }

  void endRowSelection() {
    _rowSelectionAnchor = null;
  }

  void clearRowSelection() {
    _rowSelectionAnchor = null;
    if (rowSelection.value.isNotEmpty) {
      rowSelection.value = const [];
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
    final selection = rowSelection.value;
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
    rowSelection.value = kept.isEmpty
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
      for (final row in rowSelection.value)
        if (row is LayerRowAddress) row.layerId,
    };
    return ids.contains(movingId) ? ids : const <LayerId>{};
  }

  /// The rows a press on [pressedId] acts on: the whole selection when the
  /// pressed row is in it, that row alone when it is not.
  ///
  /// 🚨THE DEFAULT FOR EVERY SELECTION-BOUND ACTION (유저 2026-09-11, the
  /// reference button's rasterize: 「선택상태 안의 레이어를 래스터라이즈버튼
  /// 누르면 선택한것들 래스터라이즈하고, 밖의 레이어를 래스터라이즈버튼누르면
  /// 그 밖에있는것만 래스터라이즈. 앞으로 비슷한 상황에서 선택관련해서
  /// 동작할거있으면 이걸 기본으로」). It is the answer the row drag already
  /// gives ([rowSelectionCarriedBy]), so it asks that rather than restating
  /// it. ⚠️What a press does to the selection ITSELF is not part of the
  /// rule — the user did not say — so nothing here touches [rowSelection].
  Set<LayerId> rowsActedOnBy(LayerId pressedId) {
    final carried = rowSelectionCarriedBy(pressedId);
    return carried.isEmpty ? {pressedId} : carried;
  }
}
