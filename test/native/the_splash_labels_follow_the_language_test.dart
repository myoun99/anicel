import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/native/launch_splash.dart';
import 'package:anicel/src/services/persistence/app_support_path.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../helpers/poll_until.dart';

/// The splash's first two stages are the runner's, said before Dart runs
/// from the names the last run left it (`LaunchSplash.labelsFileName`,
/// I-106): a launch leaves them, and so does each language the app is
/// given while it runs — 🔬검증/서피스 2026-11-12 09:08: 「언어를 바꾼 뒤 첫
/// 실행 한 번만 바뀌기 전 언어로 나온다」. With the names goes the face they
/// are said in, the language's own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final labels = File(
    testRedirectedAppSupportPath(
      LaunchSplash.labelsFileName,
      sandbox: 'launch',
    ),
  );

  /// The line the runner reads [language]'s face from: its files.
  Future<String> faceOf(AppLanguage language) async => LaunchSplash.faceFiles(
    [
      AppTypography.familyFor(language),
      ...AppTypography.fallbackFor(language),
    ],
    await rootBundle.loadString('FontManifest.json'),
  ).join('\t');

  /// Whether what is left comes to be [language]'s — its face's line, then
  /// its stage names a line each: it is written behind the call that
  /// leaves it.
  Future<bool> leftIn(AppLanguage language) async {
    final lines = [
      await faceOf(language),
      ...LaunchSplash.stageNames(AppStrings.of(language)),
    ];
    return pollUntil(() {
      try {
        return listEquals(labels.readAsLinesSync(), lines);
      } on FileSystemException {
        // Not there yet, or being written.
        return false;
      }
    });
  }

  setUp(() {
    // The splash is the desktops'.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    // No runner hears the stage Dart says.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LaunchSplash.channel, (_) async => null);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LaunchSplash.channel, null);
    AppText.settings.value = const AppLanguageSettings();
  });

  test('a launch leaves the stage names and the face of the language it '
      'speaks, and a language chosen while the app runs is left in their '
      'place', () async {
    // One the app sets in another face than the launch's.
    const chosen = AppLanguage.zhHans;
    expect(
      await faceOf(chosen),
      isNot(await faceOf(AppLanguage.ja)),
      reason: '⛔premise: the two are said in different faces',
    );
    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.ja,
    );
    await LaunchSplash.preparing(AppText.strings);
    expect(await leftIn(AppLanguage.ja), isTrue, reason: "the launch's");

    AppText.settings.value = AppText.settings.value.copyWith(
      programLanguage: chosen,
    );

    expect(await leftIn(chosen), isTrue);
  });
}
