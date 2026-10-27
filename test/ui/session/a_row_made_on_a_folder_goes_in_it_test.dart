import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️F-492 (유저 2026-10-27): 「폴더위에 서서 레이어만들때 폴더 안에서
/// 만들도록 서있는상태는 유지」.
///
/// Every kind Add Layer makes above the row you stand on — the ＋, its key
/// and the ▾ menu all ask `addLayerOfKind` — goes INTO the folder you stand
/// on, at the top of what it holds, and you stand on the folder still.
void main() {
  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  List<Layer> stackOf(EditorSessionManager s) => s.requireActiveCut.layers;

  /// [s] standing on a new, empty folder.
  LayerId standOnAFolder(EditorSessionManager s) {
    s.layerStack.addLayerOfKind(LayerKind.folder);
    final folder = s.activeLayer!;
    expect(folder.kind, LayerKind.folder, reason: 'the premise: on it');
    return folder.id;
  }

  /// The row [s]'s stack gained since [before].
  Layer addedSince(EditorSessionManager s, Set<LayerId> before) => stackOf(
    s,
  ).singleWhere((layer) => !before.contains(layer.id));

  Set<LayerId> idsOf(EditorSessionManager s) => {
    for (final layer in stackOf(s)) layer.id,
  };

  for (final kind in [
    LayerKind.animation,
    LayerKind.image,
    LayerKind.adjustment,
    LayerKind.folder,
  ]) {
    test('a ${kind.name} row made on a folder goes in it, right under the '
        'folder row, and you stand on the folder still', () {
      final s = session();
      final folder = standOnAFolder(s);
      final before = idsOf(s);

      s.layerStack.addLayerOfKind(kind);

      final added = addedSince(s, before);
      final stack = stackOf(s);
      expect(added.kind, kind, reason: 'the premise');
      expect(added.folderId, folder);
      expect(stack[stack.indexOf(added) + 1].id, folder);
      expect(folderStructureProblem(stack), isNull);
      expect(s.activeLayerId, folder);
    });
  }

  test('the next one goes on top of the first — the top of what the folder '
      'holds', () {
    final s = session();
    final folder = standOnAFolder(s);
    final empty = idsOf(s);
    s.layerStack.addLayerOfKind(LayerKind.animation);
    final first = addedSince(s, empty);
    final before = idsOf(s);

    s.layerStack.addLayerOfKind(LayerKind.animation);

    final second = addedSince(s, before);
    final stack = stackOf(s);
    expect(stack.indexOf(second), stack.indexOf(first) + 1);
    expect(second.folderId, folder);
    expect(folderStructureProblem(stack), isNull);
  });

  test('↩️a row made on a plain row is still stood on — the folder is the '
      'one place you keep standing', () {
    final s = session();
    final from = s.activeLayerId;
    final before = idsOf(s);

    s.layerStack.addLayerOfKind(LayerKind.animation);

    final added = addedSince(s, before);
    expect(added.id, isNot(from), reason: 'the premise');
    expect(s.activeLayerId, added.id);
  });

  test('undo takes the row back out, and you stand on the folder', () {
    final s = session();
    final folder = standOnAFolder(s);
    final before = idsOf(s);
    s.layerStack.addLayerOfKind(LayerKind.animation);

    s.undo();

    expect(idsOf(s), before);
    expect(s.activeLayerId, folder);
  });
}
