/// The frame's tools are opened on four engines here, each compiling
/// them where it is first asked: the bound is this file's own
/// (`timeline_grid_tile_generation_test.dart` says why).
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart'
    show GpuDeviceWent, GpuReadFailed;
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/app_kernels_ahead.dart';
import 'package:anicel/src/native/engine_frame_tools.dart';
import 'package:anicel/src/native/engine_refusals.dart';
import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';
import 'package:anicel/src/ui/gpu_started_again_message.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../helpers/a_canvas_standing_on_a_frame.dart'
    show opensTheEnginesScreens;

/// 🗣️a-lost-gpu-device-keeps-the-unsaved-tiles-Q1 (유저 2026-11-11): 「그래픽
/// 장치가 다시 시작되었다고 알린다」 · 「그래픽장치가 왜 다시시작되었는지는
/// 알수있게. 사용자는 앱 원인인지 다른건지 모르니까 어느정도는 투명하게.
/// 물론 확실하게 모를 가능성 높으니 그 경우 가능성높은 원인을 알려주도록」
/// — once the app stands on another engine ([EngineRefusals.openedAnother])
/// the shell says so in the common window, after the wait window it stood
/// behind meanwhile, with why the device went.
///
/// On the app's own engine, which the test loses three times.
void main() {
  opensTheEnginesScreens();

  test('what is said is that the device started again and then why: the '
      'cause where one is named, each its own words, and the likely ones '
      'where none is', () {
    final strings = AppText.strings;
    expect(
      {
        for (final by in GpuDeviceWent.values)
          by: gpuStartedAgainMessage(strings, by),
      },
      {
        for (final (by, why) in [
          (GpuDeviceWent.unsaid, strings.gpuWentUnsaid),
          (GpuDeviceWent.memory, strings.gpuWentByMemory),
          (GpuDeviceWent.thisApp, strings.gpuWentByThisApp),
          (GpuDeviceWent.removal, strings.gpuWentByRemoval),
          (GpuDeviceWent.reset, strings.gpuWentByReset),
          (GpuDeviceWent.driver, strings.gpuWentByDriver),
        ])
          by: '${strings.gpuStartedAgainNotice}\n\n$why',
      },
    );
    expect(
      {
        strings.gpuWentUnsaid,
        strings.gpuWentByMemory,
        strings.gpuWentByThisApp,
        strings.gpuWentByRemoval,
        strings.gpuWentByReset,
        strings.gpuWentByDriver,
      },
      hasLength(GpuDeviceWent.values.length),
      reason: 'each cause its own words',
    );
  });

  testWidgets('the app\'s device gone, the shell stands behind its wait '
      'window while another engine is opened, and says once it stands on '
      'it that the device started again, and why — each device that goes '
      'its own saying, and none to a shell that went', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var now = DateTime(2026, 11, 13, 12);
    EngineRefusals.debugClockOverride = () => now;
    addTearDown(() {
      EngineRefusals.debugClockOverride = null;
      EngineRefusals.debugForget();
      debugLetTheAppGo();
      letTheGoneAppGpuEngineGo();
    });
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final waits = find.byType(AppProgressDialog);
    final says = find.byKey(
      const ValueKey<String>('gpu-started-again-notice'),
    );
    final refused = find.byKey(const ValueKey<String>('gpu-refused-notice'));

    /// The app's device gone for want of memory, and the first refusal of
    /// it reported as what caught it reports it — both doors watched over
    /// the test's own and put back, the app opening another engine as the
    /// launch's path does but for what no pumped clock lends the time for,
    /// an engine opened and kernels compiled off this isolate: held, the
    /// one that is gone let go, and let go itself once [ready].
    void theDeviceGoes(Completer<void> ready) {
      appGpuEngine.debugLose(forMemory: true);
      final error = GpuReadFailed('a read');
      final wasReported = FlutterError.onError;
      final wasUncaught = PlatformDispatcher.instance.onError;
      EngineRefusals.install(
        openAnother: () async {
          holdTheAppForItsEngine();
          letTheGoneAppGpuEngineGo();
          await ready.future;
          // Opened here, where it is asked: the word of it is all that is
          // left to say.
          appGpuEngine;
          await openAppGpuEngine();
          debugLetTheAppGo();
        },
      );
      FlutterError.reportError(FlutterErrorDetails(exception: error));
      FlutterError.onError = wasReported;
      PlatformDispatcher.instance.onError = wasUncaught;
      expect(tester.takeException(), same(error), reason: 'still reported');
    }

    /// The frames' tools open on the engine the app stands on: asked for
    /// by what shows a frame, in real time.
    Future<void> itsToolsOpen() =>
        tester.runAsync(() => appEngineFrameTools);

    final first = Completer<void>();
    theDeviceGoes(first);
    expect(waits, findsNothing, reason: 'not in the turn it is heard in');
    await tester.pump();
    await tester.pump();
    expect(waits, findsOneWidget, reason: 'the launch\'s own window');
    expect(
      tester.widget<AppProgressDialog>(waits).windowKey,
      const ValueKey<String>('launch-progress-dialog'),
    );
    expect(says, findsNothing, reason: 'not before it stands');

    first.complete();
    await tester.pump();
    await itsToolsOpen();
    await tester.pumpAndSettle();
    expect(waits, findsNothing);
    expect(refused, findsNothing, reason: 'no refusal is told');
    expect(says, findsOneWidget);
    for (final said in [
      AppText.strings.commonNotice,
      gpuStartedAgainMessage(AppText.strings, GpuDeviceWent.memory),
    ]) {
      expect(
        find.descendant(of: says, matching: find.text(said)),
        findsOneWidget,
      );
    }
    await tester.tap(find.byKey(const ValueKey<String>('app-notice-close')));
    await tester.pumpAndSettle();
    expect(says, findsNothing, reason: '⛔premise: closed');

    // Another device, a minute on: said again.
    now = now.add(EngineRefusals.openAnotherApart);
    theDeviceGoes(Completer<void>()..complete());
    await tester.pump();
    await itsToolsOpen();
    await tester.pumpAndSettle();
    expect(says, findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    // The shell gone, it hears no more: said to one that went, the saying
    // asks a window of no tree.
    var saidToNone = 0;
    void count() => saidToNone += 1;
    EngineRefusals.openedAnother.addListener(count);
    addTearDown(() => EngineRefusals.openedAnother.removeListener(count));
    now = now.add(EngineRefusals.openAnotherApart);
    theDeviceGoes(Completer<void>()..complete());
    await tester.pump();
    await itsToolsOpen();
    await tester.pump();
    expect(saidToNone, 1, reason: '⛔premise: the app says it');
    expect(tester.takeException(), isNull);
  });
}
