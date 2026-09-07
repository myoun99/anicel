import 'versioned_settings_file.dart';
import 'dart:convert';
import 'dart:io';

import 'app_export_settings.dart';
import 'app_support_path.dart';

/// Loads and saves the export UI state (presets, last specs, location).
/// App state — an app-support JSON beside the save/input/audio settings;
/// missing/corrupt/newer files yield the defaults.
class AppExportSettingsStore {
  AppExportSettingsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() => testRedirectedAppSettingsPath(
    'export_settings.json',
    sandbox: 'export_settings',
  );

  static const int version = 1;

  // Sync dart:io on purpose (the settings JSON is tiny): async File futures
  // stall under testWidgets' fake-async zone — the documented SAVE-1
  // gotcha — and the export dialog reads/writes this store from widget
  // code that widget tests drive directly.
  Future<AppExportSettings?> load() async => loadVersionedSettingsSync(
    filePath: filePath,
    version: version,
    fromJson: AppExportSettings.fromJson,
  );

  Future<void> save(AppExportSettings settings) async {
    try {
      final file = File(filePath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({'version': version, ...settings.toJson()}),
      );
    } on Object {
      // Settings persistence is best-effort; the live state stays valid.
    }
  }
}
