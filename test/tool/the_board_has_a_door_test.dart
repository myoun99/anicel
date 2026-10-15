import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_ask.dart';
import '../../tool/board_check.dart';
import '../../tool/board_door.dart';
import '../../tool/board_say.dart';
import '../../tool/board_server.dart';
import '../helpers/temp_dir.dart';

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
    Map<String, String> saying = const {},
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, base.resolve(path));
      if (bearer != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      saying.forEach(request.headers.set);
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
    deleteTempQuietly(dir);
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

    // 🗣️card board-door-shows-what-was-typed (유저 2026-10-09, from the
    // phone: 「적어도 비밀번호 표시하는버튼있으면 틀린지아닌지 알수있을텐데」).
    // The page answered only a door that opened; every failure looked like
    // a press that did nothing. 🧪Its script was run by hand that day in the
    // app's browser with the request stood in for: the button shows and
    // hides what was typed, and 401, 403, another status and an unreachable
    // board each wrote their own line — at a phone's width, nothing wider
    // than the screen.
    test('🚨what was typed at the door can be shown, a phone keyboard keeps '
        'off it, and a door that stays shut says why — on a line whose place '
        'is there before it says anything', () async {
      final page = (await ask('GET', '/')).body;
      expect(page, contains('id="show"'));
      for (final attribute in const [
        'autocapitalize="none"',
        'autocorrect="off"',
        'spellcheck="false"',
      ]) {
        expect(page, contains(attribute));
      }
      expect(page, contains('<p id="why" role="status"></p>'));
      expect(page, contains('#why{min-height:'));
      for (final sentence in const [
        '비밀값이 맞지 않습니다.',
        '이 페이지 밖에서 온 요청으로 보였습니다(403).',
        ' 로 답했습니다.',
        '보드 서버에 닿지 못했습니다.',
        '비밀값은 맞았는데 브라우저가 열쇠(쿠키)를 남기지 않았습니다.',
      ]) {
        expect(page, contains(sentence));
      }
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
      expect(
        cookie.sameSite,
        SameSite.lax,
        reason: 'a page opened from another app is still let in (an iPhone '
            'held the key and was shown the door); a cross-site POST still '
            'carries nothing',
      );

      final back = await ask('GET', '/fresh', cookie: cookie.value);
      expect(back.status, HttpStatus.ok);
    });

    // 유저 2026-10-09, from an iPhone: the key was held (its POST carried a
    // cookie of the secret's length) and the door still said 500.
    test('🚨a browser that already holds the key and shows the secret again '
        'is answered by the door — 200 and the cookie again, 401 for a wrong '
        'one — and never by the routes (500)', () async {
      final again = await ask(
        'POST',
        '/enter',
        cookie: secret,
        body: secret,
      );
      expect(again.status, HttpStatus.ok);
      expect(again.cookies.single.sameSite, SameSite.lax);
      // A body shaped like a number, which met a JSON reader on the phone.
      final number = await ask(
        'POST',
        '/enter',
        cookie: secret,
        body: '1eae816f17f3bc5f04a868398173c6cb',
      );
      expect(number.status, HttpStatus.unauthorized);
      expect(number.cookies, isEmpty);
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

  group('a write asked by a page of another site', () {
    // 🚨Found reading the server for the door (2026-10-07, card
    // board-server-takes-posts-from-any-site): a browser sends a simple POST
    // across sites without asking, and from the machine the board is on it
    // arrives as that machine's own request. 🧪Measured that day on the
    // live server: a POST naming `Origin: https://example.com` got 200.
    bool own({String? fetchSite, String? origin}) => asksFromTheBoardItself(
      fetchSite: fetchSite,
      origin: origin,
      host: 'localhost:4321',
    );

    test('🚨a browser says where it asks from, and only the board\'s own '
        'page — or the person at the address bar — is the board\'s', () {
      expect(own(fetchSite: 'same-origin'), isTrue);
      expect(own(fetchSite: 'none'), isTrue);
      expect(own(fetchSite: 'cross-site'), isFalse);
      expect(
        own(fetchSite: 'same-site'),
        isFalse,
        reason: 'a neighbour on another port of this host is another site',
      );
      expect(
        own(fetchSite: 'cross-site', origin: 'http://localhost:4321'),
        isFalse,
        reason: 'what the browser says of the site outweighs an Origin '
            'that happens to look right',
      );
    });

    test('🚨a browser that names only an Origin has to name the very '
        'address it asked', () {
      expect(own(origin: 'http://localhost:4321'), isTrue);
      expect(own(origin: 'https://localhost:4321'), isTrue);
      expect(own(origin: 'https://example.com'), isFalse);
      expect(own(origin: 'http://localhost:3000'), isFalse);
      expect(own(origin: 'http://localhost'), isFalse);
      expect(own(origin: 'null'), isFalse, reason: 'a sandboxed page');
      expect(
        asksFromTheBoardItself(
          fetchSite: null,
          origin: 'http://localhost:4321',
          host: null,
        ),
        isFalse,
      );
    });

    test('a tool names neither, and is not a browser\'s cross-site request',
        () {
      expect(own(), isTrue);
    });

    test('🚨the server turns such a write away — 403, secret or no secret, '
        'on every route that writes — and nothing is written', () async {
      final before = records.readAsBytesSync();
      final line =
          '${jsonEncode({'kind': 'item', 'id': 'T-6', 'note': 'x'})}\n';
      for (final (route, body) in [
        ('/say', line),
        ('/submit', '{"id":"T-1","memo":"from elsewhere"}'),
        ('/intake', '{"kind":"idea","text":"from elsewhere"}'),
        ('/ack', '{"key":"T-1","why":"from elsewhere"}'),
        ('/unack', '{"key":"T-1"}'),
        ('/enter', secret),
      ]) {
        for (final saying in const [
          {'Origin': 'https://example.com'},
          {'Sec-Fetch-Site': 'cross-site'},
          {'Sec-Fetch-Site': 'same-site'},
        ]) {
          final answer = await ask(
            'POST',
            route,
            bearer: secret,
            body: body,
            saying: saying,
          );
          expect(
            answer.status,
            HttpStatus.forbidden,
            reason: '$route saying $saying',
          );
          expect(answer.cookies, isEmpty, reason: 'and no way in is handed');
        }
      }
      expect(records.readAsBytesSync(), before, reason: 'not a byte');
    });

    test('the board\'s own page and a tool still write', () async {
      final before = records.readAsLinesSync().length;
      final line =
          '${jsonEncode({'kind': 'item', 'id': 'T-7', 'note': 'x'})}\n';
      final page = await ask(
        'POST',
        '/say',
        bearer: secret,
        body: line,
        saying: {
          'Sec-Fetch-Site': 'same-origin',
          'Origin': 'http://127.0.0.1:${server.port}',
        },
      );
      expect(page.status, HttpStatus.ok);
      final olderBrowser = await ask(
        'POST',
        '/say',
        bearer: secret,
        body: line,
        saying: {'Origin': 'http://127.0.0.1:${server.port}'},
      );
      expect(olderBrowser.status, HttpStatus.ok);
      expect(records.readAsLinesSync(), hasLength(before + 2));
    });
  });

  // 유저 2026-10-09, from the phone: the right secret typed, and the door
  // said 「500」 (before the page named a reason it was a press that did
  // nothing). The server answered a request it could not make sense of with
  // an exception, and `board_up.sh` throws the exception away.
  group('a request the door cannot make sense of', () {
    /// One request to `/enter`, written by hand. ⚠️A client library folds a
    /// header sent twice into one line and encodes a body as text, so it
    /// cannot send what a proxy or a keyboard can.
    Future<({int status, bool handsAKey})> enter({
      List<String> headers = const [],
      List<int>? body,
    }) async {
      final bytes = body ?? utf8.encode(secret);
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      try {
        socket.add(
          latin1.encode(
            'POST /enter HTTP/1.1\r\n'
            'Host: 127.0.0.1:${server.port}\r\n'
            '${headers.map((h) => '$h\r\n').join()}'
            'Content-Length: ${bytes.length}\r\n'
            'Connection: close\r\n\r\n',
          ),
        );
        socket.add(bytes);
        await socket.flush();
        final reply = await socket
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .join();
        return (
          status: int.parse(reply.split(' ')[1]),
          handsAKey: reply.toLowerCase().contains('set-cookie: $kDoorCookie='),
        );
      } finally {
        socket.destroy();
      }
    }

    test('a header said twice is one value, or no value anything says', () {
      expect(oneValueOf(null), isNull);
      expect(oneValueOf(const []), isNull);
      expect(oneValueOf(const ['a']), 'a');
      expect(oneValueOf(const ['a', 'a']), 'a');
      expect(oneValueOf(const ['a', 'b']), 'a, b');
    });

    test('🚨an Origin or a Sec-Fetch-Site sent twice is answered at the door '
        '— let in when it says one thing, 403 when it says two — and never '
        'a 500', () async {
      final own = 'Origin: http://127.0.0.1:${server.port}';
      final same = await enter(headers: [own, own]);
      expect(same.status, HttpStatus.ok);
      expect(same.handsAKey, isTrue);
      final other = await enter(headers: [own, 'Origin: https://example.com']);
      expect(other.status, HttpStatus.forbidden);
      expect(other.handsAKey, isFalse);
      final site = await enter(
        headers: const [
          'Sec-Fetch-Site: same-origin',
          'Sec-Fetch-Site: same-origin',
        ],
      );
      expect(site.status, HttpStatus.ok);
      final sites = await enter(
        headers: const [
          'Sec-Fetch-Site: same-origin',
          'Sec-Fetch-Site: cross-site',
        ],
      );
      expect(sites.status, HttpStatus.forbidden);
    });

    test('🚨a body that is not text is a secret that does not match — 401, '
        'no key handed, never a 500', () async {
      for (final body in [
        [...utf8.encode(secret), 0xff, 0xfe],
        [0xc0, 0x80],
        [0xf0, 0x28, 0x8c, 0xbc],
      ]) {
        final answer = await enter(body: body);
        expect(answer.status, HttpStatus.unauthorized, reason: '$body');
        expect(answer.handsAKey, isFalse);
      }
    });

    test('a bearer shown twice is read, and does not match', () async {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      try {
        socket.add(
          latin1.encode(
            'GET /api/board HTTP/1.1\r\n'
            'Host: 127.0.0.1:${server.port}\r\n'
            'Authorization: Bearer $secret\r\n'
            'Authorization: Bearer elsewhere\r\n'
            'Connection: close\r\n\r\n',
          ),
        );
        await socket.flush();
        final reply = await socket
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .join();
        expect(reply, startsWith('HTTP/1.1 401'));
      } finally {
        socket.destroy();
      }
    });
  });

  group('what the door keeps of the secret, and of who it turned away', () {
    test('the secret is taken out of a text, wherever it stands', () {
      const door = LanDoor(secret);
      expect(
        withoutSecret(door, 'a $secret b $secret'),
        'a <secret> b <secret>',
      );
      expect(withoutSecret(door, 'nothing here'), 'nothing here');
      expect(
        withoutSecret(const LoopbackDoor(), 'a $secret'),
        'a $secret',
        reason: 'a door with no secret has none to take out',
      );
    });

    test('🚨a request the door turns away leaves a line — with whether a key '
        'came, never the key — and the secret is out of every header it '
        'names', () async {
      final log = File('${dir.path}/$kRequestFailureLog');
      if (log.existsSync()) log.deleteSync();
      await ask('GET', '/', cookie: 'a-key-that-does-not-fit');
      await ask(
        'GET',
        '/',
        saying: {'Referer': 'http://elsewhere/$secret'},
      );
      await ask('POST', '/enter', body: 'not-the-secret');
      final lines = log.readAsLinesSync();
      expect(lines, hasLength(3));
      expect(
        lines.first,
        allOf(
          contains(' GET / '),
          contains('turned away at the door (401)'),
          contains('cookie×1=<'),
        ),
      );
      expect(lines[1], contains('referer×1=http://elsewhere/<secret>'));
      expect(lines.last, contains(' POST /enter '));
      expect(log.readAsStringSync(), isNot(contains(secret)));
    });
  });

  // 🚨The server's stderr is thrown away by the script that starts it, so a
  // failed request said nothing about itself; it leaves one line instead.
  group('a request that broke the server leaves a line', () {
    String lineFor({
      Map<String, List<String>> headers = const {},
      Object error = 'FormatException: bad',
    }) => requestFailureLine(
      at: DateTime.utc(2026, 10, 9, 8, 30),
      method: 'POST',
      path: '/enter',
      from: '192.168.1.50',
      headers: headers,
      error: error,
    );

    test('it names when, what, by whom and which error', () {
      final line = lineFor();
      expect(line, startsWith('2026-10-09T08:30:00.000Z POST /enter '));
      expect(line, contains('from 192.168.1.50'));
      expect(line, contains('FormatException: bad'));
      expect(line, isNot(contains('\n')), reason: 'one line a failure');
    });

    test('🚨it says how many times each header came and what it said — a '
        'header sent twice is what a 500 at the door hid', () {
      final line = lineFor(
        headers: {
          'origin': ['http://a', 'http://b'],
          'host': ['192.168.1.6:4321'],
        },
      );
      expect(line, contains('origin×2=http://a ⏎ http://b'));
      expect(line, contains('host×1=192.168.1.6:4321'));
    });

    test('🚨a key is never written: the cookie and the bearer give their '
        'length, and the body is not in it at all', () {
      final line = lineFor(
        headers: {
          'cookie': ['board=$secret'],
          'Authorization': ['Bearer $secret'],
        },
      );
      expect(line, isNot(contains(secret)));
      expect(line, contains('cookie×1=<${'board=$secret'.length} chars>'));
      expect(
        line,
        contains('Authorization×1=<${'Bearer $secret'.length} chars>'),
      );
    });

    test('a long header is cut and a line break in one cannot make a second '
        'line', () {
      final line = lineFor(
        headers: {
          'user-agent': ['x' * 400],
          'referer': ['http://a/\r\nInjected: line'],
        },
        error: 'multi\nline',
      );
      expect(line, isNot(contains('\n')));
      expect(line, isNot(contains('x' * 200)));
    });

    test('it is appended, starts over past the ceiling, and never throws',
        () {
      final log = File('${dir.path}/failures.log');
      noteRequestFailure(log, 'one');
      noteRequestFailure(log, 'two');
      expect(log.readAsLinesSync(), ['one', 'two']);
      log.writeAsStringSync('x' * (300 * 1024));
      noteRequestFailure(log, 'three');
      expect(log.readAsLinesSync(), ['three']);
      expect(
        () => noteRequestFailure(File('${dir.path}/no/such/place.log'), 'x'),
        returnsNormally,
      );
    });

    test('🚨the request loop writes it before it answers 500', () {
      final server = File('tool/board_server.dart').readAsStringSync();
      expect(server, contains('_noteFailed(request, e);'));
      expect(
        RegExp(r'withoutSecret\(\s*_door,').hasMatch(server),
        isTrue,
        reason: 'and what it writes has the secret taken out',
      );
      expect(
        server.indexOf('_noteFailed(request, e);'),
        lessThan(server.indexOf('request.response.statusCode = 500;')),
      );
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
