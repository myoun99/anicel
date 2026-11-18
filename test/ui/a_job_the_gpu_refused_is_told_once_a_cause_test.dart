import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuReadFailed, GpuRefused;
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/native/engine_refusals.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🗣️gpu-canonical-store-Q14 (유저 2026-11-11): 「공통 알림 창으로 한 번
/// 알린다」 — 「실패가 처음 났을 때 공통 알림 창(닫기 버튼)을 한 번 띄운다 …
/// 같은 실행에서 같은 까닭으로는 다시 띄우지 않는다. 획이 사라진 경우와
/// 캔버스가 멈춘 경우 둘 다 같은 창이다」 — a job the graphics device
/// refused ends at one of the two doors every error of the app's ends at,
/// and is said from there ([EngineRefusals]).
void main() {
  void report(Object error) =>
      FlutterError.reportError(FlutterErrorDetails(exception: error));

  test('a refusal is told whichever door it ends at — once a cause, what '
      'else is thrown never, and not in the turn it is heard in — and each '
      'door still hears what it heard', () async {
    final reported = <Object>[];
    final uncaught = <Object>[];
    final wasReported = FlutterError.onError;
    final wasUncaught = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = wasReported;
      PlatformDispatcher.instance.onError = wasUncaught;
      EngineRefusals.debugForget();
    });
    FlutterError.onError = (details) => reported.add(details.exception);
    PlatformDispatcher.instance.onError = (error, _) {
      uncaught.add(error);
      return true;
    };
    EngineRefusals.install();
    var tellings = 0;
    void count() => tellings += 1;
    EngineRefusals.told.addListener(count);
    addTearDown(() => EngineRefusals.told.removeListener(count));
    // Once the turn a refusal was heard in is through.
    Future<int> told() async {
      await null;
      return tellings;
    }

    report(StateError('the app\'s own'));
    expect(await told(), 0);

    report(GpuRefused('no room'));
    expect(tellings, 0, reason: 'heard in a paint, as well');
    expect(await told(), 1);

    report(GpuRefused('no room, a stroke on'));
    expect(await told(), 1, reason: 'its cause is told');

    expect(
      PlatformDispatcher.instance.onError!(
        GpuReadFailed('lost'),
        StackTrace.empty,
      ),
      isTrue,
      reason: 'as the door answered',
    );
    expect(await told(), 2, reason: 'another cause');

    expect(reported, hasLength(3));
    expect(uncaught, hasLength(1));
  });

  test('main watches both doors before the app is run', () {
    final source = File('lib/main.dart').readAsStringSync();
    final (watched, run) = (
      source.indexOf('EngineRefusals.install();'),
      source.indexOf('runApp('),
    );
    expect(watched, isNonNegative, reason: 'main watches them');
    expect(watched, lessThan(run), reason: 'before anything is asked');
  });

  testWidgets('the shell says a refusal in the common window, once a cause', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(EngineRefusals.debugForget);
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final window = find.byKey(const ValueKey<String>('gpu-refused-notice'));

    /// [error] reported as what caught it reports it, both doors watched
    /// over the test's own — and put back before anything is expected.
    Future<void> refused(Object error) async {
      final wasReported = FlutterError.onError;
      final wasUncaught = PlatformDispatcher.instance.onError;
      EngineRefusals.install();
      report(error);
      FlutterError.onError = wasReported;
      PlatformDispatcher.instance.onError = wasUncaught;
      expect(tester.takeException(), same(error), reason: 'still reported');
      await tester.pumpAndSettle();
    }

    await refused(GpuRefused('no room'));
    expect(window, findsOneWidget);
    for (final said in [
      AppText.strings.commonNotice,
      AppText.strings.gpuRefusedNotice,
    ]) {
      expect(
        find.descendant(of: window, matching: find.text(said)),
        findsOneWidget,
      );
    }
    await tester.tap(find.byKey(const ValueKey<String>('app-notice-close')));
    await tester.pumpAndSettle();
    expect(window, findsNothing, reason: '⛔premise: closed');

    await refused(GpuRefused('no room, a stroke on'));
    expect(window, findsNothing, reason: 'its cause is told');

    await refused(GpuReadFailed('lost'));
    expect(window, findsOneWidget, reason: 'another cause');
  });
}
