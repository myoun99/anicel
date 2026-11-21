import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';

/// 🗣️A WIDGET TEST HAS THE ENGINE IT ASKS FOR BY ITS NEXT PUMP (a-process-
/// first-test-never-sees-the-canvas-stand-Q1 = 「시험에서는 엔진을 그 자리에서
/// 연다」, 유저 2026-11-20). Its clock is pumped, and an engine opened on
/// another isolate was lent no real time to come in: a file's first test
/// asked and never had it, and the canvas it showed never stood —
/// 🔬269 of 393 first tests (서피스 11-20) — while a test after it, real
/// time passed, did (`flutter_test_config.dart`,
/// [debugOpenAppGpuEngineHere]).
void main() {
  // First in the file: nothing has opened the engine yet.
  testWidgets('the engine a widget test asks for is open by its next pump, '
      'no real time lent', (tester) async {
    expect(appGpuEngineOpen.value, isNull, reason: '⛔premise: not open yet');
    var told = false;
    void tell() => told = true;
    appGpuEngineOpen.addListener(tell);
    addTearDown(() => appGpuEngineOpen.removeListener(tell));

    unawaited(openAppGpuEngine());
    expect(told, isFalse, reason: 'not told inside the call that asked');
    await tester.pumpWidget(const SizedBox());

    expect(appGpuEngineOpen.value, isNotNull);
    expect(told, isTrue);
  });
}
