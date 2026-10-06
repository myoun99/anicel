import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/export_preset.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/services/persistence/app_export_settings_store.dart';
import '../../helpers/temp_dir.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('qa-export-settings');
  });

  tearDown(() => deleteTempQuietly(temp));

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
          spec: CelsExportSpec(base: false),
        ),
      ],
      lastSpecs: const ExportTabSpecs().withSpec(
        const SequenceExportSpec(inFrame: 23, outFrame: 94),
      ),
      lastFolder: 'D:/deliver/ep03/rush',
      presetsDrawerOpen: false,
    );
    await store.save(settings);
    final restored = await store.load();
    expect(restored, settings);
    expect(restored!.presetsFor(ExportTab.sequence), hasLength(1));
    expect(restored.presetsFor(ExportTab.cels).single.name, '납품 셀');
  });

  test('the remembered folder reads from both spellings a build has written '
      '— the bare path, and the path beside the token of a folder that was '
      'reused', () {
    expect(
      AppExportSettings.fromJson(const {
        'lastLocation': 'D:/deliver/legacy',
      }).lastFolder,
      'D:/deliver/legacy',
    );
    expect(
      AppExportSettings.fromJson(const {
        'lastLocation': {'path': 'D:/deliver/granted', 'bookmark': 'Ym9v'},
      }).lastFolder,
      'D:/deliver/granted',
    );
  });

  test('what is remembered is a folder or nothing: 「끝나면 고르기」 written by '
      'a build that had it reads as nothing', () {
    expect(AppExportSettings().lastFolder, isNull);
    expect(AppExportSettings().toJson().containsKey('lastLocation'), isFalse);
    expect(
      AppExportSettings.fromJson(const {'handOver': true}).lastFolder,
      isNull,
    );
    expect(
      AppExportSettings(lastFolder: 'D:/o').toJson()['lastLocation'],
      'D:/o',
    );
    expect(
      AppExportSettings(lastFolder: 'D:/o').copyWith(lastFolder: null),
      AppExportSettings(),
    );
    // The live settings are a ValueNotifier: one that compared equal to the
    // last would be dropped, and the folder with it.
    expect(
      AppExportSettings(lastFolder: 'D:/a'),
      isNot(AppExportSettings(lastFolder: 'D:/b')),
    );
  });

  test('a place stands in a folder: the folder itself, or the one its lone '
      'file is in', () {
    const folder = ExportIntoFolder(GrantedDirectory(path: 'D:/out'));
    const file = ExportToFile('D:/out/shot.mp4');
    expect(folder.folderPath, 'D:/out');
    expect(file.folderPath, 'D:/out');
    expect(file, const ExportToFile('D:/out/shot.mp4'));
    expect(file, isNot(const ExportToFile('D:/out/other.mp4')));
    expect(folder, isNot(const ExportIntoFolder(GrantedDirectory(path: 'D:/b'))));
    expect(const ExportHandOver(), const ExportHandOver());
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
