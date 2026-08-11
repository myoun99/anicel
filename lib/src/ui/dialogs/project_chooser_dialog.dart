import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/persistence/anicel_project_archive.dart';
import '../../services/persistence/recent_projects.dart';
import '../../services/persistence/recent_projects_store.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart' show AppColors;
import '../widgets/app_window.dart';
import '../widgets/panel_flyout.dart';

/// PICK-3: which project, once the folder is known.
///
/// The native picker hands back a FOLDER — it has to, because a security
/// scope covers exactly what was picked and a project needs its sibling
/// `.assets/` directory and its autosave sidecar. That leaves one question
/// the OS cannot answer: which of the projects inside it.
///
/// This window ALWAYS opens, whatever the folder holds. It used to skip
/// itself when there was exactly one project, and that shortcut was the
/// thing that made the flow feel unpredictable: what came back after picking
/// a folder depended on a count the user could not see. One window, three
/// states — nothing, one, many.
class ProjectEntry {
  const ProjectEntry({
    required this.path,
    required this.name,
    required this.modified,
    required this.bytes,
  });

  final String path;
  final String name;
  final DateTime modified;
  final int bytes;
}

/// The `.anicel` files in [folderPath], in whatever order the filesystem
/// gave them.
///
/// Deliberately UNSORTED. Ordering is the chooser's business — it is a
/// display preference the user changes at will — and a reader that imposes
/// one is a second opinion the dialog then has to override.
///
/// Sync on purpose: async `dart:io` never completes under the widget-test
/// clock, so anything a dialog touches during build has to be sync or it can
/// never be tested. Directory listings at dialog scale are cheap.
List<ProjectEntry> anicelProjectsIn(String folderPath) {
  final directory = Directory(folderPath);
  if (!directory.existsSync()) {
    return const [];
  }
  final entries = <ProjectEntry>[];
  for (final entity in directory.listSync(followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final normalized = entity.path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    final name = slash < 0 ? normalized : normalized.substring(slash + 1);
    if (!name.toLowerCase().endsWith(anicelProjectSuffix)) {
      continue;
    }
    final stat = entity.statSync();
    entries.add(
      ProjectEntry(
        path: normalized,
        name: name,
        modified: stat.modified,
        bytes: stat.size,
      ),
    );
  }
  return entries;
}

/// Compares two names the way a person reads them: digit runs as NUMBERS.
///
/// Plain string order puts `C-10` before `C-9`, which is wrong for every
/// naming scheme this app meets — cuts are numbered sequences. The user's own
/// files happen to be zero-padded today, so this would not bite immediately;
/// it would bite the first time a folder came from someone who padded
/// differently, and the cut-folder rules already record that field naming is
/// not a fixed convention.
int naturalCompare(String a, String b) {
  final lowerA = a.toLowerCase();
  final lowerB = b.toLowerCase();
  var i = 0;
  var j = 0;
  while (i < lowerA.length && j < lowerB.length) {
    final digitA = _isDigit(lowerA.codeUnitAt(i));
    final digitB = _isDigit(lowerB.codeUnitAt(j));
    if (digitA && digitB) {
      final startA = i;
      final startB = j;
      while (i < lowerA.length && _isDigit(lowerA.codeUnitAt(i))) {
        i += 1;
      }
      while (j < lowerB.length && _isDigit(lowerB.codeUnitAt(j))) {
        j += 1;
      }
      // Compared by VALUE, so 9 < 10; leading zeros break the tie so that
      // `C-09` and `C-9` still have a stable, repeatable order.
      final numberA = lowerA.substring(startA, i);
      final numberB = lowerB.substring(startB, j);
      final trimmedA = numberA.replaceFirst(RegExp(r'^0+(?=.)'), '');
      final trimmedB = numberB.replaceFirst(RegExp(r'^0+(?=.)'), '');
      if (trimmedA.length != trimmedB.length) {
        return trimmedA.length - trimmedB.length;
      }
      final byValue = trimmedA.compareTo(trimmedB);
      if (byValue != 0) {
        return byValue;
      }
      final byPadding = numberA.length - numberB.length;
      if (byPadding != 0) {
        return byPadding;
      }
      continue;
    }
    final unitA = lowerA.codeUnitAt(i);
    final unitB = lowerB.codeUnitAt(j);
    if (unitA != unitB) {
      return unitA - unitB;
    }
    i += 1;
    j += 1;
  }
  return (lowerA.length - i) - (lowerB.length - j);
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

/// Orders [entries] for display. Never mutates the input.
List<ProjectEntry> sortProjectEntries(
  List<ProjectEntry> entries, {
  required ProjectSortKey key,
  required bool ascending,
}) {
  final sorted = [...entries];
  sorted.sort((a, b) {
    final forward = switch (key) {
      ProjectSortKey.name => naturalCompare(a.name, b.name),
      ProjectSortKey.modified => a.modified.compareTo(b.modified),
      ProjectSortKey.size => a.bytes.compareTo(b.bytes),
    };
    // Name breaks every tie, so two files saved in the same minute do not
    // swap places between openings.
    final resolved = forward != 0 ? forward : naturalCompare(a.name, b.name);
    return ascending ? resolved : -resolved;
  });
  return sorted;
}

/// Two digits, so a date column lines up.
String _two(int value) => value < 10 ? '0$value' : '$value';

/// `2026-08-11 14:03`. Deliberately numeric and language-neutral: the column
/// is scanned rather than read, and a localized month name would make the
/// rows ragged in five languages for no gain.
String formatProjectModified(DateTime when) {
  final local = when.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

/// Asks which project to open. Returns its path, or null if the user backed
/// out — including from a folder that holds nothing openable.
Future<String?> showProjectChooser(
  BuildContext context, {
  required List<ProjectEntry> entries,
  required String folderPath,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _ProjectChooserDialog(entries: entries, folderPath: folderPath),
  );
}

class _ProjectChooserDialog extends StatefulWidget {
  const _ProjectChooserDialog({
    required this.entries,
    required this.folderPath,
  });

  final List<ProjectEntry> entries;
  final String folderPath;

  @override
  State<_ProjectChooserDialog> createState() => _ProjectChooserDialogState();
}

class _ProjectChooserDialogState extends State<_ProjectChooserDialog> {
  late ProjectSortKey _key = AppRecent.projects.value.sortKey;
  late bool _ascending = AppRecent.projects.value.sortAscending;

  /// Row height. Denser than a two-line list — this window is now on the way
  /// to every project, so it is read at a glance — but taller than the 30px
  /// the same layout would take on a mouse, because on iPad it is a finger.
  static const double _rowHeight = 40;

  void _applySort({ProjectSortKey? key, bool? ascending}) {
    final nextKey = key ?? _key;
    final nextAscending = ascending ?? _ascending;
    // Picking the order it is already in writes nothing. `copyWith` would
    // hand back an equal-but-new object, which the store's identity guard
    // cannot see through — and this file would then be rewritten every time
    // the menu was opened and closed on the same choice.
    if (nextKey == _key && nextAscending == _ascending) {
      return;
    }
    setState(() {
      _key = nextKey;
      _ascending = nextAscending;
    });
    storeRecentProjects(
      AppRecent.projects.value.copyWith(
        sortKey: nextKey,
        sortAscending: nextAscending,
      ),
    );
  }

  String _sortLabel(AppStrings strings) => switch (_key) {
    ProjectSortKey.name => strings.sortByName,
    ProjectSortKey.modified => strings.sortByModified,
    ProjectSortKey.size => strings.sortBySize,
  };

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final sorted = sortProjectEntries(
      widget.entries,
      key: _key,
      ascending: _ascending,
    );
    return AppWindow(
      windowKey: const ValueKey<String>('project-chooser-dialog'),
      title: strings.fileOpenTitle,
      titleIcon: Icons.folder_open_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 460,
      height: 420,
      scrollBody: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _folderBar(strings),
          Expanded(
            child: sorted.isEmpty
                ? Center(
                    child: Text(
                      strings.projectChooserEmpty,
                      key: const ValueKey<String>('project-chooser-empty'),
                      style: const TextStyle(color: AppColors.textDim),
                    ),
                  )
                : ListView.builder(
                    primary: false,
                    itemExtent: _rowHeight,
                    itemCount: sorted.length,
                    itemBuilder: (context, index) => _row(sorted[index]),
                  ),
          ),
        ],
      ),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('project-chooser-cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  /// Which folder this list is OF, and how it is ordered.
  ///
  /// The path matters more than it looks: the granted folder is nearly always
  /// named the same thing across jobs (the user's layout is
  /// `<work>/작업/<project>`), so a folder NAME would read identically for
  /// every production. The path is ellipsized from the LEFT so the tail —
  /// the part that differs — survives, which is the trick the in-app browser
  /// used before it was deleted.
  Widget _folderBar(AppStrings strings) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.folder_outlined,
            size: 13,
            color: AppColors.textDim,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.folderPath,
              key: const ValueKey<String>('project-chooser-folder'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontSize: 11, color: AppColors.textDim),
            ),
          ),
          const SizedBox(width: 8),
          _sortButton(strings),
        ],
      ),
    );
  }

  /// The sort control.
  ///
  /// Says the current order TWICE, and both are deliberate. The button reads
  /// `Name ↑` so the state is legible without opening anything, and inside
  /// the menu the row in force is marked `selected` — which this app renders
  /// as COLOUR, never a check glyph. `checked` would be wrong here: it means
  /// a toggle, and picking one of three orders is a selection.
  Widget _sortButton(AppStrings strings) {
    final arrow = _ascending ? '↑' : '↓';
    return PanelFlyoutButton(
      key: const ValueKey<String>('project-chooser-sort'),
      label: '${_sortLabel(strings)} $arrow',
      tooltip: strings.sortByName,
      fontSize: 11,
      entriesBuilder: () => [
        for (final key in ProjectSortKey.values)
          PanelFlyoutItem(
            keyValue: 'project-chooser-sort-${key.jsonValue}',
            label: switch (key) {
              ProjectSortKey.name => strings.sortByName,
              ProjectSortKey.modified => strings.sortByModified,
              ProjectSortKey.size => strings.sortBySize,
            },
            selected: key == _key,
            onSelected: () => _applySort(key: key),
          ),
        const PanelFlyoutDivider(),
        PanelFlyoutItem(
          keyValue: 'project-chooser-sort-asc',
          label: strings.sortAscending,
          selected: _ascending,
          onSelected: () => _applySort(ascending: true),
        ),
        PanelFlyoutItem(
          keyValue: 'project-chooser-sort-desc',
          label: strings.sortDescending,
          selected: !_ascending,
          onSelected: () => _applySort(ascending: false),
        ),
      ],
    );
  }

  /// One line: what it is called, and when it was last touched.
  ///
  /// Tap opens, the way a gallery does. There is no select-then-confirm step:
  /// the row already says which project it is, so a second tap would only
  /// confirm what the first one showed.
  Widget _row(ProjectEntry entry) {
    return InkWell(
      key: ValueKey<String>('project-chooser-${entry.name}'),
      onTap: () => Navigator.of(context).pop(entry.path),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            const Icon(
              Icons.movie_creation_outlined,
              size: 15,
              color: AppColors.textDim,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.text),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              formatProjectModified(entry.modified),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textDim,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
