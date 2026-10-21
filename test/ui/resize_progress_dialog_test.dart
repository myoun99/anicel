import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../helpers/panel_finders.dart';
import 'flyout_test_helpers.dart' show flyoutOwnerByItemKey;

/// D3 (R7): the cut-canvas resize runs behind the app's ONE wait-for-this
/// window — the same [AppProgressDialog] save wears, held across BOTH
/// halves of the resize (the synchronous command and the next frame's
/// canvas-host adoption), so no input can slip between them.
///
/// Driven through the REAL entry: the CUT pill's flyout item → the
/// canvas-size dialog → confirm (parity-tests-must-drive-real-input).
void main() {
  testWidgets('confirming a resize shows the shared progress window and '
      'lands the new size', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;

    // The resize entry lives in the CUT pill's flyout.
    final owner = flyoutOwnerByItemKey['resize-cut-canvas-button'];
    if (owner != null) {
      await tester.tap(find.byKey(ValueKey<String>(owner)));
      await tester.pumpAndSettle();
    }
    await tester.tap(
      find.byKey(const ValueKey<String>('resize-cut-canvas-button')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('canvas-size-width-field')),
      '1280',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('canvas-size-height-field')),
      '720',
    );
    // The confirm action pops the request CAPTURED AT BUILD — a real
    // keystroke rebuilds per onChanged, so the frame between entry and
    // press exists for a hand too.
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-size-confirm-button')),
    );
    // One pump: the progress window mounts BEFORE the work runs (its
    // own endOfFrame law) — the freeze happens behind a painted window.
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('resize-progress-dialog')),
      findsOneWidget,
      reason: 'the ONE shared window, up before the synchronous command',
    );

    await tester.pumpAndSettle();
    expect(
      session.activeCutOrNull!.canvasSize,
      const CanvasSize(width: 1280, height: 720),
    );
    // The done label lingers, then the window removes itself.
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('resize-progress-dialog')),
      findsNothing,
    );
  });

  // 🗣️F-432 (유저 2026-10-21): 「페이스트 보드 배율 전환이 너무 느리고, 이런
  // 시간 걸리는 로직은 규칙으로서 공용 로딩창 표시해야함」.
  testWidgets('a pasteboard size or use, pressed in its window, lands behind '
      'the same wait window, under the pasteboard\'s name', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();

    final session = tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;
    // The floor lays its controls out rather than behind a gear.
    await tester.tap(
      find.descendant(
        of: mainCanvasPanelShell(),
        matching: find.byKey(
          const ValueKey<String>('canvas-pasteboard-color-button'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final (press, landed) in [
      (
        'pasteboard-size-oneAndAHalf',
        () => session.repository.requireProject().pasteboardSize ==
            PasteboardSize.oneAndAHalf,
      ),
      (
        'pasteboard-in-use',
        () => !session.repository.requireProject().pasteboardInUse,
      ),
    ]) {
      await tester.tap(find.byKey(ValueKey<String>(press)));
      await tester.pump();
      final window = find.byKey(
        const ValueKey<String>('resize-progress-dialog'),
      );
      expect(window, findsOneWidget, reason: press);
      expect(
        find.descendant(
          of: window,
          matching: find.text(AppText.strings.pasteboardTitle),
        ),
        findsOneWidget,
        reason: press,
      );
      await tester.pumpAndSettle();
      expect(landed(), isTrue, reason: press);
      await tester.pump(const Duration(milliseconds: 950));
      await tester.pumpAndSettle();
      expect(window, findsNothing, reason: press);
    }
  });
}
