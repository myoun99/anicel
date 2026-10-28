import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/feedback/feedback_forms.dart';
import 'package:anicel/src/services/persistence/usage_stats_store.dart';
import 'package:anicel/src/services/usage_stats/aptabase_client.dart';
import 'package:anicel/src/services/usage_stats/usage_stats.dart';

/// The answer and the record kept in memory, as the settings file keeps
/// them across launches.
class _MemoryStore extends UsageStatsStore {
  _MemoryStore([this.days]) : super(filePath: 'unused');

  /// What the file holds: null is off.
  List<int>? days;

  @override
  Future<List<int>?> load() async => days;

  @override
  Future<void> save(List<int>? activeDays) async => days = activeDays;
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

/// [event] as `<name>[ <key>=<value>,…]`.
String _said(Map<String, dynamic> event) {
  final props = event['props'] as Map<String, dynamic>;
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
  late int status;
  late Completer<void>? hold;
  late DateTime clock;

  /// Every periodic timer a run started, the latest last.
  late List<_Periodic> timers;

  setUp(() {
    sent = [];
    status = 200;
    hold = null;
    clock = DateTime.utc(2026, 10, 29, 6, 20);
    timers = [];
  });

  final today = UsageStats.dayOf(DateTime.utc(2026, 10, 29, 6, 20));

  AptabaseClient client({String appKey = 'A-EU-1462843916'}) => AptabaseClient(
    appKey: appKey,
    post: (endpoint, appKey, body) async {
      sent.add([for (final event in _events(body)) _said(event)]);
      await hold?.future;
      return status;
    },
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

    test('by a build with no App Key, on or not', () async {
      final store = _MemoryStore([today - 1]);
      final stats = run(store, appKey: '');
      await stats.reportLaunch();
      expect(stats.enabled.value, isTrue);
      stats.setEnabled(false);
      stats.setEnabled(true);
      await pumpEventQueue();
      expect(sent, isEmpty);
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

    test('the program language is read at each send', () async {
      var locale = 'ko';
      final stats = UsageStats(
        store: _MemoryStore([]),
        client: AptabaseClient(
          appKey: 'A-EU-1462843916',
          post: (_, _, body) async {
            sent.add([
              for (final event in _events(body))
                (event['systemProps'] as Map<String, dynamic>)['locale']
                    as String,
            ]);
            return 200;
          },
          describe: () => (model: 'x', os: FeedbackOs.iOS, osVersion: '18'),
        ),
        locale: () => locale,
        now: () => clock,
      );
      addTearDown(stats.dispose);
      unawaited(stats.restore());
      await stats.reportLaunch();
      locale = 'fr';
      nextDay();
      await stats.reportResume();
      expect(sent.map((events) => events.first), ['ko', 'fr']);
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
    test('🎯leaves the day owed: the next return the same day sends it '
        'again, and no second app_started', () async {
      final store = _MemoryStore([today - 1]);
      final stats = run(store);
      status = 503;
      await stats.reportLaunch();
      expect(store.days, [today - 1]);

      status = 200;
      await stats.reportResume();
      expect(sent, [
        [
          'app_started',
          'day days=1-2',
        ],
        [
          'day days=1-2',
        ],
      ]);
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

  /// 🗣️유저 2026-10-29: Aptabase's live view shows who is still using the
  /// app — an `in_use` 「1시간마다」 while it is on and in front.
  group('in_use, once an hour', () {
    test('🎯on and in front: one every hour, its name alone — and none '
        'before the first hour is up', () async {
      final store = _MemoryStore([today - 1]);
      final stats = run(store);
      await stats.reportLaunch();
      expect(UsageStats.inUseEvery, const Duration(hours: 1));
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
