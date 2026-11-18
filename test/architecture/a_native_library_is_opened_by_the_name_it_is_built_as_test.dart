import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨A NATIVE LIBRARY IS OPENED BY THE NAME IT IS BUILT AS.
///
/// Board android-loads-the-engine-by-its-old-name (2026-11-16): `e379111bb`
/// (11-07) named the engine crate's library `gpu_engine_core`, apart from
/// the plugin's pod on Apple's, as Dart binds it by its asset's id. The
/// Android plugin still asked `System.loadLibrary("gpu_engine")` in its two
/// classes: every Android build since found no library, the plugin's
/// channel never came up, and a cut opened on the tablet died. No test runs
/// the Kotlin — the name was written twice, and only one of them moved.
///
/// So every name a platform opens one of ours by is read against the one
/// place it is built as: the crate's `[lib] name` for Android's Kotlin, the
/// plugin's CMake `PLUGIN_NAME` for the texture shim's Windows and Linux
/// opens. Apple's open neither by name — the pod is linked into the app
/// (the shim's `DynamicLibrary.process()`), and Flutter wraps the crate's
/// asset as a framework of its own name (the crate's Cargo.toml).
void main() {
  test('every System.loadLibrary on Android names the engine crate\'s '
      'library', () {
    final crate = _libName(
      File('packages/gpu_engine/rust/Cargo.toml').readAsStringSync(),
    );
    final asked = <String, String>{
      for (final file in [
        ...filesUnder('packages/gpu_engine/android/src'),
        ...filesUnder('android/app/src'),
      ])
        if (file.path.endsWith('.kt') || file.path.endsWith('.java'))
          for (final (line, name) in _loadedLibraries(file.readAsStringSync()))
            '${file.path.replaceAll(r'\', '/')}:$line': name,
    };

    expect(
      asked,
      isNotEmpty,
      reason: '⛔premise: the plugin loads the engine',
    );
    expect(
      {
        for (final MapEntry(:key, :value) in asked.entries)
          if (value != crate) key: value,
      },
      isEmpty,
      reason: 'the crate builds lib$crate.so — load "$crate"',
    );
  });

  test('the texture shim opens the plugin library CMake builds', () {
    final opened = _openedByName(
      File('packages/gpu_engine/lib/src/texture_shim.dart').readAsStringSync(),
    );
    final windows = _pluginName(
      File('packages/gpu_engine/windows/CMakeLists.txt').readAsStringSync(),
    );
    final linux = _pluginName(
      File('packages/gpu_engine/linux/CMakeLists.txt').readAsStringSync(),
    );

    expect(opened, {'$windows.dll', 'lib$linux.so'});
  });

  test('the scans see a planted name, and not one in a comment', () {
    const kotlin = '''
// System.loadLibrary("old")
        System.loadLibrary("gpu_engine")
''';
    const toml = '''
[package]
name = "gpu_engine"

[lib]
# name = "old"
crate-type = ["cdylib"]
name = "gpu_engine_core"

[dependencies]
''';
    const shim = '''
// DynamicLibrary.open('old.dll')
    ? DynamicLibrary.open('gpu_engine_plugin.dll')
''';
    const cmake = 'set(PLUGIN_NAME "gpu_engine_plugin")\n';

    expect(_loadedLibraries(kotlin), [(2, 'gpu_engine')]);
    expect(_libName(toml), 'gpu_engine_core');
    expect(_openedByName(shim), {'gpu_engine_plugin.dll'});
    expect(_pluginName(cmake), 'gpu_engine_plugin');
  });
}

/// Each `System.loadLibrary("…")` in [source] outside a `//` comment: its
/// line, from 1, and the name it asks for.
List<(int, String)> _loadedLibraries(String source) {
  final call = RegExp(r'System\.loadLibrary\(\s*"([^"]+)"\s*\)');
  final lines = source.split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      for (final match in call.allMatches(_code(lines[i])))
        (i + 1, match.group(1)!),
  ];
}

/// The name of the crate's library: the `name` of its `[lib]` table.
String _libName(String toml) {
  // The next table's bracket ends it — one is set after the last.
  final table = RegExp(
    r'^\[lib\]\s*$([\s\S]*?)^\[',
    multiLine: true,
  ).firstMatch('$toml\n[');
  expect(table, isNotNull, reason: 'the crate has no [lib] table');
  final name = RegExp(r'^name\s*=\s*"([^"]+)"', multiLine: true)
      .firstMatch(table!.group(1)!);
  expect(name, isNotNull, reason: 'the [lib] table names no library');
  return name!.group(1)!;
}

/// Each name `DynamicLibrary.open` is handed in [source], outside a `//`
/// comment.
Set<String> _openedByName(String source) => {
  for (final line in source.split('\n'))
    for (final match in RegExp(
      r"""DynamicLibrary\.open\(\s*['"]([^'"]+)['"]\s*\)""",
    ).allMatches(_code(line)))
      match.group(1)!,
};

/// The library a plugin's CMakeLists builds: its `PLUGIN_NAME`.
String _pluginName(String cmake) {
  final set = RegExp(r'set\(PLUGIN_NAME\s+"([^"]+)"\)').firstMatch(cmake);
  expect(set, isNotNull, reason: 'the CMakeLists sets no PLUGIN_NAME');
  return set!.group(1)!;
}

/// [line] up to a `//` comment.
String _code(String line) {
  final comment = line.indexOf('//');
  return comment < 0 ? line : line.substring(0, comment);
}
