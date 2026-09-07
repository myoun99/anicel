import '../../services/persistence/versioned_settings_file.dart';
import 'dart:convert';
import 'dart:io';

import '../../services/persistence/app_support_path.dart';

/// The size and opacity a HAND last set on one brush.
///
/// 🚨H25 (유저 2026-08-23): 「클튜보면 브러시크기가 브러시마다 다르게
/// 설정가능하던데, 그거 따라가도록. 브러시 고르고 브러시크기 설정하면 다음에 같은
/// 브러시 선택할때 해당 브러시크기 남아있도록. 불투명도도 마찬가지」.
typedef BrushHandSettings = ({double? size, double? opacity});

/// Where those values live BETWEEN sessions.
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
        fromJson: (json) {
          final entries = json['brushes'] as Map<String, dynamic>? ?? const {};
          return {
            for (final entry in entries.entries)
              if (entry.value is Map<String, dynamic>)
                entry.key: (
                  size:
                      (entry.value as Map<String, dynamic>)['size'] as double?,
                  opacity:
                      (entry.value as Map<String, dynamic>)['opacity']
                          as double?,
                ),
          };
        },
      ) ??
      const {};

  Future<void> save(Map<String, BrushHandSettings> bank) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'version': version,
        'brushes': {
          for (final entry in bank.entries)
            entry.key: {
              if (entry.value.size != null) 'size': entry.value.size,
              if (entry.value.opacity != null) 'opacity': entry.value.opacity,
            },
        },
      }),
    );
  }
}
