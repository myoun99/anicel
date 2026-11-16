import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/source_brackets.dart';

/// a-thawed-cel-is-adopted-on-the-ui-thread: the weight the tiles of a cel
/// share (`TileWeight`) lives while one of them does because each holds it
/// — in a field nothing reads (`_OwnBlock.weighedBy`), and the AOT compiler
/// takes away a field nothing reads, and what it held with it.
///
/// ⚠️A SOURCE PIN, because only an AOT build drops the field and every test
/// runs on the JIT, which keeps it (`dart compile exe`, 저장 2026-11-16: of
/// 100 values such a field alone held, none lived through a churn of
/// collections in the exe — 100 under the JIT, and 100 in the exe with the
/// pragma). That the weight goes with the last tile and not before is
/// pinned by behaviour (`tiles_made_together_are_weighed_once_test.dart`).
void main() {
  test("the field a tile holds its cel's weight by is an entry point, which "
      'the AOT compiler keeps', () {
    final code = withoutComments(
      File('lib/src/models/bitmap_tile.dart').readAsStringSync(),
    );

    expect(
      code,
      matches(
        RegExp(
          r"@pragma\('vm:entry-point'\)\s+final TileWeight\? weighedBy;",
        ),
      ),
    );
  });
}
