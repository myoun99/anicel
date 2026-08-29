import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../../models/import/cut_folder_parse.dart';
import '../../models/media_asset.dart';
import '../../services/import/media_import_planner.dart';
import '../../services/pdf/pdf_render_service.dart';
import '../../services/persistence/file_type_groups.dart';
import '../../services/project_lookup.dart'
    show largeCarriedAssetBytes;
import '../../services/persistence/folder_grant.dart'
    show FolderGrant, FolderPicker, MaterializeCancelled;
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
      _reparseFolder();
    }
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
        supportedExtensions: FileTypeGroups.poolMedia.extensions ?? const [],
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
      !_running && (_files.isNotEmpty || (_folder != null && _parsed != null));

  /// Kinds not placeable yet (video needs a decode engine): named
  /// honestly instead of failing as a decode. PDF left this set in R4.
  static const Set<MediaAssetKind> _unplaceableKinds = {
    MediaAssetKind.video,
  };

  /// True while the import is WAITING on somebody else's bytes rather
  /// than doing its own work — which is the only stretch of a run that
  /// can honestly be cancelled.
  bool _waitingForFile = false;
  bool _stopWaiting = false;

  /// The ONE law, applied where a picked file is about to be READ.
  ///
  /// ⚠️Registering media is a REFERENCE and stays untouched: forcing a
  /// download for a movie somebody only registered would be the app
  /// spending their line for them, for bytes it does not need. A
  /// placement reads, so a placement waits.
  ///
  /// Said in this window's own status line rather than behind the open
  /// door's progress window — this surface is already the thing telling
  /// the user what the import is doing, and a second window over it
  /// would be two answers to one question.
  ///
  /// ⛔The staged copy is refused here even though the materialiser can
  /// still produce one: an import names the asset after its file, so a
  /// temp name would land in the project as the drawing's name. Waiting
  /// for the PICK to read is the only outcome this door can use.
  /// Answers null when the file never arrives or the user stops it.
  Future<String?> _readableForImport(String path) async {
    setState(() {
      _waitingForFile = true;
      _stopWaiting = false;
    });
    try {
      final source = await FolderPicker.materializeOpenedFile(
        path,
        within: null,
        onWaiting: (waited) {
          if (!mounted) {
            return;
          }
          final seconds = waited.inSeconds;
          setState(() {
            _status =
                (waited >= const Duration(seconds: 10)
                        ? AppText.strings.openWaitingStalledTemplate
                        : AppText.strings.openWaitingCloudTemplate)
                    .replaceAll('{sec}', '$seconds');
          });
        },
        isCancelled: () => _stopWaiting,
      );
      if (source.staged) {
        unawaited(
          File(source.path).delete().then<void>((_) {}, onError: (_) {}),
        );
        return null;
      }
      return source.path;
    } on MaterializeCancelled {
      return null;
    } on FileSystemException {
      return null;
    } finally {
      if (mounted) {
        setState(() => _waitingForFile = false);
      }
    }
  }

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
      final destination = _destination;
      if (folder != null) {
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
          // A PLACEMENT reads the file, so this is where the picked path
          // has to become a path that reads — the same law the two open
          // doors go through. A cloud file arrives here as a placeholder
          // and would otherwise fail as if it were corrupt.
          if (await _readableForImport(path) == null) {
            warnings.add(
              '${mediaAssetDefaultName(path)}: 파일을 읽지 못했습니다.',
            );
            continue;
          }
          if (!mounted) {
            return;
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
      // fixing a problem must never duplicate what already landed.
      _files.removeWhere(done.contains);
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
          // Dead while the import is doing its OWN work — stopping a
          // half-written import would be the lie the progress window
          // refuses for saves. Alive again while it is WAITING on
          // somebody else's bytes: nothing has been applied to that file
          // yet, so letting go costs nothing.
          onPressed: _waitingForFile
              ? () => setState(() => _stopWaiting = true)
              : (_running ? null : () => Navigator.of(context).pop()),
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
                      if (_folder != null) ...[
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
    final label = _folder != null
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

    final parsed = _parsed;
    if (parsed != null) {
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
    // A cut folder lands a whole CUT rather than placing a file, so the
    // destination and rasterize knobs have nothing to decide.
    final landsWholeCut = isFolder;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Copy-or-reference applies wherever a file is REGISTERED: the
          // loose files, and the reference rows a cut folder brings with
          // it.
          //
          // Two chips rather than a switch: this is one-of-two named
          // states, and in this app a choice is shown by colour while a
          // checkbox means on/off.
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
            // §6-z22: a cut folder's cels are what you draw on next, so
            // the folder import always bakes — no toggle to mislead.
            Text(
              'Cut folders always bake their cels; scans and movies '
              'stay references.',
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 6),
          ],
          // A pool registration has no rect at all — fit is a placement
          // default the asset picks up when it is later placed.
          if (landsWholeCut || _destination != null)
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
