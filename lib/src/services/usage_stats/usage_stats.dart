import 'dart:async';

import 'package:flutter/foundation.dart';

import '../persistence/usage_stats_store.dart';
import 'aptabase_client.dart';

/// The usage statistics (I-70): whether this device sends them, and what it
/// sends when it does — `app_started` once a run, `day` once a UTC day with
/// where the app runs and the settings it carries ([_whereItRuns],
/// [_settings]) and `in_use` as each session's time runs out while the app
/// is in front ([AptabaseClient.sessionLasts]).
///
/// 🗣️I-70 (유저 2026-10-29): Q1 「둘 다」 — downloads are counted from the
/// releases, and how many people USE the app from here; Q2 Aptabase
/// receives ([AptabaseClient]); Q3 「안내 창에서 묻고 기본 꺼짐」 — OFF until
/// the person turns it on, and turned on or off any time in Preferences:
/// ONE switch ([enabled]). ↩️Where it is asked moved (유저 08:1x, 「따로
/// 묻는 작은 창」): a window of its own at launch, while the person has never
/// answered ([unanswered]) — not a row under the launch notice's what's-new.
///
/// ⚖️EVERY EVENT GOES THROUGH A QUEUE ON THE DEVICE (유저 2026-10-29 08:5x,
/// 「as the official SDKs have」): an event is stamped when it happens — its
/// moment and its session fixed — written down, and only then posted; one
/// the service did not take (no network, a timeout, anything but a 2xx, the
/// app closed first) waits for the next launch, return, in_use or taken send,
/// and goes oldest first, [AptabaseClient.batchLimit] to a POST.
///
/// ⛔Off sends nothing at all and keeps nothing queued, and a build with no
/// App Key ([AptabaseClient.endpoint]) queues nothing either.
class UsageStats {
  UsageStats({
    UsageStatsStore? store,
    AptabaseClient? client,
    required String Function() locale,
    required String Function() osLocale,
    required Map<String, Object> Function() settings,
    DateTime Function() now = DateTime.now,
    Timer Function(Duration, void Function()) after = Timer.new,
  }) : _store = store,
       _client = client ?? AptabaseClient(),
       _locale = locale,
       _osLocale = osLocale,
       _settings = settings,
       _now = now,
       _after = after;

  /// Null (a test) keeps the answer in memory.
  final UsageStatsStore? _store;
  final AptabaseClient _client;

  /// The program language's code, read at each event.
  final String Function() _locale;

  /// The device's own language, as a BCP 47 tag (`ko-KR`), read at each
  /// day ([_whereItRuns]) — the shell reads it from the platform and
  /// hands it in.
  final String Function() _osLocale;

  /// The settings a `day` carries, each as its chip reads, read when the
  /// day is queued — the shell names which (I-70-Q8).
  final Map<String, Object> Function() _settings;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _after;

  /// Whether this device sends — OFF until the person says otherwise.
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// How far back a day still counts: 28 days, today among them.
  static const int windowDays = 28;

  /// How many days in the window make a device a regular.
  static const int regularDays = 3;

  /// ⚖️THE QUEUE'S BOUNDS (유저 2026-10-29 08:5x: a queue, bounded — as 관제
  /// relayed it). ↩️A DAY, not the week first relayed (관제's guess, 10-29):
  /// Aptabase's server refuses an event stamped more than a day before it
  /// arrives (`src/Features/Ingestion/EventBody.cs`, `IsValid`: `Timestamp <
  /// DateTime.UtcNow.AddDays(-1)` → "Event is too old."), so one kept
  /// longer is posted only to be thrown away; its batch endpoint
  /// (`EventsController.cs`) leaves such events out and still answers 200,
  /// so one that slips past this on its way is taken off the queue and
  /// jams nothing. And 500, kept: a day's ordinary use queues a few dozen
  /// (an `in_use` every [AptabaseClient.sessionLasts] is 26, each launch
  /// one more, the day one), so the day is the bound that works, and 500 —
  /// some 330 bytes an event — only keeps a day of hundreds of launches, an
  /// app that keeps failing to start, from growing the file past about
  /// 170 KB, its oldest going first.
  static const Duration queueKeeps = Duration(days: 1);
  static const int queueHolds = 500;

  /// Whether the app is in front: from its launch or a return to it, until
  /// it goes away ([reportAway]).
  bool _inFront = false;

  /// The next `in_use`, due as the session's time runs out — armed exactly
  /// while it sends and the app is in front ([_keepInUse]).
  Timer? _inUse;

  bool _disposed = false;

  /// The UTC days this device was used on, as far back as [windowDays] —
  /// kept on the device, never sent; empty while off.
  List<int> _days = const [];

  /// The events still to send, oldest first — kept on the device with
  /// [_days]; empty while off.
  List<AptabaseStamped> _queue = const [];

  /// Whether a POST is on its way — the one that is takes what is queued
  /// meanwhile, in turn.
  bool _flushing = false;

  Future<void> _restored = Future<void>.value();

  /// Whether this run's `app_started` is queued.
  bool _runCounted = false;

  /// Whether the person has answered — the question at launch, or the
  /// switch in Preferences — on this device ([UsageStatsStore]).
  bool _answered = false;

  /// On, and a build that can send at all.
  bool get _sends => enabled.value && _client.endpoint != null;

  /// Reads the saved answer, record and queue back.
  Future<void> restore() => _restored = _load();

  Future<void> _load() async {
    final answer = await _store?.load();
    if (answer == null) {
      return;
    }
    _answered = true;
    if (answer case UsageStatsOn(:final activeDays, :final queue)) {
      _days = activeDays;
      _queue = queue;
      if (answer.session case final session?) {
        _client.resume(session);
      }
      enabled.value = true;
    }
  }

  /// Whether the person has yet to answer, once the saved answer is back —
  /// what the question at launch asks of it.
  Future<bool> unanswered() async {
    await _restored;
    return !_answered;
  }

  /// The app has started: this run's `app_started`, and today's `day` if
  /// it is still owed, with whatever waits from before — once the saved
  /// answer is back; and the first `in_use` is armed.
  Future<void> reportLaunch() async {
    _inFront = true;
    await _restored;
    _prepare();
    await _report(countRun: true);
  }

  /// The first HTTPS connection's costly part, done now — at launch or as
  /// it is turned on, never inside a send that lands mid-stroke
  /// ([loadTrustedRoots] has the numbers) — and only when it sends.
  void _prepare() {
    if (_sends) {
      _client.prepare();
    }
  }

  /// The app is in front again: today's `day` if it is still owed — a run
  /// that crosses midnight UTC — with whatever waits; and, back from away,
  /// the next `in_use` is armed again — at once if the session's time ran
  /// out meanwhile.
  Future<void> reportResume() async {
    _inFront = true;
    await _restored;
    await _report(countRun: false);
  }

  /// The app is no longer in front — hidden, minimized, paused, or its
  /// window closing: no `in_use` until it is back, and an `app_away` that
  /// says when, written down before this completes — so an app that is
  /// closing keeps it for its next launch.
  ///
  /// 🗣️I-70-Q11 (유저 2026-10-29 21시대): 「닫을때도 보내게」 — on every
  /// going away, since a phone cannot tell closing from switching apps. It
  /// is the session's last event, so Aptabase's session ends where the
  /// person left. Once per going away: hidden, paused and detached come one
  /// after another.
  Future<void> reportAway() async {
    final wasInFront = _inFront;
    _inFront = false;
    _keepInUse();
    if (!wasInFront || !_sends) {
      return;
    }
    final kept = _queueUp(
      const [(name: 'app_away', props: <String, Object>{})],
      _now(),
    );
    unawaited(_flush());
    await kept;
  }

  /// Arms the next `in_use` for when the session the last event went in is
  /// out, while it sends and the app is in front, and disarms it otherwise
  /// — armed again at each report, so a session begun since is the one it
  /// counts from.
  void _keepInUse() {
    _inUse?.cancel();
    _inUse = null;
    if (_disposed || !_sends || !_inFront) {
      return;
    }
    _inUse = _after(_untilSessionEnds(), () => unawaited(_reportInUse()));
  }

  /// How long the session the last event went in still takes events — none
  /// once its [AptabaseClient.sessionLasts] are out, and a whole one with
  /// no session yet, or a clock put back before it began.
  Duration _untilSessionEnds() {
    const lasts = AptabaseClient.sessionLasts;
    final began = _client.session?.startedAt;
    final left = began == null ? lasts : began.add(lasts).difference(_now());
    if (left.isNegative) {
      return Duration.zero;
    }
    return left > lasts ? lasts : left;
  }

  /// The `in_use` due as the session's time runs out — the event's name
  /// alone, and the first of the next session — and the day's `day` if a
  /// new one began, with whatever waits; then the next is armed.
  ///
  /// ↩️THE HOUR ASKS FOR THE DAY TOO (2026-10-29 22시대, 관제 — 유저 asked
  /// 「day는 언제 측정인거지?」): a launch, a return and turning it on asked,
  /// and the hour did not, so an app left in front across midnight UTC
  /// (09:00 in Japan) said nothing of that day until it was left and come
  /// back to — and closed first, never: a day used and not counted.
  Future<void> _reportInUse() async {
    unawaited(
      _queueUp(const [(name: 'in_use', props: <String, Object>{})], _now()),
    );
    await _report(countRun: false);
  }

  /// The person's answer — the question's or the switch's, which is
  /// remembered either way. On reports at once — this run and today, as a
  /// launch would have; off forgets the record and the queue kept on this
  /// device, so nothing queued is ever sent after it.
  ///
  /// 🗣️MoArt's rule, which I-70 follows (유저 10-15 liked its return
  /// buckets): turning it off deletes the local record, so a device that
  /// comes back on is `new` again.
  void setEnabled(bool on) {
    enabled.value = on;
    _answered = true;
    if (!on) {
      _days = const [];
      _queue = const [];
    }
    unawaited(_store?.save(on ? _kept : const UsageStatsOff()));
    if (on) {
      _prepare();
      unawaited(_report(countRun: true));
    } else {
      _keepInUse();
    }
  }

  /// The UTC day [moment] falls on, counted from the epoch.
  static int dayOf(DateTime moment) =>
      moment.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  /// What a device that was used on [days] says on [today]: `new` with no
  /// record, `3+` when the last [windowDays] — today among them — hold
  /// [regularDays] or more, `1-2` otherwise.
  ///
  /// 🗣️MoArt's buckets exactly (moaang/moart, `activeDay`; 유저 10-15): the
  /// count stays on the device and only the bucket leaves it.
  static String bucketOf(List<int> days, int today) {
    if (days.isEmpty) {
      return 'new';
    }
    final recent = days.where((day) => today - day < windowDays).length + 1;
    return recent >= regularDays ? '3+' : '1-2';
  }

  Future<void> _report({required bool countRun}) async {
    if (!_sends) {
      return;
    }
    final now = _now();
    final today = dayOf(now);
    // ⚖️A RUN IS COUNTED ONCE, at launch or when it is turned on during
    // it (2026-10-29, this lane): the question is asked at launch, and a
    // first launch counted only from the NEXT one would never be. ↩️It was
    // not retried, as the SDKs' fire-and-forget left it; with the queue
    // (유저 08:5x) it waits for a send that takes it, like every event.
    final start = countRun && !_runCounted;
    // ⚖️THE DAY IS RECORDED IN THE WRITE THAT QUEUES IT (2026-10-29, this
    // lane, with the queue): the record and the queue are one file, so a
    // day is never counted without its event kept to send, and never
    // queued twice. ↩️It was written down only once the service took it,
    // so that a failed send left the day owed — the queue owes it now.
    final day = !_days.contains(today);
    if (start || day) {
      _runCounted = _runCounted || start;
      final bucket = bucketOf(_days, today);
      if (day) {
        _days = [
          for (final kept in _days)
            if (today - kept < windowDays) kept,
          today,
        ];
      }
      // ⚖️THE SETTINGS RIDE ON THE DAY (유저 2026-10-29 19:5x, I-70-Q8:
      // 「설정값은 실는거 a, 방식도 제안대로」): once a device-day, so a
      // device that opens the app often is counted once, as every other is.
      unawaited(
        _queueUp([
          if (start) (name: 'app_started', props: const <String, Object>{}),
          if (day)
            (
              name: 'day',
              props: {'days': bucket, ..._whereItRuns(), ..._settings()},
            ),
        ], now),
      );
    }
    // After the events: armed before them, it would count from a session
    // they may have ended, and come due at once.
    _keepInUse();
    await _flush();
  }

  /// Where the app runs, as chips on the `day`: the device's language, its
  /// model and the program language, read when the day is queued.
  ///
  /// ⚖️THE DEVICE'S LANGUAGE (유저 2026-10-29 09:1x): the program language
  /// is the systemProps' `locale`; the SDKs have no system prop for a
  /// second language, so the device's own is ours, under `osLocale`.
  /// 👁️WHAT IS SENT IS SHOWN (유저 18:4x, I-70-Q7: 「우리가 수집하기로한건
  /// 다 뜨게하고싶어」): Aptabase's dashboard draws a session's OS and its
  /// version, and each event's props as chips, but the device model and
  /// the program language nowhere (its source, 10-29) — so they are chips
  /// too, under the systemProps' own keys.
  ///
  /// ↩️ONCE A DAY (유저 2026-10-29 22시대): they rode every event, the
  /// hourly `in_use` too — 「이런 설정값은 처음만 보내게 … 사용중에도
  /// 보내는건 진짜 필요한거만」 — then each launch's `app_started` for a
  /// while, and then 「하루한번이면 되지않을까? … 디바이스가 같은세션에서
  /// 킬때마다 달라지는게 아니니까. 통계로 본다해도 하루한번 통계가
  /// 맞아보이고」: one device-day, counted once, as the settings are.
  Map<String, Object> _whereItRuns() => {
    'osLocale': _osLocale(),
    'deviceModel': _client.deviceModel,
    'locale': _locale(),
  };

  /// [events], stamped as of [now], onto the queue — written down with the
  /// record before anything is posted, so an app closed first keeps them;
  /// done when the writing is.
  Future<void> _queueUp(List<AptabaseEvent> events, DateTime now) {
    _queue = _keptAt(now, [
      ..._queue,
      ..._client.stamp(events, now: now, locale: _locale()),
    ]);
    return _save();
  }

  /// [queue] as of [now], less what is older than [queueKeeps] and, past
  /// [queueHolds], its oldest.
  static List<AptabaseStamped> _keptAt(
    DateTime now,
    List<AptabaseStamped> queue,
  ) {
    final since = now.subtract(queueKeeps);
    final fresh = [
      for (final event in queue)
        if (DateTime.tryParse('${event['timestamp']}')?.isBefore(since) ==
            false)
          event,
    ];
    return fresh.length > queueHolds
        ? fresh.sublist(fresh.length - queueHolds)
        : fresh;
  }

  Future<void> _save() async => _store?.save(_kept);

  /// What an on device keeps: the record, the queue, and the session the
  /// last event went in — so a run opened before its time is out goes on
  /// in it.
  UsageStatsOn get _kept => UsageStatsOn(_days, _queue, _client.session);

  /// Posts what waits, oldest first, a batch at a time, until the queue is
  /// empty or a POST is not taken — what is left waits for the next launch,
  /// return, in_use or event. Only a POST the service took leaves the queue:
  /// one whose 2xx never came back is sent again. Its callers asked
  /// [_sends] already, and off empties the queue.
  Future<void> _flush() async {
    if (_flushing) {
      return;
    }
    _flushing = true;
    try {
      while (_queue.isNotEmpty) {
        final batch = _queue.take(AptabaseClient.batchLimit).toList();
        // ⚠️Turned off while it was on its way: the queue is gone, and
        // nothing is written back over the off.
        if (!await _client.deliver(batch) || !enabled.value) {
          return;
        }
        _queue = [
          for (final event in _queue)
            if (!batch.any((sent) => identical(sent, event))) event,
        ];
        unawaited(_save());
      }
    } finally {
      _flushing = false;
    }
  }

  /// ⚠️A launch or a return whose saved answer lands after this arms no
  /// in_use: the shell reports them once the language is back, and does not
  /// ask whether it is still there.
  void dispose() {
    _disposed = true;
    _keepInUse();
    enabled.dispose();
  }
}
