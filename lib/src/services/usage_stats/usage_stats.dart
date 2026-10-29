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
/// ⛔Off sends nothing at all, and neither does a build with no App Key
/// ([AptabaseClient.endpoint]).
class UsageStats {
  UsageStats({
    UsageStatsStore? store,
    AptabaseClient? client,
    required String Function() locale,
    DateTime Function() now = DateTime.now,
    Timer Function(Duration, void Function(Timer)) periodic = Timer.periodic,
  }) : _store = store,
       _client = client ?? AptabaseClient(),
       _locale = locale,
       _now = now,
       _periodic = periodic;

  /// Null (a test) keeps the answer in memory.
  final UsageStatsStore? _store;
  final AptabaseClient _client;

  /// The program language's code, read at each send.
  final String Function() _locale;
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

  /// Whether the app is in front: from its launch or a return to it, until
  /// it goes away ([reportAway]).
  bool _inFront = false;

  /// The hourly `in_use` — running exactly while it is on and the app is in
  /// front ([_keepInUse]).
  Timer? _inUse;

  bool _disposed = false;

  /// The UTC days this device was used on, as far back as [windowDays] —
  /// kept on the device, never sent; empty while off.
  List<int> _days = const [];

  Future<void> _restored = Future<void>.value();

  /// Whether this run's `app_started` went out (or was tried).
  bool _runCounted = false;

  /// Whether a `day` is on its way — a resume that lands meanwhile must not
  /// send the same day twice.
  bool _dayInFlight = false;

  /// How many times the person turned it off — a send that comes back after
  /// one must not write its day into the cleared record.
  int _turnedOff = 0;

  /// Whether the person has answered — the question at launch, or the
  /// switch in Preferences — on this device ([UsageStatsStore]).
  bool _answered = false;

  /// Reads the saved answer and record back.
  Future<void> restore() => _restored = _load();

  Future<void> _load() async {
    final answer = await _store?.load();
    if (answer == null) {
      return;
    }
    _answered = true;
    if (answer case UsageStatsOn(:final activeDays)) {
      _days = activeDays;
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
  /// it is still owed — once the saved answer is back; and the hour to the
  /// first `in_use` starts.
  Future<void> reportLaunch() async {
    _inFront = true;
    await _restored;
    _keepInUse();
    await _report(countRun: true);
  }

  /// The app is in front again: today's `day` if it is still owed — a run
  /// that crosses midnight UTC, or a send that failed earlier today — and,
  /// back from away, the hour to the next `in_use` starts again.
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

  /// Starts the hourly `in_use` when it is on and the app is in front, and
  /// stops it otherwise. One already running keeps its hour.
  void _keepInUse() {
    if (_disposed || !enabled.value || !_inFront) {
      _inUse?.cancel();
      _inUse = null;
      return;
    }
    _inUse ??= _periodic(inUseEvery, (_) => unawaited(_reportInUse()));
  }

  /// The hour's `in_use`: the event's name alone — not retried, not
  /// recorded.
  Future<void> _reportInUse() => _client.send(
    [(name: 'in_use', props: const <String, Object>{})],
    now: _now(),
    locale: _locale(),
  );

  /// The person's answer — the question's or the switch's, which is
  /// remembered either way. On reports at once — this run and today, as a
  /// launch would have; off forgets the record kept on this device.
  ///
  /// 🗣️MoArt's rule, which I-70 follows (유저 10-15 liked its return
  /// buckets): turning it off deletes the local record, so a device that
  /// comes back on is `new` again.
  void setEnabled(bool on) {
    enabled.value = on;
    _answered = true;
    if (!on) {
      _days = const [];
      _turnedOff += 1;
    }
    unawaited(_store?.save(on ? UsageStatsOn(_days) : const UsageStatsOff()));
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
    // ⚠️Off is the one gate here. A build with no App Key is the client's
    // own ([AptabaseClient.endpoint]): it posts nothing, so the day stays
    // owed and nothing is counted as sent.
    if (!enabled.value) {
      return;
    }
    final now = _now();
    final today = dayOf(now);
    // ⚖️A RUN IS COUNTED ONCE, at launch or when it is turned on during
    // it (2026-10-29, this lane): the question is asked at launch, and a
    // first launch counted only from the NEXT one would never be. Not
    // retried — a run whose `app_started` failed stays uncounted, as the
    // SDKs' own fire-and-forget would leave it.
    final start = countRun && !_runCounted;
    final day = !_dayInFlight && !_days.contains(today);
    if (!start && !day) {
      return;
    }
    _runCounted = _runCounted || start;
    _dayInFlight = _dayInFlight || day;
    final days = _days;
    final turnedOff = _turnedOff;
    final sent = await _client.send(
      [
        if (start) (name: 'app_started', props: const <String, Object>{}),
        if (day) (name: 'day', props: {'days': bucketOf(days, today)}),
      ],
      now: now,
      locale: _locale(),
    );
    if (!day) {
      return;
    }
    _dayInFlight = false;
    // ⚖️THE DAY IS WRITTEN DOWN ONLY ONCE THE SERVICE TOOK IT (2026-10-29,
    // this lane). MoArt writes it before sending and never retries; here a
    // send that failed — offline at launch, the service down — leaves the
    // day owed, and the next launch or resume the same UTC day sends it
    // again. The record is what says "sent", and it is written on a 2xx
    // alone — so only a day the service took whose answer never came back
    // is sent twice.
    if (sent && _turnedOff == turnedOff) {
      _days = [
        for (final kept in days)
          if (today - kept < windowDays) kept,
        today,
      ];
      unawaited(_store?.save(UsageStatsOn(_days)));
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
