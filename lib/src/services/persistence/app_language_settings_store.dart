import 'dart:convert';
import 'dart:io';

import '../../models/app_language.dart';
import 'app_support_path.dart';

/// Loads and saves the two language settings (UI-R10 #7). Editor/app
/// state, not project data — an app-support JSON file next to the
/// workspace layout; missing/corrupt files yield the defaults.
class AppLanguageSettingsStore {
  AppLanguageSettingsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSupportFilePath('language_settings.json');

  static const int version = 1;

  Future<AppLanguageSettings?> load() async {
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
      return AppLanguageSettings.fromJson(decoded);
    } on Object catch (_) {
      // Corrupt settings never fail the editor: defaults win, the file is
      // replaced on the next save.
      return null;
    }
  }

  Future<void> save(AppLanguageSettings settings) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'version': version, ...settings.toJson()}),
    );
  }
}
