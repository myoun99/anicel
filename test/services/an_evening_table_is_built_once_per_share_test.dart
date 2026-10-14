import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/brush_dab_share.dart';

/// A stroke lays a few shares, and each share's table is a thousand powers
/// ([eveningTableFor]): the last table answers the run of dabs one move
/// lays, and the tables already built answer the shares a stroke goes back
/// to.
///
/// ⚠️A file of its own: the tables are the process's, and a file whose
/// earlier tests left them one short of their bound would start them over
/// between the two asks below.
void main() {
  test('a share asked again after another answers the table it built', () {
    final first = eveningTableFor(0.1);
    eveningTableFor(0.2);
    expect(identical(eveningTableFor(0.1), first), isTrue);
  });
}
