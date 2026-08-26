import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/import/cut_folder_parse.dart';
import '../../models/import/tvp_json_parse.dart';
import '../../models/media_asset.dart';
import '../../services/import/media_import_planner.dart';
import '../../services/pdf/pdf_render_service.dart';
import '../../services/persistence/file_type_groups.dart';
import '../../services/project_lookup.dart'
    show largeCarriedAssetBytes;
import '../../services/persistence/folder_grant.dart' show FolderGrant;
import '../dialogs/folder_pick_flow.dart';
import '../editor_session_manager.dart';
import '../export/export_settings_modules.dart';
import 'import_file_settings.dart';
import 'import_file_table.dart';
import 'import_preview.dart';
import '../text/byte_size_label.dart';
import '../widgets/app_window.dart';
import '../widgets/dock_edge_splitter.dart';

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
    this.poolOnly = false,
    this.placeOnly = false,
    this.filePicker,
    this.directoryPicker,
  });

  final EditorSessionManager session;

  /// Sources handed in by drag-and-drop (files or one folder).
  final List<String> initialPaths;

  /// Opened from the media browser, whose job is to REGISTER a file for
  /// later rather than place it now — so the destination starts on the
  /// pool. Only the starting point differs: the other destinations are
  /// still there, which is what makes this one window instead of two.
  final bool poolOnly;

  /// Opened from a pool ROW: the source is decided, so the source bar is
  /// gone and the window is called what it is doing. Everything else —
  /// the columns, the preview, the range — is the import window's, because
  /// placing an asset asks the same questions as bringing one in.
  final bool placeOnly;

  /// Injectable pickers (tests).
  final Future<List<String>> Function()? filePicker;
  final Future<String?> Function()? directoryPicker;

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  final List<String> _files = [];
  String? _folder;
  /// Where the import lands, or null for the MEDIA POOL — registered and
  /// nothing else.
  ///
  /// Null rather than a third [ImportDestination]: the planner's enum
  /// answers "where does this placement go", and registering without
  /// placing is not a place. A value there would be one every switch over
  /// the enum had to learn to ignore.
  ImportDestination? _destination = ImportDestination.activeCutLayer;

  /// Whether a placement is being planned at all — the window's ONE
  /// remaining batch-wide answer, and the reason it sits alone at the top:
  /// every other question changes meaning depending on it.
  bool get _placing => _destination != null;

  /// One answer set per FILE. The window used to hold one for the whole
  /// batch and be wrong about at least one file most of the time.
  final Map<String, ImportFileSettings> _settings = {};

  /// Rows a cell press speaks for. Empty means "the row you pressed".
  final Set<String> _selected = {};

  /// How wide the list is; the splitter moves it and the window remembers
  /// it for as long as it is open.
  double _tableWidth = 420;

  ImportFileSettings _settingsFor(String path) {
    final kind = mediaAssetKindForPath(path);
    return resolvedImportSettings(
      // Untouched rows answer with their KIND's default — a movie starts
      // as a reference. Seeding here rather than in the constructor keeps
      // "what this kind does by default" one fact in one place.
      _settings[path] ?? ImportFileSettings(mode: defaultImportMode(kind)),
      kind: kind,
      isPsd: importPathIsPsd(path),
      placing: _placing,
    );
  }

  void _setSettings(
    Iterable<String> paths,
    ImportFileSettings Function(ImportFileSettings) change,
  ) {
    setState(() {
      for (final path in paths) {
        _settings[path] = change(
          _settings[path] ?? const ImportFileSettings(),
        );
      }
    });
  }

  bool _rasterize = false;

  /// Whether the project CARRIES these files or points at them where they
  /// are. Carrying is the default now, on every platform.
  ///
  /// It was Reference, for a reason that has since been answered: the pool
  /// copied whatever it was handed, so dropping a 3GB 참고영상 meant a 3GB
  /// copy the user never asked for and could not decline. The KIND rule
  /// settles that case on its own — video is never carried, whatever this
  /// says — so the default no longer has to protect against it.
  ///
  /// What is left is which failure a person meets by not choosing. A
  /// reference dies when the original moves, and a project that has to be
  /// mailed with a folder beside it is the shape Pencil2D abandoned after
  /// its users kept sending the file alone. Apple already started here
  /// because a recorded path there stops working at the next launch; the
  /// rest follows, now that carrying costs bytes inside a ZIP rather than
  /// a second copy on disk.
  ///
  /// Reference stays one click away, for an original shared with another
  /// tool — that is a deliberate choice, which is exactly what it should
  /// be.
  bool _copyIntoProject = true;
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

  /// One stat per file for the size warning, kept because `build` asks and
  /// `build` runs on every chip tap.
  final Map<String, int> _fileSizes = {};

  @override
  void initState() {
    super.initState();
    if (widget.poolOnly) {
      _destination = null;
    }
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

  /// What the picker granted for the files in [_files], kept until Import
  /// runs so the session can record it.
  ///
  /// 🚨 The whole point of PICK-5 arrives here. On Apple a referenced path
  /// is refused after a relaunch unless the app kept the security-scoped
  /// token, and the token exists only for as long as this window holds it
  /// — nothing else in the app ever sees the picker's answer.
  final List<FolderGrant> _pickedGrants = [];

  Future<void> _pickFiles() async {
    // The injected picker (tests, and the drop path) answers in paths; the
    // real one answers in grants. Both end up in `_files`, and only the
    // real one has tokens to record.
    // 🚨 Nothing is replaced until the pick is known to have produced
    // something. A second pick that the user CANCELS returns empty and
    // leaves `_files` alone — so clearing the tokens first would strand
    // the first batch's files with no grants, and the reference they were
    // imported as would be refused at the next launch.
    final List<String> paths;
    final List<FolderGrant> grants;
    final injected = widget.filePicker;
    if (injected != null) {
      paths = await injected();
      grants = const [];
    } else {
      grants = await pickFileGrantsForUser(
        context,
        // The POOL group, not the placeable one: this window is the
        // media browser's entrance now, and the browser registers
        // movies it cannot yet place. A movie picked while a placing
        // destination is selected is refused BY NAME in the table
        // below — which is the honest version of a picker that simply
        // did not list it.
        acceptedTypeGroups: const [FileTypeGroups.poolMedia],
        allowMultiple: true,
      );
      paths = [for (final grant in grants) ?grant.path];
    }
    if (paths.isEmpty || !mounted) {
      return;
    }
    setState(() {
      _folder = null;
      _parsed = null;
      _files
        ..clear()
        ..addAll(paths);
      _pickedGrants
        ..clear()
        ..addAll(grants);
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
    // Before anything registers: the session has to be holding the tokens
    // by the time a save writes them down, and this is the only moment
    // they exist outside the picker. Harmless when the list is empty,
    // which is every desktop import and every drop.
    session.rememberMediaGrants(_pickedGrants);
    var imported = 0;
    final warnings = <String>[];
    final done = <String>[];
    try {
      final folder = _folder;
      final tvpJsonPath = _tvpJsonPath;
      final destination = _destination;
      if (tvpJsonPath != null) {
        // 1:1 always — see the Fit note in the settings column.
        // A TVPaint export registers no pool asset of its own — its
        // drawings become cels — so it has no copy-or-reference to make.
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
          copyIntoProject: _copyIntoProject,
        );
        if (folderWarnings == null) {
          warnings.add('Could not read that folder.');
        } else {
          imported += 1;
          warnings.addAll(folderWarnings);
        }
      } else if (destination == null) {
        // The pool: every kind registers, movies included. Two batches
        // rather than one, because carrying is now a per-file answer and
        // the registration verb takes one flag for the batch it is given.
        imported += _registerBatches(session, _files);
        done.addAll(_files);
      } else {
        // Audio registers rather than places, and does it in as few undos
        // as the per-file answers allow.
        final audioPaths = [
          for (final path in _files)
            if (mediaAssetKindForPath(path) == MediaAssetKind.audio) path,
        ];
        if (audioPaths.isNotEmpty) {
          imported += _registerBatches(session, audioPaths);
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
          final settings = _settingsFor(path);
          final carry = settings.mode == ImportFileMode.keepInside;
          final bake = settings.mode == ImportFileMode.rasterize;
          final failedPages = <int>[];
          final bool ok;
          try {
            ok = importPathIsPsd(path) && settings.psd == PsdPlaceMode.expand
                ? await _expandPsd(session, path, settings, warnings)
                : kind == MediaAssetKind.pdf
                ? await session.importPdfFile(
                    path: path,
                    destination: settings.into,
                    rasterize: bake,
                    fit: settings.fit,
                    copyIntoProject: carry,
                    inFrame: settings.inFrame,
                    outFrame: settings.outFrame,
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
                    destination: settings.into,
                    rasterize: bake,
                    fit: settings.fit,
                    copyIntoProject: carry,
                    inFrame: settings.inFrame,
                    outFrame: settings.outFrame,
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
                  : settings.into == ImportDestination.activeCutLayer &&
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

  /// Registers [paths] in as few undo steps as their answers allow: one
  /// batch for the carried, one for the referenced.
  int _registerBatches(EditorSessionManager session, List<String> paths) {
    var count = 0;
    for (final carry in const [true, false]) {
      final batch = [
        for (final path in paths)
          if ((_settingsFor(path).mode == ImportFileMode.keepInside) == carry)
            path,
      ];
      if (batch.isEmpty) {
        continue;
      }
      session.importMediaFiles(batch, copyIntoProject: carry);
      count += batch.length;
    }
    return count;
  }

  /// EXPAND, which reports its outcome as warnings-or-null rather than a
  /// bool: a flattened PSD has no stack, and that is not a failure worth
  /// the word "could not".
  Future<bool> _expandPsd(
    EditorSessionManager session,
    String path,
    ImportFileSettings settings,
    List<String> warnings,
  ) async {
    final expanded = await session.importPsdExpanded(
      path: path,
      destination: settings.into,
      fit: settings.fit,
    );
    if (expanded == null) {
      warnings.add(
        '${mediaAssetDefaultName(path)}: no layers to expand — import it '
        'merged instead.',
      );
      return false;
    }
    warnings.addAll(expanded);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AppWindow(
      windowKey: const ValueKey<String>('import-dialog'),
      // The file's name goes in the TITLE in place mode: the window is
      // about one file, and the strip below already owns the word "Place"
      // for the question it asks.
      title: widget.placeOnly && _files.isNotEmpty
          ? 'Place — ${mediaAssetDefaultName(_files.first)}'
          : 'Import',
      titleIcon: Icons.download_outlined,
      width: 760,
      height: 520,
      scrollBody: false,
      bodyPadding: EdgeInsets.zero,
      onClose: _running ? null : () => Navigator.of(context).pop(),
      // The size warning moved down here with the settings column: what
      // travels inside the project file is now the sum of per-row answers,
      // so it belongs where the window speaks about the batch.
      footerNote:
          _status.isEmpty &&
              _largeCarriedPaths().isEmpty &&
              _unplaceablePaths().isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_status.isNotEmpty)
                  Text(
                    _status,
                    key: const ValueKey<String>('import-status'),
                    style: Theme.of(context).textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                _unplaceableNote(context),
                _largeCarriedNote(context),
              ],
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
          if (!widget.placeOnly) ...[
            _sourceBar(context),
            const Divider(height: 1),
          ],
          _placeStrip(context),
          const Divider(height: 1),
          // Loose files answer per row; a cut folder and a TVPaint export
          // land a whole CUT and have nothing per-file to answer, so they
          // keep the interpretation list and the knobs that read it.
          Expanded(
            child: _files.isNotEmpty
                ? _twoZones(context)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _interpretationTable(context)),
                      if (_folder != null || _tvpJson != null) ...[
                        const VerticalDivider(width: 1),
                        SizedBox(width: 272, child: _settingsColumn(context)),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// The one batch-wide answer, and the only one that changes what the
  /// other questions mean — so it sits above them rather than among them.
  ///
  /// Opened from the media browser it is pinned to the pool: registering
  /// for later is what that panel is for, and a disabled chip says the
  /// other door exists rather than hiding it.
  Widget _placeStrip(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              'Place',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ExportChip(
            key: const ValueKey<String>('import-place-pool'),
            label: 'Pool',
            selected: !_placing,
            onTap: _running
                ? null
                : () => setState(() => _destination = null),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: widget.poolOnly
                ? 'The media browser registers; place from the timeline.'
                : '',
            child: ExportChip(
              key: const ValueKey<String>('import-place-timeline'),
              label: 'Timeline',
              selected: _placing,
              onTap: _running || widget.poolOnly
                  ? null
                  : () => setState(
                      () => _destination = ImportDestination.activeCutLayer,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// The list and the picture, with a grip between them.
  ///
  /// The split is draggable because the two halves are wanted in different
  /// amounts by different work: eight option columns want the room when a
  /// batch is being set up, and the picture wants it when one file is being
  /// looked at.
  Widget _twoZones(BuildContext context) {
    final previewPath = _selected.isNotEmpty
        ? _selected.last
        : (_files.isEmpty ? null : _files.first);
    final settings = previewPath == null
        ? const ImportFileSettings()
        : _settingsFor(previewPath);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxTable = constraints.maxWidth - 200;
        final tableWidth = _tableWidth.clamp(
          240.0,
          maxTable < 240 ? 240.0 : maxTable,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: tableWidth, child: _fileTable(context)),
            DockEdgeSplitter(
              axis: Axis.horizontal,
              tooltip: 'Resize',
              onDragDelta: (delta) {
                setState(() => _tableWidth = tableWidth + delta);
                return delta;
              },
            ),
            Expanded(
              child: ImportPreview(
                key: const ValueKey<String>('import-preview'),
                path: previewPath,
                inFrame: settings.inFrame,
                outFrame: settings.outFrame,
                // Trimming a REGISTRATION would have to write the trimmed
                // bytes, and there is no trimmer yet — so the ends only
                // appear where they already act: on what gets placed.
                rangeEditable: _placing,
                onRangeChanged: (start, end) {
                  if (previewPath == null) {
                    return;
                  }
                  _setSettings(
                    [previewPath],
                    (current) => current.copyWith(
                      inFrame: start,
                      outFrame: end,
                      clearOut: end == null,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// One row per file, one column per question (§3 of the round).
  Widget _fileTable(BuildContext context) {
    final placing = _placing;
    return ImportFileTable(
      key: const ValueKey<String>('import-file-table'),
      enabled: !_running,
      selected: _selected,
      onRowTap: (path) => setState(() {
        if (!_selected.remove(path)) {
          _selected.add(path);
        }
      }),
      rows: [
        for (final path in _files)
          ImportFileRow(
            path: path,
            name: mediaAssetDefaultName(path),
            modified: _modifiedOf(path),
            size: byteSizeLabel(_sizeOf(path)),
          ),
      ],
      columns: [
        ImportColumn<Object?>(
          label: 'File',
          width: 62,
          values: ImportFileMode.values,
          labelOf: (value) => importModeLabel(value! as ImportFileMode),
          valueOf: (path) => _settingsFor(path).mode,
          appliesTo: (path) => true,
          enabledFor: (path, value) => importModeAllowed(
            kind: mediaAssetKindForPath(path),
            mode: value! as ImportFileMode,
            psdExpanding: importPathIsPsd(path) &&
                placing &&
                _settingsFor(path).psd == PsdPlaceMode.expand,
            placing: placing,
            trimmed: _settingsFor(path).isTrimmed,
          ),
          onPick: (paths, value) => _setSettings(
            paths,
            (settings) => settings.copyWith(mode: value! as ImportFileMode),
          ),
        ),
        ImportColumn<Object?>(
          label: 'Into',
          width: 68,
          values: ImportDestination.values,
          labelOf: (value) => importIntoLabel(value! as ImportDestination),
          valueOf: (path) => _settingsFor(path).into,
          // A pool registration is not a placement, and a movie has no
          // placement to plan yet.
          appliesTo: (path) =>
              placing &&
              !_unplaceableKinds.contains(mediaAssetKindForPath(path)) &&
              mediaAssetKindForPath(path) != MediaAssetKind.audio,
          enabledFor: (path, value) =>
              value != ImportDestination.activeCutLayer ||
              widget.session.activeCutOrNull != null,
          onPick: (paths, value) => _setSettings(
            paths,
            (settings) =>
                settings.copyWith(into: value! as ImportDestination),
          ),
        ),
        ImportColumn<Object?>(
          label: 'Fit',
          width: 62,
          values: MediaFitMode.values,
          labelOf: (value) => importFitLabel(value! as MediaFitMode),
          valueOf: (path) => _settingsFor(path).fit,
          appliesTo: (path) =>
              placing && mediaAssetKindForPath(path) != MediaAssetKind.audio,
          enabledFor: (path, value) => true,
          onPick: (paths, value) => _setSettings(
            paths,
            (settings) => settings.copyWith(fit: value! as MediaFitMode),
          ),
        ),
        ImportColumn<Object?>(
          label: 'PSD',
          width: 66,
          values: PsdPlaceMode.values,
          labelOf: (value) =>
              (value! as PsdPlaceMode) == PsdPlaceMode.merge
              ? 'Merge'
              : 'Expand',
          valueOf: (path) => _settingsFor(path).psd,
          appliesTo: (path) => placing && importPathIsPsd(path),
          enabledFor: (path, value) => true,
          onPick: (paths, value) => _setSettings(
            paths,
            (settings) => settings.copyWith(psd: value! as PsdPlaceMode),
          ),
        ),
      ],
    );
  }

  /// Files this window cannot place — a movie, until there is a decoder.
  ///
  /// Their Into cell shows a dash, which says the question does not apply
  /// but not WHY. The row cannot carry the reason without becoming a
  /// paragraph, so the reason sits in the footer and names them.
  List<String> _unplaceablePaths() {
    if (!_placing) {
      return const [];
    }
    return [
      for (final path in _files)
        if (_unplaceableKinds.contains(mediaAssetKindForPath(path))) path,
    ];
  }

  Widget _unplaceableNote(BuildContext context) {
    final paths = _unplaceablePaths();
    if (paths.isEmpty) {
      return const SizedBox.shrink();
    }
    final named = paths.map(mediaAssetDefaultName).take(3).join(', ');
    final more = paths.length > 3 ? ' and ${paths.length - 3} more' : '';
    return Text(
      '$named$more: placement not available yet — register instead.',
      key: const ValueKey<String>('import-unplaceable-note'),
      style: Theme.of(context).textTheme.labelSmall,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// `MM-DD`, which is what a row has space for and what a person scanning
  /// a folder of today's work is actually reading.
  String _modifiedOf(String path) {
    try {
      final stamp = File(path).lastModifiedSync();
      return '${stamp.month.toString().padLeft(2, '0')}-'
          '${stamp.day.toString().padLeft(2, '0')}';
    } on Object {
      return '';
    }
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
        // Only a PLACEMENT can be refused for its kind. Registering a
        // movie in the pool is exactly what the media browser has always
        // done, so pool-bound rows read as ordinary ones.
        final unplaceable =
            kind != null &&
            _destination != null &&
            _unplaceableKinds.contains(kind);
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

  int _sizeOf(String path) => _fileSizes.putIfAbsent(path, () {
    try {
      return File(path).lengthSync();
    } on Object {
      return 0; // Unreadable: the import degrades, and so does its warning.
    }
  });

  /// Every path this import would REGISTER — the loose files, or the
  /// reference rows a cut folder brings with it. Baked cels are not here:
  /// their pixels become `.celz` and the file itself is not carried.
  List<String> _registeredPaths() {
    final folder = _folder;
    if (folder == null) {
      return _files;
    }
    final parsed = _parsed;
    if (parsed == null) {
      return const [];
    }
    return [
      for (final reference in parsed.references) '$folder/${reference.file}',
    ];
  }

  /// The files big enough that carrying them should be said out loud.
  ///
  /// Only ones that WOULD be carried. The kind ceiling means a movie is
  /// never in here however the chips are set, and warning about a file
  /// that was always going to stay outside is the noise that teaches
  /// people to ignore the real warning.
  List<String> _largeCarriedPaths() {
    // Loose files answer one at a time now, so the question is per row:
    // which of them are big AND set to travel inside the project file.
    if (_files.isNotEmpty) {
      return [
        for (final path in _files)
          // Every kind can be carried now, so a big MOVIE warns too — which
          // is the point: the ceiling that used to refuse it silently is
          // gone, and this sentence is what took its place.
          if (_settingsFor(path).mode == ImportFileMode.keepInside &&
              _sizeOf(path) >= largeCarriedAssetBytes)
            path,
      ];
    }
    if (!_copyIntoProject) {
      return const [];
    }
    return [
      for (final path in _registeredPaths())
        if (_sizeOf(path) > largeCarriedAssetBytes)
          path,
    ];
  }

  /// Says what carrying is about to cost, before it costs it.
  ///
  /// Apple's default is Keep inside and the toggle is one click away, so
  /// the size someone did not intend to take on is the one they find out
  /// about at the next sync. It leads with the TOTAL because that is the
  /// number being decided, and it names the files because that is what
  /// the answer acts on.
  Widget _largeCarriedNote(BuildContext context) {
    final large = _largeCarriedPaths();
    if (large.isEmpty) {
      return const SizedBox.shrink();
    }
    final total = large.fold<int>(0, (sum, path) => sum + _sizeOf(path));
    final named = [
      for (final path in large.take(3))
        '${mediaAssetDefaultName(path)} (${byteSizeLabel(_sizeOf(path))})',
    ].join(', ');
    final more = large.length > 3 ? ' and ${large.length - 3} more' : '';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '${byteSizeLabel(total)} goes inside the project file — $named$more. '
        'Reference leaves the originals where they are.',
        key: const ValueKey<String>('import-large-carry-note'),
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
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
          // Copy-or-reference applies wherever a file is REGISTERED: the
          // loose files, and the reference rows a cut folder brings with
          // it. A TVPaint export registers nothing of its own — its
          // drawings become cels — so it has nothing to decide here.
          //
          // Two chips rather than a switch: this is one-of-two named
          // states, and in this app a choice is shown by colour while a
          // checkbox means on/off.
          if (!isTvp) ...[
            ExportModuleRow(
              label: 'Files',
              child: Wrap(
                spacing: 4,
                children: [
                  ExportChip(
                    key: const ValueKey<String>('import-media-reference'),
                    label: 'Reference',
                    selected: !_copyIntoProject,
                    onTap: () => setState(() => _copyIntoProject = false),
                  ),
                  ExportChip(
                    key: const ValueKey<String>('import-media-copy'),
                    label: 'Keep inside',
                    selected: _copyIntoProject,
                    onTap: () => setState(() => _copyIntoProject = true),
                  ),
                ],
              ),
            ),
            Text(
              _copyIntoProject
                  ? 'The project file holds these; the originals are left '
                        'alone.'
                  : 'The files stay where they are and the project points '
                        'at them.',
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            _largeCarriedNote(context),
            const SizedBox(height: 6),
          ],
          if (!landsWholeCut) ...[
            ExportModuleRow(
              label: 'Place as',
              child: Wrap(
                spacing: 4,
                children: [
                  // The media browser's own entrance, promoted into the
                  // window that every other import already came through.
                  // It is a destination like the others because from here
                  // the user can change their mind — which is the whole
                  // reason the browser stopped opening a bare OS picker.
                  ExportChip(
                    key: const ValueKey<String>('import-destination-pool'),
                    label: 'Media pool',
                    selected: _destination == null,
                    onTap: () => setState(() => _destination = null),
                  ),
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
            // Rasterize is a question about a PLACED layer — bake the
            // pixels into cels, or read the file. A pool registration
            // places nothing, so the row would be a control with no
            // effect, which is worse than an absent one.
            if (_destination != null) ...[
              ExportToggleRow(
                key: const ValueKey<String>('import-rasterize-toggle'),
                label: 'Rasterize (bake pixels)',
                value: _rasterize,
                onChanged: (value) => setState(() => _rasterize = value),
              ),
              Text(
                _rasterize
                    ? 'Pixels absorb into cels; nothing registers.'
                    // This used to read "keeps the source linked", which
                    // was the one thing this branch did NOT do — it copied
                    // the file in. Whether the source stays linked is the
                    // Files row's question now, and this one answers its
                    // own.
                    : 'Places a layer that reads the file, and registers it '
                          'in the media browser.',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(height: 6),
            ],
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
          // A pool registration has no rect at all — fit is a placement
          // default the asset picks up when it is later placed.
          if (!isTvp && (landsWholeCut || _destination != null))
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
