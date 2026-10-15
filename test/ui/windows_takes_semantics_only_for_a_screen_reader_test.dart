import 'dart:io';

import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/platform_semantics_gate.dart';
import 'package:anicel/src/ui/ui_scale_binding.dart';

/// 🚨★★★ON WINDOWS THE PLATFORM'S ACCESSIBILITY REQUEST IS TAKEN ONLY WHILE
/// A SCREEN READER RUNS — every build (유저 2026-10-15, I-57-Q3), and a debug
/// build not even then (유저 2026-09-24) — see [PlatformSemanticsGate].
///
/// The runner says when the flag changed (`windows/runner/flutter_window.cpp`)
/// and no Dart test reaches the C++, so this file READS the runner's channel
/// literal and sends on it the way the runner does.
class _GateBinding extends AutomatedTestWidgetsFlutterBinding
    with PlatformSemanticsGate {
  bool reader = false;

  @override
  SemanticsGateInputs get semanticsGateInputs => (
    debugBuild: false,
    onWindows: true,
    environment: const {},
    screenReader: () => reader,
  );
}

void main() {
  final binding = _GateBinding();
  final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();
  final channel = RegExp(
    r'kScreenReaderChannel\[\] = "([^"]*)";',
  ).firstMatch(runner)?.group(1);

  test('who takes the request: a screen reader in every build but debug, '
      'which takes it only when asked to', () {
    bool refuses({
      required bool debugBuild,
      bool onWindows = true,
      bool screenReader = false,
      Map<String, String> environment = const {},
    }) => refusesPlatformSemantics(
      debugBuild: debugBuild,
      onWindows: onWindows,
      environment: environment,
      screenReader: screenReader,
    );

    expect(refuses(debugBuild: false), isTrue, reason: 'an IME asked');
    expect(refuses(debugBuild: false, screenReader: true), isFalse);
    expect(refuses(debugBuild: true, screenReader: true), isTrue);
    expect(
      refuses(
        debugBuild: true,
        environment: const {'ANICEL_DEBUG_SEMANTICS': '1'},
      ),
      isFalse,
    );
    expect(
      refuses(debugBuild: false, onWindows: false),
      isFalse,
      reason: 'other platforms ask only for the assistive technology they run',
    );
    expect(refuses(debugBuild: true, onWindows: false), isFalse);
  });

  test('the app wears the gate', () {
    expect(<AnicelBinding>[], isA<List<PlatformSemanticsGate>>());
  });

  test('the runner says it on the app\'s channel', () {
    expect(channel, screenReaderChannel);
  });

  testWidgets('🚨the platform\'s request waits for a screen reader, and goes '
      'with it — told on the runner\'s channel', (tester) async {
    Future<void> sayTheFlagChanged(bool running) async {
      binding.reader = running;
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        channel!,
        null,
        (_) {},
      );
      await tester.pump();
    }

    SemanticsNode? tree() => binding.renderViews.single.owner!.semanticsOwner
        ?.rootSemanticsNode;

    tester.platformDispatcher.semanticsEnabledTestValue = true;
    addTearDown(tester.platformDispatcher.clearSemanticsEnabledTestValue);
    await tester.pumpWidget(
      const Text('a', textDirection: TextDirection.ltr),
    );
    expect(binding.semanticsEnabled, isFalse, reason: 'only an IME asked');
    expect(tree(), isNull);

    await sayTheFlagChanged(true);
    expect(binding.semanticsEnabled, isTrue);
    expect(tree(), isNotNull);

    await sayTheFlagChanged(false);
    expect(binding.semanticsEnabled, isFalse);
    expect(tree(), isNull);

    // The platform's own request goes before the test ends: the binding
    // holds a handle for it whatever the gate answered.
    tester.platformDispatcher.clearSemanticsEnabledTestValue();
  }, semanticsEnabled: false);

  test('🚨the refusal is the question the framework asks, so a request that '
      'stood before the binding was made is refused too', () {
    // ↩️The platform's callback emptied in `initInstances` was the gate
    // until 2026-10-10 — the Surface Pro 11 asks before `main` runs, and
    // the framework takes that request as the binding is made.
    final source = File(
      'lib/src/ui/platform_semantics_gate.dart',
    ).readAsStringSync();
    expect(
      RegExp(
        r'bool get semanticsEnabled => !_refuses && super\.semanticsEnabled;',
      ).hasMatch(source),
      isTrue,
    );
  });
}
