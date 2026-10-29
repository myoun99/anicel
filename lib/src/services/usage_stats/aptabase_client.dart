/// The usage statistics' way out (I-70): Aptabase's event API, spoken from
/// `dart:io`.
///
/// ⚖️THE SERVICE IS APTABASE, THE CLIENT IS OURS (2026-10-29). 🗣️I-70-Q2
/// chose Aptabase to receive, and 「aptabase가 꽤 본격적이고 마음에들어서
/// 그거만 제대로 구현해도 좋아」 — so what goes over the wire is exactly what
/// the official SDKs send (aptabase_flutter 0.5.0, aptabase-python): the
/// region from the App Key, the `App-Key` header, a JSON array of events,
/// and a session id that lives in memory and turns over after an hour with
/// no event. ⛔Not their package: aptabase_flutter reads the device and the
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

  /// How long a session lasts with no event in it: the SDKs' own
  /// (aptabase_flutter `_sessionTimeout`).
  static const Duration sessionTimeout = Duration(hours: 1);

  late String _sessionId;
  DateTime? _lastEventAt;

  /// The session [now] belongs to — the one before it unless that saw no
  /// event for longer than [sessionTimeout]. Held in memory only: a new run
  /// is a new session.
  String _sessionAt(DateTime now) {
    final last = _lastEventAt;
    if (last == null || now.difference(last) > sessionTimeout) {
      _sessionId = _newSessionId(now);
    }
    _lastEventAt = now;
    return _sessionId;
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

  /// [events] as of [now], as they go over the wire: the app speaking
  /// [locale] on a device set to [osLocale], in the session [now] belongs
  /// to.
  List<AptabaseStamped> stamp(
    List<AptabaseEvent> events, {
    required DateTime now,
    required String locale,
    required String osLocale,
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
    // ⚖️THE DEVICE'S LANGUAGE IS A PROP OF EVERY EVENT (유저 2026-10-29
    // 09:1x): `locale` stays the program language, as it was, and the
    // device's own goes beside it — the SDKs have no system prop for a
    // second language, so it is ours, under `osLocale`, on every event.
    //
    // 👁️WHAT IS SENT IS SHOWN (유저 2026-10-29 18:4x, I-70-Q7: 「우리가
    // 수집하기로한건 다 뜨게하고싶어」): Aptabase's dashboard draws a
    // session's OS and its version, and every event's props as chips, but
    // the device model and the program language nowhere — its widgets, its
    // session timeline and its CSV export all leave `device_model` and
    // `locale` out (its source, 10-29). So those two ride in every event's
    // props as well, under the systemProps' own keys, beside `osLocale`.
    return [
      for (final event in events)
        {
          'timestamp': timestamp,
          'sessionId': sessionId,
          'eventName': event.name,
          'systemProps': systemProps,
          'props': {
            ...event.props,
            'osLocale': osLocale,
            'deviceModel': device.model,
            'locale': locale,
          },
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
