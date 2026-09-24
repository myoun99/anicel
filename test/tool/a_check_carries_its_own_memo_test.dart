import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_model.dart';
import '../helpers/temp_dir.dart';

/// 🚨A MEMO ON A HANDS-ON CHECK IS TWO FACTS, and only one of them clears the
/// check (유저 2026-08-31: 「실기확인 항목마다 메모란도 존재해야하지않을까?
/// **원래 실기확인은 그렇잖아**」).
///
/// ⛔The tick route writes BOTH lines because `checksWaiting` clears on
/// 확인 완료 / 완료 and on nothing else. A single 유저 line — which is what I
/// wrote first — routes the card correctly and leaves the button on screen,
/// looking to the user as though the tick never landed.
///
/// ⚠️And the routing is not decoration: H24, F-28, F-22-rest and R27-rest
/// were each ticked `ok` WITH a memo saying what was still wrong. The tick
/// cleared the row, the words left with it, and nothing on the board said
/// they existed for four days.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('board-tick'));
  tearDown(() => deleteTempQuietly(dir));

  BoardCard cardFrom(List<String> lines) {
    final file = File('${dir.path}/board.jsonl')
      ..writeAsStringSync(lines.map((l) => '$l\n').join());
    return readBoard(file).firstWhere((c) => c.id == 'C');
  }

  const opened =
      '{"kind":"item","id":"C","title":"T","at":"실기 확인",'
      '"said":"첫째","ts":"2026-08-31T01:00:00Z"}';
  const opened2 =
      '{"kind":"item","id":"C","at":"실기 확인",'
      '"said":"둘째","ts":"2026-08-31T01:01:00Z"}';

  test('⛔fixture premise: two checks are open and the card sits in 실기 확인',
      () {
    final card = cardFrom([opened, opened2]);
    expect(checksWaiting(card), hasLength(2));
    expect(card.state, 'hands');
  });

  test('a quiet tick clears its own check and nothing else', () {
    final card = cardFrom([
      opened,
      opened2,
      '{"kind":"item","id":"C","at":"확인 완료","ref":"2026-08-31T01:00:00Z",'
          '"said":"확인 — 문제 없음","ts":"2026-08-31T02:00:00Z"}',
    ]);
    expect(checksWaiting(card), ['2026-08-31T01:01:00Z']);
    expect(card.state, 'hands', reason: 'one left, so the card stays');
  });

  test('🚨a tick WITH a memo clears the check AND brings the card back', () {
    final card = cardFrom([
      opened,
      opened2,
      '{"kind":"item","id":"C","at":"확인 완료","ref":"2026-08-31T01:00:00Z",'
          '"said":"확인함","ts":"2026-08-31T02:00:00Z"}',
      '{"kind":"item","id":"C","at":"유저","ref":"2026-08-31T01:00:00Z",'
          '"said":"73번째가 흰 화면","ts":"2026-08-31T02:00:01Z"}',
    ]);
    expect(
      checksWaiting(card),
      ['2026-08-31T01:01:00Z'],
      reason: '⛔the button must go — a 유저 line alone would leave it up',
    );
    expect(
      card.state,
      'inbox',
      reason: '유저가 적은 것은 언제나 분류 전 — this is the law four reports '
          'were lost for want of',
    );
    expect(
      card.log.any((l) => l.text == '73번째가 흰 화면' && l.byUser),
      isTrue,
      reason: 'and the words are IN the story, not attached to nothing',
    );
  });

  test('🚨the last quiet tick ends the card; a memo on it does not', () {
    final ended = cardFrom([
      opened,
      '{"kind":"item","id":"C","at":"완료","ref":"2026-08-31T01:00:00Z",'
          '"said":"확인 — 문제 없음","ts":"2026-08-31T02:00:00Z"}',
    ]);
    expect(checksWaiting(ended), isEmpty);
    expect(ended.state, 'archived');

    final spoke = cardFrom([
      opened,
      '{"kind":"item","id":"C","at":"완료","ref":"2026-08-31T01:00:00Z",'
          '"said":"확인함","ts":"2026-08-31T02:00:00Z"}',
      '{"kind":"item","id":"C","at":"유저","ref":"2026-08-31T01:00:00Z",'
          '"said":"아직 렉이 있다","ts":"2026-08-31T02:00:01Z"}',
    ]);
    expect(checksWaiting(spoke), isEmpty, reason: 'every check is answered');
    expect(
      spoke.state,
      'inbox',
      reason: '⛔but it does NOT archive — that is exactly how the four were '
          'lost, and the memo is the reason to look again',
    );
  });

  test('⛔two checks answered with the SAME words both survive', () {
    // The dedupe key is (text, ref). Without the ref on the 유저 line the
    // second one would be swallowed as a repeat of the first.
    final card = cardFrom([
      opened,
      opened2,
      '{"kind":"item","id":"C","at":"확인 완료","ref":"2026-08-31T01:00:00Z",'
          '"said":"확인함","ts":"2026-08-31T02:00:00Z"}',
      '{"kind":"item","id":"C","at":"유저","ref":"2026-08-31T01:00:00Z",'
          '"said":"안 됨","ts":"2026-08-31T02:00:01Z"}',
      '{"kind":"item","id":"C","at":"완료","ref":"2026-08-31T01:01:00Z",'
          '"said":"확인함","ts":"2026-08-31T02:01:00Z"}',
      '{"kind":"item","id":"C","at":"유저","ref":"2026-08-31T01:01:00Z",'
          '"said":"안 됨","ts":"2026-08-31T02:01:01Z"}',
    ]);
    expect(checksWaiting(card), isEmpty);
    expect(
      card.log.where((l) => l.text == '안 됨').length,
      2,
      reason: 'one per check — the ref is what tells them apart',
    );
  });
}
