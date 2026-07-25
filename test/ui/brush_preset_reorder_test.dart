import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/brush_group.dart';
import 'package:quick_animaker_v2/src/models/brush_group_id.dart';
import 'package:quick_animaker_v2/src/models/brush_preset.dart';
import 'package:quick_animaker_v2/src/models/brush_preset_id.dart';
import 'package:quick_animaker_v2/src/models/brush_settings.dart';
import 'package:quick_animaker_v2/src/ui/brush/brush_preset_reorder.dart';

const _watercolor = BrushGroupId('watercolor');
const _ink = BrushGroupId('ink');

BrushPreset _preset(String id, {BrushGroupId? groupId}) {
  return BrushPreset(
    id: BrushPresetId(id),
    name: id,
    groupId: groupId,
    settings: BrushSettings(size: 5),
  );
}

List<String> _ids(List<BrushPreset> presets) => [
  for (final preset in presets) preset.id.value,
];

void main() {
  group('moveBrushPresetInLibrary', () {
    final library = [
      _preset('a'),
      _preset('b'),
      _preset('w1', groupId: _watercolor),
      _preset('w2', groupId: _watercolor),
      _preset('w3', groupId: _watercolor),
    ];

    test('moves before an anchor within the same group', () {
      final moved = moveBrushPresetInLibrary(
        presets: library,
        movedId: const BrushPresetId('w3'),
        targetGroupId: _watercolor,
        insertBeforeId: const BrushPresetId('w1'),
      );

      expect(_ids(moved), ['a', 'b', 'w3', 'w1', 'w2']);
      expect(moved[2].groupId, _watercolor);
    });

    test('appends at the end of the target group without an anchor', () {
      final moved = moveBrushPresetInLibrary(
        presets: library,
        movedId: const BrushPresetId('a'),
        targetGroupId: _watercolor,
      );

      expect(_ids(moved), ['b', 'w1', 'w2', 'w3', 'a']);
      expect(moved.last.groupId, _watercolor);
    });

    test('moving into the root section clears the group', () {
      final moved = moveBrushPresetInLibrary(
        presets: library,
        movedId: const BrushPresetId('w2'),
        targetGroupId: null,
        insertBeforeId: const BrushPresetId('b'),
      );

      expect(_ids(moved), ['a', 'w2', 'b', 'w1', 'w3']);
      expect(moved[1].groupId, isNull);
    });

    test('an unknown moved id returns the library unchanged', () {
      final moved = moveBrushPresetInLibrary(
        presets: library,
        movedId: const BrushPresetId('missing'),
        targetGroupId: null,
      );

      expect(moved, same(library));
    });

    test('a missing anchor appends at the end of the library', () {
      final moved = moveBrushPresetInLibrary(
        presets: library,
        movedId: const BrushPresetId('a'),
        targetGroupId: _watercolor,
        insertBeforeId: const BrushPresetId('missing'),
      );

      expect(_ids(moved), ['b', 'w1', 'w2', 'w3', 'a']);
    });

    test('moving into an EMPTY group appends at the end', () {
      // An empty group has no member to anchor against — the whole reason
      // groups are entities is that this case exists at all.
      final moved = moveBrushPresetInLibrary(
        presets: library,
        movedId: const BrushPresetId('a'),
        targetGroupId: _ink,
      );

      expect(_ids(moved), ['b', 'w1', 'w2', 'w3', 'a']);
      expect(moved.last.groupId, _ink);
    });
  });

  group('moveBrushGroupInLibrary', () {
    const groups = [
      BrushGroup(id: BrushGroupId('g1'), name: 'One'),
      BrushGroup(id: BrushGroupId('g2'), name: 'Two'),
      BrushGroup(id: BrushGroupId('g3'), name: 'Three'),
    ];

    List<String> ids(List<BrushGroup> groups) => [
      for (final group in groups) group.id.value,
    ];

    test('moves a group before an anchor', () {
      final moved = moveBrushGroupInLibrary(
        groups: groups,
        movedId: const BrushGroupId('g3'),
        insertBeforeId: const BrushGroupId('g1'),
      );

      expect(ids(moved), ['g3', 'g1', 'g2']);
    });

    test('appends when no anchor is given', () {
      final moved = moveBrushGroupInLibrary(
        groups: groups,
        movedId: const BrushGroupId('g1'),
      );

      expect(ids(moved), ['g2', 'g3', 'g1']);
    });

    test('a missing anchor appends', () {
      final moved = moveBrushGroupInLibrary(
        groups: groups,
        movedId: const BrushGroupId('g1'),
        insertBeforeId: const BrushGroupId('missing'),
      );

      expect(ids(moved), ['g2', 'g3', 'g1']);
    });

    test('an unknown moved id returns the list unchanged', () {
      final moved = moveBrushGroupInLibrary(
        groups: groups,
        movedId: const BrushGroupId('missing'),
      );

      expect(moved, same(groups));
    });

    test('anchoring on itself is a no-op ordering', () {
      final moved = moveBrushGroupInLibrary(
        groups: groups,
        movedId: const BrushGroupId('g2'),
        insertBeforeId: const BrushGroupId('g2'),
      );

      // Its own id is not in the remaining list, so it appends rather than
      // vanishing — order changes, membership does not.
      expect(ids(moved), ['g1', 'g3', 'g2']);
    });
  });
}
