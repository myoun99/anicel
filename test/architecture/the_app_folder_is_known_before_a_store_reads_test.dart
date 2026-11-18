import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ledger.dart' show codeOfLines;

/// 🚨THE APP'S OWN FOLDER IS KNOWN BEFORE A STORE READS, AND ON ANDROID IT
/// IS ONE AN UPDATE KEEPS.
///
/// Board android-settings-live-in-the-code-cache (2026-11-16): Android
/// starts an app with no `APPDATA`, `HOME` or `USERPROFILE`, so
/// `appSupportFilePath` fell to `Directory.systemTemp` — Flutter's
/// `code_cache`, which Android empties on every update. Measured on the
/// tablet: two settings files written, `adb install -r` of the same APK,
/// both gone, the first-run window back. The platform now hands the app's
/// folder (`platformAppSupportBase`) over `qa_storage`, and three things
/// keep it handed: main awaits the ask before the first store reads, the
/// name Dart asks is the name Android answers, and Android answers with
/// `filesDir`. No test here runs the Android side or main(), so they are
/// read from the source; the base's place in the chain is pinned by its
/// behaviour (four_more_unnamed_laws_test, 「the app-support path」).
void main() {
  test('main awaits the platform\'s folders before the first store reads',
      () {
    final start = codeOfLines(File('lib/main.dart').readAsStringSync());
    final asked = start.indexOf('await AppStorage.ensureInitialized();');
    final firstRead = [
      start.indexOf('migrateSettingsIntoTheirRoom();'),
      start.indexOf('settingsRoomIsEmpty();'),
    ];

    expect(firstRead, everyElement(greaterThan(0)), reason: '⛔premise');
    expect(asked, greaterThan(0), reason: 'the ask is not awaited in main');
    expect(firstRead, everyElement(greaterThan(asked)));
  });

  test('the name Dart asks the app\'s folder by is the name Android answers, '
      'with filesDir', () {
    final dart = codeOfLines(
      File(
        'lib/src/services/persistence/app_documents.dart',
      ).readAsStringSync(),
    );
    final kotlin = codeOfLines(
      File(
        'android/app/src/main/kotlin/com/myoun/anicel/MainActivity.kt',
      ).readAsStringSync(),
    );

    expect(
      RegExp(
        r'platformAppSupportBase\s*=\s*await\s+channel\s*'
        r"\.invokeMethod<String>\(\s*'appSupportPath'",
      ).hasMatch(dart),
      isTrue,
      reason: 'AppStorage no longer asks for the app\'s folder',
    );
    expect(
      RegExp(
        r'"appSupportPath"\s*->\s*result\.success\(filesDir\.absolutePath\)',
      ).hasMatch(kotlin),
      isTrue,
      reason: 'Android answers with another folder, or none',
    );
  });
}
