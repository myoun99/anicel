import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';

/// [LayerFolderIndex] exists only to answer the SAME questions
/// [LayerFolderQueries] answers, without re-scanning the stack per probe.
/// So the contract is equivalence, and that is what these pin — including
/// on the malformed stacks the extension is explicitly safe on (a cycle, a
/// missing parent), because a faster walk that loops forever on a cycle is
/// not the same walk.
void main() {
  Layer folder(String id, {String? parent, bool collapsed = false,
      bool visible = true}) =>
      createFolderLayer(
        id: LayerId(id),
        name: id,
        parentId: parent == null ? null : LayerId(parent),
      ).copyWith(collapsed: collapsed, isVisible: visible);

  Layer cel(String id, {String? folderId}) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    timeline: const {},
    folderId: folderId == null ? null : LayerId(folderId),
  );

  /// Asserts the index and the extension agree about every id in [stack],
  /// plus null (top level) and an id that is not in the stack at all.
  void expectAgreement(List<Layer> stack) {
    final index = LayerFolderIndex(stack);
    final probes = <LayerId?>[
      null,
      const LayerId('nowhere'),
      for (final layer in stack) layer.id,
    ];
    for (final probe in probes) {
      expect(
        index.folderById(probe)?.id,
        stack.folderById(probe)?.id,
        reason: 'folderById($probe)',
      );
      expect(
        index.ancestryOf(probe).map((f) => f.id).toList(),
        stack.ancestryOf(probe).map((f) => f.id).toList(),
        reason: 'ancestryOf($probe)',
      );
      expect(
        index.depthOf(probe),
        stack.ancestryOf(probe).length,
        reason: 'depthOf($probe)',
      );
      expect(
        index.subtreeCollapsed(probe),
        stack.subtreeCollapsed(probe),
        reason: 'subtreeCollapsed($probe)',
      );
      expect(
        index.subtreeVisible(probe),
        stack.subtreeVisible(probe),
        reason: 'subtreeVisible($probe)',
      );
      if (probe != null) {
        expect(
          index.subtreeMembersOf(probe).map((l) => l.id).toList(),
          stack.subtreeMembersOf(probe).map((l) => l.id).toList(),
          reason: 'subtreeMembersOf($probe)',
        );
      }
    }
  }

  test('a flat stack with no folders agrees', () {
    expectAgreement([cel('a'), cel('b'), cel('c')]);
  });

  test('nested folders agree — order, depth, subtree membership', () {
    // inner holds x,y; outer holds inner + z. Folder rows sit directly
    // above their members, which is the structural invariant.
    expectAgreement([
      cel('x', folderId: 'inner'),
      cel('y', folderId: 'inner'),
      folder('inner', parent: 'outer'),
      cel('z', folderId: 'outer'),
      folder('outer'),
      cel('loose'),
    ]);
  });

  test('a collapsed or hidden ancestor folds the whole subtree, both ways',
      () {
    expectAgreement([
      cel('x', folderId: 'inner'),
      folder('inner', parent: 'outer', collapsed: true),
      folder('outer', visible: false),
    ]);
  });

  test('a MISSING parent reads as top level in both', () {
    expectAgreement([
      cel('x', folderId: 'ghost'),
      folder('orphan', parent: 'ghost'),
    ]);
  });

  test('a CYCLE terminates in both, at the same chain', () {
    expectAgreement([
      folder('a', parent: 'b'),
      folder('b', parent: 'a'),
      cel('x', folderId: 'a'),
    ]);
  });

  test('a folderId naming a NON-folder layer reads as top level in both', () {
    expectAgreement([cel('base'), cel('x', folderId: 'base')]);
  });

  test('the shared subtree lists are built once and stay stack-ordered', () {
    final stack = [
      cel('x', folderId: 'f'),
      cel('y', folderId: 'f'),
      folder('f'),
    ];
    final index = LayerFolderIndex(stack);
    // Asking twice returns the same list instance — the walk runs once.
    expect(
      identical(index.subtreeMembersOf(const LayerId('f')),
          index.subtreeMembersOf(const LayerId('f'))),
      isTrue,
    );
    expect(
      index.subtreeMembersOf(const LayerId('f')).map((l) => l.id.value),
      ['x', 'y'],
    );
    // A folder nobody points at answers empty rather than null.
    expect(index.subtreeMembersOf(const LayerId('nowhere')), isEmpty);
  });
}
