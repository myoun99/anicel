import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_ask.dart';
import '../../tool/board_check.dart';
import '../../tool/board_door.dart';
import '../../tool/board_say.dart';
import '../../tool/board_server.dart';

/// 유저 2026-10-07 (card the-board-is-one-server-for-both-machines, 답 「집
/// 네트워크에서 보드 서버를 연다」): a second machine at home reads and writes
/// the same board through the server. Until that day the server had no
/// authentication, which was sound only while it listened on loopback — so
/// what this file pins is the other half of opening it: nobody who is not
/// this machine gets a byte, or writes one, without the secret, and a tool
/// that could not get in says so instead of looking like a clean board.
///
/// ⚠️ONE SERVER FOR THE WHOLE FILE. The server's records path is set once an
/// isolate; and it is bound on LOOPBACK here, handed to the real request
/// loop — a test that listened on the whole network would have the firewall
/// ask the person at the machine about the test runner. Every request is
/// treated as coming from another machine, which is the one thing a single
/// process cannot arrange for real.
void main() {
  const secret = '0123456789abcdef0123456789abcdef';
  final started = DateTime.now();
  late Directory dir;
  late File records;
  late HttpServer server;
  late Uri base;

  /// One raw request, with whatever the caller chooses to show.
  Future<({int status, String body, List<Cookie> cookies})> ask(
    String method,
    String path, {
    String? bearer,
    String? cookie,
    String? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, base.resolve(path));
      if (bearer != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      if (cookie != null) request.cookies.add(Cookie(kDoorCookie, cookie));
      if (body != null) request.add(utf8.encode(body));
      final response = await request.close();
      return (
        status: response.statusCode,
        body: await utf8.decoder.bind(response).join(),
        cookies: response.cookies,
      );
    } finally {
      client.close(force: true);
    }
  }

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('qa_board_door');
    records = File('${dir.path}/board.jsonl')
      ..writeAsStringSync(
        '${jsonEncode({
          'kind': 'item',
          'id': 'T-1',
          'title': 'the first card',
          'at': '할 일',
          'ts': '2026-10-07T00:00:00.000000',
        })}\n'
        // Its question, which is read with it.
        '${jsonEncode({
          'kind': 'decision',
          'id': 'T-1-Q1',
          'of': 'T-1',
          'at': '질문',
          'title': 'which',
          'where': 'here',
          'why': 'because',
          'options': [
            {'key': 'a', 'label': 'one', 'what': 'this', 'cost': 'none'},
            {'key': 'b', 'label': 'two', 'what': 'that', 'cost': 'some'},
          ],
          'recommend': 'a',
          'ts': '2026-10-07T00:00:00.500000',
        })}\n'
        // A word nobody reads: so the gate has something to say, and an
        // empty answer from it cannot pass for the real one.
        '${jsonEncode({
          'kind': 'item',
          'id': 'T-9',
          'bogus': 'x',
          'ts': '2026-10-07T00:00:01.000000',
        })}\n',
      );
    boardIs(
      records: records.path,
      gh: '${dir.path}/no-gh-here',
      gitRoot: dir.path,
      door: const LanDoor(secret),
      isThisMachine: (_) => false,
    );
    Directory('${dir.path}/board-shots').createSync();
    File('${dir.path}/board-shots/T-1-1.png').writeAsBytesSync([1, 2, 3]);
    File('${dir.path}/outside.png').writeAsBytesSync([9, 9, 9]);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(answerAll(server));
    base = Uri.parse('http://127.0.0.1:${server.port}');
  });

  tearDownAll(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
  });

  group('the door a launch gets', () {
    String? reading(String path) => switch (path) {
      'good' => '$secret\n',
      'short' => 'abc',
      _ => null,
    };

    test('asked for nothing, it is this machine alone — and that is no '
        'complaint', () {
      final asked = doorAsked(null, null, read: reading);
      expect(asked.door, isA<LoopbackDoor>());
      expect(asked.complaint, isNull);
    });

    test('🚨the network door exists only with its secret', () {
      final asked = doorAsked('lan', 'good', read: reading);
      expect((asked.door as LanDoor).secret, secret, reason: 'trimmed');
      expect(asked.complaint, isNull);
    });

    for (final (why, file) in [
      ('no file named', null),
      ('a file that is not there', 'gone'),
      ('a secret too short to be one', 'short'),
    ]) {
      test('🚨asked for the network with $why, it opens to this machine '
          'alone and SAYS so — never open and unlocked, never no board', () {
        final asked = doorAsked('lan', file, read: reading);
        expect(asked.door, isA<LoopbackDoor>());
        expect(asked.complaint, isNotNull);
      });
    }

    test('a place it does not know is not the network', () {
      final asked = doorAsked('everywhere', 'good', read: reading);
      expect(asked.door, isA<LoopbackDoor>());
      expect(asked.complaint, contains('everywhere'));
    });

    test('🚨the address is the door\'s: loopback alone, or every interface',
        () {
      expect(doorListensOn(const LoopbackDoor()).isLoopback, isTrue);
      expect(doorListensOn(const LanDoor(secret)), InternetAddress.anyIPv4);
    });
  });

  group('who is let in', () {
    test('this machine always — it can read the file without asking', () {
      for (final door in const [LoopbackDoor(), LanDoor(secret)]) {
        expect(
          doorAdmits(door, fromThisMachine: true, shown: null),
          isTrue,
          reason: '$door',
        );
      }
    });

    test('🚨nobody else through the loopback door, whatever they show', () {
      expect(
        doorAdmits(const LoopbackDoor(), fromThisMachine: false, shown: secret),
        isFalse,
      );
    });

    test('🚨through the network door: the secret, whole, and nothing like '
        'it', () {
      bool lets(String? shown) => doorAdmits(
        const LanDoor(secret),
        fromThisMachine: false,
        shown: shown,
      );
      expect(lets(secret), isTrue);
      expect(lets(null), isFalse);
      expect(lets(''), isFalse);
      expect(lets(secret.substring(1)), isFalse, reason: 'its tail');
      expect(lets(secret.substring(0, 31)), isFalse, reason: 'its head');
      expect(lets('${secret}0'), isFalse, reason: 'it and more');
      expect(lets(secret.toUpperCase()), isFalse);
    });
  });

  group('from another machine, without the secret', () {
    test('🚨EVERY route the server has answers 401 — read from its source, '
        'so a route added tomorrow is tried too — and nothing is written',
        () async {
      final source = File('tool/board_server.dart').readAsStringSync();
      final routes = <String>{
        '/',
        '/shot/T-1-1.png',
        for (final m in RegExp("case '(/[a-z/]+)':").allMatches(source))
          m.group(1)!,
        for (final m in RegExp("path == '(/[a-z/]+)'").allMatches(source))
          m.group(1)!,
      };
      expect(
        routes,
        containsAll(['/submit', '/tick', '/say', '/api/board', '/api/records']),
        reason: '⛔premise: the scan found the routes — an empty scan would '
            'try nothing and pass',
      );
      final before = records.readAsBytesSync();

      for (final route in routes) {
        for (final method in const ['GET', 'POST']) {
          for (final shown in const [null, 'not-the-secret']) {
            final answer = await ask(
              method,
              route,
              bearer: shown,
              body: method == 'POST' ? '{"id":"T-1","text":"x"}' : null,
            );
            expect(
              answer.status,
              HttpStatus.unauthorized,
              reason: '$method $route showing $shown',
            );
          }
        }
      }
      expect(records.readAsBytesSync(), before, reason: 'not a byte');
      expect(
        Directory('${dir.path}/board-shots').listSync(),
        hasLength(1),
        reason: 'and no shot',
      );
    });

    test('🚨what a browser is shown at the door holds nothing of the board',
        () async {
      final answer = await ask('GET', '/');
      expect(answer.status, HttpStatus.unauthorized);
      expect(answer.body, contains('id="door"'));
      expect(answer.body, isNot(contains('id="boot"')), reason: 'no data');
      expect(answer.body, isNot(contains('the first card')));
    });

    test('a wrong secret at the door gets no cookie', () async {
      final answer = await ask('POST', '/enter', body: 'not-the-secret');
      expect(answer.status, HttpStatus.unauthorized);
      expect(answer.cookies, isEmpty);
    });
  });

  group('from another machine, with the secret', () {
    test('🚨a browser shows it once and is handed the cookie that carries it '
        '— kept from scripts, and from other sites', () async {
      final entered = await ask('POST', '/enter', body: '$secret\n');
      expect(entered.status, HttpStatus.ok);
      final cookie = entered.cookies.single;
      expect(cookie.name, kDoorCookie);
      expect(cookie.httpOnly, isTrue);
      expect(cookie.sameSite, SameSite.strict);

      final back = await ask('GET', '/fresh', cookie: cookie.value);
      expect(back.status, HttpStatus.ok);
    });

    test('🚨what a session says goes through the server onto the records — '
        'whole, stamped by the server\'s clock', () async {
      final before = records.readAsLinesSync().length;
      final said = await sayToServer(BoardServer(base, secret: secret), [
        jsonEncode({'kind': 'item', 'id': 'T-2', 'note': 'from the surface'}),
        jsonEncode({'kind': 'item', 'id': 'T-2', 'at': '검증', 'how': 'look'}),
      ]);

      expect(said.refusal, isNull);
      expect(said.lines, 2);
      final lines = records.readAsLinesSync();
      expect(lines, hasLength(before + 2));
      final written = [
        for (final line in lines.skip(before))
          jsonDecode(line) as Map<String, dynamic>,
      ];
      expect(written.map((line) => line['id']), ['T-2', 'T-2']);
      expect(written.first['note'], 'from the surface');
      final stamps = [
        for (final line in written) DateTime.parse('${line['ts']}'),
      ];
      expect(stamps.first.isBefore(started), isFalse, reason: 'this clock');
      expect(stamps.last.isAfter(stamps.first), isTrue, reason: 'in order');
      expect(said.at, written.first['ts']);
    });

    test('🚨a telling the board refuses is refused through the server too, '
        'and writes nothing — it is the same function', () async {
      final before = records.readAsBytesSync();
      final said = await sayToServer(BoardServer(base, secret: secret), [
        jsonEncode({'kind': 'item', 'id': 'T-3', 'note': 'fine'}),
        jsonEncode({'kind': 'item', 'id': 'T-3', 'ts': '2030-01-01T00:00:00'}),
      ]);

      expect(said.refusal, contains('ts'));
      expect(said.lines, 0);
      expect(records.readAsBytesSync(), before);
      final raw = await ask(
        'POST',
        '/say',
        bearer: secret,
        body: '${jsonEncode({'id': 'T-3', 'ts': '2030-01-01T00:00:00'})}\n',
      );
      expect(raw.status, HttpStatus.badRequest, reason: 'and the status says '
          'so to a tool that reads nothing else');
      expect(records.readAsBytesSync(), before);
      expect(
        said.refusal,
        sayToRecords(
          File('${dir.path}/nowhere.jsonl')..writeAsStringSync(''),
          [
            jsonEncode({'kind': 'item', 'id': 'T-3', 'note': 'fine'}),
            jsonEncode({
              'kind': 'item',
              'id': 'T-3',
              'ts': '2030-01-01T00:00:00',
            }),
          ],
          DateTime.now(),
        ).refusal,
        reason: 'word for word what the file road says',
      );
    });

    test('the records are read back as the lines they are: a card\'s, or '
        'everything since a stamp — and never the whole file for nothing',
        () async {
      final server = BoardServer(base, secret: secret);
      final card = await askBoard(server, 'GET', '/api/records?id=T-1');
      expect(card.status, HttpStatus.ok);
      expect(
        [
          for (final line in const LineSplitter().convert(card.body))
            (jsonDecode(line) as Map)['id'],
        ],
        ['T-1', 'T-1-Q1'],
        reason: 'the card, and the question asked of it',
      );

      final since = await askBoard(
        server,
        'GET',
        '/api/records?since=2026-10-07T00:00:01',
      );
      expect(
        [
          for (final line in const LineSplitter().convert(since.body))
            (jsonDecode(line) as Map)['id'],
        ],
        isNot(contains('T-1')),
      );
      expect(since.body, contains('T-9'));

      final neither = await askBoard(server, 'GET', '/api/records');
      expect(neither.status, HttpStatus.badRequest);
    });

    test('🚨the gate says through the server what it says to the file',
        () async {
      final judged = await boardCheckOf(BoardServer(base, secret: secret));
      expect(judged.refusal, isNull);
      expect(judged.complaints, contains('bogus'), reason: '⛔premise: the '
          'fixture gives the gate something to say');
      expect(judged.complaints, boardCheckComplaints(records));
    });

    test('🚨a shot is a file IN the shots folder: a name that climbs out of '
        'it finds nothing', () async {
      final inside = await ask('GET', '/shot/T-1-1.png', bearer: secret);
      expect(inside.status, HttpStatus.ok);
      for (final name in ['..%2Foutside.png', '..%5Coutside.png']) {
        final outside = await ask('GET', '/shot/$name', bearer: secret);
        expect(outside.status, HttpStatus.notFound, reason: name);
      }
    });
  });

  group('a tool that could not get in says so', () {
    test('🚨without the secret a telling is REFUSED, by name of the variable '
        'that would have carried it — and nothing is written', () async {
      final before = records.readAsBytesSync();
      final said = await sayToServer(BoardServer(base), [
        jsonEncode({'kind': 'item', 'id': 'T-4', 'note': 'x'}),
      ]);
      expect(said.refusal, contains(kDoorSecretFileVariable));
      expect(records.readAsBytesSync(), before);
    });

    test('🚨a gate that was not let in DID NOT RUN — a refusal, never the '
        'empty string a clean board gives', () async {
      final judged = await boardCheckOf(BoardServer(base));
      expect(judged.refusal, isNotNull);
      final wrong = await boardCheckOf(
        BoardServer(base, secret: 'f' * kDoorSecretLength),
      );
      expect(wrong.refusal, isNotNull);
    });

    test('🚨a server that is not there is a refusal too, not a throw',
        () async {
      final gone = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final nobody = BoardServer(
        Uri.parse('http://127.0.0.1:${gone.port}'),
        secret: secret,
      );
      await gone.close(force: true);

      final said = await sayToServer(nobody, ['{"kind":"item","id":"T-5"}']);
      expect(
        said.refusal,
        contains('닿지 못했습니다'),
        reason: 'said as what it is — nobody answered — and not as an '
            'answer that could not be read',
      );
      final judged = await boardCheckOf(nobody);
      expect(judged.refusal, contains('닿지 못했습니다'));
      expect(judged.complaints, isEmpty);
    });
  });

  group('where a tool is pointed', () {
    test('an address is a server, anything else the records file', () {
      expect(boardPlaceOf('C:/x/board.jsonl'), isA<BoardFile>());
      expect(
        boardPlaceOf('http://MYOUN_HOME.local:4321', environment: const {}),
        isA<BoardServer>(),
      );
    });

    test('🚨the secret comes from the file the variable names — the variable '
        'holds a path, never the secret', () {
      final place = boardPlaceOf(
        'http://host:4321',
        environment: const {kDoorSecretFileVariable: 'the-file'},
        read: (path) => path == 'the-file' ? '$secret\r\n' : null,
      );
      expect((place as BoardServer).secret, secret);

      final none = boardPlaceOf('http://host:4321', environment: const {});
      expect((none as BoardServer).secret, isNull);
    });

    test('a server is asked, not looked for on this disk', () {
      bool onlyTheLines(String path) => path == 'lines.jsonl';
      expect(
        boardSayRefusal(['http://host:4321', 'lines.jsonl'],
            exists: onlyTheLines),
        isNull,
      );
      expect(
        boardSayRefusal(['http://host:4321', 'gone.jsonl'],
            exists: onlyTheLines),
        contains('gone.jsonl'),
      );
      expect(boardCheckRefusal(['http://host:4321'], exists: (_) => false),
          isNull);
    });

    test('🚨an empty place is said to be empty — it is what an unset '
        'variable turns into on a command line', () {
      expect(
        boardSayRefusal(['', 'lines.jsonl'], exists: (_) => true),
        contains('비었습니다'),
      );
    });

    test('board_ask takes an address and a path, and nothing else', () {
      expect(boardAskRefusal(['http://host:4321', '/api/board']), isNull);
      expect(boardAskRefusal(['board.jsonl', '/api/board']), isNotNull);
      expect(boardAskRefusal(['http://host:4321', 'api/board']), isNotNull);
      expect(boardAskRefusal(['http://host:4321']), isNotNull);
    });
  });

  group('an exe is rebuilt when ANY file it is made of changes', () {
    // `board_up.sh` and [sourcesOfEntry] follow an entry's imports ONE
    // level. The tools import each other now, so a file reached only
    // through another file would change without anything being rebuilt.
    Set<String> importsOf(String name) => {
      for (final m in RegExp(
        r"^import '([A-Za-z0-9_]+\.dart)';",
        multiLine: true,
      ).allMatches(File('tool/$name').readAsStringSync()))
        m.group(1)!,
    };

    for (final entry in const ['board_server.dart', 'board_check.dart']) {
      test('🚨everything $entry is made of is one import away from it', () {
        final near = importsOf(entry);
        expect(near, isNotEmpty, reason: '⛔premise: the scan reads imports');
        final all = <String>{...near};
        final open = [...near];
        while (open.isNotEmpty) {
          for (final further in importsOf(open.removeLast())) {
            if (all.add(further)) open.add(further);
          }
        }
        expect(all.difference({...near, entry}), isEmpty);
        expect(
          {
            for (final file in sourcesOfEntry(File('tool/$entry')))
              file.uri.pathSegments.last,
          },
          {...near, entry},
        );
      });
    }
  });
}
