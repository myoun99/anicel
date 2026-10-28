import 'dart:async' show Timer, unawaited;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../../core/progress_share.dart';
import '../../models/attached_placement.dart';
import '../../models/import/cut_folder_edits.dart';
import '../../models/import/cut_folder_parse.dart';
import '../../models/import/import_warning.dart';
import '../../models/import/picture_run.dart';
import '../../services/import/cut_folder_listing.dart';
import '../../models/canvas_size.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../models/media_asset.dart';
import '../../models/movie_clock.dart' show movieClockFor;
import '../../models/project_frame_rate.dart';
import '../../native/qa_video_decoder.dart' show QaVideoInfo;
import '../../services/import/import_layer_spot.dart';
import '../../services/import/media_import_planner.dart';
import '../../services/media/media_pixel_size.dart';
import '../../services/media/movie_bytes.dart' show readHeldMovieInfo;
import '../../services/media/video_decode_worker.dart'
    show videoDecodeBackend;
import '../../services/pdf/pdf_render_service.dart';
import '../../services/persistence/folder_grant.dart'
    show FolderGrant, FolderPicker, MaterializeCancelled;
import '../../services/persistence/provider_documents.dart';
import '../dialogs/app_progress_dialog.dart';
import '../dialogs/cloud_wait.dart';
import '../editor_session_manager.dart';
import '../timeline/layer_label_controls.dart'
    show
        LayerAttachArrowCell,
        LayerMarkChip,
        LayerMarkEdit,
        layerKindDisplayName,
        layerKindIcon;
import '../timeline/layer_rail_columns.dart'
    show
        LayerRailLeadingSlot,
        LayerTypeButton,
        layerRailLeadingCells,
        layerRailLeadingWidthTo;
import 'import_file_settings.dart';
import 'import_file_table.dart';
import 'import_preview.dart';
import 'import_warnings_notice.dart';
import 'movie_rate_dialog.dart';
import '../text/byte_size_label.dart';
import '../text/pixel_size_label.dart';
import '../widgets/app_window.dart';
import '../widgets/dock_edge_splitter.dart';
import '../widgets/panel_flyout.dart'
    show PanelFlyoutChoice, PanelFlyoutValueChoices, showPanelFlyout;
import '../widgets/pill_strip.dart' show PillItem, PillStrip;
import '../text/model_vocabulary.dart';

/// The import window (§6-z21): ONE window for every import, defaults
/// filled so the simple case is a single Enter. It picks nothing itself:
/// what the one door hands it comes in ([picked] — the menu's 「파일
/// 열기」 and 「폴더 열기」, a drop on the window, the media panel's ＋,
/// the viewer's 「미디어에 등록」), and so do files the app already holds
/// ([initialPaths]). Its table says what each source becomes, a row a
/// thing: a file, or a layer of the cut a cut FOLDER lands as — and a row
/// for what a folder leaves out, so nothing exits silently.
///
/// ↩️It had a 「파일…」 and a 「컷 폴더…」 of its own, and the menu's
/// 「가져오기/배치…」 opened it on nothing to press them (F-282, 유저
/// 2026-10-09: 「열기랑 임포트랑 되도록 하나로」).
///
/// v1 zones: source line → table | preview → action bar. The preset rail
/// and queue drawers of the export skeleton join when parser presets get
/// their store.
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

/// What one file's door tells back while it runs: how far it is, what it is
/// doing, and the pages or frames it could not render. They go down the
/// same doors together, so they are handed down as one.
///
/// 🗣️F-494 (유저 2026-10-28: 「하고있는 과정을 투명하게 … 퍼센테이지에
/// 반영하면서」): the file's share is split among the [_Stretch]es it goes
/// through, in the order they run, each named on the window's line while
/// it reports. Which of them a file goes through is its door's to find out
/// — a pool that already holds the file carries nothing — so each takes an
/// even share of what is left among the stretches that can still come
/// ([pieceShare]'s law, for pieces not known ahead), and one that never
/// starts leaves its share to the next.
class _FileReport {
  _FileReport(this._within, this._say);

  final void Function(double) _within;
  final void Function(String step) _say;

  /// The pages (a PDF) or frames (a movie) that would not render.
  final List<int> failed = [];

  _Stretch? _now;
  double _from = 0;
  double _to = 0;

  /// [fraction] of the file's piece cut ([TrimmedPieces.cut]).
  void cutting(double fraction, MediaAssetKind kind) =>
      _in(_Stretch.cut, _cuttingStep(kind), fraction);

  /// [fraction] of the file's bytes held ([MediaPool.holdCarriedBytes]).
  void carrying(double fraction) =>
      _in(_Stretch.carry, AppText.strings.imStepCarrying, fraction);

  /// [done] of the file's [total] cels rasterized.
  void rendered(int done, int total) => _in(
    _Stretch.rasterize,
    AppText.strings.imStepRasterizing,
    doneShare(done, total),
  );

  void _in(_Stretch stretch, String step, double fraction) {
    if (stretch != _now) {
      _now = stretch;
      _from = _to;
      _to = _from + (1 - _from) / (_Stretch.values.length - stretch.index);
      _say(step);
    }
    _within(runShare(fraction, from: _from, to: _to));
  }
}

/// What a placed file goes through that takes long enough to name, in the
/// order its door runs them ([_FileReport]).
enum _Stretch { cut, carry, rasterize }

/// What the pool's batches tell back while they run ([_registerFiles]).
///
/// F-282-Q1 (유저 2026-10-08: 「파일 수와 각 파일의 진행 … 으로 %를 센다」):
/// the kept files hold their count's share of the pool's, the linked ones
/// the rest. 🗣️F-494: within the kept share, each piece cut and then the
/// holding are even stretches, each named on the window's line while it
/// reports — the pieces known ahead, as [_FileReport]'s stretches are not.
class _PoolReport {
  _PoolReport(
    this._report,
    this._say, {
    required double keptShare,
    required int cuts,
  }) : _keptShare = keptShare,
       _stretches = cuts + 1;

  final void Function(double) _report;
  final void Function(String step) _say;
  final double _keptShare;
  final int _stretches;

  /// How far the [index]th piece, a [kind]'s, is cut.
  void Function(double fraction) cut(int index, MediaAssetKind kind) =>
      _stretch(_cuttingStep(kind), index);

  /// How far the kept files are held.
  void Function(double fraction) get holding =>
      _stretch(AppText.strings.imStepCarrying, _stretches - 1);

  /// The kept files are in — said outright, for a batch the pool already
  /// held, which holds nothing and says nothing.
  void kept() => _report(_keptShare);

  void Function(double fraction) _stretch(String step, int index) =>
      (fraction) {
        _say(step);
        _report(
          runShare(
            pieceShare(fraction, index: index, count: _stretches),
            from: 0,
            to: _keptShare,
          ),
        );
      };
}

/// What cutting a [kind]'s piece is called ([TrimmedPieces.cut]): a movie's
/// encoded again, another kind's span written out.
String _cuttingStep(MediaAssetKind kind) => kind == MediaAssetKind.video
    ? AppText.strings.imStepRecoding
    : AppText.strings.imStepWritingSpan;

/// The wait window's running line for a run: the cloud's word while a file
/// is on its way ([CloudWait]), the stretch under way's otherwise.
class _RunningLine implements ValueListenable<String> {
  _RunningLine(this._cloud, this._step)
    : _either = Listenable.merge([_cloud, _step]);

  final ValueListenable<String> _cloud;
  final ValueListenable<String> _step;
  final Listenable _either;

  @override
  String get value => _cloud.value.isEmpty ? _step.value : _cloud.value;

  @override
  void addListener(VoidCallback listener) => _either.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _either.removeListener(listener);
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
  PictureRun run,
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

/// The Into answer of what a cut folder leaves out: nowhere — said on its
/// row ([_FolderLeftOutRow]), so nothing goes silently.
final class _LeftOut {
  const _LeftOut();

  /// What its popup row would be keyed by.
  @override
  String toString() => 'left-out';
}

/// The Into answer of a cut folder's correction riding its symbol's own
/// layer: wherever that goes, as its attach row (🗣️F-429-Q5: 「기준
/// 행(A)을 따라감」 · 「기본값 따라가고 넣을곳 컷일때도 기본값대로 따라가게.
/// 물론 넣을곳 변경가능」) — worded on its row as the timeline's drag words
/// an attach ([_ImportDialogState._attachWord]).
final class _WithItsBase {
  const _WithItsBase();

  /// What its popup row is keyed by.
  @override
  String toString() => 'with-its-base';
}

/// A row of the table that stands for no one file of its own: what a cut
/// FOLDER brings ([CutFolderParseResult]) — a symbol's layer or a picture,
/// each a layer it lands — and the row naming what it leaves out.
///
/// 🗣️F-429 (유저 2026-10-21): 「일반 임포트창 거의 그대로」 — a folder's
/// layers are rows of the window every file comes in through, asked its
/// columns. ↩️A folder had a table of its own that read the parse out, and
/// a column of knobs answering for the whole folder at once.
sealed class _FolderRow {
  const _FolderRow();
}

/// A symbol's own layer, or a correction riding it ([ParsedCelLayer]).
final class _FolderLayerRow extends _FolderRow {
  const _FolderLayerRow(this.layer);

  final ParsedCelLayer layer;
}

/// A `_BG`/`_BOOK` picture ([ParsedPicture]).
final class _FolderPictureRow extends _FolderRow {
  const _FolderPictureRow(this.picture);

  final ParsedPicture picture;
}

/// What the folder leaves out, named on one row: what its parse excluded,
/// the sheets and work files the import does not read, and what was handed
/// in beside it.
final class _FolderLeftOutRow extends _FolderRow {
  const _FolderLeftOutRow(this.names);

  final List<String> names;
}

/// What a column asks the rows a cut folder brings ([_FolderRow]) where the
/// [ImportColumn] it rides asks a file: the answers a row is asked — none,
/// and its cell is a dash; one it can give, and it stands locked — the one
/// it gives, and what a pick changes.
class _FolderColumn {
  const _FolderColumn({
    required this.answers,
    required this.valueOf,
    this.enabledFor,
    this.wordOf,
    this.onPick,
  });

  final List<Object?> Function(_FolderRow row) answers;
  final Object? Function(_FolderRow row) valueOf;

  /// Whether [row] can give an answer it is asked — every one, when null.
  final bool Function(_FolderRow row, Object? value)? enabledFor;
  final String? Function(_FolderRow row, Object? value)? wordOf;
  final void Function(Iterable<_FolderRow> rows, Object? value)? onPick;
}

/// The left-out row's key in the table.
const _leftOutKey = 'folder-left-out';

/// The table's key for the folder's row kept by [rowKey] — no file's path
/// begins so.
String _folderRowKey(String rowKey) => 'folder:$rowKey';

/// What the preview shows of a row: the file, the pictures it pages through
/// when it brings several, whether it opens as a sound, and the span —
/// which the preview's IN/OUT change only where [editable].
typedef _Shown = ({
  String? path,
  List<String>? run,
  bool sound,
  int inFrame,
  int? outFrame,
  bool editable,
});

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
      ((_settings[path] ?? _seed).intoPool && _poolAnswers(path));

  /// Whether 「미디어」 is still an answer for [path]: a file the pool does
  /// not hold — one it holds has nothing left to register, so it is placed
  /// (09-11, above) — or a file a cut folder lists, which stays where the
  /// pool has it: a folder brought in again places nothing it was not asked
  /// to (F-429-Q4: its media rows start on 「미디어」), and the pool takes no
  /// file twice ([MediaPool.importMediaFiles]).
  bool _poolAnswers(String path) =>
      _folder != null || _poolEntryFor(path) == null;

  /// Whether [path]'s row is placed somewhere — every question but the
  /// pool's changes meaning with it, per row.
  bool _placing(String path) => !_registersOnly(path);

  /// Whether a placement has a cut to land a new layer in: the cut a folder
  /// lands as — made, and opened, before anything else of the press is
  /// placed ([_importAll]) — or the open one.
  bool get _hasCutToPlaceIn =>
      _folderLandsAsOneCut || widget.session.activeCutOrNull != null;

  /// Whether the folder lands as ONE cut — 넣을 곳 「컷」, every row of it a
  /// new layer there — rather than each row where 「커스텀」 sends it
  /// ([CutFolderEdits.custom]).
  bool get _folderLandsAsOneCut => _folder != null && !_folderEdits.custom;

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
      hasActiveCut: _hasCutToPlaceIn,
      lasting: _lasting(path),
      spot: widget.spot,
      runLength: _runOf(path)?.pictures.length,
    ).copyWith(
      intoPool: _registersOnly(path),
      // While a cut folder lands as one cut, every placement is a new layer
      // of it — a media row's too (F-429-Q4: 「새 레이어 · 미디어 중에서
      // 고릅니다」); under 「커스텀」 a media row is asked what every file is.
      into: _folderLandsAsOneCut ? ImportDestination.activeCutLayer : null,
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
      .mediaAssetByPath(path);

  /// How this window names [path] — in its title, its rows and the
  /// warnings it gives about the file: as the pool shows it (F-376).
  String _shownName(String path) =>
      widget.session.repository.requireProject().shownNameOfMedia(path);

  /// What [says] of the file at [path], put on [tally] — the file named
  /// as this window names it ([_shownName]).
  void _warnOf(
    _ImportTally tally,
    String path,
    String Function(String name) says,
  ) {
    final name = _shownName(path);
    tally.warnOf(name, says(name));
  }

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

  /// The file names of each folder a picked picture lives in, read ONCE.
  final Map<String, List<String>?> _folderNames = {};

  /// Each listed picture's run by its names alone ([pictureRunOf]), by its
  /// pool key — before a size has been asked of it.
  final Map<String, PictureRun?> _namedRuns = {};

  /// Each listed picture's run once every picture of it is measured — by
  /// its pool key, as [_namedRuns] — which nothing changes after.
  final Map<String, PictureRun?> _measuredRuns = {};

  /// [path]'s run as its folder names it ([pictureRunOf]) — null for a file
  /// that is no picture, or runs with none.
  PictureRun? _namedRunOf(String path) {
    if (mediaAssetKindForPath(path) != MediaAssetKind.image) {
      return null;
    }
    return _namedRuns.putIfAbsent(normalizedMediaPath(path), () {
      final folder = File(path).parent.path;
      final names = _folderNames.putIfAbsent(folder, () {
        try {
          return [
            for (final entry in Directory(folder).listSync())
              if (entry is File) mediaFileName(entry.path),
          ];
        } on FileSystemException {
          return null;
        }
      });
      return names == null
          ? null
          : pictureRunOf(
              mediaFileName(path),
              names,
              folderName: mediaParentFolderName(path),
            );
    });
  }

  /// The numbered run [path] is part of, when its row is placed — null for
  /// a file in none, and for one whose pictures are still being measured
  /// ([_probeRun]): the run stops where the size changes ([sameSizeRunOf]).
  ///
  /// 🗣️I-76 (유저 2026-10-06): 「A1 임포트하면 A2,A3같은 파일들 인식해서」 ·
  /// F-392 (10-17): 「그냥 A면 이라는거 없이 숫자면 연속되도록」 · 「중간에
  /// 해상도 다른거만나면 항목으로서 독립시키도록」.
  PictureRun? _runOf(String path) {
    if (!_placing(path)) {
      return null;
    }
    final key = normalizedMediaPath(path);
    if (_measuredRuns.containsKey(key)) {
      return _measuredRuns[key];
    }
    final named = _namedRunOf(path);
    if (named == null) {
      return null;
    }
    final folder = File(path).parent.path;
    final sizeKeys = {
      for (final picture in named.pictures)
        picture.file: normalizedMediaPath('$folder/${picture.file}'),
    };
    if (!sizeKeys.values.every(_pixelSizes.containsKey)) {
      return null;
    }
    return _measuredRuns[key] = sameSizeRunOf(
      named,
      mediaFileName(path),
      (file) => _pixelSizes[sizeKeys[file]],
    );
  }

  /// The pictures of [path]'s run its span keeps — the run's IN/OUT,
  /// picked on the preview ([ImportFileSettings.runIn]) — or null for a
  /// file in none.
  List<RunPicture>? _runKeptOf(String path) {
    final run = _runOf(path);
    if (run == null) {
      return null;
    }
    final span = importRunSpan(_settingsFor(path), run.pictures.length);
    return run.pictures.sublist(span.first, span.last + 1);
  }

  /// [path]'s run when its span keeps two pictures or more: they come in as
  /// one layer's frames. One comes in alone ([_placeRun]).
  PictureRun? _togetherRunOf(String path) =>
      (_runKeptOf(path)?.length ?? 0) > 1 ? _runOf(path) : null;

  /// The layer [path]'s row brings of its run ([_RunLayer]) — null for a
  /// row that brings no run of two pictures or more ([_togetherRunOf]).
  _RunLayer? _runLayerOf(String path) {
    final run = _togetherRunOf(path);
    if (run == null) {
      return null;
    }
    final settings = _settingsFor(path);
    final span = importRunSpan(settings, run.pictures.length);
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
        : [for (final picture in run.pictures) '$folder/${picture.file}'];
  }

  /// What the window asks of a file the moment it is listed: whether its
  /// movie has a sound ([_movieSound]), its size in pixels ([_pixelSizes]),
  /// and the sizes of the pictures it runs with ([_probeRun]).
  void _probe(String path) {
    _probeMovieSound(path);
    _readPixelSize(path);
    _probeRun(path);
  }

  /// The size of every picture [path] runs with by name ([_namedRunOf]),
  /// asked in the one line of reads — its run stops where the size changes
  /// ([_runOf]), and a press of Import waits for them ([_placeFiles]).
  void _probeRun(String path) {
    final folder = File(path).parent.path;
    for (final picture in _namedRunOf(path)?.pictures ?? const <RunPicture>[]) {
      _readPixelSize(
        '$folder/${picture.file}',
        wanted: () => _files.contains(path),
      );
    }
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

  /// Each listed file's size at 1:1 once it is read ([readMediaPixelSize]),
  /// and each picture's it runs with ([_probeRun]), by pool key — null for
  /// one that has none, a sound, or that could not be read. A file not here
  /// is still waiting its turn (F-375).
  final Map<String, CanvasSize?> _pixelSizes = {};

  /// The reads, ONE AT A TIME in the order the files were listed: a
  /// picture's header is read off its whole file in memory, so a batch read
  /// at once would hold every file of it together.
  Future<void> _pixelSizeReads = Future<void>.value();

  /// [path]'s size read in its turn, while [wanted] — while it is listed,
  /// unless a caller says otherwise.
  void _readPixelSize(String path, {bool Function()? wanted}) {
    final key = normalizedMediaPath(path);
    _pixelSizeReads = _pixelSizeReads.then((_) async {
      if (!mounted ||
          _pixelSizes.containsKey(key) ||
          !(wanted?.call() ?? _files.contains(path))) {
        return;
      }
      final kind = mediaAssetKindForPath(path);
      final size = kind == null
          ? null
          : await readMediaPixelSize(
              kind,
              path,
              widget.session.projectFile.holdMediaBytes,
            );
      if (mounted) {
        _pixelSizes[key] = size;
        _showPixelSizesSoon();
      }
    });
  }

  /// The sizes read since the rows last showed them come up together, at
  /// most every [_pixelSizesShownEvery]: a batch read one by one would
  /// otherwise rebuild the whole window once a file — the window whose
  /// every press was late (F-373).
  Timer? _pixelSizesShowing;
  static const _pixelSizesShownEvery = Duration(milliseconds: 200);

  void _showPixelSizesSoon() {
    _pixelSizesShowing ??= Timer(_pixelSizesShownEvery, () {
      _pixelSizesShowing = null;
      if (mounted) {
        setState(() {});
      }
    });
  }

  /// [path]'s row word for its size: nothing until it is read, a dash for
  /// a file with none.
  String _resolutionOf(String path) {
    final key = normalizedMediaPath(path);
    if (!_pixelSizes.containsKey(key)) {
      return '';
    }
    final size = _pixelSizes[key];
    return size == null ? '—' : pixelSizeLabel(size.width, size.height);
  }

  /// The project's accumulated audio pull — a movie's preview counts its
  /// frames on the sound's clock, as its placement does.
  ({int numerator, int denominator}) get _projectAudioSpeed =>
      widget.session.repository.requireProject().audioSpeed;

  CutFolderParseResult? _parsed;

  /// What the window changed of a cut folder's own answers — each row's
  /// colour label, kind and fit ([CutFolderEdits]); the cut's name is
  /// [_cutName]'s.
  ///
  /// ↩️The folder's fit and its media's carry were one answer each for the
  /// whole folder, in a column of their own; the fit is each row's now, and
  /// the media are rows asked what every file is asked (F-429-Q4).
  CutFolderEdits _folderEdits = const CutFolderEdits();

  /// The cut's name: filled with the one the folder gives and changed as
  /// typed (🗣️F-429: 「컷 이름 읽어오는 거 등 규칙에 맞춰서 입력은 해두되 그거
  /// 사용자가 변경할수있게」) — left empty, the folder's own again.
  final TextEditingController _cutName = TextEditingController();

  /// The rows a cut folder brings that are no file of their own
  /// ([_FolderRow]), by their key in the table, in the TIMELINE's order —
  /// the top layer first (유저 F-429: 「순서도 타임라인에맞춰서 일반적으로
  /// A레이어가 밑이고 B가 위니」).
  Map<String, _FolderRow> _folderRows = const {};

  /// What the folder leaves out, said on the table's last row — null when it
  /// leaves nothing out.
  _FolderLeftOutRow? _leftOut;

  /// Whether the folder's cut has landed: its rows leave the table as a file
  /// that landed leaves it ([_runImport]), and a second press brings in only
  /// what is still listed.
  bool _folderLanded = false;

  /// The folder's row at [key] — null for a file's.
  _FolderRow? _folderRowAt(String key) =>
      _folderRows[key] ?? (key == _leftOutKey ? _leftOut : null);

  /// Every row of the table by its key, in its order: the folder's layers,
  /// the files, and what the folder leaves out.
  List<String> get _rowKeys => [
    ..._folderRows.keys,
    ..._files,
    if (_leftOut != null) _leftOutKey,
  ];
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
        _probe(path);
      }
    }
    final dropped = _folder;
    if (dropped != null) {
      // A folder came with loose files: the folder is the import, the
      // files are listed as ignored (one window, one source shape).
      _ignoredSources.addAll(_files);
      _files.clear();
      _readFolder();
    }
  }

  @override
  void dispose() {
    _pixelSizesShowing?.cancel();
    // A copy still on its way is stopped: nothing is left to take it.
    _wait.cancel();
    _wait.status.removeListener(_waitChanged);
    _wait.waiting.removeListener(_waitChanged);
    _wait.dispose();
    _step.dispose();
    _cutName.dispose();
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
        if (_parsed case final parsed?) {
          _leftOut = _leftOutOf(parsed);
        }
      } else {
        _files.addAll(paths);
      }
    });
    paths.forEach(_probe);
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

  void _readFolder() {
    final folder = _folder;
    if (folder == null) {
      _parsed = null;
      return;
    }
    final directory = Directory(folder);
    if (!directory.existsSync()) {
      _parsed = null;
      _status = _Sentence(AppText.strings.imFolderGone);
      return;
    }
    final List<CutFolderEntry> entries;
    try {
      // SYNCHRONOUS where the import door's walk is asynchronous: the pick
      // that names the folder reads it inside its own frame. The walk is
      // each caller's; what a listed entity MEANS is shared.
      entries = cutFolderEntriesFrom(
        folder,
        directory.listSync(recursive: true),
      );
    } on FileSystemException catch (error) {
      _parsed = null;
      _status = _Sentence(AppText.strings.imFolderUnreadable(error.message));
      return;
    }
    final parsed = _parsed = parseCutFolderAt(folder, entries: entries);
    _takeFolderRows(folder, parsed);
  }

  /// [parsed] as the table lists it: its layers in the timeline's order
  /// ([_folderRows]); its timesheet scans and reference movie as FILES,
  /// asked what every file is asked and starting on the pool, where the
  /// folder import always put them (🗣️F-429-Q4: 「미디어 행만 넣을 곳을 고를
  /// 수 있게」 — 처음엔 미디어); and what it leaves out ([_leftOut]). What it
  /// said of itself is the status line's, as a run's warnings are.
  void _takeFolderRows(String folder, CutFolderParseResult parsed) {
    _cutName.text = _folderEdits.nameOf(parsed);
    _folderRows = {
      // The planner stands a folder's pictures at the bottom and its layers
      // over them in the parse's order — read top-down, as the timeline is.
      for (final layer in parsed.layers.reversed)
        _folderRowKey(layer.rowKey): _FolderLayerRow(layer),
      for (final picture in parsed.pictures.reversed)
        _folderRowKey(picture.rowKey): _FolderPictureRow(picture),
    };
    for (final MapEntry(:key, value: row) in _folderRows.entries) {
      _readPixelSize(
        _folderFilesOf(row).first,
        wanted: () => _folderRows.containsKey(key),
      );
    }
    // By name, as a file dialog lists them: the walk's order is the
    // platform's, and the same folder reads the same on every machine.
    final media = [
      for (final reference in parsed.references)
        if (_isMediaRow(reference.kind)) reference.file,
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final file in media) {
      final path = cutFolderFilePath(folder, file);
      _files.add(path);
      _settings[path] = _seed.copyWith(intoPool: true);
      _probe(path);
    }
    _leftOut = _leftOutOf(parsed);
    if (parsed.warnings.isNotEmpty) {
      _status = _Warnings([
        for (final warning in parsed.warnings)
          warning.partsFor(AppText.language),
      ]);
    }
  }

  /// Whether a folder's reference of [kind] is a FILE of the window's —
  /// a timesheet scan or the reference movie, which the folder import always
  /// registered; the timing sheets and work files it never read are left
  /// out.
  static bool _isMediaRow(ParsedReferenceKind kind) =>
      kind == ParsedReferenceKind.timesheetScan ||
      kind == ParsedReferenceKind.movie;

  /// The row naming what [parsed] leaves out, each once — null when it
  /// leaves nothing: a file by its name, what lies inside a folder by the
  /// folder's (「_old/」) — a folder left out whole is its files' folder —
  /// the sheets and work files the import does not read, and what was handed
  /// in beside the folder.
  _FolderLeftOutRow? _leftOutOf(CutFolderParseResult parsed) {
    final names = {
      for (final exclusion in parsed.excluded) _topNameOf(exclusion.path),
      for (final reference in parsed.references)
        if (!_isMediaRow(reference.kind)) _topNameOf(reference.file),
      for (final source in _ignoredSources) mediaFileName(source),
    };
    final shown = [
      for (final name in names)
        if (!names.contains('$name/')) name,
    ];
    return shown.isEmpty ? null : _FolderLeftOutRow(shown);
  }

  /// [relativePath]'s first name — with its slash when it is a folder's.
  static String _topNameOf(String relativePath) {
    final slash = relativePath.indexOf('/');
    return slash < 0 ? relativePath : relativePath.substring(0, slash + 1);
  }

  bool get _canImport => !_busy && (_files.isNotEmpty || _folderToLand != null);

  /// The folder whose cut the press lands — null when there is none, it
  /// could not be read, or its cut has landed already ([_folderLanded]).
  String? get _folderToLand =>
      _parsed == null || _folderLanded ? null : _folder;

  /// Importing, or waiting on a document's bytes after a pick — either way
  /// the sources are not to be changed or run from under it.
  bool get _busy => _running || _wait.waiting.value;

  /// The wait for somebody else's bytes ([_readableForImport]) — after a
  /// pick, said on this window's status line with its Cancel as the stop;
  /// during a run, said on the wait window the run stands behind, with
  /// ITS Cancel (F-282-Q1). Waiting is the only stretch of a run that can
  /// honestly be stopped, and a stop gives up the one file waited for.
  final CloudWait _wait = CloudWait();

  /// The stretch of the run under way, as the wait window's line names it
  /// (🗣️F-494, 유저 2026-10-28: 「하고있는 과정을 투명하게 보여줬으면함」) —
  /// empty between stretches, where the window says 「임포트하는 중」.
  final ValueNotifier<String> _step = ValueNotifier<String>('');

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
    if (!_canImport) {
      return;
    }
    // 🗣️F-405 (유저 2026-10-19: 「여러파일 임포트/배치시 레이어 하나당
    // 한번언두인데 임포트한거 한번에 언두하도록」): what one press of Import
    // writes is ONE undo step — every file it registers or places, and the
    // project rate it took for a movie when it asked. The doors write a
    // file at a time across many events, so the press folds them once it
    // is over, as a sweep across rows does ([HistoryGestures.foldSince]).
    final history = widget.session.historyManager.gestures;
    final pressed = history.mark;
    if (!await _answerMovieRates() || !mounted) {
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
    final finished = await _importBehindTheWaitWindow(tally);
    // What landed is folded however the run ended — a batch that stopped
    // part-way is still one press.
    history.foldSince(pressed, 'Import');
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
      if (tally.done.contains(_folder)) {
        _folderHasLanded();
      }
      _status = tally.warnings.isEmpty
          ? _Sentence(AppText.strings.imStatusNothing)
          : _Warnings(tally.warnings);
    });
  }

  /// The folder's rows leave the table once its cut has landed, as a file
  /// that landed leaves it.
  void _folderHasLanded() {
    _folderLanded = true;
    _selected.removeWhere((key) => _folderRowAt(key) != null);
    _folderRows = const {};
    _leftOut = null;
  }

  /// Every file of the press, imported into [tally] — false when this
  /// window went away part-way ([_importAll]).
  ///
  /// 🗣️유저 2026-10-08 (F-282-Q1, 「굽기 · 저장과 같은 기다림 창에」): the
  /// whole run stands behind the app's one wait window. Its % counts the
  /// files, and the one being placed as far as that one says (a movie's
  /// frames, a PDF's pages, a folder's scans); a cloud file's wait is its
  /// status line, and its Cancel gives that file up. ↩️Only a movie that
  /// baked stood behind one — a window of its own for every movie — and
  /// the rest said 「임포트하는 중…」 on this window's status line.
  Future<bool> _importBehindTheWaitWindow(_ImportTally tally) =>
      runWithAppProgress<bool>(
        context: context,
        title: AppText.strings.imImport,
        titleIcon: Icons.download_outlined,
        runningLabel: AppText.strings.imStatusImporting,
        doneLabel: AppText.strings.imStatusDone,
        windowKey: const ValueKey<String>('import-progress-dialog'),
        runningStatus: _RunningLine(_wait.status, _step),
        onCancel: _wait.cancel,
        cancelLive: _wait.waiting,
        task: (report) => _importAll(tally, report),
      );

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
  /// ([readHeldMovieInfo]) — null when it does not open.
  Future<QaVideoInfo?> _movieInfoOf(String path) => readHeldMovieInfo(
    videoDecodeBackend,
    widget.session.projectFile.holdMediaBytes,
    path,
  );

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
      // Each row as its 넣을 곳 says: a folder's cut first — what its media
      // rows place lands in it, the cut its landing opens — then the files
      // that only register, then the ones that are placed. One count over
      // all of it: a folder's scans, and a file each.
      final folder = _folderToLand;
      final registering = _files.where(_registersOnly).toList();
      final placing = _files.where(_placing).toList();
      final scans = folder == null ? 0 : _folderScanCount;
      final total = scans + _files.length;
      final landed = doneShare(scans, total);
      final registered = doneShare(scans + registering.length, total);
      void Function(double) stretch(double from, double to) =>
          (fraction) => report(runShare(fraction, from: from, to: to));
      if (folder != null &&
          !await _importCutFolder(folder, tally, stretch(0, landed))) {
        // Its media rows place into the cut it would have made.
        return true;
      }
      if (registering.isNotEmpty) {
        // The pool: every kind registers, movies included. Two batches
        // rather than one, because carrying is a per-file answer and the
        // registration verb takes one flag for the batch it is given.
        await _registerFiles(registering, tally, stretch(landed, registered));
      }
      if (placing.isNotEmpty) {
        // ⛔The `await` is NOT redundant: `return _placeFiles(tally)`
        // hands the future to the caller and this try never sees it
        // fail, so a throw part-way through the batch would escape as an
        // unhandled async error and leave the spinner running forever.
        return await _placeFiles(placing, tally, stretch(registered, 1));
      }
    } on Object catch (error) {
      tally.warn('$error');
    }
    return true;
  }

  /// The folder's cut, landed as the window answered it — false when the
  /// folder could not be read. [report] counts its scans.
  Future<bool> _importCutFolder(
    String folder,
    _ImportTally tally,
    void Function(double) report,
  ) async {
    final folderWarnings = await widget.session.cutFolderDoor.importCutFolder(
      folderPath: folder,
      edits: _folderEditsToRun,
      onProgress: (baked, total) => report(doneShare(baked, total)),
    );
    if (folderWarnings == null) {
      tally.warn(AppText.strings.imCutFolderUnreadable);
      return false;
    }
    tally
      ..imported += 1
      ..done.add(folder)
      ..warnAll(folderWarnings);
    return true;
  }

  /// The folder's answers as the window holds them now — the cut named as
  /// typed, or as the folder names it when the field is left empty.
  CutFolderEdits get _folderEditsToRun {
    final typed = _cutName.text.trim();
    return _folderEdits.copyWith(cutName: typed.isEmpty ? null : typed);
  }

  /// How many files the folder's cut bakes — its share of the run's %, as
  /// its door counts them going ([CutFolderImportDoor.importCutFolder]).
  int get _folderScanCount => _folderRows.values.fold(
    0,
    (count, row) => count + _folderFilesOf(row).length,
  );

  /// Whether the file at [path] reads for a placement — said in [tally],
  /// of its name, when it does not.
  ///
  /// A PLACEMENT reads the file, so this is where the picked path has to
  /// become a path that reads — the same law the two open doors go
  /// through. A cloud file arrives here as a placeholder and would
  /// otherwise fail as if it were corrupt.
  ///
  /// 🐞F-282 ④ (유저 2026-10-04: 「동영상을 잘라내서 임포트시,
  /// 미디어풀에 등록되는데, 그걸 다시 타임라인에 배치하려하면 파일을
  /// 읽지 못했다고 뜸」): bytes the PROJECT holds are not read from the
  /// file — every door reads the carry first — so there is no file to wait
  /// for. A piece cut on import and a voice take never had one; a carried
  /// file's original may be gone.
  Future<bool> _readsForPlacement(String path, _ImportTally tally) async {
    if (widget.session.projectFile.projectHoldsMediaBytes(path) ||
        await _readableForImport(path) != null) {
      return true;
    }
    _warnOf(tally, path, AppText.strings.imUnreadable);
    return false;
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
    // The window counts from its first frame (F-282-Q1) — the wait below
    // included, for nothing is placed until it is over.
    report(0);
    // A run is what its measured pictures say ([_runOf]), so the press
    // waits out the reads the rows asked for ([_probeRun]).
    await _pixelSizeReads;
    if (!mounted) {
      return false;
    }
    // A run two of its own pictures were picked from comes in once when
    // their rows would bring the same layer of it ([_RunLayer]) — the
    // second row is already in. A row that keeps another span, or puts it
    // elsewhere, brings what its own cells say.
    final runsPlaced = <_RunLayer>{};
    for (final (index, path) in paths.indexed) {
      void within(double fraction) =>
          report(pieceShare(fraction, index: index, count: count));
      within(0);
      final run = _runLayerOf(path);
      if (run != null && runsPlaced.contains(run)) {
        tally
          ..imported += 1
          ..done.add(path);
        continue;
      }
      final kind = mediaAssetKindForPath(path);
      if (!await _readsForPlacement(path, tally)) {
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
    final fileReport = _FileReport(within, (step) => _step.value = step);
    final bool ok;
    try {
      ok = await _placeCarryingOnlyTheSpan(path, kind, tally, fileReport);
    } on Object {
      _warnOf(tally, path, AppText.strings.imCorrupt);
      return;
    } finally {
      _step.value = '';
    }
    final failed = fileReport.failed.length;
    if (failed > 0) {
      // A PDF's are pages; a movie's — and a numbered run's — are frames.
      _warnOf(
        tally,
        path,
        (name) => kind == MediaAssetKind.pdf
            ? AppText.strings.imPagesFailed(name, failed)
            : AppText.strings.imFramesFailed(name, failed),
      );
    }
    if (ok) {
      tally.imported += 1;
      tally.done.add(path);
      return;
    }
    _warnOf(tally, path, (name) => _placementFailure(name, kind));
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
    // Named from its start: a sound's or a page range's cut says nothing
    // until it is done (F-494).
    fileReport.cutting(0, kind);
    final piece = await pieces.cut(
      path,
      kind,
      inFrame: settings.inFrame,
      outFrame: settings.outFrame,
      onProgress: (fraction) => fileReport.cutting(fraction, kind),
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
        onCarrying: fileReport.carrying,
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
        onCarrying: fileReport.carrying,
      );
    }
    return _placePicture(path, settings, fileReport, sourcePath: sourcePath);
  }

  /// A picture through a picture's door, as its row answers — the ordinary
  /// image path, and a run's span that keeps one picture ([_placeRun]).
  Future<bool> _placePicture(
    String picture,
    ImportFileSettings settings,
    _FileReport fileReport, {
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
    onCarrying: fileReport.carrying,
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
    List<RunPicture> kept,
    _ImportTally tally,
    _FileReport fileReport,
  ) async {
    final folder = File(path).parent.path;
    final files = <({String path, String label})>[];
    for (final picture in kept) {
      final file = '$folder/${picture.file}';
      // Every picture of the run reads before it is placed, the law the
      // picked one already went through ([_readsForPlacement]).
      if (!mounted) {
        return false;
      }
      if (mediaFileName(file) != mediaFileName(path) &&
          !await _readsForPlacement(file, tally)) {
        continue;
      }
      files.add((path: file, label: picture.number));
    }
    final settings = _settingsFor(path);
    if (files.length == 1) {
      return _placePicture(files.single.path, settings, fileReport);
    }
    return widget.session.importDoors.importPictureRun(
      files: files,
      name: _runOf(path)!.name,
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
    onCarrying: fileReport.carrying,
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
  /// [report] counts the files the batches have landed, the kept ones as
  /// they go: each piece cut, then the holding, named on the window's line
  /// while it reports (F-494: a trimmed movie's two minutes stood a minute
  /// at 0% here).
  Future<void> _registerFiles(
    List<String> paths,
    _ImportTally tally,
    void Function(double) report,
  ) async {
    report(0);
    // The files the pool keeps, and those of them cut into a piece first.
    final keeping = [
      for (final path in paths)
        if (_settingsFor(path).mode == ImportFileMode.keepInside) path,
    ];
    final cutting = [
      for (final path in keeping)
        if (mediaAssetKindForPath(path) != null &&
            _comesInAsAPiece(path, _settingsFor(path)))
          path,
    ];
    final told = _PoolReport(
      report,
      (step) => _step.value = step,
      keptShare: doneShare(keeping.length, paths.length),
      cuts: cutting.length,
    );
    // What the pool is handed — a piece in place of the file it was cut
    // from — and the picked file each one stands for.
    final carried = <String, String>{};
    final referenced = <String>[];
    for (final path in paths) {
      final kind = mediaAssetKindForPath(path);
      if (kind != null && cutting.contains(path)) {
        final piece = await _cutForThePool(
          path,
          kind,
          told.cut(cutting.indexOf(path), kind),
        );
        if (piece == null) {
          _warnOf(tally, path, (name) => _placementFailure(name, kind));
        } else {
          carried[piece] = path;
        }
      } else if (keeping.contains(path)) {
        carried[path] = path;
      } else {
        referenced.add(path);
      }
    }
    await _holdInThePool(carried, told);
    tally
      ..imported += carried.length
      ..done.addAll(carried.values);
    told.kept();
    await widget.session.mediaPool.importMediaFiles(
      referenced,
      copyIntoProject: false,
    );
    tally
      ..imported += referenced.length
      ..done.addAll(referenced);
    report(1);
  }

  /// [carried] — what the pool is handed, by the picked file each stands
  /// for — held in the pool as ONE batch, each piece with the file it was
  /// cut from, and each piece kept or let go of as the batch went.
  Future<void> _holdInThePool(
    Map<String, String> carried,
    _PoolReport told,
  ) async {
    final pieces = widget.session.trimmedPieces;
    final cutFrom = {
      for (final MapEntry(key: handed, value: picked) in carried.entries)
        if (handed != picked) handed: picked,
    };
    var held = false;
    try {
      await widget.session.mediaPool.importMediaFiles(
        carried.keys.toList(),
        copyIntoProject: true,
        cutFrom: cutFrom,
        onCarrying: told.holding,
      );
      held = true;
    } finally {
      _step.value = '';
      for (final piece in cutFrom.keys) {
        held ? pieces.secure(piece) : pieces.discard(piece);
      }
    }
  }

  /// [path] cut into its piece for the pool, [told] how far from the cut's
  /// start on — a sound's or a page range's cut says nothing until it is
  /// done, and the window names it all the same (F-494). The piece's path,
  /// or null when it would not cut.
  Future<String?> _cutForThePool(
    String path,
    MediaAssetKind kind,
    void Function(double fraction) told,
  ) async {
    final settings = _settingsFor(path);
    told(0);
    try {
      final piece = await widget.session.trimmedPieces.cut(
        path,
        kind,
        inFrame: settings.inFrame,
        outFrame: settings.outFrame,
        onProgress: told,
      );
      return piece?.path;
    } finally {
      _step.value = '';
    }
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
      _warnOf(tally, path, AppText.strings.imPsdNoLayers);
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
    final button = AppWindowActionButton(
      AppWindowAction(
        label: AppText.strings.imWarningCount(warnings.length),
        actionKey: const ValueKey<String>('import-warnings-button'),
        onPressed: warnings.isEmpty
            ? null
            : () => unawaited(
                showImportWarnings(
                  context,
                  windowKey: const ValueKey<String>('import-warnings-notice'),
                  warnings: warnings,
                ),
              ),
      ),
    );
    return Stack(
      key: const ValueKey<String>('import-status-line'),
      alignment: AlignmentDirectional.centerStart,
      children: [
        if (warnings.isEmpty)
          // Held for its height only: laid out, never painted, pressed or
          // read out. ⛔Not a `Visibility`, which takes a slot away
          // (the_slot_is_reserved_test) — an `Opacity` at nought paints
          // nothing and composites nothing, and the shown button wears
          // none.
          IgnorePointer(
            child: ExcludeSemantics(
              child: Opacity(opacity: 0, child: button),
            ),
          )
        else
          button,
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
          ? AppText.strings.imPlaceTitle(_shownName(_files.first))
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
          // Every source answers per row — a cut folder's layers too, as the
          // rows of the cut it lands as (F-429). ↩️A folder kept a list that
          // read its parse out, and a column of knobs answering for all of
          // it at once.
          Expanded(child: _twoZones(context)),
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
    final rows = [for (final key in _rowKeys) _tableRowOf(key)];
    final columns = _tableColumns();
    final preview = _preview();
    final leadWidth = _leadWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        final minTable = ImportFileTable.minimumWidth(
          context,
          rows: rows,
          columns: columns,
          leadWidth: leadWidth,
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
                      leadWidth: leadWidth,
                    ))
                .clamp(narrowest, maxTable);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: tableWidth,
              child: _fileTable(rows, columns, leadWidth),
            ),
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
    final key = _selected.isNotEmpty ? _selected.last : _rowKeys.firstOrNull;
    final shown = _shownOf(key);
    return ImportPreview(
      key: const ValueKey<String>('import-preview'),
      session: widget.session,
      path: shown.path,
      run: shown.run,
      opensAsSound: shown.sound,
      inFrame: shown.inFrame,
      outFrame: shown.outFrame,
      rangeEditable: shown.editable,
      soundPeaks: widget.session.audioConformStore.ensurePeaksFor,
      holdBytes: widget.session.projectFile.holdMediaBytes,
      frameRate: widget.session.projectSettings.projectFrameRate,
      audioSpeed: _projectAudioSpeed,
      onRangeChanged: (start, end) {
        if (key != null && _folderRowAt(key) == null) {
          _keepSpan(key, start, end);
        }
      },
    );
  }

  /// What the preview shows of the row at [key] ([_Shown]) — nothing, with
  /// no row.
  _Shown _shownOf(String? key) {
    final folderRow = key == null ? null : _folderRowAt(key);
    if (key == null || folderRow != null) {
      // A folder's row pages through the pictures it brings — every one of
      // them comes in, so its span is no question of the preview's.
      final files = folderRow == null
          ? const <String>[]
          : _folderFilesOf(folderRow);
      return (
        path: files.firstOrNull,
        run: files.length > 1 ? files : null,
        sound: false,
        inFrame: 0,
        outFrame: null,
        editable: false,
      );
    }
    final settings = _settingsFor(key);
    final run = _runFilesOf(key);
    return (
      path: key,
      run: run,
      sound: _landsAsSound(key),
      inFrame: run != null ? settings.runIn : settings.inFrame,
      outFrame: run != null ? settings.runOut : settings.outFrame,
      // The ends appear wherever they act: on what gets placed, and on what
      // gets registered, which comes in as its piece ([_registerFiles]).
      // 🪦Registrations went without them until a trimmer existed
      // (2026-09-24). ⛔Not on a file the pool already holds when only
      // registering: that adds nothing, so a span there would act on
      // nothing.
      editable: _placing(key) || _poolEntryFor(key) == null,
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
  /// is. The name is the pool's when the pool holds the file, as the pool's
  /// own row shows it (F-376).
  ImportFileRow _tableRow(String path) {
    return ImportFileRow(
      path: path,
      name: mediaAssetNameFor(_poolEntryFor(path), path),
      extension: mediaFileNameParts(path).extension,
      modified: _modifiedOf([path]),
      size: byteSizeLabel(_sizeOf(path)),
      resolution: _resolutionOf(path),
    );
  }

  /// The table's row at [key]: a file's, or a row of the folder's.
  ImportFileRow _tableRowOf(String key) => switch (_folderRowAt(key)) {
    final row? => _folderTableRow(key, row),
    null => _tableRow(key),
  };

  /// A folder's row as the table lists it: its name, the newest of its
  /// files' days, their size together and the first's in pixels — what a
  /// fit is chosen by — and the timeline row's own cells before its name
  /// ([_folderLead]).
  ImportFileRow _folderTableRow(String key, _FolderRow row) {
    final files = _folderFilesOf(row);
    return ImportFileRow(
      path: key,
      name: _folderRowName(row),
      extension: '',
      modified: _modifiedOf(files),
      size: files.isEmpty
          ? ''
          : byteSizeLabel(files.fold(0, (total, file) => total + _sizeOf(file))),
      resolution: files.isEmpty ? '' : _resolutionOf(files.first),
      lead: _folderLead(key, row),
    );
  }

  /// [row]'s files where they lie — a layer's cels in their order, a
  /// picture's one; none for what the folder leaves out.
  List<String> _folderFilesOf(_FolderRow row) {
    final folder = _folder!;
    return switch (row) {
      _FolderLayerRow(:final layer) => [
        for (final cel in layer.cells) cutFolderFilePath(folder, cel.file),
      ],
      _FolderPictureRow(:final picture) => [
        cutFolderFilePath(folder, picture.file),
      ],
      _FolderLeftOutRow() => const [],
    };
  }

  /// [row]'s name: a layer by its symbol alone — a correction's too, which
  /// its colour label tells apart (🗣️F-429-Q2: 「A1s인경우 A만
  /// 레이어이름으로 남김. 구분은 색라벨로 되기때문」) — a picture by its own,
  /// and what is left out by every name it holds.
  static String _folderRowName(_FolderRow row) => switch (row) {
    _FolderLayerRow(:final layer) => layer.symbol,
    _FolderPictureRow(:final picture) => picture.name,
    _FolderLeftOutRow(:final names) => names.join(' · '),
  };

  /// [row] as the layer it lands: the key its answers are kept by
  /// ([CutFolderEdits]), and its kind and colour label as the folder's
  /// rules give them until someone picks others — null for what the folder
  /// leaves out.
  ({String key, LayerKind kind, LayerMark mark})? _folderLayerOf(
    _FolderRow row,
  ) {
    final parsed = _parsed!;
    return switch (row) {
      _FolderLayerRow(:final layer) => (
        key: layer.rowKey,
        kind: _folderEdits.kindOfLayer(parsed, layer),
        mark: _folderEdits.markOfLayer(parsed, layer),
      ),
      _FolderPictureRow(:final picture) => (
        key: picture.rowKey,
        kind: _folderEdits.kindOfPicture(picture),
        mark: _folderEdits.markOfPicture(picture),
      ),
      _FolderLeftOutRow() => null,
    };
  }

  /// [row]'s cells before its name: the TIMELINE RAIL's own
  /// ([layerRailLeadingCells]) — its colour label and take, a correction's
  /// attach arrow, its kind — as the row will stand in the timeline
  /// (🗣️F-429: 「타임라인 레이어처럼 최대한 기존 로직/디자인 재사용. 출력창 셀
  /// 탭에서 재사용한것처럼」). The label opens the timeline's own picker, the
  /// kind 이미지 · 애니메이션, each for every selected row when the pressed
  /// one is among them (F-429-Q1). Null for what the folder leaves out.
  Widget? _folderLead(String key, _FolderRow row) {
    final layer = _folderLayerOf(row);
    if (layer == null) {
      return null;
    }
    final attached =
        row is _FolderLayerRow &&
        _folderEdits.ridesItsBase(_parsed!, row.layer);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: layerRailLeadingCells(
        includeSectionSlot: false,
        mark: LayerMarkChip(
          keyPrefix: 'import',
          layerId: LayerId(key),
          mark: layer.mark,
          onMarkSelected: (_, edit) => _editFolderMarks(key, edit),
        ),
        timesheet: attached
            ? LayerAttachArrowCell(
                keyPrefix: 'import',
                idValue: key,
                placement: AttachedPlacement.above,
              )
            : null,
        typeButton: LayoutBuilder(
          builder: (context, room) => LayerTypeButton(
            keyPrefix: 'import',
            idValue: key,
            kind: layer.kind,
            height: room.maxHeight,
            // A correction is its symbol's kind, as an attach row made in
            // the timeline is ([CutFolderEdits.kindOfLayer]) — the glyph
            // alone, nothing to press.
            onTap: attached ? null : () => _pickFolderKind(context, key),
          ),
        ),
      ),
    );
  }

  /// The folder's rows a press on [pressed] speaks for — the selection's,
  /// when it is among them ([importRowsPressedWith]) — as the layers they
  /// land.
  Iterable<({String key, LayerKind kind, LayerMark mark})>
  _folderLayersPressedWith(String pressed) => [
    for (final key in importRowsPressedWith(_selected, pressed))
      if (_folderRowAt(key) case final row?) ?_folderLayerOf(row),
  ];

  /// [edit] made to the colour label of every row a press on [pressed]
  /// speaks for — a label picked, or a take.
  void _editFolderMarks(String pressed, LayerMarkEdit edit) {
    final marks = {..._folderEdits.marks};
    for (final layer in _folderLayersPressedWith(pressed)) {
      marks[layer.key] = edit(layer.mark);
    }
    setState(() => _folderEdits = _folderEdits.copyWith(marks: marks));
  }

  /// The kinds a press on a row's kind offers — 이미지 · 애니메이션, an image
  /// only for a row of one cel ([CutFolderEdits.holds]) — the pick going to
  /// every row the press speaks for, each taking it as far as its cels
  /// allow (🗣️F-429: 「1장짜리 그림을 기본 이미지레이어로 자동지정해두지만
  /// 같은창에서 애니메이션레이어로 변경가능」).
  void _pickFolderKind(BuildContext anchor, String pressed) {
    final row = _folderRowAt(pressed)!;
    final cels = _folderFilesOf(row).length;
    unawaited(
      showPanelFlyout(
        anchor,
        entries: const [LayerKind.image, LayerKind.animation]
            .asFlyoutValueChoices(
              current: _folderLayerOf(row)?.kind,
              choiceOf: (kind) => PanelFlyoutChoice(
                key: 'import-kind-${kind.jsonValue}',
                label: layerKindDisplayName(kind),
                icon: layerKindIcon(kind),
                enabled: CutFolderEdits.holds(kind, cels),
              ),
              onPicked: (kind) => _setFolderKinds(pressed, kind),
            ),
      ),
    );
  }

  void _setFolderKinds(String pressed, LayerKind kind) {
    final kinds = {..._folderEdits.kinds};
    for (final layer in _folderLayersPressedWith(pressed)) {
      kinds[layer.key] = kind;
    }
    setState(() => _folderEdits = _folderEdits.copyWith(kinds: kinds));
  }

  /// The room before every row's name while a folder's rows are listed:
  /// the timeline rail's cells up to its name, as the export window's cels
  /// list wears them.
  double get _leadWidth => _folderRows.isEmpty
      ? 0
      : layerRailLeadingWidthTo(
          to: LayerRailLeadingSlot.name,
          includeSectionSlot: false,
        );

  /// One row per file, one column per question (§3 of the round).
  Widget _fileTable(
    List<ImportFileRow> rows,
    List<ImportColumn<Object?>> columns,
    double leadWidth,
  ) => ImportFileTable(
    key: const ValueKey<String>('import-file-table'),
    enabled: !_running,
    leadWidth: leadWidth,
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
      _alsoOfTheFolder(_intoColumn(), _folderInto),
      // The layer's question, wherever something is placed (「플레이스가
      // 타임라인이면 굽기열 만들기」).
      if (placementAsked) _alsoOfTheFolder(_bakeColumn(), _folderBake),
      // The pool's question, asked only of a file the pool has not answered
      // (「플레이스가 타임라인일땐 그냥 품기/참조인 그 열 자체를 삭제」 for
      // pooled files, 「프로젝트의 임포트 버튼 … 품기/참조열 존재하도록」
      // for new ones).
      if (any((path) => _poolEntryFor(path) == null))
        _alsoOfTheFolder(_fileColumn(), _folderFile),
      if (placementAsked) _alsoOfTheFolder(_fitColumn(), _folderFit),
      // A run's, a Photoshop document's, a movie-with-sound's own question —
      // one column, each row its own (F-282).
      if (placementAsked) _alsoOfTheFolder(_optionColumn(), _folderOption),
    ];
  }

  /// [files] as a cut folder's rows answer it too ([_FolderColumn]): a row
  /// of the folder is asked [folder], a file's row [files] — ONE column, so
  /// its header answers for both, and a press on a row of either kind
  /// speaks for the selection of both.
  ImportColumn<Object?> _alsoOfTheFolder(
    ImportColumn<Object?> files,
    _FolderColumn folder,
  ) => ImportColumn<Object?>(
    id: files.id,
    label: files.label,
    help: files.help,
    style: files.style,
    values: files.values,
    labelOf: files.labelOf,
    valuesFor: (key) => switch (_folderRowAt(key)) {
      final row? => folder.answers(row),
      null => files.answersFor(key),
    },
    wordOf: (key, value) => switch (_folderRowAt(key)) {
      final row? => folder.wordOf?.call(row, value),
      null => files.wordOf?.call(key, value),
    },
    valueOf: (key) => switch (_folderRowAt(key)) {
      final row? => folder.valueOf(row),
      null => files.valueOf(key),
    },
    appliesTo: (key) => switch (_folderRowAt(key)) {
      final row? => folder.answers(row).isNotEmpty,
      null => files.appliesTo(key),
    },
    enabledFor: (key, value) => switch (_folderRowAt(key)) {
      final row? =>
        folder.answers(row).contains(value) &&
            (folder.enabledFor?.call(row, value) ?? true),
      null => files.enabledFor(key, value),
    },
    onPick: (keys, value) {
      // An answer the files are never asked — a folder row's own — is not
      // theirs to take.
      if (files.values.contains(value)) {
        files.onPick([
          for (final key in keys)
            if (_folderRowAt(key) == null) key,
        ], value);
      }
      // A row that cannot give the answer lets it pass, as a file's resolves
      // it away.
      folder.onPick?.call([
        for (final key in keys)
          if (_folderRowAt(key) case final row?)
            if (folder.answers(row).contains(value)) row,
      ], value);
    },
  );

  /// Where a folder's row goes. Under 「컷」, a new layer of the cut the
  /// folder lands as — the one answer, locked (🗣️F-429-Q1: 「컷 누르면 …
  /// 임포트하는 항목들 새 레이어로 해두고 비활성화색」); under 「커스텀」, a
  /// new layer of the open cut or a new cut, as every file is asked
  /// (「커스텀하면 레이어당 하나하나 새 컷 만들어서 넣는다거나 새 레이어
  /// 정한다거나 가능」). A correction rides its symbol under both until
  /// 「커스텀」 sends it elsewhere ([CutFolderEdits.ridesItsBase]); what the
  /// folder leaves out goes nowhere.
  _FolderColumn get _folderInto => _FolderColumn(
    answers: _folderIntoAnswers,
    valueOf: _folderIntoOf,
    enabledFor: (row, value) =>
        value != ImportDestination.activeCutLayer || _hasCutToPlaceIn,
    wordOf: (row, value) => value is _WithItsBase ? _attachWord(row) : null,
    onPick: _pickFolderInto,
  );

  List<Object> _folderIntoAnswers(_FolderRow row) => switch (row) {
    _FolderLeftOutRow() => const [_LeftOut()],
    _ when !_folderEdits.custom => [_folderIntoOf(row)],
    _FolderLayerRow(:final layer) when _parsed!.baseOf(layer) != null =>
      const [
        _WithItsBase(),
        ImportDestination.activeCutLayer,
        ImportDestination.newCut,
      ],
    _ => ImportDestination.values,
  };

  Object _folderIntoOf(_FolderRow row) {
    final layer = _folderLayerOf(row);
    if (layer == null) {
      return const _LeftOut();
    }
    if (row is _FolderLayerRow &&
        _folderEdits.ridesItsBase(_parsed!, row.layer)) {
      return const _WithItsBase();
    }
    return _folderEdits.custom
        ? _folderEdits.intoOf(
            layer.key,
            hasOpenCut: widget.session.activeCutOrNull != null,
          )
        : ImportDestination.activeCutLayer;
  }

  /// [row]'s ride in words — the timeline's own, as its drag names an
  /// attach: the symbol, and whether it rides SYNCED or FREE
  /// ([CutFolderParseResult.correctsOnlyItsBaseCels]).
  String? _attachWord(_FolderRow row) {
    if (row is! _FolderLayerRow) {
      return null;
    }
    final template = _parsed!.correctsOnlyItsBaseCels(row.layer)
        ? AppText.strings.tlDropAttachSyncedTemplate
        : AppText.strings.tlDropAttachFreeTemplate;
    return template.replaceAll('{name}', row.layer.symbol);
  }

  /// [value] as the 넣을 곳 of [rows]: a destination kept for each, or —
  /// riding its symbol — none of its own.
  void _pickFolderInto(Iterable<_FolderRow> rows, Object? value) {
    final into = {..._folderEdits.into};
    for (final row in rows) {
      final key = _folderLayerOf(row)!.key;
      if (value case final ImportDestination destination) {
        into[key] = destination;
      } else {
        into.remove(key);
      }
    }
    setState(() => _folderEdits = _folderEdits.copyWith(into: into));
  }

  /// A folder's cels bake, every one — they are what is drawn on next
  /// (§6-z22) — the one answer, locked.
  _FolderColumn get _folderBake => _FolderColumn(
    answers: (row) => row is _FolderLeftOutRow ? const [] : const [true],
    valueOf: (row) => true,
  );

  /// What a baked row leaves in the pool: nothing, so the pool's question
  /// is not its (F-282-Q6: 「굽는 줄의 「파일」은 「—」」).
  _FolderColumn get _folderFile =>
      _FolderColumn(answers: (row) => const [], valueOf: (row) => null);

  /// How a folder's row lays its cels on the cut's canvas — the cut is the
  /// project's size, not the scans', so every fit is an answer
  /// ([CutFolderEdits.fitOf]).
  _FolderColumn get _folderFit => _FolderColumn(
    answers: (row) => row is _FolderLeftOutRow ? const [] : MediaFitMode.values,
    valueOf: (row) => _folderEdits.fitOf(_folderLayerOf(row)!.key),
    onPick: (rows, value) => setState(
      () => _folderEdits = _folderEdits.copyWith(
        fits: {
          ..._folderEdits.fits,
          for (final row in rows) _folderLayerOf(row)!.key: value! as MediaFitMode,
        },
      ),
    ),
  );

  /// A folder's layer as its 「옵션」 cell says it: the cels it brings, as a
  /// numbered run's cell says its span (「A1–A21 (22장)」).
  _FolderColumn get _folderOption => _FolderColumn(
    answers: (row) => row is _FolderLayerRow ? const [_RunSpan()] : const [],
    valueOf: (row) => const _RunSpan(),
    wordOf: (row, value) => _spanWord([
      for (final file in _folderFilesOf(row)) mediaFileNameParts(file).name,
    ]),
  );

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
    // 🗣️유저 2026-08-30: 「품기는 압축된 파일 저장시키는거라고 문장 넣는게
    // 좋을거같아」 — said where an explanation is said, as the header's
    // tooltip (F-366). It also answers a question the size column would
    // otherwise raise: the media pool shows what an asset OCCUPIES, which
    // after carrying is smaller than the file imported. ↩️It was a line
    // under the cut folder's carry chips, the one place the window asked
    // it, until F-429 made the folder's media rows of their own.
    help: [
      for (final (mode, says) in [
        (ImportFileMode.keepInside, AppText.strings.imKeepExplain),
        (ImportFileMode.reference, AppText.strings.imReferenceExplain),
      ])
        '${importModeLabel(mode)} — $says',
    ].join('\n'),
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
    final kept = _runKeptOf(path);
    return kept == null
        ? null
        : _spanWord([for (final picture in kept) picture.shown]);
  }

  /// Pictures in a row as a cell says them: the first and the last and how
  /// many for two or more, the one's own name for one.
  static String _spanWord(List<String> shown) => shown.length == 1
      ? shown.single
      : AppText.strings.imRunSpan(shown.first, shown.last, shown.length);

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
        _LeftOut() => AppText.strings.imExcluded,
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
        _IntoThePool() => widget.poolOnly || _poolAnswers(path),
        ImportDestination.activeCutLayer => _hasCutToPlaceIn,
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
  /// row there registers. A file a cut folder lists goes into the cut it
  /// lands as, or the pool (🗣️F-429-Q4: 「미디어 행은 새 레이어 · 미디어 중에서
  /// 고릅니다」) — under 「커스텀」, wherever every file goes.
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
    if (answering != null) {
      return [answering];
    }
    return _folderLandsAsOneCut
        ? const [ImportDestination.activeCutLayer, _IntoThePool()]
        : const [...ImportDestination.values, _IntoThePool()];
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

  /// The newest of [paths]' days, `MM-DD` — what a row has space for and
  /// what a person scanning a folder of today's work is actually reading.
  String _modifiedOf(Iterable<String> paths) {
    DateTime? newest;
    for (final path in paths) {
      final stamp = _stampOf(path);
      if (stamp != null && (newest == null || stamp.isAfter(newest))) {
        newest = stamp;
      }
    }
    if (newest == null) {
      return '';
    }
    return '${newest.month.toString().padLeft(2, '0')}-'
        '${newest.day.toString().padLeft(2, '0')}';
  }

  /// One stat per file for its day, kept as [_fileSizes] is: `build` asks on
  /// every press, and a folder's row asks for every cel it brings.
  final Map<String, DateTime?> _stamps = {};

  DateTime? _stampOf(String path) => _stamps.putIfAbsent(path, () {
    try {
      return File(path).lastModifiedSync();
    } on Object {
      return null;
    }
  });

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
    final parsed = _parsed;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              key: const ValueKey<String>('import-source-line'),
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (parsed != null) ..._folderLanding(theme, parsed),
        ],
      ),
    );
  }

  /// Where a folder lands, beside the folder it comes from: as ONE cut —
  /// named in the field beside it, the folder's own cut number until typed
  /// over and the folder's again when left empty — or 「커스텀」, each row
  /// where its own 넣을 곳 says, the name dimmed in its place (🗣️F-429-Q1:
  /// 「컷 이름만 남기고, 그 쪽에 넣을 곳 컷/커스텀 버튼 만들어서, 컷 누르면 컷
  /// 이름 텍스트같은거 활성화되면서」).
  List<Widget> _folderLanding(ThemeData theme, CutFolderParseResult parsed) {
    final open = !_busy && _folderToLand != null;
    PillItem choice(String key, String label, {required bool custom}) =>
        PillItem(
          keyValue: 'import-folder-into-$key',
          label: label,
          selected: _folderEdits.custom == custom,
          onTap: open
              ? () => setState(
                  () => _folderEdits = _folderEdits.copyWith(custom: custom),
                )
              : null,
        );
    final caption = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return [
      const SizedBox(width: 12),
      Text(AppText.strings.imInto, style: caption),
      const SizedBox(width: 6),
      // Its own width, so the path beside it takes the rest.
      IntrinsicWidth(
        child: PillStrip(
          items: [
            choice('cut', AppText.strings.imFolderAsOneCut, custom: false),
            choice('custom', AppText.strings.imFolderPerRow, custom: true),
          ],
        ),
      ),
      const SizedBox(width: 12),
      Text(AppText.strings.renameCutField, style: caption),
      const SizedBox(width: 6),
      SizedBox(
        width: 120,
        child: TextField(
          key: const ValueKey<String>('import-cut-name-field'),
          controller: _cutName,
          enabled: open && !_folderEdits.custom,
          decoration: InputDecoration(
            hintText: const CutFolderEdits().nameOf(parsed),
          ),
        ),
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
}
