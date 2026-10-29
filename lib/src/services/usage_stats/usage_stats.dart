import 'dart:async';

import 'package:flutter/foundation.dart';

import '../persistence/usage_stats_store.dart';
import 'aptabase_client.dart';

/// The usage statistics (I-70): whether this device sends them, and what it
/// sends when it does — `app_started` once a run, `day` once a UTC day and
/// `in_use` once an hour while the app is in front.
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
/// app closed first) waits for the next launch, return, hour or taken send,
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
    DateTime Function() now = DateTime.now,
    Timer Function(Duration, void Function(Timer)) periodic = Timer.periodic,
  }) : _store = store,
       _client = client ?? AptabaseClient(),
       _locale = locale,
       _osLocale = osLocale,
       _now = now,
       _periodic = periodic;

  /// Null (a test) keeps the answer in memory.
  final UsageStatsStore? _store;
  final AptabaseClient _client;

  /// The program language's code, read at each event.
  final String Function() _locale;

  /// The device's own language, as a BCP 47 tag (`ko-KR`), read at each
  /// event — the shell reads it from the platform and hands it in.
  final String Function() _osLocale;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function(Timer)) _periodic;

  /// Whether this device sends — OFF until the person says otherwise.
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// How far back a day still counts: 28 days, today among them.
  static const int windowDays = 28;

  /// How many days in the window make a device a regular.
  static const int regularDays = 3;

  /// How often a device says it is still in use while the app is in front.
  ///
  /// 🗣️유저 2026-10-29: Aptabase's live view should show the people still
  /// using the app — 「1시간마다」, chosen over 30 minutes.
  static const Duration inUseEvery = Duration(hours: 1);

  /// ⚖️THE QUEUE'S BOUNDS (유저 2026-10-29 08:5x, as 관제 relayed them —
  /// 「drop events older than 7 days and keep at most ~500」): an event a
  /// week old is past what the live view and the day counts are for, so it
  /// is dropped; and 500 — far above a week of an hour's `in_use` and each
  /// launch's two — is the ceiling that keeps the file small whatever
  /// happens, the oldest going first.
  static const Duration queueKeeps = Duration(days: 7);
  static const int queueHolds = 500;

  /// Whether the app is in front: from its launch or a return to it, until
  /// it goes away ([reportAway]).
  bool _inFront = false;

  /// The hourly `in_use` — running exactly while it sends and the app is in
  /// front ([_keepInUse]).
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
  /// answer is back; and the hour to the first `in_use` starts.
  Future<void> reportLaunch() async {
    _inFront = true;
    await _restored;
    _keepInUse();
    await _report(countRun: true);
  }

  /// The app is in front again: today's `day` if it is still owed — a run
  /// that crosses midnight UTC — with whatever waits; and, back from away,
  /// the hour to the next `in_use` starts again.
  Future<void> reportResume() async {
    _inFront = true;
    await _restored;
    _keepInUse();
    await _report(countRun: false);
  }

  /// The app is no longer in front — hidden, minimized, paused: no
  /// `in_use` until it is back.
  void reportAway() {
    _inFront = false;
    _keepInUse();
  }

  /// Starts the hourly `in_use` when it sends and the app is in front, and
  /// stops it otherwise. One already running keeps its hour.
  void _keepInUse() {
    if (_disposed || !_sends || !_inFront) {
      _inUse?.cancel();
      _inUse = null;
      return;
    }
    _inUse ??= _periodic(inUseEvery, (_) => unawaited(_reportInUse()));
  }

  /// The hour's `in_use` — the event's name alone — with whatever waits.
  Future<void> _reportInUse() async {
    _queueUp(const [(name: 'in_use', props: <String, Object>{})], _now());
    await _flush();
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
    unawaited(
      _store?.save(on ? UsageStatsOn(_days, _queue) : const UsageStatsOff()),
    );
    _keepInUse();
    if (on) {
      unawaited(_report(countRun: true));
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
      _queueUp([
        if (start) (name: 'app_started', props: const <String, Object>{}),
        if (day) (name: 'day', props: {'days': bucket}),
      ], now);
    }
    await _flush();
  }

  /// [events], stamped as of [now], onto the queue — written down with the
  /// record before anything is posted, so an app closed first keeps them.
  void _queueUp(List<AptabaseEvent> events, DateTime now) {
    _queue = _keptAt(now, [
      ..._queue,
      ..._client.stamp(
        events,
        now: now,
        locale: _locale(),
        osLocale: _osLocale(),
      ),
    ]);
    _save();
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

  void _save() => unawaited(_store?.save(UsageStatsOn(_days, _queue)));

  /// Posts what waits, oldest first, a batch at a time, until the queue is
  /// empty or a POST is not taken — what is left waits for the next launch,
  /// return, hour or event. Only a POST the service took leaves the queue:
  /// one whose 2xx never came back is sent again.
  Future<void> _flush() async {
    if (_flushing) {
      return;
    }
    _flushing = true;
    try {
      while (_sends && _queue.isNotEmpty) {
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
        _save();
      }
    } finally {
      _flushing = false;
    }
  }

  /// ⚠️A launch or a return whose saved answer lands after this starts no
  /// hour: the shell reports them once the language is back, and does not
  /// ask whether it is still there.
  void dispose() {
    _disposed = true;
    _keepInUse();
    enabled.dispose();
  }
}
