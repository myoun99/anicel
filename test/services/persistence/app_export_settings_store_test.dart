import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/export_preset.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/services/persistence/app_export_settings_store.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('qa-export-settings');
  });

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } on Object {
      // Windows can hold the handle a beat; leak the temp dir over failing.
    }
  });

  String pathIn(String name) => '${temp.path.replaceAll('\\', '/')}/$name.json';

  test('missing file loads as null', () async {
    final store = AppExportSettingsStore(filePath: pathIn('missing'));
    expect(await store.load(), isNull);
  });

  test('save/load round-trips presets, specs, location and drawers', () async {
    final store = AppExportSettingsStore(filePath: pathIn('roundtrip'));
    final settings = AppExportSettings(
      presets: [
        const ExportPreset(
          id: ExportPresetId('p1'),
          name: '러시 체크 MP4',
          spec: SequenceExportSpec(applyLayerFx: false),
        ),
        const ExportPreset(
          id: ExportPresetId('p2'),
          name: '납품 셀',
          spec: CelsExportSpec(selection: CelsSelectionPreset.attach),
        ),
      ],
      lastSpecs: const ExportTabSpecs().withSpec(
        const SequenceExportSpec(inFrame: 23, outFrame: 94),
      ),
      lastLocation: const GrantedDirectory(
        path: 'D:/deliver/ep03/rush',
        bookmark: 'Ym9va21hcms=',
      ),
      presetsDrawerOpen: false,
    );
    await store.save(settings);
    final restored = await store.load();
    expect(restored, settings);
    expect(restored!.presetsFor(ExportTab.sequence), hasLength(1));
    // An older build's bare-string spelling still reads (token-less).
    expect(
      AppExportSettings.fromJson(const {
        'lastLocation': 'D:/deliver/legacy',
      }).lastLocation,
      const GrantedDirectory(path: 'D:/deliver/legacy'),
    );
    expect(restored.presetsFor(ExportTab.cels).single.name, '납품 셀');
  });

  test('corrupt JSON loads as null', () async {
    final path = pathIn('corrupt');
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync('not json {');
    expect(await AppExportSettingsStore(filePath: path).load(), isNull);
  });

  test('a newer version loads as null (forward compatibility)', () async {
    final path = pathIn('newer');
    final store = AppExportSettingsStore(filePath: path);
    await store.save(AppExportSettings());
    final raw =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    raw['version'] = AppExportSettingsStore.version + 1;
    File(path).writeAsStringSync(jsonEncode(raw));
    expect(await store.load(), isNull);
  });

  test('the store redirects itself away from the real file under test', () {
    // Widget tests reach this through the PRODUCTION menu wiring — they
    // must never read or write the user's real settings file.
    expect(
      AppExportSettingsStore.defaultFilePath(),
      contains('qa_test_export_settings_'),
    );
    expect(
      AppExportSettingsStore.defaultFilePath(),
      endsWith('/export_settings.json'),
    );
  });
}
