import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_model.dart';
import '../helpers/temp_dir.dart';

/// 🚨A QUESTION IS A CARD WITH OPTIONS — not a card whose `kind` is a magic
/// word (유저 2026-08-31: 「너가 질문으로 옮긴것들, **질문으로 옮김이라는
/// 내용만 있는 질문항목**이야. 질문의 내용이없어. 다른 질문들이랑 뭐가
/// 다르길래 이렇게 작동하지? **통일하고 이런일 없도록 구조변경해도되**」).
///
/// ⛔`kind` was a word a writer had to REMEMBER, and I forgot it six times in
/// one day. Six question cards written as `item` reached 답할 것 and rendered
/// as ordinary rows — the stage line 「질문으로 옮김」 and no question inside.
/// Nothing was wrong with the data: `where`, `why`, `options` and `recommend`
/// were all there. The reader was asking the wrong thing about it.
///
/// ⚠️Notice what a count or a smoke test would have said: the cards were on
/// the board, in the right section, with the right title. Only a person
/// opening one could see that the question was missing.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('board-asks'));
  tearDown(() => deleteTempQuietly(dir));

  List<BoardCard> cardsFrom(List<String> lines) {
    final file = File('${dir.path}/board.jsonl')
      ..writeAsStringSync(lines.map((l) => '$l\n').join());
    return readBoard(file);
  }

  BoardCard one(List<BoardCard> cards, String id) =>
      cards.firstWhere((c) => c.id == id);

  const origin =
      '{"kind":"item","id":"W","title":"작업","at":"남은 것",'
      '"rest":"할 것","ts":"2026-08-31T01:00:00Z"}';

  /// The SAME question twice, differing only in the word `kind`.
  String question(String kind) =>
      '{"kind":"$kind","id":"W-Q1","at":"질문","title":"이렇게 할까",'
      '"where":"거기","why":"막혔다",'
      '"options":[{"key":"a","label":"A안"},{"key":"b","label":"B안"}],'
      '"recommend":"a","ts":"2026-08-31T02:00:00Z"}';

  test('⛔fixture premise: the two differ ONLY by kind', () {
    final asItem = one(cardsFrom([origin, question('item')]), 'W-Q1');
    final asDecision = one(cardsFrom([origin, question('decision')]), 'W-Q1');
    expect(asItem.kind, 'item');
    expect(asDecision.kind, 'decision');
    expect(asItem.options.length, asDecision.options.length);
    expect(asItem.why, asDecision.why);
  });

  for (final kind in ['item', 'decision']) {
    test('🚨a $kind card with options ASKS, and folds into its origin', () {
      final cards = cardsFrom([origin, question(kind)]);
      final q = one(cards, 'W-Q1');
      expect(
        cardAsks(q),
        isTrue,
        reason: '⛔the fields say it is a question; `kind` does not get a '
            'vote, because remembering a word is what failed',
      );
      expect(
        q.foldedInto,
        'W',
        reason: '질문은 원본 카드 안의 항목 — a question was never a subject '
            'of its own',
      );
      expect(
        one(cards, 'W').state,
        'ask',
        reason: 'and the ORIGIN is what sits in 답할 것',
      );
    });

    test('🚨answering a $kind question sends the origin to 분류 전', () {
      final cards = cardsFrom([
        origin,
        question(kind),
        '{"kind":"decision","id":"W-Q1","answer":"a","answerNote":"",'
            '"ts":"2026-08-31T03:00:00Z","state":"archived"}',
        '{"kind":"item","id":"W","ts":"2026-08-31T03:00:01Z"}',
      ]);
      expect(one(cards, 'W-Q1').answer, 'a');
      expect(
        one(cards, 'W').state,
        'inbox',
        reason: 'an answer is something the user said that I have to read',
      );
    });
  }

  test('⛔a card with NO options is not dragged into asking', () {
    // The origin cards in 답할 것 hold folded questions and carry none of
    // their own — turning every card into a question would be the same
    // mistake pointing the other way.
    final cards = cardsFrom([origin]);
    expect(cardAsks(one(cards, 'W')), isFalse);
    expect(one(cards, 'W').state, 'open');
  });

  group('답은 유저의 말로 적힌다', () {
    // 🚨유저 2026-09-12: 「보드에 2만으로는 알수없잖아. 그런것도 개선해줘」.
    //
    // The radio's value is the option's KEY, and a key is an index by
    // construction — so what the user picked reached the records file as a
    // number. The board drew it correctly (it resolves the key when it
    // renders), which is precisely why nobody noticed: only the LINE was
    // unreadable, and the line is the record.
    File recordsFile(List<String> lines) =>
        File('${dir.path}/board.jsonl')
          ..writeAsStringSync(lines.map((l) => '$l\n').join());

    test('🚨a key comes back as its LABEL — the line says what was chosen', () {
      final file = recordsFile([origin, question('decision')]);
      expect(answerWordFor('W-Q1', 'a', file), 'A안');
      expect(answerWordFor('W-Q1', 'b', file), 'B안');
    });

    test('🚨an option written with NO key resolves too — the key is its '
        'INDEX, and that index is what the record used to keep', () {
      final file = recordsFile([
        origin,
        '{"kind":"decision","id":"W-Q2","at":"질문","title":"어느 쪽",'
            '"where":"거기","why":"막혔다",'
            '"options":[{"label":"그대로 둔다"},{"label":"드러낸다"},'
            '{"label":"잘라 맞춘다"}],"ts":"2026-08-31T02:00:00Z"}',
      ]);
      expect(answerWordFor('W-Q2', '2', file), '드러낸다');
    });

    test('⛔an answer naming no option is kept EXACTLY as written', () {
      final file = recordsFile([origin, question('decision')]);
      // Free text, the panel's `other`, and every answer written before this
      // existed — all of them are already the user's word.
      expect(answerWordFor('W-Q1', '직접 적은 답', file), '직접 적은 답');
      expect(answerWordFor('W-Q1', 'other', file), 'other');
      expect(answerWordFor('W-Q1', 'se-lane', file), 'se-lane');
    });

    test('⛔an empty answer stays empty, and an unknown card changes nothing',
        () {
      final file = recordsFile([origin, question('decision')]);
      expect(answerWordFor('W-Q1', '', file), '');
      expect(answerWordFor('nope', 'a', file), 'a');
    });
  });

  test('⛔a legacy `decision` with no options still asks', () {
    // Written before options were required. It must keep its panel rather
    // than silently becoming an ordinary row — the very failure above.
    final cards = cardsFrom([
      '{"kind":"decision","id":"L","at":"질문","title":"옛 질문",'
          '"note":"본문","ts":"2026-08-31T01:00:00Z"}',
    ]);
    expect(cardAsks(one(cards, 'L')), isTrue);
  });
}
