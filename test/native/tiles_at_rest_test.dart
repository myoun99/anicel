import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/tiles_at_rest.dart';

/// Who is told as the engine's tiles come to rest (`TilesAtRest`, card
/// cel-originals-are-held-twice-in-ram-and-on-the-gpu): each for as long
/// as it asked to be, in the order they asked, and by what it said last.
///
/// When a rest is is the ledger's
/// (the_ledger_folds_its_tiles_once_the_hand_rests_test.dart).
void main() {
  late TilesAtRest told;
  late List<String> heard;

  setUp(() {
    told = TilesAtRest();
    heard = [];
  });

  test('everyone told hears each rest, in the order they asked', () {
    final first = Object();
    final second = Object();
    told.tells(first, () => heard.add('first'));
    told.tells(second, () => heard.add('second'));

    told.rested();
    told.rested();

    expect(heard, ['first', 'second', 'first', 'second']);
  });

  test('🚨one told anew hears by what it said last, and once', () {
    final holder = Object();
    told.tells(holder, () => heard.add('before'));
    told.tells(holder, () => heard.add('now'));

    told.rested();

    expect(heard, ['now']);
  });

  test('🚨one forgotten hears no more, and the others still', () {
    final gone = Object();
    final stays = Object();
    told.tells(gone, () => heard.add('gone'));
    told.tells(stays, () => heard.add('stays'));
    expect(told.debugTells(gone), isTrue, reason: '⛔premise');

    told.forgets(gone);
    told.rested();

    expect(heard, ['stays']);
    expect(told.debugTells(gone), isFalse);
    expect(told.debugTells(stays), isTrue);
  });

  test('one that forgets itself as it hears leaves the rest their word', () {
    final leaves = Object();
    final stays = Object();
    told.tells(leaves, () {
      heard.add('leaves');
      told.forgets(leaves);
    });
    told.tells(stays, () => heard.add('stays'));

    told.rested();
    told.rested();

    expect(heard, ['leaves', 'stays', 'stays']);
  });

  test('a rest with nobody told is nobody\'s', () {
    expect(told.rested, returnsNormally);
  });
}
