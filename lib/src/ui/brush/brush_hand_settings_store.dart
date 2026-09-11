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
/// ⚠️The axis is the PRESET id — and, for the eraser, the tool as well
/// (`_handKey` in the workspace): each paint tool keeps its own settings
/// (R11-④), so one preset held by both tools is two memories. Keying by the
/// tool ALONE would give two brushes one memory, which is why it is not that.
class BrushHandSettingsStore {
  BrushHandSettingsStore({String? filePath})
    : filePath = filePath ?? defaultBrushHandSettingsFilePath();

  final String filePath;

  /// ⚠️Sandboxed under `FLUTTER_TEST`: the workspace builds this store
  /// itself, so every widget test that picks a brush reaches it through the
  /// production wiring — and would read and write the developer's own bank
  /// without the redirect.
  static String defaultBrushHandSettingsFilePath() =>
      testRedirectedAppSettingsPath(
        'brush_hand_settings.json',
        sandbox: 'brush-hand-settings',
      );

  static const int version = 1;

  /// What the hand left on each brush, by key; empty when missing/corrupt/
  /// newer — a brush with no entry reads what is baked into its own file,
  /// which is the other half of the user's answer.
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
