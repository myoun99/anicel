import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_check.dart';
import '../../tool/board_model.dart';

/// 🚨★★★THE GATE, DRIVEN AS A FUNCTION.
///
/// ⛔It used to be driven as a PROCESS — `dart run tool/board_check.dart` once
/// per case — and under the full affected run the contention alone made it
/// fail: 실측 2026-08-27, **nine red in a bulk run, 13/13 green alone**. A
/// test that goes red for reasons that have nothing to do with the subject is
/// a test people learn to re-run instead of read.
///
/// 🚨EVERY CASE IS A PAIR: a file that must complain and the smallest edit
/// that must silence it. A one-sided test proves the gate can shout, not that
/// it can tell the difference — and a gate that shouts at everything is the
/// failure mode this file exists to prevent, not the one it is testing for.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('board-check'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// ⚠️Stamped from the REAL clock, minutes ago — never a fixed date. A fixed
  /// one has to clear the gate's history cutoff, which pushed these fixtures
  /// into TOMORROW, and the future-stamp check then caught every one of them.
  /// 🧪That is the same mistake the check exists to catch, made in the test.
  // ⚠️A FIXED instant, not the clock: every fixture time is derived from it
  // and so is the gate's idea of 「now」, so a case means the same thing
  // whenever and wherever it runs.
  final base = DateTime.parse('2026-08-31T00:00:00Z');
  String at(String hhmm) {
    final parts = hhmm.split(':');
    return base
        .add(Duration(
          minutes: int.parse(parts[0]) * 6 + int.parse(parts[1]),
        ))
        .toIso8601String();
  }

  String complaintsFor(List<String> lines) {
    final file = File('${dir.path}/board.jsonl')
      ..writeAsStringSync(lines.map((l) => '$l\n').join());
    // ⚠️The line rules start at a constant that is AFTER the bogus stamps in
    // the real records (see kLinesSince). A fixture cannot be stamped there
    // without being in the future, which the future check would then catch —
    // so the test names its own line, minutes before its own fixtures.
    // 🚨THE TEST NAMES ITS OWN POLICY. Comparing fixtures against the gate's
    // hardcoded dates made the suite depend on what day the machine thinks
    // it is — green here, red on a Windows CI shard, with nothing about the
    // board changed. Both cutoffs and 「now」 are stated here instead.
    return boardCheckComplaints(
      file,
      since: base.toIso8601String(),
      linesSince: base.toIso8601String(),
      now: base.add(const Duration(hours: 2)),
    );
  }

  /// The smallest card that passes everything: a story with one 대분류.
  String card(String id, {String at_ = '남은 것', String rest = '아직 남았다'}) =>
      '{"kind":"item","id":"$id","at":"$at_","rest":"$rest",'
      '"ts":"${at('09:00')}","title":"$id","tags":["구조"]}';

  test('a clean board says nothing at all', () {
    expect(complaintsFor([card('A')]), isEmpty);
  });

  group('읽히지 않는 줄', () {
    test('a line the reader could not use is named by its number', () {
      final out = complaintsFor([card('A'), '{ this is not json']);
      expect(out, contains('깨졌습니다'));
      expect(out, contains('2'), reason: 'the line number is the whole point');
    });
  });

  group('어느 칸도 말하지 않는 카드', () {
    test('a story with entries but no 대분류 is filed nowhere on purpose', () {
      // ⚠️`작업 기록` is a 소분류: it is a real entry and it moves nothing, so
      // this card lands in 바로 가능 by default and claims to be startable.
      final out = complaintsFor([
        '{"kind":"item","id":"A","at":"작업 기록","note":"뭔가 했다",'
            '"ts":"${at('09:00')}"}',
      ]);
      expect(out, contains('어느 칸도 말하지 않는 카드'));
      expect(out, contains('A'));
    });

    test('⛔and one 대분류 anywhere in the story silences it', () {
      expect(
        complaintsFor([
          '{"kind":"item","id":"A","at":"남은 것","rest":"남음",'
              '"ts":"${at('09:00')}"}',
          '{"kind":"item","id":"A","at":"작업 기록","note":"그 뒤에 한 일",'
              '"ts":"${at('10:00')}"}',
        ]),
        isEmpty,
        reason: '소분류가 뒤에 쌓여도 칸은 마지막 대분류가 정한다',
      );
    });

    test('⛔a law is not a card and is never asked where it sits', () {
      expect(
        complaintsFor([
          card('A'),
          '{"kind":"law","id":"law-구조","tag":"구조","note":"이 영역의 법",'
              '"ts":"${at('09:00')}"}',
        ]),
        isEmpty,
      );
    });

    test('⛔nor is a question folded into another card', () {
      // 🚨THE REAL SHAPE, from Q-brush-param on 2026-08-31: an ANSWERED
      // question. Its own story then holds a 유저 대답 entry — a 소분류 — and
      // no 대분류 at all, so judged as a card it looks filed nowhere. It is
      // not a card: it is an entry inside the card it was folded into.
      //
      // ⛔The first version of this case used an UNANSWERED question, whose
      // own log is empty, so it was skipped before the folding rule was ever
      // consulted. 🧪The mutation proved it: removing `foldedInto == null`
      // killed nothing. A green that measures an empty room.
      expect(
        complaintsFor([
          card('A'),
          '{"kind":"decision","id":"A-Q1","title":"질문","where":"w","why":"y",'
              '"options":[{"key":"1","label":"ㄱ"},{"key":"2","label":"ㄴ"}],'
              '"ts":"${at('09:30')}"}',
          '{"kind":"decision","id":"A-Q1","answer":"1","answerNote":"이걸로",'
              '"ts":"${at('10:00')}"}',
        ]),
        isNot(contains('어느 칸도')),
      );
    });
  });

  group('모르는 항목 이름 · state 손대기', () {
    test('an invented stage name moves nothing, and says so', () {
      final out = complaintsFor([
        '{"kind":"item","id":"A","at":"보류중임","note":"x","ts":"${at('09:00')}"}',
      ]);
      expect(out, contains('모르는 항목 이름'));
      expect(out, contains('보류중임'));
    });

    test('⛔a name the model knows is silent', () {
      expect(complaintsFor([card('A', at_: '나중에', rest: '')]), isEmpty);
    });

    test('🚨writing `state` by hand is itself the defect now', () {
      final out = complaintsFor([
        '{"kind":"item","id":"A","at":"남은 것","rest":"남음","state":"queue",'
            '"ts":"${at('09:00')}"}',
      ]);
      expect(out, contains('state 를 손으로 쓴 줄'));
    });

    test('⛔except the two endings, which no stage word produces', () {
      expect(
        complaintsFor([
          card('A'),
          '{"kind":"item","id":"B","state":"archived","ts":"${at('09:00')}"}',
          '{"kind":"item","id":"C","state":"deleted","ts":"${at('09:00')}"}',
        ]),
        isEmpty,
      );
    });
  });

  group('착지했는데 실기 확인으로 안 갔다', () {
    test('a merge moves nothing, so a shipped card sits until I move it', () {
      final out = complaintsFor([
        '{"kind":"item","id":"A","at":"구현","pr":1234,"note":"고쳤다",'
            '"ts":"${at('09:00')}"}',
      ]);
      expect(out, contains('착지했는데'));
      expect(out, contains('A'));
    });

    test('⛔writing 실기 확인 silences it', () {
      expect(
        complaintsFor([
          '{"kind":"item","id":"A","at":"구현","pr":1234,"note":"고쳤다",'
              '"ts":"${at('09:00')}"}',
          '{"kind":"item","id":"A","at":"실기 확인","note":"기기에서 볼 것",'
              '"ts":"${at('10:00')}"}',
        ]),
        isEmpty,
      );
    });

    test('⛔and so does still owing something — the work is not done', () {
      expect(
        complaintsFor([
          '{"kind":"item","id":"A","at":"구현","pr":1234,"note":"절반 했다",'
              '"ts":"${at('09:00')}"}',
          '{"kind":"item","id":"A","at":"남은 것","rest":"나머지",'
              '"ts":"${at('10:00')}"}',
        ]),
        isEmpty,
      );
    });

    test('a card that only claims a PR and says nothing is named', () {
      final out = complaintsFor([
        '{"kind":"item","id":"A","pr":1234,"at":"실기 확인",'
            '"ts":"${at('09:00')}"}',
      ]);
      expect(out, contains('제목만 있고'));
    });

    test('a PR written only in prose is invisible to the board', () {
      final out = complaintsFor([
        '{"kind":"item","id":"A","at":"남은 것","rest":"남음",'
            '"note":"#1302 에서 고쳤다","ts":"${at('09:00')}"}',
      ]);
      expect(out, contains('본문에만'));
    });

    test('🚨a check written into `rest` files the card as startable work', () {
      final out = complaintsFor([
        '{"kind":"item","id":"A","at":"남은 것","rest":"태블릿에서 눌러본다",'
            '"ts":"${at('09:00')}"}',
      ]);
      expect(out, contains('확인 방법이 들어 있는'));
    });
  });

  group('답할 수 없는 질문', () {
    String question(String body) =>
        '{"kind":"decision","id":"Q-a","ts":"${at('09:00')}",$body}';

    test('no options means the radios cannot be drawn', () {
      final out = complaintsFor([
        question('"title":"질문","where":"w","why":"y","of":"A"'),
        card('A'),
      ]);
      expect(out, contains('답할 수 없는'));
    });

    test('options with no where/why leave nothing to decide between', () {
      final out = complaintsFor([
        question('"title":"질문","of":"A","options":'
            '[{"key":"1","label":"ㄱ"},{"key":"2","label":"ㄴ"}]'),
        card('A'),
      ]);
      expect(out, contains('내용이 안 보이는'));
    });

    test('🚨a recommend that names no option renders as nothing at all', () {
      final out = complaintsFor([
        question('"title":"질문","where":"w","why":"y","of":"A",'
            '"recommend":"첫 번째가 낫습니다","options":'
            '[{"key":"1","label":"ㄱ"},{"key":"2","label":"ㄴ"}]'),
        card('A'),
      ]);
      expect(out, contains('추천이 안 보이는'));
    });

    test('a question belonging to nothing has nowhere to carry an answer', () {
      final out = complaintsFor([
        question('"title":"질문","where":"w","why":"y","options":'
            '[{"key":"1","label":"ㄱ"},{"key":"2","label":"ㄴ"}]'),
      ]);
      expect(out, contains('어느 카드의 질문인지'));
    });

    test('🚨★★★an unanswered question whose card is NOT in 답할 것', () {
      // 🧪THE REAL SHAPE, taken from H25 on 2026-08-31: I raised the question
      // and wrote 대기중 on the card ONE MINUTE later, so the card sat in
      // 대화 중 holding a question nobody was being asked.
      //
      // ⚠️A question alone does NOT trigger this — folding it in makes it the
      // newest 대분류, which IS 답할 것. It takes a later 대분류 to bury it,
      // and that is exactly what the first fixture here got wrong.
      final out = complaintsFor([
        card('A'),
        question('"title":"질문","where":"w","why":"y","of":"A","options":'
            '[{"key":"1","label":"ㄱ"},{"key":"2","label":"ㄴ"}]'),
        '{"kind":"item","id":"A","at":"나중에","note":"나중에 하기로",'
            '"ts":"${at('11:00')}"}',
      ]);
      expect(out, contains('답할 것에 없는'));
      expect(out, contains('A'));
    });

    // 🚨★★★THE GATE HAS ONE CLOCK, AND THE TEST HANDS IT OVER.
    //
    // ⛔`_answersNobodyRead` called `DateTime.now()` directly, so every
    // fixture here aged against the REAL day while the rest of the gate aged
    // against `base`. That is a time BOMB rather than a flake: it passed for
    // as long as `base` was today, and on 2026-09-01 it went red on CI, on a
    // PR that had not touched the board at all.
    //
    // ⚠️This case exists so the next such line cannot hide. It runs the
    // whole gate against a board stamped a WEEK before its `now` — if any
    // check reaches for the wall clock again, the fixture is minutes old by
    // that clock and the complaint it should raise goes missing.
    test('🚨every check ages against the clock it was HANDED', () {
      final old = DateTime.parse('2026-08-24T00:00:00Z');
      final file = File('${dir.path}/aged.jsonl')
        ..writeAsStringSync(
          [
            '{"kind":"item","id":"A","title":"t","at":"분류 전",'
                '"note":"n","ts":"${old.toIso8601String()}"}',
          ].map((l) => '$l\n').join(),
        );

      expect(
        boardCheckComplaints(
          file,
          since: old.toIso8601String(),
          linesSince: old.toIso8601String(),
          now: old.add(const Duration(minutes: 5)),
        ),
        isNot(contains('분류 전에 하루 넘게')),
        reason:
            'five minutes old by the clock it was given — a check that '
            'asks the machine what day it is would call this a week stale',
      );
      expect(
        boardCheckComplaints(
          file,
          since: old.toIso8601String(),
          linesSince: old.toIso8601String(),
          now: old.add(const Duration(days: 7)),
        ),
        contains('분류 전에 하루 넘게'),
        reason:
            '★and the premise: the SAME board does raise it once the handed '
            'clock has moved on, so the case above is not passing by '
            'measuring nothing',
      );
    });

    test('⛔a question folded in with nothing after it IS 답할 것', () {
      expect(
        complaintsFor([
          card('A'),
          question('"title":"질문","where":"w","why":"y","of":"A","options":'
              '[{"key":"1","label":"ㄱ"},{"key":"2","label":"ㄴ"}]'),
        ]),
        isEmpty,
        reason: '질문이 마지막 대분류면 카드는 이미 답할 것에 있다',
      );
    });

    test('⛔and the card sitting in 답할 것 silences it', () {
      expect(
        complaintsFor([
          card('A', at_: '나중에', rest: ''),
          question('"title":"질문","where":"w","why":"y","of":"A","options":'
              '[{"key":"1","label":"ㄱ"},{"key":"2","label":"ㄴ"}]'),
          '{"kind":"item","id":"A","at":"답할 것","note":"Q-a 가 미답",'
              '"ts":"${at('11:00')}"}',
        ]),
        isEmpty,
        reason: '질문과 답할 것은 한 칸의 두 이름이다 — 단어가 아니라 칸으로 본다',
      );
    });
  });

  group('죽은 ack', () {
    test('an ack for a landing that now HAS a card is a line to delete', () {
      File('${dir.path}/.gate-ack').writeAsStringSync('1234 카드 없이 지나감\n');
      final out = complaintsFor([
        '{"kind":"item","id":"A","at":"실기 확인","pr":1234,"note":"고쳤다",'
            '"ts":"${at('09:00')}"}',
      ]);
      expect(out, contains('카드가 생긴 착지의 ack'));
    });

    test('⛔an ack silences every complaint about that card, not just one', () {
      File('${dir.path}/.gate-ack').writeAsStringSync('A 손대지 않기로 했다\n');
      expect(
        complaintsFor([
          '{"kind":"item","id":"A","at":"보류중임","state":"queue","pr":1234,'
              '"ts":"${at('09:00')}"}',
        ]),
        isEmpty,
      );
    });
  });

  group('역사는 다시 심판하지 않는다', () {
    test('🚨a card written before the model changed is left alone', () {
      // ⛔Without this the gate opened with THIRTY complaints about history —
      // and every one was correct under the model it was written for. A gate
      // that starts by shouting at the past is one people scroll past.
      expect(
        complaintsFor([
          '{"kind":"item","id":"A","at":"작업 기록","note":"옛날 카드",'
              '"ts":"2026-08-20T09:00:00+09:00"}',
        ]),
        isEmpty,
      );
    });
  });

  group('아직 오지 않은 시각', () {
    test('🚨a stamp in the future reorders somebody else\'s work', () {
      // 🧪The real one: I stamped 39 records with times that had not happened,
      // and 유저 ticked a card that then would not leave, because my future
      // 실기 확인 sorted AFTER their 완료 and stayed the last 대분류.
      // ⚠️Future relative to the gate's  (base + 2h), not the wall clock.
      final soon = base.add(const Duration(hours: 9));
      final out = complaintsFor([
        '{"kind":"item","id":"A","at":"남은 것","rest":"남음",'
            '"ts":"${soon.toIso8601String()}"}',
      ]);
      expect(out, contains('아직 오지 않은 시각'));
    });

    test('⛔a stamp that has happened is silent', () {
      expect(complaintsFor([card('A')]), isEmpty);
    });

    test('⚠️and it is asked even of lines older than the cutoff', () {
      // Gating it behind the history rule would have hidden every stamp made
      // before the rule existed — including the ones that caused it.
      final out = complaintsFor([
        '{"kind":"item","id":"A","at":"남은 것","rest":"남음",'
            '"ts":"2027-01-01T09:00:00+09:00"}',
      ]);
      expect(out, contains('아직 오지 않은 시각'));
    });
  });

  group('실기 확인이 여럿이면 전부 ok일 때만', () {
    String check(String note, String hhmm) =>
        '{"kind":"item","id":"A","at":"실기 확인","note":"$note",'
        '"ts":"${at(hhmm)}"}';
    String tick(String hhmm) =>
        '{"kind":"item","id":"A","at":"확인 완료","said":"확인 — 문제 없음",'
        '"ref":"${at(hhmm)}","ts":"${at('11:00')}"}';

    test('🚨★★★one tick does not take the other two off the board', () {
      // ⛔It used to: one 완료 ended the card whatever else it held, so
      // ticking the first of three took the other two with it — and nothing
      // brings them back, because nothing shows them.
      final out = complaintsFor([
        check('첫째', '09:00'),
        check('둘째', '09:01'),
        check('셋째', '09:02'),
        tick('09:00'),
      ]);
      expect(out, isEmpty, reason: '아직 둘이 남았으므로 카드는 실기 확인에 있다');
    });

    test('⛔and a 완료 with no ref still ends the whole card', () {
      // Every 완료 written before per-check ticks existed meant exactly that.
      expect(
        complaintsFor([
          check('첫째', '09:00'),
          check('둘째', '09:01'),
          '{"kind":"item","id":"A","at":"완료","said":"확인 — 문제 없음",'
              '"ts":"${at('11:00')}"}',
        ]),
        isEmpty,
      );
    });
  });

  group('체크는 호스트와 함께 죽지 않는다', () {
    test('🚨★★★a check whose host has ended still stands on its own', () {
      // 🧪TEN of them were gone this way: the 4GB save check rode
      // `stop-gate-was-dead` into the archive, four buffer checks rode
      // `scroll-the-buffer-on-a-pan`, two rode a deleted round. Still
      // unticked, and on no list at all — nothing could bring them back.
      // 유저 saw it from the other side: 「실기 확인에 등장 안 하는 카드가
      // 있어」. It is the law they had just stated about ticks: something
      // ELSE finishing is not this check passing.
      // ⛔ASKED OF THE MODEL, not of the gate. A gate-level assertion passes
      // either way — a folded check raises no complaint and neither does a
      // clean standing one — which is the empty room this suite already
      // caught itself measuring once.
      final file = File('${dir.path}/board.jsonl')
        ..writeAsStringSync(
          '{"kind":"item","id":"HOST","at":"완료","pr":1234,"note":"끝났다",'
          '"ts":"${at('09:00')}"}\n'
          '{"kind":"check","id":"C-x","under":1234,"title":"기기에서 볼 것",'
          '"how":"눌러 본다","ts":"${at('09:30')}"}\n',
        );
      final check = readBoard(file, now: base.add(const Duration(hours: 2))).firstWhere((c) => c.id == 'C-x');
      expect(check.foldedInto, isNull, reason: '호스트가 끝났으니 접히지 않는다');
      expect(check.state, 'hands', reason: '그리고 실기 확인 칸에 선다');
    });

    test('⛔but it DOES fold when the host is still on the board', () {
      final file = File('${dir.path}/board.jsonl')
        ..writeAsStringSync(
          '{"kind":"item","id":"HOST","at":"실기 확인","pr":1234,"note":"산다",'
          '"ts":"${at('09:00')}"}\n'
          '{"kind":"check","id":"C-x","under":1234,"title":"기기에서 볼 것",'
          '"how":"눌러 본다","ts":"${at('09:30')}"}\n',
        );
      expect(readBoard(file, now: base.add(const Duration(hours: 2))).firstWhere((c) => c.id == 'C-x').foldedInto, 'HOST');
    });
  });
}
