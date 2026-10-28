// 🗣️유저 2026-10-25 (board `frame-panels-build-in-one-frame-Q2`): 「손가락으로
// 통일」 — everything a press acts on points with the hand while it is live,
// and with the arrow while it is dead ([AppCursors]). A control in this app
// gets its cursor one of three ways, and these hold each: a Material button
// reads the theme, an `InkWell` names it (no theme reaches one), and the
// app's own faces resolve it.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/tool_setting_rows.dart';
import 'package:anicel/src/ui/color/color_slot_pair.dart';
import 'package:anicel/src/ui/color/color_status_bar.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/command_pill.dart';

import '../../tool/source_brackets.dart';
import '../helpers/dart_sources.dart';

/// Each `InkWell(` / `InkResponse(` in [source] whose own arguments name no
/// `mouseCursor`, by line of [source] with its comments taken out.
Iterable<int> _silentInks(String source) sync* {
  final code = withoutComments(source);
  final call = RegExp(r'(^|[^A-Za-z_])(InkWell|InkResponse)\(');
  for (final match in call.allMatches(code)) {
    final openAt = match.end - 1;
    if (namedArgument(code, openAt, 'mouseCursor') == null) {
      yield '\n'.allMatches(code.substring(0, openAt)).length + 1;
    }
  }
}

MouseCursor _cursorAt(WidgetTester tester, Offset position) {
  final result = HitTestResult();
  RendererBinding.instance.hitTestInView(result, position, tester.view.viewId);
  for (final entry in result.path) {
    if (entry.target case final MouseTrackerAnnotation annotation
        when annotation.cursor != MouseCursor.defer) {
      return annotation.cursor;
    }
  }
  return SystemMouseCursors.basic;
}

Future<MouseCursor> _cursorOf(WidgetTester tester, Widget control) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Material(
        child: Center(child: KeyedSubtree(key: _control, child: control)),
      ),
    ),
  );
  return _cursorAt(tester, tester.getCenter(find.byKey(_control)));
}

const _control = ValueKey<String>('control');

void main() {
  test('every InkWell names its cursor — no theme reaches one', () {
    final silent = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final path = libPath(file);
      for (final line in _silentInks(file.readAsStringSync())) {
        silent.add('$path:$line');
      }
    }
    expect(
      silent,
      isEmpty,
      reason:
          'an InkWell shows the arrow on a desktop unless it says otherwise '
          '— `mouseCursor: AppCursors.press`',
    );
  });

  test('the hand is spelled once — in AppCursors', () {
    final spelled = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final lines = withoutComments(file.readAsStringSync()).split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('SystemMouseCursors.click')) {
          spelled.add('${libPath(file)}:${i + 1}');
        }
      }
    }
    expect(spelled, isEmpty);
  });

  testWidgets('every Material button family points with the hand while it '
      'is live, and with the arrow while it is dead', (tester) async {
    Widget word(String text) => Text(text);
    for (final (family, make) in <(String, Widget Function(VoidCallback?))>[
      ('TextButton', (p) => TextButton(onPressed: p, child: word('OK'))),
      ('FilledButton', (p) => FilledButton(onPressed: p, child: word('OK'))),
      (
        'OutlinedButton',
        (p) => OutlinedButton(onPressed: p, child: word('OK')),
      ),
      (
        'IconButton',
        (p) => IconButton(onPressed: p, icon: const Icon(Icons.add)),
      ),
      (
        'ListTile',
        (p) => SizedBox(
          width: 200,
          child: ListTile(onTap: p, title: word('Row')),
        ),
      ),
      (
        'InkWell',
        (p) => InkWell(
          mouseCursor: AppCursors.press,
          onTap: p,
          child: const SizedBox(width: 40, height: 40),
        ),
      ),
    ]) {
      expect(
        await _cursorOf(tester, make(() {})),
        SystemMouseCursors.click,
        reason: '$family, live',
      );
      expect(
        await _cursorOf(tester, make(null)),
        SystemMouseCursors.basic,
        reason: '$family, dead',
      );
    }
  });

  testWidgets("the app's own faces point with the hand while they are live, "
      'and with the arrow while they are dead', (tester) async {
    Future<MouseCursor> at(Widget control, String key) async {
      await _cursorOf(tester, control);
      return _cursorAt(
        tester,
        tester.getCenter(find.byKey(ValueKey<String>(key))),
      );
    }

    for (final live in [true, false]) {
      final press = live ? () {} : null;
      final hand = live ? SystemMouseCursors.click : SystemMouseCursors.basic;
      final strap = StrapIconButton(
        buttonKey: 'strap',
        menuKey: 'strap-caret',
        icon: Icons.add,
        tooltip: 'Add',
        onPressed: press,
        entriesBuilder: () => const [],
      );
      expect(await at(strap, 'strap'), hand, reason: 'icon button, $live');
      expect(await at(strap, 'strap-caret'), hand, reason: 'caret, $live');
      expect(
        await at(
          ToolSettingAction(keyValue: 'act', label: 'Go', onPressed: press),
          'act',
        ),
        hand,
        reason: 'tool setting action, $live',
      );
    }
    final bar = SizedBox(
      width: 320,
      child: ColorStatusBar(color: 0xFF336699, onColorChanged: (_) {}),
    );
    for (final readout in ['color-status-hex', 'color-status-r']) {
      expect(await at(bar, readout), SystemMouseCursors.click, reason: readout);
    }
    expect(
      await at(
        ColorSlotPair(
          foreground: const Color(0xFF000000),
          background: const Color(0xFFFFFFFF),
          onBackgroundTap: () {},
        ),
        'color-wheel-background-swatch',
      ),
      SystemMouseCursors.click,
      reason: 'the swap swatch',
    );
  });

  testWidgets("a popup menu's row points with the hand while it is live, "
      'and with the arrow while it is dead', (tester) async {
    for (final live in [true, false]) {
      await _cursorOf(
        tester,
        PopupMenuButton<int>(
          itemBuilder: (_) => [
            PopupMenuItem<int>(
              value: 1,
              enabled: live,
              child: const Text('Row'),
            ),
          ],
          child: const Text('Open'),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        _cursorAt(tester, tester.getCenter(find.text('Row'))),
        live ? SystemMouseCursors.click : SystemMouseCursors.basic,
        reason: live ? 'live' : 'dead',
      );
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    }
  });
}
