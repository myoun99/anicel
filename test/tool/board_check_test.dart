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
  _recommendMustNameAnOption();
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('anicel-board-check');
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  String stamp(Duration ago) => DateTime.now().subtract(ago).toIso8601String();

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
    final run = await Process.run(
      'dart',
      [
        'run',
        'tool/board_check.dart',
        file.path,
        // ⚠️`runInShell`: on Windows the SDK entry point is `dart.bat`, and a
        // bare `dart` is not an executable the process API can find.
      ],
      workingDirectory: Directory.current.path,
      runInShell: true,
    );
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
      reason:
          '분류 전은 「내가 읽고 분류한다」 — 답이 달린 채 남으면 유저 '
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
      reason:
          '⛔새 피드백이 분류 전에 있는 것은 정상이다 — 그것으로 막으면 '
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
      reason:
          'the board moves an answered question to 분류 전 by itself; '
          'this one has been answered and its state simply has not caught up',
    );
  });

  test('the ack silences EVERY complaint, not only the newest ones', () async {
    // 🚨It used to exempt a card from the age checks and nothing else, so
    // acking a card the gate had named changed nothing and the same line
    // came back every turn. An ack that does not silence is worse than
    // none: the next reader learns to scroll past the gate.
    final out = await complaintFor(
      [
        {
          'kind': 'item',
          'id': 'I-8',
          'state': 'open',
          'ts': stamp(const Duration(hours: 1)),
          // The older complaint: a check written where remaining CODE goes.
          'rest': '실기로 확인한다',
        },
      ],
      acked: ['I-8'],
    );
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
    final out = await complaintFor(
      [
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
      ],
      acked: ['F-31-rest'],
    );
    expect(out, isEmpty);
  });

  // 🚨★★★유저 2026-08-29: 「색 키를 GPU로 보니까 작업완료고 남은건
  // 실기뿐인거같은데 이런건 착수가능이 아니라 실기확인에 있는게 맞는거
  // 아니야? … 이거 게이트에 문제있는거같은데 분류못해내는거보니」.
  //
  // Twenty finished cards were sitting in 착수 가능. The renderer knows
  // nine states and drops everything else into that column, so a state
  // name nobody defined does not create a new column — it silently files
  // the card as unstarted work.
  group('보드가 모르는 state', () {
    test('정의되지 않은 state 는 잡힌다', () async {
      final out = await complaintFor([
        {'id': 'X1', 'kind': 'item', 'state': 'done', 'note': 'x'},
      ]);
      expect(out, contains('X1(done)'));
      // ⛔ASCII ONLY in assertions: the harness reads the child's stdout
      // through the system codepage, so Korean comes back mojibake. Every
      // test here checks the CARD ID, which is what the reader needs to
      // act on anyway.
    });

    test('아는 state 아홉은 조용하다', () async {
      for (final s in const [
        'open',
        'inbox',
        'wip',
        'ask',
        'gate',
        'queue',
        'mine',
        'archived',
        'deleted',
      ]) {
        final out = await complaintFor([
          {
            'id': 'X-$s',
            'kind': 'item',
            'state': s,
            'note': 'x',
            // ⛔A fresh ts: an inbox card older than a day is caught by a
            // DIFFERENT check, and this test is about state names only.
            'ts': stamp(Duration.zero),
          },
        ]);
        expect(out, isNot(contains('X-$s')), reason: '$s 는 아는 상태다');
      }
    });

    test('state 를 안 쓰면 open 이라 조용하다', () async {
      final out = await complaintFor([
        {'id': 'X2', 'kind': 'item', 'note': 'x'},
      ]);
      expect(out, isNot(contains('X2')));
    });
  });

  // 🚨The board files a card by its `pr` FIELD. 「#1302」 in the note tells
  // the reader and nobody else, so a shipped card sits in 착수 가능.
  group('PR을 본문에만 적은 카드', () {
    test('note 에 PR 번호가 있는데 pr 필드가 없으면 잡힌다', () async {
      final out = await complaintFor([
        {'id': 'Y1', 'kind': 'item', 'note': '고쳤다 (PR #1302).'},
      ]);
      expect(out, contains('Y1'));
    });

    test('pr 필드가 있으면 조용하다', () async {
      final out = await complaintFor([
        {'id': 'Y2', 'kind': 'item', 'pr': 1302, 'note': '고쳤다 (PR #1302).'},
      ]);
      expect(out, isNot(contains('Y2')));
    });

    test('끝난 카드에는 PR을 요구하지 않는다', () async {
      // ⛔An archived card is off every list — nothing to misfile, and a
      // gate that cries wolf is a gate nobody reads.
      final out = await complaintFor([
        {
          'id': 'Y3',
          'kind': 'item',
          'state': 'archived',
          'note': '고쳤다 (PR #1302).',
        },
      ]);
      expect(out, isNot(contains('Y3')));
    });

    test('세 자리 숫자는 PR 이 아니다', () async {
      final out = await complaintFor([
        {'id': 'Y4', 'kind': 'item', 'note': 'R26 #41 시트 페이지뷰.'},
      ]);
      expect(out, isNot(contains('Y4')));
    });
  });

  // 🚨★★★AN ACK CARRIES ITS REASON, AND A DEAD ACK GETS NAMED.
  //
  // `.gate-ack` was a bare list of numbers. By 2026-08-29 it held 34 and
  // seventeen of them were dead — the landing had a card by then, so the
  // line silenced nothing and read to the next person as "still uncarded".
  group('.gate-ack', () {
    test('a reason after the key still silences — the key is the first '
        'token, not the whole line', () async {
      final out = await complaintFor(
        [
          {
            'kind': 'item',
            'id': 'I-8',
            'state': 'open',
            'ts': stamp(const Duration(hours: 1)),
            'rest': '실기로 확인한다',
          },
        ],
        acked: ['I-8 another session owns this one'],
      );
      expect(out, isEmpty);
    });

    test('a # line is a comment, not a key', () async {
      // The file needs somewhere to say what its own format is, and a
      // header that silenced a card called `#` would be a trap.
      final out = await complaintFor(
        [
          {
            'kind': 'item',
            'id': 'I-8',
            'state': 'open',
            'ts': stamp(const Duration(hours: 1)),
            'rest': '실기로 확인한다',
          },
        ],
        acked: ['# key <space> reason', 'I-8 still open'],
      );
      expect(out, isEmpty);
    });

    test('an ack for a landing that NOW has a card is named', () async {
      final out = await complaintFor(
        [
          {
            'kind': 'item',
            'id': 'C-1',
            'state': 'open',
            'pr': 1302,
            'note': 'x',
            'how': 'y',
            'ts': stamp(const Duration(hours: 1)),
          },
        ],
        acked: ['1302 was another session'],
      );
      expect(out, contains('1302'));
    });

    test('and an ack for a landing with no card stays quiet', () async {
      // ⛔THE CONTROL. A rule that named every numeric ack would "pass" the
      // test above while telling the user to delete lines that are still
      // doing their job.
      final out = await complaintFor(
        [
          {
            'kind': 'item',
            'id': 'C-1',
            'state': 'open',
            'pr': 1302,
            'note': 'x',
            'how': 'y',
            'ts': stamp(const Duration(hours: 1)),
          },
        ],
        acked: ['1399 nobody carded this'],
      );
      expect(out, isEmpty);
    });

    test('an ARCHIVED card still counts as having the landing', () async {
      // The gate's main loop skips archived cards. Reading the PR set off
      // that loop would have called a healthy ack dead — archiving a card
      // is the opposite of losing it.
      final out = await complaintFor(
        [
          {
            'kind': 'item',
            'id': 'C-1',
            'state': 'archived',
            'pr': 1302,
            'note': 'x',
            'how': 'y',
            'ts': stamp(const Duration(hours: 1)),
          },
        ],
        acked: ['1302 was another session'],
      );
      expect(out, contains('1302'));
    });
  });
}

/// 🚨추천이 선택지를 안 가리키면 **화면에 아무것도 안 나온다.**
///
/// 2026-08-28 실사고: `I-4-tone` 의 `recommend` 에 추천 이유를 문단으로 적었고,
/// 유저는 **한 글자도 못 봤다.** `note` 가 안 그려지던 것과 같은 모양이라 같은
/// 게이트가 막아야 한다.
void _recommendMustNameAnOption() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('anicel-board-rec');
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// ⚠️Same invocation as the gate's other tests: `dart` is `dart.bat` on
  /// Windows so it needs a shell, and the argument is the FILE. The reply is
  /// matched on the ASCII id — Windows decodes the child's Korean in the
  /// console codepage and it arrives here as mojibake.
  Future<String> gate(
    String id, {
    Object? recommend,
    required List<Map<String, String>> options,
  }) async {
    final file = File('${dir.path}/board.jsonl');
    file.writeAsStringSync(
      jsonEncode({
        'kind': 'decision',
        'id': id,
        'state': 'ask',
        'ts': DateTime.now().toIso8601String(),
        'where': 'somewhere on screen',
        'why': 'blocked for this reason',
        'options': options,
        'recommend': ?recommend,
      }),
    );
    final run = await Process.run(
      'dart',
      ['run', 'tool/board_check.dart', file.path],
      workingDirectory: Directory.current.path,
      runInShell: true,
    );
    return '${run.stdout}';
  }

  const keyed = [
    {'key': '1', 'label': 'a'},
    {'key': '2', 'label': 'b'},
  ];

  test('문장을 적으면 게이트가 이름을 부른다', () async {
    final out = await gate(
      'T99-Q1',
      recommend: '1번이 낫습니다 — 폭이 넓어지고 대가가 없어서',
      options: keyed,
    );
    expect(out, contains('T99-Q1'));
  });

  test('키를 적으면 조용하다', () async {
    final out = await gate('T99-Q2', recommend: '2', options: keyed);
    expect(
      out,
      isNot(contains('T99-Q2')),
      reason:
          '⚠️이 카드는 방금 만들어졌고 where·why·label 이 다 있으므로, '
          '이름이 뜬다면 그건 추천 때문이다',
    );
  });

  test('키를 안 쓴 선택지도 번호로 세어 준다 — 서버가 그렇게 채운다', () async {
    // 서버는 key 가 없으면 순번을 넣는다. 게이트가 다른 규칙으로 세면
    // 「서버는 받아들이는데 게이트는 막는」 어긋남이 생긴다.
    final out = await gate(
      'T99-Q3',
      recommend: '2',
      options: const [
        {'label': 'a'},
        {'label': 'b'},
      ],
    );
    expect(out, isNot(contains('T99-Q3')));
  });
}
