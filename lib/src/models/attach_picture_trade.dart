import 'attached_layer_resolve.dart' show isSyncedAttachedLayer;
import 'block_row_swap.dart';
import 'cel_rekey.dart';
import 'frame_id.dart';
import 'layer.dart';
import 'layer_id.dart';

/// The PICTURES a rows' hop on the same frames trades inside one attach
/// group — a base and its SYNCED rows, which show one set of blocks — with
/// every cel, name, exposure and link staying where it is.
///
/// 🗣️F-330 (유저 2026-10-10): 「같은 위치에 대한 행이동은 타임라인을 바꾸는게
/// 아니고 서로의 그림을 바꾸는거라 가능해도될듯」 — and I-98 (10-14): 「싱크행
/// 이라도 선택/드래그로 블록끼리 자리바꾸는 이동은 가능하도록. 내부 그림만
/// 바꿔치기 하는 느낌」.
///
/// [group] is the group's rows in the order the rows show them, [sources]
/// the ones the selection holds, carried [rowDelta] rows on; [baseCels] the
/// base's cels the selection covers. Each source row's picture goes
/// [rowDelta] rows on, and the rows it lands on hand theirs back across the
/// moved rows, as a move's landed-on blocks go ([rowLandedOnGoesBackTo]). A
/// row's cel for the base's cel is that cel on the base and its link on a
/// synced row.
///
/// Null when a source is no row of [group] or is carried off it, or when a
/// row the trade passes through has no cel for one of [baseCels]. ⚖️Mine,
/// not the user's: a synced row is given a cel for every base cel (its
/// mount stores the complete links, a cel born on the base is born on its
/// rows), so a row without one is an orphan with nowhere to hang a picture
/// — and a trade makes no cel.
List<CelPictureMove>? picturesTradedInAttachGroup({
  required List<Layer> group,
  required Iterable<LayerId> sources,
  required int rowDelta,
  required Iterable<FrameId> baseCels,
}) {
  final indexOf = {for (final (index, row) in group.indexed) row.id: index};
  final from = <int>{};
  for (final source in sources) {
    final index = indexOf[source];
    final landing = index == null ? -1 : index + rowDelta;
    if (landing < 0 || landing >= group.length) {
      return null;
    }
    from.add(index!);
  }
  if (rowDelta == 0 || from.isEmpty) {
    return null;
  }
  final entered = {for (final index in from) index + rowDelta}.difference(
    from,
  );
  final hops = [
    for (final index in from) (index, index + rowDelta),
    for (final index in entered)
      (
        index,
        rowLandedOnGoesBackTo(index, sources: from, rowDelta: rowDelta),
      ),
  ];
  final moves = <CelPictureMove>[];
  for (final baseCel in baseCels.toSet()) {
    for (final (fromIndex, toIndex) in hops) {
      final (fromRow, toRow) = (group[fromIndex], group[toIndex]);
      final fromCel = _celOf(fromRow, baseCel);
      final toCel = _celOf(toRow, baseCel);
      if (fromCel == null || toCel == null) {
        return null;
      }
      moves.add((
        fromRow: fromRow.id,
        fromCel: fromCel,
        toRow: toRow.id,
        toCel: toCel,
      ));
    }
  }
  return moves;
}

/// [row]'s cel for the base's [baseCel]: its link on a synced row, the cel
/// itself on the base.
FrameId? _celOf(Layer row, FrameId baseCel) =>
    isSyncedAttachedLayer(row) ? row.baseFrameLinks[baseCel] : baseCel;
