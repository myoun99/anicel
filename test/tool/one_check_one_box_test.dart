import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_model.dart';
import '../../tool/board_server.dart';

/// 🚨★★★ONE CHECK, ONE BOX — and `send()` reads the first textarea in the
/// card, which is why two of them was not a tidiness problem.
///
/// ⛔A `check` card carried a memo box of its own under the story, with its
/// own wording (「비워 두면 OK」) and its own button (제출). When every 실기
/// 확인 entry grew a box (#1427) that made TWO boxes asking one question, and
/// `send()` does `c.querySelector('textarea')` — THE FIRST ONE.
///
/// 🧪So typing 「73프레임이 하얗다」 into the lower box and pressing 제출 read
/// the EMPTY upper box, decided the tick was clean, and wrote 「확인 — 문제
/// 없음」. The words were gone and the card closed as fine — precisely the
/// failure #1427 existed to end, reintroduced by #1427.
///
/// ⚠️Nothing is stranded: measured on the live board, all 57 check cards
/// carried at least one per-entry 확인 (55 one, 2 two).
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('one-box'));
  tearDown(() => dir.deleteSync(recursive: true));

  String page(List<String> lines) {
    final f = File('${dir.path}/board.jsonl')
      ..writeAsStringSync(lines.map((l) => '$l\n').join());
    return renderBoard(readBoard(f));
  }

  String panelOf(String html, String id) {
    final start = html.indexOf('id="c-$id"');
    expect(start, greaterThan(-1), reason: '⛔premise: the card is drawn');
    final next = html.indexOf('<details class="p ', start + 1);
    return html.substring(start, next < 0 ? html.length : next);
  }

  const check = '{"kind":"check","id":"C-x","at":"실기 확인","title":"T",'
      '"how":"이렇게 본다","note":"본다","ts":"2026-08-31T01:00:00Z"}';

  test('🚨a check card has exactly ONE memo box, and it is the check\'s', () {
    final panel = panelOf(page([check]), 'C-x');
    expect(
      RegExp('<textarea').allMatches(panel),
      hasLength(1),
      reason: '⛔two boxes meant the one you typed in was not the one read',
    );
    expect(
      panel,
      contains('비워 두면 문제 없음'),
      reason: 'the surviving box is the per-check one — it carries the ref of '
          'the check it clears',
    );
    expect(panel, isNot(contains('비워 두면 OK')));
  });

  test('🚨the box that stays is the one the button reads', () {
    // `send()`/`tick()` both take the FIRST textarea they find; with one box
    // there is no gap between 「where I typed」 and 「what was read」.
    final panel = panelOf(page([check]), 'C-x');
    final box = panel.indexOf('<textarea');
    final button = panel.indexOf('tick(event');
    expect(box, greaterThan(-1));
    expect(button, greaterThan(box), reason: 'the button belongs to that box');
    expect(
      panel,
      isNot(contains('onclick="send(')),
      reason: '⛔the card-level 제출 is gone — one question, one control. '
          '⚠️`onclick=`, not the bare name: the page carries the `send` '
          'FUNCTION for decision cards, and matching that would pass on a '
          'panel that still had the button',
    );
  });

  test('⛔two checks still get two boxes — this removed a duplicate, not the '
      'feature', () {
    final panel = panelOf(
      page([
        check,
        '{"kind":"check","id":"C-x","at":"실기 확인","note":"둘째도 본다",'
            '"ts":"2026-08-31T02:00:00Z"}',
      ]),
      'C-x',
    );
    expect(RegExp('<textarea').allMatches(panel), hasLength(2));
    expect(RegExp(r'tick\(event').allMatches(panel), hasLength(2));
  });

  test('🚨a screenshot pasted in a per-check box can find its CARD', () {
    // ⛔The paste handler walked `closest('details')`, and an ENTRY is a
    // `<details class="lg">` with no id — so a shot pasted into a per-check
    // box posted an empty id and went nowhere. Cards are the ones named
    // `c-<id>`; the handler asks for that now.
    final html = page([check]);
    expect(html, contains(r"""closest('details[id^="c-"]')"""));
    expect(
      html,
      isNot(contains("ta.closest('details');")),
      reason: 'the loose walk is gone, not shadowed',
    );
  });

  test('⛔an item card in 실기 확인 is unchanged — it never had two', () {
    final panel = panelOf(
      page([
        '{"kind":"item","id":"W","at":"실기 확인","title":"작업","note":"본다",'
            '"ts":"2026-08-31T01:00:00Z"}',
      ]),
      'W',
    );
    expect(RegExp('<textarea').allMatches(panel), hasLength(1));
    expect(panel, contains('tick(event'));
  });
}
