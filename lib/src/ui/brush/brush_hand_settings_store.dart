import '../../services/persistence/versioned_settings_file.dart';
import 'dart:convert';
import 'dart:io';

import '../../models/brush_hand_settings.dart';
export '../../models/brush_hand_settings.dart' show BrushHandSettings;
import '../../services/persistence/app_support_path.dart';

/// Where [BrushHandSettings] lives BETWEEN sessions.
///
/// ⛔Not in the preset file. 유저 답 (Q-brush-store, 2번 변형): 「앱 안에서는 앱
/// 저장소에 두되 내보낼 때는 브러시 파일에 쓴다」 — the Photoshop/CSP shape. A
/// slider drag must not rewrite a document on disk, and a brush someone shares
/// should still carry the size they were using when they shared it.
///
/// ⛔Not in `PaintToolStateNotifier`'s bank either ([[tool-parameter-round]]
/// TP1): that one saves and restores a whole state, so every new field
/// silently resets when it is not in the snapshot.
///
/// ⚠️The axis is the PRESET id, not the tool — the eraser carries its own
/// preset choice (R11-④), so keying by tool would give two brushes one memory.
class BrushHandSettingsStore {
  BrushHandSettingsStore({String? filePath})
    : filePath = filePath ?? defaultBrushHandSettingsFilePath();

  final String filePath;

  static String defaultBrushHandSettingsFilePath() =>
      appSettingsFilePath('brush_hand_settings.json');

  static const int version = 1;

  /// The saved values by preset id; empty when missing/corrupt/newer — a
  /// brush with no entry reads the size baked into its own file, which is
  /// the other half of the user's answer.
  Future<Map<String, BrushHandSettings>> load() async =>
      await loadVersionedSettings(
        filePath: filePath,
        version: version,
        // ⚠️The bank's shape is shared with the exported brush file — the
        // same map in both homes, so a fourth value cannot land in one
        // spelling and miss the other.
        fromJson: (json) => brushHandSettingsBankFromJson(
          json['brushes'] as Map<String, dynamic>?,
        ),
      ) ??
      const {};

  Future<void> save(Map<String, BrushHandSettings> bank) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'version': version,
        'brushes': brushHandSettingsBankToJson(bank),
      }),
    );
  }
}
