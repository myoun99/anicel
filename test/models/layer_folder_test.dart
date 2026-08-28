import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';

void main() {
  Layer folder(String id, {String? parent, bool collapsed = false}) =>
      createFolderLayer(
        id: LayerId(id),
        name: id,
        parentId: parent == null ? null : LayerId(parent),
      ).copyWith(collapsed: collapsed);

  Layer cel(String id, {String? folderId}) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    timeline: const {},
    folderId: folderId == null ? null : LayerId(folderId),
  );

  group('folder rows are layers', () {
    test('createFolderLayer holds no cels and prints nothing', () {
      final row = folder('a');
      expect(row.kind, LayerKind.folder);
      expect(layerKindHoldsDrawings(row.kind), isFalse);
      expect(layerKindAcceptsBrushInput(row.kind), isFalse);
      expect(layerKindTakesTimesheetColumn(row.kind), isFalse);
      expect(row.frames, isEmpty);
      expect(row.timeline, isEmpty);
      expect(row.onTimesheet, isFalse);
    });

    test('a folder carries the same display state every layer carries', () {
      final row = folder('a');
      expect(layerKindHasPictureOpacity(row.kind), isTrue);
      expect(layerKindHasLayerTransform(row.kind), isTrue);
      expect(layerKindComposites(row.kind), isTrue);
      // ...but paints no surface of its own — its members do.
      expect(layerKindPaintsArtwork(row.kind), isFalse);
    });

    test('toJson/fromJson round-trips the row, twirl included', () {
      final row = folder('a', collapsed: true).copyWith(opacity: 0.5);
      final restored = Layer.fromJson(row.toJson());
      expect(restored, row);
      expect(restored.collapsed, isTrue);
      expect(folder('a').toJson().containsKey('collapsed'), isFalse);
    });
  });

  group('folder queries over the stack', () {
    // Stack order, bottom → top: each folder sits directly above its run.
    final stack = [
      cel('l1', folderId: 'grandchild'),
      folder('grandchild', parent: 'child'),
      folder('child', parent: 'root', collapsed: true),
      folder('root'),
    ];

    test('ancestryOf walks to the top, nearest first', () {
      expect(
        stack.ancestryOf(const LayerId('grandchild')).map((f) => f.id.value),
        ['grandchild', 'child', 'root'],
      );
      expect(stack.ancestryOf(null), isEmpty);
    });

    test('folderById ignores rows that are not folders', () {
      expect(stack.folderById(const LayerId('l1')), isNull);
      expect(stack.folderById(const LayerId('root'))?.name, 'root');
    });

    test('subtreeCollapsed sees any collapsed ancestor', () {
      expect(stack.subtreeCollapsed(const LayerId('grandchild')), isTrue);
      expect(stack.subtreeCollapsed(const LayerId('root')), isFalse);
    });

    test('subtreeVisible: a hidden ancestor hides the subtree', () {
      final withHidden = [
        cel('l1', folderId: 'child'),
        folder('child', parent: 'root'),
        folder('root').copyWith(isVisible: false),
      ];
      expect(withHidden.subtreeVisible(const LayerId('child')), isFalse);
    });

    test('subtreeMembersOf gathers the whole subtree in stack order', () {
      expect(
        stack.subtreeMembersOf(const LayerId('root')).map((l) => l.id.value),
        ['l1', 'grandchild', 'child'],
      );
      expect(
        stack.directMembersOf(const LayerId('root')).map((l) => l.id.value),
        ['child'],
      );
    });
  });

  group('folderStructureProblem', () {
    test('sound structures pass', () {
      expect(
        folderStructureProblem([
          cel('below'),
          cel('m1', folderId: 'a'),
          cel('m2', folderId: 'b'),
          folder('b', parent: 'a'),
          cel('m3', folderId: 'a'),
          folder('a'),
          cel('above'),
        ]),
        isNull,
        reason:
            "a's members (nested b included) form one unbroken run with the "
            'folder row directly above it',
      );
    });

    test('attach folders: a pure organizer and the shared outer folder '
        'pass; a folder mixing attach rows with other rows is reported', () {
      Layer attach(String id, {required String base, String? folderId}) =>
          cel(id, folderId: folderId).copyWith(
            attachedToLayerId: LayerId(base),
          );

      // Pure organizer: nothing but one base's attaches.
      expect(
        folderStructureProblem([
          cel('base'),
          attach('a1', base: 'base', folderId: 'org'),
          attach('a2', base: 'base', folderId: 'org'),
          folder('org'),
        ]),
        isNull,
      );
      // Shared OUTER folder: the base lives in it too.
      expect(
        folderStructureProblem([
          cel('base', folderId: 'outer'),
          attach('a1', base: 'base', folderId: 'outer'),
          folder('outer'),
        ]),
        isNull,
      );
      // Mixing an attach with an unrelated row (no base member) would
      // split the group across a folder boundary.
      expect(
        folderStructureProblem([
          cel('base'),
          attach('a1', base: 'base', folderId: 'bad'),
          cel('stray', folderId: 'bad'),
          folder('bad'),
        ]),
        contains('mixes attach rows'),
      );
    });

    test('🆕an attach organizer may NEST — the leaves name the base', () {
      // 유저 2026-08-29: 「어태치 폴더 중첩도 허용하는 방향으로 가자」.
      Layer attach(String id, {required String base, String? folderId}) =>
          cel(id, folderId: folderId).copyWith(
            attachedToLayerId: LayerId(base),
          );

      // ⛔이것이 예전에 거부되던 모양이다: 조직자 안의 폴더는
      // `attachedToLayerId` 가 없어서 「순수 조직자」 판정을 깨뜨렸다.
      expect(
        folderStructureProblem([
          cel('base'),
          attach('a1', base: 'base', folderId: 'inner'),
          folder('inner', parent: 'org'),
          attach('a2', base: 'base', folderId: 'org'),
          folder('org'),
        ]),
        isNull,
        reason: '중첩 폴더는 구조지, 「누구의 어태치인가」에 대한 답이 아니다',
      );

      // 🚨중첩을 허용한 것이지 섞임을 허용한 것이 아니다 — 깊은 곳의 잎이
      // 다른 base 를 타면 그룹이 여전히 폴더 경계로 쪼개진다.
      expect(
        folderStructureProblem([
          cel('base'),
          cel('other'),
          attach('a1', base: 'base', folderId: 'inner'),
          folder('inner', parent: 'org'),
          attach('a2', base: 'other', folderId: 'org'),
          folder('org'),
        ]),
        contains('mixes attach rows'),
        reason: '두 base 가 한 조직자 안에 있으면 그룹 범위를 못 만든다',
      );

      // 🚨어태치가 아닌 행이 깊은 곳에 섞이는 것도 그대로 막힌다.
      expect(
        folderStructureProblem([
          cel('base'),
          attach('a1', base: 'base', folderId: 'inner'),
          cel('stray', folderId: 'inner'),
          folder('inner', parent: 'org'),
          folder('org'),
        ]),
        contains('mixes attach rows'),
        reason: '깊이가 섞임을 숨겨 주지 않는다',
      );
    });

    test('a non-contiguous folder run is reported', () {
      expect(
        folderStructureProblem([
          cel('m1', folderId: 'a'),
          cel('outsider'),
          cel('m2', folderId: 'a'),
          folder('a'),
        ]),
        contains('not contiguous'),
      );
    });

    test('a folder row away from its members is reported', () {
      expect(
        folderStructureProblem([
          cel('m1', folderId: 'a'),
          folder('a'),
          cel('stray'),
        ]),
        isNull,
        reason: 'the folder sits directly above its run',
      );
      expect(
        folderStructureProblem([
          folder('a'),
          cel('m1', folderId: 'a'),
        ]),
        contains('directly above'),
      );
    });

    test('a missing folder reference is reported', () {
      expect(
        folderStructureProblem([cel('orphan', folderId: 'ghost')]),
        contains('missing folder'),
      );
    });

    test('a cyclic parent chain is reported', () {
      expect(
        folderStructureProblem([
          folder('a', parent: 'b'),
          folder('b', parent: 'a'),
        ]),
        contains('cyclic'),
      );
    });
  });
}
