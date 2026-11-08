import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**THE ONE THING THAT MAKES THE PARK ROUTE WORTH HAVING IS
/// INVISIBLE TO EVERY BEHAVIOURAL TEST.** `encodeCelEntryFromSurface`
/// writes a tile's bytes as its reader hands them over — read back from
/// the engine a batch at a time through one block (flip lane ⓓ,
/// `EngineTileLedger.readEach`), or on a worker through `readPixels` —
/// each a view straight to the writer. Writing `tile.pixels` instead
/// produces BYTE-FOR-BYTE the same stream — and a defensive 64KB copy per
/// tile, at the moment the byte budget said there was no room.
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
    final end = source.indexOf('_celStreamHeaderOf(_ByteReader');
    expect(start, greaterThan(-1), reason: 'setup: the function is there');
    expect(end, greaterThan(start), reason: 'setup: and the next one after');

    // The route hands its tiles — the drawing's, and since the cel stream's
    // v3 every text plate's — to ONE walk of the writer's, so the contract
    // is the pair: the route goes through that walk and no other, and the
    // walk reads in place.
    final body = source.substring(start, end);
    expect(
      body.contains('writer.tilesOf('),
      isTrue,
      reason: 'setup: this is the function the contract is about',
    );
    const copies =
        'BitmapTile.pixels is a defensive 64KB copy per tile, and not '
        'copying is the whole reason this route exists. The bytes are '
        'identical either way, so no behavioural test can see it.';
    expect(body.contains('.pixels'), isFalse, reason: copies);

    final walkStart = source.indexOf('void tilesOf(');
    final walkEnd = source.indexOf('void bytes(List<int>');
    expect(walkStart, greaterThan(-1), reason: 'setup: the walk is there');
    expect(walkEnd, greaterThan(walkStart), reason: 'setup: and the next');
    final walk = source.substring(walkStart, walkEnd);
    expect(walk.contains('read(['), isTrue, reason: 'setup: it reads');
    expect(walk.contains('.pixels'), isFalse, reason: copies);

    // And each reader the route is handed hands views: the engine's, the
    // default, and the worker's.
    expect(
      body.contains('EngineTileLedger.instance.readEach'),
      isTrue,
      reason: 'setup: the engine reads by default',
    );
    final ledger = File(
      'lib/src/native/engine_tile_ledger.dart',
    ).readAsStringSync();
    final eachStart = ledger.indexOf('void readEach(');
    final eachEnd = ledger.indexOf('static const int readBatch');
    expect(eachEnd, greaterThan(eachStart), reason: 'setup: the read is there');
    final each = ledger.substring(eachStart, eachEnd);
    expect(each.contains('Uint8List.sublistView'), isTrue, reason: copies);
    expect(each.contains('.pixels'), isFalse, reason: copies);
    final worker = File(
      'lib/src/services/persistence/thaw_in_worker.dart',
    ).readAsStringSync();
    final inPlace = worker.substring(worker.indexOf('void _readInPlace('));
    expect(inPlace.contains('readPixels'), isTrue, reason: 'setup: it reads');
    expect(inPlace.contains('.pixels'), isFalse, reason: copies);
  });
}
