import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_model.dart';
import '../helpers/temp_dir.dart';

/// 🚨★★★ONE SESSION'S WORD TO ANOTHER IS AN ENTRY ON A CARD.
///
/// 유저 2026-10-07 (the-board-is-one-server-for-both-machines-Q2): 「글은
/// 카드의 흐름에 적고, 「전달」 보기는 그것을 모아 보여 주기만 한다」. Two
/// machines run sessions under two accounts, a session's own messages do not
/// cross accounts, and the board is the one thing both reach.
///
/// ⛔The first shape proposed kept these in a list of their own, beside the
/// cards — and the law that ended that shape for answers stands here too:
/// 「별개로 두는것좀 절대로 없게해. 싹 다 타임라인흐름이야」 (유저
/// 2026-08-31). So what is pinned first is that a letter is NOTHING BUT a
/// line of its card: it stands in the story where it was written, it moves
/// the card nowhere, and being read is a mark on it rather than a row.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('board-letters'));
  tearDown(() => deleteTempQuietly(dir));

  List<BoardCard> board(List<String> lines) {
    final file = File('${dir.path}/board.jsonl')
      ..writeAsStringSync(lines.map((line) => '$line\n').join());
    return readBoard(file);
  }

  const mine = '보드/통합';
  const theirs = '타임라인/콘티';
  const card =
      '{"kind":"item","id":"W","at":"하는 중","owner":"$theirs",'
      '"title":"작업","note":"시작","ts":"2026-10-07T10:00:00.000000"}';
  String letter(
    String ts, {
    String to = theirs,
    String from = mine,
    String note = '레인이 착지했다',
    String id = 'W',
  }) => '{"kind":"item","id":"$id","to":"$to","from":"$from",'
      '"note":"$note","ts":"$ts"}';
  String read(String ts, {required String ref, required String by}) =>
      '{"kind":"item","id":"W","at":"$kReadMark","ref":"$ref",'
      '"from":"$by","ts":"$ts"}';
  const t1 = '2026-10-07T11:00:00.000000';
  const t2 = '2026-10-07T12:00:00.000000';
  const t3 = '2026-10-07T13:00:00.000000';

  group('a letter stands in its card\'s story', () {
    test('where it was written, under 전달, naming who it is for and who '
        'wrote it', () {
      final w = board([card, letter(t1)]).single;
      final entry = w.log.last;
      expect(entry.at, kLetterStage);
      expect(entry.text, '레인이 착지했다');
      expect((entry.to, entry.from), (theirs, mine));
      expect(entry.ts, t1);
      expect(entry.isLetter, isTrue);
      expect(w.log.first.isLetter, isFalse, reason: 'a note names nobody');
    });

    test('⛔it moves the card nowhere and names no new holder', () {
      final before = board([card]).single;
      final after = board([card, letter(t1, to: mine, from: theirs)]).single;
      expect(statusOf(after), statusOf(before));
      expect(after.owner, theirs, reason: '`to` is not `owner`');
    });

    // 🚨The pin above FAILED for one hour on 2026-10-08, between 10:00 and
    // 11:00: its card's 하는 중 (10-07 10:00) had gone quiet a day ago and
    // its letter (10-07 11:00) had not — and the letter was counted as the
    // card's newest entry, so the card with the letter was still 진행 중 and
    // the card without it was not. A letter had moved the card.
    // ⚠️Off the real clock here: a claim lapses a day after the card's last
    // word, so a fixed date measures nothing once it is a day old.
    group('and renews no claim', () {
      String ago(Duration time) =>
          DateTime.now().subtract(time).toIso8601String();
      String claimed(String ts) =>
          '{"kind":"item","id":"W","at":"하는 중","owner":"$theirs",'
          '"title":"작업","note":"시작","ts":"$ts"}';

      test('🚨a holder who went quiet a day ago is not kept in 진행 중 by a '
          'word left for them', () {
        final quiet = claimed(ago(const Duration(hours: 30)));
        final leftSince = letter(ago(const Duration(hours: 1)));
        expect(
          statusOf(board([quiet]).single),
          isNot(BoardStatus.doing),
          reason: '⛔premise: the claim has lapsed',
        );

        expect(
          statusOf(board([quiet, leftSince]).single),
          statusOf(board([quiet]).single),
        );
      });

      test('a claim the holder still keeps stays kept, letter or none', () {
        final live = claimed(ago(const Duration(hours: 2)));
        final leftSince = letter(ago(const Duration(hours: 1)));

        expect(statusOf(board([live]).single), BoardStatus.doing);
        expect(statusOf(board([live, leftSince]).single), BoardStatus.doing);
      });

      test('the holder\'s own word after a letter is the card\'s word — it '
          'is the letter that is not counted, not what follows it', () {
        final quiet = claimed(ago(const Duration(hours: 30)));
        final leftSince = letter(ago(const Duration(hours: 3)));
        final working =
            '{"kind":"item","id":"W","note":"이어서 한다",'
            '"ts":"${ago(const Duration(hours: 1))}"}';

        expect(
          statusOf(board([quiet, leftSince, working]).single),
          BoardStatus.doing,
        );
      });
    });

    test('⛔the same words again are another letter — to a second 담당, or '
        'to the same one twice', () {
      final w = board([
        card,
        letter(t1),
        letter(t2, to: '저장'),
        letter(t3),
      ]).single;
      final letters = w.log.where((entry) => entry.isLetter).toList();
      expect([for (final entry in letters) entry.ts], [t1, t2, t3]);
      expect([for (final entry in letters) entry.to], [theirs, '저장', theirs]);
    });
  });

  group('a 읽음 is a mark on the letter it names', () {
    test('the reader and the moment are noted on the letter, and the story '
        'gains no row', () {
      final w = board([card, letter(t1), read(t2, ref: t1, by: theirs)]).single;
      expect(w.log, hasLength(2), reason: 'the note and the letter');
      expect(w.log.last.readBy, {theirs: t2});
    });

    test('⛔being read is not the card moving: its date stays the '
        'letter\'s', () {
      final w = board([card, letter(t1), read(t3, ref: t1, by: theirs)]).single;
      expect(w.updated, t1);
    });

    test('⛔a mark that names no letter marks nothing — not a note, and '
        'not another card\'s letter', () {
      final cards = board([
        card,
        letter(t1),
        read(t2, ref: '2026-10-07T10:00:00.000000', by: theirs),
        read(t3, ref: 'no-such-stamp', by: theirs),
      ]);
      expect(cards.single.log.last.readBy, isEmpty);
      expect(cards.single.log.first.readBy, isEmpty);
    });

    test('each reader once — the first reading stands', () {
      final w = board([
        card,
        letter(t1, to: kEveryone),
        read(t2, ref: t1, by: theirs),
        read(t3, ref: t1, by: theirs),
        read(t3, ref: t1, by: '저장'),
      ]).single;
      expect(w.log.last.readBy, {theirs: t2, '저장': t3});
    });
  });

  group('who a letter waits for', () {
    test('the 담당 it names, until they have read it — and nobody else', () {
      final unread = board([card, letter(t1)]).single.log.last;
      expect(letterWaitsFor(unread, theirs), isTrue);
      expect(letterWaitsFor(unread, '저장'), isFalse);
      final seen = board([
        card,
        letter(t1),
        read(t2, ref: t1, by: theirs),
      ]).single.log.last;
      expect(letterWaitsFor(seen, theirs), isFalse);
    });

    test('⛔never the one who wrote it — a notice to everyone included', () {
      final toAll = board([card, letter(t1, to: kEveryone)]).single.log.last;
      expect(letterWaitsFor(toAll, mine), isFalse);
      final toSelf = board([card, letter(t1, to: mine)]).single.log.last;
      expect(letterWaitsFor(toSelf, mine), isFalse);
    });

    test('a notice to everyone waits for each 담당 on their own', () {
      final notice = board([
        card,
        letter(t1, to: kEveryone),
        read(t2, ref: t1, by: theirs),
      ]).single.log.last;
      expect(letterWaitsFor(notice, theirs), isFalse);
      expect(letterWaitsFor(notice, '저장'), isTrue);
    });

    test('⛔a session with no name is waited for by nothing, and a note is '
        'no letter', () {
      final w = board([card, letter(t1, to: kEveryone)]).single;
      expect(letterWaitsFor(w.log.last, ''), isFalse);
      expect(letterWaitsFor(w.log.first, theirs), isFalse);
    });
  });

  test('the letters of a board are read off its cards, in their order', () {
    const other =
        '{"kind":"item","id":"V","at":"할 일","title":"다른 작업",'
        '"note":"x","ts":"2026-10-07T10:30:00.000000"}';
    final cards = board([
      card,
      other,
      letter(t1),
      letter(t2, id: 'V', to: '저장'),
      letter(t3, to: kEveryone),
    ]);
    expect(
      [
        for (final letter in lettersOf(cards))
          (letter.card.id, letter.entry.ts),
      ],
      [('W', t1), ('W', t3), ('V', t2)],
    );
  });
}
