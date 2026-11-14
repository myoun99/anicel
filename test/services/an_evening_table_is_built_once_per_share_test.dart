import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/brush_dab_share.dart';

/// A stroke lays a share a move, and each share's table is a thousand
/// powers ([eveningTableFor]): the last table answers the run of dabs one
/// move lays, and the tables already built answer the shares a stroke goes
/// back to — every share there is to lay ([shareSteps]) at once.
///
/// ⚠️A file of its own: the tables are the process's, and a file that
/// asked for shares no dab lays would have them start over under the asks
/// below.
void main() {
  test('a share asked again after another answers the table it built', () {
    final first = eveningTableFor(100 / shareSteps);
    eveningTableFor(200 / shareSteps);
    expect(identical(eveningTableFor(100 / shareSteps), first), isTrue);
  });

  // 🔬A 300 px line of a vector layer lays 50–130 shares, a point a pixel
  // from the last: held 64 at a time, a stroke of 117 built 134 tables and
  // every stroke after built its own again.
  test('🚨every share a dab can lay is held at once: a stroke of many '
      'paces builds a share\'s table once', () {
    final first = eveningTableFor(1 / shareSteps);
    for (var step = 2; step < shareSteps; step += 1) {
      eveningTableFor(step / shareSteps);
    }
    expect(identical(eveningTableFor(1 / shareSteps), first), isTrue);
  });
}
