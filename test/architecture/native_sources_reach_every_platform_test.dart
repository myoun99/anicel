import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★EVERY SOURCE THE ENGINE COMPILES ON ONE PLATFORM COMPILES ON ALL
/// OF THEM.
///
/// The engine is one C code base built three ways: CMake for Windows,
/// Linux and Android (`build.gradle` points at the same CMakeLists), and a
/// CocoaPods pod per Apple platform whose `Classes/` holds one forwarder
/// per source file — a `#include "../../src/<file>"` and nothing else,
/// because a pod compiles only what is under `Classes/`.
///
/// 🔥2026-08-30 (#1373) added `qa_compress.c` and the zstd amalgamation to
/// the CMake list and to neither pod. Nothing failed: the Dart side probes
/// `qa_zstd_*` and answers「no engine」when the symbols are missing, the
/// desktop wrote zstd because ITS engine answered, and on 2026-09-13 the
/// user's iPad could not open a single project the desktop had saved —
/// the manifest itself is zstd. The codec's own law reads「a file this app
/// writes must never need a library that might not be there」; it was
/// kept on the writing side only. This test is the reading side: whatever
/// one build can write, every build can read, because every build
/// compiles the same sources.
///
/// ⛔Read from the build files, not from a list kept here: a list would
/// need the same discipline this test exists to enforce.
void main() {
  final root = _repoRoot();
  final cmake = File('$root/packages/qa_native/src/CMakeLists.txt');
  final pods = <String, Directory>{
    'ios': Directory('$root/packages/qa_native/ios/Classes'),
    'macos': Directory('$root/packages/qa_native/macos/Classes'),
  };

  test('every source in the CMake engine library has a forwarder in both '
      'Apple pods', () {
    final sources = _engineLibrarySources(cmake.readAsStringSync());
    expect(
      sources,
      contains('qa_compress.c'),
      reason: 'the parser must see the list this test is about',
    );
    expect(sources, contains('third_party/zstd/zstd.c'));

    final missing = <String>[];
    for (final pod in pods.entries) {
      final forwarded = _forwardedSources(pod.value);
      for (final source in sources) {
        if (!forwarded.contains(source)) {
          missing.add('${pod.key}: $source');
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'compiled by CMake on desktop and Android, compiled by NO Apple '
          'pod — an iPad or a Mac will lack these symbols and answer '
          '「no engine」 to a file another platform wrote:\n'
          '${missing.join('\n')}',
    );
  });

  test('the Apple-only source is forwarded too, and the pods agree with '
      'each other', () {
    final ios = _forwardedSources(pods['ios']!);
    final macos = _forwardedSources(pods['macos']!);
    expect(ios, contains('qa_video_apple.m'));
    expect(
      ios,
      equals(macos),
      reason: 'one engine, two pods: a source forwarded on one Apple '
          'platform and not the other is the same defect one platform '
          'narrower',
    );
  });
}

/// The files listed in `add_library(qa_engine SHARED …)`, relative to
/// `src/` — the portable set every platform compiles. Sources added
/// under `if(APPLE)` / `if(WIN32)` afterwards are platform-specific by
/// construction and are not in this block.
List<String> _engineLibrarySources(String cmake) {
  final start = cmake.indexOf('add_library(qa_engine SHARED');
  expect(start, isNot(-1), reason: 'the engine library block moved');
  final end = cmake.indexOf(')', start);
  final block = cmake.substring(start, end);
  return RegExp(r'\$\{CMAKE_CURRENT_LIST_DIR\}/([^"]+)"')
      .allMatches(block)
      .map((m) => m.group(1)!)
      .toList();
}

/// The `src/`-relative paths the forwarders under [classes] include.
Set<String> _forwardedSources(Directory classes) {
  final include = RegExp(r'#include\s+"\.\./\.\./src/([^"]+)"');
  return {
    for (final file in classes.listSync().whereType<File>())
      for (final match in include.allMatches(file.readAsStringSync()))
        match.group(1)!,
  };
}

String _repoRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('pubspec.yaml not found above ${Directory.current}');
    }
    dir = parent;
  }
  return dir.path;
}
