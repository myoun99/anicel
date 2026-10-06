import 'package:flutter/foundation.dart';

import '../../core/path_names.dart';
import '../../models/export_preset.dart';
import '../../models/export_spec.dart';
import 'app_save_settings.dart' show GrantedDirectory;

/// Where an export's outputs go: a PLACE asked before the run
/// ([ExportPlace] — a folder for several files, one file's own path for a
/// lone one), or handed over once the run is done, where the platform
/// cannot be asked before (F-221, closed 2026-10-06; drive-folder-windows-Q1,
/// 유저 2026-09-27: 「내보내기가 끝나면 드라이브로 넘긴다 — 파일 창을 거쳐」).
/// ONE value, so a destination is never two of them and no code can leave
/// half of one behind.
///
/// ⛔Which of them a run gets is not a choice a person makes any more (the
/// 「찾아보기…」 · 「끝나면 고르기」 pair is gone): what is written and the
/// platform decide it, at the one door (`askWhereOutputsGo`).
sealed class ExportDestination {
  const ExportDestination();
}

/// A destination that IS somewhere: asked before the run, so it names a
/// folder or a file on a disk — where a hand-over is nowhere until its
/// window is answered.
sealed class ExportPlace extends ExportDestination {
  const ExportPlace();

  /// The folder the place stands in: where the run writes, and where the
  /// window asking the NEXT place opens ([AppExportSettings.lastFolder]).
  String get folderPath;
}

/// A folder asked before the run — what several files are asked. The
/// bookmark half is the token the OS issued with the pick (macOS/iOS); it
/// is what lets the folder be WRITTEN to (Q-scoped-folder-settings, 유저
/// 08-26).
final class ExportIntoFolder extends ExportPlace {
  const ExportIntoFolder(this.folder);

  final GrantedDirectory folder;

  @override
  String get folderPath => folder.path;

  @override
  bool operator ==(Object other) =>
      other is ExportIntoFolder && other.folder == folder;

  @override
  int get hashCode => folder.hashCode;
}

/// ONE FILE's own place, asked before the run through a save window
/// (F-221-Q3, 유저 2026-10-06: the count decides — 「한 장이면 파일 저장 창,
/// 두 장부터 폴더 창」). [path] is the file itself, under the name the window
/// answered with: the run writes its lone file there, whatever name a rule
/// or a field would have given it.
final class ExportToFile extends ExportPlace {
  const ExportToFile(this.path);

  final String path;

  @override
  String get folderPath => folderOfPath(path);

  @override
  bool operator ==(Object other) => other is ExportToFile && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// Asked afterwards: the outputs are made in the run's room and handed to
/// the user's pick once the run is done — all a platform with no window
/// that asks first can do, and the one way an export reaches a place no
/// folder window opens, Google Drive above all.
final class ExportHandOver extends ExportDestination {
  const ExportHandOver();

  @override
  bool operator ==(Object other) => other is ExportHandOver;

  @override
  int get hashCode => (ExportHandOver).hashCode;
}

/// APP-side export UI state (출력 UI v10): the per-tab presets, the last
/// used spec per tab, the folder the last export was asked a place in and
/// the drawer states.
/// App state, not project state — presets are the user's own vocabulary
/// and follow the machine; per-cut manual exceptions are project data
/// (`ExportProjectOverrides`).
class AppExportSettings {
  AppExportSettings({
    List<ExportPreset> presets = const [],
    this.lastSpecs = const ExportTabSpecs(),
    this.lastFolder,
    this.presetsDrawerOpen = true,
    this.queueDrawerOpen = true,
  }) : presets = List.unmodifiable(presets);

  final List<ExportPreset> presets;
  final ExportTabSpecs lastSpecs;

  /// The folder the last place an export was asked stands in
  /// ([ExportPlace.folderPath]); null until the first.
  ///
  /// Remembered for ONE thing: the next window that asks opens there. A
  /// place is asked afresh at every Export (F-221-Q4, 유저 2026-10-06), so
  /// this is never where one goes unasked — which is why it is a path and
  /// carries no token: the app writes nowhere it was not just handed.
  ///
  /// ↩️It was the whole destination — folder and token, or 「끝나면 고르기」
  /// — while a place was chosen ahead and every run reused it. A hand-over
  /// is not somewhere: a run that was handed over leaves this as it was.
  final String? lastFolder;

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
    Object? lastFolder = _unset,
    bool? presetsDrawerOpen,
    bool? queueDrawerOpen,
  }) => AppExportSettings(
    presets: presets ?? this.presets,
    lastSpecs: lastSpecs ?? this.lastSpecs,
    lastFolder: identical(lastFolder, _unset)
        ? this.lastFolder
        : lastFolder as String?,
    presetsDrawerOpen: presetsDrawerOpen ?? this.presetsDrawerOpen,
    queueDrawerOpen: queueDrawerOpen ?? this.queueDrawerOpen,
  );

  Map<String, dynamic> toJson() => {
    'presets': [for (final preset in presets) preset.toJson()],
    'lastSpecs': lastSpecs.toJson(),
    'lastLocation': ?lastFolder,
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
      // Both spellings of a folder: the bare path, or the path+bookmark a
      // build wrote while the folder was reused. A file written while
      // 「끝나면 고르기」 was a choice says `handOver` and no folder: it reads
      // as nothing remembered, which is what it is.
      lastFolder: GrantedDirectory.fromJson(json['lastLocation'])?.path,
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
          other.lastFolder == lastFolder &&
          other.presetsDrawerOpen == presetsDrawerOpen &&
          other.queueDrawerOpen == queueDrawerOpen;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(presets),
    lastSpecs,
    lastFolder,
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
