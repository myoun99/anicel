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

/// [key] pressed under Shift, TYPING [typed] — how a layout that puts a
/// character on Shift delivers it: Windows names a printable key by what it
/// types unshifted, so a JIS `=` arrives as `minus` with Shift held.
Future<void> _typeUnderShift(
  WidgetTester tester,
  LogicalKeyboardKey key,
  String typed,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(key, character: typed);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
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
  /// 🚨F-156 (유저 2026-09-17): 「붙여넣기 기본값 단축키 변경. 독립 붙여넣기를
  /// 컨트롤+v로, 링크 붙여넣기를 컨트롤+b로」.
  ///
  /// ⚠️Counted in CELS as well as glyphs: an unnamed drawing prints the same
  /// mark whether a paste linked it or minted a new one, so the cells alone
  /// cannot tell the two keys apart — the old mapping passed a glyph test.
  for (final (name, key, button, cels) in const [
    (
      'Ctrl+V is the pill\'s Paste independent — a cel of its own',
      LogicalKeyboardKey.keyV,
      'shared-paste-independent-button',
      2,
    ),
    (
      'Ctrl+B is the pill\'s Paste linked — the same cel again',
      LogicalKeyboardKey.keyB,
      'shared-paste-linked-button',
      1,
    ),
  ]) {
    testWidgets(name, (tester) async {
      int celsOnTheRow() => tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session
          .activeLayer!
          .frames
          .length;
      Future<void> copyThenMove() async {
        await _press(tester, LogicalKeyboardKey.keyC, control: true);
        await tapHomeTimelineCell(
          tester,
          const ValueKey<String>('timeline-cell-default-layer-1-1'),
        );
      }

      final byButton = await _onAFreshDrawing(tester, () async {
        await copyThenMove();
        await tapToolbarButton(tester, ValueKey<String>(button));
      });
      expect(byButton.after, isNot(byButton.before), reason: 'LIVENESS');
      expect(celsOnTheRow(), cels, reason: 'what the $button makes');

      final byKey = await _onAFreshDrawing(tester, () async {
        await copyThenMove();
        await _press(tester, key, control: true);
      });
      expect(byKey.after, byButton.after);
      expect(celsOnTheRow(), cels);
    });
  }

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

  // 🚨A KEY IS THE CHARACTER IT TYPES (a-key-is-the-character-it-types) —
  // 유저 2026-09-13: 「일본어 키보드나 한국어 상태등 키보드가 영어가 아닐때도
  // 대응하도록」. The IME half landed first; this is the LAYOUT half.
  testWidgets('a JIS `=` — Shift+- TYPING it — is the same Solo', (
    tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    expect(session.visibilitySolo.layerVisibilitySoloEnabled, isFalse);

    await _typeUnderShift(tester, LogicalKeyboardKey.minus, '=');
    expect(session.visibilitySolo.layerVisibilitySoloEnabled, isTrue);

    await _typeUnderShift(tester, LogicalKeyboardKey.minus, '=');
    expect(session.visibilitySolo.layerVisibilitySoloEnabled, isFalse);
  });

  testWidgets('⛔the same keys typing something else are not Solo — Shift+- '
      'is `_` on a US board', (tester) async {
    await tester.pumpWidget(const AnicelApp());
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;

    await _typeUnderShift(tester, LogicalKeyboardKey.minus, '_');
    expect(
      session.visibilitySolo.layerVisibilitySoloEnabled,
      isFalse,
      reason: 'the binding is the character `=`, not the `-` key',
    );
  });

  testWidgets('⛔a key that types the character with NO Shift is not the '
      'binding — the numpad `.` steps no frame', (tester) async {
    await tester.pumpWidget(const AnicelApp());
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final standingAt = session.currentFrameIndex;

    await tester.sendKeyEvent(
      LogicalKeyboardKey.numpadDecimal,
      character: '.',
    );
    await tester.pumpAndSettle();
    expect(
      session.currentFrameIndex,
      standingAt,
      reason: 'only a layout that puts the character on SHIFT reaches it '
          'under another key — the numpad is a key of its own',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.period, character: '.');
    await tester.pumpAndSettle();
    expect(
      session.currentFrameIndex,
      isNot(standingAt),
      reason: '⛔전제: `.` itself steps the frame here',
    );
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
