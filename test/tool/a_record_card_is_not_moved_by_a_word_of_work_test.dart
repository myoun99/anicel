import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_model.dart';
import '../../tool/board_say.dart';
import '../../tool/board_server.dart';
import '../helpers/project_scratch_folder.dart';

/// 🚨A CARD FILED IN 기록 IS NOT MOVED BY A WORD OF WORK.
///
/// 유저 2026-10-16: 「기록용은 따로 백로그말고 항목두는게 나아보이는데」, and
/// 2026-10-18 (record-cards-get-their-own-place-Q1): 「기록 카드엔 칸 말을
/// 쓰기 전에 막는다」. The seven roadmaps, handovers and session notes that
/// went to 기록 held 73 lines of place words — 하는 중 written on a roadmap
/// out of habit — and the last place word wins, so the next one would have
/// carried the card back among the work.
void main() {
  const filed = '{"kind":"item","id":"R","title":"로드맵","at":"기록",'
      '"note":"남은 일","ts":"2026-10-18T09:00:00"}';
  const work = '{"kind":"item","id":"W","title":"작업","at":"할 일",'
      '"note":"할 것","ts":"2026-10-18T09:00:00"}';

  File records(List<String> lines) {
    final d = Directory.systemTemp.createTempSync('record-cards');
    deleteAfterSessionEnds(d);
    return File('${d.path}/board.jsonl')
      ..writeAsStringSync('${lines.join('\n')}\n');
  }

  List<BoardCard> board(List<String> lines) => readBoard(records(lines));

  test('⛔premise: a card filed in 기록 stands there, a card of work does '
      'not', () {
    expect(recordCards(board([filed, work])), {'R'});
  });

  group('거절', () {
    const inRecords = {'R'};
    String? refusal(String at) =>
        recordCardRefusal({'id': 'R', 'at': at, 'note': 'x'}, 1, inRecords);

    test('🚨a word that would move it is refused, and the refusal says the '
        'way out', () {
      final why = refusal('하는 중');
      expect(why, isNotNull);
      expect(why, contains('R'));
      expect(why, contains('기록'));
      expect(why, contains('하는 중'));
      expect(why, contains('`note`'));
      for (final word in ['할 일', '백로그', '진행 중', '착수 가능', '남은 것']) {
        expect(refusal(word), isNotNull, reason: word);
      }
    });

    test('⛔what does not move it passes: 기록 itself, an ending, a 소분류, '
        'no `at` at all', () {
      for (final word in ['기록', '완료', '취소', '작업 기록', '정정', '']) {
        expect(refusal(word), isNull, reason: word);
      }
    });

    test('⛔nor do the two words that are no longer places', () {
      expect(refusal('유저'), isNull);
      expect(refusal('질문'), isNull);
    });

    test('⛔a card that is not in 기록 takes any word', () {
      expect(
        recordCardRefusal({'id': 'W', 'at': '하는 중'}, 1, inRecords),
        isNull,
      );
    });
  });

  group('쓰는 길', () {
    test('🚨the writer refuses it whole — the line next to it does not land '
        'either', () {
      final file = records([filed, work]);
      final before = file.readAsStringSync();
      final said = sayToRecords(
        file,
        [
          '{"id":"W","note":"좋은 줄"}',
          '{"id":"R","at":"하는 중","note":"오늘 한 것"}',
        ],
        DateTime.utc(2026, 10, 18, 10),
      );
      expect(said.refusal, contains('기록 칸의 카드'));
      expect(file.readAsStringSync(), before);
    });

    test('⛔a note on it is written, and the card stays in 기록', () {
      final file = records([filed]);
      final said = sayToRecords(
        file,
        ['{"id":"R","note":"오늘 한 것"}'],
        DateTime.utc(2026, 10, 18, 10),
      );
      expect(said.refusal, isNull);
      final card = readBoard(file).firstWhere((c) => c.id == 'R');
      expect(statusOf(card), BoardStatus.records);
    });

    test('⛔a move from the board does not go through the writer — the user '
        'can still take it back among the work', () {
      final file = records([filed]);
      final card = readBoard(file).firstWhere((c) => c.id == 'R');
      final line = moveRecord(
        card: card,
        id: 'R',
        to: '할 일',
        now: () => '2026-10-18T10:00:00',
      );
      file.writeAsStringSync('${jsonEncode(line)}\n', mode: FileMode.append);
      expect(
        statusOf(readBoard(file).firstWhere((c) => c.id == 'R')),
        BoardStatus.todo,
      );
    });
  });
}
