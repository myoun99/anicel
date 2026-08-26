import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The board gate's own guard.
///
/// 유저 2026-08-27: 「세션에서 대답 완료해서 작업끝났것이 답할것에 아직
/// 올라와있고 … 그런일 발생안하도록 작업흐름 개선하고싶고」. Measured that
/// day: ten cards sat in 분류 전 carrying an answer and eight more sat there
/// unclassified, some for days — and two of those memos were the work the
/// user had just asked for out loud.
///
/// ⚠️These drive the REAL program, not a copy of its rules. The gate is a
/// `main()` that the Stop hook runs as an exe; a test that re-implemented the
/// predicate would go green while the thing the hook runs said something else.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('anicel-board-check');
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  String stamp(Duration ago) =>
      DateTime.now().subtract(ago).toIso8601String();

  /// Runs the gate over [records] and returns what it complained about.
  Future<String> complaintFor(
    List<Map<String, dynamic>> records, {
    List<String> acked = const [],
  }) async {
    final file = File('${dir.path}/board.jsonl');
    file.writeAsStringSync(records.map(jsonEncode).join('\n'));
    if (acked.isNotEmpty) {
      File('${dir.path}/.gate-ack').writeAsStringSync(acked.join('\n'));
    }
    final run = await Process.run('dart', [
      'run',
      'tool/board_check.dart',
      file.path,
      // ⚠️`runInShell`: on Windows the SDK entry point is `dart.bat`, and a
      // bare `dart` is not an executable the process API can find.
    ], workingDirectory: Directory.current.path, runInShell: true);
    // ⚠️Matched on ASCII ids only. Windows decodes a child's stdout in the
    // console codepage, so the Korean sentences come back as mojibake here
    // even though the hook receives them intact.
    return '${run.stdout}';
  }

  test('a card the user ANSWERED but nobody classified is named', () async {
    final out = await complaintFor([
      {
        'kind': 'item',
        'id': 'Q-apple-gate-time',
        'state': 'inbox',
        'answer': 'A + 스위트 3샤드',
        'ts': stamp(const Duration(minutes: 5)),
      },
    ]);
    expect(
      out,
      contains('Q-apple-gate-time'),
      reason: '분류 전은 「내가 읽고 분류한다」 — 답이 달린 채 남으면 유저 '
          '피드백을 아무도 안 읽은 것이 된다',
    );
  });

  test('feedback that arrived THIS TURN is not a failure', () async {
    final out = await complaintFor([
      {
        'kind': 'item',
        'id': 'F-99',
        'state': 'inbox',
        'said': '방금 적어 준 것',
        'ts': stamp(const Duration(minutes: 5)),
      },
    ]);
    expect(
      out,
      isEmpty,
      reason: '⛔새 피드백이 분류 전에 있는 것은 정상이다 — 그것으로 막으면 '
          '그 칸이 쓸모가 없어진다',
    );
  });

  test('the same card a day later IS a failure', () async {
    final out = await complaintFor([
      {
        'kind': 'item',
        'id': 'F-38',
        'state': 'inbox',
        'said': '변형 언두하면 선택도 되돌리기',
        'ts': stamp(const Duration(hours: 25)),
      },
    ]);
    expect(out, contains('F-38'));
  });

  test('a question still asking after a day is named — its answer may have '
      'come in CHAT, which the board cannot see', () async {
    final out = await complaintFor([
      {
        'kind': 'decision',
        'id': 'Q-remaining-14',
        'state': 'ask',
        'ts': stamp(const Duration(hours: 30)),
        'where': 'x',
        'why': 'y',
        'options': [
          {'key': '1', 'label': 'a'},
          {'key': '2', 'label': 'b'},
        ],
      },
    ]);
    expect(out, contains('Q-remaining-14'));
  });

  test('an ANSWERED question is not still asking', () async {
    final out = await complaintFor([
      {
        'kind': 'decision',
        'id': 'Q-done',
        'state': 'ask',
        'answer': '2',
        'ts': stamp(const Duration(hours: 30)),
      },
    ]);
    expect(
      out,
      isEmpty,
      reason: 'the board moves an answered question to 분류 전 by itself; '
          'this one has been answered and its state simply has not caught up',
    );
  });

  test('the ack silences EVERY complaint, not only the newest ones', () async {
    // 🚨It used to exempt a card from the age checks and nothing else, so
    // acking a card the gate had named changed nothing and the same line
    // came back every turn. An ack that does not silence is worse than
    // none: the next reader learns to scroll past the gate.
    final out = await complaintFor([
      {
        'kind': 'item',
        'id': 'I-8',
        'state': 'open',
        'ts': stamp(const Duration(hours: 1)),
        // The older complaint: a check written where remaining CODE goes.
        'rest': '실기로 확인한다',
      },
    ], acked: ['I-8']);
    expect(out, isEmpty);
  });

  test('and without the ack that same card IS named', () async {
    final out = await complaintFor([
      {
        'kind': 'item',
        'id': 'I-8',
        'state': 'open',
        'ts': stamp(const Duration(hours: 1)),
        'rest': '실기로 확인한다',
      },
    ]);
    expect(out, contains('I-8'));
  });

  test('an id in .gate-ack goes quiet — a question that is genuinely still '
      'open must not nag for ever', () async {
    final out = await complaintFor([
      {
        'kind': 'decision',
        'id': 'F-31-rest',
        'state': 'ask',
        'ts': stamp(const Duration(hours: 30)),
        // ⚠️Answerable, deliberately: without these the OLDER check (「답할 수
        // 없는 결정 카드」) fires and the ack would look broken when what it
        // silenced was a different complaint entirely.
        'where': 'x',
        'why': 'y',
        'options': [
          {'key': '1', 'label': 'a'},
          {'key': '2', 'label': 'b'},
        ],
      },
    ], acked: ['F-31-rest']);
    expect(out, isEmpty);
  });
}
