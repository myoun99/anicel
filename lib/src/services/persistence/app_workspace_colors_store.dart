import 'dart:convert';
import 'dart:io';

import '../../models/app_workspace_colors.dart';
import 'app_support_path.dart';

/// Loads and saves the workspace surface colors (R28 #9) — the
/// pasteboard color. Editor/app state, not project data: an app-support
/// JSON file beside the accent settings; missing/corrupt files yield the
/// defaults.
class AppWorkspaceColorsStore {
  AppWorkspaceColorsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSupportFilePath('workspace_colors.json');

  static const int version = 1;

  Future<AppWorkspaceColors?> load() async {
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
      return AppWorkspaceColors.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  Future<void> save(AppWorkspaceColors settings) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'version': version, ...settings.toJson()}),
    );
  }
}
