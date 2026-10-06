import 'package:flutter/foundation.dart';

import '../../models/export_preset.dart';
import '../../models/export_spec.dart';
import 'app_save_settings.dart' show GrantedDirectory;

/// Where an export's outputs go: a folder chosen before the run, or —
/// 「끝나면 고르기」 (drive-folder-windows-Q1, 유저 2026-09-27: 「내보내기가 끝나면
/// 드라이브로 넘긴다 — 파일 창을 거쳐」) — handed over once the run is done.
/// ONE value, so a destination is never both and no code can leave half of
/// one behind.
sealed class ExportDestination {
  const ExportDestination();
}

/// A folder chosen before the run. The bookmark half is what lets the
/// replayed folder be WRITTEN to after a relaunch on macOS
/// (Q-scoped-folder-settings, 유저 08-26).
final class ExportIntoFolder extends ExportDestination {
  const ExportIntoFolder(this.folder);

  final GrantedDirectory folder;

  @override
  bool operator ==(Object other) =>
      other is ExportIntoFolder && other.folder == folder;

  @override
  int get hashCode => folder.hashCode;
}

/// 「끝나면 고르기」: the outputs are made in the run's room and handed to the
/// user's pick once the run is done — the one way an export reaches a place
/// no folder window opens, Google Drive above all.
final class ExportHandOver extends ExportDestination {
  const ExportHandOver();

  @override
  bool operator ==(Object other) => other is ExportHandOver;

  @override
  int get hashCode => (ExportHandOver).hashCode;
}

/// APP-side export UI state (출력 UI v10): the per-tab presets, the last
/// used spec per tab, the last destination and the drawer states.
/// App state, not project state — presets are the user's own vocabulary
/// and follow the machine; per-cut manual exceptions are project data
/// (`ExportProjectOverrides`).
class AppExportSettings {
  AppExportSettings({
    List<ExportPreset> presets = const [],
    this.lastSpecs = const ExportTabSpecs(),
    this.lastDestination,
    this.presetsDrawerOpen = true,
    this.queueDrawerOpen = true,
  }) : presets = List.unmodifiable(presets);

  final List<ExportPreset> presets;
  final ExportTabSpecs lastSpecs;

  /// The last chosen destination; null until the first choice.
  final ExportDestination? lastDestination;

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
    Object? lastDestination = _unset,
    bool? presetsDrawerOpen,
    bool? queueDrawerOpen,
  }) => AppExportSettings(
    presets: presets ?? this.presets,
    lastSpecs: lastSpecs ?? this.lastSpecs,
    lastDestination: identical(lastDestination, _unset)
        ? this.lastDestination
        : lastDestination as ExportDestination?,
    presetsDrawerOpen: presetsDrawerOpen ?? this.presetsDrawerOpen,
    queueDrawerOpen: queueDrawerOpen ?? this.queueDrawerOpen,
  );

  Map<String, dynamic> toJson() => {
    'presets': [for (final preset in presets) preset.toJson()],
    'lastSpecs': lastSpecs.toJson(),
    ...switch (lastDestination) {
      ExportIntoFolder(:final folder) => {'lastLocation': folder.toJson()},
      ExportHandOver() => {'handOver': true},
      null => const <String, dynamic>{},
    },
    if (!presetsDrawerOpen) 'presetsDrawerOpen': false,
    if (!queueDrawerOpen) 'queueDrawerOpen': false,
  };

  static AppExportSettings fromJson(Map<String, dynamic> json) {
    final rawPresets = json['presets'] as List<dynamic>? ?? const [];
    return AppExportSettings(
      presets: [
        // A preset of a tab that is one no longer is dropped (F-289: the
        // timesheet and the cut envelope are kinds of the Cels tab now).
        for (final preset in rawPresets)
          ?ExportPreset.fromJson(preset as Map<String, dynamic>),
      ],
      lastSpecs: json['lastSpecs'] == null
          ? const ExportTabSpecs()
          : ExportTabSpecs.fromJson(json['lastSpecs'] as Map<String, dynamic>),
      lastDestination: json['handOver'] == true
          ? const ExportHandOver()
          // Both spellings: the bare path older builds wrote, or
          // path+bookmark.
          : switch (GrantedDirectory.fromJson(json['lastLocation'])) {
              final folder? => ExportIntoFolder(folder),
              null => null,
            },
      presetsDrawerOpen: json['presetsDrawerOpen'] as bool? ?? true,
      queueDrawerOpen: json['queueDrawerOpen'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppExportSettings &&
          listEquals(other.presets, presets) &&
          other.lastSpecs == lastSpecs &&
          other.lastDestination == lastDestination &&
          other.presetsDrawerOpen == presetsDrawerOpen &&
          other.queueDrawerOpen == queueDrawerOpen;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(presets),
    lastSpecs,
    lastDestination,
    presetsDrawerOpen,
    queueDrawerOpen,
  );
}

/// The LIVE export UI state (the [AppSave] idiom): the session restores
/// and persists it; the export dialog reads and writes it.
abstract final class AppExport {
  static final ValueNotifier<AppExportSettings> settings =
      ValueNotifier<AppExportSettings>(AppExportSettings());
}
