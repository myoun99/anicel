import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_memory_settings.dart';
import 'package:anicel/src/services/persistence/app_memory_settings_store.dart';

void main() {
  tearDown(() {
    AppMemory.settings.value = const AppMemorySettings();
  });

  test('the default is the automatic allowance', () {
    expect(const AppMemorySettings().allowanceBytes, isNull);
  });

  test('json roundtrip', () {
    const chosen = AppMemorySettings(allowanceBytes: 3 << 30);
    expect(AppMemorySettings.fromJson(chosen.toJson()), chosen);
    expect(
      AppMemorySettings.fromJson(const AppMemorySettings().toJson()),
      const AppMemorySettings(),
    );
  });

  test('a stored allowance that is not a positive whole number reads as '
      'the automatic one', () {
    for (final stranger in <Object?>[0, -5, 1.5, 'lots', null]) {
      expect(
        AppMemorySettings.fromJson({
          'allowanceBytes': stranger,
        }).allowanceBytes,
        isNull,
        reason: '$stranger',
      );
    }
  });

  test('the store keeps a chosen allowance between runs', () async {
    final directory = await Directory.systemTemp.createTemp('anicel-memory');
    addTearDown(() => directory.delete(recursive: true));
    final store = AppMemorySettingsStore(
      filePath: '${directory.path}/memory_settings.json',
    );
    expect(await store.load(), isNull, reason: 'nothing stored yet');

    await store.save(const AppMemorySettings(allowanceBytes: 2 << 30));

    expect(
      await store.load(),
      const AppMemorySettings(allowanceBytes: 2 << 30),
    );
  });
}
