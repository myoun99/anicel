// 🗣️유저 2026-10-25 (board `frame-panels-build-in-one-frame-Q2`): 「손가락으로
// 통일」 — everything a press acts on points with the hand while it is live,
// and with the arrow while it is dead ([AppCursors]). A control in this app
// gets its cursor one of three ways, and these hold each: a Material button
// reads the theme, an `InkWell` names it (no theme reaches one), and the
// app's own faces resolve it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// Folders whose `InkWell`s are another lane's to change, with why — and
/// how many still say nothing, so a fix there shrinks this by hand.
const _notYet = <String, (String, int)>{
  'lib/src/ui/export/': (
    "the save lane's (서피스11 저장) — handed over 2026-10-25",
    16,
  ),
  'lib/src/ui/import/': (
    "the save lane's (서피스11 저장) — handed over 2026-10-25",
    4,
  ),
};

/// Each `InkWell(` / `InkResponse(` in [source] whose arguments name no
/// `mouseCursor`, by line.
Iterable<int> _silentInks(String source) sync* {
  final call = RegExp(r'(^|[^A-Za-z_])(InkWell|InkResponse)\(');
  for (final match in call.allMatches(source)) {
    final lineStart = source.lastIndexOf('\n', match.start) + 1;
    if (source.substring(lineStart, match.start).trimLeft().startsWith('//')) {
      continue;
    }
    var depth = 0;
    var end = match.end - 1;
    for (; end < source.length; end++) {
      final c = source[end];
      if (c == '(') depth++;
      if (c == ')' && --depth == 0) break;
    }
    final arguments = source.substring(match.end, end);
    // Its own arguments only — a nested call's are not its.
    final own = StringBuffer();
    var nested = 0;
    for (final c in arguments.split('')) {
      if (c == '(' || c == '[' || c == '{') nested++;
      if (c == ')' || c == ']' || c == '}') nested--;
      if (nested == 0) own.write(c);
    }
    if (!own.toString().contains('mouseCursor:')) {
      yield '\n'.allMatches(source.substring(0, match.start)).length + 1;
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
    final waiting = <String, int>{for (final folder in _notYet.keys) folder: 0};
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      final lines = _silentInks(file.readAsStringSync()).toList();
      if (lines.isEmpty) continue;
      final folder = _notYet.keys.where(path.startsWith).firstOrNull;
      if (folder != null) {
        waiting[folder] = waiting[folder]! + lines.length;
        continue;
      }
      silent.addAll([for (final line in lines) '$path:$line']);
    }
    expect(
      silent,
      isEmpty,
      reason:
          'an InkWell shows the arrow on a desktop unless it says otherwise '
          '— `mouseCursor: AppCursors.press`',
    );
    expect(waiting, {
      for (final MapEntry(:key, :value) in _notYet.entries) key: value.$2,
    }, reason: 'fixed one there? take it off _notYet');
  });

  test('the hand is spelled once — in AppCursors', () {
    final spelled = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (lines[i].contains('SystemMouseCursors.click')) {
          spelled.add('${file.path}:${i + 1}');
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
