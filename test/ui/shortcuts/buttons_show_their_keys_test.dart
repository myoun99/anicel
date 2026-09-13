import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
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

  testWidgets('a menu row that presses a bound action prints the key at its '
      'right end, dim — 「저장 Ctrl+S」', (tester) async {
    // 🗣️유저 2026-09-13 (I-19-menu-keys, 1번): 「중간에 점 두는게아니라 저장
    // Ctrl+S 이런식으로. 단축키 텍스트는 흐린색. 단축키 텍스트 오른쪽정렬」.
    await _pumpApp(tester);
    await tester.tap(_button('top-strip-project-button'));
    await tester.pumpAndSettle();

    Finder inRow(String id, Finder text) => find.descendant(
      of: find.byKey(ValueKey<String>('menu-$id')),
      matching: text,
    );
    final keys = inRow('file-save', find.text('Ctrl+S'));
    expect(keys, findsOneWidget, reason: 'the live key, spelled once');
    expect(
      tester.widget<Text>(keys).style!.color,
      AppColors.textDim,
      reason: '흐린색',
    );
    expect(
      tester.getTopLeft(keys).dx,
      greaterThan(tester.getTopRight(inRow('file-save', find.text('Save'))).dx),
      reason: 'after the label — 「저장 Ctrl+S」, no dot leaders between',
    );
    final longer = inRow('file-save-as', find.text('Ctrl+Shift+S'));
    expect(
      tester.getTopRight(keys).dx,
      tester.getTopRight(longer).dx,
      reason: '오른쪽정렬 — two keys of different widths end at one edge',
    );
    expect(
      tester.getTopLeft(keys).dx,
      isNot(tester.getTopLeft(longer).dx),
      reason: 'the widths really differ, or the edge above measured nothing',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('menu-file-open')),
        matching: find.textContaining('Ctrl'),
      ),
      findsNothing,
      reason: 'a row that presses no action prints no key',
    );
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
