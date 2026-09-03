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
}
