import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../../models/import/cut_folder_parse.dart';
import '../../models/import/import_warning.dart';
import '../../services/import/cut_folder_listing.dart';
import '../../models/media_asset.dart';
import '../../models/movie_clock.dart' show movieClockFor;
import '../../models/project_frame_rate.dart';
import '../../native/qa_video_decoder.dart' show QaVideoInfo;
import '../../services/import/import_layer_spot.dart';
import '../../services/import/media_import_planner.dart';
import '../../services/media/movie_bytes.dart' show openHeldMovie;
import '../../services/media/video_decode_worker.dart'
    show videoDecodeBackend;
import '../../services/pdf/pdf_render_service.dart';
import '../../services/persistence/folder_grant.dart'
    show FolderGrant, FolderPicker, MaterializeCancelled;
import '../../services/persistence/provider_documents.dart';
import '../dialogs/app_progress_dialog.dart';
import '../dialogs/cloud_wait.dart';
import '../editor_session_manager.dart';
import '../export/export_settings_modules.dart';
import 'import_file_settings.dart';
import 'import_file_table.dart';
import 'import_preview.dart';
import 'import_warnings_notice.dart';
import 'movie_rate_dialog.dart';
import '../text/byte_size_label.dart';
import '../widgets/app_window.dart';
import '../widgets/dock_edge_splitter.dart';
import '../widgets/settings_rows.dart';
import '../text/model_vocabulary.dart';

/// The import window (§6-z21): ONE window for every import, defaults
/// filled so the simple case is a single Enter. It picks nothing itself:
/// what the one door hands it comes in ([picked] — the menu's 「파일
/// 열기…」 and 「폴더 열기…」, a drop on the window, the media panel's ＋,
/// the viewer's 「미디어에 등록」), and so do files the app already holds
/// ([initialPaths]). The interpretation table shows what each source
/// becomes (folders list every file, dropped ones included — nothing exits
/// silently).
///
/// ↩️It had a 「파일…」 and a 「컷 폴더…」 of its own, and the menu's
/// 「가져오기/배치…」 opened it on nothing to press them (F-282, 유저
/// 2026-10-09: 「열기랑 임포트랑 되도록 하나로」).
///
/// v1 zones: source line → interpretation table (preview) | settings
/// modules → action bar. The preset rail and queue drawers of the export
/// skeleton join when parser presets get their store.
class ImportDialog extends StatefulWidget {
  const ImportDialog({
    super.key,
    required this.session,
    this.initialPaths = const [],
    this.picked = const [],
    this.poolOnly = false,
    this.placeOnly = false,
    this.spot,
  });

  final EditorSessionManager session;

  /// Files the app already holds, handed in by path (files or one folder) —
  /// a media row placed, a drag from the pool.
  final List<String> initialPaths;

  /// What the one door handed in (F-282): a pick's grants — the token that
  /// reopens a referenced file next launch, a document with no filesystem
  /// path (PICK-7) — a drop's and the viewer's paths, or a folder. Taken in
  /// as [initialPaths] are, the documents through copies of this window's.
  final List<FolderGrant> picked;

  /// Opened through a pool's door — the media panel's ＋, the viewer's
  /// 「미디어에 등록」 — whose job is to REGISTER a file for later rather
  /// than place it now: the window stands on the pool, and the timeline is
  /// shown but shut (08-14, 유저가 시안을 보고 확정: 「＋도 같은 창을 열고
  /// Place=Pool 고정, Timeline 비활성」).
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

  /// What the run could not do, each as its notice lists it.
  final List<WarningLine> warnings = [];
  final List<String> done = [];

  /// [sentence], said of the file [name].
  void warnOf(String name, String sentence) =>
      warnings.add(partsOf(sentence, about: name));

  /// [sentence], said of no one file.
  void warn(String sentence) => warnings.add((about: null, says: sentence));

  /// The warnings a door raised, in the reader's language.
  void warnAll(Iterable<ImportWarning> raised) => warnings.addAll(
    raised.map((warning) => warning.partsFor(AppText.language)),
  );
}

/// What the window last had to say on its status line: a sentence, or the
/// warnings a run or a pick left — said as the button their notice opens
/// from (F-370-Q1) — and never both.
sealed class _Said {
  const _Said();
}

final class _Sentence extends _Said {
  const _Sentence(this.words);

  final String words;
}

final class _Warnings extends _Said {
  const _Warnings(this.lines);

  final List<WarningLine> lines;
}

/// [done] of [total] as the share the wait window counts — all of it when
/// there was nothing to count.
double _share(int done, int total) => total <= 0 ? 1 : done / total;

/// What one file's door tells back while it runs: how far it is, and the
/// pages or frames it could not render. The two go down the same doors
/// together, so they are handed down as one.
class _FileReport {
  _FileReport(this._within);

  final void Function(double) _within;

  /// The pages (a PDF) or frames (a movie) that would not render.
  final List<int> failed = [];

  /// [done] of the file's [total] pieces rendered.
  void rendered(int done, int total) => _within(_share(done, total));
}

/// Which question the 「옵션」 column asks a row.
enum _OptionAsked {
  /// A numbered run's: all of it, or this file alone.
  run,

  /// A Photoshop document's: its layers kept, or merged.
  psd,

  /// A movie's with a sound: picture and sound, picture, or sound.
  sound,
}

/// The Into answer a SOUND gives: the track's SE rows, by their own rule.
final class _SoundOnSeRows {
  const _SoundOnSeRows();

  /// What its popup row is keyed by.
  @override
  String toString() => 'se-rows';
}

/// The 「옵션」 answer of a picture in a numbered run: the span IN/OUT keep
/// of it, picked on the preview and only shown here — one answer, so the
/// cell stands locked and says the span ([_runSpanWord]).
final class _RunSpan {
  const _RunSpan();

  /// What its popup row would be keyed by.
  @override
  String toString() => 'run';
}

/// The layer a row brings of its numbered run, as the run's door is handed
/// it (`ProjectImportDoors.importPictureRun`): the run, the span of it the
/// row's IN/OUT keep, and the two answers the door reads — where the layer
/// goes and how it fits. Rows that hand it the same bring one layer.
typedef _RunLayer = ({
  ParsedCelLayer run,
  int first,
  int last,
  ImportDestination into,
  MediaFitMode fit,
});

/// The Into answer of a file that only registers: the media pool, placed
/// nowhere ([ImportFileSettings.intoPool]).
final class _IntoThePool {
  const _IntoThePool();

  /// What its popup row is keyed by.
  @override
  String toString() => 'pool';
}

class _ImportDialogState extends State<ImportDialog> {
  final List<String> _files = [];
  String? _folder;

  /// Whether [path]'s row only REGISTERS — its 넣을 곳 is 「미디어」 — as
  /// its row answers ([ImportFileSettings.intoPool]), unless the context
  /// answered: a pool's door registers every row ([ImportDialog.poolOnly],
  /// 08-14), and a file the pool already holds has nothing left to
  /// register, so it is placed (유저 2026-09-11: 「미디어풀에 있던걸 타임라인
  /// 등 드래그앤드롭할때는 플레이스의 풀을 비활성화」).
  ///
  /// Read from the row's own answer, not from [_settingsFor]: what a row
  /// resolves to depends on this ([_runOf] among it).
  ///
  /// ⚠️The planner's [ImportDestination] still answers only WHERE a
  /// placement goes — registering without placing is not a place, and a
  /// third value there would be one every switch over the enum had to
  /// learn to ignore (08-12). So the row holds the two questions apart.
  bool _registersOnly(String path) =>
      widget.poolOnly ||
      ((_settings[path] ?? _seed).intoPool && _poolEntryFor(path) == null);

  /// Whether [path]'s row is placed somewhere — every question but the
  /// pool's changes meaning with it, per row.
  bool _placing(String path) => !_registersOnly(path);

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

  /// The copies this window read documents through — files the picker
  /// handed over with no filesystem path (PICK-7, Drive on Android), each
  /// brought into this run's room under the document's own name.
  ///
  /// 🗣️유저 2026-09-27: 「안한것 다 해줘. 임포트 드라이브로 할때라던가」.
  /// Such a file is CARRIED — its copy goes with the run, so there is
  /// nothing lasting to point at ([importModeAllowed]) — and the copy is let
  /// go of when a pick replaces it or the window closes: by then the staged
  /// bytes are the project's, and a second copy that stays is what 유저
  /// 08-27 refused (「사본 남으면 진짜 용서안할게」).
  final Set<String> _intakeCopies = {};

  /// Whether [path] will still be where it is when the project opens next.
  bool _lasting(String path) => !_intakeCopies.contains(path);

  ImportFileSettings _settingsFor(String path) {
    final kind = mediaAssetKindForPath(path);
    final resolved = resolvedImportSettings(
      // Untouched rows answer with their seed ([_seed]) — without a movie's
      // sound on a picture row's frames.
      _settings[path] ?? _seed,
      kind: kind,
      isPsd: importPathIsPsd(path),
      placing: _placing(path),
      hasActiveCut: widget.session.activeCutOrNull != null,
      lasting: _lasting(path),
      spot: widget.spot,
      runLength: _runOf(path)?.cells.length,
    ).copyWith(intoPool: _registersOnly(path));
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
      .mediaAssetByPath(path);

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

  /// The folders the picked pictures live in, each read ONCE, as the
  /// preview reads a dropped folder ([_folderEntries]) — under the parse
  /// config they were read with ([_runConfig]).
  final Map<String, CutFolderParseResult?> _runFolders = {};
  CutFolderParseConfig? _runConfig;

  /// The numbered run [path] is part of (`celRunOf`), when its row is
  /// placed — null for a file in none.
  ///
  /// 🗣️I-76 (유저 2026-10-06): 「A1 임포트하면 A2,A3같은 파일들 인식해서」 —
  /// the folder is read with the cut folder's own grammar and knobs
  /// ([_parseConfig]), so a run is what the folder import would call that
  /// picture's layer.
  ParsedCelLayer? _runOf(String path) {
    if (!_placing(path) ||
        mediaAssetKindForPath(path) != MediaAssetKind.image) {
      return null;
    }
    if (_runConfig != _parseConfig) {
      _runFolders.clear();
      _runConfig = _parseConfig;
    }
    final folder = File(path).parent.path;
    final parsed = _runFolders.putIfAbsent(folder, () {
      try {
        return parseCutFolderAt(
          folder,
          entries: cutFolderEntriesFrom(folder, Directory(folder).listSync()),
          config: _parseConfig,
        );
      } on FileSystemException {
        return null;
      }
    });
    return parsed == null ? null : celRunOf(mediaFileName(path), parsed);
  }

  /// The pictures of [path]'s run its span keeps — the run's IN/OUT,
  /// picked on the preview ([ImportFileSettings.runIn]) — or null for a
  /// file in none.
  List<ParsedCel>? _runKeptOf(String path) {
    final run = _runOf(path);
    if (run == null) {
      return null;
    }
    final span = importRunSpan(_settingsFor(path), run.cells.length);
    return run.cells.sublist(span.first, span.last + 1);
  }

  /// [path]'s run when its span keeps two pictures or more: they come in as
  /// one layer's frames. One comes in alone ([_placeRun]).
  ParsedCelLayer? _togetherRunOf(String path) =>
      (_runKeptOf(path)?.length ?? 0) > 1 ? _runOf(path) : null;

  /// The layer [path]'s row brings of its run ([_RunLayer]) — null for a
  /// row that brings no run of two pictures or more ([_togetherRunOf]).
  _RunLayer? _runLayerOf(String path) {
    final run = _togetherRunOf(path);
    if (run == null) {
      return null;
    }
    final settings = _settingsFor(path);
    final span = importRunSpan(settings, run.cells.length);
    return (
      run: run,
      first: span.first,
      last: span.last,
      into: settings.into,
      fit: settings.fit,
    );
  }

  /// Every picture of [path]'s run, in order — what the preview pages
  /// through — or null for a file in none.
  List<String>? _runFilesOf(String path) {
    final run = _runOf(path);
    final folder = File(path).parent.path;
    return run == null
        ? null
        : [for (final cel in run.cells) '$folder/${cel.file}'];
  }

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
  _Said _status = const _Sentence('');

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
    _wait.status.addListener(_waitChanged);
    _wait.waiting.addListener(_waitChanged);
    // A grant's path is taken now, as a path handed in is — the first frame
    // shows the files, not an empty window that fills a frame later. Its
    // token is kept for the run ([_pickedGrants]); a document's bytes come
    // after, under the wait a pick's always came under.
    final grantedPaths = [for (final grant in widget.picked) ?grant.path];
    _pickedGrants.addAll([
      for (final grant in widget.picked)
        if (grant.path != null) grant,
    ]);
    final documents = [
      for (final grant in widget.picked)
        if (grant.document != null) grant,
    ];
    if (documents.isNotEmpty) {
      // Once this build is done: the wait the copies go under redraws.
      unawaited(Future<void>.microtask(() => _takeDocuments(documents)));
    }
    for (final path in [...widget.initialPaths, ...grantedPaths]) {
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

  @override
  void dispose() {
    // A copy still on its way is stopped: nothing is left to take it.
    _wait.cancel();
    _wait.status.removeListener(_waitChanged);
    _wait.waiting.removeListener(_waitChanged);
    _wait.dispose();
    _intakeCopies.forEach(ProviderDocuments.letGo);
    super.dispose();
  }

  /// What the door handed in with the files in [_files] — a pick's grants
  /// — kept until Import runs so the session can record them.
  ///
  /// 🚨 The whole point of PICK-5 arrives here. On Apple a referenced path
  /// is refused after a relaunch unless the app kept the security-scoped
  /// token, and the token exists only for as long as this window holds it
  /// — nothing else in the app ever sees the picker's answer.
  final List<FolderGrant> _pickedGrants = [];

  /// The documents the door handed in, listed once their copies have come
  /// ([_readablePathsOf]) — beside a folder they are left out, as a file
  /// handed in with one is.
  Future<void> _takeDocuments(List<FolderGrant> documents) async {
    final paths = await _readablePathsOf(documents);
    if (paths.isEmpty || !mounted) {
      return;
    }
    setState(() {
      if (_folder != null) {
        _ignoredSources.addAll(paths);
      } else {
        _files.addAll(paths);
      }
    });
    paths.forEach(_probeMovieSound);
  }

  /// What each of [picked] is read from: its own path, or — a document with
  /// no filesystem path (PICK-7) — a copy brought into this run's room
  /// ([_intakeCopies]) under the wait, the clock and the Stop a cloud file's
  /// placement waits with ([_readableForImport]). A document that does not
  /// come is left out and named in the warnings the status line opens.
  Future<List<String>> _readablePathsOf(List<FolderGrant> picked) async {
    final paths = <String>[];
    final missed = <String>[];
    for (final grant in picked) {
      if (grant.document case final document?) {
        final copy = await _readableForImport(document.uri);
        if (!mounted) {
          // The window went while the copy came: nothing will let go of it.
          if (copy != null) {
            ProviderDocuments.letGo(copy);
          }
          return const [];
        }
        if (copy == null) {
          missed.add(document.name);
        } else {
          _intakeCopies.add(copy);
          paths.add(copy);
        }
      } else if (grant.path case final path?) {
        paths.add(path);
      }
    }
    if (picked.any((grant) => grant.document != null)) {
      setState(
        () => _status = _Warnings([
          for (final name in missed)
            partsOf(AppText.strings.imUnreadable(name), about: name),
        ]),
      );
    }
    return paths;
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
        _status = _Sentence(AppText.strings.imFolderGone);
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
        _status = _Sentence(AppText.strings.imFolderUnreadable(error.message));
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
      !_busy && (_files.isNotEmpty || (_folder != null && _parsed != null));

  /// Importing, or waiting on a document's bytes after a pick — either way
  /// the sources are not to be changed or run from under it.
  bool get _busy => _running || _wait.waiting.value;

  /// The wait for somebody else's bytes ([_readableForImport]) — after a
  /// pick, said on this window's status line with its Cancel as the stop;
  /// during a run, said on the wait window the run stands behind, with
  /// ITS Cancel (F-282-Q1). Waiting is the only stretch of a run that can
  /// honestly be stopped, and a stop gives up the one file waited for.
  final CloudWait _wait = CloudWait();

  void _waitChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// The window's status line: a wait's own while there is one, else what
  /// the window last had to say.
  _Said get _statusLine => _wait.status.value.isNotEmpty
      ? _Sentence(_wait.status.value)
      : _status;

  /// The ONE law, applied where a picked file is about to be READ.
  ///
  /// ⚠️Registering media is a REFERENCE and stays untouched: forcing a
  /// download for a movie somebody only registered would be the app
  /// spending their line for them, for bytes it does not need. A
  /// placement reads, so a placement waits.
  ///
  /// ↩️It was said on this window's own status line during a run too, on
  /// the premise that a second window over it would be two answers to one
  /// question — until the whole run stood behind the app's wait window
  /// (유저 2026-10-08, F-282-Q1: 「클라우드 파일을 기다리는 줄과 「그만」도
  /// 이 창으로 옮긴다」), which is then the one answer.
  ///
  /// ⛔The staged copy is refused here even though the materialiser can
  /// still produce one: an import names the asset after its file, so a
  /// temp name would land in the project as the drawing's name. Waiting
  /// for the PICK to read is the only outcome this door can use.
  /// Answers null when the file never arrives or the user stops it.
  Future<String?> _readableForImport(String path) async {
    _wait.begin();
    try {
      final source = await FolderPicker.materializeOpenedFile(
        path,
        within: null,
        onWaiting: (waited, arrival) {
          if (mounted) {
            _wait.report(waited, arrival);
          }
        },
        isCancelled: _wait.isCancelled,
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
        _wait.ended();
      }
    }
  }

  Future<void> _runImport() async {
    if (!_canImport || !await _answerMovieRates() || !mounted) {
      return;
    }
    setState(() {
      _running = true;
      _status = _Sentence(AppText.strings.imStatusImporting);
    });
    // Before anything registers: the session has to be holding the tokens
    // by the time a save writes them down, and this is the only moment
    // they exist outside the picker. Harmless when the list is empty,
    // which is every desktop import and every drop.
    widget.session.mediaGrants.rememberMediaGrants(_pickedGrants);
    final tally = _ImportTally();
    // 🗣️유저 2026-10-08 (F-282-Q1, 「굽기 · 저장과 같은 기다림 창에」): the
    // whole run stands behind the app's one wait window. Its % counts the
    // files, and the one being placed as far as that one says (a movie's
    // frames, a PDF's pages, a folder's scans); a cloud file's wait is its
    // status line, and its Cancel gives that file up. ↩️Only a movie that
    // baked stood behind one — a window of its own for every movie — and
    // the rest said 「임포트하는 중…」 on this window's status line.
    final finished = await runWithAppProgress<bool>(
      context: context,
      title: AppText.strings.imImport,
      titleIcon: Icons.download_outlined,
      runningLabel: AppText.strings.imStatusImporting,
      doneLabel: AppText.strings.imStatusDone,
      windowKey: const ValueKey<String>('import-progress-dialog'),
      runningStatus: _wait.status,
      onCancel: _wait.cancel,
      cancelLive: _wait.waiting,
      task: (report) => _importAll(tally, report),
    );
    if (!finished || !mounted) {
      return; // the dialog went away part-way through the batch
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
          ? _Sentence(AppText.strings.imStatusNothing)
          : _Warnings(tally.warnings);
    });
  }

  /// 🗣️import-movie-fps-mismatch-notice (유저 10-06: 「알리는게 좋겠어」 ·
  /// 「셋다 맞고」, 10-10 「1번」 — asked when Import is pressed): a movie
  /// about to be PLACED whose rate is the project's pulldown partner
  /// ([pulldownPartnerOf]) is named before it lands, and the project may
  /// take its rate, the sound keeping its real time (「오디오 타이밍 유지」,
  /// the plain rate change). A row that only registers places nothing — it
  /// is asked when it is placed, through this window. False when the
  /// person backed out of the import.
  Future<bool> _answerMovieRates() async {
    final project = widget.session.projectSettings.projectFrameRate;
    final movie = await _pulldownPartnerAmongPlaced(project);
    if (movie == null) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    final answer = await showMovieRateDialog(
      context,
      project: project,
      movie: movie,
    );
    if (answer == MovieRateAnswer.take && mounted) {
      await _respanFor(from: project, to: movie);
      widget.session.projectSettings.setProjectFrameRate(movie);
    }
    return answer != null && mounted;
  }

  /// The rate of the first placed movie that runs at [project]'s pulldown
  /// partner, or null when none does.
  Future<ProjectFrameRate?> _pulldownPartnerAmongPlaced(
    ProjectFrameRate project,
  ) async {
    for (final path in _files.where(_placing)) {
      if (mediaAssetKindForPath(path) != MediaAssetKind.video) {
        continue;
      }
      final movie = await _movieInfoOf(path);
      final partner = movie == null
          ? null
          : pulldownPartnerOf(project, (
              numerator: movie.fpsNumerator,
              denominator: movie.fpsDenominator,
            ));
      if (partner != null) {
        return partner;
      }
    }
    return null;
  }

  /// What [path]'s movie says of itself, read as its door will read it
  /// ([openHeldMovie]) — null when it does not open.
  Future<QaVideoInfo?> _movieInfoOf(String path) async {
    final opened = await openHeldMovie(
      videoDecodeBackend,
      widget.session.projectFile.holdMediaBytes,
      path,
    );
    if (opened == null) {
      return null;
    }
    try {
      return opened.info;
    } finally {
      await opened.close();
    }
  }

  /// Every span counted in PROJECT frames — a movie's and a sound's, whose
  /// IN/OUT run on the sound's clock (`ProjectImportDoors.importVideoFile`)
  /// — moved from [from]'s frames to [to]'s, so what the person stood IN
  /// and OUT on before the rate changed is what comes in.
  Future<void> _respanFor({
    required ProjectFrameRate from,
    required ProjectFrameRate to,
  }) async {
    for (final path in [..._files]) {
      final settings = _settings[path];
      if (settings == null || !settings.isTrimmed) {
        continue;
      }
      final moved = switch (mediaAssetKindForPath(path)) {
        MediaAssetKind.video => await _movieSpanAt(path, settings, from, to),
        MediaAssetKind.audio => _spanAt(
          settings,
          (frame) => frameAtSameTime(frame, from: from, to: to),
          (frame) => frameAtSameTime(frame, from: from, to: to),
        ),
        _ => null,
      };
      if (moved != null && mounted) {
        _setSettings([path], (_) => moved);
      }
    }
  }

  /// [settings]' span with its IN through [first] and its OUT through
  /// [last] — an OUT left at the end stays there.
  ImportFileSettings _spanAt(
    ImportFileSettings settings,
    int Function(int frame) first,
    int Function(int frame) last,
  ) => settings.copyWith(
    inFrame: first(settings.inFrame),
    outFrame: switch (settings.outFrame) {
      final out? => last(out),
      null => null,
    },
  );

  /// A movie's span kept on the same PICTURES: the movie frame each end
  /// showed on [from]'s clock, found again on [to]'s ([movieClockFor]) —
  /// IN at the first frame that shows its picture, OUT at the last. Null
  /// when the movie does not open.
  Future<ImportFileSettings?> _movieSpanAt(
    String path,
    ImportFileSettings settings,
    ProjectFrameRate from,
    ProjectFrameRate to,
  ) async {
    final movie = await _movieInfoOf(path);
    if (movie == null) {
      return null;
    }
    final speed = _projectAudioSpeed;
    final before = movieClockFor(
      projectRate: from,
      audioSpeed: speed,
      movie: movie,
    );
    final after = movieClockFor(
      projectRate: to,
      audioSpeed: speed,
      movie: movie,
    );
    return _spanAt(
      settings,
      (frame) => after.projectFramesCovering(before.movieFrameAt(frame)),
      (frame) =>
          after.projectFramesCovering(before.movieFrameAt(frame) + 1) - 1,
    );
  }

  /// Runs the picked import, whichever door it goes through, telling
  /// [report] how far it is (0–1). Answers FALSE when the dialog went away
  /// part-way.
  ///
  /// ⛔ONE catch for the whole run: a batch that throws part-way KEEPS
  /// what already landed (the tally fills as it goes) and the error
  /// becomes a warning, so the dialog says what happened rather than
  /// leaving a dead spinner behind an unhandled error.
  Future<bool> _importAll(
    _ImportTally tally,
    void Function(double) report,
  ) async {
    try {
      final folder = _folder;
      if (folder != null) {
        await _importCutFolder(folder, tally, report);
        return true;
      }
      // Each row as its 넣을 곳 says: the ones that only register, then the
      // ones that are placed — one count over both, a file each.
      final registering = _files.where(_registersOnly).toList();
      final placing = _files.where(_placing).toList();
      final share = _share(registering.length, _files.length);
      if (registering.isNotEmpty) {
        // The pool: every kind registers, movies included. Two batches
        // rather than one, because carrying is a per-file answer and the
        // registration verb takes one flag for the batch it is given.
        await _registerFiles(
          registering,
          tally,
          (fraction) => report(fraction * share),
        );
      }
      if (placing.isNotEmpty) {
        // ⛔The `await` is NOT redundant: `return _placeFiles(tally)`
        // hands the future to the caller and this try never sees it
        // fail, so a throw part-way through the batch would escape as an
        // unhandled async error and leave the spinner running forever.
        return await _placeFiles(
          placing,
          tally,
          (fraction) => report(share + fraction * (1 - share)),
        );
      }
    } on Object catch (error) {
      tally.warn('$error');
    }
    return true;
  }

  Future<void> _importCutFolder(
    String folder,
    _ImportTally tally,
    void Function(double) report,
  ) async {
    final folderWarnings = await widget.session.cutFolderDoor.importCutFolder(
      folderPath: folder,
      config: _parseConfig,
      fit: _fit,
      copyIntoProject: _copyIntoProject,
      onProgress: (baked, total) => report(_share(baked, total)),
    );
    if (folderWarnings == null) {
      tally.warn(AppText.strings.imCutFolderUnreadable);
      return;
    }
    tally
      ..imported += 1
      ..warnAll(folderWarnings);
  }

  /// Places every picked file — a picture where the window says, a sound on
  /// the track's SE rows — telling [report] the files before the one being
  /// placed and that one as far as it says. Answers FALSE when the dialog
  /// went away part-way — the caller must not touch its state after that.
  Future<bool> _placeFiles(
    List<String> paths,
    _ImportTally tally,
    void Function(double) report,
  ) async {
    final count = paths.length;
    // A run two of its own pictures were picked from comes in once when
    // their rows would bring the same layer of it ([_RunLayer]) — the
    // second row is already in. A row that keeps another span, or puts it
    // elsewhere, brings what its own cells say.
    final runsPlaced = <_RunLayer>{};
    for (final (index, path) in paths.indexed) {
      void within(double fraction) =>
          report((index + fraction.clamp(0, 1)) / count);
      within(0);
      final run = _runLayerOf(path);
      if (run != null && runsPlaced.contains(run)) {
        tally
          ..imported += 1
          ..done.add(path);
        continue;
      }
      final kind = mediaAssetKindForPath(path);
      // A PLACEMENT reads the file, so this is where the picked path
      // has to become a path that reads — the same law the two open
      // doors go through. A cloud file arrives here as a placeholder
      // and would otherwise fail as if it were corrupt.
      //
      // 🐞F-282 ④ (유저 2026-10-04: 「동영상을 잘라내서 임포트시,
      // 미디어풀에 등록되는데, 그걸 다시 타임라인에 배치하려하면 파일을
      // 읽지 못했다고 뜸」): bytes the PROJECT holds are not read from the
      // file — every door reads the carry first — so there is no file to
      // wait for. A piece cut on import and a voice take never had one; a
      // carried file's original may be gone.
      if (!widget.session.projectFile.projectHoldsMediaBytes(path) &&
          await _readableForImport(path) == null) {
        final name = mediaFileName(path);
        tally.warnOf(name, AppText.strings.imUnreadable(name));
        continue;
      }
      if (!mounted) {
        return false;
      }
      await _placeOneFile(path, kind, tally, within);
      if (run != null) {
        runsPlaced.add(run);
      }
    }
    report(1);
    return true;
  }

  /// One file through its door, telling [within] how far it is. ⛔A file
  /// that fails does NOT abort the batch: it leaves a named warning and the
  /// loop moves on (the image path's per-file contract).
  Future<void> _placeOneFile(
    String path,
    MediaAssetKind? kind,
    _ImportTally tally,
    void Function(double) within,
  ) async {
    final fileReport = _FileReport(within);
    final name = mediaFileName(path);
    final bool ok;
    try {
      ok = await _placeCarryingOnlyTheSpan(path, kind, tally, fileReport);
    } on Object {
      tally.warnOf(name, AppText.strings.imCorrupt(name));
      return;
    }
    final failed = fileReport.failed.length;
    if (failed > 0) {
      // A PDF's are pages; a movie's — and a numbered run's — are frames.
      tally.warnOf(
        name,
        kind == MediaAssetKind.pdf
            ? AppText.strings.imPagesFailed(name, failed)
            : AppText.strings.imFramesFailed(name, failed),
      );
    }
    if (ok) {
      tally.imported += 1;
      tally.done.add(path);
      return;
    }
    tally.warnOf(name, _placementFailure(name, kind));
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
  ///
  /// A piece is a pool entry's to be: a row that leaves none (baked,
  /// F-282-Q6) bakes its span from the file through its door's IN/OUT.
  bool _comesInAsAPiece(String path, ImportFileSettings settings) =>
      settings.isTrimmed &&
      settings.mode == ImportFileMode.keepInside &&
      _poolEntryFor(path) == null &&
      _keepsAPoolEntry(path);

  /// Whether [path]'s row leaves its file in the media pool: a row that
  /// only registers, and a placement that does by [placementRegisters] —
  /// one the layer draws from, or a movie whose sound lands beside its
  /// baked picture.
  bool _keepsAPoolEntry(String path) {
    final settings = _settingsFor(path);
    return settings.intoPool ||
        placementRegisters(
          baked: settings.bake,
          soundReadsIt:
              _asksSound(path) &&
              settings.movieParts == MovieParts.pictureAndSound,
        );
  }

  /// [path] through its door — or, when it comes in as its PIECE
  /// ([_comesInAsAPiece]), the span cut into a file of its own and placed
  /// whole, with [path] as where it came from, then held like every carried
  /// file once it has landed. The doors behind it are the ones an untrimmed
  /// file goes through.
  Future<bool> _placeCarryingOnlyTheSpan(
    String path,
    MediaAssetKind? kind,
    _ImportTally tally,
    _FileReport fileReport,
  ) async {
    final settings = _settingsFor(path);
    if (kind == null || !_comesInAsAPiece(path, settings)) {
      return _placeThrough(path, kind, tally, settings, fileReport);
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
        settings.copyWith(inFrame: 0, outFrame: piece.frames - 1),
        fileReport,
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
  /// renderer, or the ordinary image path — the doors that count their
  /// work telling [fileReport] how far it is.
  Future<bool> _placeThrough(
    String path,
    MediaAssetKind? kind,
    _ImportTally tally,
    ImportFileSettings settings,
    _FileReport fileReport, {
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
      return _placeMovie(path, settings, fileReport, sourcePath: sourcePath);
    }
    if (importPathIsPsd(path) && settings.psd == PsdPlaceMode.expand) {
      return _expandPsd(widget.session, path, settings, tally);
    }
    if (_runKeptOf(path) case final kept?) {
      return _placeRun(path, kept, tally, fileReport);
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
        // A 100-page conte renders for seconds — the wait window's % says
        // where it is instead of looking hung.
        onRenderProgress: fileReport.rendered,
        onPageRenderFailed: fileReport.failed.add,
        spot: widget.spot,
        sourcePath: sourcePath,
      );
    }
    return _placePicture(path, settings, sourcePath: sourcePath);
  }

  /// A picture through a picture's door, as its row answers — the ordinary
  /// image path, and a run's span that keeps one picture ([_placeRun]).
  Future<bool> _placePicture(
    String picture,
    ImportFileSettings settings, {
    String? sourcePath,
  }) => widget.session.importDoors.importImageFile(
    path: picture,
    destination: settings.into,
    rasterize: settings.bake,
    fit: settings.fit,
    copyIntoProject: settings.mode == ImportFileMode.keepInside,
    inFrame: settings.inFrame,
    outFrame: settings.outFrame,
    spot: widget.spot,
    sourcePath: sourcePath,
  );

  /// [path]'s numbered run as its span keeps it ([_runKeptOf]): two
  /// pictures or more through the run's door
  /// (`ProjectImportDoors.importPictureRun`) as one layer's frames, one
  /// through a picture's ([_placePicture]) — alone, as a picture always
  /// came in, whichever picture IN and OUT stood on. Every picture is
  /// waited for as the picked one is: one that never arrives is named and
  /// left out.
  Future<bool> _placeRun(
    String path,
    List<ParsedCel> kept,
    _ImportTally tally,
    _FileReport fileReport,
  ) async {
    final folder = File(path).parent.path;
    final files = <({String path, String label})>[];
    for (final cel in kept) {
      final file = '$folder/${cel.file}';
      // Every picture of the run reads before it is placed, the law the
      // picked one already went through ([_placeFiles]).
      if (!mounted) {
        return false;
      }
      if (mediaFileName(file) != mediaFileName(path) &&
          !widget.session.projectFile.projectHoldsMediaBytes(file) &&
          await _readableForImport(file) == null) {
        final name = mediaFileName(file);
        tally.warnOf(name, AppText.strings.imUnreadable(name));
        continue;
      }
      files.add((path: file, label: cel.label));
    }
    final settings = _settingsFor(path);
    if (files.length == 1) {
      return _placePicture(files.single.path, settings);
    }
    return widget.session.importDoors.importPictureRun(
      files: files,
      name: _runOf(path)!.symbol,
      settings: settings,
      spot: widget.spot,
      onRenderProgress: fileReport.rendered,
      onCelFailed: fileReport.failed.add,
    );
  }

  /// A MOVIE's door (미디어 배치 라운드 6). What lands is the 「소리」
  /// answer — the picture, the picture with its sound on the SE rows, or
  /// the sound alone, which is also what an SE row's empty cell takes
  /// (「SE 행은 소리만 담으므로 영상의 소리만 블록이 된다」,
  /// [importMovieParts] — the cell used to be answered HERE, straight to a
  /// sound's door). A picture that bakes is hundreds of cels (「이런 무거움이
  /// 예상되는 로직은 로딩 ui 띄우도록」), so its frames are what [fileReport]
  /// counts for it — under the run's one wait window ([_runImport]).
  /// ↩️It stood behind a wait window of its own, one for every movie.
  Future<bool> _placeMovie(
    String path,
    ImportFileSettings settings,
    _FileReport fileReport, {
    String? sourcePath,
  }) => widget.session.importDoors.importVideoFile(
    path: path,
    settings: settings,
    onRenderProgress: fileReport.rendered,
    onFrameRenderFailed: fileReport.failed.add,
    spot: widget.spot,
    sourcePath: sourcePath,
  );

  /// Why a placement of the file [name] that ran and answered `false` did
  /// not land: a build with no PDF renderer says so, anything else could
  /// not be imported.
  String _placementFailure(String name, MediaAssetKind? kind) {
    if (kind == MediaAssetKind.pdf && PdfRenderService.availability != true) {
      return AppText.strings.imNoPdfRenderer(name);
    }
    return AppText.strings.imCouldNotImport(name);
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
  ///
  /// [report] counts the files the batches have landed.
  Future<void> _registerFiles(
    List<String> paths,
    _ImportTally tally,
    void Function(double) report,
  ) async {
    final pool = widget.session.mediaPool;
    final pieces = widget.session.trimmedPieces;
    report(0);
    // What the pool is handed — a piece in place of the file it was cut
    // from — and the picked file each one stands for.
    final carried = <String, String>{};
    final referenced = <String>[];
    for (final path in paths) {
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
          final name = mediaFileName(path);
          tally.warnOf(name, _placementFailure(name, kind));
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
    report(_share(carried.length, paths.length));
    await pool.importMediaFiles(referenced, copyIntoProject: false);
    tally
      ..imported += referenced.length
      ..done.addAll(referenced);
    report(1);
  }

  /// EXPAND, which reports its outcome as warnings-or-null rather than a
  /// bool: a flattened PSD has no stack, and that is not a failure worth
  /// the word "could not".
  Future<bool> _expandPsd(
    EditorSessionManager session,
    String path,
    ImportFileSettings settings,
    _ImportTally tally,
  ) async {
    final expanded = await session.importDoors.importPsdExpanded(
      path: path,
      destination: settings.into,
      fit: settings.fit,
      spot: widget.spot,
    );
    if (expanded == null) {
      final name = mediaFileName(path);
      tally.warnOf(name, AppText.strings.imPsdNoLayers(name));
      return false;
    }
    tally.warnAll(expanded);
    return true;
  }

  /// Sized as the export window is: its share of the app screen by area
  /// ([AppWindow.screenShare] — F-337, 유저 2026-10-10: 「익스포트/임포트 창이
  /// 너무 큼. 앱 화면의 절반정도로」, then 2/3). ↩️All the room the screen leaves
  /// (F-282-Q7, 유저 2026-10-09: 「출력창과 같은 법 — 화면이 남긴 자리
  /// 전체」), and before that 760 × 520, whatever the screen. The
  /// LayoutBuilder stands OUTSIDE the window: the window owns its dialog, so
  /// the screen it halves is the app's, not the dialog's.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, screen) =>
        _window(context, AppWindow.screenShare(screen)),
  );

  /// The status line — a sentence, or the warnings a run or a pick left as
  /// the button their notice opens from, the Open door's
  /// ([showImportWarnings]).
  ///
  /// 🗣️F-370-Q1 (유저 2026-10-17: 「끝 줄을 「경고 N가지」 버튼으로 — 누르면
  /// 같은 묶음 알림」). ↩️The line said the first three warnings joined by
  /// 「 · 」, and the rest were never seen.
  ///
  /// ⛔Its PLACE is always the button's (「없다가 생기는 UI 금지」): laid out
  /// whether or not there are warnings, so the line that turns into it — or
  /// back — moves nothing. ↩️It was mounted when there was something to say.
  Widget _statusLineOf(BuildContext context) {
    final said = _statusLine;
    final warnings = said is _Warnings ? said.lines : const <WarningLine>[];
    return Stack(
      key: const ValueKey<String>('import-status-line'),
      alignment: AlignmentDirectional.centerStart,
      children: [
        Visibility(
          visible: warnings.isNotEmpty,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: AppWindowActionButton(
            AppWindowAction(
              label: AppText.strings.imWarningCount(warnings.length),
              actionKey: const ValueKey<String>('import-warnings-button'),
              onPressed: () => unawaited(
                showImportWarnings(
                  context,
                  windowKey: const ValueKey<String>('import-warnings-notice'),
                  warnings: warnings,
                ),
              ),
            ),
          ),
        ),
        if (said case _Sentence(:final words))
          Text(
            words,
            key: const ValueKey<String>('import-status'),
            style: Theme.of(context).textTheme.labelSmall,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  Widget _window(BuildContext context, Size room) {
    return AppWindow(
      windowKey: const ValueKey<String>('import-dialog'),
      // The file's name goes in the TITLE in place mode: the window is
      // about one file, and the strip below already owns the word "Place"
      // for the question it asks.
      title: widget.placeOnly && _files.isNotEmpty
          ? AppText.strings.imPlaceTitle(mediaFileName(_files.first))
          : AppText.strings.imImport,
      titleIcon: Icons.download_outlined,
      width: room.width,
      height: room.height,
      scrollBody: false,
      bodyPadding: EdgeInsets.zero,
      onClose: _running ? null : () => Navigator.of(context).pop(),
      footerNote: _statusLineOf(context),
      actions: [
        AppWindowAction(
          label: AppText.strings.commonCancel,
          actionKey: const ValueKey<String>('import-cancel-button'),
          emphasis: AppWindowActionEmphasis.quiet,
          // Dead while the import is doing its OWN work — stopping a
          // half-written import would be the lie the progress window
          // refuses for saves. Alive again while a pick WAITS on somebody
          // else's bytes: nothing has been applied to that file yet, so
          // letting go costs nothing. (A run's wait is stopped from the
          // wait window it stands behind.)
          onPressed: _wait.waiting.value
              ? _wait.cancel
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

  /// The list and the picture, with a grip between them.
  ///
  /// The split is draggable because the two halves are wanted in different
  /// amounts by different work: eight option columns want the room when a
  /// batch is being set up, and the picture wants it when one file is being
  /// looked at. Until it is dragged the list takes what its columns and a
  /// readable name need; where the window cannot give it that, the list
  /// scrolls sideways at that width instead of squeezing the name.
  Widget _twoZones(BuildContext context) {
    final rows = [for (final path in _files) _tableRow(path)];
    final columns = _tableColumns();
    final preview = _preview();
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
              ImportPreview.minimumWidthIn(context),
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
            Expanded(child: preview),
          ],
        );
      },
    );
  }

  /// The picture zone: the file picked last — the first, before any is —
  /// with the ends of its span wherever they act. A picture in a numbered
  /// run is previewed as its run, and the transport's IN/OUT are the run's
  /// (F-282, 시안 ④).
  Widget _preview() {
    final path = _selected.isNotEmpty
        ? _selected.last
        : (_files.isEmpty ? null : _files.first);
    final settings = path == null
        ? const ImportFileSettings()
        : _settingsFor(path);
    final run = path == null ? null : _runFilesOf(path);
    return ImportPreview(
      key: const ValueKey<String>('import-preview'),
      session: widget.session,
      path: path,
      run: run,
      opensAsSound: path != null && _landsAsSound(path),
      inFrame: run != null ? settings.runIn : settings.inFrame,
      outFrame: run != null ? settings.runOut : settings.outFrame,
      // The ends appear wherever they act: on what gets placed, and on what
      // gets registered, which comes in as its piece ([_registerFiles]).
      // 🪦Registrations went without them until a trimmer existed
      // (2026-09-24). ⛔Not on a file the pool already holds when only
      // registering: that adds nothing, so a span there would act on
      // nothing.
      rangeEditable:
          path != null && (_placing(path) || _poolEntryFor(path) == null),
      soundPeaks: widget.session.audioConformStore.ensurePeaksFor,
      holdBytes: widget.session.projectFile.holdMediaBytes,
      frameRate: widget.session.projectSettings.projectFrameRate,
      audioSpeed: _projectAudioSpeed,
      onRangeChanged: (start, end) {
        if (path != null) {
          _keepSpan(path, start, end);
        }
      },
    );
  }

  /// [path]'s span as the preview's IN/OUT leave it: the pictures of its
  /// numbered run that come in ([ImportFileSettings.runIn]), or the trim
  /// of the file itself.
  void _keepSpan(String path, int start, int? end) => _setSettings(
    [path],
    (current) => _runOf(path) != null
        ? current.copyWith(
            runIn: start,
            runOut: end,
            clearRunOut: end == null,
          )
        : current.copyWith(
            inFrame: start,
            outFrame: end,
            clearOut: end == null,
          ),
  );

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

  /// The columns this window asks, in the order one answers the next: where
  /// the file goes decides whether it is baked, the bake whether the pool
  /// is asked how to keep it, and only a placed picture is fitted.
  ///
  /// 🚨THE PLACEMENT'S QUESTIONS STAND, every row or none (유저 2026-10-09:
  /// 「굽기/맞춤/옵션 다 보이는채로 ok. 보이게하고 지금처럼 - 이렇게
  /// 표시하면되」): a row they do not ask shows 「—」. ↩️They came and went
  /// with the window's place (09-11: 「즉 필요없는것들 안보이게 삭제해도됨」
  /// · 「이런건 예외야. 필요한 것만 보이게하려고」) — the user's own exception
  /// to the no-disappearing-UI rule, and the reason was the PSD column,
  /// meaningless beside other files (유저 10-09).
  ///
  /// ⛔Not in a window a pool's door opened ([ImportDialog.poolOnly]): every
  /// row there registers, so the questions of a placement cannot be asked
  /// at all (유저 2026-10-09: 「미디어패널의 경우엔 굽기 맞춤 옵션
  /// 안넣어도되 … 임포트는 진짜 존재할일이 없는 구조잖아. 그런건 예외로」).
  ///
  /// ⚠️A value the CONTEXT answered — a new cut's 1:1, an expanded PSD's
  /// bake, a pooled file's carry in a mixed batch — shows locked
  /// (「1:1로 고정시켜서 노출시키도록. 비활성화된상태로」).
  List<ImportColumn<Object?>> _tableColumns() {
    bool any(bool Function(String path) test) => _files.any(test);
    final placementAsked = !widget.poolOnly;
    return [
      if (_files.isNotEmpty) _intoColumn(),
      // The layer's question, wherever something is placed (「플레이스가
      // 타임라인이면 굽기열 만들기」).
      if (placementAsked) _bakeColumn(),
      // The pool's question, asked only of a file the pool has not answered
      // (「플레이스가 타임라인일땐 그냥 품기/참조인 그 열 자체를 삭제」 for
      // pooled files, 「프로젝트의 임포트 버튼 … 품기/참조열 존재하도록」
      // for new ones).
      if (any((path) => _poolEntryFor(path) == null)) _fileColumn(),
      if (placementAsked) _fitColumn(),
      // A run's, a Photoshop document's, a movie-with-sound's own question —
      // one column, each row its own (F-282).
      if (placementAsked) _optionColumn(),
    ];
  }

  /// Whether [path] places as a PICTURE — the only thing a fit or a bake
  /// means anything for. A sound goes to the SE rows; a movie is a picture
  /// here, and its sound follows the 「소리」 answer — unless that answer is
  /// the sound alone.
  bool _placesPicture(String path) => !_landsAsSound(path);

  /// Whether the 「소리」 question is this row's: a movie being placed that
  /// the conform found a sound in ([_probeMovieSound]).
  bool _asksSound(String path) => importSoundAllowed(
    kind: mediaAssetKindForPath(path),
    placing: _placing(path),
    hasSound: _movieSound[normalizedMediaPath(path)] ?? false,
  );

  /// Whether [path] lands as a SOUND on the SE rows — a sound file, or a
  /// movie whose 「소리」 answer is the sound alone ([importLandsAsSound]).
  bool _landsAsSound(String path) => importLandsAsSound(
    kind: mediaAssetKindForPath(path),
    settings: _settingsFor(path),
  );

  ImportColumn<Object?> _fileColumn() => ImportColumn<Object?>(
    id: 'file',
    label: AppText.strings.imFile,
    values: ImportFileMode.values,
    labelOf: (value) => importModeLabel(value! as ImportFileMode),
    valueOf: (path) => _settingsFor(path).mode,
    // Asked only of a row that leaves an entry — a baked one leaves none
    // (F-282-Q6: 「굽는 줄의 「파일」은 「—」」).
    appliesTo: _keepsAPoolEntry,
    enabledFor: (path, value) {
      // A pooled file in a mixed batch shows the pool's answer, locked.
      if (_poolEntryFor(path) != null) {
        return value == _settingsFor(path).mode;
      }
      return importModeAllowed(
        mode: value! as ImportFileMode,
        trimmed: _settingsFor(path).isTrimmed,
        lasting: _lasting(path),
      );
    },
    onPick: (paths, value) => _setSettings(
      paths,
      (settings) => settings.copyWith(mode: value! as ImportFileMode),
    ),
  );

  ImportColumn<Object?> _bakeColumn() => ImportColumn<Object?>(
    id: 'bake',
    label: AppText.strings.imBake,
    style: ImportColumnStyle.toggle,
    values: const [false, true],
    labelOf: (value) => importOnOffLabel(value == true),
    valueOf: (path) => _settingsFor(path).bake,
    appliesTo: (path) =>
        _placesPicture(path) &&
        importBakeAllowed(
          kind: mediaAssetKindForPath(path),
          placing: _placing(path),
        ),
    enabledFor: (path, value) =>
        value == true ||
        !importBakeLocked(
          isPsd: importPathIsPsd(path),
          placing: _placing(path),
          psd: _settingsFor(path).psd,
          spot: widget.spot,
          together: _togetherRunOf(path) != null,
        ),
    onPick: (paths, value) => _setSettings(
      paths,
      (settings) => settings.copyWith(bake: value == true),
    ),
  );

  /// THE 「옵션」 COLUMN — what only some kinds of file are asked, each on
  /// its own row: a numbered run's (the span the preview's IN/OUT keep of
  /// it, said and not asked), a Photoshop document's (its layers kept, or
  /// merged), a movie's with a sound (its picture and sound, the picture
  /// alone, the sound alone).
  ///
  /// 🗣️유저 2026-10-09 (F-282): 「psd같은 다 해당안되는것같은건 그냥 psd라는
  /// 항목이 없어지게 하고싶은데 … BG의 해당위치에 레이어 보존 레이어
  /// 합치기 이렇게 두개 두고」 · 「옵션으로. 연번/소리도 같은칸」. ↩️Three
  /// columns — 「PSD」, 「소리」, 「연번」 — each a dash on every row but its
  /// own kind's.
  ///
  /// A run's question is its own when a run's pictures are Photoshop
  /// documents too: the run comes in as its pictures, merged.
  ImportColumn<Object?> _optionColumn() => ImportColumn<Object?>(
    id: 'option',
    label: AppText.strings.imOptions,
    values: [
      PsdPlaceMode.expand,
      PsdPlaceMode.merge,
      MovieParts.pictureAndSound,
      MovieParts.picture,
      MovieParts.sound,
    ],
    valuesFor: _optionAnswers,
    labelOf: (value) => switch (value) {
      final PsdPlaceMode psd => importPsdLabel(psd),
      final MovieParts parts => importMoviePartsLabel(parts),
      _ => '',
    },
    wordOf: (path, value) => switch (value) {
      _RunSpan() => _runSpanWord(path),
      _ => null,
    },
    valueOf: _optionAnswerOf,
    appliesTo: (path) => _optionAsked(path) != null,
    enabledFor: (path, value) => switch (value) {
      // A row's frames take the merged picture (expanding makes layers,
      // and a row takes frames).
      final PsdPlaceMode psd =>
        psd == PsdPlaceMode.merge || !importPsdLocked(widget.spot),
      // What the drop's place keeps in is not an answer to take out
      // ([importMovieParts]).
      final MovieParts parts => importMovieParts(parts, widget.spot) == parts,
      _ => true,
    },
    // A header press speaks for every row: each takes the answer of its
    // own kind, and the rest let it pass.
    onPick: (paths, value) => _setSettings(
      paths,
      (settings) => switch (value) {
        final PsdPlaceMode psd => settings.copyWith(psd: psd),
        final MovieParts parts => settings.copyWith(movieParts: parts),
        _ => settings,
      },
    ),
  );

  /// What [path]'s row may answer in the 「옵션」 column: its own kind's.
  List<Object?> _optionAnswers(String path) => switch (_optionAsked(path)) {
    _OptionAsked.run => const [_RunSpan()],
    _OptionAsked.psd => const [PsdPlaceMode.expand, PsdPlaceMode.merge],
    _OptionAsked.sound => const [
      MovieParts.pictureAndSound,
      MovieParts.picture,
      MovieParts.sound,
    ],
    null => const [],
  };

  /// [path]'s answer in the 「옵션」 column, its own kind's.
  Object? _optionAnswerOf(String path) {
    final settings = _settingsFor(path);
    return switch (_optionAsked(path)) {
      _OptionAsked.run => const _RunSpan(),
      _OptionAsked.psd => settings.psd,
      _OptionAsked.sound => settings.movieParts,
      null => null,
    };
  }

  /// The span a run's row keeps, as its 「옵션」 cell says it: 「A2–A3 (2장)」
  /// for two pictures or more, the picture's own name for one.
  ///
  /// 🗣️I-76-Q1: 「「A1–A3 (3장)」 처럼 이어지는 그림의 수가 보이고」 · F-282
  /// 시안 ④: 「연번은 들어갈 범위만(A2–A3)」.
  String? _runSpanWord(String path) {
    final run = _runOf(path);
    final kept = _runKeptOf(path);
    if (run == null || kept == null) {
      return null;
    }
    String name(ParsedCel cel) => '${run.symbol}${cel.label}';
    return kept.length == 1
        ? name(kept.single)
        : AppText.strings.imRunSpan(
            name(kept.first),
            name(kept.last),
            kept.length,
          );
  }

  /// Which question the 「옵션」 column asks [path]'s row, if any — only of
  /// a placed row: registering brings the file in as it is.
  _OptionAsked? _optionAsked(String path) {
    if (!_placing(path)) {
      return null;
    }
    if (_runOf(path) != null) {
      return _OptionAsked.run;
    }
    if (importPathIsPsd(path)) {
      return _OptionAsked.psd;
    }
    return _asksSound(path) ? _OptionAsked.sound : null;
  }

  /// Where each file goes: a new layer, a new cut — the SE rows, for a
  /// sound — or the media pool alone (「미디어」, F-282: the window's
  /// 「풀 / 타임라인」 strip, one answer for the whole batch, came down to
  /// the row).
  ImportColumn<Object?> _intoColumn() {
    final spot = widget.spot;
    return ImportColumn<Object?>(
      id: 'into',
      label: AppText.strings.imInto,
      values: [
        ...ImportDestination.values,
        const _SoundOnSeRows(),
        const _IntoThePool(),
      ],
      valuesFor: _intoAnswers,
      labelOf: (value) => switch (value) {
        final ImportDestination into => importIntoLabel(into),
        final ImportLayerSpot dropped => _spotLabel(dropped),
        _SoundOnSeRows() => AppText.strings.imIntoSeRow,
        // The pool by its panel's name.
        _IntoThePool() => AppText.strings.panelMedia,
        _ => '',
      },
      // A sound's place is the SE rows' own rule (유저 2026-09-11: 「SE1부터
      // … 겹치지 않는 … 기존 SE행 … 없으면 새 SE행」) — the one placement a
      // sound has.
      valueOf: (path) => _registersOnly(path)
          ? const _IntoThePool()
          : _landsAsSound(path)
          ? (spot is SeCellSpot ? spot : const _SoundOnSeRows())
          : _answeredSpot ?? _settingsFor(path).into,
      appliesTo: (path) => true,
      enabledFor: (path, value) => switch (value) {
        // A file the pool already holds has nothing left to register.
        _IntoThePool() => widget.poolOnly || _poolEntryFor(path) == null,
        ImportDestination.activeCutLayer =>
          widget.session.activeCutOrNull != null,
        _ => true,
      },
      onPick: (paths, value) => _setSettings(
        paths,
        (settings) => switch (value) {
          _IntoThePool() => settings.copyWith(intoPool: true),
          final ImportDestination into => settings.copyWith(
            into: into,
            intoPool: false,
          ),
          _ => settings.copyWith(intoPool: false),
        },
      ),
    );
  }

  /// The drop's place when it answered the cut, shown locked; the canvas's
  /// spot is a default and leaves the cut to the 「넣을 곳」 column
  /// (pool-drop-picks-layer-or-cut, 유저 2026-09-12).
  ImportLayerSpot? get _answeredSpot {
    final spot = widget.spot;
    return spot?.answeredDestination == null ? null : spot;
  }

  /// What [path]'s row may answer in the 「넣을 곳」 column. A drop's answer
  /// is the ONE value, so the cell shows it and opens nothing — the shape
  /// every locked answer in this table has. So is a pool's door's: every
  /// row there registers.
  List<Object?> _intoAnswers(String path) {
    final spot = widget.spot;
    final answering = _answeredSpot;
    if (widget.poolOnly) {
      return const [_IntoThePool()];
    }
    if (_landsAsSound(path)) {
      return [
        if (spot is SeCellSpot) spot else const _SoundOnSeRows(),
        if (answering == null) const _IntoThePool(),
      ];
    }
    return answering == null
        ? const [...ImportDestination.values, _IntoThePool()]
        : [answering];
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
    // Never opens this window — a swap has nothing to ask (I-47) — but a
    // spot is a spot, and this one names its row.
    ReferenceSwapSpot(:final layerId) =>
      widget.session.layerById(layerId)?.name ?? '',
  };

  ImportColumn<Object?> _fitColumn() => ImportColumn<Object?>(
    id: 'fit',
    label: AppText.strings.imFit,
    values: MediaFitMode.values,
    labelOf: (value) => importFitLabel(value! as MediaFitMode),
    valueOf: (path) => _settingsFor(path).fit,
    appliesTo: (path) => _placing(path) && _placesPicture(path),
    enabledFor: (path, value) =>
        value == MediaFitMode.none ||
        !importFitLocked(_settingsFor(path), placing: _placing(path)),
    onPick: (paths, value) => _setSettings(
      paths,
      (settings) => settings.copyWith(fit: value! as MediaFitMode),
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
        // A document's copy lies in this run's room, which is nowhere the
        // person keeps anything — the bar names the document instead.
        ? (_lasting(_files.single)
              ? _files.single
              : mediaFileName(_files.single))
        : AppText.strings.imFileCount(_files.length);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        label,
        key: const ValueKey<String>('import-source-line'),
        style: theme.textTheme.bodySmall,
        overflow: TextOverflow.ellipsis,
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
          SettingsSwitchRow(
            tileKey: const ValueKey<String>('import-subfolders-toggle'),
            label: AppText.strings.imArchivedProcesses,
            value: _parseConfig.includeProcessSubfolders,
            onChanged: (value) => setState(() {
              _parseConfig = _parseConfig.copyWith(
                includeProcessSubfolders: value,
              );
              _reparseFolder(rescan: false);
            }),
          ),
          SettingsSwitchRow(
            tileKey: const ValueKey<String>('import-multicut-toggle'),
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
