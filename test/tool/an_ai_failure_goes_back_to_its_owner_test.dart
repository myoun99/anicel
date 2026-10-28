import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_model.dart';
import '../../tool/board_say.dart';
import '../helpers/temp_dir.dart';

/// 🗣️유저 2026-10-27, ai-verdict-done-is-the-users-tick-Q1 = a: 「자동 — 담당의
/// 할 일로 옮기고 담당 세션에 알림」. A 🤖AI 검증 실패 on a card in 검증 does
/// what 관제 did by hand for every failure before: the card goes back to its
/// owner's 할 일, and the line reaches the owner's session as a letter.
void main() {
  late Directory dir;
  late File records;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('board-ai-failure');
    records = File('${dir.path}/board.jsonl');
  });
  tearDown(() => deleteTempQuietly(dir));

  const owner = '캔버스 베이스 패널';
  BoardCard read(List<String> lines) {
    records.writeAsStringSync(lines.map((l) => '$l\n').join());
    return readBoard(records).firstWhere((c) => c.id == 'F-1');
  }

  String born({String holder = owner}) => jsonEncode({
        'kind': 'item',
        'id': 'F-1',
        'title': '고침',
        'at': '할 일',
        'owner': holder,
        'ts': '2026-10-27T01:00:00Z',
      });
  const landed = '{"id":"F-1","at":"검증","how":"열어 본다",'
      '"ts":"2026-10-27T02:00:00Z"}';
  const failedAt = '2026-10-27T02:50:00Z';
  const words = '🤖**AI 검증 실패**(10-27 서피스, 윈도 릴리스 master '
      '`d61cca6da`): 세로 획의 바운딩 상자가 통째로 검게 칠해진다';
  final failed = jsonEncode({'id': 'F-1', 'note': words, 'ts': failedAt});

  /// What 관제 wrote for a failure before: the card back to 할 일.
  const movedByHand = '{"id":"F-1","at":"할 일","note":"관제: 실패 — 담당에",'
      '"ts":"2026-10-27T02:55:00Z"}';

  ({BoardStatus status, String owner, int waiting}) asked(BoardCard card) =>
      (
        status: statusOf(card),
        owner: card.owner,
        waiting: checksWaiting(card).length,
      );

  List<BoardLog> toldTo(String reader, BoardCard card) => [
        for (final letter in lettersOf([card]))
          if (letterWaitsFor(letter.entry, reader)) letter.entry,
      ];

  test('🚨the card goes back to its owner\'s 할 일, as 관제 moved it by hand',
      () {
    expect(asked(read([born(), landed, failed])),
        asked(read([born(), landed, movedByHand])));
    expect(statusOf(read([born(), landed, failed])), BoardStatus.todo);
  });

  test('🚨the owner is told the failure — the verdict\'s own words, from the '
      'verdict', () {
    final told = toldTo(owner, read([born(), landed, failed]));
    expect([for (final l in told) (l.ts, l.from, l.to, l.text)],
        [(failedAt, kAiVerifier, owner, words)]);
  });

  test('🚨the session\'s hook takes it once: the 읽음 lands on the verdict', () {
    read([born(), landed, failed]);
    final now = DateTime.parse('2026-10-27T03:00:00Z');
    expect(takeLetters(records, owner, now), contains('세로 획의 바운딩 상자'));
    expect(toldTo(owner, readBoard(records).single), isEmpty);
    expect(takeLetters(records, owner, now), isEmpty);
  });

  test('once a later word moves the card, the failure waits for nobody', () {
    const taken = '{"id":"F-1","at":"하는 중","note":"고친다",'
        '"ts":"2026-10-27T03:00:00Z"}';
    expect(toldTo(owner, read([born(), landed, failed, taken])), isEmpty);
  });

  test('⛔a card nobody holds goes to 할 일 and tells no one', () {
    final card = read([born(holder: ''), landed, failed]);
    expect(statusOf(card), BoardStatus.todo);
    expect(lettersOf([card]), isEmpty);
  });

  test('⛔on a card taken back into work, or for 유저 확인 필요, nothing moves '
      'and no one is told', () {
    // ⚠️백로그, not 하는 중: a claim lapses a day after the card's last
    // entry ([wentQuiet]), and a fixed date would fail tomorrow.
    const shelved = '{"id":"F-1","at":"백로그","note":"나중에",'
        '"ts":"2026-10-27T02:40:00Z"}';
    final taken = read([born(), landed, shelved, failed]);
    expect(lettersOf([taken]), isEmpty);
    expect(statusOf(taken), BoardStatus.backlog);

    final userTurn = jsonEncode({
      'id': 'F-1',
      'note': '👤**유저 확인 필요**: 펜 압력은 기기에서',
      'ts': failedAt,
    });
    final waiting = read([born(), landed, userTurn]);
    expect(statusOf(waiting), BoardStatus.verify);
    expect(lettersOf([waiting]), isEmpty);
  });
}
