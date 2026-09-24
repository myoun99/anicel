import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/ui_scale_binding.dart';

/// 🚨A DEBUG BUILD ON WINDOWS DOES NOT TAKE THE PLATFORM'S ACCESSIBILITY
/// REQUEST (유저 2026-09-24, `debug-frames-pay-a-semantics-walk-Q1`:
/// 「디버그에서는 받지 않는다」) — the per-frame walk that request buys a
/// debug build was two thirds of the UI thread while drawing. Profile,
/// release and every other platform keep answering it, and one environment
/// variable opens the gate again.
void main() {
  testWidgets('the gate closes on a Windows debug build only, and one '
      'variable opens it', (tester) async {
    final dispatcher = tester.binding.platformDispatcher;
    final original = dispatcher.onSemanticsEnabledChanged;
    addTearDown(() => dispatcher.onSemanticsEnabledChanged = original);
    void heard() {}

    void close({
      required bool debugBuild,
      required bool onWindows,
      Map<String, String> environment = const {},
    }) {
      dispatcher.onSemanticsEnabledChanged = heard;
      AnicelBinding.closePlatformSemanticsGate(
        dispatcher,
        debugBuild: debugBuild,
        onWindows: onWindows,
        environment: environment,
      );
    }

    close(debugBuild: true, onWindows: true);
    expect(dispatcher.onSemanticsEnabledChanged, isNull);

    close(
      debugBuild: true,
      onWindows: true,
      environment: const {'ANICEL_DEBUG_SEMANTICS': '1'},
    );
    expect(dispatcher.onSemanticsEnabledChanged, same(heard));

    close(debugBuild: false, onWindows: true);
    expect(
      dispatcher.onSemanticsEnabledChanged,
      same(heard),
      reason: 'profile and release answer the platform as always',
    );

    close(debugBuild: true, onWindows: false);
    expect(
      dispatcher.onSemanticsEnabledChanged,
      same(heard),
      reason: 'the request that was measured is Windows\'',
    );
  });

  test('the app binding closes the gate as it starts', () {
    final source = File('lib/src/ui/ui_scale_binding.dart').readAsStringSync();
    // Inside AnicelBinding's own initInstances: the body runs to the first
    // two-space closing brace, and the call must come before it.
    expect(
      RegExp(
        r'class AnicelBinding [\s\S]*?void initInstances\(\) \{'
        r'(?:(?!\r?\n  \}\r?\n)[\s\S])*?closePlatformSemanticsGate\(\s*'
        r'platformDispatcher,\s*debugBuild: kDebugMode,\s*'
        r'onWindows: Platform\.isWindows,\s*'
        r'environment: Platform\.environment,',
      ).hasMatch(source),
      isTrue,
    );
  });
}
