import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_model.dart';
import '../helpers/temp_dir.dart';

/// 🗣️유저 2026-11-15, a-voided-ai-verdict-cannot-reopen-its-card-Q1 = a: 「AI
/// 가 끝낸 카드만, AI 의 뒤 판정 줄로 다시 연다」.
///
/// 🧪pen-up-dock-tail: a 🤖AI 검증완료 ended it, the number behind it turned
/// out to be measured on a screen that was not drawing, and the verify
/// session's 👤유저 확인 필요 after it — a `정정` line, the only line an
/// ended card takes — changed the chip and left the card in 완료.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('board-ai-reopen'));
  tearDown(() => deleteTempQuietly(dir));

  const owner = '브러시';
  BoardCard read(List<String> lines) {
    final records = File('${dir.path}/board.jsonl')
      ..writeAsStringSync(lines.map((l) => '$l\n').join());
    return readBoard(records).firstWhere((c) => c.id == 'F-1');
  }

  final born = jsonEncode({
    'kind': 'item',
    'id': 'F-1',
    'title': '고침',
    'at': '할 일',
    'owner': owner,
    'ts': '2026-11-15T01:00:00Z',
  });
  const landed = '{"id":"F-1","at":"검증","how":"열어 본다",'
      '"ts":"2026-11-15T02:00:00Z"}';
  String line(String words, String ts, {String at = ''}) => jsonEncode({
        'id': 'F-1',
        if (at.isNotEmpty) 'at': at,
        'note': words,
        'ts': ts,
      });
  final aiDone = line('🤖**AI 검증완료 · 증거 있음**: 봤다', '2026-11-15T02:50:00Z');
  const voidedAt = '2026-11-15T03:10:00Z';

  /// What the verify session writes on a card that has ended.
  String fix(String words) => line(words, voidedAt, at: '정정');
  final handed = fix('👤**유저 확인 필요**: 그 숫자는 안 그려지던 화면에서 쟀다');
  final failed = fix('🤖**AI 검증 실패**: 도크가 멈칫한다');

  test('⛔premise: the AI verdict ended the card', () {
    final card = read([born, landed, aiDone]);
    expect(statusOf(card), BoardStatus.done);
    expect(endedCards([card]), contains('F-1'));
  });

  test('🚨유저 확인 필요 after it brings the card back to 검증 — on the shelf, '
      'its own line the check that waits', () {
    final card = read([born, landed, aiDone, handed]);
    expect(statusOf(card), BoardStatus.verify);
    expect(endedCards([card]), isEmpty);
    expect(checksWaiting(card), [voidedAt]);
    expect(onTheShelf(card), isTrue);
  });

  test('🚨a failure after it sends the card to its owner\'s 할 일, and tells '
      'the owner', () {
    final card = read([born, landed, aiDone, failed]);
    expect(statusOf(card), BoardStatus.todo);
    expect(
      [
        for (final letter in lettersOf([card]))
          (letter.entry.to, letter.entry.from, letter.entry.ts),
      ],
      [(owner, kAiVerifier, voidedAt)],
    );
  });

  test('⛔a 완료 the user pressed stays ended, whatever an AI says after it',
      () {
    const ticked = '{"id":"F-1","at":"완료","said":"","ts":'
        '"2026-11-15T02:50:00Z"}';
    for (final verdict in [handed, failed]) {
      final card = read([born, landed, ticked, verdict]);
      expect(statusOf(card), BoardStatus.done, reason: verdict);
      expect(lettersOf([card]), isEmpty, reason: verdict);
    }
  });

  test('⛔another 검증완료 after it leaves the card as it was', () {
    final card = read([born, landed, aiDone, fix('🤖**AI 검증완료**: 또 봤다')]);
    expect(statusOf(card), BoardStatus.done);
  });

  test('a 검증완료 after the reopening ends the card again', () {
    final card = read([
      born,
      landed,
      aiDone,
      handed,
      line('🤖**AI 검증완료**: 기기에서 봤다', '2026-11-15T04:00:00Z'),
    ]);
    expect(statusOf(card), BoardStatus.done);
    expect(checksWaiting(card), isEmpty);
  });

  test('⛔a card the AI ended and someone moved on is not pulled back', () {
    const moved = '{"id":"F-1","at":"백로그","said":"","ts":'
        '"2026-11-15T03:00:00Z"}';
    final card = read([born, landed, aiDone, moved, failed]);
    expect(statusOf(card), BoardStatus.backlog);
  });
}
