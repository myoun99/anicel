import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/source_brackets.dart';

/// a-thawed-cel-is-adopted-on-the-ui-thread: a tile's block is freed by a
/// finalizer attached with NO detach token (`TileBlocks.freeWith`), and one
/// nothing outside the blocks' file can attach to.
///
/// ⚠️A SOURCE PIN, because a token nobody detaches frees the same blocks at
/// the same moment: what tells the two apart is what the VM keeps for every
/// tile alive — a slot of the finalizer's Expando and a set beside it, the
/// table rebuilt whole as tiles come and go — which no test here can see.
/// That a collected tile gives its block back is pinned by behaviour
/// (`a_collected_tile_gives_its_block_back_test.dart`).
void main() {
  final code = withoutComments(
    File('lib/src/native/tile_blocks.dart').readAsStringSync(),
  );

  test('a tile block is attached to its finalizer with its weight and no '
      'detach token', () {
    expect(code, contains('externalSize: byteLength'));
    expect(code, isNot(contains('detach')));
  });

  test('a block weighed with the rest of its cel is attached with no weight '
      'of its own — the cel tells it once (TileWeight)', () {
    // ⚠️On the source for the reason above: the weight told is the VM's
    // to count, and no test here reads it. Told twice, the cel's tiles
    // were scavenged for as before (the card's 11-16 lines).
    expect(code, contains('_freesWhenCollected.attach(holder, block.cast());'));
  });

  test('the finalizer of the tile blocks is their file\'s own', () {
    final finalizers = [
      for (final declared in RegExp(
        r'NativeFinalizer (\w+) =',
      ).allMatches(code))
        declared.group(1),
    ];
    expect(finalizers, isNotEmpty, reason: 'premise: the file declares one');
    expect(finalizers, everyElement(startsWith('_')));
  });
}
