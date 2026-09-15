import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_model.dart';
import '../../tool/board_server.dart';

/// 🚨★★★THE FIRST TEST THAT LOOKS AT WHAT THE BOARD DRAWS.
///
/// ⛔Every board bug on 2026-08-31 was in the renderer and none of them could
/// be caught: a question drawn as an ordinary row, a hands-on check with no
/// memo box of its own, a memo box still holding words it no longer edits.
/// **The model was right every time.** `test/tool/` covered the model and had
/// no way to see the screen, so all three reached 유저 — who found them by
/// opening the page and looking.
///
/// ⚠️This asserts on MARKUP, which is usually a smell. It is the right call
/// here: the defects were never in the data, they were in whether a control
/// appeared at all. A test that reads the cards back would have passed on all
/// three.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('board-draw'));
  tearDown(() => dir.deleteSync(recursive: true));

  String page(List<String> lines) {
    final f = File('${dir.path}/board.jsonl')
      ..writeAsStringSync(lines.map((l) => '$l\n').join());
    return renderBoard(readBoard(f));
  }

  group('질문은 고를 것이 있어야 질문이다', () {
    // 유저 2026-08-31: 「질문으로 옮김이라는 내용만 있는 질문항목이야.
    // 질문의 내용이없어.」 — six of them, written as `item` because `kind`
    // is a word the writer has to remember.
    const origin = '{"kind":"item","id":"W","at":"남은 것","title":"작업",'
        '"rest":"할 것","ts":"2026-08-31T01:00:00Z"}';
    String question(String kind) =>
        '{"kind":"$kind","id":"W-Q1","at":"질문","title":"이렇게 할까",'
        '"where":"거기","why":"막혔다",'
        '"options":[{"key":"a","label":"A안"},{"key":"b","label":"B안"}],'
        '"recommend":"a","ts":"2026-08-31T02:00:00Z"}';

    for (final kind in ['item', 'decision']) {
      test('🚨a $kind card with options draws RADIOS, not a row', () {
        final html = page([origin, question(kind)]);
        expect(
          html,
          contains('name="ans-W-Q1"'),
          reason: '⛔without the radio there is nothing to answer with — the '
              'card was on the board, in the right section, right title',
        );
        expect(html, contains('value="a"'));
        expect(html, contains('value="b"'));
        expect(html, contains('A안'));
        expect(
          html,
          contains('value="other"'),
          reason: 'the free answer is part of the form, not an afterthought — '
              '25 answers in the live file name no option at all',
        );
      });
    }
  });

  group('실기 확인은 항목마다 자기 메모란을 갖는다', () {
    // 유저 2026-08-31: 「실기확인 항목마다 메모란도 존재해야하지않을까?
    // 원래 실기확인은 그렇잖아」 — a card can hold several checks and the
    // card-level box could not say WHICH one a note was about.
    test('🚨two checks draw two boxes and two buttons', () {
      final html = page([
        '{"kind":"item","id":"W","at":"실기 확인","title":"작업",'
            '"note":"첫째를 본다","ts":"2026-08-31T01:00:00Z"}',
        '{"kind":"item","id":"W","at":"실기 확인","note":"둘째를 본다",'
            '"ts":"2026-08-31T02:00:00Z"}',
      ]);
      // 🚨THE BOX ITSELF, not its wrapper. 🧪MUTATION SURVIVOR: deleting
      // the textarea and keeping `<div class="tick">` left this test green,
      // and a box is the entire thing 유저 asked for — 「실기확인 항목마다
      // **메모란**도 존재해야하지않을까」. Counting the container counted
      // the shape of my implementation instead of the thing on screen.
      // ⚠️By the tick box's OWN placeholder. `rows="2"` alone counts three
      // here: the page also carries the general feedback box, which is
      // always there. A count that includes furniture is not a count.
      expect(
        RegExp('placeholder="문제가 있으면 적어 주세요 — 비워 두면 문제 없음')
            .allMatches(html),
        hasLength(2),
      );
      expect(RegExp('class="tick"').allMatches(html), hasLength(2));
      expect(RegExp(r'tick\(event').allMatches(html), hasLength(2));
      expect(
        RegExp('2026-08-31T01:00:00Z').allMatches(html),
        isNotEmpty,
        reason: '⛔each button carries the ts of the check it clears — that '
            'ref is the whole difference between two identical 「확인」 words',
      );
    });

    test('⛔a check already ticked draws no box', () {
      final html = page([
        '{"kind":"item","id":"W","at":"실기 확인","title":"작업",'
            '"note":"본다","ts":"2026-08-31T01:00:00Z"}',
        '{"kind":"item","id":"W","at":"확인 완료","ref":"2026-08-31T01:00:00Z",'
            '"said":"확인 — 문제 없음","ts":"2026-08-31T02:00:00Z"}',
      ]);
      expect(
        html,
        isNot(contains('class="tick"')),
        reason: '🧪the one-line version of the tick routed the card correctly '
            'and LEFT THE BUTTON ON SCREEN; only a probe caught it',
      );
    });
  });

  group('메모란은 비어 있다 — 그 버튼이 하는 일이 「추가」라서', () {
    // 유저 2026-08-31: 「메모입력란에 과거에 입력한 텍스트가 그대로
    // 남아있으니까 입력한 메모를 수정하는건가 처럼 느껴져. 그러니 메모란
    // 비어있도록」.
    const inbox = '{"kind":"item","id":"W","at":"유저","title":"원래 적은 말",'
        '"said":"원래 적은 말","ts":"2026-08-31T01:00:00Z"}';

    test('🚨the box holds nothing', () {
      final html = page([inbox]);
      expect(
        html,
        contains('<textarea rows="4" placeholder='),
        reason: 'placeholder only — a prefilled box describes an action this '
            'control no longer takes',
      );
      expect(
        RegExp('<textarea rows="4"[^>]*>원래').hasMatch(html),
        isFalse,
        reason: '⛔and re-submitting it wrote nothing at all, because '
            'identical text dedupes on (text, ref)',
      );
    });

    test('⛔but the words are still ON the card, in its story', () {
      final html = page([inbox]);
      expect(
        html,
        contains('원래 적은 말'),
        reason: 'emptying the BOX must not be emptying the card — the story '
            'is what the box is adding to',
      );
    });
  });

  test('⛔법은 카드로 안 그려진다 — 태그가 같은 카드에 붙는다', () {
    // 🧪Measured before writing this: the model reports a law in `open`, and
    // I nearly filed that as 「laws sit in 착수 가능 pretending to be work」.
    // The renderer pulls them into `_laws` first. The MODEL's state is
    // meaningless for a law, and only the page could say so.
    final html = page([
      '{"kind":"item","id":"W","at":"남은 것","title":"작업","tags":["보드"],'
          '"rest":"할 것","ts":"2026-08-31T01:00:00Z"}',
      '{"kind":"law","id":"law-보드","tag":"보드","care":"손대기 전에 이걸 읽어라",'
          '"ts":"2026-08-31T02:00:00Z"}',
    ]);
    expect(html, isNot(contains('id="c-law-보드"')));
    expect(
      html,
      contains('손대기 전에 이걸 읽어라'),
      reason: '🚨the law still has to REACH the card that carries its tag — '
          'gone from the page entirely would be the opposite bug',
    );
  });

  group('칸은 이야기가 정한다 — 옛 답이나 예전 PR 이 카드를 숨기지 않는다', () {
    // 🚨★★★2026-09-15: a session wrote a roadmap and then read the page, and
    // four work cards were on NO section at all — F-28, R27-rest and F-18
    // carried an `answer` an old check submit had left behind, I-8 an old PR
    // claim. Their stories said 남은 것 and 나중에; the renderer asked two
    // other questions and drew them nowhere, which looks exactly like a card
    // that ended.
    test('🚨a work card carrying an old check answer is drawn', () {
      final html = page([
        '{"kind":"item","id":"W","title":"작업","answer":"ok",'
            '"ts":"2026-08-31T01:00:00Z"}',
        '{"kind":"item","id":"W","at":"남은 것","note":"아직 남았다",'
            '"ts":"2026-08-31T02:00:00Z"}',
      ]);
      expect(
        html,
        contains('id="c-W"'),
        reason: 'an `answer` on a card that asks nothing is not an ending — '
            'the model already says so (`endedCards`), and the page has to '
            'ask the same question',
      );
    });

    test('🚨a card that once claimed a PR and was put off is drawn', () {
      final html = page([
        '{"kind":"item","id":"W","title":"작업","pr":1234,"at":"실기 확인",'
            '"note":"착지","ts":"2026-08-31T01:00:00Z"}',
        '{"kind":"item","id":"W","at":"나중에","note":"상담이 먼저",'
            '"ts":"2026-08-31T02:00:00Z"}',
      ]);
      expect(
        html,
        contains('id="c-W"'),
        reason: 'a merge does not move a card and does not hide one either — '
            'the newest 대분류 is 나중에, so that is where it is drawn',
      );
    });
  });
}
