import '../../models/layer_id.dart';
import '../../models/timeline_row_address.dart';
import 'property_lane_model.dart';

/// The layer whose row sits [rowDelta] display rows away from
/// [sourceLayerId]'s cells row — the block-move drop target. Lane rows
/// resolve to their owning layer; out-of-range deltas clamp to the ends.
LayerId? resolveBlockMoveTargetLayer({
  required List<TimelineDisplayRow> rows,
  required LayerId sourceLayerId,
  required int rowDelta,
}) {
  if (rows.isEmpty) {
    return null;
  }
  var sourceIndex = -1;
  for (var index = 0; index < rows.length; index += 1) {
    if (!rows[index].isLane && rows[index].layer.id == sourceLayerId) {
      sourceIndex = index;
      break;
    }
  }
  if (sourceIndex < 0) {
    return null;
  }
  final targetIndex = (sourceIndex + rowDelta).clamp(0, rows.length - 1);
  return rows[targetIndex].layer.id;
}

/// The display row a cell SELECT drag has reached: its layer, plus the
/// lane id when the pointer is over a property-lane row (R27 #14 —
/// "A셀부터 오파시티까지만").
///
/// [resolveBlockMoveTargetLayer] answers the same question for MOVES,
/// where a lane row can only mean its owning layer (keys do not accept
/// dropped blocks). Selection is the other half: a lane row IS a
/// selectable row, so the drag has to be able to stop on it. Same row
/// walk, different verb — hence two functions over one row list rather
/// than one function with a mode flag.
({LayerId layerId, String? laneId})? resolveSelectionSpanHead({
  required List<TimelineDisplayRow> rows,
  required LayerId sourceLayerId,
  required int rowDelta,
}) {
  if (rows.isEmpty) {
    return null;
  }
  var sourceIndex = -1;
  for (var index = 0; index < rows.length; index += 1) {
    if (!rows[index].isLane && rows[index].layer.id == sourceLayerId) {
      sourceIndex = index;
      break;
    }
  }
  if (sourceIndex < 0) {
    return null;
  }
  final target = rows[(sourceIndex + rowDelta).clamp(0, rows.length - 1)];
  return (layerId: target.layer.id, laneId: target.lane?.laneId);
}

/// 🚨★★★ THE SELECTION SPAN — every row a select drag has swept, in the
/// order they are DRAWN, addresses and all.
///
/// 유저 확정 (2026-08-12): 「프레임셀은 다 똑같은 규칙으로 여러개 선택가능하도록.
/// 헤더니까 뭐 다르게한다거나 제발좀 절대로좀 그만좀하자.」
///
/// ★**THE LAW: the span is the DISPLAY row list, sliced. Nothing rebuilds a
/// row list of its own.**
///
/// The rule used to be stated as a per-kind eligibility test, and the test
/// was not even the thing that failed — a predicate wrote "EVERY row selects
/// now" while the list it filtered was assembled fresh out of the model
/// (`cut.layers + track.seLayers`). Three kinds of row are on screen and not
/// in that model walk: the track-owned TRANSITION clone the rail inserts,
/// every LANE row, and their group HEADERS. Anchor on one and the lookup
/// missed, so the span collapsed to the single row you started on; cross one
/// and it was silently stepped over rather than swept. Each new row kind
/// bought another hand-written exception, which is why the same complaint
/// came back round after round.
///
/// Slicing what is drawn makes "if you can see it, you can select it" true
/// by construction, and a row kind decides only what an edit DOES to it —
/// never whether it may be in the range.
///
/// Returns the inclusive run from [anchor] to the row [rowDelta] away,
/// always in display order (a drag upward returns top-to-bottom too). Empty
/// when the anchor is not on screen, which is the one honest "no span".
List<TimelineRowAddress> resolveSelectionSpanRows({
  required List<TimelineDisplayRow> rows,
  required TimelineRowAddress anchor,
  required int rowDelta,
}) {
  if (rows.isEmpty) {
    return const [];
  }
  final anchorIndex = rows.indexWhere((row) => row.address == anchor);
  if (anchorIndex < 0) {
    return const [];
  }
  final headIndex = (anchorIndex + rowDelta).clamp(0, rows.length - 1);
  final low = anchorIndex < headIndex ? anchorIndex : headIndex;
  final high = anchorIndex < headIndex ? headIndex : anchorIndex;
  return [for (var i = low; i <= high; i += 1) rows[i].address];
}
