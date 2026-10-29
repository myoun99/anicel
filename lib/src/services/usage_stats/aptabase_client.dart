/// The usage statistics' way out (I-70): Aptabase's event API, spoken from
/// `dart:io`.
///
/// ⚖️THE SERVICE IS APTABASE, THE CLIENT IS OURS (2026-10-29). 🗣️I-70-Q2
/// chose Aptabase to receive, and 「aptabase가 꽤 본격적이고 마음에들어서
/// 그거만 제대로 구현해도 좋아」 — so what goes over the wire is exactly what
/// the official SDKs send (aptabase_flutter 0.5.0, aptabase-python): the
/// region from the App Key, the `App-Key` header, a JSON array of events,
/// and a session id — turned over 55 minutes after it began, not after
/// their hour with no event ([AptabaseClient.sessionLasts]), and kept
/// across a reopen, which theirs is not ([AptabaseClient.resume]). ⛔Not
/// their package: aptabase_flutter reads the device and the
/// build again through device_info_plus and package_info_plus — a second
/// reader beside [DeviceDescriptions] (I-139) and [buildNumber], which is a
/// copy (CLAUDE.md 절대명령 1 · 4) — and brings shared_preferences and
/// universal_io along: four plugins on six platforms for one POST.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode;

import '../../core/build_stamp.dart';
import '../../native/device_description.dart';
import '../feedback/feedback_forms.dart' show DeviceDescription;

/// The define `tool/release_build.sh` passes the App Key in, spelled again
/// there; `every_release_build_is_stamped_one_way_test.dart` reads both.
const String aptabaseKeyDefine = 'ANICEL_APTABASE_KEY';

/// ⚠️EMPTY IN EVERY BUILD BUT A RELEASE: the script is the only place that
/// passes it, so a build from the IDE, Android Studio or a test can never
/// send — that is the one condition, not a second "is this stamped" gate.
const String _definedKey = String.fromEnvironment(aptabaseKeyDefine);

/// One event: its name and its own properties.
typedef AptabaseEvent = ({String name, Map<String, Object> props});

/// One event as it goes over the wire ([AptabaseClient.stamp]) — its
/// moment and its session fixed when it happened, so one that waits on the
/// device for a later send keeps both.
typedef AptabaseStamped = Map<String, Object?>;

/// A session as a run leaves it: its id and when it began
/// ([AptabaseClient.resume]).
typedef AptabaseSession = ({String id, DateTime startedAt});

/// The network half: POSTs [body] to [endpoint] under [appKey] and answers
/// the response's status code. A test hands one in — no test reaches the
/// network.
typedef AptabasePost =
    Future<int> Function(Uri endpoint, String appKey, String body);

/// Sends [AptabaseEvent]s to the region its App Key names.
final class AptabaseClient {
  AptabaseClient({
    this.appKey = _definedKey,
    AptabasePost post = postToAptabase,
    void Function() prepare = loadTrustedRoots,
    DeviceDescription Function() describe = DeviceDescriptions.read,
    this.build = buildNumber,
    Random? random,
  }) : endpoint = endpointFor(appKey),
       _post = post,
       _prepare = prepare,
       _describe = describe,
       _random = random ?? Random();

  final String appKey;

  /// Where events go — null when [appKey] names no region, and then
  /// nothing is ever sent.
  final Uri? endpoint;

  /// The round's number the events name the app's version by.
  final String build;

  final AptabasePost _post;
  final void Function() _prepare;
  final DeviceDescription Function() _describe;
  final Random _random;

  /// Readies what the first HTTPS connection needs ([loadTrustedRoots]) —
  /// now, at a moment the caller chooses, rather than inside the first
  /// POST that gets through.
  void prepare() => _prepare();

  /// The events API of the region in [appKey] — `A-EU-…` or `A-US-…`,
  /// three parts — or null for any other key, the empty one included.
  ///
  /// ⚠️The SDKs also know `SH` (self-hosted, with a host of its own) and
  /// `DEV` (a local server); neither is ours, so neither sends.
  static Uri? endpointFor(String appKey) {
    final parts = appKey.split('-');
    if (parts.length != 3) {
      return null;
    }
    final host = switch (parts[1]) {
      'EU' => 'eu.aptabase.com',
      'US' => 'us.aptabase.com',
      _ => null,
    };
    return host == null ? null : Uri.https(host, '/api/v0/events');
  }

  /// How long a session takes events after it began: the first event past
  /// it begins the next — and the app's `in_use` comes due then
  /// (`UsageStats`), so a run in front is a new session every 55 minutes.
  ///
  /// ⚖️A SESSION LASTS 55 MINUTES AT MOST (유저 2026-10-29 22시대, I-70-Q13
  /// b: 「그럼 b로하자 … 중요한건 하루몇대, 실시간사용중 수」): Aptabase's
  /// Live view lists the sessions that BEGAN within the last hour (its
  /// server's `live_sessions__v1.pipe` and `live_geo__v1.pipe`: `HAVING
  /// StartedAt >= now() - interval 1 hour`), so a session held for as long
  /// as the app was used showed in Live for its first hour alone. Begun
  /// again before the hour is out, a device in use is always in Live — the
  /// pros' real-time, whoever was active lately. How many devices a day is
  /// the `day`'s count, not Aptabase's users (its user is the connection's
  /// IP, made again each session).
  ///
  /// ↩️It was the SDKs' rule — a new session after an hour with no event
  /// (aptabase_flutter `_sessionTimeout`) — with an `in_use` every 55
  /// minutes to keep a run in front ONE session (I-70-Q5, 유저 10-29 11시:
  /// 「켠 동안 한 세션」). An hour with no event is past 55 minutes from the
  /// start too, so that rule had nothing left to say, and went.
  ///
  /// 🗣️The `in_use`: 유저 2026-10-29, 「1시간마다」 over 30 minutes. ↩️55,
  /// not 60 (asked again at Q13: 「1시간마다는 안좋던가」): at 60 a session
  /// leaves Live the moment the next is due, and a timer that fires late or
  /// a send still on its way blinks the device out; five minutes keep it
  /// in, for about 9% more events.
  static const Duration sessionLasts = Duration(minutes: 55);

  late String _sessionId;
  DateTime? _startedAt;

  /// The session [now] belongs to — the one before it unless that began
  /// [sessionLasts] ago or more.
  ///
  /// ↩️IT OUTLIVES THE RUN (유저 2026-10-29 20:5x, I-70-Q10: 「1시간 안에
  /// 다시 열면 같은 세션」): Aptabase makes its user from the connection's
  /// IP and User-Agent once a session and keeps it on that session, so an
  /// app closed and opened again began a new session — and a new person,
  /// whenever the IP had turned over meanwhile. It was held in memory
  /// only, as the SDKs hold it; now a run keeps it ([session]) and the next
  /// goes on in it ([resume]) — within its [sessionLasts], since Q13. Still
  /// no id beyond the session's.
  String _sessionAt(DateTime now) {
    final began = _startedAt;
    if (began == null || now.difference(began) >= sessionLasts) {
      _sessionId = _newSessionId(now);
      _startedAt = now;
    }
    return _sessionId;
  }

  /// The session the last event was stamped in and when it began — null
  /// before any event.
  AptabaseSession? get session {
    final began = _startedAt;
    return began == null ? null : (id: _sessionId, startedAt: began);
  }

  /// Goes on in [kept], a session an earlier run left: the next event joins
  /// it unless [sessionLasts] have passed since it began ([_sessionAt]).
  void resume(AptabaseSession kept) {
    _sessionId = kept.id;
    _startedAt = kept.startedAt;
  }

  /// The SDKs' id: the epoch in seconds, eight random digits after it.
  String _newSessionId(DateTime now) {
    final seconds = now.millisecondsSinceEpoch ~/ 1000;
    return '${seconds * 100000000 + _random.nextInt(100000000)}';
  }

  /// The most events one POST carries — 관제 relayed 25 with the queue
  /// (유저 2026-10-29 08:5x), and a queue sends in POSTs of this many.
  static const int batchLimit = 25;

  /// POSTs [stamped] as one batch; answers whether the service took them
  /// (a 2xx).
  ///
  /// ⚠️Never throws: a send that fails — offline, refused, too slow — is
  /// false, and nothing else (no dialog, no log). A client with no
  /// [endpoint] posts nothing and answers false.
  Future<bool> deliver(List<AptabaseStamped> stamped) async {
    final to = endpoint;
    if (to == null) {
      return false;
    }
    try {
      final status = await _post(to, appKey, jsonEncode(stamped));
      return status >= 200 && status < 300;
    } on Object {
      return false;
    }
  }

  /// The device's product model, as [stamp]'s systemProps say it — for the
  /// day's own chips (`UsageStats`).
  String get deviceModel => _describe().model;

  /// [events] as of [now], as they go over the wire: the app speaking
  /// [locale], in the session [now] belongs to, each with its own props.
  List<AptabaseStamped> stamp(
    List<AptabaseEvent> events, {
    required DateTime now,
    required String locale,
  }) {
    final device = _describe();
    final timestamp = now.toUtc().toIso8601String();
    final sessionId = _sessionAt(now);
    // ⛔No id beyond the session's.
    //
    // ↩️THE DEVICE MODEL GOES (유저 2026-10-29 09:0x): the product model the
    // feedback forms already read — `Microsoft Corporation Surface Pro,
    // 11th Edition`, `iPad13,4`, `samsung SM-X710`, or `Unknown` — under
    // the SDKs' own key; never the name the person gave the device. It
    // stayed out at first because the forms of I-139 asked for it and these
    // statistics did not.
    final systemProps = <String, Object>{
      'isDebug': kDebugMode,
      'osName': device.os.choice,
      'osVersion': device.osVersion,
      'deviceModel': device.model,
      'locale': locale,
      'appVersion': build,
      'appBuildNumber': build,
      'sdkVersion': 'anicel@$build',
    };
    // ⚖️THE SYSTEMPROPS RIDE EVERY EVENT, AS THE SDKs SEND THEM — the
    // envelope Aptabase reads each event by. The chips that say the same
    // where its dashboard draws them are the day's own (`UsageStats`).
    return [
      for (final event in events)
        {
          'timestamp': timestamp,
          'sessionId': sessionId,
          'eventName': event.name,
          'systemProps': systemProps,
          'props': event.props,
        },
    ];
  }
}

/// How long one step of a send may take before it is given up.
const Duration _sendTimeout = Duration(seconds: 10);

/// Loads the trusted roots every HTTPS connection of this process checks
/// against — the OS's store, once per process — as the first
/// [postToAptabase] would.
///
/// ⚖️MEASURED BEFORE IT WAS MOVED (관제 2026-10-29, the main PC, an AOT
/// exe timing the event loop's worst stall): the first
/// `SecurityContext.defaultContext` of a process stalls the loop 20–25 ms
/// (Windows' root store), 3 runs of 3; touched first, the first HTTPS
/// stalls ~1 ms, and any round trip 0.4–1.5 ms (`jsonEncode` of 500
/// queued events 0.85 ms). The first POST is normally the launch's — but
/// offline at launch the connection fails before TLS, and the load lands
/// on the first POST that gets through: an hour's `in_use` or a return,
/// perhaps mid-stroke — one or two frames, on the old tablets the app is
/// for (`UsageStats` loads it at launch, and when it is turned on).
void loadTrustedRoots() => SecurityContext.defaultContext;

/// The real [AptabasePost]: an HTTPS POST through `dart:io`.
Future<int> postToAptabase(Uri endpoint, String appKey, String body) async {
  final client = HttpClient()..connectionTimeout = _sendTimeout;
  try {
    final request = await client.postUrl(endpoint).timeout(_sendTimeout);
    final bytes = utf8.encode(body);
    request.headers
      ..set('App-Key', appKey, preserveHeaderCase: true)
      ..set('Content-Type', 'application/json', preserveHeaderCase: true);
    request
      ..contentLength = bytes.length
      ..add(bytes);
    final response = await request.close().timeout(_sendTimeout);
    await response.drain<void>().timeout(_sendTimeout);
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}
