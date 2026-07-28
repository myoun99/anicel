import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_group.dart';
import 'package:anicel/src/models/brush_group_id.dart';

import '../helpers/json_round_trip.dart';

void main() {
  group('BrushGroup', () {
    const group = BrushGroup(id: BrushGroupId('ink'), name: 'Ink');

    test('starts expanded', () {
      expect(group.collapsed, isFalse);
    });

    test('copyWith preserves unspecified fields', () {
      final renamed = group.copyWith(name: 'Inking');

      expect(renamed.id, group.id);
      expect(renamed.collapsed, group.collapsed);
      expect(renamed.name, 'Inking');
    });

    test('toJson/fromJson round-trips both fold states', () {
      expectJsonRoundTrip(group, BrushGroup.fromJson);
      expectJsonRoundTrip(group.copyWith(collapsed: true), BrushGroup.fromJson);
    });

    test('equality includes id, name, and fold state', () {
      expect(group.copyWith(id: const BrushGroupId('paint')), isNot(group));
      expect(group.copyWith(name: 'Inking'), isNot(group));
      expect(group.copyWith(collapsed: true), isNot(group));
    });

    test('renaming keeps identity, so members stay put', () {
      // The whole point of groups being entities: a rename is one write and
      // no member has to be touched.
      expect(group.copyWith(name: 'Inking').id, group.id);
    });
  });

  group('importedBrushGroupId', () {
    test('is derived from the source name, so re-import finds it again', () {
      expect(
        importedBrushGroupId('NOAHS-BRUSHES'),
        importedBrushGroupId('NOAHS-BRUSHES'),
      );
      expect(
        importedBrushGroupId('NOAHS-BRUSHES'),
        isNot(importedBrushGroupId('불투명 수채')),
      );
    });
  });
}
