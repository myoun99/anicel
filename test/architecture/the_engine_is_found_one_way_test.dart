import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★ONE WAY TO FIND THE ENGINE, and it is the one that fails on CI.
///
/// `test/helpers/native_engine_path.dart` resolves the engine per platform,
/// honours `QA_ENGINE_PATH`, and FAILS on a builder that was told to have
/// one. A suite that spells out the Windows build path for itself bypasses
/// all three: on a Mac it can only skip, and it skips green. Seven suites
/// had done that by 2026-09-10, and seventeen tests skipped on Codemagic in
/// the one step that exists to check that machine.
///
/// ⛔A source scan and not a behaviour test: a hardcoded path WORKS on the
/// machine that wrote it, so no test run there can see it.
void main() {
  test('no suite spells out where the engine lives', () {
    final hardcoded = RegExp(r'native_standalone[\/]+Release[\/]+qa_engine');
    const resolver = 'helpers/native_engine_path.dart';
    final offenders = <String>[
      for (final file in Directory('test').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            !file.path.replaceAll(r'\', '/').endsWith(resolver) &&
            hardcoded.hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'resolve the engine with nativeEngineLibraryPathOrNull() '
          'from $resolver — it is the only lookup that fails on CI',
    );
  });
}
