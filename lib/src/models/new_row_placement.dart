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

/// The attach group [layer] belongs to, named by its base: a rider names
/// the base it rides, an organizer folder the base it organizes, and any
/// other row its own group.
LayerId _attachGroupOf(Layer layer, List<Layer> stack) =>
    layer.attachedToLayerId ?? attachOrganizerBaseOf(layer, stack) ?? layer.id;
