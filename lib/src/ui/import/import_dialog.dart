import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../../models/import/cut_folder_parse.dart';
import '../../services/import/cut_folder_listing.dart';
import '../../models/media_asset.dart';
import '../../services/import/media_import_planner.dart';
import '../../services/pdf/pdf_render_service.dart';
import '../../services/persistence/file_type_groups.dart';
import '../../services/project_lookup.dart' show largeCarriedAssetBytes;
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

  /// Opened from the media pool, whose job is to REGISTER a file for
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

/// What an import run has come to so far.
///
/// ⛔MUTABLE on purpose: a batch that throws part-way must keep what
/// already landed, and `done` is what gets removed from the list so that
/// pressing Import again never re-imports a file that succeeded.
class _ImportTally {
  int imported = 0;
  final List<String> warnings = [];
  final List<String> done = [];
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
        _settings[path] = change(_settings[path] ?? const ImportFileSettings());
      }
    });
  }

  /// Whether the project CARRIES these files or points at them where they
  /// are. Carrying is the default now, on every platform.
  ///
  /// It was Reference, for a reason that has since been answered: the pool
  /// copied whatever it was handed, so dropping a 3GB 참고영상 meant a 3GB
  /// copy the user never asked for and could not decline.
  ///
  /// 🚨This paragraph used to end「the KIND rule settles that case on its
  /// own — video is never carried, whatever this says」. That ceiling died
  /// 2026-08-14 and video carries like anything else; the kind only picks
  /// this toggle's STARTING position ([defaultImportMode]). What protects
  /// against the 3GB surprise now is the size note below and the toggle
  /// itself, both of which the person can see before pressing Import.
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
        // media pool's entrance now, and the browser registers
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
      try {
        // SYNCHRONOUS where the import door's walk is asynchronous: this
        // preview re-reads on every knob change and has to have its
        // answer inside the frame that turned the knob. The walk is each
        // caller's; what a listed entity MEANS is shared.
        _folderEntries = cutFolderEntriesFrom(
          folder,
          directory.listSync(recursive: true),
        );
      } on FileSystemException catch (error) {
        _parsed = null;
        _folderEntries = null;
        _status = 'Could not read the folder: ${error.message}';
        return;
      }
    }
    _parsed = parseCutFolderAt(
      folder,
      entries: _folderEntries!,
      config: _parseConfig,
    );
  }

  bool get _canImport =>
      !_running && (_files.isNotEmpty || (_folder != null && _parsed != null));

  /// Kinds not placeable yet (video needs a decode engine): named
  /// honestly instead of failing as a decode. PDF left this set in R4.
  static const Set<MediaAssetKind> _unplaceableKinds = {MediaAssetKind.video};

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
    // Before anything registers: the session has to be holding the tokens
    // by the time a save writes them down, and this is the only moment
    // they exist outside the picker. Harmless when the list is empty,
    // which is every desktop import and every drop.
    widget.session.mediaGrants.rememberMediaGrants(_pickedGrants);
    final tally = _ImportTally();
    if (!await _importAll(tally)) {
      return; // the dialog went away part-way through the batch
    }
    if (!mounted) {
      return;
    }
    if (tally.imported > 0 && tally.warnings.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _running = false;
      // What SUCCEEDED leaves the list — pressing Import again after
      // fixing a problem must never duplicate what already landed.
      _files.removeWhere(tally.done.contains);
      _status = tally.warnings.isEmpty
          ? 'Nothing imported.'
          : tally.warnings.take(3).join(' · ');
    });
  }

  /// Runs the picked import, whichever door it goes through. Answers
  /// FALSE when the dialog went away part-way.
  ///
  /// ⛔ONE catch for the whole run: a batch that throws part-way KEEPS
  /// what already landed (the tally fills as it goes) and the error
  /// becomes a warning, so the dialog says what happened rather than
  /// leaving a dead spinner behind an unhandled error.
  Future<bool> _importAll(_ImportTally tally) async {
    try {
      final folder = _folder;
      if (folder != null) {
        await _importCutFolder(folder, tally);
      } else if (_destination == null) {
        // The pool: every kind registers, movies included. Two batches
        // rather than one, because carrying is now a per-file answer and
        // the registration verb takes one flag for the batch it is given.
        tally.imported += _registerBatches(widget.session, _files);
        tally.done.addAll(_files);
      } else {
        // ⛔The `await` is NOT redundant: `return _placeFiles(tally)`
        // hands the future to the caller and this try never sees it
        // fail, so a throw part-way through the batch would escape as an
        // unhandled async error and leave the spinner running forever.
        return await _placeFiles(tally);
      }
    } on Object catch (error) {
      tally.warnings.add('$error');
    }
    return true;
  }

  Future<void> _importCutFolder(String folder, _ImportTally tally) async {
    final folderWarnings = await widget.session.cutFolderDoor.importCutFolder(
      folderPath: folder,
      config: _parseConfig,
      fit: _fit,
      copyIntoProject: _copyIntoProject,
    );
    if (folderWarnings == null) {
      tally.warnings.add('Could not read that folder.');
      return;
    }
    tally.imported += 1;
    tally.warnings.addAll(folderWarnings);
  }

  /// Places every picked file, audio first. Answers FALSE when the dialog
  /// went away part-way — the caller must not touch its state after that.
  Future<bool> _placeFiles(_ImportTally tally) async {
    // Audio registers rather than places, and does it in as few undos
    // as the per-file answers allow.
    final audioPaths = [
      for (final path in _files)
        if (mediaAssetKindForPath(path) == MediaAssetKind.audio) path,
    ];
    if (audioPaths.isNotEmpty) {
      tally.imported += _registerBatches(widget.session, audioPaths);
      tally.done.addAll(audioPaths);
    }
    for (final path in _files) {
      final kind = mediaAssetKindForPath(path);
      if (kind == MediaAssetKind.audio) {
        continue;
      }
      if (_unplaceableKinds.contains(kind)) {
        tally.warnings.add(
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
        tally.warnings.add('${mediaAssetDefaultName(path)}: 파일을 읽지 못했습니다.');
        continue;
      }
      if (!mounted) {
        return false;
      }
      await _placeOneFile(path, kind, tally);
    }
    return true;
  }

  /// One file through its door. ⛔A file that fails does NOT abort the
  /// batch: it leaves a named warning and the loop moves on (the image
  /// path's per-file contract).
  Future<void> _placeOneFile(
    String path,
    MediaAssetKind? kind,
    _ImportTally tally,
  ) async {
    final failedPages = <int>[];
    final bool ok;
    try {
      ok = await _placeThrough(path, kind, tally, failedPages);
    } on Object {
      tally.warnings.add(
        '${mediaAssetDefaultName(path)} could not be opened — '
        'corrupt or password-locked.',
      );
      return;
    }
    if (failedPages.isNotEmpty) {
      tally.warnings.add(
        '${mediaAssetDefaultName(path)}: ${failedPages.length} '
        'page(s) failed to render — their cels stay empty.',
      );
    }
    if (ok) {
      tally.imported += 1;
      tally.done.add(path);
      return;
    }
    tally.warnings.add(_placementFailure(path, kind, _settingsFor(path)));
  }

  /// Which door this file goes through: an expanded PSD, the PDF
  /// renderer, or the ordinary image path.
  Future<bool> _placeThrough(
    String path,
    MediaAssetKind? kind,
    _ImportTally tally,
    List<int> failedPages,
  ) {
    final settings = _settingsFor(path);
    final carry = settings.mode == ImportFileMode.keepInside;
    final bake = settings.mode == ImportFileMode.rasterize;
    if (importPathIsPsd(path) && settings.psd == PsdPlaceMode.expand) {
      return _expandPsd(widget.session, path, settings, tally.warnings);
    }
    if (kind == MediaAssetKind.pdf) {
      return widget.session.importDoors.importPdfFile(
        path: path,
        destination: settings.into,
        rasterize: bake,
        fit: settings.fit,
        copyIntoProject: carry,
        inFrame: settings.inFrame,
        outFrame: settings.outFrame,
        // A 100-page conte renders for seconds — the footer says where
        // it is instead of looking hung.
        onRenderProgress: (rendered, total) {
          if (mounted) {
            setState(() => _status = 'Rendering PDF page $rendered/$total…');
          }
        },
        onPageRenderFailed: failedPages.add,
      );
    }
    return widget.session.importDoors.importImageFile(
      path: path,
      destination: settings.into,
      rasterize: bake,
      fit: settings.fit,
      copyIntoProject: carry,
      inFrame: settings.inFrame,
      outFrame: settings.outFrame,
    );
  }

  /// Why a placement that ran and answered `false` did not land, most
  /// specific reason first: a build with no renderer, then a destination
  /// that is not there.
  String _placementFailure(
    String path,
    MediaAssetKind? kind,
    ImportFileSettings settings,
  ) {
    if (kind == MediaAssetKind.pdf && PdfRenderService.availability != true) {
      return '${mediaAssetDefaultName(path)}: no PDF renderer in this build.';
    }
    if (settings.into == ImportDestination.activeCutLayer &&
        widget.session.activeCutOrNull == null) {
      return 'No active cut — pick "New cut" or leave the gap.';
    }
    return 'Could not import ${mediaAssetDefaultName(path)}.';
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
      session.mediaPool.importMediaFiles(batch, copyIntoProject: carry);
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
    final expanded = await session.importDoors.importPsdExpanded(
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
          label: AppText.strings.commonCancel,
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
          label: AppText.strings.imImport,
          actionKey: const ValueKey<String>('import-run-button'),
          onPressed: _canImport ? _runImport : null,
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
  /// Opened from the media pool it is pinned to the pool: registering
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
          Flexible(
            child: ExportPillStrip(
              items: [
                ExportPillItem(
                  keyValue: 'import-place-pool',
                  label: AppText.strings.imPool,
                  selected: !_placing,
                  onTap: _running
                      ? null
                      : () => setState(() => _destination = null),
                ),
                ExportPillItem(
                  keyValue: 'import-place-timeline',
                  label: AppText.strings.panelTimeline,
                  selected: _placing,
                  onTap: _running || widget.poolOnly
                      ? null
                      : () => setState(
                          () => _destination = ImportDestination.activeCutLayer,
                        ),
                  tooltip: widget.poolOnly
                      ? 'The media pool registers; place from the timeline.'
                      : null,
                ),
              ],
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
              tooltip: AppText.strings.commonResize,
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
          label: AppText.strings.imFile,
          width: 62,
          values: ImportFileMode.values,
          labelOf: (value) => importModeLabel(value! as ImportFileMode),
          valueOf: (path) => _settingsFor(path).mode,
          appliesTo: (path) => true,
          enabledFor: (path, value) => importModeAllowed(
            kind: mediaAssetKindForPath(path),
            mode: value! as ImportFileMode,
            psdExpanding:
                importPathIsPsd(path) &&
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
          label: AppText.strings.imInto,
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
            (settings) => settings.copyWith(into: value! as ImportDestination),
          ),
        ),
        ImportColumn<Object?>(
          label: AppText.strings.imFit,
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
          labelOf: (value) => (value! as PsdPlaceMode) == PsdPlaceMode.merge
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
            child: Text(AppText.strings.imFilesButton),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            key: const ValueKey<String>('import-browse-folder-button'),
            onPressed: _running ? null : _pickFolder,
            child: Text(AppText.strings.imCutFolderButton),
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
        addRow(
          'Excluded',
          '${exclusion.path} — ${exclusion.reason}',
          dim: true,
        );
      }
      for (final warning in parsed.warnings) {
        addRow('⚠', warning);
      }
    } else if (_files.isNotEmpty) {
      for (final path in _files) {
        final kind = mediaAssetKindForPath(path);
        // Only a PLACEMENT can be refused for its kind. Registering a
        // movie in the pool is exactly what the media pool has always
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
  /// Only ones that WOULD be carried — warning about a file that is
  /// staying outside is the noise that teaches people to ignore the real
  /// warning.
  ///
  /// 🪦It used to say「the kind ceiling means a movie is never in here
  /// however the chips are set」. That ceiling died 2026-08-14: a movie
  /// STARTS on Reference and lands here the moment someone sets it to
  /// Keep inside — which is exactly when a 3GB warning is worth having.
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
        if (_sizeOf(path) > largeCarriedAssetBytes) path,
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
        'Carrying compresses each file as it comes in, so the project grows '
        'by less than that. Reference leaves the originals where they are.',
        key: const ValueKey<String>('import-large-carry-note'),
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }

  /// The FOLDER column. A cut folder lands a whole CUT rather than
  /// placing a file, and a loose file answers per ROW in the file table
  /// (2026-08-14, 「answers per file, not per batch」) — so this pane is
  /// built only when there is a folder, and every question in it is one a
  /// whole delivery answers at once.
  Widget _settingsColumn(BuildContext context) {
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
          ExportChoiceRow<bool>(
            label: AppText.strings.imFiles,
            keyPrefix: 'import-media',
            values: const [false, true],
            selected: _copyIntoProject,
            keyOf: (copy) => copy ? 'copy' : 'reference',
            labelOf: (copy) => copy ? 'Keep inside' : 'Reference',
            onSelect: (copy) => setState(() => _copyIntoProject = copy),
          ),
          // ⛔Not a new caption — this line already existed and already
          // switched with the choice. 유저 2026-08-30 asked for the
          // compression to be said out loud (「품기는 압축된 파일
          // 저장시키는거라고 문장 넣는게 좋을거같아」), and the sentence
          // that describes what Keep inside DOES is where it belongs.
          //
          // 🚨It also answers a question the size column would otherwise
          // raise: the media pool shows what an asset OCCUPIES, which
          // after carrying is smaller than the file that was imported.
          Text(
            _copyIntoProject
                ? 'The project file holds these, compressed; the originals '
                      'are left alone.'
                : 'The files stay where they are and the project points '
                      'at them.',
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          _largeCarriedNote(context),
          const SizedBox(height: 6),
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
          ExportChoiceRow<MediaFitMode>(
            label: AppText.strings.imFit,
            keyPrefix: 'import-fit',
            values: MediaFitMode.values,
            selected: _fit,
            keyOf: (fit) => fit.jsonValue,
            labelOf: (fit) => switch (fit) {
              MediaFitMode.stretch => 'Stretch',
              MediaFitMode.contain => 'Keep aspect',
              MediaFitMode.none => '1:1',
            },
            onSelect: (fit) => setState(() => _fit = fit),
          ),
          const SizedBox(height: 10),
          ExportToggleRow(
            key: const ValueKey<String>('import-subfolders-toggle'),
            label: AppText.strings.imArchivedProcesses,
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
            label: AppText.strings.imMultiCutFolders,
            value: _parseConfig.multiCutFolders,
            onChanged: (value) => setState(() {
              _parseConfig = _parseConfig.copyWith(multiCutFolders: value);
              _reparseFolder(rescan: false);
            }),
          ),
          ExportChoiceRow<CelRevisionPolicy>(
            label: AppText.strings.imRevisions,
            keyPrefix: 'import-revision',
            values: CelRevisionPolicy.values,
            selected: _parseConfig.revisionPolicy,
            keyOf: (policy) => policy.jsonValue,
            labelOf: (policy) => switch (policy) {
              CelRevisionPolicy.latestOnly => 'Latest',
              CelRevisionPolicy.all => 'All',
              CelRevisionPolicy.originalOnly => 'Originals',
            },
            onSelect: (policy) => setState(() {
              _parseConfig = _parseConfig.copyWith(revisionPolicy: policy);
              _reparseFolder(rescan: false);
            }),
          ),
        ],
      ),
    );
  }
}
