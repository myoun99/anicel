import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_say.dart';

/// 🚨★★★I DO NOT GET TO TYPE `ts`.
///
/// ⛔A stamp written by hand is a value I have to compute correctly every
/// single time, and the record is: **39 invented stamps on 2026-08-31**
/// (02·03·04·06·09·11·12·14시 while the clock read 01:36), and twice more the
/// same day AFTER the gate existed to catch it — I read the clock in one
/// command and wrote a later time in the next. The gate caught both. A rule
/// that has to be obeyed 41 times is not a rule, it is a missing mechanism.
///
/// ⚠️It matters because `ts` is the STORY'S ORDER, not a date on a panel: 유저
/// ticked `C-t11` at 01:34 and the card did not leave, because a 실기 확인 I
/// had stamped 14:10 sorted after their tick and stayed the last 대분류.
///
/// ⚠️And it REFUSES rather than writes. An append-only file cannot take a bad
/// line back, so an unknown field, an unknown kind or a missing id costs one
/// message instead of a permanent complaint.
void main() {
  test('🚨★★★a `ts` of my own is refused — that IS the tool', () {
    expect(
      recordRefusal({'kind': 'item', 'id': 'W', 'ts': '2026-09-09T00:00:00'}, 1),
      contains('ts'),
    );
  });

  test('⛔a field nobody reads is refused BEFORE it is written', () {
    final why = recordRefusal({'kind': 'item', 'id': 'W', 'ask': '내용'}, 1);
    expect(why, contains('ask'));
    expect(
      why,
      contains('options'),
      reason: 'the fix is in the refusal — the reader lists what it does read',
    );
  });

  test('⛔a kind nobody handles is refused', () {
    expect(recordRefusal({'kind': '질문', 'id': 'W'}, 1), contains('질문'));
  });

  test('⛔a record with no id is refused — the board skips those silently', () {
    expect(recordRefusal({'kind': 'item', 'at': '남은 것'}, 1), contains('id'));
  });

  test('⛔`meta` carries whatever its note needs, and needs no id', () {
    // 🧪`landedSince` looks dead to every `json['…']` site in tool/, and
    // `board_gate.sh:223` greps it straight out of the file.
    expect(
      recordRefusal({'kind': 'meta', 'landedSince': '2026-08-23T00:00:00Z'}, 1),
      isNull,
    );
  });

  test('🚨a well-formed record passes', () {
    expect(
      recordRefusal({'kind': 'item', 'id': 'W', 'at': '남은 것', 'rest': '할 것'}, 1),
      isNull,
    );
  });

  group('부를 수 없는 방식은 조용히 넘어가지 않는다', () {
    test('⛔wrong argument count', () {
      expect(boardSayRefusal([]), isNotNull);
      expect(boardSayRefusal(['a'], exists: (_) => true), isNotNull);
      expect(boardSayRefusal(['a', 'b', 'c'], exists: (_) => true), isNotNull);
    });

    test('⛔a missing file is named', () {
      final why = boardSayRefusal(['board.jsonl', 'nope.jsonl'],
          exists: (p) => p == 'board.jsonl');
      expect(why, contains('nope.jsonl'));
    });

    test('🚨two real paths run', () {
      expect(
        boardSayRefusal(['board.jsonl', 'in.jsonl'], exists: (_) => true),
        isNull,
      );
    });
  });

  group('실제로 붙여 쓴다', () {
    // ⚠️No subprocess. `boardSayAppend` hands back BYTES or a REFUSAL and
    // never both, so both halves are visible to a plain call — and a test
    // that spawns `dart` is a test that depends on a PATH the runner may
    // not have.
    test('🚨stamps from the given clock, in order', () {
      final now = DateTime.utc(2026, 8, 31, 22, 55, 34);
      final r = boardSayAppend([
        '{"kind":"item","id":"T","at":"남은 것","title":"첫 줄"}',
        '{"kind":"item","id":"T","at":"하는 중","note":"둘째 줄"}',
      ], now);
      expect(r.refusal, isNull);
      final lines = r.bytes!.trim().split('\n');
      expect(lines, hasLength(2));
      final a = jsonDecode(lines[0]) as Map<String, dynamic>;
      final b = jsonDecode(lines[1]) as Map<String, dynamic>;
      expect(a['title'], '첫 줄', reason: '한글이 argv 를 안 타야 한다');
      expect(
        a['ts'],
        now.toIso8601String(),
        reason: '⛔premise: the stamp is the clock it was HANDED, not a '
            'string the tool invented — otherwise this measures nothing',
      );
      expect(
        DateTime.parse('${a['ts']}').isBefore(DateTime.parse('${b['ts']}')),
        isTrue,
        reason: 'the story keeps the order they were written in',
      );
    });

    test('⛔a bad line yields NO BYTES — half an append is impossible', () {
      final r = boardSayAppend([
        '{"kind":"item","id":"T","at":"남은 것","title":"좋은 줄"}',
        '{"kind":"item","id":"T","ask":"나쁜 줄"}',
      ], DateTime.utc(2026, 8, 31));
      expect(r.refusal, contains('ask'));
      expect(
        r.bytes,
        isNull,
        reason: '🚨the GOOD line must not come back either — the caller has '
            'nothing to write, so it cannot half-write an append-only file',
      );
    });

    test('⛔a line that is not JSON is named by its number', () {
      final r = boardSayAppend(['{oops'], DateTime.utc(2026, 8, 31));
      expect(r.refusal, contains('1번째 줄'));
      expect(r.bytes, isNull);
    });

    test('⛔nothing to say is a refusal, not an empty append', () {
      final r = boardSayAppend(['', '   '], DateTime.utc(2026, 8, 31));
      expect(r.refusal, isNotNull);
      expect(r.bytes, isNull);
    });
  });
}
