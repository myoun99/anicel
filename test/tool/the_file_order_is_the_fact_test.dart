import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_check.dart';

/// 🚨★★★A LATER LINE WITH AN EARLIER STAMP.
///
/// 유저 2026-08-31: 「c-t12같은거, 이런 비슷한 문제 실기확인에서 많거든?
/// **내용은 완료인 상태인데 왜 실기확인으로 옮긴건지?**」
///
/// ⛔THE FUTURE-STAMP RULE GOES BLIND. It asks 「is this later than now」, so
/// a stamp of 14:10 written at 01:36 is caught for eight hours and then
/// becomes ordinary history. 🧪That is exactly what happened: I stamped
/// `C-t11` and `C-t12` 실기 확인 at 14:10 while the clock read 01:36; 유저
/// ticked them 완료 at 01:34 and 01:39. Their real completions sorted BEFORE
/// my invented stamp, so the last 대분류 stayed 실기 확인 and the cards would
/// not leave the board — for the rest of the day, with the future check
/// looking straight past them.
///
/// ⚠️And the second symptom came from the same line: the cards showed no memo
/// box on their 실기 확인 entry, because a ref-less 완료 means 「this card is
/// done」 and clears every check. The board was telling the truth about the
/// checks and lying about the section, from one bad number.
///
/// 🚨THIS CHECK READS NO CLOCK. The file is append-only, so its ORDER is a
/// fact; a stamp that disagrees with it is wrong whenever you look.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('board-order'));
  tearDown(() => dir.deleteSync(recursive: true));

  String complaints(List<String> lines) {
    File('${dir.path}/board.jsonl').writeAsStringSync(lines.join('\n'));
    return boardCheckComplaints(File('${dir.path}/board.jsonl'),
        // ⚠️A year later, so the future-stamp rule cannot be what catches
        // these — that is the whole point of this file.
        now: DateTime.utc(2027, 9, 1));
  }

  const kLaw = '적힌 순서와 시각이 다른 카드';

  test('🚨★★★C-t12 exactly: 완료 ticked before an invented 실기 확인', () {
    final out = complaints([
      '{"kind":"check","id":"C-t12","at":"실기 확인","title":"T12",'
          '"note":"이걸 본다","ts":"2026-08-31T14:10:00+09:00"}',
      '{"kind":"item","id":"C-t12","at":"완료","said":"확인 — 문제 없음",'
          '"ts":"2026-08-31T01:39:40+09:00"}',
    ]);
    expect(out, contains(kLaw));
    expect(out, contains('C-t12'));
    expect(
      out,
      contains('board_say'),
      reason: '⛔the complaint carries the way out — writing `ts` by hand is '
          'what made this, and the tool that refuses to is the fix',
    );
  });

  test('⛔the same lines in honest order say nothing', () {
    final out = complaints([
      '{"kind":"check","id":"C-t12","at":"실기 확인","title":"T12",'
          '"note":"이걸 본다","ts":"2026-08-31T01:30:00+09:00"}',
      '{"kind":"item","id":"C-t12","at":"완료","said":"확인 — 문제 없음",'
          '"ts":"2026-08-31T01:39:40+09:00"}',
    ]);
    expect(out, isNot(contains(kLaw)));
  });

  group('🚨★★★두 규칙이 손을 넘기는 지점', () {
    // ⚠️`sortByTime` ALREADY neutralises a stamp that has not happened yet:
    // it inherits the entry before it, which is file order. That was written
    // for this very incident, so on the morning of 08-31 the board was
    // CORRECT — and the future-stamp rule was naming the line.
    //
    // ⛔The hole opens when the clock passes the invented time. 14:10 stops
    // being 「the future」 and becomes ordinary history: it sorts normally,
    // reorders the story, and the future rule looks straight past it. That
    // is why 유저 hit it TODAY and not that morning.
    final lines = [
      '{"kind":"check","id":"W","at":"실기 확인","title":"T","note":"본다",'
          '"ts":"2026-08-31T14:10:00+09:00"}',
      '{"kind":"item","id":"W","at":"완료","said":"확인",'
          '"ts":"2026-08-31T01:39:00+09:00"}',
    ];

    test('⛔before that moment the board is already right', () {
      // 14:10+09:00 is 05:10Z; 02:00Z is before it.
      File('${dir.path}/board.jsonl').writeAsStringSync(lines.join('\n'));
      expect(
        boardCheckComplaints(File('${dir.path}/board.jsonl'),
            now: DateTime.utc(2026, 8, 31, 2)),
        isNot(contains(kLaw)),
        reason: '⛔premise: nothing to fix yet — `sortByTime` is holding the '
            'story in file order, and complaining here would train the '
            'reader to ignore this check',
      );
    });

    test('🚨after it, this check has it — and never lets go', () {
      File('${dir.path}/board.jsonl').writeAsStringSync(lines.join('\n'));
      for (final when in [
        DateTime.utc(2026, 8, 31, 20),
        DateTime.utc(2027, 1, 1),
        DateTime.utc(2030, 1, 1),
      ]) {
        expect(
          boardCheckComplaints(File('${dir.path}/board.jsonl'), now: when),
          contains(kLaw),
          reason: '$when 에도 잡혀야 한다 — 이 검사는 시계를 안 본다',
        );
      }
    });
  });

  test('⛔a card that has finished is not this — it is off the board either '
      'way', () {
    final out = complaints([
      '{"kind":"item","id":"W","at":"착수 가능","title":"작업",'
          '"rest":"할 것","ts":"2026-08-30T00:10:00+09:00"}',
      '{"kind":"item","id":"W","at":"완료","said":"끝","ts":"2026-08-29T22:05:00+09:00"}',
      '{"id":"W","state":"archived","ts":"2026-08-30T23:10:00+09:00"}',
    ]);
    expect(
      out,
      isNot(contains(kLaw)),
      reason: '🧪two live cards looked like this and both were archived — '
          'a gate that complains about history is a gate nobody reads',
    );
  });

  test('⛔a stage word that is not a section cannot move anything', () {
    // 구현 · AI 판단 are stages, not places. Their order cannot put a card in
    // the wrong box, so they are not this complaint.
    final out = complaints([
      '{"kind":"item","id":"W","at":"실기 확인","title":"작업","note":"본다",'
          '"ts":"2026-08-31T01:00:00+09:00"}',
      '{"kind":"item","id":"W","at":"구현","pr":1234,"note":"고쳤다",'
          '"ts":"2026-08-30T00:00:00+09:00"}',
    ]);
    expect(out, isNot(contains(kLaw)));
  });

  test('⛔an ack silences it, like every other complaint', () {
    File('${dir.path}/.gate-ack').writeAsStringSync('C-t12 알고 있다\n');
    final out = complaints([
      '{"kind":"check","id":"C-t12","at":"실기 확인","title":"T12",'
          '"note":"본다","ts":"2026-08-31T14:10:00+09:00"}',
      '{"kind":"item","id":"C-t12","at":"완료","said":"확인",'
          '"ts":"2026-08-31T01:39:40+09:00"}',
    ]);
    expect(out, isNot(contains(kLaw)));
  });
}
