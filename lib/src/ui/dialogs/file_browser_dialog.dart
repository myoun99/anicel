import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/persistence/app_documents.dart';
import '../widgets/app_window.dart';
import 'app_confirm_dialog.dart';
import 'app_prompt_dialog.dart';

/// SAVE-1c: the in-app file browser — the MOBILE open/save surface of
/// the real-path model (the OS pickers hand out content URIs Android-
/// side, which the path-based save stack cannot edit in place; iOS has
/// no save dialog at all). Browses REAL directories only, so everything
/// picked here works with incremental saves, sidecars and the
/// `<project>.assets/` folder pair.
///
/// Cloud folders are explicitly the sync-app mirror model: the footer
/// says so instead of pretending a Drive document could open in place.
enum FileBrowserMode { open, saveAs }

Future<String?> showQapFileBrowser(
  BuildContext context, {
  required FileBrowserMode mode,
  String? suggestedName,
  String? initialDirectory,
}) async {
  final startDirectory =
      initialDirectory ?? await ensuredAppDocumentsDirectory();
  if (!context.mounted) {
    return null;
  }
  return showDialog<String>(
    context: context,
    builder: (context) => _FileBrowserDialog(
      mode: mode,
      suggestedName: suggestedName,
      initialDirectory: startDirectory,
    ),
  );
}

class _FileBrowserDialog extends StatefulWidget {
  const _FileBrowserDialog({
    required this.mode,
    required this.suggestedName,
    required this.initialDirectory,
  });

  final FileBrowserMode mode;
  final String? suggestedName;
  final String initialDirectory;

  @override
  State<_FileBrowserDialog> createState() => _FileBrowserDialogState();
}

class _FileBrowserDialogState extends State<_FileBrowserDialog> {
  late String _directory = widget.initialDirectory.replaceAll('\\', '/');
  late final TextEditingController _name = TextEditingController(
    text: widget.suggestedName ?? '',
  );
  List<FileSystemEntity> _entries = const [];
  String? _error;
  bool _accessGranted = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    _accessGranted = await AppStorage.isAllFilesAccessGranted();
    if (!mounted) {
      return;
    }
    try {
      final directory = Directory(_directory);
      // Sync listing by design: dialog-sized directories, and the sync
      // API works under the widget-test clock (async dart:io never
      // completes there).
      final listing = directory.listSync(followLinks: false);
      listing.sort((a, b) {
        final aDir = a is Directory ? 0 : 1;
        final bDir = b is Directory ? 0 : 1;
        if (aDir != bDir) {
          return aDir - bDir;
        }
        return _nameOf(a).toLowerCase().compareTo(_nameOf(b).toLowerCase());
      });
      setState(() {
        _entries = [
          for (final entry in listing)
            if (entry is Directory ||
                (widget.mode == FileBrowserMode.open &&
                    _nameOf(entry).toLowerCase().endsWith('.qap')))
              entry,
        ];
        _error = null;
      });
    } on Object catch (error) {
      setState(() {
        _entries = const [];
        _error = '$error';
      });
    }
  }

  static String _nameOf(FileSystemEntity entity) {
    final path = entity.path.replaceAll('\\', '/');
    final index = path.lastIndexOf('/');
    return index < 0 ? path : path.substring(index + 1);
  }

  void _enter(String path) {
    setState(() => _directory = path.replaceAll('\\', '/'));
    _refresh();
  }

  void _up() {
    final index = _directory.lastIndexOf('/');
    if (index > 0) {
      _enter(_directory.substring(0, index));
    }
  }

  Future<void> _newFolder() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const AppPromptDialog(
        windowKey: ValueKey<String>('file-browser-new-folder-dialog'),
        title: 'New folder',
        titleIcon: Icons.create_new_folder_outlined,
        fieldLabel: 'Folder name',
        initialValue: '',
        confirmLabel: 'Create',
        emptyError: 'Folder name cannot be empty.',
        fieldKey: ValueKey<String>('file-browser-new-folder-name'),
        confirmKey: ValueKey<String>('file-browser-new-folder-create'),
      ),
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty || !mounted) {
      return;
    }
    try {
      Directory('$_directory/$trimmed').createSync(recursive: true);
      _enter('$_directory/$trimmed');
    } on Object catch (error) {
      setState(() => _error = '$error');
    }
  }

  Future<void> _saveHere() async {
    var name = _name.text.trim();
    if (name.isEmpty) {
      return;
    }
    if (!name.toLowerCase().endsWith('.qap')) {
      name = '$name.qap';
    }
    final path = '$_directory/$name';
    if (File(path).existsSync()) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (context) => AppConfirmDialog(
          windowKey: const ValueKey<String>('file-browser-replace-dialog'),
          title: 'Replace file?',
          titleIcon: Icons.warning_amber_outlined,
          message: '$name already exists here.',
          actions: [
            AppWindowAction(
              label: 'Cancel',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            AppWindowAction(
              label: 'Replace',
              actionKey: const ValueKey<String>('file-browser-overwrite'),
              emphasis: AppWindowActionEmphasis.primary,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      if (overwrite != true || !mounted) {
        return;
      }
    }
    if (mounted) {
      Navigator.of(context).pop(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppWindow(
      windowKey: const ValueKey<String>('file-browser-dialog'),
      title: widget.mode == FileBrowserMode.open
          ? 'Open project'
          : 'Save project',
      titleIcon: widget.mode == FileBrowserMode.open
          ? Icons.folder_open_outlined
          : Icons.save_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 560,
      height: 540,
      scrollBody: false,
      body: SizedBox(
        width: 520,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey<String>('file-browser-up'),
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'Up',
                  onPressed: _up,
                ),
                TextButton(
                  key: const ValueKey<String>('file-browser-root-appdocs'),
                  onPressed: () => _enter(ensuredAppDocumentsDirectorySync()),
                  child: const Text('App documents'),
                ),
                Expanded(
                  child: Text(
                    _directory,
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                  ),
                ),
              ],
            ),
            if (!_accessGranted)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: colorScheme.errorContainer,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Storage access is off — projects outside the app '
                      'folder need the All-Files permission.',
                      style: TextStyle(fontSize: 12),
                    ),
                    TextButton(
                      key: const ValueKey<String>('file-browser-grant'),
                      onPressed: () async {
                        await AppStorage.requestAllFilesAccess();
                      },
                      child: const Text('Open settings'),
                    ),
                    TextButton(
                      key: const ValueKey<String>('file-browser-recheck'),
                      onPressed: _refresh,
                      child: const Text('Check again'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: TextStyle(color: colorScheme.error),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final entry in _entries)
                          ListTile(
                            key: ValueKey<String>(
                              'file-browser-entry-${_nameOf(entry)}',
                            ),
                            dense: true,
                            leading: Icon(
                              entry is Directory
                                  ? Icons.folder
                                  : Icons.movie_creation_outlined,
                            ),
                            title: Text(_nameOf(entry)),
                            onTap: () {
                              if (entry is Directory) {
                                _enter(entry.path);
                              } else if (widget.mode == FileBrowserMode.open) {
                                Navigator.of(context).pop(entry.path);
                              } else {
                                _name.text = _nameOf(entry);
                              }
                            },
                          ),
                      ],
                    ),
            ),
            if (widget.mode == FileBrowserMode.saveAs)
              AppWindowField(
                label: 'File name',
                emphasized: true,
                child: TextField(
                  key: const ValueKey<String>('file-browser-name'),
                  controller: _name,
                  decoration: const InputDecoration(suffixText: '.qap'),
                  onSubmitted: (_) => _saveHere(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                widget.mode == FileBrowserMode.open
                    ? 'Cloud services (Google Drive, Dropbox …): use a sync '
                          'app (Autosync, FolderSync …) and open its mirror '
                          'folder here — direct cloud documents are not '
                          'supported.'
                    : 'Cloud folders: save into a sync-app mirror folder to '
                          'work with Google Drive / Dropbox.',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.mode == FileBrowserMode.saveAs)
          AppWindowAction(
            label: 'New folder…',
            actionKey: const ValueKey<String>('file-browser-new-folder'),
            onPressed: _newFolder,
          ),
        AppWindowAction(
          label: 'Cancel',
          actionKey: const ValueKey<String>('file-browser-cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (widget.mode == FileBrowserMode.saveAs)
          AppWindowAction(
            label: 'Save',
            actionKey: const ValueKey<String>('file-browser-save'),
            emphasis: AppWindowActionEmphasis.primary,
            onPressed: _saveHere,
          ),
      ],
    );
  }
}

