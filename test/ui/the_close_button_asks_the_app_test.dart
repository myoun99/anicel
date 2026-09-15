import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/home_page.dart';

/// 🚨★★★F-128 — THE CLOSE BUTTON ASKS THE APP.
///
/// 유저 2026-09-14: 「그림 그렸는데 닫으려고 할때 편집한게 있으니 저장하라는
/// 메시지가 언제부턴가 안뜸」.
///
/// 🧪Measured on the Windows Release build before the fix (2026-09-15): the
/// new-frame button pressed (a drawing in the timeline, undo lit), WM_CLOSE
/// posted to the window — and five seconds later the process was gone with
/// nothing asked. Flutter's Windows engine asks the app about a close only
/// while the window is the process's LAST parentless top-level window, and
/// the process had two: GDI+, loaded at startup by pdfium.dll, keeps a
/// hidden one of its own.
///
/// The runner asks now (`windows/runner/flutter_window.cpp`), with the
/// framework's own question on the framework's own channel. Neither half
/// can see the other — no Dart test reaches the C++, and the C++ never sees
/// what Dart answers — so this file READS the runner's literals and sends
/// them to the app the way the runner does.
///
/// The other half of F-128 — a save that cleared edits it never wrote — is
/// `test/ui/session/a_save_is_clean_only_as_of_what_it_wrote_test.dart`.
void main() {
  final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();

  String literal(String name) {
    final spelled = RegExp(
      '$name\\[\\] =\\s+(?:R"\\((.*?)\\)"|"([^"]*)");',
      dotAll: true,
    ).firstMatch(runner);
    if (spelled == null) {
      fail('the runner no longer spells $name');
    }
    return spelled.group(1) ?? spelled.group(2)!;
  }

  test('the runner asks before the engine sees the close', () {
    final asks = runner.indexOf('message == WM_CLOSE');
    final engine = runner.indexOf('HandleTopLevelWindowProc(');
    expect(
      asks,
      isNonNegative,
      reason: 'the close goes to the engine, which does not ask while any '
          'hidden window lives in the process',
    );
    expect(engine, isNonNegative);
    expect(
      asks,
      lessThan(engine),
      reason: 'where the engine CAN ask it asks as well — two windows for '
          'one close',
    );
  });

  Future<void> makeDirty(WidgetTester tester) async {
    final button = find.byKey(const ValueKey<String>('new-frame-button'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  /// The runner's bytes on the runner's channel. Returns a reader for the
  /// app's answer, which exists once whatever the app asked is answered.
  String? Function() askAsTheRunnerDoes(WidgetTester tester) {
    String? answer;
    unawaited(
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        literal('kPlatformChannel'),
        ByteData.sublistView(utf8.encode(literal('kRequestAppExit'))),
        (reply) => answer = reply == null
            ? ''
            : utf8.decode(Uint8List.sublistView(reply)),
      ),
    );
    return () => answer;
  }

  const gate = ValueKey<String>('system-exit-dialog');

  testWidgets('an EDITED project: the question opens the gate, and Cancel '
      'keeps the window', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();
    await makeDirty(tester);

    final answer = askAsTheRunnerDoes(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(gate), findsOneWidget);
    expect(answer(), isNull, reason: 'the app answers once the person has');

    await tester.tap(find.byKey(const ValueKey<String>('system-exit-cancel')));
    await tester.pumpAndSettle();
    expect(answer(), isNotNull);
    expect(answer(), isNot(contains(literal('kAppSaidExit'))));
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('an EDITED project: Close lets the window go', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();
    await makeDirty(tester);

    final answer = askAsTheRunnerDoes(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('system-exit-close')));
    await tester.pumpAndSettle();

    expect(answer(), contains(literal('kAppSaidExit')));
  });

  testWidgets('an UNEDITED project lets the window go without asking', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();

    final answer = askAsTheRunnerDoes(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(gate), findsNothing);
    expect(answer(), contains(literal('kAppSaidExit')));
  });
}
