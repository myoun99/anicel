import 'attached_layer_resolve.dart' show attachedGroupEndIndex;
import 'layer.dart';
import 'layer_folder.dart'
    show LayerFolderQueries, attachOrganizerBaseOf, folderChainAbove;
import 'layer_id.dart';

/// Where a NEW row joins [stack] when it is aimed at [insertAt]: the model
/// index it takes and the folder it belongs to.
///
/// 🚨ONE answer for every door that makes a row — Add Layer above the
/// active one, a file let go on the canvas, a file let go between two rail
/// rows. The canvas drop used to ask only for Add Layer's INDEX and skip
/// both rules below, so a picture dropped with a folder member active
/// landed inside the folder's run without belonging to it.
///
/// Two structural rules, and they used to live inside the drawing-kind arm
/// of Add Layer, where every later kind had to remember them:
/// - an attach group is INDIVISIBLE (R26 #36): aimed inside a group, the
///   row lands past the whole group, never between a base and its attach
///   rows — whether the row it was aimed above is the base or one of its
///   attaches. BOTH sides count: a below-only group used to slip through an
///   above-only check.
/// - the row joins the folder of the row BELOW it — for Add Layer, the
///   active row's own folder, or the folder stood on ([newRowPlacementOn],
///   which aims inside it). A member names its own folder, a folder row
///   names its parent, nothing below is top level: the membership a moved
///   row takes (`resolveLayerDrop`). A row inserted into a folder's
///   contiguous member run without belonging to it breaks the folder
///   invariant and composites in the wrong scope; for R6b's adjustment that
///   meant filtering nothing at all, silently.
({int index, LayerId? folderId}) newRowPlacement(
  List<Layer> stack,
  int insertAt,
) {
  var index = insertAt.clamp(0, stack.length);
  if (index > 0 && index < stack.length) {
    final base = _attachGroupOf(stack[index - 1], stack);
    if (base == _attachGroupOf(stack[index], stack)) {
      index = attachedGroupEndIndex(base, stack);
    }
  }
  return (
    index: index,
    folderId: index > 0 ? stack[index - 1].folderId : null,
  );
}

/// Where a row made while standing on [standing] joins [stack]: above it,
/// as [newRowPlacement] places a row aimed there — or, standing on a
/// FOLDER, inside it, at the top of what it holds. Nothing stood on in the
/// stack (no row, or a track's SE row) is the top of the stack.
///
/// 🗣️F-492 (유저 2026-10-27): 「폴더위에 서서 레이어만들때 폴더 안에서
/// 만들도록 서있는상태는 유지」. ↩️A folder stood on was a row like any
/// other, and the new row went above it — out of it, into its parent.
///
/// ⛔Not an attach ORGANIZER: everything inside one rides its base (유저
/// 2026-08-29: 「a레이어 어태치 안에 있는 모든거는 a에 대한 어태치여야해」),
/// and a new row rides nothing — it goes above the organizer, as above any
/// row.
({int index, LayerId? folderId}) newRowPlacementOn(
  List<Layer> stack,
  LayerId? standing,
) {
  final index = stack.indexWhere((layer) => layer.id == standing);
  if (index == -1) {
    return newRowPlacement(stack, stack.length);
  }
  final row = stack[index];
  if (row.kind.groupsLayers && attachOrganizerBaseOf(row, stack) == null) {
    // The folder row sits right above its members: its own seat is the
    // top of their run, and the folder steps up over the new row.
    return (index: index, folderId: row.id);
  }
  return newRowPlacement(stack, index + 1);
}

/// The row you stand on once [made] joined [stack] while you stood on
/// [standing]: the row you made — or, where it went inside the folder you
/// stood on, that folder still (「서있는상태는 유지」, F-492 above).
///
/// ONE answer for every door that makes a row and stands on it — Add Layer,
/// and a file let go on the canvas or between two rail rows.
LayerId rowStoodOnAfterMaking(
  List<Layer> stack, {
  required LayerId made,
  required LayerId? standing,
}) {
  final index = stack.indexWhere((layer) => layer.id == made);
  if (standing == null || index == -1) {
    return made;
  }
  final inside = folderChainAbove(
    stack[index].folderId,
    stack.folderById,
  ).any((folder) => folder.id == standing);
  return inside ? standing : made;
}

/// Where a cut's CONTE row is born in [stack]: at the bottom of ACTION —
/// the stack's first row, in no folder (raw order runs bottom-up, and the
/// drawing section is the lowest on the screen).
///
/// 🗣️F-369 (유저 2026-10-16): 「콘티패널에서 콘티행에 +같은거 눌러서
/// 콘티레이어 생성될때, 컷 들어가면 액션섹션의 젤 위에 생성되는데 그게아니라
/// 젤 밑에 생성되도록」. ONE answer for every door that makes a cut its conte
/// row — the conte row's `+`, a first stroke on a cut that has none, Add
/// Layer's conte entry: a cut holds one (`LayerKind.isSingletonPerCut`), so
/// each makes the same row. ↩️Add Layer and the `+` put it above the active
/// row, and the first stroke on top of the stack.
({int index, LayerId? folderId}) conteRowPlacement(List<Layer> stack) =>
    newRowPlacement(stack, 0);

/// The attach group [layer] belongs to, named by its base: a rider names
/// the base it rides, an organizer folder the base it organizes, and any
/// other row its own group.
LayerId _attachGroupOf(Layer layer, List<Layer> stack) =>
    layer.attachedToLayerId ?? attachOrganizerBaseOf(layer, stack) ?? layer.id;

/// Where a row put down above [row] goes in [stack] as it stands NOW: the
/// seat right above it, and the top of the stack when [row] names none
/// here. Read again for every row a block puts down — the one before it
/// moved everything above.
///
/// ONE answer for every block of rows a verb lands over a row: a paste
/// over the row you stand on, a linked paste, and a duplicate over the
/// topmost of the rows it copies (F-455).
int seatAboveRow(List<Layer> stack, LayerId? row) {
  final index = stack.indexWhere((layer) => layer.id == row);
  return index == -1 ? stack.length : index + 1;
}
