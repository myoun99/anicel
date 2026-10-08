import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_door.dart';
import '../../tool/board_me.dart';
import '../../tool/board_model.dart';
import '../../tool/board_say.dart';
import '../../tool/board_server.dart';
import '../helpers/temp_dir.dart';

/// 유저 2026-10-07 (the-board-is-one-server-for-both-machines-Q2): 「글은
/// 카드의 흐름에 적고, 「전달」 보기는 그것을 모아 보여 주기만 한다 … 세션은
/// 턴이 시작하고 끝날 때 자기 앞의 안 읽은 줄을 훅이 보여 준다」.
///
/// `a_letter_is_an_entry_on_a_card_test` pins what a letter IS. This file
/// pins the road it travels: a session says once which 담당 it answers to,
/// the tool signs its letters with that, a line that is half a letter is
/// refused when it is written, the server hands a session what waits for it
/// and marks it read by the same act, and the board shows the letters
/// without keeping any.
///
/// ⚠️The hook that asks the server is bash, and the suite spawns no process
/// (tests_do_not_race_the_code_test): what it does is pinned by
/// `session_letters_test.sh`, run by hand. The server it asks is real here —
/// one for the file, bound on loopback (the_board_has_a_door_test says why).
void main() {
  const mine = '보드/통합';
  const theirs = '타임라인/콘티';
  final now = DateTime.parse('2026-10-07T15:00:00.000');
  late Directory dir;
  late File records;
  late HttpServer server;
  late Uri base;

  String line(Map<String, Object?> record) => jsonEncode(record);
  final card = line({
    'kind': 'item',
    'id': 'W',
    'at': '하는 중',
    'owner': theirs,
    'title': '작업',
    'note': '시작',
    'ts': '2026-10-07T10:00:00.000000',
  });
  final other = line({
    'kind': 'item',
    'id': 'V',
    'at': '할 일',
    'title': '다른 작업',
    'note': '아직',
    'ts': '2026-10-07T10:30:00.000000',
  });
  String letter(
    String ts, {
    String id = 'W',
    String to = theirs,
    String from = mine,
    String note = '레인이 착지했다',
  }) => line({'id': id, 'to': to, 'from': from, 'note': note, 'ts': ts});
  const t1 = '2026-10-07T11:00:00.000000';
  const t2 = '2026-10-07T12:00:00.000000';
  const t3 = '2026-10-07T12:10:00.000000';
  const t4 = '2026-10-07T12:20:00.000000';

  void boardHolds(List<String> lines) =>
      records.writeAsStringSync(lines.map((l) => '$l\n').join());
  List<Map<String, dynamic>> written() => [
    for (final l in records.readAsLinesSync())
      if (l.trim().isNotEmpty) jsonDecode(l) as Map<String, dynamic>,
  ];

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('qa_board_letters');
    records = File('${dir.path}/board.jsonl')..writeAsStringSync('');
    boardIs(
      records: records.path,
      gh: '${dir.path}/no-gh-here',
      gitRoot: dir.path,
      door: const LoopbackDoor(),
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(answerAll(server));
    base = Uri.parse('http://127.0.0.1:${server.port}');
  });
  tearDownAll(() async {
    await server.close(force: true);
    deleteTempQuietly(dir);
  });

  group('a session says once which 담당 it answers to', () {
    const env = {
      kBoardFolderVariable: r'C:\local\board',
      kSessionIdVariable: 'abc-123',
    };

    test('the name is kept with the machine\'s flags, a file a session', () {
      expect(
        sessionNameFile(env),
        'C:/local/board/$kSessionNamesFolder/abc-123',
      );
      String? reading(String path) =>
          path == 'C:/local/board/$kSessionNamesFolder/abc-123'
          ? '$theirs\r\n'
          : null;
      expect(sessionNameOf(env, read: reading), theirs);
    });

    test('⛔no folder, no session, or nothing registered: no name — never '
        'somebody else\'s', () {
      expect(sessionNameFile({kSessionIdVariable: 'abc'}), isNull);
      expect(sessionNameFile({kBoardFolderVariable: 'C:/b'}), isNull);
      expect(sessionNameOf(env, read: (_) => null), isNull);
      expect(sessionNameOf(env, read: (_) => ' \n'), isNull);
    });

    test('a 담당 is one line, and 「모두」 is not one', () {
      expect(sessionNameRefusal(theirs), isNull);
      expect(sessionNameRefusal('캔버스 베이스 패널'), isNull);
      expect(sessionNameRefusal(''), isNotNull);
      expect(sessionNameRefusal('a\nb'), isNotNull);
      expect(sessionNameRefusal(kEveryone), contains(kEveryone));
    });
  });

  group('the tool signs a letter for the session', () {
    test('a letter and a reader\'s mark with no writer get this session\'s '
        '담당; everything else is left as it was written', () {
      final unsigned = line({'id': 'W', 'to': theirs, 'note': '보냄'});
      final mark = line({'id': 'W', 'at': kReadMark, 'ref': t1});
      final signedAlready = letter(t1, from: '저장');
      final note = line({'id': 'W', 'note': '그냥 적는 줄'});
      final out = signedBy(mine, [unsigned, mark, signedAlready, note, '{x']);
      expect(jsonDecode(out[0]), containsPair('from', mine));
      expect(jsonDecode(out[1]), containsPair('from', mine));
      expect(out.sublist(2), [signedAlready, note, '{x']);
    });

    test('⛔a session that registered nothing signs nothing — and the '
        'letter is then refused by name', () {
      final unsigned = line({'id': 'W', 'to': theirs, 'note': '보냄'});
      expect(signedBy(null, [unsigned]), [unsigned]);
      expect(
        recordRefusal(jsonDecode(unsigned) as Map<String, dynamic>, 1),
        contains('board_me.dart'),
      );
    });
  });

  group('a line that is half a letter is refused when it is written', () {
    String? refusal(Map<String, Object?> record) =>
        recordRefusal(Map<String, dynamic>.from(record), 3);

    test('a whole letter and a whole mark pass', () {
      expect(refusal({'id': 'W', 'to': theirs, 'from': mine, 'note': 'x'}),
          isNull);
      expect(
        refusal({'id': 'W', 'to': kEveryone, 'from': mine, 'note': 'x'}),
        isNull,
      );
      expect(
        refusal({'id': 'W', 'at': kReadMark, 'ref': t1, 'from': theirs}),
        isNull,
      );
      expect(refusal({'id': 'W', 'note': '전달이 아닌 줄'}), isNull);
    });

    test('⛔no words, no reader, or its own writer for a reader', () {
      expect(
        refusal({'id': 'W', 'to': theirs, 'from': mine}),
        allOf(startsWith('3번째 줄'), contains('note')),
      );
      expect(
        refusal({'id': 'W', 'to': ' ', 'from': mine, 'note': 'x'}),
        contains('`to` 가 비었습니다'),
      );
      expect(
        refusal({'id': 'W', 'to': mine, 'from': mine, 'note': 'x'}),
        contains('자기 앞으로'),
      );
    });

    test('⛔`from` alone is read by nobody', () {
      expect(
        refusal({'id': 'W', 'from': mine, 'note': 'x'}),
        contains('`from`'),
      );
    });

    test('⛔a letter goes on a card, not on its question — what is written '
        'on a question is drawn nowhere', () {
      expect(
        refusal({'id': 'W-Q1', 'to': theirs, 'from': mine, 'note': 'x'}),
        allOf(contains('「W-Q1」'), contains('「W」')),
      );
    });

    test('⛔a mark is a mark: it names a letter and a reader, and carries '
        'no words', () {
      expect(
        refusal({'id': 'W', 'at': kReadMark, 'from': theirs}),
        contains('`ref`'),
      );
      expect(
        refusal({'id': 'W', 'at': kReadMark, 'ref': t1}),
        contains('`from`'),
      );
      expect(
        refusal({
          'id': 'W',
          'at': kReadMark,
          'ref': t1,
          'from': theirs,
          'note': '읽었다',
        }),
        contains('「note」'),
      );
    });
  });

  group('a mark must name a letter that waits for its reader', () {
    String? marking({
      required String ref,
      required String by,
      String id = 'W',
    }) {
      boardHolds([card, letter(t1)]);
      return sayToRecords(records, [
        line({'id': id, 'at': kReadMark, 'ref': ref, 'from': by}),
      ], now).refusal;
    }

    test('the reader it was left for marks it, once', () {
      expect(marking(ref: t1, by: theirs), isNull);
      expect(written().last, {
        'id': 'W',
        'at': kReadMark,
        'ref': t1,
        'from': theirs,
        'ts': now.toIso8601String(),
      });
      final again = sayToRecords(records, [
        line({'id': 'W', 'at': kReadMark, 'ref': t1, 'from': theirs}),
      ], now).refusal;
      expect(again, contains('이미 읽었습니다'));
    });

    test('⛔a stamp that is no letter\'s, another card, another reader, or '
        'the writer: refused, and nothing is written', () {
      for (final refusal in [
        marking(ref: 'no-such-stamp', by: theirs),
        marking(ref: '2026-10-07T10:00:00.000000', by: theirs),
        marking(ref: t1, by: theirs, id: 'V'),
        marking(ref: t1, by: '저장'),
        marking(ref: t1, by: mine),
      ]) {
        expect(refusal, isNotNull);
        expect(written(), hasLength(2), reason: '$refusal');
      }
    });
  });

  test('a letter for a name no open card is held by warns, and is written', () {
    boardHolds([card]);
    final said = sayToRecords(records, [
      line({'id': 'W', 'to': '타임라인', 'from': mine, 'note': 'x'}),
      line({'id': 'W', 'to': theirs, 'from': mine, 'note': 'y'}),
      line({'id': 'W', 'to': kEveryone, 'from': mine, 'note': 'z'}),
    ], now);
    expect(said.refusal, isNull);
    expect(said.lines, 3);
    expect(said.warnings, hasLength(1));
    expect(
      said.warnings.single,
      allOf(startsWith('1번째 줄'), contains('「타임라인」'), contains(theirs)),
    );
  });

  group('what waits for a session is taken', () {
    test('its letters come as text, oldest first, with how to answer — and '
        'are marked read by the same act', () {
      boardHolds([
        card,
        other,
        letter(t2, note: '둘째 줄\n"따옴표" 포함'),
        letter(t1, id: 'V', from: '관제', note: '첫째'),
        letter(t3, to: '저장'),
        letter(t4, to: mine, from: theirs),
      ]);
      final text = takeLetters(records, theirs, now);
      expect(
        text,
        '📨 보드에 「$theirs」 앞으로 남은 전달 2건 — 읽음으로 표시했습니다.\n'
        '\n'
        '━ 관제 → $theirs · 카드 V 「다른 작업」 · 10-07 11:00\n'
        '첫째\n'
        '\n'
        '━ $mine → $theirs · 카드 W 「작업」 · 10-07 12:00\n'
        '둘째 줄\n'
        '"따옴표" 포함\n'
        '\n'
        '답은 그 카드에 `to` 를 적은 줄로 남깁니다: '
        '{"id":"<카드>","to":"<보낸 담당>","note":"…"}',
      );
      final marks = written().skip(6).toList();
      expect(marks, [
        {
          'id': 'V',
          'at': kReadMark,
          'ref': t1,
          'from': theirs,
          'ts': now.toIso8601String(),
        },
        {
          'id': 'W',
          'at': kReadMark,
          'ref': t2,
          'from': theirs,
          'ts': now.add(const Duration(milliseconds: 1)).toIso8601String(),
        },
      ]);
      expect(takeLetters(records, theirs, now), isEmpty, reason: 'taken');
    });

    test('⛔a mark names no kind — a line\'s kind is its card\'s — and '
        'takes nobody else\'s letters', () {
      final check = line({
        'kind': 'check',
        'id': 'C-1',
        'title': '기기에서 볼 것',
        'ts': '2026-10-07T10:40:00.000000',
      });
      boardHolds([card, check, letter(t1, id: 'C-1'), letter(t2, to: '저장')]);
      takeLetters(records, theirs, now);
      final cards = readBoard(records);
      expect(written().last.containsKey('kind'), isFalse);
      expect(cards.singleWhere((c) => c.id == 'C-1').kind, 'check');
      expect(
        [
          for (final l in lettersOf(cards))
            if (letterWaitsFor(l.entry, '저장')) l.entry.ts,
        ],
        [t2],
      );
    });

    test('⛔nobody asking, or nothing waiting: nothing said, nothing '
        'written', () {
      boardHolds([card, letter(t1, to: '저장')]);
      expect(takeLetters(records, '', now), isEmpty);
      expect(takeLetters(records, theirs, now), isEmpty);
      expect(written(), hasLength(2));
    });

    test('the server hands them over on one request, by the reader\'s '
        'name', () async {
      boardHolds([card, letter(t1)]);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      Future<({int status, String body})> take(String method) async {
        final request = await client.openUrl(
          method,
          base.replace(
            path: '/letters/take',
            queryParameters: {'to': theirs},
          ),
        );
        final response = await request.close();
        return (
          status: response.statusCode,
          body: await utf8.decoder.bind(response).join(),
        );
      }

      final first = await take('POST');
      expect(first.status, HttpStatus.ok);
      expect(first.body, startsWith('📨 보드에 「$theirs」 앞으로 남은 전달 1건'));
      expect(written().last, containsPair('at', kReadMark));
      expect((await take('POST')).body, isEmpty, reason: 'taken already');
      expect(written(), hasLength(3));
    });
  });

  group('the board shows the letters and keeps none', () {
    final at = DateTime.parse('2026-10-07T15:00:00');

    test('each names the card it stands in; one waiting for its 담당 says '
        'so, a read one names its readers', () {
      const readAt = '2026-10-07T12:30:00.000000';
      boardHolds([
        card,
        other,
        letter(t1),
        letter(t2, id: 'V', to: kEveryone),
        line({
          'id': 'V',
          'at': kReadMark,
          'ref': t2,
          'from': '저장',
          'ts': readAt,
        }),
      ]);
      expect(lettersShown(readBoard(records), at), [
        {
          'card': 'W',
          'title': '작업',
          'ts': t1,
          'to': theirs,
          'from': mine,
          'text': '레인이 착지했다',
          'waits': true,
          'readBy': <Object?>[],
        },
        {
          'card': 'V',
          'title': '다른 작업',
          'ts': t2,
          'to': kEveryone,
          'from': mine,
          'text': '레인이 착지했다',
          'waits': false,
          'readBy': [
            {'who': '저장', 'ts': readAt},
          ],
        },
      ]);
    });

    test('a letter that waits is shown however old; a read one for two '
        'weeks', () {
      const old = '2026-09-01T09:00:00.000000';
      const older = '2026-09-01T08:00:00.000000';
      boardHolds([
        card,
        letter(old),
        letter(older, to: '저장'),
        line({
          'id': 'W',
          'at': kReadMark,
          'ref': older,
          'from': '저장',
          'ts': '2026-09-01T10:00:00.000000',
        }),
      ]);
      expect(
        [for (final l in lettersShown(readBoard(records), at)) l['ts']],
        [old],
      );
    });

    test('in its card\'s story a letter wears whom it is for, who wrote it '
        'and whether it was read', () {
      boardHolds([card, letter(t1)]);
      final unread = renderCards(readBoard(records));
      expect(unread, contains('<span class="lgk">$kLetterStage</span>'));
      // The page spells a `/` as an entity, in a name as anywhere.
      const forTheirs = '타임라인&#47;콘티';
      expect(
        unread,
        contains('<span class="chip">$forTheirs ← 보드&#47;통합</span>'),
      );
      expect(unread, contains('<span class="chip run">안 읽음</span>'));
      expect(unread, isNot(contains('읽음 — ')));

      boardHolds([
        card,
        letter(t1),
        line({
          'id': 'W',
          'at': kReadMark,
          'ref': t1,
          'from': theirs,
          'ts': '2026-10-07T13:30:00.000000',
        }),
      ]);
      final read = renderCards(readBoard(records));
      expect(read, contains('<span class="chip ok">읽음</span>'));
      expect(read, contains('<p class="d">읽음 — $forTheirs · 10-07</p>'));
    });

    test('the page has a 「전달」 view that reads them from the board\'s '
        'answer', () {
      final script = boardScript();
      expect(script, contains("['letters','전달']"));
      expect(script, contains('DATA.letters'));
      expect(script, contains("S.view === 'letters'"));
    });
  });
}
