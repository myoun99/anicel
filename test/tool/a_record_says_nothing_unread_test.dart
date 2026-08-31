import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_check.dart';
import '../../tool/board_model.dart';

/// 🚨★★★THE BOARD MUST NOT SILENTLY DROP WHAT IT WAS TOLD.
///
/// 유저 2026-08-31: 「**결함들 다 구조적으로 해결해줘. 근본적인부분에서**」.
///
/// ⛔Every board defect this project has had is one shape — **a word the
/// writer had to remember**, spelled slightly wrong, silently doing nothing:
/// · `kind` forgotten on six questions ⇒ they drew as ordinary rows with the
///   question missing. On the board, right section, right title.
/// · a PR written into the note body instead of `pr` ⇒ 「카드 없음」.
/// · `item` + `ask` ⇒ the card does not appear at all.
/// · `state:"done"` ⇒ 77 cards fell into 착수 가능 (2026-08-30).
/// · an option without `key` ⇒ the answer came back as the string 「null」.
///
/// The last one was fixed by CONSTRUCTION (`option['key'] ??= '$index'`) and
/// is the model for the rest: the reader knows exactly which keys it looks
/// at, so anything else in a record is provably unread — and saying so costs
/// one pass over keys already parsed.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('board-unread'));
  tearDown(() => dir.deleteSync(recursive: true));

  File records(List<String> lines) =>
      File('${dir.path}/board.jsonl')..writeAsStringSync(lines.join('\n'));

  String complaints(List<String> lines) =>
      boardCheckComplaints(records(lines), now: DateTime.utc(2026, 9, 1));

  const good = '{"kind":"item","id":"W","at":"남은 것","title":"작업",'
      '"rest":"할 것","ts":"2026-08-31T01:00:00Z"}';

  group('아무도 안 읽는 말', () {
    test('🚨a key no reader looks at is named, with its line', () {
      readBoard(records([
        good,
        '{"kind":"item","id":"W","ask":"이거 어떻게 할까",'
            '"ts":"2026-08-31T02:00:00Z"}',
      ]));
      expect(unreadFields, hasLength(1));
      expect(unreadFields.single.field, 'ask');
      expect(unreadFields.single.id, 'W');
      expect(
        unreadFields.single.line,
        2,
        reason: '⛔the line number is what makes it findable — the file is '
            'append-only and the card merges many lines',
      );
    });

    test('🚨and the gate says so out loud', () {
      final out = complaints([
        good,
        '{"kind":"item","id":"W","ask":"내용","ts":"2026-08-31T02:00:00Z"}',
      ]);
      expect(out, contains('아무도 안 읽는 말'));
      expect(out, contains('2:W(ask)'));
      expect(
        out,
        contains('options'),
        reason: 'the complaint lists what IS read, so the fix is in the '
            'complaint rather than in a document somewhere',
      );
    });

    test('🚨an unknown `kind` is the same defect', () {
      final out = complaints([
        good,
        '{"kind":"질문","id":"W","ts":"2026-08-31T02:00:00Z"}',
      ]);
      expect(out, contains('kind=질문'));
    });

    test('⛔a card written correctly says nothing', () {
      expect(complaints([good]), isNot(contains('아무도 안 읽는 말')));
      expect(unreadFields, isEmpty);
    });

    test('⛔`meta` carries whatever its note needs — THIS file is not its '
        'only reader', () {
      // 🧪`landedSince` looks dead to every `json['…']` site in tool/, and
      // `board_gate.sh:223` greps it straight out of the file. Flagging it
      // would have taught the reader to ignore this check on its first run.
      final out = complaints([
        good,
        '{"kind":"meta","landedSince":"2026-08-23T21:17:40Z","note":"기준선"}',
      ]);
      expect(out, isNot(contains('아무도 안 읽는 말')));
    });

    test('⛔`law` IS checked — it is a card the board draws, not a note', () {
      final out = complaints([
        good,
        '{"kind":"law","tag":"보드","made_up":"x","ts":"2026-08-31T02:00:00Z"}',
      ]);
      expect(out, contains('made_up'));
    });

    test('⛔an ack silences it, like every other complaint', () {
      File('${dir.path}/.gate-ack').writeAsStringSync('W 알고 있다\n');
      final out = complaints([
        good,
        '{"kind":"item","id":"W","ask":"내용","ts":"2026-08-31T02:00:00Z"}',
      ]);
      expect(out, isNot(contains('아무도 안 읽는 말')));
    });
  });

  group('게이트가 아무것도 안 읽고 초록이라 말하지 않는다', () {
    // 🧪2026-08-31: I ran `board_check.exe --records <path>`. `args.first`
    // was `--records`, not a file, so it read nothing and exited 0 — and the
    // board had five complaints waiting, two of them cards I had written
    // twenty minutes earlier. ⛔The refusal used to be a bare `return`, which
    // produces the same silence a clean board produces.
    test('🚨--records is refused BY NAME, because that is the call that '
        'fooled me', () {
      final r = boardCheckRefusal(['--records', 'x.jsonl']);
      expect(r, isNotNull);
      expect(r, contains('--records'));
    });

    test('⛔no arguments is a refusal, not a pass', () {
      expect(boardCheckRefusal([]), isNotNull);
    });

    test('⛔anything option-shaped is a refusal', () {
      expect(boardCheckRefusal(['--help'], exists: (_) => true), isNotNull);
      expect(boardCheckRefusal(['-v'], exists: (_) => true), isNotNull);
    });

    test('⛔a missing file is a refusal — it is not an empty board', () {
      final r = boardCheckRefusal(['nope.jsonl'], exists: (_) => false);
      expect(r, isNotNull);
      expect(r, contains('nope.jsonl'));
    });

    test('🚨one real path runs', () {
      expect(boardCheckRefusal(['board.jsonl'], exists: (_) => true), isNull);
    });
  });

  group('읽는 키 목록은 손으로 관리하지 않는다', () {
    // ⛔A hand-kept list is one more word to remember, which IS the defect.
    // 🧪It bit inside this very change: `kKinds` shipped without `check` and
    // `record`, and the probe flagged 160 valid lines before the gate ever
    // ran. Both ARE read — board_model.dart:843 and board_server.dart:933.
    String source(String name) =>
        File('${Directory.current.path}/tool/$name').readAsStringSync();

    test('🚨kReadFields == every json[\'…\'] the model reads', () {
      final read = RegExp(r"""json\['([a-zA-Z]+)'\]""")
          .allMatches(source('board_model.dart'))
          .map((m) => m.group(1)!)
          .toSet();
      expect(
        read,
        isNotEmpty,
        reason: '⛔premise: an empty scan would make this test vacuously '
            'green — the exact 「빈 것을 쟀다」 failure this repo keeps having',
      );
      expect(
        kReadFields,
        read,
        reason: 'a key the model reads but this set omits gets reported as '
            'unread and the writer is sent chasing a working record; a key '
            'in the set that nothing reads is silently dropped forever',
      );
    });

    test('🚨kKinds covers every kind any tool compares against', () {
      final kinds = <String>{};
      for (final f in ['board_model.dart', 'board_server.dart']) {
        kinds.addAll(RegExp(r"""kind (?:!=|==) '([a-zA-Z]+)'""")
            .allMatches(source(f))
            .map((m) => m.group(1)!));
      }
      expect(kinds, isNotEmpty, reason: '⛔premise: the scan found something');
      expect(
        kinds.difference(kKinds),
        isEmpty,
        reason: 'a kind a reader handles must not be reported as unknown — '
            '`check` and `record` were missed exactly this way',
      );
    });
  });
}
