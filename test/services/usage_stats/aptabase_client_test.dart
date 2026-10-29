import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/feedback/feedback_forms.dart';
import 'package:anicel/src/services/usage_stats/aptabase_client.dart';

/// One POST the client made.
typedef _Post = ({Uri endpoint, String appKey, String body});

/// A [Random] that always draws [value].
class _Drawn implements Random {
  _Drawn(this.value);

  int value;

  @override
  int nextInt(int max) => value;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}

const DeviceDescription _device = (
  model: 'Surface Pro, 11th Edition',
  os: FeedbackOs.windows,
  osVersion: '11 25H2 (26200.6899)',
);

/// 🗣️I-70 (유저 2026-10-29): Aptabase receives (Q2), 「그거만 제대로 구현해도
/// 좋아」 — so what goes over the wire is the official SDKs' own: the
/// region from the App Key, a JSON array of events, and a session id —
/// whose turning over is ours (Q13).
void main() {
  late List<_Post> posts;
  late int status;
  late _Drawn random;

  setUp(() {
    posts = [];
    status = 200;
    random = _Drawn(12345678);
  });

  AptabaseClient client({String appKey = 'A-EU-1462843916'}) => AptabaseClient(
    appKey: appKey,
    post: (endpoint, appKey, body) async {
      posts.add((endpoint: endpoint, appKey: appKey, body: body));
      return status;
    },
    describe: () => _device,
    build: '1081',
    random: random,
  );

  const day = (name: 'day', props: <String, Object>{'days': '3+'});
  const started = (name: 'app_started', props: <String, Object>{});
  final now = DateTime.utc(2026, 10, 29, 6, 20);

  List<Map<String, dynamic>> sent(int index) => [
    for (final event in jsonDecode(posts[index].body) as List)
      event as Map<String, dynamic>,
  ];

  /// [events] stamped as of [now] and delivered at once.
  Future<bool> send(
    AptabaseClient it,
    List<AptabaseEvent> events, {
    required DateTime now,
    String locale = 'ko',
  }) => it.deliver(it.stamp(events, now: now, locale: locale));

  group('the App Key names the region', () {
    test('A-EU-… goes to the EU events API, A-US-… to the US one', () {
      expect(
        AptabaseClient.endpointFor('A-EU-1462843916'),
        Uri.parse('https://eu.aptabase.com/api/v0/events'),
      );
      expect(
        AptabaseClient.endpointFor('A-US-0000000001'),
        Uri.parse('https://us.aptabase.com/api/v0/events'),
      );
    });

    test('⛔any other key sends nothing — the empty one, a self-hosted or a '
        'local one, a key not in three parts', () {
      for (final key in [
        '',
        'A-SH-1462843916',
        'A-DEV-1462843916',
        'A-eu-1462843916',
        'A-EU',
        'A-EU-1462843916-2',
        'EU-1462843916',
      ]) {
        expect(AptabaseClient.endpointFor(key), isNull, reason: key);
        expect(client(appKey: key).endpoint, isNull, reason: key);
      }
    });

    test('⛔a client with no key posts nothing at all', () async {
      expect(await send(client(appKey: ''), [started], now: now), isFalse);
      expect(posts, isEmpty);
    });
  });

  group('what goes over the wire', () {
    test('🎯one POST: the App Key, and a JSON ARRAY of the events — each '
        'with exactly the SDKs\' keys', () async {
      expect(await send(client(), [started, day], now: now), isTrue);
      expect(posts, hasLength(1));
      expect(
        posts.single.endpoint,
        Uri.parse('https://eu.aptabase.com/api/v0/events'),
      );
      expect(posts.single.appKey, 'A-EU-1462843916');
      final events = sent(0);
      expect(events, hasLength(2));
      for (final event in events) {
        expect(event.keys.toSet(), {
          'timestamp',
          'sessionId',
          'eventName',
          'systemProps',
          'props',
        });
        expect(event['timestamp'], '2026-10-29T06:20:00.000Z');
        expect(
          event['sessionId'],
          '${now.millisecondsSinceEpoch ~/ 1000}12345678',
        );
        expect(event['systemProps'], {
          'isDebug': true,
          'osName': 'Windows',
          'osVersion': '11 25H2 (26200.6899)',
          'deviceModel': 'Surface Pro, 11th Edition',
          'locale': 'ko',
          'appVersion': '1081',
          'appBuildNumber': '1081',
          'sdkVersion': 'anicel@1081',
        });
      }
      // Each event's own props, and nothing added — the day's chips are its
      // own (`UsageStats`, 유저 2026-10-29 22시대).
      expect(events[0]['eventName'], 'app_started');
      expect(events[0]['props'], isEmpty);
      expect(events[1]['eventName'], 'day');
      expect(events[1]['props'], {'days': '3+'});
    });

    test('the device model the day\'s chips say is the systemProps\' own',
        () async {
      final it = client();
      await send(it, [started], now: now);
      expect(
        it.deviceModel,
        (sent(0).single['systemProps'] as Map<String, dynamic>)['deviceModel'],
      );
    });

    test('the device model is the product\'s, as the feedback forms read it '
        '— and one that could not be read says so (유저 2026-10-29 09:0x)',
        () async {
      final unread = AptabaseClient(
        appKey: 'A-EU-1462843916',
        post: (endpoint, appKey, body) async {
          posts.add((endpoint: endpoint, appKey: appKey, body: body));
          return 200;
        },
        describe: () =>
            (model: 'Unknown', os: FeedbackOs.android, osVersion: '14'),
        build: '1081',
      );
      await send(unread, [started], now: now);
      expect(
        (sent(0).single['systemProps'] as Map<String, dynamic>)['deviceModel'],
        'Unknown',
      );
    });

    test('the timestamp is UTC whatever clock the moment was read '
        'on', () async {
      // A local moment, wherever the test runs.
      final local = DateTime(2026, 10, 29, 15, 20);
      await send(client(), [day], now: local, locale: 'ja');
      expect(sent(0).single['timestamp'], local.toUtc().toIso8601String());
      expect(sent(0).single['timestamp'], endsWith('Z'));
      expect(
        (sent(0).single['systemProps'] as Map<String, dynamic>)['locale'],
        'ja',
      );
    });

    test('a 2xx is taken; anything else, or a POST that throws, is not — '
        'and never reaches the caller', () async {
      for (final (code, taken) in const [
        (200, true),
        (202, true),
        (299, true),
        (199, false),
        (300, false),
        (400, false),
        (500, false),
      ]) {
        status = code;
        expect(
          await send(client(), [day], now: now),
          taken,
          reason: '$code',
        );
      }
      final throwing = AptabaseClient(
        appKey: 'A-EU-1462843916',
        post: (_, _, _) async => throw const SocketException('offline'),
        describe: () => _device,
      );
      expect(await send(throwing, [day], now: now), isFalse);
    });
  });

  group('stamped when they happen, posted later', () {
    test('🎯an event keeps its moment and its session whatever later POST '
        'takes it — and a POST of several, oldest first, says them as they '
        'were', () async {
      final it = client();
      final first = it.stamp([started], now: now, locale: 'ko');
      random.value = 87654321;
      final later = now.add(const Duration(hours: 3));
      final second = it.stamp([day], now: later, locale: 'fr');
      expect(posts, isEmpty, reason: 'stamping posts nothing');

      expect(await it.deliver([...first, ...second]), isTrue);
      final events = sent(0);
      expect(events.map((event) => event['timestamp']), [
        '2026-10-29T06:20:00.000Z',
        '2026-10-29T09:20:00.000Z',
      ]);
      expect(events.map((event) => event['sessionId']), [
        '${now.millisecondsSinceEpoch ~/ 1000}12345678',
        '${later.millisecondsSinceEpoch ~/ 1000}87654321',
      ]);
      expect(
        events.map(
          (event) => (event['systemProps'] as Map<String, dynamic>)['locale'],
        ),
        ['ko', 'fr'],
      );
      expect(posts.single.body, jsonEncode([...first, ...second]));
    });
  });

  /// 🗣️I-70-Q13 b (유저 2026-10-29 22시대): a session takes events for 55
  /// minutes from its start, however they keep coming — Aptabase's Live
  /// lists the sessions begun within the hour.
  group('the session', () {
    test('🎯one id until 55 minutes after it began, however events keep '
        'coming — then a new one', () async {
      final it = client();
      Future<String> sendAt(DateTime at) async {
        await send(it, [day], now: at);
        return sent(posts.length - 1).single['sessionId'] as String;
      }

      final first = await sendAt(now);
      expect(first, '${now.millisecondsSinceEpoch ~/ 1000}12345678');
      expect(it.session, (id: first, startedAt: now));

      random.value = 87654321;
      expect(await sendAt(now.add(const Duration(minutes: 30))), first);
      const lasts = AptabaseClient.sessionLasts;
      final out = now.add(lasts);
      final edge = out.subtract(const Duration(milliseconds: 1));
      expect(await sendAt(edge), first);

      final second = await sendAt(out);
      expect(second, '${out.millisecondsSinceEpoch ~/ 1000}87654321');
      expect(it.session, (id: second, startedAt: out));
      expect(await sendAt(out.add(const Duration(minutes: 1))), second);
    });

    test('a new client — a new run — starts a new session, unless it goes '
        'on in one kept from before, while that one\'s 55 minutes last',
        () async {
      final kept = client();
      await send(kept, [day], now: now);
      final session = kept.session!;

      random.value = 1;
      await send(client(), [day], now: now.add(const Duration(minutes: 1)));
      expect(sent(1).single['sessionId'], isNot(session.id));

      final reopened = client()..resume(session);
      await send(reopened, [day], now: now.add(const Duration(minutes: 54)));
      expect(sent(2).single['sessionId'], session.id);
      await send(reopened, [day], now: now.add(AptabaseClient.sessionLasts));
      expect(sent(3).single['sessionId'], isNot(session.id));
    });
  });

  test('the real POST says the App Key and JSON, and carries the body as it '
      'was written', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = <({HttpHeaders headers, String body})>[];
    server.listen((request) async {
      received.add((
        headers: request.headers,
        body: await utf8.decodeStream(request),
      ));
      request.response.statusCode = 202;
      await request.response.close();
    });

    final status = await postToAptabase(
      Uri.http('127.0.0.1:${server.port}', '/api/v0/events'),
      'A-EU-1462843916',
      '[{"props":{"days":"1-2"},"locale":"한국어"}]',
    );

    expect(status, 202);
    expect(received.single.headers.value('App-Key'), 'A-EU-1462843916');
    expect(
      received.single.headers.value('Content-Type'),
      'application/json',
    );
    // Its length said up front, as the SDKs' HTTP clients say it — not
    // chunked.
    expect(
      received.single.headers.contentLength,
      utf8.encode('[{"props":{"days":"1-2"},"locale":"한국어"}]').length,
    );
    expect(
      received.single.body,
      '[{"props":{"days":"1-2"},"locale":"한국어"}]',
    );
  });
}
