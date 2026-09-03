import 'dart:convert';
import 'dart:io';

import '../../models/app_input_settings.dart';
import 'app_support_path.dart';

/// Loads and saves the pointer-input policy (UI-R22 #6). Editor/app
/// state — an app-support JSON file beside the language/accent settings;
/// missing/corrupt files yield the defaults.
class AppInputSettingsStore {
  AppInputSettingsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSupportFilePath('input_settings.json');

  static const int version = 1;

  Future<AppInputSettings?> load() async {
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
      return AppInputSettings.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  Future<void> save(AppInputSettings settings) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'version': version, ...settings.toJson()}),
    );
  }
}
