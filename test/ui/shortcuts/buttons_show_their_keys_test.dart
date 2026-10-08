import 'package:anicel/src/ui/widgets/app_tooltip.dart';
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
      ('shared-paste-linked-button', 'Paste linked (Ctrl+B)'),
      ('shared-paste-independent-button', 'Paste independent (Ctrl+V)'),
      ('shared-delete-button', 'Delete (Delete)'),
      // F-261: the left hand's — Edit, the onion, and the sill's transport.
      // ↩️I-63 (유저 2026-10-03): Edit left X for Shift+F, and the onion
      // and the solo traded Q and T.
      ('shared-edit-button', 'Edit (Shift+F)'),
      ('rail-onion-skin-button', 'Toggle Onion Skin (T)'),
      ('playback-play-button', 'Play (Shift+X)'),
      ('playback-skip-to-start-button', 'To Start (Shift+Z)'),
      // 🗣️I-40: in the list since REC1-B (Ctrl+R), and silent about it.
      ('playback-record-voice-button', 'Record voice at the playhead (Ctrl+R)'),
      ('rail-visibility-solo-button', 'Solo active layer (Q)'),
      ('undo-button', 'Undo (Ctrl+Z)'),
      ('redo-button', 'Redo (Ctrl+Shift+Z)'),
      ('tool-brush-button', 'Brush Tool (B)'),
      ('tool-eraser-button', 'Eraser Tool (E)'),
      // One button, two actions: both keys land on it.
      ('tool-fill-button', 'Fill Tool (F)'),
      ('tool-guide-button', 'Guide Tool (G)'),
      // A tool with no key of its own shows its name alone — M, L and V
      // are retired (I-19, 2026-09-13).
      // ↩️The cut tool wore C until I-53 (유저 2026-09-28): C is the lasso
      // cut's tile now — 「잘라내기를 고르고싶으면 올가미 잘라내기의 단축키를
      // 사용할 예정」 — and the tool itself ships unbound.
      ('tool-cut-button', 'Cut Tool'),
      ('tool-select-button', 'Select Tool'),
      ('tool-move-button', 'Transform Tool'),
      // The film verbs ship unbound, so they show their name alone.
      ('new-frame-button', 'Add'),
    ]) {
      expect(_tooltip(tester, _button(key)), tooltip, reason: key);
    }
    // ↩️It read 'Zoom In (Shift+.)' until F-261 moved the zoom (Shift+E).
    expect(
      _tooltip(tester, inMainCanvas(_button('canvas-viewport-zoom-in'))),
      'Zoom In (Shift+E)',
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

    // The layer pill's ＋ is a strap — its body wears its action's name and
    // reads the same bindings (I-63 ③).
    const addLayer = 'timeline-toolbar-add-layer-button';
    expect(_tooltip(tester, _button(addLayer)), 'Add Layer');
    bindings.setActivators(EditorActionIds.layerAdd, const [
      SingleActivator(LogicalKeyboardKey.keyN, shift: true),
    ]);
    await tester.pumpAndSettle();
    expect(_tooltip(tester, _button(addLayer)), 'Add Layer (Shift+N)');

    // And a control that is not an AppIconButton reads the same bindings.
    String commaTooltip() => tester
        .widget<Tooltip>(
          find
              .ancestor(
                of: _button('set-comma-1-button'),
                matching: find.byType(AppTooltip),
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
    // Save As and its Ctrl+Shift+S are one level in since backlog-21-Q1, so
    // this menu's second, longer key is one recorded here.
    tester
        .widget<EditorShortcutScope>(find.byType(EditorShortcutScope))
        .notifier!
        .setActivators(EditorActionIds.fileNew, const [
          SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true),
        ]);
    await tester.pumpAndSettle();
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
      AppColors.shortcutKeys,
      reason: '흐린색 — and 「진짜 흐리게」',
    );
    expect(
      tester.getTopLeft(keys).dx,
      greaterThan(tester.getTopRight(inRow('file-save', find.text('Save'))).dx),
      reason: 'after the label — 「저장 Ctrl+S」, no dot leaders between',
    );
    final longer = inRow('file-new', find.text('Ctrl+Shift+N'));
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

  testWidgets('a blend mode\'s row in the strip\'s list prints its key — '
      'every mode is an action (I-31), and the row it is picked from says '
      'so', (tester) async {
    await _pumpApp(tester);
    await tester.tap(_button('brush-tool-blend-menu-button'));
    await tester.pumpAndSettle();

    Finder inRow(String mode, Finder text) => find.descendant(
      of: find.byKey(ValueKey<String>('brush-tool-blend-$mode')),
      matching: text,
    );
    expect(inRow('multiply', find.text('F5')), findsOneWidget);
    expect(inRow('color', find.text('F1')), findsOneWidget);
    expect(
      inRow('hardLight', find.textContaining(RegExp(r'^F\d'))),
      findsNothing,
      reason: 'a mode that ships with no key prints none',
    );
  });

  testWidgets('a tool library tile prints its key at the row\'s end the way '
      'a menu row does — the lasso\'s X', (tester) async {
    // 🗣️유저 2026-09-13: 「선택도구의 올가미 선택에 w로 두고싶어」 —
    // ↩️F-261 (유저 2026-10-02): W walks up the sheet now, and 「올가미를 z」.
    // ↩️I-63 (유저 2026-10-03): 「올가미선택을 x로두고 z는 비워두도록」.
    await _pumpApp(tester);
    await tester.tap(_button('tool-select-button'));
    await tester.pumpAndSettle();

    final lasso = find.byKey(const ValueKey<String>('sub-tool-select-lasso'));
    final key = find.descendant(of: lasso, matching: find.text('X'));
    expect(key, findsOneWidget);
    expect(tester.widget<Text>(key).style!.color, AppColors.shortcutKeys);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('sub-tool-select-rect')),
        matching: find.byType(Text),
      ),
      findsOneWidget,
      reason: 'an unbound tile prints its name and nothing else',
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
