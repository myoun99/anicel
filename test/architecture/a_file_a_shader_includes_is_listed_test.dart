@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨A FILE A SHADER `#include`s IS LISTED AMONG THE ASSETS, OR A CHANGE TO
/// IT IS NEVER COMPILED.
///
/// flutter compiles the shaders again only when a listed asset is newer
/// than what it compiled — `flutter test` asks so of its test assets
/// (`_needsRebuild`), an app build of its asset depfile — and a file a
/// shader includes is no shader of its own. 🔬10-28: nine mutants of
/// `shaders/lens_light.glsl` lived, because every test drew with the
/// shaders compiled before them. Listed, it is an input like any asset,
/// and a change to it compiles every shader again.
///
/// An include in angle brackets is the SDK's (`flutter/runtime_effect.glsl`),
/// compiled with the SDK.
void main() {
  final included = <String, String>{
    for (final file in Directory('shaders').listSync().whereType<File>())
      if (file.path.endsWith('.frag'))
        for (final match in RegExp(
          '^#include "([^"]+)"',
          multiLine: true,
        ).allMatches(file.readAsStringSync()))
          'shaders/${match.group(1)!}': file.uri.pathSegments.last,
  };

  test('the scan finds the includes', () {
    expect(included.keys, contains('shaders/lens_light.glsl'));
  });

  test('every file a shader includes is listed among the assets', () {
    final assets = _assetsOf(File('pubspec.yaml').readAsLinesSync());
    expect(
      [
        for (final MapEntry(key: path, value: by) in included.entries)
          if (!assets.contains(path)) '$path (by $by)',
      ],
      isEmpty,
      reason: 'list it under `flutter: assets:` in pubspec.yaml, or a '
          'change to it leaves the shaders compiled before it',
    );
    for (final path in included.keys) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });
}

/// The entries of `flutter: assets:` in [pubspec].
Set<String> _assetsOf(List<String> pubspec) {
  final at = pubspec.indexWhere((line) => line.trimRight() == '  assets:');
  expect(at, greaterThanOrEqualTo(0), reason: 'pubspec lists its assets');
  return {
    for (final line in pubspec.skip(at + 1).takeWhile(
      (line) => !RegExp(r'^ {0,2}\S').hasMatch(line),
    ))
      if (RegExp(r'^\s+- (\S+)').firstMatch(line) case final match?)
        match.group(1)!,
  };
}
