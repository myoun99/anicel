import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
/// 입력 수단과 무관하게 한 법으로」.
///
/// 🪦This file used to pin that NO registry action zoomed the viewport, so
/// that the day one did, whoever bound it would read the answer and put the
/// pass-through in the gate rather than inside the zoom. I-19 bound two
/// (유저 2026-09-13: 「shift+>(확대) shift+<(축소)」), and the pass-through
/// is in the gate's key half and in the action funnel, both asking
/// `viewZoomPassesPlayback`.
///
/// ⚠️The keys here carry NO modifier on purpose. A modifier's own DOWN is a
/// key press the stop law answers before the chord exists — which is what
/// the default Shift+. meets during playback, and a question on the board,
/// not a behaviour to pin.
void main() {
  Future<EditorSessionManager> pumpEditor(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    tester
        .widget<EditorShortcutScope>(find.byType(EditorShortcutScope))
        .notifier!
        .setActivators(EditorActionIds.canvasZoomIn, const [
          SingleActivator(LogicalKeyboardKey.bracketRight),
        ]);
    await tester.pump();
    return tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;
  }

  String readout(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: inMainCanvas(
            find.byKey(const ValueKey<String>('canvas-viewport-zoom-label')),
          ),
          matching: find.byType(Text),
        ),
      )
      .data!;

  testWidgets('a ZOOM key while the canvas plays zooms, and the canvas keeps '
      'playing', (tester) async {
    final session = await pumpEditor(tester);
    final before = readout(tester);
    session.playbackRig.playback.play(scope: PlaybackScope.activeCut);
    await tester.pump(const Duration(milliseconds: 16));
    expect(session.playbackRig.playback.isPlaying, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();

    expect(
      session.playbackRig.playback.isPlaying,
      isTrue,
      reason: 'zoom is navigation — 「입력 수단과 무관하게 한 법」 with the '
          'wheel and the pinch, which already pass',
    );
    expect(readout(tester), isNot(before), reason: 'and the view zoomed');

    session.playbackRig.transports.stopAll();
    await tester.pumpAndSettle();
  });

  testWidgets('…but while ANOTHER transport plays, a zoom key stops it like '
      'any key — the hole belongs to its own run', (tester) async {
    final session = await pumpEditor(tester);
    final before = readout(tester);
    final viewer = FakePlaybackTransport();
    addTearDown(viewer.dispose);
    session.playbackRig.transports.add(viewer);
    viewer.play();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();

    expect(viewer.isPlaying, isFalse, reason: 'the gate half: 「정지」');
    expect(readout(tester), before, reason: 'the funnel half: 「입력 일 안함」');
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
