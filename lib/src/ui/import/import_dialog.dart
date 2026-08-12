import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../models/import/cut_folder_parse.dart';
import '../../models/import/tvp_json_parse.dart';
import '../../models/media_asset.dart';
import '../../services/import/media_import_planner.dart';
import '../../services/pdf/pdf_render_service.dart';
import '../../services/persistence/file_type_groups.dart';
import '../dialogs/folder_pick_flow.dart';
import '../editor_session_manager.dart';
import '../export/export_settings_modules.dart';
import '../widgets/app_window.dart';

/// The 가져오기/배치 window (§6-z21): ONE window for every import — file
/// picks, folder drops, OS drag-and-drop all land here, defaults filled
/// so the simple case is a single Enter. The interpretation table shows
/// what each source becomes (folders list every file, dropped ones
/// included — nothing exits silently).
///
/// v1 zones: source bar → interpretation table (preview) | settings
/// modules → action bar. The preset rail and queue drawers of the export
/// skeleton join when parser presets get their store.
class ImportDialog extends StatefulWidget {
  const ImportDialog({
    super.key,
    required this.session,
    this.initialPaths = const [],
    this.filePicker,
    this.directoryPicker,
  });

  final EditorSessionManager session;

  /// Sources handed in by drag-and-drop (files or one folder).
  final List<String> initialPaths;

  /// Injectable pickers (tests).
  final Future<List<String>> Function()? filePicker;
  final Future<String?> Function()? directoryPicker;

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  final List<String> _files = [];
  String? _folder;
  ImportDestination _destination = ImportDestination.activeCutLayer;
  bool _rasterize = false;
  MediaFitMode _fit = MediaFitMode.contain;
  CutFolderParseConfig _parseConfig = const CutFolderParseConfig();
  CutFolderParseResult? _parsed;
  bool _running = false;
  String _status = '';

  /// A picked `.json` that turns out to be a TVPaint export. It brings a
  /// whole cut with it — stack, exposure, cel numbers — so it becomes THE
  /// source rather than joining the file list.
  String? _tvpJsonPath;
  TvpJsonParseResult? _tvpJson;

  /// Sources the drop carried but this window cannot act on (the folder
  /// path wins when a folder is among them) — listed so nothing exits
  /// silently.
  final List<String> _ignoredSources = [];

  @override
  void initState() {
    super.initState();
    for (final path in widget.initialPaths) {
      if (Directory(path).existsSync()) {
        if (_folder == null) {
          _folder = path;
        } else {
          _ignoredSources.add(path);
        }
      } else {
        _files.add(path);
      }
    }
    final dropped = _folder;
    if (dropped != null) {
      // §6-z22: folder imports always BAKE (cels are for drawing on) —
      // the toggle is not offered in folder mode.
      _rasterize = true;
      // A folder came with loose files: the folder is the import, the
      // files are listed as ignored (one window, one source shape).
      _ignoredSources.addAll(_files);
      _files.clear();
      // A TVPaint export is a folder too. Reading one with the cut-folder
      // parser produces nonsense out of `[001] TAP/` and friends, so the
      // contents decide which import this is — not which button was used.
      if (_looksLikeTvpExport(dropped)) {
        _folder = null;
        _adoptTvpExportFolder(dropped);
      } else {
        _reparseFolder();
      }
    } else {
      _adoptTvpJsonFromFiles();
    }
  }

  /// Promotes a picked or dropped TVPaint `.json` to THE source. A
  /// `.json` that is not one keeps the window open with the reason
  /// instead of failing later as a decode (§6-z21: nothing exits
  /// silently).
  void _adoptTvpJsonFromFiles() {
    _tvpJsonPath = null;
    _tvpJson = null;
    final candidate = _files.firstWhere(
      (path) => path.toLowerCase().endsWith('.json'),
      orElse: () => '',
    );
    if (candidate.isEmpty) {
      return;
    }
    // A `.json` this window cannot read must LEAVE the file list. Left in
    // it, Import would send it down the still-image path and report
    // "corrupt or password-locked" — which is not what happened.
    void reject(String reason) {
      _status = '${mediaAssetDefaultName(candidate)}: $reason';
      _files.remove(candidate);
      _ignoredSources.add(candidate);
    }

    final TvpJsonParseResult parsed;
    try {
      parsed = parseTvpJson(File(candidate).readAsStringSync());
    } on TvpJsonParseException catch (error) {
      reject(error.message);
      return;
    } on FileSystemException catch (error) {
      reject(error.message);
      return;
    }
    _tvpJson = parsed;
    _tvpJsonPath = candidate;
    // The export IS the import; anything picked alongside it is listed
    // rather than dropped.
    _ignoredSources.addAll(_files.where((path) => path != candidate));
    _files.clear();
  }

  /// Adopts a TVPaint export FOLDER: the `.json` plus the per-instance
  /// image folders that sit beside it.
  ///
  /// 🚨 The folder — not the `.json` — is what gets picked, and that is
  /// the whole point. On iOS and macOS a security scope lands on exactly
  /// the item the user chose and nowhere else, so picking `clip.json`
  /// grants that one file and leaves `[001] TAP/` unreadable: the cut
  /// imports with every cel empty. The project picker learned this the
  /// same way (its sidecars sit beside the file it used to pick).
  void _adoptTvpExportFolder(String folderPath) {
    _tvpJsonPath = null;
    _tvpJson = null;
    final List<String> jsonPaths;
    try {
      jsonPaths = [
        for (final entity in Directory(folderPath).listSync())
          if (entity is File && entity.path.toLowerCase().endsWith('.json'))
            entity.path,
      ]..sort();
    } on FileSystemException catch (error) {
      _status = 'Could not read that folder: ${error.message}';
      return;
    }
    if (jsonPaths.isEmpty) {
      _status =
          '${mediaAssetDefaultName(folderPath)}: no .json in this folder — '
          'pick the folder TVPaint exported, the one holding the image '
          'folders.';
      return;
    }
    for (final path in jsonPaths) {
      try {
        _tvpJson = parseTvpJson(File(path).readAsStringSync());
        _tvpJsonPath = path;
        break;
      } on TvpJsonParseException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    if (_tvpJsonPath == null) {
      _status =
          '${mediaAssetDefaultName(folderPath)}: none of its '
          '${jsonPaths.length} .json file(s) is a TVPaint export.';
      return;
    }
    // Nothing exits silently: the ones that were not the export are named.
    _ignoredSources.addAll(jsonPaths.where((path) => path != _tvpJsonPath));
  }

  /// Whether [folderPath] is a TVPaint export rather than a cut folder —
  /// a dropped export folder must not go down the cut-folder parser and
  /// come out as nonsense.
  bool _looksLikeTvpExport(String folderPath) {
    try {
      for (final entity in Directory(folderPath).listSync()) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
          continue;
        }
        try {
          parseTvpJson(File(entity.path).readAsStringSync());
          return true;
        } on Object {
          continue;
        }
      }
    } on FileSystemException {
      return false;
    }
    return false;
  }

  Future<void> _pickTvpExport() async {
    final path = widget.directoryPicker != null
        ? await widget.directoryPicker!()
        : await pickFolderForUser(context);
    if (path == null || !mounted) {
      return;
    }
    setState(() {
      _folder = null;
      _parsed = null;
      _status = '';
      _files.clear();
      _ignoredSources.clear();
      _adoptTvpExportFolder(path);
    });
  }

  Future<void> _pickFiles() async {
    final picker =
        widget.filePicker ??
        () async {
          final files = await openFiles(
            acceptedTypeGroups: const [FileTypeGroups.importableMedia],
          );
          return [for (final file in files) file.path];
        };
    final paths = await picker();
    if (paths.isEmpty || !mounted) {
      return;
    }
    setState(() {
      _folder = null;
      _parsed = null;
      _files
        ..clear()
        ..addAll(paths);
      _adoptTvpJsonFromFiles();
    });
  }

  Future<void> _pickFolder() async {
    // PICK-2: not `getDirectoryPath`. That call is unimplemented on iOS and
    // returns a SAF tree URI on Android — and the very next thing this does
    // is `Directory(folder).listSync(recursive: true)`, which answers "that
    // folder is gone" for a URI. A wrong answer that looks like a right one.
    final path = widget.directoryPicker != null
        ? await widget.directoryPicker!()
        : await pickFolderForUser(context);
    if (path == null || !mounted) {
      return;
    }
    setState(() {
      _files.clear();
      _tvpJsonPath = null;
      _tvpJson = null;
      _folder = path;
      _rasterize = true;
      _reparseFolder();
    });
  }

  /// The folder's entries, scanned ONCE per folder pick — re-parsing on
  /// a knob change replays these instead of walking the disk again.
  List<CutFolderEntry>? _folderEntries;

  void _reparseFolder({bool rescan = true}) {
    final folder = _folder;
    if (folder == null) {
      _parsed = null;
      _folderEntries = null;
      return;
    }
    if (rescan || _folderEntries == null) {
      final directory = Directory(folder);
      if (!directory.existsSync()) {
        _parsed = null;
        _folderEntries = null;
        _status = 'That folder is gone.';
        return;
      }
      final prefixLength = directory.path.length + 1;
      final entries = <CutFolderEntry>[];
      try {
        for (final entity in directory.listSync(recursive: true)) {
          final relative = entity.path.length > prefixLength
              ? entity.path.substring(prefixLength)
              : entity.path;
          entries.add(
            CutFolderEntry(
              relative.replaceAll('\\', '/'),
              isDirectory: entity is Directory,
            ),
          );
        }
      } on FileSystemException catch (error) {
        _parsed = null;
        _folderEntries = null;
        _status = 'Could not read the folder: ${error.message}';
        return;
      }
      _folderEntries = entries;
    }
    final directory = Directory(folder);
    final parentPath = directory.parent.path;
    _parsed = parseCutFolder(
      folderName: mediaAssetDefaultName(folder),
      entries: _folderEntries!,
      config: _parseConfig,
      parentFolderName: parentPath.isEmpty
          ? null
          : mediaAssetDefaultName(parentPath),
    );
  }

  bool get _canImport =>
      !_running &&
      (_files.isNotEmpty ||
          (_folder != null && _parsed != null) ||
          _tvpJson != null);

  /// Kinds not placeable yet (video needs a decode engine): named
  /// honestly instead of failing as a decode. PDF left this set in R4.
  static const Set<MediaAssetKind> _unplaceableKinds = {
    MediaAssetKind.video,
  };

  Future<void> _runImport() async {
    if (!_canImport) {
      return;
    }
    setState(() {
      _running = true;
      _status = 'Importing…';
    });
    final session = widget.session;
    var imported = 0;
    final warnings = <String>[];
    final done = <String>[];
    try {
      final folder = _folder;
      final tvpJsonPath = _tvpJsonPath;
      if (tvpJsonPath != null) {
        // 1:1 always — see the Fit note in the settings column.
        final tvpWarnings = await session.importTvpJson(
          jsonPath: tvpJsonPath,
          fit: MediaFitMode.none,
        );
        if (tvpWarnings == null) {
          warnings.add('Could not read that TVPaint export.');
        } else {
          imported += 1;
          done.add(tvpJsonPath);
          warnings.addAll(tvpWarnings);
        }
      } else if (folder != null) {
        final folderWarnings = await session.importCutFolder(
          folderPath: folder,
          config: _parseConfig,
          fit: _fit,
        );
        if (folderWarnings == null) {
          warnings.add('Could not read that folder.');
        } else {
          imported += 1;
          warnings.addAll(folderWarnings);
        }
      } else {
        // Audio registers as ONE batch (one undo), whatever the count.
        final audioPaths = [
          for (final path in _files)
            if (mediaAssetKindForPath(path) == MediaAssetKind.audio) path,
        ];
        if (audioPaths.isNotEmpty) {
          session.importMediaFiles(audioPaths);
          imported += audioPaths.length;
          done.addAll(audioPaths);
        }
        for (final path in _files) {
          final kind = mediaAssetKindForPath(path);
          if (kind == MediaAssetKind.audio) {
            continue;
          }
          if (_unplaceableKinds.contains(kind)) {
            warnings.add(
              '${mediaAssetDefaultName(path)}: ${kind!.jsonValue} placement '
              'is not available yet.',
            );
            continue;
          }
          final failedPages = <int>[];
          final bool ok;
          try {
            ok = kind == MediaAssetKind.pdf
                ? await session.importPdfFile(
                    path: path,
                    destination: _destination,
                    rasterize: _rasterize,
                    fit: _fit,
                    // A 100-page conte renders for seconds — the footer
                    // says where it is instead of looking hung.
                    onRenderProgress: (rendered, total) {
                      if (mounted) {
                        setState(
                          () =>
                              _status = 'Rendering PDF page $rendered/$total…',
                        );
                      }
                    },
                    onPageRenderFailed: failedPages.add,
                  )
                : await session.importImageFile(
                    path: path,
                    destination: _destination,
                    rasterize: _rasterize,
                    fit: _fit,
                  );
          } on Object {
            // A corrupt/locked file must not abort the rest of the batch —
            // it gets its named warning and the loop moves on (the image
            // path's per-file contract).
            warnings.add(
              '${mediaAssetDefaultName(path)} could not be opened — '
              'corrupt or password-locked.',
            );
            continue;
          }
          if (failedPages.isNotEmpty) {
            warnings.add(
              '${mediaAssetDefaultName(path)}: ${failedPages.length} '
              'page(s) failed to render — their cels stay empty.',
            );
          }
          if (ok) {
            imported += 1;
            done.add(path);
          } else {
            warnings.add(
              kind == MediaAssetKind.pdf &&
                      PdfRenderService.availability != true
                  ? '${mediaAssetDefaultName(path)}: no PDF renderer in '
                        'this build.'
                  : _destination == ImportDestination.activeCutLayer &&
                        session.activeCutOrNull == null
                  ? 'No active cut — pick "New cut" or leave the gap.'
                  : 'Could not import ${mediaAssetDefaultName(path)}.',
            );
          }
        }
      }
    } on Object catch (error) {
      warnings.add('$error');
    }
    if (!mounted) {
      return;
    }
    if (imported > 0 && warnings.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _running = false;
      // What SUCCEEDED leaves the list — pressing Import again after
      // fixing a problem must never duplicate what already landed. A
      // TVPaint export is not IN that list (it replaced it), so it is
      // released here or a second Enter lands the cut twice — and the
      // camera warning keeps this window open often enough for that to
      // be reachable.
      _files.removeWhere(done.contains);
      if (_tvpJsonPath != null && done.contains(_tvpJsonPath)) {
        _tvpJsonPath = null;
        _tvpJson = null;
      }
      _status = warnings.isEmpty
          ? 'Nothing imported.'
          : warnings.take(3).join(' · ');
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppWindow(
      windowKey: const ValueKey<String>('import-dialog'),
      title: 'Import / Place',
      titleIcon: Icons.download_outlined,
      width: 760,
      height: 520,
      scrollBody: false,
      bodyPadding: EdgeInsets.zero,
      onClose: _running ? null : () => Navigator.of(context).pop(),
      footerNote: _status.isEmpty
          ? null
          : Text(
              _status,
              key: const ValueKey<String>('import-status'),
              style: Theme.of(context).textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
      actions: [
        AppWindowAction(
          label: 'Cancel',
          actionKey: const ValueKey<String>('import-cancel-button'),
          emphasis: AppWindowActionEmphasis.quiet,
          onPressed: _running ? null : () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: 'Import',
          actionKey: const ValueKey<String>('import-run-button'),
          onPressed: _canImport ? () => _runImport() : null,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sourceBar(context),
          const Divider(height: 1),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _interpretationTable(context)),
                const VerticalDivider(width: 1),
                SizedBox(width: 272, child: _settingsColumn(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceBar(BuildContext context) {
    final theme = Theme.of(context);
    final label = _tvpJsonPath != null
        ? _tvpJsonPath!
        : _folder != null
        ? _folder!
        : _files.isEmpty
        ? 'No source selected'
        : _files.length == 1
        ? _files.single
        : '${_files.length} files';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const ValueKey<String>('import-browse-files-button'),
            onPressed: _running ? null : _pickFiles,
            child: const Text('Files…'),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            key: const ValueKey<String>('import-browse-folder-button'),
            onPressed: _running ? null : _pickFolder,
            child: const Text('Cut folder…'),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            key: const ValueKey<String>('import-browse-tvpaint-button'),
            onPressed: _running ? null : _pickTvpExport,
            child: const Text('TVPaint export…'),
          ),
        ],
      ),
    );
  }

  Widget _interpretationTable(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    void addRow(String leading, String body, {bool dim = false}) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 86,
                child: Text(
                  leading,
                  style: theme.textTheme.labelSmall!.copyWith(
                    color: dim
                        ? theme.colorScheme.outline
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  body,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: dim ? theme.colorScheme.outline : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final tvp = _tvpJson;
    final parsed = _parsed;
    if (tvp != null) {
      addRow(
        'Clip',
        '${tvp.clipName} · ${tvp.width}×${tvp.height} · ${tvp.frameCount} '
            'frames · ${tvp.frameRate.toStringAsFixed(tvp.frameRate.truncateToDouble() == tvp.frameRate ? 0 : 3)}fps',
      );
      // Top-first, the way the layer panel reads — the parse hands them
      // over bottom-first because that is what the cut wants.
      for (final layer in tvp.layers.reversed) {
        final edges = [
          if (layer.preBehavior != TvpEdgeBehavior.none)
            'pre ${layer.preBehavior.name}',
          if (layer.postBehavior != TvpEdgeBehavior.none)
            'post ${layer.postBehavior.name}',
        ];
        addRow(
          'Layer ${layer.position}',
          '${layer.name} — ${layer.instances.length} drawing(s), '
              '${layer.blocks.length} exposure(s)'
              '${edges.isEmpty ? '' : ' · ${edges.join(', ')}'}'
              '${layer.visible ? '' : ' · hidden'}',
          dim: !layer.visible,
        );
      }
      addRow(
        'Camera',
        'shoots ${tvp.camera.width}×${tvp.camera.height}'
            '${tvp.camera.isAnimated ? ', ${tvp.camera.positions.length} '
                  'baked frames' : ', still'}',
        dim: !tvp.camera.isAnimated,
      );
      for (final warning in tvp.warnings) {
        addRow('⚠', warning);
      }
    } else if (parsed != null) {
      addRow(
        'Cut',
        parsed.cutNumbers.isEmpty
            ? parsed.folderName
            : parsed.cutNumbers.join(' · ') +
                  (parsed.cutNumbers.length > 1 ? '  (겸용)' : ''),
      );
      if (parsed.processTokens.isNotEmpty) {
        addRow('Process', parsed.processTokens.join(' + '));
      }
      for (final layer in parsed.layers) {
        addRow(
          'Layer ${layer.symbol}',
          '${layer.cells.length} cels '
              '(${layer.cells.map((c) => c.label).join(', ')})',
        );
      }
      for (final picture in parsed.pictures) {
        addRow('Picture', picture.name);
      }
      for (final group in parsed.processGroups) {
        addRow(
          'Process ${group.process}',
          [
            for (final layer in group.layers)
              '${layer.symbol}: ${layer.cells.length}',
          ].join(' · '),
        );
      }
      for (final reference in parsed.references) {
        addRow('Reference', reference.file, dim: true);
      }
      for (final exclusion in parsed.excluded) {
        addRow('Excluded', '${exclusion.path} — ${exclusion.reason}',
            dim: true);
      }
      for (final warning in parsed.warnings) {
        addRow('⚠', warning);
      }
    } else if (_files.isNotEmpty) {
      for (final path in _files) {
        final kind = mediaAssetKindForPath(path);
        final unplaceable = kind != null && _unplaceableKinds.contains(kind);
        addRow(
          kind?.jsonValue ?? 'file',
          unplaceable
              ? '${mediaAssetDefaultName(path)} — placement not available yet'
              : mediaAssetDefaultName(path),
          dim: kind == null || unplaceable,
        );
      }
    } else {
      addRow(
        '',
        'Pick files or a cut folder to see the interpretation.',
        dim: true,
      );
    }
    for (final ignored in _ignoredSources) {
      addRow('Ignored', mediaAssetDefaultName(ignored), dim: true);
    }

    return ListView(
      key: const ValueKey<String>('import-interpretation-table'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: rows,
    );
  }

  Widget _settingsColumn(BuildContext context) {
    final isFolder = _folder != null;
    final isTvp = _tvpJson != null;
    // Both of these land a whole CUT rather than placing a file, so the
    // destination and rasterize knobs have nothing to decide.
    final landsWholeCut = isFolder || isTvp;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!landsWholeCut) ...[
            ExportModuleRow(
              label: 'Place as',
              child: Wrap(
                spacing: 4,
                children: [
                  ExportChip(
                    key: const ValueKey<String>('import-destination-layer'),
                    label: 'Layer in cut',
                    selected: _destination == ImportDestination.activeCutLayer,
                    // A gap has no cut to place into (UI-R9 #3).
                    onTap: widget.session.activeCutOrNull == null
                        ? null
                        : () => setState(
                            () =>
                                _destination =
                                    ImportDestination.activeCutLayer,
                          ),
                  ),
                  ExportChip(
                    key: const ValueKey<String>('import-destination-cut'),
                    label: 'New cut',
                    selected: _destination == ImportDestination.newCut,
                    onTap: () => setState(
                      () => _destination = ImportDestination.newCut,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ExportToggleRow(
              key: const ValueKey<String>('import-rasterize-toggle'),
              label: 'Rasterize (bake pixels)',
              value: _rasterize,
              onChanged: (value) => setState(() => _rasterize = value),
            ),
            Text(
              _rasterize
                  ? 'Pixels absorb into cels; nothing registers.'
                  : 'Keeps the source linked and registers it in the media '
                        'browser.',
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 6),
          ] else ...[
            if (isTvp) ...[
              // One destination today, shown rather than hidden: the row
              // is where "into the cut I am in" joins it later, and an
              // absent control cannot say that it is coming.
              ExportModuleRow(
                label: 'Place as',
                child: Wrap(
                  spacing: 4,
                  children: [
                    ExportChip(
                      key: const ValueKey<String>('import-destination-cut'),
                      label: 'New cut',
                      selected: true,
                      onTap: () => setState(
                        () => _destination = ImportDestination.newCut,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
            // §6-z22: a cut folder's cels are what you draw on next, so
            // the folder import always bakes — no toggle to mislead. A
            // TVPaint export is the same shape.
            Text(
              isTvp
                  ? 'A TVPaint export always bakes its cels. Export it with '
                        '「빈 사진 포함」 on — with it off, TVPaint omits every '
                        'instance with no pixels, and their labels and '
                        'timing come through empty.'
                  : 'Cut folders always bake their cels; scans and movies '
                        'stay references.',
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 6),
          ],
          // Fit has nothing to decide for a TVPaint export: the cut is
          // born at the clip's size and every exported image IS that
          // size, so all three modes compute the same rect. The import
          // passes 1:1, which copies bytes instead of resampling them.
          if (!isTvp)
            ExportModuleRow(
              label: 'Fit',
              child: Wrap(
                spacing: 4,
                children: [
                  for (final fit in MediaFitMode.values)
                    ExportChip(
                      key: ValueKey<String>('import-fit-${fit.jsonValue}'),
                      label: switch (fit) {
                        MediaFitMode.stretch => 'Stretch',
                        MediaFitMode.contain => 'Keep aspect',
                        MediaFitMode.none => '1:1',
                      },
                      selected: _fit == fit,
                      onTap: () => setState(() => _fit = fit),
                    ),
                ],
              ),
            ),
          if (isFolder) ...[
            const SizedBox(height: 10),
            ExportToggleRow(
              key: const ValueKey<String>('import-subfolders-toggle'),
              label: 'Archived processes (LO/, GEN/…)',
              value: _parseConfig.includeProcessSubfolders,
              onChanged: (value) => setState(() {
                _parseConfig = _parseConfig.copyWith(
                  includeProcessSubfolders: value,
                );
                _reparseFolder(rescan: false);
              }),
            ),
            ExportToggleRow(
              key: const ValueKey<String>('import-multicut-toggle'),
              label: 'Multi-cut folders (겸용)',
              value: _parseConfig.multiCutFolders,
              onChanged: (value) => setState(() {
                _parseConfig = _parseConfig.copyWith(multiCutFolders: value);
                _reparseFolder(rescan: false);
              }),
            ),
            ExportModuleRow(
              label: 'Revisions',
              child: Wrap(
                spacing: 4,
                children: [
                  for (final policy in CelRevisionPolicy.values)
                    ExportChip(
                      key: ValueKey<String>(
                        'import-revision-${policy.jsonValue}',
                      ),
                      label: switch (policy) {
                        CelRevisionPolicy.latestOnly => 'Latest',
                        CelRevisionPolicy.all => 'All',
                        CelRevisionPolicy.originalOnly => 'Originals',
                      },
                      selected: _parseConfig.revisionPolicy == policy,
                      onTap: () => setState(() {
                        _parseConfig = _parseConfig.copyWith(
                          revisionPolicy: policy,
                        );
                        _reparseFolder(rescan: false);
                      }),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
