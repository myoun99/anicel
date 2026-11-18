import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart' show codeOf, codeOfLines;

/// 🚨A KOTLIN NATIVE METHOD MEETS ITS RUST EXPORT, AND THE PLUGIN HANDS THE
/// ENGINE ITS CONTEXT AS IT ATTACHES.
///
/// Board android-dies-opening-the-sound-output (2026-11-16): the app died
/// two seconds after launch on the tablet. cpal's AAudio host asks the JVM
/// through `ndk_context::android_context()` as a stream opens, nothing had
/// set it, and its `expect` panicked across `qa_audio_device_open`. The
/// plugin now hands the application's context to the engine through a JNI
/// call — a third name written in two languages, beside the two the
/// library's own name broke (a_native_library_is_opened_by_the_name_it_is_
/// built_as_test). No test on this machine runs Android's Kotlin or the
/// engine's Android code, so the two halves are read against each other:
/// each `external fun` of the plugin's Kotlin is answered by the Rust
/// export JNI names it by, and each such export by a method that asks for
/// it.
void main() {
  test('every Kotlin external fun has the Rust export JNI looks for, and '
      'every export a method', () {
    final asked = <String>{
      for (final file in filesUnder('packages/gpu_engine/android/src'))
        if (file.path.endsWith('.kt'))
          ..._jniNamesAsked(file.readAsStringSync()),
    };
    final exported = <String>{
      for (final file in [
        ...filesUnder('packages/gpu_engine/rust/src'),
        ...filesUnder('packages/gpu_engine/rust/native'),
      ])
        if (file.path.endsWith('.rs'))
          ..._jniExports(file.readAsStringSync()),
    };

    expect(asked, isNotEmpty, reason: '⛔premise: the plugin has natives');
    expect(asked.difference(exported), isEmpty, reason: 'no Rust export');
    expect(exported.difference(asked), isEmpty, reason: 'no Kotlin method');
  });

  test('the plugin hands the engine its context as it attaches', () {
    final plugin = File(
      'packages/gpu_engine/android/src/main/kotlin/com/myoun/gpu_engine/'
      'GpuEnginePlugin.kt',
    ).readAsStringSync();
    final attach = RegExp(
      r'override fun onAttachedToEngine\([^)]*\)\s*\{([^}]*)\}',
    ).firstMatch(plugin);

    expect(attach, isNotNull, reason: 'the plugin no longer attaches here');
    expect(
      attach!.group(1),
      contains('handAndroidContext(binding.applicationContext)'),
    );
  });

  test('the scans read a planted method and export, not a comment', () {
    const kotlin = '''
package com.myoun.gpu_engine

object PenPoints {
    // private external fun old(x: Long)
    private external fun point(
        x: Double,
    )
}
''';
    const rust = '''
// pub extern "system" fn Java_com_myoun_gpu_1engine_PenPoints_old(
pub extern "system" fn Java_com_myoun_gpu_1engine_PenPoints_point(
''';

    expect(_jniNamesAsked(kotlin), {
      'Java_com_myoun_gpu_1engine_PenPoints_point',
    });
    expect(_jniExports(rust), {
      'Java_com_myoun_gpu_1engine_PenPoints_point',
    });
  });
}

/// The JNI names [kotlin]'s `external fun`s are looked up by: `Java_`, the
/// package with its dots as `_`, the class, the method — each `_` in a
/// name written `_1` (the JNI spec's escape).
Set<String> _jniNamesAsked(String kotlin) {
  final code = codeOfLines(kotlin);
  final package = RegExp(r'^package\s+([\w.]+)', multiLine: true)
      .firstMatch(code)!
      .group(1)!;
  // At a line's start, so a doc comment's 「the object the …」 is no owner.
  final owner = RegExp(
    r'^(?:\w+\s+)*(?:class|object)\s+(\w+)',
    multiLine: true,
  ).firstMatch(code)!;
  final methods = RegExp(
    r'^\s*(?:\w+\s+)*external fun\s+(\w+)',
    multiLine: true,
  );
  return {
    for (final method in methods.allMatches(code))
      [
        'Java',
        ...package.split('.').map(_escaped),
        _escaped(owner.group(1)!),
        _escaped(method.group(1)!),
      ].join('_'),
  };
}

/// The `Java_…` functions [rust] exports, outside a `//` comment.
Set<String> _jniExports(String rust) => {
  for (final line in rust.split('\n'))
    for (final match in RegExp(r'\bfn\s+(Java_\w+)').allMatches(codeOf(line)))
      match.group(1)!,
};

String _escaped(String name) => name.replaceAll('_', '_1');
