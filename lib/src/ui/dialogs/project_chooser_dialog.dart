import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/persistence/anicel_project_archive.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// PICK-3: which project, once the folder is known.
///
/// The native picker hands back a FOLDER — it has to, because a security
/// scope covers exactly what was picked and a project needs its sibling
/// `.assets/` directory and its autosave sidecar. That leaves one question
/// the OS cannot answer: which of the projects inside it.
///
/// This is not a rare branch. The user works one folder per cut and put it
/// plainly — 「물론 여러개 들어가있을때가 많아」 — so this window is, in
/// practice, the open dialog on iPad and macOS. It is built accordingly:
/// modification date on every row, newest first, because the one the user
/// wants is nearly always the one they touched last.
///
/// A folder holding exactly one project skips it entirely. Confirming a
/// choice that has no alternative is a step that only ever costs a tap.
class ProjectEntry {
  const ProjectEntry({required this.path, required this.name, required this.modified});

  final String path;
  final String name;
  final DateTime modified;
}

/// The `.anicel` files in [folderPath], newest first.
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
    entries.add(
      ProjectEntry(
        path: normalized,
        name: name,
        modified: entity.lastModifiedSync(),
      ),
    );
  }
  entries.sort((a, b) => b.modified.compareTo(a.modified));
  return entries;
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
/// out — or if the folder holds nothing openable.
///
/// Skips the window when [entries] holds exactly one project.
Future<String?> showProjectChooser(
  BuildContext context, {
  required List<ProjectEntry> entries,
}) async {
  if (entries.length == 1) {
    return entries.first.path;
  }
  return showDialog<String>(
    context: context,
    builder: (context) => _ProjectChooserDialog(entries: entries),
  );
}

class _ProjectChooserDialog extends StatelessWidget {
  const _ProjectChooserDialog({required this.entries});

  final List<ProjectEntry> entries;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final colorScheme = Theme.of(context).colorScheme;
    return AppWindow(
      windowKey: const ValueKey<String>('project-chooser-dialog'),
      title: strings.fileOpenTitle,
      titleIcon: Icons.folder_open_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 460,
      height: 420,
      scrollBody: false,
      body: SizedBox(
        width: 420,
        height: 320,
        child: entries.isEmpty
            ? Center(
                child: Text(
                  strings.projectChooserEmpty,
                  key: const ValueKey<String>('project-chooser-empty'),
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              )
            : ListView(
                children: [
                  for (final entry in entries)
                    ListTile(
                      key: ValueKey<String>('project-chooser-${entry.name}'),
                      dense: true,
                      leading: const Icon(Icons.movie_creation_outlined),
                      title: Text(entry.name),
                      subtitle: Text(formatProjectModified(entry.modified)),
                      // Tap opens, the way a gallery does. There is no
                      // select-then-confirm step: the row already says which
                      // project it is and when it was last touched, so a
                      // second tap would only confirm what the first one
                      // already showed.
                      onTap: () => Navigator.of(context).pop(entry.path),
                    ),
                ],
              ),
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
}
