import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_model.dart';
import '../helpers/temp_dir.dart';

/// 🚨★★★THE BOARD IS READ ON FROM WHERE IT STOPPED, NOT AGAIN FROM THE TOP
/// (유저 2026-10-19: 「세션들 활발하게 돌아갈때 … 피드백 제출버튼누르면
/// 10초뒤에 되는느낌. 근본/구조적으로 어떻게 못하나? 대충 해결해봣자 또 …
/// 시간지나면 점점 느려질거같은데」 · 「프로들 … 극한으로」).
///
/// 🧪Measured that day: every reader refolded the whole 18.8MB file — the
/// page, a card, the gate on every session's turn, a letter, a submit (twice)
/// — 0.55s each, in the server's one line of requests; and the checkouts it
/// shows ran sixty-two `git` processes inside whichever request came 20s after
/// the last. Both grew with time: the file with history, the checkouts with
/// lanes. [BoardRecords] reads only what was appended; these pins keep it so.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('board-memory'));
  tearDown(() => deleteTempQuietly(dir));

  String line(String id, Map<String, Object?> rest) =>
      jsonEncode({'id': id, ...rest});

  group('read on, not again', () {
    test('a read after an append reads the appended bytes and no others',
        () {
      // Past the 64 KiB the reader keeps as its witness, so the line changed
      // below sits where only a reread from the top would see it.
      final pad = [
        for (var i = 0; i < 400; i++)
          line('pad-$i', {'title': 'x' * 200, 'at': '할 일'}),
      ];
      final f = File('${dir.path}/board.jsonl')
        ..writeAsStringSync([
          ...pad,
          line('M', {'title': 'AAAA', 'at': '할 일'}),
          for (var i = 0; i < 4; i++) line('tail-$i', {'title': 'y' * 100}),
        ].map((l) => '$l\n').join());
      expect(f.lengthSync(), greaterThan(64 * 1024 + 2000),
          reason: '⛔premise: the changed line is past the witness');
      String titleOf(String id) =>
          readBoard(f).firstWhere((c) => c.id == id).title;
      expect(titleOf('M'), 'AAAA');

      // The file says BBBB now where it said AAAA — a change an append-only
      // log never makes, so a reader that reads on does not see it.
      final text = f.readAsStringSync();
      f.openSync(mode: FileMode.append)
        ..setPositionSync(
            utf8.encode(text.substring(0, text.indexOf('AAAA'))).length)
        ..writeStringSync('BBBB')
        ..closeSync();
      expect(f.readAsStringSync(),
          allOf(contains('BBBB'), isNot(contains('AAAA'))),
          reason: '⛔premise: the line changed in place');
      f.writeAsStringSync('${line('Z', {'title': 'new'})}\n',
          mode: FileMode.append);

      expect(titleOf('Z'), 'new', reason: 'what was appended is read');
      expect(titleOf('M'), 'AAAA',
          reason: '🚨and nothing before it: a reread from the top would say '
              'BBBB');

      // A file that got SHORTER was rewritten, and is read from the top.
      final bytes = f.readAsBytesSync();
      f.writeAsBytesSync(bytes.sublist(0, bytes.length - 2));
      expect(titleOf('M'), 'BBBB');
    });

    test('nothing written, nothing folded: the same reading is handed back',
        () {
      final f = File('${dir.path}/board.jsonl')
        ..writeAsStringSync('${line('A', {'at': '할 일'})}\n');
      final now = DateTime.utc(2026, 10, 19);
      expect(identical(readBoard(f, now: now), readBoard(f, now: now)),
          isTrue);
      final before = readBoard(f, now: now);
      f.writeAsStringSync('${line('B', {'at': '할 일'})}\n',
          mode: FileMode.append);
      expect(identical(readBoard(f, now: now), before), isFalse);
    });

    test('🚨a file rewritten to the same length is read again — a test does '
        'that, inside one tick of the clock', () {
      final f = File('${dir.path}/board.jsonl')
        ..writeAsStringSync('${line('A', {'at': '검증'})}\n');
      expect(statusOf(readBoard(f).single), BoardStatus.verify);
      f.writeAsStringSync('${line('A', {'at': '완료'})}\n');
      expect(f.lengthSync(), utf8.encode('${line('A', {'at': '검증'})}\n')
          .length, reason: '⛔premise: 검증 and 완료 are the same length');
      expect(statusOf(readBoard(f).single), BoardStatus.done);
    });

    test('a last line with no newline, finished by the next write, is read '
        'as the finished line', () {
      final f = File('${dir.path}/board.jsonl')
        ..writeAsStringSync('${line('A', {'at': '할 일'})}\n{"id":"B","ti');
      expect(readBoard(f).map((c) => c.id), ['A']);
      expect(badLines, [2]);
      f.writeAsStringSync('tle":"done"}\n', mode: FileMode.append);
      expect(readBoard(f).map((c) => c.title), ['', 'done']);
      expect(badLines, isEmpty);
    });

    test('a carriage return ends a line as it did for the reader it replaced',
        () {
      final f = File('${dir.path}/board.jsonl')
        ..writeAsStringSync('x\r\ny\rz\n${line('A', {'at': '할 일'})}\n');
      expect(readBoard(f).map((c) => c.id), ['A']);
      expect(badLines, [1, 2, 3]);
      expect(BoardRecords.of(f).lines.single.no, 4);
    });
  });

  group('read on is read whole', () {
    // Every kind of line that folds one card into another, or marks another
    // card's entry: the passes the fold runs on its copy.
    final story = [
      line('T', {'kind': 'item', 'title': 'host', 'at': '할 일', 'ts': '2026-10-01T01:00:00'}),
      line('T', {'pr': 7, 'ts': '2026-10-01T02:00:00'}),
      line('T', {'pr': 7, 'note': 'shipped', 'ts': '2026-10-01T03:00:00'}),
      line('T-Q1', {'kind': 'decision', 'title': 'which?', 'at': '질문', 'options': [{'label': 'a'}, {'label': 'b'}], 'ts': '2026-10-01T04:00:00'}),
      line('C-1', {'kind': 'check', 'under': 7, 'how': 'try it', 'ts': '2026-10-01T05:00:00'}),
      line('T', {'note': 'for you', 'to': '저장', 'from': '관제', 'ts': '2026-10-01T06:00:00'}),
      line('T', {'at': '읽음', 'ref': '2026-10-01T06:00:00', 'from': '저장', 'ts': '2026-10-01T07:00:00'}),
      line('T-Q1', {'answer': '2', 'answerNote': 'b it is', 'ts': '2026-10-01T08:00:00'}),
      line('U', {'kind': 'item', 'tag': '보드', 'at': '분류 전', 'ts': '2026-10-01T09:00:00'}),
      line('U', {'kind': 'item', 'note': 'later', 'ts': '2026-10-01T00:30:00'}),
      line('L', {'kind': 'law', 'tag': '보드', 'care': 'read first', 'ts': '2026-10-01T10:00:00'}),
      line('T', {'at': '완료', 'ts': '2026-10-01T11:00:00'}),
      line('C-2', {'kind': 'check', 'under': 7, 'how': 'after the end', 'ts': '2026-10-01T12:00:00'}),
    ];

    String canon(List<BoardCard> cards) => jsonEncode([
          for (final e in cards)
            [
              e.id, e.kind, e.title, e.tags, e.state, e.updated, e.created,
              e.foldedInto, e.under, e.of, e.rest, e.care, e.tag, e.where,
              e.why, e.how, e.pr, e.prs, e.options, e.recommend, e.answer,
              e.answerNote, e.priority, e.owner,
              [
                for (final l in e.log)
                  [
                    l.ts, l.at, l.text, l.byUser, l.pr, l.how, l.ref, l.to,
                    l.from, l.readBy, l.ask?.id,
                  ],
              ],
            ],
        ]);

    test('🚨after every line, the board read on is the board read from the '
        'top', () {
      final now = DateTime.utc(2026, 10, 2);
      final grown = File('${dir.path}/grown.jsonl')..writeAsStringSync('');
      for (var n = 1; n <= story.length; n++) {
        grown.writeAsStringSync('${story[n - 1]}\n', mode: FileMode.append);
        // A new path is a reader that has read nothing yet.
        final whole = File('${dir.path}/whole-$n.jsonl')
          ..writeAsStringSync(story.take(n).map((l) => '$l\n').join());
        final cards = readBoard(grown, now: now);
        expect(canon(cards), canon(readBoard(whole, now: now)),
            reason: 'after line $n');
        if (n == 8) {
          expect(cards.firstWhere((c) => c.id == 'C-1').foldedInto, 'T',
              reason: '⛔premise: the story folds a check into its host');
          expect(cards.firstWhere((c) => c.id == 'T-Q1').foldedInto, 'T',
              reason: '⛔premise: and a question into the card it asks for');
        }
      }
      expect(
          readBoard(grown, now: now)
              .where((c) => c.kind == 'check')
              .map((c) => c.foldedInto),
          [null, null],
          reason: '⛔premise: and stands the checks alone once the host '
              'ended — the passes run again on the lines, not on the last '
              'reading');
    });

    test('🚨the copy the passes work on carries every field of a card — read '
        'out of the class, so a field added tomorrow is asked about too', () {
      final source = File('tool/board_model.dart').readAsStringSync();
      final body = RegExp(r'class BoardCard \{([\s\S]*?)\n  BoardCard copy\(\)')
          .firstMatch(source)!
          .group(1)!;
      final fields = {
        for (final m in RegExp(r'^  (?:final )?[\w<>?, ]+ (\w+)(?: = [^;]+)?;$',
                multiLine: true)
            .allMatches(body))
          m.group(1)!,
      }..removeAll([
          // What the constructor is handed, and [copy] hands it on.
          for (final m in RegExp(r'this\.(\w+)').allMatches(body)) m.group(1)!,
        ]);
      expect(fields, containsAll(['title', 'log', 'prs', 'owner', 'options']),
          reason: '⛔premise: the scan found the fields');
      final copy = RegExp(r'BoardCard copy\(\) => BoardCard\(id, kind\)([\s\S]*?);\n')
          .firstMatch(source)!
          .group(1)!;
      for (final field in fields) {
        expect(copy, matches(RegExp('\\.\\.$field(?: =|\\.addAll)')),
            reason: '「$field」 is lost on every reading after a write');
      }
    });
  });

  test('🚨the server runs no process and reads no file whole inside a '
      'request — every request waits for the ones before it', () {
    final server = File('tool/board_server.dart').readAsStringSync();
    expect(server, isNot(contains('runSync(')),
        reason: 'a process run in a request stops the board — see `_git`');
    expect(server, isNot(contains('readAsLinesSync(')),
        reason: 'the records are read through BoardRecords, on from where '
            'the last request stopped');
    final model = File('tool/board_model.dart').readAsStringSync();
    expect('readAsLinesSync('.allMatches(model), hasLength(1),
        reason: 'one whole read of the records: the rewrite (`/purge`)');
  });
}
