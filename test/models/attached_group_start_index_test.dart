// AN ATTACH GROUP STARTS AT THE FIRST ATTACH ROW THAT SITS BELOW ITS BASE.
//
// The mutation campaign (2026-09-03) turned the group walk's `==` into `!=`
// — every row that was NOT attached to the base then joined the group —
// and nothing noticed. These pins walk a small stack.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';

Layer _row(String id, {String? attachedTo}) => Layer(
  id: LayerId(id),
  name: id,
  frames: const [],
  attachedToLayerId: attachedTo == null ? null : LayerId(attachedTo),
  attachedMode: AttachedMode.synced,
);

void main() {
  test('the group starts at the base when nothing rides below it', () {
    final layers = [_row('x'), _row('base'), _row('y')];
    expect(attachedGroupStartIndex(const LayerId('base'), layers), 1);
  });

  test('an attach row placed below the base pulls the start up to it', () {
    final layers = [_row('x'), _row('att', attachedTo: 'base'), _row('base')];
    expect(attachedGroupStartIndex(const LayerId('base'), layers), 1);
  });

  test('a row attached to some OTHER base does not join', () {
    final layers = [_row('other', attachedTo: 'z'), _row('base')];
    expect(attachedGroupStartIndex(const LayerId('base'), layers), 1);
  });

  test('a missing base answers the list length, so the slice is empty', () {
    final layers = [_row('x')];
    expect(attachedGroupStartIndex(const LayerId('nope'), layers), 1);
  });

  group('the SLICE the seven callers take', () {
    test('is the base plus the rows on BOTH sides of it', () {
      final layers = [
        _row('x'),
        _row('below', attachedTo: 'base'),
        _row('base'),
        _row('above', attachedTo: 'base'),
        _row('y'),
      ];
      expect(
        attachedGroupSlice(
          const LayerId('base'),
          layers,
        ).map((layer) => layer.id.value),
        ['below', 'base', 'above'],
      );
    });

    test('a missing base gives an EMPTY slice, never the whole stack', () {
      final layers = [_row('x'), _row('base')];
      expect(attachedGroupSlice(const LayerId('nope'), layers), isEmpty);
    });

    test('the base id of a member is the row it rides; of a base, itself', () {
      expect(
        attachBaseIdOf(_row('att', attachedTo: 'base')),
        const LayerId('base'),
      );
      expect(attachBaseIdOf(_row('base')), const LayerId('base'));
    });
  });
}
