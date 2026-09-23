import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../../models/import/cut_folder_parse.dart';
import '../../services/import/cut_folder_listing.dart';
import '../../models/media_asset.dart';
import '../../services/import/import_layer_spot.dart';
import '../../services/import/media_import_planner.dart';
import '../../services/pdf/pdf_render_service.dart';
import '../../services/persistence/file_type_groups.dart';
import '../../services/persistence/folder_grant.dart'
    show FolderGrant, FolderPicker, MaterializeCancelled;
import '../dialogs/app_progress_dialog.dart';
import '../dialogs/folder_pick_flow.dart';
import '../editor_session_manager.dart';
import '../export/export_settings_modules.dart';
import 'import_file_settings.dart';
import 'import_file_table.dart';
import 'import_preview.dart';
import '../text/byte_size_label.dart';
import '../widgets/app_window.dart';
import '../widgets/dock_edge_splitter.dart';
import '../text/cloud_wait_line.dart';
import '../text/model_vocabulary.dart';

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
    this.spot,
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

  /// Where a DROP put the file ([ImportLayerSpot]). The drop answered it,
  /// so the Into column shows that answer locked instead of asking (유저
  /// 2026-09-11: 「드래그앤드롭으로 넣을곳 지정했으면 그거 따라서
  /// 고정해두고 비활성화된상태로」). Null for every entrance that is not a
  /// drop.
  final ImportLayerSpot? spot;

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

/// The Into answer a SOUND gives: the track's SE rows, by their own rule.
final class _SoundOnSeRows {
  const _SoundOnSeRows();
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

  /// How wide the list is once the splitter has moved it — null until then,
  /// which means 「wide enough for its columns and a readable name」.
  ///
  /// It was a fixed 420px, and the fixed columns took 368 of it: the name
  /// got 20px and did not show at all (유저 2026-09-11: 「이름은
  /// 표시도안되고. 제대로 효율좋게 하자」).
  double? _tableWidth;

  ImportFileSettings _settingsFor(String path) {
    final kind = mediaAssetKindForPath(path);
    final resolved = resolvedImportSettings(
      // Untouched rows answer with their seed ([_seed]) — without a movie's
      // sound on a picture row's frames.
      _settings[path] ?? _seed,
      kind: kind,
      isPsd: importPathIsPsd(path),
      placing: _placing,
      hasActiveCut: widget.session.activeCutOrNull != null,
      spot: widget.spot,
    );
    // A file the pool already holds has answered the pool's question: the
    // window does not ask it again, and no answer pressed here stands in
    // for the pool's (유저 2026-09-11, 미디어 배치 라운드: 「풀에서
    // 가져올때는 가 로 하자」 — 다시 묻지 않는다).
    final pooled = _poolEntryFor(path);
    return pooled == null
        ? resolved
        : resolved.copyWith(
            mode: pooled.carried
                ? ImportFileMode.keepInside
                : ImportFileMode.reference,
          );
  }

  /// The pool's entry for [path], or null for a file the pool has not seen.
  MediaAsset? _poolEntryFor(String path) => widget.session.repository
      .requireProject()
      .mediaAssetByPath(normalizedMediaPath(path));

  void _setSettings(
    Iterable<String> paths,
    ImportFileSettings Function(ImportFileSettings) change,
  ) {
    setState(() {
      for (final path in paths) {
        _settings[path] = change(_settings[path] ?? _seed);
      }
    });
  }

  /// 🐛ONE SEED FOR READING AND WRITING ([seedImportSettings]). A row's
  /// first answer used to start from the class's blank default instead, so
  /// pressing Bake on a movie also turned its Link into Keep — one column
  /// changed under a press in another.
  ImportFileSettings get _seed => seedImportSettings(spot: widget.spot);

  /// Whether each MOVIE in the batch has a sound, by its pool key — the
  /// conform answers, and the 「소리」 column asks only of a movie with one.
  final Map<String, bool> _movieSound = {};

  void _probeMovieSound(String path) {
    if (mediaAssetKindForPath(path) != MediaAssetKind.video) {
      return;
    }
    final key = normalizedMediaPath(path);
    if (_movieSound.containsKey(key)) {
      return;
    }
    unawaited(
      widget.session.audioConformStore.ensurePeaksFor(key).then((peaks) {
        if (mounted) {
          setState(() => _movieSound[key] = peaks != null);
        }
      }),
    );
  }

  /// The project's accumulated audio pull — a movie's preview counts its
  /// frames on the sound's clock, as its placement does.
  ({int numerator, int denominator}) get _projectAudioSpeed =>
      widget.session.repository.requireProject().audioSpeed;

  /// Whether the project CARRIES these files or points at them where they
  /// are. Carrying is the default now, on every platform.
  ///
  /// It was Reference, for a reason that has since been answered: the pool
  /// copied whatever it was handed, so dropping a 3GB 참고영상 meant a 3GB
  /// copy the user never asked for and could not decline.
  ///
  /// 🚨This paragraph used to end「the KIND rule settles that case on its
  /// own — video is never carried, whatever this says」. That ceiling died
  /// 2026-08-14 and video carries like anything else. The kind then picked
  /// only a file's STARTING answer, and a size note named what carrying would
  /// cost; both went 2026-09-16 (유저: any file, at any size, is kept or
  /// linked as the person answers — the decisions are on
  /// [seedImportSettings]). The toggle itself is what the person sees before
  /// pressing Import.
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
        _probeMovieSound(path);
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
        _status = AppText.strings.imFolderGone;
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
        _status = AppText.strings.imFolderUnreadable(error.message);
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
        onWaiting: (waited, arrival) {
          if (!mounted) {
            return;
          }
          // The sentence is [cloudWaitLine]'s, here and in the top strip's
          // open window (F-141) — one law, one place.
          setState(() => _status = cloudWaitLine(waited, arrival));
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
      _status = AppText.strings.imStatusImporting;
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
          ? AppText.strings.imStatusNothing
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
        await _registerFiles(tally);
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
      tally.warnings.add(AppText.strings.imCutFolderUnreadable);
      return;
    }
    tally.imported += 1;
    tally.warnings.addAll(
      folderWarnings.map((warning) => warning.textFor(AppText.language)),
    );
  }

  /// Places every picked file — a picture where the window says, a sound on
  /// the track's SE rows. Answers FALSE when the dialog went away part-way —
  /// the caller must not touch its state after that.
  Future<bool> _placeFiles(_ImportTally tally) async {
    for (final path in _files) {
      final kind = mediaAssetKindForPath(path);
      // A PLACEMENT reads the file, so this is where the picked path
      // has to become a path that reads — the same law the two open
      // doors go through. A cloud file arrives here as a placeholder
      // and would otherwise fail as if it were corrupt.
      if (await _readableForImport(path) == null) {
        tally.warnings.add(
          AppText.strings.imUnreadable(mediaFileName(path)),
        );
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
      ok = await _placeCarryingOnlyTheSpan(path, kind, tally, failedPages);
    } on Object {
      tally.warnings.add(
        AppText.strings.imCorrupt(mediaFileName(path)),
      );
      return;
    }
    if (failedPages.isNotEmpty) {
      final name = mediaFileName(path);
      tally.warnings.add(
        kind == MediaAssetKind.video
            ? AppText.strings.imFramesFailed(name, failedPages.length)
            : AppText.strings.imPagesFailed(name, failedPages.length),
      );
    }
    if (ok) {
      tally.imported += 1;
      tally.done.add(path);
      return;
    }
    tally.warnings.add(_placementFailure(path, kind, _settingsFor(path)));
  }

  /// Whether [path] comes in as its PIECE ([TrimmedPieces]) — trimmed, and
  /// carried in — whether it is placed or only registered.
  ///
  /// 🗣️유저 2026-09-23: 「비디오든 이미지든 오디오든 관계없이 법 하나로」 —
  /// ONE answer, here, for every kind and both of the window's modes.
  ///
  /// ⚠️Not a file the pool already holds, and not an exception of this
  /// round's making — two standing answers meet here. The pool's answer
  /// stands for a file it holds (유저 2026-09-11: 「풀에서 가져올때는 가 로
  /// 하자」, [_settingsFor]), so its Keep is the pool's, not this window's;
  /// and a file the pool carries is inside already, every byte of it — a
  /// piece of it would be a second copy (유저 08-27: 「사본 남으면 진짜
  /// 용서안할게」). Placing a stretch of it takes the pooled file as it is.
  bool _comesInAsAPiece(String path, ImportFileSettings settings) =>
      settings.isTrimmed &&
      settings.mode == ImportFileMode.keepInside &&
      _poolEntryFor(path) == null;

  /// [path] through its door — or, when it comes in as its PIECE
  /// ([_comesInAsAPiece]), the span cut into a file of its own and placed
  /// whole, with [path] as where it came from, then held like every carried
  /// file once it has landed. The doors behind it are the ones an untrimmed
  /// file goes through.
  Future<bool> _placeCarryingOnlyTheSpan(
    String path,
    MediaAssetKind? kind,
    _ImportTally tally,
    List<int> failedPages,
  ) async {
    final settings = _settingsFor(path);
    if (kind == null || !_comesInAsAPiece(path, settings)) {
      return _placeThrough(path, kind, tally, failedPages, settings);
    }
    final pieces = widget.session.trimmedPieces;
    final piece = await pieces.cut(
      path,
      kind,
      inFrame: settings.inFrame,
      outFrame: settings.outFrame,
    );
    if (piece == null) {
      return false;
    }
    var landed = false;
    try {
      landed = await _placeThrough(
        piece.path,
        kind,
        tally,
        failedPages,
        settings.copyWith(inFrame: 0, outFrame: piece.frames - 1),
        sourcePath: path,
      );
    } finally {
      if (landed) {
        pieces.secure(piece.path);
      } else {
        pieces.discard(piece.path);
      }
    }
    return landed;
  }

  /// Which door this file goes through: an expanded PSD, the PDF
  /// renderer, or the ordinary image path.
  Future<bool> _placeThrough(
    String path,
    MediaAssetKind? kind,
    _ImportTally tally,
    List<int> failedPages,
    ImportFileSettings settings, {
    String? sourcePath,
  }) {
    final carry = settings.mode == ImportFileMode.keepInside;
    final bake = settings.bake;
    if (kind == MediaAssetKind.audio) {
      return widget.session.importDoors.importSoundFile(
        path: path,
        copyIntoProject: carry,
        inFrame: settings.inFrame,
        outFrame: settings.outFrame,
        spot: widget.spot,
        sourcePath: sourcePath,
      );
    }
    if (kind == MediaAssetKind.video) {
      return _placeMovie(path, settings, failedPages, sourcePath: sourcePath);
    }
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
            setState(
              () => _status = AppText.strings.imRenderingPdf(rendered, total),
            );
          }
        },
        onPageRenderFailed: failedPages.add,
        spot: widget.spot,
        sourcePath: sourcePath,
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
      spot: widget.spot,
      sourcePath: sourcePath,
    );
  }

  /// Why a placement that ran and answered `false` did not land, most
  /// specific reason first: a build with no renderer, then a destination
  /// that is not there.
  /// A MOVIE's door (미디어 배치 라운드 6). Let go on an SE row's empty
  /// cell it is its sound alone (「SE 행은 소리만 담으므로 영상의 소리만
  /// 블록이 된다」). Anywhere else the picture lands — cels when it bakes,
  /// behind the app's one wait window, because a bake is hundreds of them
  /// (「이런 무거움이 예상되는 로직은 로딩 ui 띄우도록」) — with its sound on
  /// the SE rows when the 「소리」 answer says so.
  Future<bool> _placeMovie(
    String path,
    ImportFileSettings settings,
    List<int> failedFrames, {
    String? sourcePath,
  }) {
    final doors = widget.session.importDoors;
    final carry = settings.mode == ImportFileMode.keepInside;
    if (widget.spot is SeCellSpot) {
      return doors.importSoundFile(
        path: path,
        copyIntoProject: carry,
        inFrame: settings.inFrame,
        outFrame: settings.outFrame,
        spot: widget.spot,
        sourcePath: sourcePath,
      );
    }
    Future<bool> place(void Function(int rendered, int total)? progress) =>
        doors.importVideoFile(
          path: path,
          settings: settings,
          onRenderProgress: progress,
          onFrameRenderFailed: failedFrames.add,
          spot: widget.spot,
          sourcePath: sourcePath,
        );
    if (!settings.bake) {
      return place(null);
    }
    return runWithAppProgress<bool>(
      context: context,
      title: mediaFileName(path),
      titleIcon: Icons.movie_outlined,
      runningLabel: AppText.strings.bakeProgressRunning,
      doneLabel: AppText.strings.bakeProgressDone,
      windowKey: const ValueKey<String>('movie-bake-progress'),
      task: (report) => place(
        (rendered, total) => report(total <= 0 ? 1 : rendered / total),
      ),
    );
  }

  String _placementFailure(
    String path,
    MediaAssetKind? kind,
    ImportFileSettings settings,
  ) {
    if (kind == MediaAssetKind.pdf && PdfRenderService.availability != true) {
      return AppText.strings.imNoPdfRenderer(mediaFileName(path));
    }
    return AppText.strings.imCouldNotImport(mediaFileName(path));
  }

  /// Registers every picked file in as few undo steps as their answers
  /// allow — one batch for the carried, one for the referenced — a file
  /// that comes in as its PIECE ([_comesInAsAPiece]) as that piece, with the
  /// file as where it was cut from.
  ///
  /// 🗣️The same step a placement takes (유저 2026-09-11 「자른것만 안으로
  /// 들어가도록」). The pool's trim was designed with the placement's
  /// (import-place round, 2026-08-14 — 「In/Out 잘라 넣기 = 실제로 잘라서
  /// 품기」) and waited for a trimmer, which the placements got on
  /// 2026-09-23.
  Future<void> _registerFiles(_ImportTally tally) async {
    final pool = widget.session.mediaPool;
    final pieces = widget.session.trimmedPieces;
    // What the pool is handed — a piece in place of the file it was cut
    // from — and the picked file each one stands for.
    final carried = <String, String>{};
    final referenced = <String>[];
    for (final path in _files) {
      final settings = _settingsFor(path);
      final kind = mediaAssetKindForPath(path);
      if (kind != null && _comesInAsAPiece(path, settings)) {
        final piece = await pieces.cut(
          path,
          kind,
          inFrame: settings.inFrame,
          outFrame: settings.outFrame,
        );
        if (piece == null) {
          tally.warnings.add(_placementFailure(path, kind, settings));
        } else {
          carried[piece.path] = path;
        }
      } else if (settings.mode == ImportFileMode.keepInside) {
        carried[path] = path;
      } else {
        referenced.add(path);
      }
    }
    final cutFrom = {
      for (final MapEntry(key: handed, value: picked) in carried.entries)
        if (handed != picked) handed: picked,
    };
    var held = false;
    try {
      await pool.importMediaFiles(
        carried.keys.toList(),
        copyIntoProject: true,
        cutFrom: cutFrom,
      );
      held = true;
    } finally {
      for (final piece in cutFrom.keys) {
        held ? pieces.secure(piece) : pieces.discard(piece);
      }
    }
    tally
      ..imported += carried.length
      ..done.addAll(carried.values);
    await pool.importMediaFiles(referenced, copyIntoProject: false);
    tally
      ..imported += referenced.length
      ..done.addAll(referenced);
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
      copyIntoProject: settings.mode == ImportFileMode.keepInside,
      fit: settings.fit,
      spot: widget.spot,
    );
    if (expanded == null) {
      warnings.add(AppText.strings.imPsdNoLayers(mediaFileName(path)));
      return false;
    }
    warnings.addAll(
      expanded.map((warning) => warning.textFor(AppText.language)),
    );
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
          ? AppText.strings.imPlaceTitle(mediaFileName(_files.first))
          : AppText.strings.imImport,
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
  /// A pill the window's source cannot use stays on screen, disabled, so
  /// the other door is seen rather than hidden. Opened from the media
  /// pool's ＋ it is pinned to the pool — registering for later is what that
  /// panel is for. Opened on files the pool already holds (a pool row's
  /// 「배치…」, a drag from the pool) it is pinned to the timeline (유저
  /// 2026-09-11: 「미디어풀에 있던걸 타임라인 등 드래그앤드롭할때는
  /// 플레이스의 풀을 비활성화」).
  Widget _placeStrip(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              AppText.strings.imPlaceLabel,
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
                  onTap: _running || widget.placeOnly
                      ? null
                      : () => setState(() => _destination = null),
                  tooltip: widget.placeOnly
                      ? AppText.strings.imAlreadyPooledTooltip
                      : null,
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
                      ? AppText.strings.imPoolOnlyTooltip
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
  /// looked at. Until it is dragged the list takes what its columns and a
  /// readable name need; where the window cannot give it that, the list
  /// scrolls sideways at that width instead of squeezing the name.
  Widget _twoZones(BuildContext context) {
    final previewPath = _selected.isNotEmpty
        ? _selected.last
        : (_files.isEmpty ? null : _files.first);
    final settings = previewPath == null
        ? const ImportFileSettings()
        : _settingsFor(previewPath);
    final rows = [for (final path in _files) _tableRow(path)];
    final columns = _tableColumns();
    return LayoutBuilder(
      builder: (context, constraints) {
        final minTable = ImportFileTable.minimumWidth(
          context,
          rows: rows,
          columns: columns,
        );
        // The picture keeps 200 while the table can spare it, and never
        // less than its own transport needs. Past that the TABLE yields: it
        // is laid out narrower than its minimum and scrolls sideways inside
        // rather than pushing this row over the window's edge.
        final roomForTable = math.max(
          0.0,
          constraints.maxWidth -
              DockEdgeSplitter.thickness -
              ImportPreview.minimumWidth,
        );
        final maxTable = math.min(
          math.max(minTable, constraints.maxWidth - 200),
          roomForTable,
        );
        final narrowest = math.min(minTable, maxTable);
        final tableWidth =
            (_tableWidth ??
                    ImportFileTable.preferredWidth(
                      context,
                      rows: rows,
                      columns: columns,
                    ))
                .clamp(narrowest, maxTable);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: tableWidth, child: _fileTable(rows, columns)),
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
                // The ends appear wherever they act: on what gets placed,
                // and on what gets registered, which comes in as its piece
                // ([_registerFiles]). 🪦Registrations went without them
                // until a trimmer existed (2026-09-24). ⛔Not on a file the
                // pool already holds when only registering: that adds
                // nothing, so a span there would act on nothing.
                rangeEditable:
                    _placing ||
                    (previewPath != null && _poolEntryFor(previewPath) == null),
                soundPeaks: widget.session.audioConformStore.ensurePeaksFor,
                holdBytes: widget.session.projectFile.holdMediaBytes,
                frameRate: widget.session.projectSettings.projectFrameRate,
                audioSpeed: _projectAudioSpeed,
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

  /// A row names its file WITHOUT the extension, which it shows on its own:
  /// the name is what gets cut short when room runs out, the extension never
  /// is.
  ImportFileRow _tableRow(String path) {
    final parts = mediaFileNameParts(path);
    return ImportFileRow(
      path: path,
      name: parts.name,
      extension: parts.extension,
      modified: _modifiedOf(path),
      size: byteSizeLabel(_sizeOf(path)),
    );
  }

  /// One row per file, one column per question (§3 of the round).
  Widget _fileTable(
    List<ImportFileRow> rows,
    List<ImportColumn<Object?>> columns,
  ) => ImportFileTable(
    key: const ValueKey<String>('import-file-table'),
    enabled: !_running,
    selected: _selected,
    onRowTap: (path) => setState(() {
      if (!_selected.remove(path)) {
        _selected.add(path);
      }
    }),
    rows: rows,
    columns: columns,
  );

  /// The columns this window asks.
  ///
  /// 🚨ONE LAW: a column stands only when some row of THIS window has to
  /// answer it (유저 2026-09-11, 미디어 배치 라운드 5: 「즉 필요없는것들
  /// 안보이게 삭제해도됨」). Place, where the window was opened from and the
  /// kinds in it decide that. A column coming and going with Place is the
  /// user's own exception to the no-disappearing-UI rule, and it holds in
  /// this window only (「이런건 예외야. 필요한 것만 보이게하려고」).
  ///
  /// ⚠️A value the CONTEXT answered — a new cut's 1:1, an expanded PSD's
  /// bake, a pooled file's carry in a mixed batch — is not a reason to drop
  /// its column: the column stays and the value shows locked (「1:1로
  /// 고정시켜서 노출시키도록. 비활성화된상태로」). Only a question this
  /// placement does not ask goes.
  List<ImportColumn<Object?>> _tableColumns() {
    final placing = _placing;
    bool any(bool Function(String path) test) => _files.any(test);
    return [
      // The pool's question, asked only of a file the pool has not answered
      // (「플레이스가 타임라인일땐 그냥 품기/참조인 그 열 자체를 삭제」 for
      // pooled files, 「프로젝트의 임포트 버튼 … 품기/참조열 존재하도록」
      // for new ones).
      if (any((path) => _poolEntryFor(path) == null)) _fileColumn(),
      // The layer's question, wherever something is placed (「플레이스가
      // 타임라인이면 굽기열 만들기」).
      if (any(
        (path) => importBakeAllowed(
          kind: mediaAssetKindForPath(path),
          placing: placing,
        ),
      ))
        _bakeColumn(placing),
      // A movie's sound, asked only of a movie that has one (라운드 6 확인:
      // 「소리열: 추천대로」).
      if (any(_asksSound)) _soundColumn(),
      if (placing && _files.isNotEmpty) _intoColumn(),
      if (placing && any(_placesPicture)) _fitColumn(placing),
      // 「PSD가 아닌파일은 PSD열 삭제」.
      if (placing && any(importPathIsPsd)) _psdColumn(placing),
    ];
  }

  /// Whether [path] places as a PICTURE — the only thing a fit means
  /// anything for. A sound goes to the SE rows; a movie is a picture here,
  /// and its sound follows the 「소리」 answer.
  bool _placesPicture(String path) => !_isSound(path);

  /// Whether the 「소리」 question is this row's: a movie being placed that
  /// the conform found a sound in ([_probeMovieSound]).
  bool _asksSound(String path) => importSoundAllowed(
    kind: mediaAssetKindForPath(path),
    placing: _placing,
    hasSound: _movieSound[normalizedMediaPath(path)] ?? false,
  );

  bool _isSound(String path) =>
      mediaAssetKindForPath(path) == MediaAssetKind.audio;

  ImportColumn<Object?> _fileColumn() => ImportColumn<Object?>(
    id: 'file',
    label: AppText.strings.imFile,
    values: ImportFileMode.values,
    labelOf: (value) => importModeLabel(value! as ImportFileMode),
    valueOf: (path) => _settingsFor(path).mode,
    appliesTo: (path) => true,
    enabledFor: (path, value) {
      // A pooled file in a mixed batch shows the pool's answer, locked.
      if (_poolEntryFor(path) != null) {
        return value == _settingsFor(path).mode;
      }
      return importModeAllowed(
        mode: value! as ImportFileMode,
        trimmed: _settingsFor(path).isTrimmed,
      );
    },
    onPick: (paths, value) => _setSettings(
      paths,
      (settings) => settings.copyWith(mode: value! as ImportFileMode),
    ),
  );

  ImportColumn<Object?> _bakeColumn(bool placing) => ImportColumn<Object?>(
    id: 'bake',
    label: AppText.strings.imBake,
    style: ImportColumnStyle.toggle,
    values: const [false, true],
    labelOf: (value) => importOnOffLabel(value == true),
    valueOf: (path) => _settingsFor(path).bake,
    appliesTo: (path) => importBakeAllowed(
      kind: mediaAssetKindForPath(path),
      placing: placing,
    ),
    enabledFor: (path, value) =>
        value == true ||
        !importBakeLocked(
          isPsd: importPathIsPsd(path),
          placing: placing,
          psd: _settingsFor(path).psd,
          spot: widget.spot,
        ),
    onPick: (paths, value) => _setSettings(
      paths,
      (settings) => settings.copyWith(bake: value == true),
    ),
  );

  ImportColumn<Object?> _soundColumn() => ImportColumn<Object?>(
    id: 'sound',
    label: AppText.strings.imSound,
    style: ImportColumnStyle.toggle,
    values: const [false, true],
    labelOf: (value) => importOnOffLabel(value == true),
    valueOf: (path) => _settingsFor(path).sound,
    appliesTo: _asksSound,
    enabledFor: (path, value) =>
        value == true || !importSoundLocked(widget.spot),
    onPick: (paths, value) => _setSettings(
      paths,
      (settings) => settings.copyWith(sound: value == true),
    ),
  );

  ImportColumn<Object?> _intoColumn() {
    final spot = widget.spot;
    // A drop that answered the cut shows that answer locked; the canvas's
    // spot is a default and leaves the cut to this column
    // (pool-drop-picks-layer-or-cut, 유저 2026-09-12).
    final answering = spot?.answeredDestination == null ? null : spot;
    return ImportColumn<Object?>(
      id: 'into',
      label: AppText.strings.imInto,
      // A drop's answer is the ONE value, so the cell shows it and opens
      // nothing — the shape every locked answer in this table has.
      values: answering == null ? ImportDestination.values : [answering],
      labelOf: (value) => switch (value) {
        final ImportDestination into => importIntoLabel(into),
        final ImportLayerSpot dropped => _spotLabel(dropped),
        _SoundOnSeRows() => AppText.strings.imIntoSeRow,
        _ => '',
      },
      // A sound's place is the SE rows' own rule (유저 2026-09-11: 「SE1부터
      // … 겹치지 않는 … 기존 SE행 … 없으면 새 SE행」) — answered, so shown
      // locked, like every answer the context gave.
      valueOf: (path) => _isSound(path)
          ? (spot is SeCellSpot ? spot : const _SoundOnSeRows())
          : answering ?? _settingsFor(path).into,
      appliesTo: (path) => true,
      enabledFor: (path, value) =>
          !_isSound(path) &&
          (value != ImportDestination.activeCutLayer ||
              widget.session.activeCutOrNull != null),
      onPick: (paths, value) {
        if (value is ImportDestination) {
          _setSettings(paths, (settings) => settings.copyWith(into: value));
        }
      },
    );
  }

  /// A drop's answer in words: 「새 레이어」 for the canvas, 「새 컷」 for the
  /// storyboard's frames, the row and the cell for a row's frames or an SE
  /// cell (「A 원화 · 9번 칸」, 「S1 · 6번 칸」 — the mockup's words).
  String _spotLabel(ImportLayerSpot spot) => switch (spot) {
    AboveActiveLayerSpot() || LayerSlotSpot() => AppText.strings.imIntoNewLayer,
    NewCutSpot() => importIntoLabel(ImportDestination.newCut),
    RowFramesSpot(:final layerId, :final frameIndex) =>
      AppText.strings.imIntoRowCell(
        widget.session.layerById(layerId)?.name ?? '',
        frameIndex + 1,
      ),
    SeCellSpot(:final layerId, :final shownCell) =>
      AppText.strings.imIntoRowCell(
        widget.session.activeTrack.seLayers
                .where((layer) => layer.id == layerId)
                .firstOrNull
                ?.name ??
            '',
        shownCell + 1,
      ),
  };

  ImportColumn<Object?> _fitColumn(bool placing) => ImportColumn<Object?>(
    id: 'fit',
    label: AppText.strings.imFit,
    values: MediaFitMode.values,
    labelOf: (value) => importFitLabel(value! as MediaFitMode),
    valueOf: (path) => _settingsFor(path).fit,
    appliesTo: _placesPicture,
    enabledFor: (path, value) =>
        value == MediaFitMode.none ||
        !importFitLocked(_settingsFor(path), placing: placing),
    onPick: (paths, value) => _setSettings(
      paths,
      (settings) => settings.copyWith(fit: value! as MediaFitMode),
    ),
  );

  ImportColumn<Object?> _psdColumn(bool placing) => ImportColumn<Object?>(
    id: 'psd',
    label: 'PSD',
    values: PsdPlaceMode.values,
    labelOf: (value) => importPsdLabel(value! as PsdPlaceMode),
    valueOf: (path) => _settingsFor(path).psd,
    appliesTo: (path) => placing && importPathIsPsd(path),
    enabledFor: (path, value) =>
        value == PsdPlaceMode.merge || !importPsdLocked(widget.spot),
    onPick: (paths, value) => _setSettings(
      paths,
      (settings) => settings.copyWith(psd: value! as PsdPlaceMode),
    ),
  );


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
        ? AppText.strings.imNoSource
        : _files.length == 1
        ? _files.single
        : AppText.strings.imFileCount(_files.length);
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

  /// What the window says it will DO with what was picked: one row per
  /// thing it recognised, and the dim rows for what it will leave alone.
  Widget _interpretationTable(BuildContext context) {
    final parsed = _parsed;
    return ListView(
      key: const ValueKey<String>('import-interpretation-table'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        // ⛔NO LOOSE-FILE BRANCH. Loose files go to the file TABLE instead
        // (`_twoZones`), and this table is only built when `_files` is
        // empty — the branch that listed them here could not run at all,
        // and was still being kept in step with the kinds (감사 2026-09-09).
        if (parsed != null)
          ..._cutFolderRows(parsed)
        else
          _InterpretationRow(
            leading: '',
            body: AppText.strings.imPickToSee,
            dim: true,
          ),
        for (final ignored in _ignoredSources)
          _InterpretationRow(
            leading: AppText.strings.imIgnored,
            body: mediaFileName(ignored),
            dim: true,
          ),
      ],
    );
  }

  /// A parsed CUT FOLDER, read out in the order the delivery reads: the
  /// cut, its process, its layers and their cels, then what was left out.
  List<_InterpretationRow> _cutFolderRows(CutFolderParseResult parsed) {
    final strings = AppText.strings;
    return [
      _InterpretationRow(
        leading: strings.exCut,
        body: parsed.cutNumbers.isEmpty
            ? parsed.folderName
            : parsed.cutNumbers.join(' · ') +
                  (parsed.cutNumbers.length > 1
                      ? '  ${strings.imMultiCutMark}'
                      : ''),
      ),
      if (parsed.processTokens.isNotEmpty)
        _InterpretationRow(
          leading: strings.imProcess,
          body: parsed.processTokens.join(' + '),
        ),
      for (final layer in parsed.layers)
        _InterpretationRow(
          leading: '${strings.exLayer} ${layer.symbol}',
          body:
              '${strings.exCelCount(layer.cells.length)} '
              '(${layer.cells.map((c) => c.label).join(', ')})',
        ),
      for (final picture in parsed.pictures)
        _InterpretationRow(leading: strings.imPicture, body: picture.name),
      for (final group in parsed.processGroups)
        _InterpretationRow(
          leading: '${strings.imProcess} ${group.process}',
          body: [
            for (final layer in group.layers)
              '${layer.symbol}: ${layer.cells.length}',
          ].join(' · '),
        ),
      for (final reference in parsed.references)
        _InterpretationRow(
          leading: strings.imReference,
          body: reference.file,
          dim: true,
        ),
      for (final exclusion in parsed.excluded)
        _InterpretationRow(
          leading: strings.imExcluded,
          body: '${exclusion.path} — '
              '${exclusion.reason.labelFor(AppText.language)}',
          dim: true,
        ),
      for (final warning in parsed.warnings)
        _InterpretationRow(
          leading: '⚠',
          body: warning.textFor(AppText.language),
        ),
    ];
  }


  int _sizeOf(String path) => _fileSizes.putIfAbsent(path, () {
    try {
      return File(path).lengthSync();
    } on Object {
      return 0; // Unreadable: the import degrades.
    }
  });

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
            labelOf: (copy) => importModeLabel(
              copy ? ImportFileMode.keepInside : ImportFileMode.reference,
            ),
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
                ? AppText.strings.imKeepExplain
                : AppText.strings.imReferenceExplain,
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 6),
          // §6-z22: a cut folder's cels are what you draw on next, so
          // the folder import always bakes — no toggle to mislead.
          Text(
            AppText.strings.imCutFolderBakes,
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
            labelOf: importFitLabel,
            onSelect: (fit) => setState(() => _fit = fit),
          ),
          const SizedBox(height: 10),
          ExportToggleRow(
            keyValue: 'import-subfolders-toggle',
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
            keyValue: 'import-multicut-toggle',
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
              CelRevisionPolicy.latestOnly => AppText.strings.imRevLatest,
              CelRevisionPolicy.all => AppText.strings.imRevAll,
              CelRevisionPolicy.originalOnly => AppText.strings.imRevOriginals,
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

/// One line of the interpretation table: what was recognised on the left,
/// what it is on the right. [dim] is the "will be left alone" reading —
/// references, exclusions, ignored files and the empty prompt.
class _InterpretationRow extends StatelessWidget {
  const _InterpretationRow({
    required this.leading,
    required this.body,
    this.dim = false,
  });

  final String leading;
  final String body;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
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
    );
  }
}
