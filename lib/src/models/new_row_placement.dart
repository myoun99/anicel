import 'attached_layer_resolve.dart' show attachedGroupEndIndex;
import 'layer.dart';
import 'layer_folder.dart' show attachOrganizerBaseOf;
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
///   active row's own folder. A member names its own folder, a folder row
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
