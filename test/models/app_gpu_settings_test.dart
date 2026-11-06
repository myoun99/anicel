import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_gpu_settings.dart';
import 'package:anicel/src/services/persistence/app_gpu_settings_store.dart';
import '../helpers/project_scratch_folder.dart';

/// The GPU choice (connection-round-checklist-Q4, 유저 2026-11-06: 「자동 ·
/// 절전 · 고성능」) as its settings file holds it — the file the Windows
/// runner reads before Dart runs.
void main() {
  tearDown(AppGpu.debugReset);

  test('the default is no preference — the OS picks', () {
    expect(const AppGpuSettings().preference, AppGpuPreference.auto);
  });

  test('json roundtrip, for every choice', () {
    for (final preference in AppGpuPreference.values) {
      final chosen = AppGpuSettings(preference: preference);
      expect(AppGpuSettings.fromJson(chosen.toJson()), chosen);
    }
  });

  test('a name this build does not know reads as no preference, as the '
      'runner reads it', () {
    for (final stranger in <Object?>['discrete', '', 2, null]) {
      expect(
        AppGpuSettings.fromJson({'preference': stranger}).preference,
        AppGpuPreference.auto,
        reason: '$stranger',
      );
    }
  });

  test('the store keeps a choice between runs', () async {
    final directory = await Directory.systemTemp.createTemp('anicel-gpu');
    deleteAfterSessionEnds(directory);
    final store = AppGpuSettingsStore(
      filePath: '${directory.path}/gpu_settings.json',
    );
    expect(await store.load(), isNull, reason: 'nothing stored yet');

    await store.save(
      const AppGpuSettings(preference: AppGpuPreference.highPerformance),
    );

    expect(
      await store.load(),
      const AppGpuSettings(preference: AppGpuPreference.highPerformance),
    );
  });

  test('what the run started with is the first word only — a later restore '
      'is not what the engine was made with', () {
    expect(AppGpu.startedWith, isNull);
    AppGpu.noteStartedWith(AppGpuPreference.lowPower);
    AppGpu.noteStartedWith(AppGpuPreference.highPerformance);
    expect(AppGpu.startedWith, AppGpuPreference.lowPower);
  });
}
