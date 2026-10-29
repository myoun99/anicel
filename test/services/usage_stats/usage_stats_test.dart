import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/feedback/feedback_forms.dart';
import 'package:anicel/src/services/persistence/usage_stats_store.dart';
import 'package:anicel/src/services/usage_stats/aptabase_client.dart';
import 'package:anicel/src/services/usage_stats/usage_stats.dart';

/// The answer, the record and the queue kept in memory, as the settings
/// file keeps them across launches.
class _MemoryStore extends UsageStatsStore {
  /// On with [days] and [queue] — or never answered without days.
  _MemoryStore([List<int>? days, List<AptabaseStamped> queue = const []])
    : answer = days == null ? null : UsageStatsOn(days, queue),
      super(filePath: 'unused');

  /// What the file holds: null is no file.
  UsageStatsAnswer? answer;

  /// The days the file holds: none while it is off or never answered.
  List<int>? get days => switch (answer) {
    UsageStatsOn(:final activeDays) => activeDays,
    _ => null,
  };

  /// The events the file holds still to send: none while it is off or
  /// never answered.
  List<AptabaseStamped>? get queue => switch (answer) {
    UsageStatsOn(:final queue) => queue,
    _ => null,
  };

  @override
  Future<UsageStatsAnswer?> load() async => answer;

  @override
  Future<void> save(UsageStatsAnswer answer) async => this.answer = answer;
}

/// A periodic timer the test ticks by hand ([fire]).
class _Periodic implements Timer {
  _Periodic(this.every, this._onTick);

  final Duration every;
  final void Function(Timer) _onTick;
  bool _active = true;
  int _ticks = 0;

  /// One period gone by.
  void fire() {
    if (_active) {
      _ticks += 1;
      _onTick(this);
    }
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _ticks;
}

/// One POST's events, each as its name and props: `day days=3+`.
typedef _Sent = List<String>;

/// The events in a POST's [body].
List<Map<String, dynamic>> _events(String body) =>
    (jsonDecode(body) as List).cast<Map<String, dynamic>>();

/// [event] as `<name>[ <key>=<value>,…]` — less the device's language, its
/// model and the program language, which every event carries (the client's
/// tests read them).
String _said(Map<String, dynamic> event) {
  final props = {...event['props'] as Map<String, dynamic>}
    ..remove('osLocale')
    ..remove('deviceModel')
    ..remove('locale');
  return [
    event['eventName'] as String,
    if (props.isNotEmpty)
      [for (final MapEntry(:key, :value) in props.entries) '$key=$value']
          .join(','),
  ].join(' ');
}

/// 🗣️I-70 (유저 2026-10-29): opt-in, OFF by default (Q3); `app_started`
/// every launch and `day` once a UTC day with MoArt's return buckets
/// (유저 10-15) — the count on the device, only the bucket sent.
void main() {
  late List<_Sent> sent;

  /// Every POST's events as they went over the wire.
  late List<List<Map<String, dynamic>>> bodies;

  /// What the client was asked, in order: `prepare` and `post`.
  late List<String> calls;
  late int status;
  late Completer<void>? hold;
  late DateTime clock;

  /// The settings a run's shell hands in — none unless a test sets them.
  late Map<String, Object> settings;

  /// Every periodic timer a run started, the latest last.
  late List<_Periodic> timers;

  setUp(() {
    sent = [];
    bodies = [];
    calls = [];
    status = 200;
    hold = null;
    clock = DateTime.utc(2026, 10, 29, 6, 20);
    settings = const {};
    timers = [];
  });

  final today = UsageStats.dayOf(DateTime.utc(2026, 10, 29, 6, 20));

  AptabaseClient client({String appKey = 'A-EU-1462843916'}) => AptabaseClient(
    appKey: appKey,
    post: (endpoint, appKey, body) async {
      calls.add('post');
      sent.add([for (final event in _events(body)) _said(event)]);
      bodies.add(_events(body));
      await hold?.future;
      return status;
    },
    prepare: () => calls.add('prepare'),
    describe: () => (model: 'x', os: FeedbackOs.android, osVersion: '14'),
    build: '1081',
  );

  /// A periodic timer the test ticks, kept in [timers].
  Timer periodic(Duration every, void Function(Timer) onTick) {
    final timer = _Periodic(every, onTick);
    timers.add(timer);
    return timer;
  }

  /// A run of the app on [store], restored as the shell restores it.
  UsageStats run(_MemoryStore? store, {String appKey = 'A-EU-1462843916'}) {
    final stats = UsageStats(
      store: store,
      client: client(appKey: appKey),
      locale: () => 'ko',
      osLocale: () => 'ko-KR',
      settings: () => settings,
      now: () => clock,
      periodic: periodic,
    );
    addTearDown(stats.dispose);
    unawaited(stats.restore());
    return stats;
  }

  /// The periodic timers still running.
  List<_Periodic> running() => [
    for (final timer in timers)
      if (timer.isActive) timer,
  ];

  void nextDay([int days = 1]) => clock = clock.add(Duration(days: days));

  group('⛔nothing is sent', () {
    test('🎯by default — a device nobody asked is OFF, and its launches and '
        'returns send nothing', () async {
      final stats = run(_MemoryStore());
      await stats.reportLaunch();
      await stats.reportResume();
      expect(stats.enabled.value, isFalse);
      expect(sent, isEmpty);

      final unsaved = run(null);
      await unsaved.reportLaunch();
      expect(unsaved.enabled.value, isFalse);
      expect(sent, isEmpty);
    });

    test('by a build with no App Key, on or not — which queues nothing, '
        'counts no day and runs no hour', () async {
      final store = _MemoryStore([today - 1]);
      final stats = run(store, appKey: '');
      await stats.reportLaunch();
      expect(stats.enabled.value, isTrue);
      expect(store.days, [today - 1]);
      expect(store.queue, isEmpty);
      expect(timers, isEmpty);
      stats.setEnabled(false);
      stats.setEnabled(true);
      await pumpEventQueue();
      expect(sent, isEmpty);
      expect(store.queue, isEmpty);
      expect(timers, isEmpty);
    });

    test('once it is turned off', () async {
      final stats = run(_MemoryStore([today - 1]));
      await pumpEventQueue();
      expect(stats.enabled.value, isTrue);
      stats.setEnabled(false);
      await stats.reportLaunch();
      nextDay();
      await stats.reportResume();
      expect(sent, isEmpty);
    });
  });

  group('when it is on', () {
    test('🎯a launch sends app_started and today, in one POST', () async {
      final stats = run(_MemoryStore([today - 3]));
      await stats.reportLaunch();
      expect(sent, [
        [
          'app_started',
          'day days=1-2',
        ],
      ]);
    });

    test('🎯turning it on sends at once — this run, and today as new', () async {
      final store = _MemoryStore();
      final stats = run(store);
      await stats.reportLaunch();
      expect(sent, isEmpty);

      stats.setEnabled(true);
      await pumpEventQueue();
      expect(sent, [
        [
          'app_started',
          'day days=new',
        ],
      ]);
      expect(store.days, [today]);
      // On already: nothing more.
      stats.setEnabled(true);
      await pumpEventQueue();
      expect(sent, hasLength(1));
    });

    test('🎯once a UTC day: the same day again sends nothing, the next day '
        'sends its day — and the run is counted once', () async {
      final store = _MemoryStore([]);
      final stats = run(store);
      await stats.reportLaunch();
      await stats.reportResume();
      await stats.reportLaunch();
      clock = DateTime.utc(2026, 10, 29, 23, 59);
      await stats.reportResume();
      expect(sent, hasLength(1));

      clock = DateTime.utc(2026, 10, 30, 0, 1);
      await stats.reportResume();
      expect(sent, hasLength(2));
      expect(sent[1], [
        'day days=1-2',
      ]);
      expect(store.days, [today, today + 1]);
    });

    test('the next launch on the same day sends app_started alone', () async {
      final store = _MemoryStore([]);
      await run(store).reportLaunch();
      await run(store).reportLaunch();
      expect(sent, [
        [
          'app_started',
          'day days=new',
        ],
        ['app_started'],
      ]);
      expect(store.days, [today], reason: 'a launch with no day writes none');
    });

    test('a run is counted once — turned off and on again it sends no second '
        'app_started', () async {
      final stats = run(_MemoryStore([]));
      await stats.reportLaunch();
      // A run that crosses midnight UTC, and its new day.
      nextDay();
      await stats.reportResume();
      stats.setEnabled(false);
      stats.setEnabled(true);
      await pumpEventQueue();
      expect(sent, [
        ['app_started', 'day days=new'],
        ['day days=1-2'],
        ['day days=new'],
      ]);
    });

    test('🎯the settings ride on the day alone, as they read when the day is '
        'queued (유저 2026-10-29, I-70-Q8)', () async {
      settings = {'uiScale': '80%', 'accent': '#4FA8A0'};
      final stats = run(_MemoryStore([]));
      await stats.reportLaunch();
      settings = {'uiScale': '100%', 'accent': '#E05A47'};
      timers.single.fire();
      await pumpEventQueue();
      nextDay();
      await stats.reportResume();
      expect(sent, [
        ['app_started', 'day days=new,uiScale=80%,accent=#4FA8A0'],
        ['in_use'],
        ['day days=1-2,uiScale=100%,accent=#E05A47'],
      ]);
    });

    test('the program language and the device\'s are read at each send — '
        'the device\'s on every event, the hour\'s too', () async {
      var locale = 'ko';
      var osLocale = 'ja-JP';
      final stats = UsageStats(
        store: _MemoryStore([]),
        client: AptabaseClient(
          appKey: 'A-EU-1462843916',
          post: (_, _, body) async {
            sent.add([
              for (final event in _events(body))
                '${(event['systemProps'] as Map<String, dynamic>)['locale']} '
                    '${(event['props'] as Map<String, dynamic>)['osLocale']}',
            ]);
            return 200;
          },
          prepare: () {},
          describe: () => (model: 'x', os: FeedbackOs.iOS, osVersion: '18'),
        ),
        locale: () => locale,
        osLocale: () => osLocale,
        settings: () => const {},
        now: () => clock,
        periodic: periodic,
      );
      addTearDown(stats.dispose);
      unawaited(stats.restore());
      await stats.reportLaunch();
      locale = 'fr';
      osLocale = 'fr-CA';
      nextDay();
      await stats.reportResume();
      timers.single.fire();
      await pumpEventQueue();
      expect(sent, [
        ['ko ja-JP', 'ko ja-JP'],
        ['fr fr-CA'],
        ['fr fr-CA'],
      ]);
    });
  });

  group('MoArt\'s buckets', () {
    test('no record is new; a record — even an old one — is not', () {
      expect(UsageStats.bucketOf(const [], today), 'new');
      expect(UsageStats.bucketOf([today - 400], today), '1-2');
    });

    test('🎯today and one more day is 1-2; today and two more is 3+', () {
      expect(UsageStats.bucketOf([today - 1], today), '1-2');
      expect(UsageStats.bucketOf([today - 2, today - 1], today), '3+');
      expect(UsageStats.bucketOf([today - 9, today - 5, today - 1], today), '3+');
    });

    test('🎯the window is 28 days with today: 27 days back counts, 28 does '
        'not', () {
      expect(UsageStats.bucketOf([today - 27, today - 1], today), '3+');
      expect(UsageStats.bucketOf([today - 28, today - 1], today), '1-2');
      expect(UsageStats.bucketOf([today - 28, today - 27], today), '1-2');
    });

    test('the day number is the UTC day since the epoch', () {
      expect(UsageStats.dayOf(DateTime.utc(1970, 1, 1, 23, 59)), 0);
      expect(UsageStats.dayOf(DateTime.utc(1970, 1, 2)), 1);
      expect(
        UsageStats.dayOf(DateTime.utc(2026, 10, 29, 23, 59, 59, 999)),
        UsageStats.dayOf(DateTime.utc(2026, 10, 29)),
      );
      expect(UsageStats.dayOf(DateTime.utc(2026, 10, 29)), 20755);
    });

    test('🎯the record keeps the window alone, and today — on the device',
        () async {
      final store = _MemoryStore([today - 40, today - 28, today - 27]);
      await run(store).reportLaunch();
      expect(sent.single.last, 'day days=1-2');
      expect(store.days, [today - 27, today]);
    });
  });

  group('off forgets', () {
    test('🎯turning it off clears the record, and back on it is new again',
        () async {
      final store = _MemoryStore([today - 2, today - 1]);
      final stats = run(store);
      await stats.reportLaunch();
      expect(sent.single.last, 'day days=3+');
      expect(store.days, [today - 2, today - 1, today]);

      stats.setEnabled(false);
      expect(store.days, isNull);

      nextDay();
      stats.setEnabled(true);
      await pumpEventQueue();
      expect(sent.last.last, 'day days=new');
      expect(store.days, [today + 1]);
    });

    test('a day on its way when it is turned off is not written into the '
        'cleared record', () async {
      final store = _MemoryStore([today - 1]);
      final stats = run(store);
      hold = Completer<void>();
      final launch = stats.reportLaunch();
      await pumpEventQueue();
      expect(sent, hasLength(1));

      stats.setEnabled(false);
      hold!.complete();
      await launch;
      expect(store.days, isNull);

      stats.setEnabled(true);
      await pumpEventQueue();
      expect(sent.last.last, 'day days=new');
    });
  });

  group('a send that fails', () {
    test('🎯keeps its events on the device: the next return sends the same '
        'ones — no second day, no second app_started — and then nothing',
        () async {
      final store = _MemoryStore([today - 1]);
      final stats = run(store);
      status = 503;
      await stats.reportLaunch();
      expect(store.days, [today - 1, today], reason: 'counted as queued');
      expect(store.queue!.map(_said), ['app_started', 'day days=1-2']);

      status = 200;
      clock = clock.add(const Duration(minutes: 5));
      await stats.reportResume();
      expect(sent, [
        ['app_started', 'day days=1-2'],
        ['app_started', 'day days=1-2'],
      ]);
      expect(bodies[1], bodies[0], reason: 'the same events, as they were');
      expect(store.queue, isEmpty);
      expect(store.days, [today - 1, today]);

      await stats.reportResume();
      expect(sent, hasLength(2));
    });

    test('a launch that lands while a return\'s day is on its way sends '
        'app_started alone, and the day goes once', () async {
      final stats = run(_MemoryStore([]));
      hold = Completer<void>();
      // The return first, before the answer is even back.
      final resume = stats.reportResume();
      await pumpEventQueue();
      final launch = stats.reportLaunch();
      await pumpEventQueue();
      final again = stats.reportResume();
      await pumpEventQueue();
      hold!.complete();
      await Future.wait([resume, launch, again]);
      expect(sent, [
        ['day days=new'],
        ['app_started'],
      ]);
    });

    test('a return while the day is on its way sends it once', () async {
      final stats = run(_MemoryStore([]));
      hold = Completer<void>();
      final launch = stats.reportLaunch();
      await pumpEventQueue();
      await stats.reportResume();
      hold!.complete();
      await launch;
      await stats.reportResume();
      expect(sent, hasLength(1));
    });
  });

  /// 🗣️유저 2026-10-29 08:1x: 「따로 묻는 작은 창」, asked ONCE — whichever
  /// way it is answered, and wherever.
  group('the question is asked once', () {
    test('🎯a device never asked is unanswered — and off', () async {
      final stats = run(_MemoryStore());
      expect(await stats.unanswered(), isTrue);
      expect(stats.enabled.value, isFalse);
    });

    test('🎯「보내기」 and 「보내지 않기」 are both remembered: the next run is '
        'not asked, and is what was answered', () async {
      for (final yes in [true, false]) {
        final store = _MemoryStore();
        final first = run(store);
        expect(await first.unanswered(), isTrue);
        first.setEnabled(yes);
        expect(await first.unanswered(), isFalse, reason: '$yes');
        expect(
          store.answer,
          yes ? isA<UsageStatsOn>() : isA<UsageStatsOff>(),
          reason: '$yes',
        );

        final next = run(store);
        expect(await next.unanswered(), isFalse, reason: '$yes');
        expect(next.enabled.value, yes, reason: '$yes');
      }
    });

    test('a saved answer is read before it is asked about', () async {
      final store = _MemoryStore()..answer = const UsageStatsOff();
      expect(await run(store).unanswered(), isFalse);
      expect(await run(_MemoryStore([])).unanswered(), isFalse);
    });
  });

  /// 🗣️유저 2026-10-29: Aptabase's live view shows who is still using the
  /// app — an `in_use` 「1시간마다」 while it is on and in front; I-70-Q5:
  /// 「켠 동안 한 세션」, so a little under the hour.
  group('in_use, about once an hour', () {
    test('🎯on and in front: one every 55 minutes, its name alone — and '
        'none before the first is due', () async {
      final store = _MemoryStore([today - 1]);
      final stats = run(store);
      await stats.reportLaunch();
      expect(UsageStats.inUseEvery, const Duration(minutes: 55));
      expect(timers.single.every, UsageStats.inUseEvery);
      expect(sent, [
        ['app_started', 'day days=1-2'],
      ]);

      timers.single.fire();
      await pumpEventQueue();
      expect(sent.last, ['in_use']);
      timers.single.fire();
      await pumpEventQueue();
      expect(sent, hasLength(3));
      expect(sent.last, ['in_use']);
      expect(store.days, [today - 1, today], reason: 'an in_use records no day');
      expect(stats.enabled.value, isTrue);
    });

    test('🎯a run in front stays ONE session — each in_use, a second late '
        'as a timer is, comes before the last event\'s session runs out',
        () async {
      final stats = run(_MemoryStore([today - 1]));
      await stats.reportLaunch();
      for (var tick = 0; tick < 3; tick += 1) {
        clock = clock.add(UsageStats.inUseEvery + const Duration(seconds: 1));
        timers.single.fire();
        await pumpEventQueue();
      }
      expect(sent, [
        ['app_started', 'day days=1-2'],
        ['in_use'],
        ['in_use'],
        ['in_use'],
      ]);
      expect({
        for (final body in bodies)
          for (final event in body) event['sessionId'],
      }, hasLength(1));
      expect(
        UsageStats.inUseEvery + const Duration(seconds: 1),
        lessThan(AptabaseClient.sessionTimeout),
      );
    });

    test('⛔none while off — at launch, and from the moment it is turned '
        'off; turned on, the hour starts then', () async {
      final stats = run(_MemoryStore());
      await stats.reportLaunch();
      expect(timers, isEmpty);

      stats.setEnabled(true);
      await pumpEventQueue();
      expect(running(), hasLength(1));
      final hour = timers.single;

      stats.setEnabled(false);
      expect(running(), isEmpty);
      hour.fire();
      await pumpEventQueue();
      expect(sent.expand((events) => events), isNot(contains('in_use')));
    });

    test('⛔none while away; back in front, the hour starts again — and a '
        'return while still in front keeps the hour it has', () async {
      final stats = run(_MemoryStore([]));
      await stats.reportLaunch();
      final first = timers.single;

      await stats.reportResume();
      expect(timers, [first], reason: 'inactive and back: the same hour');

      stats.reportAway();
      expect(running(), isEmpty);
      first.fire();
      await pumpEventQueue();
      expect(sent, hasLength(1));

      await stats.reportResume();
      expect(running(), hasLength(1));
      expect(running().single, isNot(same(first)));
      running().single.fire();
      await pumpEventQueue();
      expect(sent.last, ['in_use']);
    });

    test('turned on before the launch is reported, the hour waits for the '
        'launch — the shell\'s report is what says the app is in front',
        () async {
      final stats = run(_MemoryStore());
      stats.setEnabled(true);
      await pumpEventQueue();
      expect(timers, isEmpty);
      await stats.reportLaunch();
      expect(running(), hasLength(1));
    });

    test('away before the saved answer is back: the launch starts no hour',
        () async {
      final stats = run(_MemoryStore([]));
      final launch = stats.reportLaunch();
      stats.reportAway();
      await launch;
      expect(stats.enabled.value, isTrue);
      expect(timers, isEmpty);
    });

    test('gone with the settings — and a launch reported after starts none',
        () async {
      final stats = UsageStats(
        store: _MemoryStore([]),
        client: client(),
        locale: () => 'ko',
        osLocale: () => 'ko-KR',
        settings: () => const {},
        now: () => clock,
        periodic: periodic,
      );
      unawaited(stats.restore());
      await stats.reportLaunch();
      expect(running(), hasLength(1));

      stats.dispose();
      expect(running(), isEmpty);
      await stats.reportLaunch();
      expect(running(), isEmpty);
    });
  });

  /// 🗣️유저 2026-10-29 08:5x: an offline queue, as the official SDKs have —
  /// kept on the device with each event's own moment and session.
  group('the queue', () {
    /// An `in_use` as it went over the wire at [at], from a run of its own.
    AptabaseStamped stampedAt(DateTime at) => client()
        .stamp(
          [(name: 'in_use', props: const <String, Object>{})],
          now: at,
          locale: 'ko',
          osLocale: 'ko-KR',
        )
        .single;

    test('🎯offline, the events wait on the device — written before the '
        'POST — and the next launch online sends them, oldest first, with '
        'their own moments and session, then its own', () async {
      final store = _MemoryStore([today - 1]);
      status = 503;
      hold = Completer<void>();
      final launch = run(store).reportLaunch();
      await pumpEventQueue();
      // Closed now, mid-send, it would keep them.
      expect(store.queue!.map(_said), ['app_started', 'day days=1-2']);
      hold!.complete();
      await launch;
      hold = null;
      final waiting = bodies.single;

      // The next launch, two hours on — online.
      status = 200;
      clock = clock.add(const Duration(hours: 2));
      await run(store).reportLaunch();
      expect(sent.last, ['app_started', 'day days=1-2', 'app_started']);
      final went = bodies.last;
      expect(went.take(2), waiting, reason: 'the same events, as they were');
      expect(went[0]['timestamp'], '2026-10-29T06:20:00.000Z');
      expect(went[2]['timestamp'], '2026-10-29T08:20:00.000Z');
      expect(went[2]['sessionId'], isNot(went[0]['sessionId']));
      expect(store.queue, isEmpty);
    });

    test('🎯nothing goes twice: a taken POST leaves the queue, and the next '
        'return, hour or launch sends only what is new', () async {
      final store = _MemoryStore([today - 1]);
      final stats = run(store);
      await stats.reportLaunch();
      await stats.reportResume();
      timers.single.fire();
      await pumpEventQueue();
      await run(store).reportLaunch();
      expect(sent, [
        ['app_started', 'day days=1-2'],
        ['in_use'],
        ['app_started'],
      ]);
      expect(store.queue, isEmpty);
    });

    test('the timer\'s in_use waits too, and goes with the next one', () async {
      final store = _MemoryStore([today - 1]);
      final stats = run(store);
      await stats.reportLaunch();
      status = 503;
      clock = clock.add(UsageStats.inUseEvery);
      timers.single.fire();
      await pumpEventQueue();
      expect(store.queue!.map(_said), ['in_use']);

      status = 200;
      clock = clock.add(UsageStats.inUseEvery);
      timers.single.fire();
      await pumpEventQueue();
      expect(sent.last, ['in_use', 'in_use']);
      expect(bodies.last.map((event) => event['timestamp']), [
        '2026-10-29T07:15:00.000Z',
        '2026-10-29T08:10:00.000Z',
      ]);
      expect(store.queue, isEmpty);
    });

    test('🎯in POSTs of 25, oldest first; one not taken keeps the rest for '
        'later', () async {
      final waiting = [
        for (var minute = 0; minute < 30; minute += 1)
          stampedAt(clock.subtract(Duration(minutes: 60 - minute))),
      ];
      final store = _MemoryStore([today - 1], waiting);
      var posts = 0;
      final stats = UsageStats(
        store: store,
        client: AptabaseClient(
          appKey: 'A-EU-1462843916',
          post: (_, _, body) async {
            bodies.add(_events(body));
            posts += 1;
            return posts == 2 ? 503 : 200;
          },
          prepare: () {},
          describe: () => (model: 'x', os: FeedbackOs.android, osVersion: '14'),
        ),
        locale: () => 'ko',
        osLocale: () => 'ko-KR',
        settings: () => const {},
        now: () => clock,
        periodic: periodic,
      );
      addTearDown(stats.dispose);
      unawaited(stats.restore());
      await stats.reportLaunch();
      expect(bodies.map((body) => body.length), [25, 7]);
      expect(bodies[0], [for (final event in waiting.take(25)) event]);
      expect(store.queue, hasLength(7));
      expect(store.queue!.first, waiting[25]);
      expect(store.queue!.map(_said).skip(5), ['app_started', 'day days=1-2']);

      await stats.reportResume();
      expect(bodies.map((body) => body.length), [25, 7, 7]);
      expect(store.queue, isEmpty);
    });

    // Aptabase refuses an event more than a day old ("Event is too old.",
    // `EventBody.IsValid`): the queue keeps no longer than the server takes.
    test('🎯more than a day old is dropped — a day to the millisecond is '
        'kept', () async {
      final day = clock.subtract(const Duration(days: 1));
      final store = _MemoryStore([today - 1], [
        stampedAt(day.subtract(const Duration(milliseconds: 1))),
        stampedAt(day),
      ]);
      status = 503;
      await run(store).reportLaunch();
      expect(store.queue!.map((event) => event['timestamp']), [
        day.toIso8601String(),
        clock.toIso8601String(),
        clock.toIso8601String(),
      ]);
    });

    test('a launch after two days offline sends only what is new', () async {
      final store = _MemoryStore([today - 1]);
      status = 503;
      await run(store).reportLaunch();
      expect(store.queue, hasLength(2));

      status = 200;
      nextDay(2);
      await run(store).reportLaunch();
      expect(sent.last, ['app_started', 'day days=3+']);
      expect(bodies.last.map((event) => event['timestamp']), [
        clock.toIso8601String(),
        clock.toIso8601String(),
      ]);
      expect(store.queue, isEmpty);
    });

    test('one whose moment cannot be read is dropped — its age is not '
        'known', () async {
      final unreadable = {...stampedAt(clock), 'timestamp': 'yesterday'};
      final store = _MemoryStore([today - 1], [unreadable]);
      status = 503;
      await run(store).reportLaunch();
      expect(store.queue!.map(_said), ['app_started', 'day days=1-2']);
    });

    test('turned on again while on keeps what waits', () async {
      final store = _MemoryStore([today - 1]);
      final stats = run(store);
      status = 503;
      await stats.reportLaunch();
      stats.setEnabled(true);
      await pumpEventQueue();
      expect(store.queue!.map(_said), ['app_started', 'day days=1-2']);
    });

    test('🎯it holds 500 at most, the oldest dropped first', () async {
      final waiting = [
        for (var second = 0; second < UsageStats.queueHolds; second += 1)
          stampedAt(
            clock.subtract(
              Duration(seconds: UsageStats.queueHolds - second),
            ),
          ),
      ];
      final store = _MemoryStore([today - 1], waiting);
      status = 503;
      await run(store).reportLaunch();
      expect(UsageStats.queueHolds, 500);
      expect(store.queue, hasLength(500));
      expect(store.queue!.first, waiting[2]);
      expect(store.queue!.map(_said).skip(498), [
        'app_started',
        'day days=1-2',
      ]);
    });

    test('⛔off clears it — nothing queued is sent after, and back on '
        'only what is new goes', () async {
      final store = _MemoryStore([today - 1]);
      final stats = run(store);
      status = 503;
      await stats.reportLaunch();
      expect(store.queue, hasLength(2));

      stats.setEnabled(false);
      expect(store.answer, isA<UsageStatsOff>());
      status = 200;
      await stats.reportResume();
      expect(sent, hasLength(1));

      stats.setEnabled(true);
      await pumpEventQueue();
      expect(sent.last, ['day days=new']);
      expect(store.queue, isEmpty);
    });

    test('a POST taken after it was turned off writes nothing back over the '
        'off', () async {
      final store = _MemoryStore([today - 1]);
      final stats = run(store);
      hold = Completer<void>();
      final launch = stats.reportLaunch();
      await pumpEventQueue();
      stats.setEnabled(false);
      hold!.complete();
      await launch;
      expect(store.answer, isA<UsageStatsOff>());
    });
  });

  /// 관제 2026-10-29: the first HTTPS of a process loads the OS's trusted
  /// roots — 20–25 ms of the event loop — so it is loaded where a stroke
  /// is not ([loadTrustedRoots]).
  group('the first connection is readied', () {
    test('🎯at launch while it is on — before anything is posted', () async {
      await run(_MemoryStore([today - 1])).reportLaunch();
      expect(calls, ['prepare', 'post']);
    });

    test('🎯offline at launch, still at launch — not in the hour that gets '
        'through', () async {
      final stats = run(_MemoryStore([today - 1]));
      status = 503;
      await stats.reportLaunch();
      status = 200;
      timers.single.fire();
      await pumpEventQueue();
      expect(calls, ['prepare', 'post', 'post']);
    });

    test('⛔not while off, nor in a build with no App Key', () async {
      await run(_MemoryStore()).reportLaunch();
      await run(_MemoryStore([today - 1]), appKey: '').reportLaunch();
      expect(calls, isEmpty);
    });

    test('turned on, at that press — before what it sends', () async {
      final stats = run(_MemoryStore());
      await stats.reportLaunch();
      stats.setEnabled(true);
      await pumpEventQueue();
      expect(calls, ['prepare', 'post']);

      stats.setEnabled(false);
      expect(calls, hasLength(2), reason: 'turned off readies nothing');
    });
  });

  test('the saved answer and record come back on the next run', () async {
    final store = _MemoryStore();
    final first = run(store);
    await first.reportLaunch();
    first.setEnabled(true);
    await pumpEventQueue();

    nextDay();
    final second = run(store);
    await second.reportLaunch();
    expect(second.enabled.value, isTrue);
    expect(sent.last, [
      'app_started',
      'day days=1-2',
    ]);
  });
}
