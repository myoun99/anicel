import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_refusals.dart';

import '../helpers/the_apps_engine_let_go.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
/// 않고 새 장치를 열어 사본으로 되살린다」 — the first refusal heard of a
/// device that is gone is where the app learns that it went
/// ([EngineRefusals]): it opens another engine in its place, once a
/// device, and says that the device started again and why
/// (🗣️a-lost-gpu-device-keeps-the-unsaved-tiles-Q1, 유저 2026-11-11) in
/// place of a refusal.
///
/// Told as a refusal is — 🗣️gpu-canonical-store-Q14: once a cause — are a
/// device that goes within a minute of the last opening (⚖️브러시/렌더링's
/// bound, a-lost-gpu-device-keeps-the-unsaved-tiles-Q2 asks) and one in
/// whose place no engine stands.
///
/// How the app opens one is stood in for ([EngineRefusals.install]): the
/// launch's own path is pinned where a session goes on by it
/// (`a_session_goes_on_once_the_app_opens_another_engine_test.dart`).
///
/// On the app's own engine, which each test loses: the one after it finds
/// the next.
void main() {
  late int tellings;
  late int startedAgain;
  late int asked;
  late DateTime now;
  void countATelling() => tellings += 1;
  void countAStart() => startedAgain += 1;

  setUp(() {
    (tellings, startedAgain, asked) = (0, 0, 0);
    now = DateTime(2026, 11, 13, 12);
    final reported = FlutterError.onError;
    final uncaught = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = reported;
      PlatformDispatcher.instance.onError = uncaught;
      EngineRefusals.told.removeListener(countATelling);
      EngineRefusals.openedAnother.removeListener(countAStart);
      EngineRefusals.debugClockOverride = null;
      EngineRefusals.debugForget();
      // No test leaves the app on a device that is gone.
      letTheGoneAppGpuEngineGo();
    });
    FlutterError.onError = (_) {};
    PlatformDispatcher.instance.onError = (_, _) => true;
    EngineRefusals.debugClockOverride = () => now;
    EngineRefusals.told.addListener(countATelling);
    EngineRefusals.openedAnother.addListener(countAStart);
  });

  /// Both doors watched, the app opening another engine as [open] does —
  /// once the one that is gone is let go, as the launch's path lets it.
  void opening(Future<void> Function() open) => EngineRefusals.install(
    openAnother: () {
      asked += 1;
      letTheGoneAppGpuEngineGo();
      return open();
    },
  );

  /// The app's device gone for want of memory — the one cause a test can
  /// name — and the word of it heard already.
  GpuEngine theAppsDeviceGone() {
    final gone = appGpuEngine..debugLose(forMemory: true);
    expect(appGpuEngineIsGone, isTrue, reason: '⛔premise: it is gone');
    return gone;
  }

  void report(Object refused) =>
      FlutterError.reportError(FlutterErrorDetails(exception: refused));

  /// [refused] reported as what caught it reports it, and all it set off
  /// through.
  Future<void> heard(Object refused) async {
    report(refused);
    await pumpEventQueue();
  }

  test('the first refusal heard of a device that is gone opens another '
      'engine in its place — once, after the turn it is heard in — and '
      'the app says that it stands on it, and why the one before went: no '
      'refusal is told, nor of what is refused meanwhile', () async {
    final mayStand = Completer<void>();
    opening(() async {
      await mayStand.future;
      await openAppGpuEngine();
    });
    final gone = theAppsDeviceGone();

    report(GpuReadFailed('a read'));
    expect(asked, 0, reason: 'heard in a paint, as well');
    await null;
    expect(asked, 1);
    expect(isTheAppsEngine(gone), isFalse, reason: '⛔premise: let go');

    // What was on its way on the engine let go is refused as it ends, at
    // either door: that one loss.
    await heard(GpuRefused('a landing'));
    PlatformDispatcher.instance.onError!(
      GpuReadFailed('a copy'),
      StackTrace.empty,
    );
    await pumpEventQueue();
    expect(asked, 1);
    expect(startedAgain, 0, reason: 'not before it stands');

    mayStand.complete();
    await untilTheNextIsOpen();
    expect(startedAgain, 1);
    expect(
      EngineRefusals.wentBy,
      GpuDeviceWent.memory,
      reason: 'asked of the engine that went, before it was let go',
    );
    expect(tellings, 0);

    // The device the app stands on is there: what it refuses is told.
    await heard(GpuRefused('no room'));
    expect((asked, startedAgain, tellings), (1, 1, 1));
  });

  test('a device that goes within a minute of that opening is told as a '
      'refusal is — one cause, whatever is refused for it, and a cause of '
      'its own — and the app opens none more for it till the minute is '
      'through; the cause is told of the next device again', () async {
    opening(openAppGpuEngine);
    await heard(GpuReadFailed('a read the device refused'));
    expect(tellings, 1, reason: '⛔premise: a cause by its type');

    theAppsDeviceGone();
    await heardTillTheNextIsOpen(GpuReadFailed('a read'));
    expect((asked, startedAgain, tellings), (1, 1, 1));

    now = now.add(
      EngineRefusals.openAnotherApart - const Duration(seconds: 1),
    );
    final lost = theAppsEngineLost();
    await heard(GpuReadFailed('a read'));
    expect(asked, 1, reason: 'none more');
    expect(tellings, 2, reason: 'not the cause its type was');
    await heard(GpuRefused('a landing'));
    await heard(GpuReadFailed('a save'));
    expect(tellings, 2, reason: 'one cause');
    expect(isTheAppsEngine(lost), isTrue, reason: 'the app stays on it');
    // What a lost device raises is no test's to answer for: each use of
    // what was made on it raises one.
    expect(debugTakeAppGpuEngineNoted(), isNull);
    expect(lost.debugTakeNoted(), isNotNull, reason: '⛔premise');

    now = now.add(const Duration(seconds: 1));
    await heardTillTheNextIsOpen(GpuRefused('a frame'));
    expect((asked, startedAgain, tellings), (2, 2, 2));
    expect(EngineRefusals.wentBy, GpuDeviceWent.unsaid, reason: 'destroyed');

    now = now.add(const Duration(seconds: 59));
    theAppsDeviceGone();
    await heard(GpuRefused('a frame'));
    expect(asked, 2);
    expect(tellings, 3, reason: 'another device: its cause is told again');
  });

  test('a device in whose place no engine stands is told as a refusal is, '
      'and the app does not say it started again: where none was opened, '
      'and where the one opened went as it was made ready', () async {
    var opensOne = false;
    opening(() async {
      if (opensOne) {
        (await openAppGpuEngine()).debugLose(forMemory: true);
      }
    });
    theAppsDeviceGone();
    await heard(GpuReadFailed('a read'));
    expect((asked, startedAgain, tellings), (1, 0, 1));
    expect(EngineRefusals.wentBy, GpuDeviceWent.unsaid);

    now = now.add(EngineRefusals.openAnotherApart);
    opensOne = true;
    theAppsDeviceGone();
    await heardTillTheNextIsOpen(GpuReadFailed('a read'));
    expect(appGpuEngineIsGone, isTrue, reason: '⛔premise: gone as made');
    expect((asked, startedAgain), (2, 0));
    expect(tellings, 1, reason: 'the one cause, told already');
    expect(EngineRefusals.wentBy, GpuDeviceWent.unsaid);
  });

  test('an opening that fails leaves the door hearing', () async {
    final escaped = <Object>[];
    var fails = true;
    opening(() async {
      if (fails) {
        throw StateError('no path');
      }
      await openAppGpuEngine();
    });
    theAppsDeviceGone();
    await runZonedGuarded(
      () => heard(GpuReadFailed('a read')),
      (error, _) => escaped.add(error),
    );
    expect(escaped.single, isStateError);
    expect((asked, startedAgain, tellings), (1, 0, 0));

    now = now.add(EngineRefusals.openAnotherApart);
    fails = false;
    theAppsDeviceGone();
    await heardTillTheNextIsOpen(GpuReadFailed('a read'));
    expect((asked, startedAgain), (2, 1));
  });
}

/// Once the app's next engine is open and all that sets off is through —
/// an engine opens off this isolate, in its own time.
Future<void> untilTheNextIsOpen() async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (appGpuEngineOpen.value == null) {
    expect(DateTime.now().isBefore(deadline), isTrue, reason: 'never open');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  await pumpEventQueue();
}

/// [refused] reported as what caught it reports it, and the engine that
/// sets off open ([untilTheNextIsOpen]).
Future<void> heardTillTheNextIsOpen(Object refused) async {
  FlutterError.reportError(FlutterErrorDetails(exception: refused));
  await pumpEventQueue();
  await untilTheNextIsOpen();
}
