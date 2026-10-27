import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_model.dart';
import '../../tool/board_server.dart';
import '../helpers/temp_dir.dart';

/// 🗣️유저 2026-10-27: 「ai 검증완료면 그냥 내가 확인한거랑 똑같이
/// 작동하도록」 — every pin here builds the same card twice, once ticked by
/// the user (the lines the server writes) and once verified by the AI (the
/// line the verify session writes), and asks the board the same questions.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('board-ai-tick'));
  tearDown(() => deleteTempQuietly(dir));

  BoardCard read(List<String> lines) {
    final f = File('${dir.path}/board.jsonl')
      ..writeAsStringSync(lines.map((l) => '$l\n').join());
    return readBoard(f).firstWhere((c) => c.id == 'F-1');
  }

  var clock = 0;
  String now() => '2026-10-27T03:00:${(clock++).toString().padLeft(2, '0')}Z';

  const born = '{"kind":"item","id":"F-1","title":"고침","at":"할 일",'
      '"ts":"2026-10-27T01:00:00Z"}';
  const landed = '{"id":"F-1","at":"검증","how":"열어 본다",'
      '"ts":"2026-10-27T02:00:00Z"}';
  const relanded = '{"id":"F-1","at":"검증","how":"다시 열어 본다",'
      '"ts":"2026-10-27T02:30:00Z"}';
  const backToWork = '{"id":"F-1","at":"할 일","note":"다시 고친다",'
      '"ts":"2026-10-27T02:40:00Z"}';

  String note(String text) => jsonEncode(
      {'id': 'F-1', 'note': text, 'ts': '2026-10-27T02:50:00Z'});

  /// The user's 확인 on the list: every waiting check ticked, as the server
  /// writes it.
  List<String> userTicks(List<String> lines) => [
        ...lines,
        for (final r in confirmRecords(card: read(lines), now: now))
          jsonEncode(r),
      ];

  ({BoardStatus status, String state, int waiting, String? ended}) asked(
    List<String> lines,
  ) {
    final card = read(lines);
    return (
      status: statusOf(card),
      state: card.state,
      waiting: checksWaiting(card).length,
      ended: endedCards([card])[card.id],
    );
  }

  test('⛔fixture premise: a landed card waits in 검증 on one check, and the '
      'user\'s 확인 ends it', () {
    expect(asked([born, landed]),
        (status: BoardStatus.verify, state: 'hands', waiting: 1, ended: null));
    expect(asked(userTicks([born, landed])),
        (status: BoardStatus.done, state: 'archived', waiting: 0, ended: '완료'));
  });

  test('🚨검증완료 — plain or with evidence — ends the card as the tick does',
      () {
    // ⚠️As long as the lines the verify session really writes: the label is
    // read off the line's opening, and a short fixture never cuts one.
    for (final words in [
      '🤖**AI 검증완료**(10-27 서피스, 윈도 릴리스 master `d61cca6da`, '
          '마우스): ①일본어 セル 탭의 글자가 다 보인다',
      '🤖**AI 검증완료 · 증거 있음**(10-27 서피스, 윈도 릴리스 master '
          '`d61cca6da`): ①첨부 1 의 1 — 칸이 글자만큼 넓다',
    ]) {
      expect(
        asked([born, landed, note(words)]),
        asked(userTicks([born, landed])),
        reason: words,
      );
    }
  });

  test('🚨two checks waiting — both go, as the list\'s 확인 ticks both', () {
    expect(asked(userTicks([born, landed, relanded])).waiting, 0);
    expect(
      asked([born, landed, relanded, note('🤖**AI 검증완료**: 봤다')]),
      asked(userTicks([born, landed, relanded])),
    );
  });

  // ↩️실패 waited here too until Q1 = a sent it back to its owner — pinned in
  // an_ai_failure_goes_back_to_its_owner_test.
  test('⛔유저 확인 필요 leaves it waiting in 검증 for the user', () {
    expect(asked([born, landed, note('👤**유저 확인 필요**: 펜')]),
        asked([born, landed]));
  });

  test('⛔on a card taken back into work it finishes nothing — nor does the '
      'user\'s last tick there', () {
    final taken = [born, landed, backToWork];
    expect(asked(userTicks(taken)).status, BoardStatus.todo);
    expect(asked([...taken, note('🤖**AI 검증완료**: 봤다')]).status,
        BoardStatus.todo);
  });

  test('a landing after the verdict brings it back to 검증, waiting on the new '
      'check', () {
    const later = '{"id":"F-1","at":"검증","how":"또 열어 본다",'
        '"ts":"2026-10-27T04:00:00Z"}';
    final card = read([born, landed, note('🤖**AI 검증완료**: 봤다'), later]);
    expect(statusOf(card), BoardStatus.verify);
    expect(checksWaiting(card), ['2026-10-27T04:00:00Z']);
  });

  test('🧪the verdict left for 관제 first and then written on the card ends '
      'it — the card\'s line is no repeat of the letter (10-27)', () {
    const words = '🤖**AI 검증완료**(서피스): 봤다';
    final first = jsonEncode({
      'id': 'F-1',
      'to': '관제',
      'from': '검증/서피스',
      'note': words,
      'ts': '2026-10-27T02:45:00Z',
    });
    expect(asked([born, landed, first, note(words)]),
        asked(userTicks([born, landed])));
  });

  test('⛔a letter carrying the words moves nothing; nor do the words inside '
      'a line, or a line whose `at` names its own place', () {
    final letter = jsonEncode({
      'id': 'F-1',
      'to': '관제',
      'from': '검증/서피스',
      'note': '🤖**AI 검증완료**: 봤다',
      'ts': '2026-10-27T02:50:00Z',
    });
    final ownPlace = jsonEncode({
      'id': 'F-1',
      'at': '검증',
      'how': '열어 본다',
      'note': '🤖**AI 검증완료**: 봤다',
      'ts': '2026-10-27T02:50:00Z',
    });
    for (final line in [letter, note('적어 둠: 🤖AI 검증완료 는 다음에'), ownPlace]) {
      expect(asked([born, landed, line]).status, BoardStatus.verify,
          reason: line);
    }
  });
}
