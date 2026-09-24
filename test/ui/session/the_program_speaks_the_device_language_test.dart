import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/persistence/app_language_settings_store.dart';
import 'package:anicel/src/ui/session/editor_app_settings.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import '../../helpers/temp_dir.dart';

/// 🚨F-157 (유저 2026-09-17): 「앱 기본 언어 설정값, 디바이스? 의 언어 설정
/// 기준으로. 즉 앱컨테이너 설정에 language_settings.json 파일이 없을때 가
/// 로직적으로 맞는거같은데 그런부분은 알아서 맡기고. 표기언어 기본값은 지금처럼
/// 일본어 그대로」.
///
/// The device is INJECTED here: the one line that reads the operating system
/// is the running app's, and a test that read it would pass or fail by the
/// language of the machine it ran on.
void main() {
  setUp(() => AppText.settings.value = const AppLanguageSettings());
  tearDown(() => AppText.settings.value = const AppLanguageSettings());

  group('the language a device reads the app in', () {
    test('the first of its languages the app speaks, in the device\'s own '
        'order', () {
      expect(AppLanguage.forDevice(['ko']), AppLanguage.ko);
      expect(AppLanguage.forDevice(['ja', 'en']), AppLanguage.ja);
      expect(
        AppLanguage.forDevice(['de', 'fr', 'ko']),
        AppLanguage.fr,
        reason: 'German is not spoken, so the next one the device prefers',
      );
      expect(AppLanguage.forDevice(['en', 'ko']), AppLanguage.en);
    });

    test('every Chinese reads the one Chinese the app speaks', () {
      expect(AppLanguage.forDevice(['zh']), AppLanguage.zhHans);
    });

    test('a device the app does not speak reads English', () {
      expect(AppLanguage.forDevice(['de', 'pt']), AppLanguage.en);
      expect(AppLanguage.forDevice(const []), AppLanguage.en);
    });
  });

  group('the saved language and the device', () {
    late Directory directory;
    setUp(() {
      directory = Directory.systemTemp.createTempSync('qa-device-language');
    });
    tearDown(() => deleteTempQuietly(directory));

    AppLanguageSettingsStore store() => AppLanguageSettingsStore(
      filePath: '${directory.path}/language_settings.json',
    );

    /// What the app speaks once a session's restore has landed, on a device
    /// that prefers [device].
    Future<AppLanguageSettings> restored(
      AppLanguageSettingsStore? store,
      List<String> device,
    ) async {
      final settings = EditorAppSettings(
        languageSettingsStore: store,
        deviceLanguageCodes: () => device,
      );
      settings.restore();
      await settings.languageRestored;
      return AppText.settings.value;
    }

    test('no settings file: the program speaks the device\'s language and '
        'the notation stays Japanese', () async {
      expect(
        await restored(store(), ['ko']),
        const AppLanguageSettings(
          programLanguage: AppLanguage.ko,
          notationLanguage: AppLanguage.ja,
        ),
      );
    });

    test('a saved choice wins over the device', () async {
      const saved = AppLanguageSettings(
        programLanguage: AppLanguage.fr,
        notationLanguage: AppLanguage.en,
      );
      await store().save(saved);
      expect(await restored(store(), ['ko']), saved);
    });

    test('the device\'s language is not written down — a device that '
        'changes its language is followed until the user picks one', () async {
      // ⚠️The writes are fire-and-forget, so an absent FILE right after the
      // restore proves nothing; the store counts what it was asked to save.
      final recording = _RecordingStore(filePath: store().filePath);
      await restored(recording, ['ko']);
      expect(recording.saves, isEmpty);
      expect((await restored(store(), ['ja'])).programLanguage, AppLanguage.ja);
    });

    test('a host with no settings store keeps the defaults', () async {
      expect(await restored(null, ['ko']), const AppLanguageSettings());
    });
  });
}

/// A real store that also counts what it was asked to save.
class _RecordingStore extends AppLanguageSettingsStore {
  _RecordingStore({required super.filePath});

  final saves = <AppLanguageSettings>[];

  @override
  Future<void> save(AppLanguageSettings settings) async {
    saves.add(settings);
  }
}
