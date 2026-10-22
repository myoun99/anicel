import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_model.dart';
import '../helpers/temp_dir.dart';

/// 🗣️유저 2026-10-22: 「ai 검증을 제목쪽에 태그로 넣어서 카드 안누르고도
/// 어떤결과인지 확인가능하게 해줘」 — the row's chip reads [aiVerdictOf].
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('board-ai'));
  tearDown(() => deleteTempQuietly(dir));

  BoardCard card(List<String> notes) {
    final lines = [
      '{"kind":"item","id":"F-1","at":"검증","title":"고침",'
          '"ts":"2026-10-20T01:00:00Z"}',
      for (var i = 0; i < notes.length; i++)
        '{"id":"F-1","note":"${notes[i]}",'
            '"ts":"2026-10-2${i + 1}T02:00:00Z"}',
    ];
    final f = File('${dir.path}/board.jsonl')
      ..writeAsStringSync(lines.map((l) => '$l\n').join());
    return readBoard(f).firstWhere((c) => c.id == 'F-1');
  }

  test('each of the four labels, bold as the sessions write them, is read '
      'with its day', () {
    for (final (written, verdict) in [
      ('🤖**AI 검증완료 · 증거 있음**(서피스): 봤다', 'evidence'),
      ('🤖**AI 검증완료**(서피스): 봤다', 'done'),
      ('🤖**AI 검증 실패**: 안 고쳐짐', 'failed'),
      ('👤**유저 확인 필요**: 펜 느낌', 'user'),
    ]) {
      expect(
        aiVerdictOf(card([written])),
        (verdict: verdict, day: '10-21'),
        reason: written,
      );
    }
  });

  test('the newest verdict wins, and a later line that is no verdict keeps '
      'it', () {
    expect(
      aiVerdictOf(
        card([
          '👤**유저 확인 필요**: 키',
          '🤖**AI 검증 실패**: 그대로다',
          '🏁착지 — 다시 고쳤다',
        ]),
      ),
      (verdict: 'failed', day: '10-22'),
    );
  });

  test('⛔a card with no verdict line has none — a word inside a line is no '
      'verdict', () {
    expect(aiVerdictOf(card([])), isNull);
    expect(aiVerdictOf(card(['적어 둠: 🤖AI 검증완료 는 다음에'])), isNull);
  });
}
