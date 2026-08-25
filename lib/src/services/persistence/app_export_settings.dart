import 'package:flutter/foundation.dart';

import '../../models/export_preset.dart';
import '../../models/export_spec.dart';
import 'app_save_settings.dart' show GrantedDirectory;

/// APP-side export UI state (출력 UI v10): the per-tab presets, the last
/// used spec per tab, the last output location and the drawer states.
/// App state, not project state — presets are the user's own vocabulary
/// and follow the machine; per-cut manual exceptions are project data
/// (`ExportProjectOverrides`).
class AppExportSettings {
  AppExportSettings({
    List<ExportPreset> presets = const [],
    this.lastSpecs = const ExportTabSpecs(),
    this.lastLocation,
    this.presetsDrawerOpen = true,
    this.queueDrawerOpen = true,
  }) : presets = List.unmodifiable(presets);

  final List<ExportPreset> presets;
  final ExportTabSpecs lastSpecs;

  /// The last chosen output directory; null until the first export. The
  /// bookmark half is what lets the replayed location be WRITTEN to
  /// after a relaunch on macOS (Q-scoped-folder-settings, 유저 08-26).
  final GrantedDirectory? lastLocation;

  final bool presetsDrawerOpen;
  final bool queueDrawerOpen;

  List<ExportPreset> presetsFor(ExportTab tab) => [
    for (final preset in presets)
      if (preset.tab == tab) preset,
  ];

  static const Object _unset = Object();

  AppExportSettings copyWith({
    List<ExportPreset>? presets,
    ExportTabSpecs? lastSpecs,
    Object? lastLocation = _unset,
    bool? presetsDrawerOpen,
    bool? queueDrawerOpen,
  }) => AppExportSettings(
    presets: presets ?? this.presets,
    lastSpecs: lastSpecs ?? this.lastSpecs,
    lastLocation: identical(lastLocation, _unset)
        ? this.lastLocation
        : lastLocation as GrantedDirectory?,
    presetsDrawerOpen: presetsDrawerOpen ?? this.presetsDrawerOpen,
    queueDrawerOpen: queueDrawerOpen ?? this.queueDrawerOpen,
  );

  Map<String, dynamic> toJson() => {
    'presets': [for (final preset in presets) preset.toJson()],
    'lastSpecs': lastSpecs.toJson(),
    if (lastLocation != null) 'lastLocation': lastLocation!.toJson(),
    if (!presetsDrawerOpen) 'presetsDrawerOpen': false,
    if (!queueDrawerOpen) 'queueDrawerOpen': false,
  };

  static AppExportSettings fromJson(Map<String, dynamic> json) {
    final rawPresets = json['presets'] as List<dynamic>? ?? const [];
    return AppExportSettings(
      presets: [
        for (final preset in rawPresets)
          ExportPreset.fromJson(preset as Map<String, dynamic>),
      ],
      lastSpecs: json['lastSpecs'] == null
          ? const ExportTabSpecs()
          : ExportTabSpecs.fromJson(json['lastSpecs'] as Map<String, dynamic>),
      // Both spellings: the bare path older builds wrote, or path+bookmark.
      lastLocation: GrantedDirectory.fromJson(json['lastLocation']),
      presetsDrawerOpen: json['presetsDrawerOpen'] as bool? ?? true,
      queueDrawerOpen: json['queueDrawerOpen'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppExportSettings &&
          _listEquals(other.presets, presets) &&
          other.lastSpecs == lastSpecs &&
          other.lastLocation == lastLocation &&
          other.presetsDrawerOpen == presetsDrawerOpen &&
          other.queueDrawerOpen == queueDrawerOpen;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(presets),
    lastSpecs,
    lastLocation,
    presetsDrawerOpen,
    queueDrawerOpen,
  );

  static bool _listEquals(List<ExportPreset> a, List<ExportPreset> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// The LIVE export UI state (the [AppSave] idiom): the session restores
/// and persists it; the export dialog reads and writes it.
abstract final class AppExport {
  static final ValueNotifier<AppExportSettings> settings =
      ValueNotifier<AppExportSettings>(AppExportSettings());
}
