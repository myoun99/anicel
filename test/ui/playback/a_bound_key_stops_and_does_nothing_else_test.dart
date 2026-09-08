import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/fake_playback_transport.dart';

/// 🚨★★★**T28-c THROUGH THE REAL EDITOR: 「뭘 하든 정지만. 입력 일 안함」**
/// (유저 2026-08-13), for a BOUND key, whatever is the thing playing.
///
/// Both assertions are load-bearing and neither used to hold:
/// - the STOP now covers a media viewer as well as the canvas (유저
///   2026-09-07 `exclusive`, both directions), because the gate holds
///   `PlaybackTransports` instead of one concrete controller;
/// - the CONSUME held for nobody. `PlaybackActuationGate`'s doc promised
///   「`,` and `.` move no frame」 and 실측 2026-09-08 they moved one. The
///   stop runs from a `HardwareKeyboard` handler, which is BEFORE focus
///   dispatch, so `home_page`'s funnel — where that half was said to live
///   — was always asked after the answer had been turned into 「아니오」.
///
/// ⇒ This file pumps the whole editor, because the bug was in the wiring
/// between three widgets and every unit around it was green.
void main() {
  Future<EditorSessionManager> pumpEditor(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;
  }

  /// 🪦The original law, and it did not hold. 유저 2026-08-13 said 「뭘 하든
  /// 정지만. **입력 일 안함**」 and the gate's doc spelled out 「`,` and `.`
  /// move no frame」 — but 실측 2026-09-08 the frame stepped every time. The
  /// gate stopped playback from a `HardwareKeyboard` handler, which runs
  /// BEFORE focus dispatch, so the funnel's guard was asked a question that
  /// the stop had just turned into 「아니오」.
  testWidgets('a bound key while the CANVAS plays stops it and does NOT '
      'also step a frame', (tester) async {
    final session = await pumpEditor(tester);
    session.playbackRig.playback.play(scope: PlaybackScope.activeCut);
    await tester.pump(const Duration(milliseconds: 16));
    expect(session.playbackRig.playback.isPlaying, isTrue);
    final standingAt = session.currentFrameIndex;

    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.pump();

    expect(session.playbackRig.playback.isPlaying, isFalse);
    expect(session.currentFrameIndex, standingAt, reason: '「입력 일 안함」');

    await tester.pumpAndSettle();
  });

  testWidgets('a bound key while a NON-canvas transport plays stops it and '
      'does NOT also do its job', (tester) async {
    final session = await pumpEditor(tester);

    // A media viewer, as far as everything downstream is concerned.
    final viewer = FakePlaybackTransport();
    addTearDown(viewer.dispose);
    session.playbackRig.transports.add(viewer);
    viewer.play();
    await tester.pump();
    final standingAt = session.currentFrameIndex;

    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.pump();

    expect(viewer.isPlaying, isFalse, reason: 'the gate half: 「정지」');
    expect(
      session.currentFrameIndex,
      standingAt,
      reason: 'the funnel half: 「입력 일 안함」 — the canvas was not the '
          'thing playing, and the frame must not have stepped anyway',
    );

    // And the SECOND press does its job — 유저 09-08 「그대로 둠. 그게 직관적임」.
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.pump();
    expect(
      session.currentFrameIndex,
      isNot(standingAt),
      reason: 'the gate is only in the way while something plays',
    );

    await tester.pumpAndSettle();
  });
}
