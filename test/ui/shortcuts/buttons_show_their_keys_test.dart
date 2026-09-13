import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

import '../../helpers/panel_finders.dart';

/// 🗣️I-19 (유저 2026-09-12): 「이런 버튼들 툴버튼도 그런데 툴팁으로 숏컷 키
/// 보여주도록. 낡지않을구조로.」 — and 09-13: 「맥은 컨트롤키가 다르다
/// 했던가? … 멀티플랫폼부분도 신경써서」.
///
/// 「낡지않을」 is measured the way it would go stale: re-record a key and read
/// the SAME mounted button again. The toolbars cache their groups, so a
/// tooltip composed where a group is built would keep the old key.
Future<void> _pumpApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1700, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const AnicelApp());
  await tester.pumpAndSettle();
}

String _tooltip(WidgetTester tester, Finder face) =>
    tester.widget<AppIconButtonFace>(face).tooltip;

Finder _button(String key) => find.byKey(ValueKey<String>(key));

void main() {
  testWidgets('a button that presses a bound action shows the action\'s key '
      '— the pill, the rail, the tools and the canvas bar alike', (
    tester,
  ) async {
    await _pumpApp(tester);

    for (final (key, tooltip) in const [
      ('shared-cut-button', 'Cut (Ctrl+X)'),
      ('shared-copy-button', 'Copy (Ctrl+C)'),
      ('shared-paste-linked-button', 'Paste linked (Ctrl+V)'),
      ('shared-paste-independent-button', 'Paste independent (Ctrl+B)'),
      ('shared-delete-button', 'Delete (Delete)'),
      ('undo-button', 'Undo (Ctrl+Z)'),
      ('redo-button', 'Redo (Ctrl+Shift+Z)'),
      ('tool-brush-button', 'Brush Tool (B)'),
      ('tool-eraser-button', 'Eraser Tool (E)'),
      // One button, two actions: both keys land on it.
      ('tool-select-button', 'Select Tool (M, L)'),
      ('tool-move-button', 'Move / Transform Tool (V, Ctrl+T)'),
      // The film verbs ship unbound, so they show their name alone.
      ('new-frame-button', 'Add'),
    ]) {
      expect(_tooltip(tester, _button(key)), tooltip, reason: key);
    }
    expect(
      _tooltip(tester, inMainCanvas(_button('canvas-viewport-zoom-in'))),
      'Zoom In (Shift+.)',
    );
  });

  testWidgets('re-recording a key re-labels the SAME mounted button — the '
      'cached toolbar group included', (tester) async {
    await _pumpApp(tester);
    final bindings = tester
        .widget<EditorShortcutScope>(find.byType(EditorShortcutScope))
        .notifier!;

    bindings.setActivators(EditorActionIds.editCopy, const [
      SingleActivator(LogicalKeyboardKey.keyK, control: true),
    ]);
    await tester.pumpAndSettle();
    expect(_tooltip(tester, _button('shared-copy-button')), 'Copy (Ctrl+K)');

    bindings.setActivators(EditorActionIds.editCopy, const []);
    await tester.pumpAndSettle();
    expect(
      _tooltip(tester, _button('shared-copy-button')),
      'Copy',
      reason: 'an unbound action shows no key at all',
    );

    // An unbound film verb gains one the moment it is recorded.
    bindings.setActivators(EditorActionIds.frameNewDrawing, const [
      SingleActivator(LogicalKeyboardKey.keyN),
    ]);
    await tester.pumpAndSettle();
    expect(_tooltip(tester, _button('new-frame-button')), 'Add (N)');

    // And a control that is not an AppIconButton reads the same bindings.
    String commaTooltip() => tester
        .widget<Tooltip>(
          find
              .ancestor(
                of: _button('set-comma-1-button'),
                matching: find.byType(Tooltip),
              )
              .first,
        )
        .message!;
    expect(commaTooltip(), endsWith('(1)'));
    bindings.setActivators(EditorActionIds.timelineComma1, const [
      SingleActivator(LogicalKeyboardKey.keyQ),
    ]);
    await tester.pumpAndSettle();
    expect(commaTooltip(), endsWith('(Q)'));
  });

  testWidgets('on a Mac the same buttons say ⌘, and Shift keeps its glyph', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _pumpApp(tester);
      expect(_tooltip(tester, _button('shared-copy-button')), 'Copy (⌘C)');
      expect(_tooltip(tester, _button('redo-button')), 'Redo (⇧⌘Z)');
      expect(_tooltip(tester, _button('tool-brush-button')), 'Brush Tool (B)');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
