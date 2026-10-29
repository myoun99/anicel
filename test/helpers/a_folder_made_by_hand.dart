import 'package:anicel/src/models/attached_layer_resolve.dart'
    show attachBaseIdOf;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show LayerRowSubject;

/// A FOLDER AROUND THE ROW STOOD ON — its whole attach group — made as the
/// user makes one: an empty folder from Add Layer, then the group's base
/// dropped on it. Stood on the row again; the folder is handed back.
///
/// 🗣️R5 #14: 「폴더로 묶기」 went from the layer menu — a folder is made
/// EMPTY and filled by dropping rows on it. ↩️A fixture wanting a folder
/// called the menu's old verb, which no screen called any more
/// (layer-menu-strings-outlive-their-entries-Q3).
LayerId groupTheActiveRowIntoAFolder(EditorSessionManager session) {
  final row = session.activeLayer!;
  return _asOneStep(session, () {
    session.layerStack.addLayerOfKind(LayerKind.folder);
    final folder = session.activeLayerId!;
    _dropOn(session, attachBaseIdOf(row), folder);
    session.selectLayer(row.id);
    return folder;
  });
}

/// An attach ORGANIZER (공정 폴더) around the attach row stood on, made as
/// the user makes one: an empty folder from Add Layer dropped on the row —
/// it joins the row's group — then the row dropped on the folder. Stood on
/// the row again; the folder is handed back.
LayerId groupTheActiveAttachIntoAFolder(EditorSessionManager session) {
  final row = session.activeLayerId!;
  return _asOneStep(session, () {
    session.layerStack.addLayerOfKind(LayerKind.folder);
    final folder = session.activeLayerId!;
    _dropOn(session, folder, row);
    _dropOn(session, row, folder);
    session.selectLayer(row);
    return folder;
  });
}

/// The steps [make] takes, banked as ONE undo: a fixture's folder is one
/// setting-up, as the menu's verb it stands in for was.
LayerId _asOneStep(EditorSessionManager session, LayerId Function() make) {
  late LayerId folder;
  session.historyManager.runAsOneStep('Group into folder', () {
    folder = make();
  });
  return folder;
}

/// One whole drag of [moving]'s row, let go ON [target]'s.
void _dropOn(EditorSessionManager session, LayerId moving, LayerId target) {
  final drag = session.layerRowDragVerbs;
  final layers = session.layers;
  drag.beginLayerRowDrag(LayerRowSubject(moving));
  drag.updateLayerRowDropOnRow(
    layers,
    layers.indexWhere((layer) => layer.id == target),
    target,
  );
  drag.endLayerRowDrag();
}
