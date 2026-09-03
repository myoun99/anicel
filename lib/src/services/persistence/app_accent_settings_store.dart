import 'dart:convert';
import 'dart:io';

import '../../models/app_accents.dart';
import 'app_support_path.dart';

/// Loads and saves the two program accents (UI-R22 #5). Editor/app
/// state, not project data — an app-support JSON file beside the
/// language settings; missing/corrupt files yield the defaults.
class AppAccentSettingsStore {
  AppAccentSettingsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSupportFilePath('accent_settings.json');

  static const int version = 1;

  Future<AppAccentSettings?> load() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if ((decoded['version'] as int? ?? 0) > version) {
        return null;
      }
      return AppAccentSettings.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  Future<void> save(AppAccentSettings settings) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'version': version, ...settings.toJson()}),
    );
  }
}
