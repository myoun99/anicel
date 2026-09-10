import 'dart:io';

import 'package:flutter_test/flutter_test.dart' show fail;

/// Where a locally built native engine can be found — the ONE resolver
/// every parity/benchmark suite shares.
///
/// The suites used to hardcode `build\native_standalone\Release\
/// qa_engine.dll`, so on macOS and Linux they could only ever skip: the
/// byte-parity pins that exist to catch a compiler disagreeing with the
/// Dart reference never ran on the platforms most likely to disagree
/// (Apple clang on arm64, gcc on x86_64). Resolving per platform — and
/// honoring the `QA_ENGINE_PATH` override CI sets — is what makes them
/// real everywhere.
///
/// Null = no engine built here, on a machine that was not told to have
/// one; callers skip, and say why.
///
/// 🚨★★★**ON A CI BUILDER A MISSING ENGINE FAILS HERE, NOT IN THE CALLER.**
/// [nativeEngineRequired] used to be a flag every suite had to remember to
/// read, and 27 of the 40 that resolved an engine here did not — they
/// skipped, and a skipped parity suite prints the same green as a passing
/// one. Seven more never called this at all and kept the hardcoded Windows
/// path, so on Codemagic's Mac (2026-09-10) they skipped seventeen tests in
/// the one step that exists to check that machine. Failing inside the
/// resolver means no caller can turn「CI built nothing」into a skip: a call
/// at the top of `main` fails the file's load, a call inside a test fails
/// that test.
String? nativeEngineLibraryPathOrNull() {
  final override = Platform.environment['QA_ENGINE_PATH'];
  if (override != null && override.isNotEmpty && File(override).existsSync()) {
    return override;
  }
  final root = Directory.current.path;
  String at(List<String> parts) =>
      [root, ...parts].join(Platform.pathSeparator);
  final candidates = <String>[
    if (Platform.isWindows)
      at(['build', 'native_standalone', 'Release', 'qa_engine.dll']),
    if (Platform.isMacOS) ...[
      // The plain cmake build (Makefile generator: no config subdir).
      at(['build', 'native_standalone', 'libqa_engine.dylib']),
      at(['build', 'ci-apple', 'libqa_engine.dylib']),
    ],
    if (Platform.isLinux) ...[
      at(['build', 'native_standalone', 'libqa_engine.so']),
      at(['build', 'ci-gcc', 'libqa_engine.so']),
    ],
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  if (nativeEngineRequired) {
    fail(nativeEngineMissingSkipReason);
  }
  return null;
}

/// The message a skipped suite prints, so the reason is never a mystery.
const String nativeEngineMissingSkipReason =
    'no locally built native engine — build it with: '
    'cmake -S packages/qa_native/src -B build/native_standalone && '
    'cmake --build build/native_standalone --config Release '
    '(or set QA_ENGINE_PATH)';

/// Whether a missing engine must FAIL rather than skip.
///
/// A skipped parity suite and a passing one look identical in a CI summary,
/// and this project has now been bitten by that twice: #614 (the pins were
/// hardcoded to a Windows path, so macOS and Linux could only skip) and the
/// Linux job that never built an engine at all. Every CI job that builds a
/// binary sets `QA_REQUIRE_NATIVE=1`, so if the build silently stops
/// producing one, the suites say so instead of going quiet — and the
/// resolver above is where they say it.
///
/// ⛔A suite reads this only to ask what the resolver cannot: that the
/// engine LOADS — an ABI match, a symbol, the OS encoder. Asking again
/// whether it EXISTS is the resolver's answer written a second time, and
/// the six suites that did so lost that branch on 2026-09-10.
///
/// Local runs leave it unset and keep skipping gracefully — nobody should
/// need cmake installed to run the Dart tests.
bool get nativeEngineRequired =>
    Platform.environment['QA_REQUIRE_NATIVE'] == '1';
