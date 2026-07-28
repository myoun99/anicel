import 'dart:convert';
import 'dart:io';

import '../../ui/playback/audio_sync_settings.dart';
import 'app_support_path.dart';

/// Loads and saves the A/V offset (audio program 2D).
///
/// APP state, not project state — deliberately. The offset describes the
/// machine's output path (its screen, its device buffer, whichever
/// headphones are paired), so it belongs to the rig and not to the film.
/// Storing it in the `.anicel` would carry one person's Bluetooth delay into
/// everyone else's copy of the project.
///
/// Same shape as the language/accent/input stores beside it: an
/// app-support JSON file, missing or corrupt files yielding the defaults.
class AudioSyncSettingsStore {
  AudioSyncSettingsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() =>
      appSupportFilePath('audio_sync_settings.json');

  static const int version = 1;

  Future<AudioSyncSettings?> load() async {
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
      return AudioSyncSettings.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  Future<void> save(AudioSyncSettings settings) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'version': version, ...settings.toJson()}),
    );
  }
}
