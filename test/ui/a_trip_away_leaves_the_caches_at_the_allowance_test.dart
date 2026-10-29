import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';

import '../helpers/poll_until.dart';

/// 🗣️F-504 (유저 2026-10-29, Galaxy Tab, a Clip Studio file opened from
/// Drive): 「재생시 처음에 지금, 뒤 한장만 초록바인상태로 재생됨, 그러고
/// 메모리 허용을 살짝 조절햇다 원래대로 돌리니 그 초록바가 20프레임유지」 ·
/// 「허용된거에서 메모리 최대한쓰자」.
///
/// Read in the embedding, not measured on the tablet: Android's Flutter
/// says memory is tight at every trim level from RUNNING_LOW up, and since
/// API 34 an app is told only UI_HIDDEN and BACKGROUND — the app covered by
/// a picker, by Drive. Each one halved the caches and only the allowance
/// moving raised them, so a few trips away left playback on its floor: two
/// frames of a large canvas. The trip is driven through the shell here, in
/// the order Android drives it.
void main() {
  late EditorSessionManager session;

  Future<void> boot(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    session = tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip).first)
        .projects
        .sessions
        .first;
  }

  /// Covered, and told so twice — as the UI hides, and as the app goes to
  /// the background.
  Future<void> away(WidgetTester tester) async {
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleMemoryPressure()
      ..handleAppLifecycleStateChanged(AppLifecycleState.paused)
      ..handleMemoryPressure();
    await tester.pump();
  }

  Future<void> back(WidgetTester tester) async {
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }

  ({int playback, int cels, int undo}) lines() => (
    playback: session.playbackRig.playbackCache.playbackCacheByteBudget,
    cels: session.renderCaches.brushFrameStore.hotCelByteBudget,
    undo: session.historyManager.byteBudget,
  );

  testWidgets('🚨back in front, every cache stands at the allowance again', (
    tester,
  ) async {
    await boot(tester);
    final before = lines();

    await away(tester);
    final whileAway = lines();
    expect(whileAway.playback, lessThan(before.playback), reason: 'premise');
    expect(whileAway.cels, lessThan(before.cels), reason: 'premise');
    expect(whileAway.undo, lessThan(before.undo), reason: 'premise');

    await back(tester);

    expect(
      lines(),
      before,
      reason: '🪦it held until the allowance moved: two frames of a large '
          'canvas played',
    );
  });

  testWidgets('a warning said in front holds while the app stays there', (
    tester,
  ) async {
    await boot(tester);
    final before = lines();

    tester.binding.handleMemoryPressure();
    await tester.pump(const Duration(seconds: 5));

    expect(
      lines().playback,
      lessThan(before.playback),
      reason: "iOS's warning comes in front — the one the iPhone was killed "
          'after',
    );
  });

  testWidgets('and the warmer looks again in the room that came back', (
    tester,
  ) async {
    await boot(tester);
    final scheduler = session.playbackRig.prerenderScheduler;
    var rests = 0;
    scheduler.changes.addListener(() => rests += 1);
    session.warmActiveCut();
    await tester.runAsync(() => patiently(scheduler.idle));
    expect(rests, greaterThan(0), reason: 'premise: the walk came to rest');
    await away(tester);
    await tester.runAsync(() => patiently(scheduler.idle));
    final restsAway = rests;

    await back(tester);
    await tester.runAsync(() => patiently(scheduler.idle));

    expect(
      rests,
      greaterThan(restsAway),
      reason: 'a walk resting for want of room waits for something to move',
    );
  });
}
