import 'package:flutter/foundation.dart';

/// PICK-4: the projects this user opened last.
///
/// Every native app has this menu, and going all-native makes it load-bearing
/// rather than a convenience. The picker is now the ONLY way to reach a
/// project the app does not already know about, and on iPad that means
/// walking into Files, into Drive, and down three folders — every single
/// time. A recent list is what keeps the common case to one tap.
///
/// On Apple platforms an entry carries more than a path. A path outside the
/// app container is refused after relaunch unless the app can produce the
/// security-scoped bookmark it was granted, so the bookmark IS the entry;
/// the path is only what it resolves to today.
@immutable
class RecentProject {
  const RecentProject({
    required this.path,
    this.folderBookmark,
    this.needsReconnect = false,
  });

  /// The project file.
  final String path;

  /// The security-scoped bookmark for the FOLDER the project sits in —
  /// never for the file. The grant has to cover the sibling `.assets/`
  /// directory and the autosave sidecar, neither of which a file-scoped
  /// bookmark reaches.
  ///
  /// Null on Windows, Linux and Android, where a path is durable by itself.
  final String? folderBookmark;

  /// The bookmark stopped resolving — the provider was reinstalled, the
  /// account changed, the folder moved.
  ///
  /// The row is KEPT and flagged rather than dropped. The user still knows
  /// which project they mean; only the app has lost its way to it, and
  /// deleting the row would hide a project they may well still have.
  final bool needsReconnect;

  String get name {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  RecentProject copyWith({bool? needsReconnect, String? folderBookmark}) =>
      RecentProject(
        path: path,
        folderBookmark: folderBookmark ?? this.folderBookmark,
        needsReconnect: needsReconnect ?? this.needsReconnect,
      );

  Map<String, dynamic> toJson() => {
    'path': path,
    'folderBookmark': folderBookmark,
    'needsReconnect': needsReconnect,
  };

  static RecentProject? fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String?;
    if (path == null || path.isEmpty) {
      return null;
    }
    final bookmark = json['folderBookmark'] as String?;
    return RecentProject(
      path: path,
      folderBookmark: bookmark != null && bookmark.isNotEmpty ? bookmark : null,
      needsReconnect: json['needsReconnect'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecentProject &&
      other.path == path &&
      other.folderBookmark == folderBookmark &&
      other.needsReconnect == needsReconnect;

  @override
  int get hashCode => Object.hash(path, folderBookmark, needsReconnect);
}

/// The list, newest first.
@immutable
class RecentProjects {
  const RecentProjects({this.entries = const []});

  /// Ten, the same cap the recent-colours strip uses. Long enough to span a
  /// working week of cuts, short enough that the menu stays a menu.
  static const int maxEntries = 10;

  final List<RecentProject> entries;

  /// Records an open. Promotes to the front, de-duplicates by path, caps.
  ///
  /// Returns `this` unchanged when nothing moved — the caller writes to disk
  /// on every change, and re-saving the already-open project would otherwise
  /// rewrite the file on every Ctrl+S. That exact bug already happened once
  /// with the colour palette, which wrote its JSON on every stroke commit.
  RecentProjects withOpened(RecentProject project) {
    if (entries.isNotEmpty && entries.first == project) {
      return this;
    }
    return RecentProjects(
      entries: [
        project,
        ...entries.where((entry) => entry.path != project.path),
      ].take(maxEntries).toList(),
    );
  }

  /// Flags an entry whose bookmark stopped resolving. Unknown paths are
  /// ignored, and an entry already flagged returns `this`.
  RecentProjects withReconnectNeeded(String path) {
    var changed = false;
    final next = [
      for (final entry in entries)
        if (entry.path == path && !entry.needsReconnect)
          () {
            changed = true;
            return entry.copyWith(needsReconnect: true);
          }()
        else
          entry,
    ];
    return changed ? RecentProjects(entries: next) : this;
  }

  /// Replaces an entry's bookmark after a successful reconnect, clearing the
  /// flag with it.
  RecentProjects withReconnected(String path, String? folderBookmark) {
    var changed = false;
    final next = [
      for (final entry in entries)
        if (entry.path == path)
          () {
            changed = true;
            return RecentProject(
              path: entry.path,
              folderBookmark: folderBookmark,
            );
          }()
        else
          entry,
    ];
    return changed ? RecentProjects(entries: next) : this;
  }

  RecentProjects without(String path) {
    if (!entries.any((entry) => entry.path == path)) {
      return this;
    }
    return RecentProjects(
      entries: [
        for (final entry in entries)
          if (entry.path != path) entry,
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'entries': [for (final entry in entries) entry.toJson()],
  };

  static RecentProjects fromJson(Map<String, dynamic> json) {
    final raw = json['entries'];
    if (raw is! List) {
      return const RecentProjects();
    }
    final parsed = <RecentProject>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final entry = RecentProject.fromJson(
        item.map((key, value) => MapEntry('$key', value)),
      );
      if (entry != null) {
        parsed.add(entry);
      }
    }
    // Re-capped on read so a hand-edited file cannot grow the menu.
    return RecentProjects(entries: parsed.take(maxEntries).toList());
  }

  @override
  bool operator ==(Object other) =>
      other is RecentProjects && listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hashAll(entries);
}

/// The app-wide live list — the [AppSave] idiom.
abstract final class AppRecent {
  static final ValueNotifier<RecentProjects> projects =
      ValueNotifier<RecentProjects>(const RecentProjects());
}
