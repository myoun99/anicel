import 'dart:convert';
import 'dart:io';

import 'app_support_path.dart';
import 'recent_projects.dart';

/// PICK-4: the recent-projects list on disk.
///
/// Shaped after [AppExportSettingsStore] rather than the settings stores
/// beside it, for the two reasons that store gives:
///
/// - **Sync `dart:io`.** Async `File` futures stall under `testWidgets`'
///   fake-async zone, and this list is read while BUILDING the File menu —
///   widget code that widget tests drive directly.
/// - **Redirected under FLUTTER_TEST.** Tests reach this through the
///   production menu wiring, and a test that recorded an open would
///   otherwise write into the real user's recent list.
class RecentProjectsStore {
  RecentProjectsStore({String? filePath})
    : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() {
    final environment = Platform.environment;
    if (environment['FLUTTER_TEST'] == 'true') {
      return '${Directory.systemTemp.path.replaceAll('\\', '/')}/'
          'qa_test_recent_projects_$pid/recent_projects.json';
    }
    return appSupportFilePath('recent_projects.json');
  }

  static const int version = 1;

  RecentProjects load() {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        return const RecentProjects();
      }
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      if ((decoded['version'] as int? ?? 0) > version) {
        return const RecentProjects();
      }
      return RecentProjects.fromJson(decoded);
    } on Object {
      // A missing or corrupt list is an empty list, never an error: losing
      // the menu is a nuisance, refusing to open the app over it is not.
      return const RecentProjects();
    }
  }

  void save(RecentProjects projects) {
    try {
      final file = File(filePath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({'version': version, ...projects.toJson()}),
      );
    } on Object {
      // Best-effort; the live list stays valid for this session.
    }
  }
}

/// Records an open, in memory and on disk.
///
/// Writes only when the list actually changed — re-opening the project that
/// is already at the front returns the same object, so a save-heavy session
/// does not rewrite this file on every Ctrl+S.
void recordRecentProject(RecentProject project, {RecentProjectsStore? store}) {
  final next = AppRecent.projects.value.withOpened(project);
  if (identical(next, AppRecent.projects.value)) {
    return;
  }
  AppRecent.projects.value = next;
  (store ?? RecentProjectsStore()).save(next);
}

/// Persists a mutation produced by one of [RecentProjects]' `with…` methods.
void storeRecentProjects(RecentProjects next, {RecentProjectsStore? store}) {
  if (identical(next, AppRecent.projects.value)) {
    return;
  }
  AppRecent.projects.value = next;
  (store ?? RecentProjectsStore()).save(next);
}
