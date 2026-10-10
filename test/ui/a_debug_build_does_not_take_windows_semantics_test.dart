import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/ui_scale_binding.dart';

/// 🚨A DEBUG BUILD ON WINDOWS DOES NOT TAKE THE PLATFORM'S ACCESSIBILITY
/// REQUEST (유저 2026-09-24, `debug-frames-pay-a-semantics-walk-Q1`:
/// 「디버그에서는 받지 않는다」) — the per-frame walk that request buys a
/// debug build was two thirds of the UI thread while drawing. Profile,
/// release and every other platform keep answering it, and one environment
/// variable takes it again.
void main() {
  test('a Windows debug build refuses, and one variable takes it again', () {
    bool refuses({
      required bool debugBuild,
      required bool onWindows,
      Map<String, String> environment = const {},
    }) => AnicelBinding.refusesPlatformSemantics(
      debugBuild: debugBuild,
      onWindows: onWindows,
      environment: environment,
    );

    expect(refuses(debugBuild: true, onWindows: true), isTrue);
    expect(
      refuses(
        debugBuild: true,
        onWindows: true,
        environment: const {'ANICEL_DEBUG_SEMANTICS': '1'},
      ),
      isFalse,
    );
    expect(
      refuses(debugBuild: false, onWindows: true),
      isFalse,
      reason: 'profile and release answer the platform as always',
    );
    expect(
      refuses(debugBuild: true, onWindows: false),
      isFalse,
      reason: 'the request that was measured is Windows\'',
    );
  });

  test('the refusal is the question the framework asks, so a request that '
      'stood before the binding was made is refused too', () {
    // ↩️The platform's callback emptied in `initInstances` was the gate
    // until 2026-10-10 — the Surface Pro 11 asks before `main` runs, and
    // the framework takes that request as the binding is made.
    final source = File('lib/src/ui/ui_scale_binding.dart').readAsStringSync();
    expect(
      RegExp(
        r'class AnicelBinding [\s\S]*?'
        r'bool get semanticsEnabled =>\s*'
        r'!_refusesPlatformSemantics && super\.semanticsEnabled;',
      ).hasMatch(source),
      isTrue,
    );
    // Decided as the binding is made, from the build it is.
    expect(
      RegExp(
        r'final bool _refusesPlatformSemantics = refusesPlatformSemantics\(\s*'
        r'debugBuild: kDebugMode,\s*onWindows: Platform\.isWindows,\s*'
        r'environment: Platform\.environment,',
      ).hasMatch(source),
      isTrue,
    );
  });
}
