import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/visibility_solo.dart';

/// 🚨F-129 — STANDING ON A FOLDER, SOLO SHOWS EVERYTHING IT HOLDS.
///
/// 유저 2026-09-14: 「활성레이어 솔로 시, 폴더에 서있으면 폴더 내용물 전부 on해서
/// 보여주도록. 중첩이 몇개있던 관계없이 내용물 전부」.
///
/// Solo kept the active row and the folders above it on. Standing on a
/// folder, that was the folder alone — a box with every row in it switched
/// off — so soloing a group showed nothing of the group.
void main() {
  /// Held by its own type — `tool/mutation_run.dart` picks a file's
  /// witnesses by which tests IMPORT it.
  VisibilitySolo soloOf(EditorSessionManager s) => s.visibilitySolo;

  const outer = LayerId('solo-outer');
  const inner = LayerId('solo-inner');
  const near = LayerId('solo-near');

  /// The drawing row made the deepest member of two nested folders, with a
  /// sibling beside the inner folder — each folder row directly above its
  /// members (the folder invariant):
  ///
  ///     outer
  ///       near
  ///       inner
  ///         deep   ← the drawing row, its own eye switched OFF
  ({EditorSessionManager s, LayerId deep}) nested() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cutId = s.requireActiveCut.id;
    final deep = s.requireActiveCut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.animation,
    );
    s.repository.replaceLayer(layer: deep.copyWith(folderId: inner));
    final at = s.requireActiveCut.layers.indexWhere(
      (layer) => layer.id == deep.id,
    );
    s.repository.insertLayer(
      cutId: cutId,
      layer: createFolderLayer(id: inner, name: 'inner', parentId: outer),
      index: at + 1,
    );
    s.repository.insertLayer(
      cutId: cutId,
      layer: Layer(
        id: near,
        name: 'near',
        frames: const [],
        timeline: const {},
        folderId: outer,
      ),
      index: at + 2,
    );
    s.repository.insertLayer(
      cutId: cutId,
      layer: createFolderLayer(id: outer, name: 'outer'),
      index: at + 3,
    );
    expect(
      folderStructureProblem(s.requireActiveCut.layers),
      isNull,
      reason: 'the premise: well-formed nested folders',
    );
    s.refreshAfterCutCommand();
    s.layerSwitches.toggleLayerVisibility(deep.id);
    return (s: s, deep: deep.id);
  }

  Set<LayerId> shownIn(EditorSessionManager s) => {
    for (final layer in s.requireActiveCut.layers)
      if (layer.isVisible) layer.id,
  };

  test('standing on a folder, every row under it is on — the nested folder, '
      'the row in it whose own eye was off, the sibling — and nothing '
      'outside it', () {
    final (:s, :deep) = nested();
    s.selectLayer(outer);

    soloOf(s).toggleLayerVisibilitySolo();

    expect(shownIn(s), {outer, near, inner, deep});
  });

  test('standing on the inner folder: what it holds and the folder above '
      'it, not the sibling beside it', () {
    final (:s, :deep) = nested();
    s.selectLayer(inner);

    soloOf(s).toggleLayerVisibilitySolo();

    expect(
      shownIn(s),
      {outer, inner, deep},
      reason:
          'the folder ABOVE stays on so the row is shown at all; the subtree '
          'is the one of the folder you stand on, not of every folder above',
    );
  });

  test('leaving puts the eye that was off back off', () {
    final (:s, :deep) = nested();
    final before = shownIn(s);
    expect(before.contains(deep), isFalse, reason: 'the CONTROL');
    s.selectLayer(outer);
    soloOf(s).toggleLayerVisibilitySolo();

    soloOf(s).toggleLayerVisibilitySolo();

    expect(shownIn(s), before);
  });
}
