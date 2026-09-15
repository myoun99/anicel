import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_check.dart';
import '../../tool/board_model.dart';
import '../../tool/board_server.dart';

/// 🚨★★★A TICK KEEPS THE KIND OF THE CARD IT TICKS (2026-09-15).
///
/// The tick route wrote `kind: item` on every card it ticked. On a card born
/// `kind: check` that one word turned it into an item — and a check's
/// 「실기 확인」 entry is not a line in the file, it is the entry the model
/// folds in FOR a check (`foldChecksIntoCards`). So the very tick that
/// cleared the check removed the entry its own `ref` pointed at. Six finished
/// cards kept the board gate saying 「가리키는 곳이 없는 값」 at the end of
/// every turn, in every session, with nothing on screen to show why.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('board-tick-kind'));
  tearDown(() => dir.deleteSync(recursive: true));

  File boardOf(List<String> lines) => File('${dir.path}/board.jsonl')
    ..writeAsStringSync(lines.map((l) => '$l\n').join());

  var clock = 0;
  String now() => '2026-08-31T02:00:0${clock++}Z';

  List<String> tick(List<String> lines, String id, {String note = ''}) {
    final card = readBoard(boardOf(lines)).firstWhere((c) => c.id == id);
    final ref = checksWaiting(card).first;
    return [
      ...lines,
      for (final r
          in tickRecords(card: card, id: id, ref: ref, note: note, now: now))
        jsonEncode(r),
    ];
  }

  const bornACheck = '{"kind":"check","id":"C","title":"기기에서 본다",'
      '"how":"열고 저장하고 다시 연다","ts":"2026-08-31T01:00:00Z"}';

  test('⛔fixture premise: a check card waits on the entry the model folds in',
      () {
    final card = readBoard(boardOf([bornACheck])).single;
    expect(card.kind, 'check');
    expect(checksWaiting(card), ['2026-08-31T01:00:00Z']);
    expect(card.state, 'hands');
  });

  test('🚨a quiet tick on a check card keeps it a check, and its ref resolves',
      () {
    final after = boardOf(tick([bornACheck], 'C'));
    final card = readBoard(after).single;
    expect(card.kind, 'check', reason: 'the tick is about the check, not a '
        'reason to become something else');
    expect(card.state, 'archived', reason: 'the last check cleared ends it');
    expect(
      boardCheckComplaints(after, now: DateTime.utc(2026, 9, 1)),
      isNot(contains('가리키는 곳이 없는 값')),
      reason: 'the ref names the folded 실기 확인 entry, which only exists '
          'while the card is a check',
    );
  });

  test('🚨a tick with a memo keeps the kind on BOTH of its lines', () {
    final lines = tick([bornACheck], 'C', note: '저장이 두 번 떴다');
    final written = lines.skip(1).map(jsonDecode).cast<Map>().toList();
    expect(written, hasLength(2));
    expect(written.map((r) => r['kind']), everyElement('check'));
    expect(
      boardCheckComplaints(boardOf(lines), now: DateTime.utc(2026, 9, 1)),
      isNot(contains('가리키는 곳이 없는 값')),
    );
  });

  test('⛔an item card stays an item — the kind is the card’s, whatever it is',
      () {
    const bornAnItem = '{"kind":"item","id":"W","title":"작업","at":"실기 확인",'
        '"note":"이걸 본다","ts":"2026-08-31T01:00:00Z"}';
    final lines = tick([bornAnItem], 'W');
    expect((jsonDecode(lines.last) as Map<String, dynamic>)['kind'], 'item');
    expect(readBoard(boardOf(lines)).single.state, 'archived');
  });
}
