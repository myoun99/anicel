import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/ui/editor_workspace.dart';

import '../../helpers/home_page_probes.dart';
import '../../helpers/panel_finders.dart';

/// 🗣️I-19 (유저 2026-09-12 / 09-13): 「여러 단축키 기존 버튼에 연결」 — every
/// key here presses a button that already existed, and the test for each is
/// that it does what THAT BUTTON does, driven through the real app.
///
/// ⛔Not 「the key calls a method」: a key wired to a sibling of the button's
/// verb would pass that and still be a second law.
Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
}) async {
  if (control) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  }
  if (shift) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyEvent(key);
  if (shift) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  if (control) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }
  await tester.pumpAndSettle();
}

const _row = 'default-layer-1';

List<String> _glyphs() => [
  for (var i = 0; i < 4; i++) rowPainter(_row).cellModelAt(i).glyph,
];

/// A fresh app with a drawing on frame 0 of the first row, the cells before
/// and after [act].
Future<({List<String> before, List<String> after})> _onAFreshDrawing(
  WidgetTester tester,
  Future<void> Function() act,
) async {
  // A different root first: pumping the same app again would keep its
  // session, and the second run would start from the first one's result.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(const AnicelApp());
  await tester.pumpAndSettle();
  await tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));
  final before = _glyphs();
  await act();
  return (before: before, after: _glyphs());
}

void main() {
  testWidgets('Ctrl+C and Ctrl+V are the pill\'s Copy and Paste linked', (
    tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await tester.pumpAndSettle();
    await tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));

    await _press(tester, LogicalKeyboardKey.keyC, control: true);
    await tapHomeTimelineCell(
      tester,
      const ValueKey<String>('timeline-cell-default-layer-1-1'),
    );
    await _press(tester, LogicalKeyboardKey.keyV, control: true);

    // The same two cells the buttons' own test reads after copy + linked
    // paste (`home_frame_and_clipboard_test`).
    expectCellText(_row, 0, '○');
    expectCellText(_row, 1, '○');
  });

  for (final (name, button, key, control) in const [
    ('Cut', 'shared-cut-button', LogicalKeyboardKey.keyX, true),
    ('Delete', 'shared-delete-button', LogicalKeyboardKey.delete, false),
  ]) {
    testWidgets('${control ? 'Ctrl+' : ''}${key.keyLabel} does what the '
        'pill\'s $name button does', (tester) async {
      final byButton = await _onAFreshDrawing(
        tester,
        () => tapToolbarButton(tester, ValueKey<String>(button)),
      );
      expect(
        byButton.after,
        isNot(byButton.before),
        reason: 'the button changed something, or the parity below is two '
            'no-ops agreeing',
      );
      final byKey = await _onAFreshDrawing(
        tester,
        () => _press(tester, key, control: control),
      );
      expect(byKey.before, byButton.before);
      expect(byKey.after, byButton.after);
    });
  }

  testWidgets('Ctrl+B is the pill\'s Paste independent', (tester) async {
    Future<void> copyThenMove() async {
      await tapToolbarButton(
        tester,
        const ValueKey<String>('shared-copy-button'),
      );
      await tapHomeTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-default-layer-1-1'),
      );
    }

    final byButton = await _onAFreshDrawing(tester, () async {
      await copyThenMove();
      await tapToolbarButton(
        tester,
        const ValueKey<String>('shared-paste-independent-button'),
      );
    });
    expect(byButton.after, isNot(byButton.before));
    final byKey = await _onAFreshDrawing(tester, () async {
      await copyThenMove();
      await _press(tester, LogicalKeyboardKey.keyB, control: true);
    });
    expect(byKey.after, byButton.after);
  });

  testWidgets('= is the legend eye\'s 「Solo active layer」', (tester) async {
    await tester.pumpWidget(const AnicelApp());
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    expect(session.visibilitySolo.layerVisibilitySoloEnabled, isFalse);

    await _press(tester, LogicalKeyboardKey.equal);
    expect(session.visibilitySolo.layerVisibilitySoloEnabled, isTrue);

    await _press(tester, LogicalKeyboardKey.equal);
    expect(session.visibilitySolo.layerVisibilitySoloEnabled, isFalse);
  });

  testWidgets('Shift+. and Shift+, take the canvas bar\'s zoom step, along '
      'the zoom snap list', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AnicelApp());
    await tester.pumpAndSettle();

    String readout() => tester
        .widget<Text>(
          find.descendant(
            of: inMainCanvas(
              find.byKey(const ValueKey<String>('canvas-viewport-zoom-label')),
            ),
            matching: find.byType(Text),
          ),
        )
        .data!;

    await tester.tap(
      inMainCanvas(find.byKey(const ValueKey<String>('canvas-viewport-reset'))),
    );
    await tester.pumpAndSettle();
    expect(readout(), '100.00%');

    await _press(tester, LogicalKeyboardKey.period, shift: true);
    expect(readout(), '125.00%', reason: 'the next entry up, not ×1.25 by luck');
    await _press(tester, LogicalKeyboardKey.period, shift: true);
    expect(readout(), '150.00%');
    await _press(tester, LogicalKeyboardKey.comma, shift: true);
    expect(readout(), '125.00%');

    await tester.tap(
      inMainCanvas(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-in')),
      ),
    );
    await tester.pumpAndSettle();
    expect(readout(), '150.00%', reason: 'the button walks the same list');

    for (var i = 0; i < 4; i++) {
      await _press(tester, LogicalKeyboardKey.period, shift: true);
    }
    expect(
      readout(),
      '400.00%',
      reason: '200, 300, 400 — and past the last entry there is no step',
    );
  });
}
