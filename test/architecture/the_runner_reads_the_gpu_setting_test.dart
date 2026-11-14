import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_gpu_settings.dart';
import 'package:anicel/src/services/persistence/app_gpu_settings_store.dart';

import '../helpers/source_body.dart';

/// 🗣️connection-round-checklist-Q4 (유저 2026-11-06): 「환경설정에 GPU 고르기를
/// 넣는다 — 자동 · 절전 · 고성능」. The engine takes the GPU preference when the
/// runner makes it, before Dart runs, so the Windows runner reads the choice
/// from the settings file Dart writes — ONE file, read in two languages.
///
/// A FILE HAS NO COMPILER: this is the spelling check across the two. The
/// runner's path is the store's, its key is the one `toJson` writes, every
/// choice but 「auto」 maps to the flutter preference of its meaning, and the
/// preference is set before the window — the engine — is made.
///
/// ⚠️A SOURCE PIN, because this suite runs no runner: which GPU a launch
/// gets is the desktop's to show.
void main() {
  final source = File('windows/runner/main.cpp').readAsStringSync();
  String readerOf() => sourceBodyOf(
    source,
    'flutter::GpuPreference GpuPreferenceOfTheSettings()',
  );

  test('the runner reads the store\'s own file, under the APPDATA the app '
      'support path stands on', () {
    final reader = readerOf();
    final path = AppGpuSettingsStore.defaultFilePath();
    expect(path, contains('/anicel/'));
    final tail = path.split('/anicel/').last;
    expect(reader, contains('GetEnvironmentVariable(L"APPDATA"'));
    expect(
      reader,
      contains('L"${r'\\anicel\\'}${tail.replaceAll('/', r'\\')}"'),
    );
  });

  test('the runner reads the key the settings write, in the shape of the '
      'version it knows', () {
    // The preference's key — the file holds the plugins' limit too, which
    // the runner does not read.
    final json = const AppGpuSettings().toJson();
    final key = json.keys.singleWhere(
      (key) => json[key] == AppGpuPreference.auto.name,
    );
    expect(readerOf(), contains('"\\"$key\\""'));
    expect(
      AppGpuSettingsStore.version,
      1,
      reason: 'the runner reads the first version\'s shape — change both',
    );
  });

  test('every choice but 「auto」 is the flutter preference of its meaning, '
      'and anything else is none', () {
    final reader = readerOf();
    const meant = {
      AppGpuPreference.lowPower: 'LowPowerPreference',
      AppGpuPreference.highPerformance: 'HighPerformancePreference',
    };
    expect(
      meant.keys.toSet(),
      AppGpuPreference.values.toSet().difference({AppGpuPreference.auto}),
      reason: '⛔premise: a new choice is spelled in the runner too',
    );
    for (final MapEntry(key: preference, value: flutterName)
        in meant.entries) {
      expect(
        RegExp(
          'if \\(name == "${preference.name}"\\) \\{\\s*'
          'return flutter::GpuPreference::$flutterName;',
        ).hasMatch(reader),
        isTrue,
        reason: '${preference.name} → $flutterName',
      );
    }
    expect(
      RegExp(
        r'return flutter::GpuPreference::NoPreference;\s*\}$',
      ).hasMatch(reader.trimRight()),
      isTrue,
      reason: 'what is not a known name asks for nothing',
    );
  });

  test('the preference is set before the window makes the engine', () {
    final main = sourceBodyOf(source, 'int APIENTRY wWinMain(');
    final set = main.indexOf(
      'project.set_gpu_preference(GpuPreferenceOfTheSettings());',
    );
    expect(set, greaterThan(main.indexOf('flutter::DartProject project(')));
    expect(main.indexOf('FlutterWindow window(project);'), greaterThan(set));
  });
}
