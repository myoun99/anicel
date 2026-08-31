import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_check.dart';

/// 🚨★★★A POINTER THAT POINTS AT NOTHING.
///
/// 유저 2026-08-31: 「결함들 다 구조적으로 해결해줘. 근본적인부분에서」.
///
/// The same law as `a_record_says_nothing_unread_test`, one level in: there
/// the key was never read; here the key WAS read and the value WAS used, and
/// it resolved to nothing — silently, with a board that looks fine.
///
/// 🧪All three were measured on fixtures before the check existed, and every
/// one produced no complaint at all.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('board-ptr'));
  tearDown(() => dir.deleteSync(recursive: true));

  String complaints(List<String> lines) {
    File('${dir.path}/board.jsonl').writeAsStringSync(lines.join('\n'));
    return boardCheckComplaints(File('${dir.path}/board.jsonl'),
        now: DateTime.utc(2026, 9, 1));
  }

  const kLaw = '가리키는 곳이 없는 값';
  const check = '{"kind":"item","id":"W","at":"실기 확인","title":"작업",'
      '"note":"이걸 본다","ts":"2026-08-31T01:00:00Z"}';

  group('ref — 지울 체크를 못 찾는다', () {
    test('🚨a 확인 완료 whose ref clears no check is named', () {
      // ⛔The tick button stays on screen and the card never leaves 실기
      // 확인. 🧪I shipped a one-line version of this on 2026-08-31 and only
      // saw it by probing `waiting=1` by hand.
      final out = complaints([
        check,
        '{"kind":"item","id":"W","at":"확인 완료","ref":"없는-ts",'
            '"said":"확인","ts":"2026-08-31T02:00:00Z"}',
      ]);
      expect(out, contains(kLaw));
      expect(out, contains('W: ref→없는-ts'));
    });

    test('⛔a ref that names the real check says nothing', () {
      final out = complaints([
        check,
        '{"kind":"item","id":"W","at":"확인 완료","ref":"2026-08-31T01:00:00Z",'
            '"said":"확인","ts":"2026-08-31T02:00:00Z"}',
      ]);
      expect(out, isNot(contains(kLaw)));
    });
  });

  group('of — 원본 카드가 파일에 없다', () {
    const opts = '"options":[{"key":"a","label":"A"},{"key":"b","label":"B"}],'
        '"where":"거기","why":"막혔다","recommend":"a"';

    test('🚨a question naming an origin that does not exist', () {
      // The question stands alone and the answer has nowhere to go back to.
      final out = complaints([
        check,
        '{"kind":"decision","id":"X-Q1","of":"없는카드","at":"질문",'
            '"title":"질문",$opts,"ts":"2026-08-31T02:00:00Z"}',
      ]);
      expect(out, contains('X-Q1: of→없는카드'));
    });

    test('🚨the `<원본>-Q<번호>` NAME is a pointer too', () {
      final out = complaints([
        check,
        '{"kind":"decision","id":"없는카드-Q1","at":"질문","title":"질문",'
            '$opts,"ts":"2026-08-31T02:00:00Z"}',
      ]);
      expect(out, contains('of→없는카드'));
    });

    test('⛔naming NO origin is not this — standing alone is correct there', () {
      // ⚠️`_questionsNobodyCanAnswer` already has a better complaint for a
      // question that names nothing. The defect here is naming something
      // that does not exist, which looks connected and is not.
      final out = complaints([
        check,
        '{"kind":"decision","id":"W-Q1","at":"질문","title":"질문",$opts,'
            '"ts":"2026-08-31T02:00:00Z"}',
      ]);
      expect(out, isNot(contains(kLaw)));
    });
  });

  group('법의 tag — 아무 카드도 안 쓴다', () {
    test('🚨a law whose tag no card carries', () {
      // ⛔Its 「손대기 전에」 is written and appears on nothing, and the law
      // itself sits in 착수 가능 looking like startable work.
      final out = complaints([
        check,
        '{"kind":"law","id":"law-없는태그","tag":"없는태그","note":"법",'
            '"ts":"2026-08-31T02:00:00Z"}',
      ]);
      expect(out, contains('law-없는태그: tag→없는태그'));
    });

    test('🚨a law cannot vouch for its own tag', () {
      // 🧪MUTATION SURVIVOR. Dropping the `kind != 'law'` guard broke nothing,
      // because `readBoard` does not fold a law's `tag` into its `tags` — so
      // no fixture reached the guard at all. ⛔The honest fix is the fixture,
      // not deleting a guard whose absence lets a law satisfy itself the day
      // somebody writes `tags` on one.
      final out = complaints([
        check,
        '{"kind":"law","id":"law-혼자","tag":"혼자","tags":["혼자"],'
            '"note":"법","ts":"2026-08-31T02:00:00Z"}',
      ]);
      expect(out, contains('law-혼자: tag→혼자'));
    });

    test('⛔a law whose tag a card actually carries says nothing', () {
      final out = complaints([
        '{"kind":"item","id":"W","at":"남은 것","title":"작업","tags":["보드"],'
            '"rest":"할 것","ts":"2026-08-31T01:00:00Z"}',
        '{"kind":"law","id":"law-보드","tag":"보드","note":"법",'
            '"ts":"2026-08-31T02:00:00Z"}',
      ]);
      expect(out, isNot(contains(kLaw)));
    });
  });

  group('⛔answer 는 이 법이 아니다', () {
    test('🚨a free answer naming no option is CORRECT, not dangling', () {
      // 🧪I wrote this as the fourth pointer. The live file produced 25 hits
      // and every one was right: the panel renders a radio with
      // `value="other"`, and `_askPanel` falls back to `{'label': d.answer}`
      // on purpose so an answer naming no option still shows.
      // ⛔An answer is the USER's word, not a key I get to constrain.
      final out = complaints([
        check,
        '{"kind":"decision","id":"W-Q1","at":"질문","title":"질문",'
            '"options":[{"key":"a","label":"A"},{"key":"b","label":"B"}],'
            '"where":"거기","why":"막혔다","recommend":"a",'
            '"ts":"2026-08-31T02:00:00Z"}',
        '{"kind":"decision","id":"W-Q1","answer":"이미 다른 데서 정했다",'
            '"ts":"2026-08-31T03:00:00Z","state":"archived"}',
        '{"kind":"item","id":"W","at":"유저","ts":"2026-08-31T03:00:01Z"}',
      ]);
      expect(out, isNot(contains(kLaw)));
    });
  });

  test('⛔an ack silences it, like every other complaint', () {
    File('${dir.path}/.gate-ack').writeAsStringSync('W 알고 있다\n');
    final out = complaints([
      check,
      '{"kind":"item","id":"W","at":"확인 완료","ref":"없는-ts","said":"확인",'
          '"ts":"2026-08-31T02:00:00Z"}',
    ]);
    expect(out, isNot(contains(kLaw)));
  });
}
