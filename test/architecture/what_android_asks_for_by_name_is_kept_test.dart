import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨WHAT THE ANDROID PLUGIN ASKS FLUTTER FOR BY NAME, A RELEASE KEEPS.
///
/// GpuEnginePlugin.kt looks up patch 0006's `createHardwareBufferTexture`
/// by name, so the app still builds on Flutter's own engine; no Java code
/// calls it, and a release's R8 took it out of FlutterRenderer — the QA
/// APK's canvas stood empty, the plugin finding Anicel's engine "not
/// Anicel's" (검증 2026-11-24 01:42, card
/// the-galaxy-tab-canvas-went-slow-on-build-1095). The keep rule beside
/// the plugin holds it — and the name is written twice, in the lookup and
/// in the rule: changed in one alone, the release drops it again without
/// a word (관제 01:44). This reads both.
void main() {
  const plugin =
      'packages/gpu_engine/android/src/main/kotlin/com/myoun/gpu_engine/GpuEnginePlugin.kt';
  const rules = 'packages/gpu_engine/android/consumer-rules.pro';
  const gradle = 'packages/gpu_engine/android/build.gradle.kts';

  test('each method the plugin looks up by name is kept, with its '
      'parameters, and the rules ship with the plugin', () {
    // A class, `X::class.java`; a primitive, `java.lang.Long.TYPE` (`long`).
    const parameter = r'([\w.]+)::class\.java|java\.lang\.(\w+)\.TYPE';
    final lookups = RegExp(
      r'getMethod\(\s*"(\w+)"((?:\s*,\s*(?:' + parameter + r'))*)\s*,?\s*\)',
    ).allMatches(File(plugin).readAsStringSync()).map((found) {
      final parameters = RegExp(parameter)
          .allMatches(found.group(2)!)
          .map(
            (type) =>
                type.group(1)?.split('.').last ?? type.group(2)!.toLowerCase(),
          )
          .join(',');
      return '${found.group(1)}($parameters)';
    }).toSet();
    expect(lookups, isNotEmpty, reason: 'CONTROL: the lookup is found');

    final kept = RegExp(r'\*\*\*\s+(\w+)\(([^)]*)\)\s*;')
        .allMatches(File(rules).readAsStringSync())
        .map((found) {
      final parameters = found
          .group(2)!
          .split(',')
          .map((type) => type.trim().split('.').last)
          .where((type) => type.isNotEmpty)
          .join(',');
      return '${found.group(1)}($parameters)';
    }).toSet();

    expect(kept, lookups, reason: 'what is asked for by name is kept');
    expect(
      File(gradle).readAsStringSync(),
      contains('consumerProguardFiles("consumer-rules.pro")'),
      reason: 'the rules reach the app that builds the plugin',
    );
  });
}
