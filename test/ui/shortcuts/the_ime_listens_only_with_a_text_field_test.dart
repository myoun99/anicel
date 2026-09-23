import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/shortcuts/keyboard_ime_switch.dart';

/// 🗣️I-19 ④ (유저 2026-09-13): 「일본어 키보드나 한국어 상태등 키보드가
/// 영어가 아닐때도 대응하도록」 — 「숏컷 얘기임. 지금은 일본어 히라가나상태로
/// 치면 이상한 텍스트입력기? 같은 게 뜸.」
///
/// Flutter's Windows engine drops every key an IME takes, so a shortcut can
/// only see a key the IME was not listening for. The IME listens while a
/// text field holds the keyboard and nowhere else ([KeyboardImeSwitch]).
///
/// ⚠️TWO HALVES THAT CANNOT SEE EACH OTHER: Dart says when, the runner
/// switches the window's input context. No Dart test reaches the C++, so
/// the last group READS the runner, the way the close-button pin does
/// (`the_close_button_asks_the_app_test.dart`).
void main() {
  late List<Object?> said;

  setUp(() {
    said = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(KeyboardImeSwitch.channel, (call) async {
          said.add('${call.method}:${call.arguments}');
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(KeyboardImeSwitch.channel, null);
  });

  /// A text field above a focusable stand-in for the canvas, the canvas
  /// holding the keyboard.
  Future<({FocusNode field, FocusNode canvas})> pumpFieldAndCanvas(
    WidgetTester tester,
  ) async {
    final field = FocusNode();
    final canvas = FocusNode();
    addTearDown(field.dispose);
    addTearDown(canvas.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: field),
              Focus(
                focusNode: canvas,
                child: const SizedBox(width: 100, height: 100),
              ),
            ],
          ),
        ),
      ),
    );
    canvas.requestFocus();
    await tester.pump();
    return (field: field, canvas: canvas);
  }

  testWidgets(
    'the IME is off where a key is a command, on while a text field holds '
    'the keyboard, and off again when it lets go',
    (tester) async {
      final nodes = await pumpFieldAndCanvas(tester);
      final ime = KeyboardImeSwitch.install();
      addTearDown(() => ime?.uninstall());

      expect(
        said,
        ['setImeOpen:false'],
        reason: 'the canvas holds the keyboard: a key is a command, and an '
            'IME listening would swallow it',
      );

      nodes.field.requestFocus();
      await tester.pump();
      expect(said.last, 'setImeOpen:true', reason: 'a field types words');

      nodes.canvas.requestFocus();
      await tester.pump();
      expect(said.last, 'setImeOpen:false');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    '⛔nowhere but Windows does anything touch the channel — the other '
    'engines hand a key to the shortcuts before their text system',
    (tester) async {
      final nodes = await pumpFieldAndCanvas(tester);
      final ime = KeyboardImeSwitch.install();
      addTearDown(() => ime?.uninstall());

      nodes.field.requestFocus();
      await tester.pump();

      expect(ime, isNull);
      expect(said, isEmpty);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  group('the runner half', () {
    final runner = File('windows/runner/flutter_window.cpp')
        .readAsStringSync();

    test('it listens on the channel Dart speaks, for the method Dart sends',
        () {
      expect(
        runner,
        contains(
          'kKeyboardChannel[] = "${KeyboardImeSwitch.channel.name}";',
        ),
      );
      expect(
        runner,
        contains('kSetImeOpen[] = "${KeyboardImeSwitch.setImeOpen}";'),
      );
    });

    test('it switches the window\'s input context — the default one back '
        'for a field, none at all elsewhere', () {
      expect(
        runner,
        contains('ImmAssociateContextEx(view, nullptr, *open ? IACE_DEFAULT : 0)'),
      );
      expect(
        File('windows/runner/CMakeLists.txt').readAsStringSync(),
        contains('imm32.lib'),
        reason: 'ImmAssociateContextEx lives in imm32',
      );
    });

    test('main() installs the switch', () {
      expect(
        File('lib/main.dart').readAsStringSync(),
        contains('KeyboardImeSwitch.install()'),
      );
    });
  });
}
