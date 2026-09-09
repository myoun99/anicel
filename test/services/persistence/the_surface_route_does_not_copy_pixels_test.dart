import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**THE ONE THING THAT MAKES THE PARK ROUTE WORTH HAVING IS
/// INVISIBLE TO EVERY BEHAVIOURAL TEST.** `encodeCelEntryFromSurface`
/// writes a tile's bytes through `readPixels`, which hands the native
/// view straight to the writer. Writing `tile.pixels` instead produces
/// BYTE-FOR-BYTE the same stream — and a defensive 64KB copy per tile,
/// at the moment the byte budget said there was no room.
///
/// ⚠️Verified by mutation: swapping `readPixels` for the getter left the
/// whole suite green. So the contract is enforced on the source, the way
/// this repo closes 「사본 금지」.
void main() {
  test('🚨the surface route reads pixels IN PLACE, never through the '
      'defensive getter', () {
    final source = File(
      'lib/src/services/persistence/brush_drawing_binary_codec.dart',
    ).readAsStringSync();

    final start = source.indexOf('Uint8List encodeCelEntryFromSurface');
    final end = source.indexOf('Uint8List encodeCelEntry(AnicelCelEntry');
    expect(start, greaterThan(-1), reason: 'setup: the function is there');
    expect(end, greaterThan(start), reason: 'setup: and the next one after');

    final body = source.substring(start, end);
    expect(
      body.contains('readPixels'),
      isTrue,
      reason: 'setup: this is the function the contract is about',
    );
    expect(
      body.contains('.pixels'),
      isFalse,
      reason:
          'BitmapTile.pixels is a defensive 64KB copy per tile, and not '
          'copying is the whole reason this route exists. The bytes are '
          'identical either way, so no behavioural test can see it.',
    );
  });
}
