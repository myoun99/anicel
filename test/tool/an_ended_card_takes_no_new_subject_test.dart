import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_model.dart';
import '../../tool/board_say.dart';

/// 🚨★★★A CARD THAT HAS ENDED DOES NOT TAKE A NEW SUBJECT.
///
/// ⛔I did this twice in one hour on 2026-09-01, and both times the words
/// landed where nobody could see them:
///
/// · `board-exe-goes-stale` had finished at 03:20 with an explicit
///   `state:"archived"`, which the story cannot overturn. Three lines about
///   #1434 went onto an invisible card.
/// · `memory-usage-panel-Q1` was a question from 08-28 that 유저 **had already
///   answered**. My new question merged onto an answered card and never
///   reached 답할 것 — 유저 found it: 「메모리는 질문으로 안올라와있어」.
///   ⚠️Worse, the answer had been there the whole time, so the question I was
///   asking had been decided a week earlier.
///
/// ⚠️Amending an ended card is legitimate — a correction, a pointer to where
/// the subject went. `정정` says so out loud, and saying it is the whole
/// difference between 「I know this is finished」 and 「I did not look」.
void main() {
  Map<String, String> endedFrom(List<String> lines) {
    final d = Directory.systemTemp.createTempSync('ended');
    addTearDown(() => d.deleteSync(recursive: true));
    File('${d.path}/board.jsonl').writeAsStringSync(lines.join('\n'));
    return endedCards(readBoard(File('${d.path}/board.jsonl')));
  }

  group('무엇이 끝난 카드인가', () {
    test('🚨완료로 닫힌 카드', () {
      final ended = endedFrom([
        '{"kind":"item","id":"W","at":"완료","said":"끝","ts":"2026-08-31T01:00:00Z"}',
      ]);
      expect(ended['W'], '완료');
    });

    test('🚨★★★이미 답이 나온 질문 — archived 가 아니어도 끝난 것이다', () {
      // ⛔THE ONE THAT COST 유저 A WEEK. It is not archived by state; writing a
      // NEW question onto it shows the OLD answer and the new words never
      // become a question at all.
      final ended = endedFrom([
        '{"kind":"item","id":"W","at":"남은 것","title":"작업","rest":"할 것",'
            '"ts":"2026-08-31T01:00:00Z"}',
        '{"kind":"decision","id":"W-Q1","at":"질문","title":"물음","where":"거기",'
            '"why":"막혔다","options":[{"key":"1","label":"A"},{"key":"2","label":"B"}],'
            '"recommend":"1","ts":"2026-08-31T02:00:00Z"}',
        '{"kind":"decision","id":"W-Q1","answer":"1","answerNote":"이걸로",'
            '"ts":"2026-08-31T03:00:00Z"}',
      ]);
      expect(ended['W-Q1'], contains('답'));
    });

    test('⛔★★★질문이 아닌 카드의 `answer` 는 끝이 아니다', () {
      // 🚨MEASURED WITHIN THE HOUR OF SHIPPING THIS GUARD. `R27-rest` is
      // ordinary work whose old `/submit` left `answer:"ok"` on it, and the
      // first version read that as 「answered question」 — refusing to let me
      // record findings on a live card that 유저 had just given new work.
      // ⛔An `answer` field is not a question; `cardAsks` is.
      final ended = endedFrom([
        '{"kind":"item","id":"W","at":"남은 것","title":"작업","rest":"할 것",'
            '"ts":"2026-08-31T01:00:00Z"}',
        '{"kind":"item","id":"W","answer":"ok","ts":"2026-08-31T02:00:00Z"}',
      ]);
      expect(ended.containsKey('W'), isFalse);
    });

    test('⛔★★★답을 받고 일감으로 이어진 카드는 끝난 것이 아니다', () {
      // 🚨MEASURED 2026-09-10 ON `F-34`. A card can raise a question, get the
      // answer, and carry on as work — the options stay on it for ever, so
      // `cardAsks` keeps saying yes and the guard was refusing every record
      // about that work, INCLUDING the one saying the code had landed. The
      // card sat in 착수 가능 with no way to say it was done.
      // ⚠️The difference from `W-Q1` above is one thing only: a 대분류 arrived
      // AFTER the answer, so the board draws this as work rather than as a
      // question waiting to be answered.
      final ended = endedFrom([
        '{"kind":"item","id":"W","at":"질문","title":"물음","where":"거기",'
            '"why":"막혔다","options":[{"key":"1","label":"A"},{"key":"2","label":"B"}],'
            '"recommend":"1","ts":"2026-08-31T01:00:00Z"}',
        '{"kind":"item","id":"W","answer":"1","ts":"2026-08-31T02:00:00Z"}',
        '{"kind":"item","id":"W","at":"남은 것","rest":"답대로 만든다",'
            '"ts":"2026-08-31T03:00:00Z"}',
      ]);
      expect(
        ended.containsKey('W'),
        isFalse,
        reason: '답 뒤에 대분류가 왔으면 그 카드는 일감이다',
      );
    });

    test('⛔살아 있는 카드는 끝난 것이 아니다', () {
      final ended = endedFrom([
        '{"kind":"item","id":"W","at":"남은 것","title":"작업","rest":"할 것",'
            '"ts":"2026-08-31T01:00:00Z"}',
      ]);
      expect(ended.containsKey('W'), isFalse);
    });
  });

  group('거절', () {
    const ended = {'W': '완료'};

    test('🚨새 주제는 거절되고, 카드가 끝났다는 것과 나갈 길을 말한다', () {
      final why = endedCardRefusal(
        {'kind': 'item', 'id': 'W', 'at': '남은 것', 'note': '새 주제'}, 1, ended);
      expect(why, isNotNull);
      expect(why, contains('W'));
      expect(why, contains('완료'));
      expect(
        why,
        contains('정정'),
        reason: '⛔the refusal must carry the way out — a rule you have to '
            'remember somewhere else is the thing that keeps failing',
      );
    });

    test('🚨`정정` 은 통과한다 — 끝난 카드를 고치는 것은 정당하다', () {
      expect(
        endedCardRefusal({'id': 'W', 'at': '정정', 'note': '고침'}, 1, ended),
        isNull,
      );
    });

    test('⛔살아 있는 카드는 그냥 통과', () {
      expect(
        endedCardRefusal({'id': 'X', 'at': '남은 것'}, 1, ended),
        isNull,
      );
    });
  });

  test('🚨★★★쓰기 전에 막는다 — 한 줄이라도 나쁘면 아무것도 안 나간다', () {
    final r = boardSayAppend(
      [
        '{"kind":"item","id":"A","at":"남은 것","title":"좋은 줄"}',
        '{"kind":"item","id":"W","at":"남은 것","note":"끝난 카드에 새 주제"}',
      ],
      DateTime.utc(2026, 9, 1),
      ended: {'W': '완료'},
    );
    expect(r.refusal, contains('W'));
    expect(
      r.bytes,
      isNull,
      reason: 'the good line must not land either — an append-only file '
          'cannot take half a write back',
    );
  });

  test('⛔ended 를 안 넘기면 예전과 똑같이 동작한다', () {
    // ⚠️The default is empty, so every caller that does not know about this
    // keeps working — the guard is added, not swapped in.
    final r = boardSayAppend(
      ['{"kind":"item","id":"W","at":"남은 것","title":"작업"}'],
      DateTime.utc(2026, 9, 1),
    );
    expect(r.refusal, isNull);
    expect(r.bytes, isNotNull);
  });
}
