import 'versioned_settings_file.dart';
import 'dart:convert';
import 'dart:io';

import '../../models/app_ui_scale.dart';
import 'app_support_path.dart';

/// Loads and saves the UI scale. Editor/app state, not project data — an
/// app-support JSON file beside the accents and the language.
///
/// 🚨**This one is loaded BEFORE `runApp`, unlike its neighbours.** The
/// others restore asynchronously and the app simply repaints when they
/// land; a scale that restores late would lay the whole window out at 100%,
/// paint it, and then jump. "한 프레임 보이는 건 무조건 걸린다" — and this
/// is the most visible frame there is. The cost is one small file read
/// before the first frame, which is itself far more expensive.
class AppUiScaleStore {
  AppUiScaleStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() => appSettingsFilePath('ui_scale.json');

  static const int version = 1;

  /// The stored scale, SNAPPED to the ladder, or null when there is nothing
  /// usable on disk.
  ///
  /// ⚠️Snapping here and not at the call site: a file written by a build
  /// with a different ladder is the normal way an off-ladder value arrives,
  /// and a value the settings row cannot show would leave every stop
  /// looking unselected.
  Future<double?> load() => loadVersionedSettings(
    filePath: filePath,
    version: version,
    fromJson: (json) {
      final scale = (json['scale'] as num?)?.toDouble();
      if (scale == null || !scale.isFinite || scale <= 0) {
        return null;
      }
      return AppUiScale.snap(scale);
    },
  );

  Future<void> save(double scale) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'version': version, 'scale': scale}));
  }
}
