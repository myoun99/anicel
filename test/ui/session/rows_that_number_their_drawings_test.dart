import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/session/block_naming.dart';

/// Which ROWS 자동 이름 지정 numbers (I-18). The kinds are the table's
/// column ([LayerKind.numbersItsDrawings], pinned in `layer_kind_test`);
/// this pins what the row adds to its kind.
void main() {
  test('a row of its own answers as its kind does', () {
    for (final kind in LayerKind.values) {
      final row = Layer(
        id: const LayerId('row'),
        name: 'R',
        frames: const [],
        kind: kind,
      );
      expect(
        rowNumbersItsDrawings(row),
        kind.numbersItsDrawings,
        reason: kind.name,
      );
    }
  });

  test('⛔a SYNCED attach row names nothing of its own — it prints its '
      "base's names (UI-R24 #2)", () {
    Layer attached(AttachedMode mode) => Layer(
      id: const LayerId('rider'),
      name: 'Rider',
      frames: const [],
      attachedToLayerId: const LayerId('base'),
      attachedMode: mode,
    );

    expect(rowNumbersItsDrawings(attached(AttachedMode.synced)), isFalse);
    expect(
      rowNumbersItsDrawings(attached(AttachedMode.free)),
      isTrue,
      reason: 'a FREE attach row authors its own drawings (UI-R21 #3)',
    );
  });
}
