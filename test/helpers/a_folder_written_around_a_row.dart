import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_folder.dart' show createFolderLayer;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/project_lookup.dart' show requireCut;
import 'package:anicel/src/services/project_repository.dart';

/// A FOLDER around [member] in [cutId], written straight into
/// [repository]: the folder row right above the member, in the member's own
/// folder, and the member in it — the shape a drop on an empty folder
/// leaves (R5 #14). In that cut only, and outside the undo history.
///
/// ↩️These fixtures ran the folder-creation command, which went with the
/// menu verbs that alone called it
/// (layer-menu-strings-outlive-their-entries-Q3).
void writeAFolderAround(
  ProjectRepository repository, {
  required CutId cutId,
  required LayerId member,
  required LayerId folderId,
  String name = 'Folder',
}) {
  final layers = requireCut(repository.requireProject(), cutId).layers;
  final index = layers.indexWhere((layer) => layer.id == member);
  repository.insertLayer(
    cutId: cutId,
    layer: createFolderLayer(
      id: folderId,
      name: name,
      parentId: layers[index].folderId,
    ),
    index: index + 1,
  );
  repository.updateLayerFolderId(
    cutId: cutId,
    layerId: member,
    folderId: folderId,
  );
}
