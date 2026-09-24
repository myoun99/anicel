import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/fake_playback_transport.dart';
import '../../helpers/panel_finders.dart';

/// 🚨R6q3 — 유저 2026-08-25, 답 2번: 「키보드 줌도 통과시킨다. 재생 중 줌은
/// 입력 수단과 무관하게 한 법으로」 — and 2026-09-13, I-19-zoom-key-playback
/// 1번: 「수식키는 혼자선 입력으로 치지 않는다」.
///
/// 🪦This file used to pin that NO registry action zoomed the viewport, so
/// that the day one did, whoever bound it would read the answer and put the
/// pass-through in the gate rather than inside the zoom. I-19 bound two
/// (「shift+>(확대) shift+<(축소)」); the pass-through is in the gate's key
/// half and in the action funnel, both asking `viewZoomPassesPlayback`.
///
/// ⚠️The zoom presses here are the DEFAULT chord, Shift held around the key:
/// the question the second answer settles is exactly what Shift's own
/// key-down does before the chord exists.
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

  String textOf(WidgetTester tester, String key) => tester
      .widget<Text>(
        find.descendant(
          of: inMainCanvas(find.byKey(ValueKey<String>(key))),
          matching: find.byType(Text),
        ),
      )
      .data!;

  Future<void> shifted(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }

  Future<void> playCanvas(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    session.playbackRig.playback.play(scope: PlaybackScope.activeCut);
    await tester.pump(const Duration(milliseconds: 16));
    expect(session.playbackRig.playback.isPlaying, isTrue);
  }

  Future<EditorSessionManager> playingCanvas(WidgetTester tester) async {
    final session = await pumpEditor(tester);
    await playCanvas(tester, session);
    return session;
  }

  /// A point on the canvas panel clear of the floating regions — where the
  /// D13 tap test presses.
  Offset onCanvas(WidgetTester tester) {
    final panel = tester.getRect(
      find.byKey(const ValueKey<String>('main-canvas-brush-host-container')),
    );
    return Offset(panel.center.dx, panel.top + panel.height / 4);
  }

  testWidgets('Shift+. while the canvas plays zooms, and the canvas keeps '
      'playing', (tester) async {
    final session = await playingCanvas(tester);
    final before = textOf(tester, 'canvas-viewport-zoom-label');

    await shifted(tester, LogicalKeyboardKey.period);

    expect(
      session.playbackRig.playback.isPlaying,
      isTrue,
      reason: 'zoom is navigation — 「입력 수단과 무관하게 한 법」 with the '
          'wheel and the pinch — and Shift alone was not an input',
    );
    expect(
      textOf(tester, 'canvas-viewport-zoom-label'),
      isNot(before),
      reason: 'and the view zoomed',
    );

    session.playbackRig.transports.stopAll();
    await tester.pumpAndSettle();
  });

  // 🚨A KEY IS THE CHARACTER IT TYPES (a-key-is-the-character-it-types): the
  // gate's question and the funnel's map read ONE set of forms. On a JIS
  // keyboard `'` is Shift+7, arriving as `7` with Shift held, typing `'`.
  testWidgets('a zoom moved to `\'` zooms from a JIS Shift+7 while the canvas '
      'plays — the gate and the map read the same typed form', (tester) async {
    final session = await playingCanvas(tester);
    EditorShortcutScope.peek(
      tester.element(find.byType(EditorCanvasArea)),
    )!.setActivators(EditorActionIds.canvasZoomIn, const [
      SingleActivator(LogicalKeyboardKey.quoteSingle),
    ]);
    await tester.pump();
    final before = textOf(tester, 'canvas-viewport-zoom-label');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit7, character: "'");
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit7);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(
      session.playbackRig.playback.isPlaying,
      isTrue,
      reason: 'the gate knew it for a zoom',
    );
    expect(
      textOf(tester, 'canvas-viewport-zoom-label'),
      isNot(before),
      reason: 'and the map zoomed',
    );

    session.playbackRig.transports.stopAll();
    await tester.pumpAndSettle();
  });

  testWidgets('a modifier let go with nothing after it stops on its '
      'release', (tester) async {
    final session = await playingCanvas(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(
      session.playbackRig.playback.isPlaying,
      isTrue,
      reason: '「수식키는 혼자선 입력으로 치지 않는다」 — not on its own down',
    );

    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(
      session.playbackRig.playback.isPlaying,
      isFalse,
      reason: 'a Shift pressed and released alone was a press after all',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('…but a modifier held through a canvas WHEEL notch is not lone '
      'when it comes up — the notch was the something after', (tester) async {
    final session = await playingCanvas(tester);
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    wheel.hover(onCanvas(tester));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, -120)));
    await tester.pump();
    expect(
      session.playbackRig.playback.isPlaying,
      isTrue,
      reason: 'D13: the notch navigated',
    );

    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(
      session.playbackRig.playback.isPlaying,
      isTrue,
      reason: 'Shift was not alone — the answer names a modifier with '
          'nothing after it, and a pointer actuation is something',
    );

    session.playbackRig.transports.stopAll();
    await tester.pumpAndSettle();
  });

  testWidgets('Alt held while the canvas plays IS the eyedropper, and the '
      'canvas keeps playing — a modifier reaches the app like any other', (
    tester,
  ) async {
    // 🗣️유저 2026-09-13: 「스포이드가 잡히는게 왜 문제지? 스포이드 작동할때
    // 재생 멈추게되는거아닌가? 전혀 문제없는데」.
    // ⚠️The press that USES the eyedropper is not pinned here: over the
    // playback view it does not stop yet, and did not for the eyedropper
    // TOOL before I-19 either (board: `playback-tap-taken-by-tool-layer`).
    // ↩️It does now, and the tool does nothing with it — pinned with every
    // tool in `a_press_on_playback_takes_no_tool_test.dart`.
    final session = await pumpEditor(tester);
    CanvasTool toolOf() =>
        tester.widget<ToolsPanel>(find.byType(ToolsPanel)).tool;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    await playCanvas(tester, session);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(
      toolOf(),
      CanvasTool.eyedropper,
      reason: 'not an input, so not eaten — the hold reached the app',
    );
    expect(session.playbackRig.playback.isPlaying, isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(toolOf(), CanvasTool.brush, reason: 'letting go returns the brush');
    expect(
      session.playbackRig.playback.isPlaying,
      isFalse,
      reason: 'and an Alt let go with nothing after it stops, like any '
          'modifier',
    );
  });

  testWidgets('a modifier chord that is NOT a zoom stops like any key, and '
      'does nothing else', (tester) async {
    final session = await playingCanvas(tester);
    final angle = textOf(tester, 'canvas-viewport-rotation-label');

    // Shift+R is the canvas rotate — bound, and not a zoom.
    await shifted(tester, LogicalKeyboardKey.keyR);

    expect(session.playbackRig.playback.isPlaying, isFalse);
    expect(
      textOf(tester, 'canvas-viewport-rotation-label'),
      angle,
      reason: '「입력 일 안함」 — the chord stopped playback and rotated nothing',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('…and while ANOTHER transport plays, a zoom chord stops it like '
      'any key — the hole belongs to its own run', (tester) async {
    final session = await pumpEditor(tester);
    final before = textOf(tester, 'canvas-viewport-zoom-label');
    final viewer = FakePlaybackTransport();
    addTearDown(viewer.dispose);
    session.playbackRig.transports.add(viewer);
    viewer.play();
    await tester.pump();

    await shifted(tester, LogicalKeyboardKey.period);

    expect(viewer.isPlaying, isFalse, reason: 'the gate half: 「정지」');
    expect(
      textOf(tester, 'canvas-viewport-zoom-label'),
      before,
      reason: 'the funnel half: 「입력 일 안함」',
    );
    await tester.pumpAndSettle();
  });

  test('the gate says which question it answers, and not the old clause', () {
    final gate = File(
      'lib/src/ui/playback/playback_actuation_gate.dart',
    ).readAsStringSync();

    expect(
      gate,
      isNot(contains('bound zoom keys included')),
      reason: 'that clause is what made the split look real — this repo does '
          'not delete a decision comment, it corrects a wrong one',
    );
    expect(
      gate,
      contains('R6q3'),
      reason: 'and the correction says which question it answers',
    );
  });
}
