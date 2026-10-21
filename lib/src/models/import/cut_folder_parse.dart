/// The configurable CUT-FOLDER parser (import round, user-confirmed
/// 07-29): real Japanese animation cut folders measured from the user's
/// own delivery folders (CSM3 · UPN · KHT — see the cut-folder naming
/// rules). The grammar is HUMAN-made and drifts (typos, lost prefixes,
/// mixed extensions, skipped numbers), so this is deliberately a
/// CONFIGURABLE parser whose result feeds a live preview — never a fixed
/// rule the user cannot correct.
///
/// The two-dimensional core (rule B): file names are LAYER SYMBOL × CEL
/// NUMBER (`A1..A16`, `B1..B11`, compound `ABH1`), NOT a flat numbered
/// sequence. `_`-prefixed files are never cels (rule E): `_BG*`/`_BOOK*`
/// are picture layers, `_TS*`/`*_ts_*` are timesheet scans, `_mov*` is
/// the reference movie, `_old/` is history. Trailing underscores are
/// revision marks (rule F: `A2` → `A2_` → `A2__`), insertion letters sit
/// between numbers (rule C: `G3a` between `G3` and `G4`), and a process
/// letter after the number is whose correction the drawing is (rule N:
/// `A1s` · `A1_s` — 작감).
///
/// 🗣️F-429 (유저 2026-10-21) took three readings OUT: 「일단 겸용컷으로 읽는
/// 로직 삭제. 항상 한 컷으로만 들어오는느낌. 나머지 두개도 일단 삭제. 규칙
/// 확실하게 다시 정하고싶음」. ↩️A folder naming several cuts (rule H:
/// `069_077_086`) made 겸용컷 of the rest; revisions could come in all or
/// as originals; process subfolders (`LO/`, rule G/M) could come in as
/// attach folders. Now the folder is ONE cut named by its first number,
/// the latest revision is the cel, and a subfolder is always the archive.
library;

import '../../core/collection_equality.dart';
import '../../core/path_names.dart';
import '../layer_kind.dart';
import '../layer_mark.dart';
import '../layer_process.dart';
import 'import_warning.dart';

/// How the folder NAME is read (rule I: studios differ).
enum CutFolderNameRule {
  /// `title_episode_cut(_cut…)_process` — CSM3/UPN/moart style.
  titleEpisodeCut('titleEpisodeCut'),

  /// The folder name is the cut number alone (KHT style); the process
  /// comes from the parent folder when [CutFolderParseConfig.parentFolderProcessHint]
  /// is on.
  cutNumberOnly('cutNumberOnly');

  const CutFolderNameRule(this.jsonValue);

  final String jsonValue;

  String toJson() => jsonValue;

  static CutFolderNameRule fromJson(Object? json) {
    for (final value in values) {
      if (value.jsonValue == json) {
        return value;
      }
    }
    return titleEpisodeCut;
  }
}

/// The parser's knobs — presettable per studio ("CSM3용", "UPN용").
class CutFolderParseConfig {
  const CutFolderParseConfig({
    this.nameRule = CutFolderNameRule.titleEpisodeCut,
    this.parentFolderProcessHint = false,
    this.maxLayerSymbolLength = 4,
    this.insertionLetters = true,
    this.excludeNames = const ['_old', '_3D'],
  });

  final CutFolderNameRule nameRule;

  /// KHT style: the parent folder (`作業/LO/264`) names the process.
  final bool parentFolderProcessHint;

  /// Longest leading uppercase run still read as one layer symbol
  /// (`A` / `ABH` — rule D).
  final int maxLayerSymbolLength;

  /// Read a lowercase letter after the number as an insertion (`G3a`).
  final bool insertionLetters;

  /// Directory/file names excluded outright (case-insensitive).
  final List<String> excludeNames;

  CutFolderParseConfig copyWith({
    CutFolderNameRule? nameRule,
    bool? parentFolderProcessHint,
    int? maxLayerSymbolLength,
    bool? insertionLetters,
    List<String>? excludeNames,
  }) {
    return CutFolderParseConfig(
      nameRule: nameRule ?? this.nameRule,
      parentFolderProcessHint:
          parentFolderProcessHint ?? this.parentFolderProcessHint,
      maxLayerSymbolLength: maxLayerSymbolLength ?? this.maxLayerSymbolLength,
      insertionLetters: insertionLetters ?? this.insertionLetters,
      excludeNames: excludeNames ?? this.excludeNames,
    );
  }

  Map<String, dynamic> toJson() => {
    'nameRule': nameRule.toJson(),
    if (parentFolderProcessHint) 'parentFolderProcessHint': true,
    if (maxLayerSymbolLength != 4)
      'maxLayerSymbolLength': maxLayerSymbolLength,
    if (!insertionLetters) 'insertionLetters': false,
    'excludeNames': excludeNames,
  };

  factory CutFolderParseConfig.fromJson(Map<String, dynamic> json) {
    return CutFolderParseConfig(
      nameRule: CutFolderNameRule.fromJson(json['nameRule']),
      parentFolderProcessHint:
          (json['parentFolderProcessHint'] as bool?) ?? false,
      maxLayerSymbolLength: (json['maxLayerSymbolLength'] as int?) ?? 4,
      insertionLetters: (json['insertionLetters'] as bool?) ?? true,
      excludeNames: [
        for (final name in (json['excludeNames'] as List<dynamic>?) ?? const [])
          name as String,
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CutFolderParseConfig &&
          other.nameRule == nameRule &&
          other.parentFolderProcessHint == parentFolderProcessHint &&
          other.maxLayerSymbolLength == maxLayerSymbolLength &&
          other.insertionLetters == insertionLetters &&
          listEquals(other.excludeNames, excludeNames);

  @override
  int get hashCode => Object.hash(
    nameRule,
    parentFolderProcessHint,
    maxLayerSymbolLength,
    insertionLetters,
    Object.hashAll(excludeNames),
  );
}

/// One entry handed to the parser: a path RELATIVE to the dropped folder
/// (forward or back slashes) + whether it is a directory.
class CutFolderEntry {
  const CutFolderEntry(this.relativePath, {this.isDirectory = false});

  final String relativePath;
  final bool isDirectory;
}

/// A parsed cel: `G3a__` → number 3, insertion 'a', revision rank 2.
class ParsedCel {
  const ParsedCel({
    required this.number,
    this.insertion = '',
    required this.revisionRank,
    required this.file,
    this.olderRevisions = const [],
  });

  final int number;

  /// The insertion letters after the number (rule C) — '' for none;
  /// sorts AFTER the bare number ('' < 'a' < 'b').
  final String insertion;

  /// How revised this file is (rule F: trailing `_`s and letter suffixes
  /// that name no correction each add a rank step). 0 = the unmarked
  /// original.
  final int revisionRank;

  /// The surviving file — the latest revision — relative path.
  final String file;

  /// The earlier revisions the latest one stands for (shown in the preview
  /// so nothing disappears silently).
  final List<String> olderRevisions;

  /// The cel's display label (`3a`).
  String get label => '$number$insertion';
}

/// One drawing layer: a symbol's naturally-sorted cels — its own
/// ([correction] null), or one correction's of them (`A1s` · `A2s`: 작감).
class ParsedCelLayer {
  const ParsedCelLayer({
    required this.symbol,
    required this.cells,
    this.correction,
  });

  final String symbol;
  final List<ParsedCel> cells;

  /// Whose correction these cels are (rule N), or null for the symbol's
  /// own cels.
  ///
  /// 🗣️F-429-Q2 (유저 2026-10-21): a correction comes in as the ATTACH of
  /// the symbol's own layer (the 07-29 decision: 「어태치 레이어로 수정
  /// 그리는 걸 전제」), named by the symbol alone — 「A1s인경우 A만
  /// 레이어이름으로 남김. 구분은 색라벨로 되기때문」.
  final LayerRevise? correction;
}

/// A `_`-prefixed picture (rule E): `_BG`, `_BOOK2`, `_BG補足` — each
/// distinct name is ONE picture layer (single cel).
class ParsedPicture {
  const ParsedPicture({
    required this.name,
    required this.file,
    this.olderRevisions = const [],
  });

  /// Display name without the `_` prefix (`BG`, `BOOK2`).
  final String name;

  final String file;
  final List<String> olderRevisions;
}

enum ParsedReferenceKind { timesheetScan, movie, timingSheet, workFile }

/// A file that stays a REFERENCE (registered, never baked — §6-z22):
/// timesheet scans, the reference movie, TDTS/XDTS timing sheets.
class ParsedReference {
  const ParsedReference({required this.file, required this.kind});

  final String file;
  final ParsedReferenceKind kind;
}

/// A file/folder the parse dropped, with the reason — the preview shows
/// these so nothing exits silently (§6-z21).
class ParsedExclusion {
  const ParsedExclusion({required this.path, required this.reason});

  final String path;
  final ExclusionReason reason;
}

/// Why the parse dropped a file — the stable key the string tables answer,
/// and the English the UI falls back to.
///
/// 🚨The reasons were free strings written at each [ParsedExclusion] until
/// F-124 (2026-09-16): six sentences no language but English could say, with
/// nothing to stop a seventh spelling of 「unrecognized」.
enum ExclusionReason {
  processSubfolder('process subfolder (archive)'),
  unrecognized('unrecognized'),
  excludedName('excluded name'),
  memoText('memo text'),
  insertionLettersOff('insertion letters off');

  const ExclusionReason(this.label);

  /// The English wording, and the fallback for a language that has not
  /// tabled this reason (`ExclusionReasonWords.labelFor`).
  final String label;
}

/// The whole folder, interpreted.
class CutFolderParseResult {
  const CutFolderParseResult({
    required this.folderName,
    this.title,
    this.episode,
    this.cutNumber,
    required this.processTokens,
    required this.layers,
    required this.pictures,
    required this.references,
    required this.excluded,
    required this.warnings,
  });

  final String folderName;
  final String? title;
  final String? episode;

  /// The cut the folder names — its FIRST cut number (`069_077_086` →
  /// `069`); null when the name holds none.
  final String? cutNumber;

  /// The process suffix decomposed by the longest-first token table
  /// (rule N: `loekss` → lo, e, k, ss — a SET, order not meaningful).
  final List<String> processTokens;

  /// The symbols' layers, each symbol's own first and its corrections after
  /// it in [LayerRevise] order — the order they stack from the bottom.
  final List<ParsedCelLayer> layers;
  final List<ParsedPicture> pictures;
  final List<ParsedReference> references;
  final List<ParsedExclusion> excluded;
  final List<ImportWarning> warnings;

  /// The stage the folder delivers (rule A/N: `loeks` → LO, `gen` → 원화),
  /// or null when its name says none.
  ///
  /// ⚠️원화 wins over LO: a folder's top level is its NEWEST work (rule M —
  /// 「최상위 = 지금 이 폴더의 주인공」), and 원화 comes after LO.
  LayerProcess? get stage {
    if (processTokens.contains('gen') || processTokens.contains('g')) {
      return LayerProcess.key;
    }
    if (processTokens.contains('lo')) {
      return LayerProcess.layout;
    }
    return null;
  }

  /// The colour label [layer] comes in wearing — the folder's stage, and
  /// the correction its letters name (rule N) — before anyone changes it.
  ///
  /// 🗣️F-429 (유저 2026-10-21): 「수정공정 이런거 자동지정 규칙에 따라
  /// 작감공정으로서 인식은 시키되, 그런것도 유저가 … 변경」. A folder that
  /// names no stage gives what a new animation layer is born with.
  LayerMark markOf(ParsedCelLayer layer) => LayerMark(
    process: stage ?? LayerMark.bornOfKind(LayerKind.animation).process,
    revise: layer.correction,
  );
}

/// Rule N's process vocabulary, LONGEST FIRST (`ss` is 총작감, never
/// s+s).
const List<String> _processTokens = [
  'gen',
  'lo',
  'ss',
  'sa',
  'tp',
  'g',
  'e',
  's',
  'k',
];

List<String> _decomposeProcess(Iterable<String> rawTokens) {
  final tokens = <String>[];
  for (final raw in rawTokens) {
    var rest = raw.toLowerCase();
    while (rest.isNotEmpty) {
      String? matched;
      for (final token in _processTokens) {
        if (rest.startsWith(token)) {
          matched = token;
          break;
        }
      }
      if (matched == null) {
        tokens.add(rest);
        break;
      }
      tokens.add(matched);
      rest = rest.substring(matched.length);
    }
  }
  return tokens;
}

final RegExp _numericToken = RegExp(r'^\d+$');

/// `A2a__` core grammar: symbol + number + insertion + revision marks
/// (rule B/C/F). Revision marks = trailing underscores and/or a short
/// lowercase suffix after an underscore (`B1_ss`).
final RegExp _celFilePattern = RegExp(r'^([A-Z]+)(\d+)([a-z]*)((?:_+[a-z]*)*)$');

/// Rule N's corrections — the letters a file name says whose correction a
/// drawing is, read as the colour label's revise.
const Map<String, LayerRevise> _corrections = {
  'e': LayerRevise.direction,
  's': LayerRevise.animationDirector,
  'ss': LayerRevise.chiefAnimationDirector,
  'k': LayerRevise.director,
};

/// A correction written after an underscore (`A1_s`, `B1_ss` — the CSM
/// spelling), and the revision underscores after it.
final RegExp _underscoredCorrection = RegExp(r'^_([a-z]+)(_*)$');

/// What follows a cel's number: its insertion letters, whose correction it
/// is, and the revision marks left — `A1s` · `A1_s` are 작감 of cel 1,
/// `G3a` is the insertion 3a, `A2__` is cel 2's second revision.
///
/// ⚠️ONE correction letter run, exactly — `A1es` names none and stays the
/// insertion it always read as (rule N's `A1esk` was never seen, 07-29).
({String insertion, LayerRevise? correction, String marks}) _readSuffix(
  String letters,
  String marks,
) {
  final lettered = _corrections[letters];
  if (lettered != null) {
    return (insertion: '', correction: lettered, marks: marks);
  }
  final underscored = _underscoredCorrection.firstMatch(marks);
  final correction = _corrections[underscored?.group(1)];
  if (underscored != null && correction != null) {
    return (
      insertion: letters,
      correction: correction,
      marks: underscored.group(2)!,
    );
  }
  return (insertion: letters, correction: null, marks: marks);
}

/// Every mark character deepens the revision.
int _revisionRankOf(String marks) => marks.length;

String _stemOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot <= 0 ? fileName : fileName.substring(0, dot);
}

String _extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot == -1 ? '' : fileName.substring(dot + 1).toLowerCase();
}

const Set<String> _imageExtensions = {'png', 'jpg', 'jpeg', 'webp', 'bmp'};

/// Rule F, stated once for cels and pictures alike: revisions sort by
/// rank, the LATEST is the one kept, and every older one is listed beside
/// it by file. [rankOf] and [fileOf] are the two things a revision of
/// either kind can say about itself.
({T latest, List<String> olderFiles}) _foldRevisions<T>(
  List<T> revisions, {
  required int Function(T revision) rankOf,
  required String Function(T revision) fileOf,
}) {
  final sorted = [...revisions]
    ..sort((a, b) => rankOf(a).compareTo(rankOf(b)));
  final latest = sorted.last;
  return (
    latest: latest,
    olderFiles: [
      for (final older in sorted)
        if (!identical(older, latest)) fileOf(older),
    ],
  );
}

/// Rule F for the pictures: BG and BOOK revisions fold to the latest, the
/// older ones listed beside it, sorted by name.
List<ParsedPicture> _foldPictures(
  Map<String, List<({int rank, String file})>> pictureFiles,
) {
  final pictures = <ParsedPicture>[];
  for (final entry in pictureFiles.entries) {
    final folded = _foldRevisions(
      entry.value,
      rankOf: (revision) => revision.rank,
      fileOf: (revision) => revision.file,
    );
    pictures.add(
      ParsedPicture(
        name: entry.key,
        file: folded.latest.file,
        olderRevisions: folded.olderFiles,
      ),
    );
  }
  pictures.sort((a, b) => a.name.compareTo(b.name));
  return pictures;
}

/// One cel's place in the folder: its layer — the symbol, and whose
/// correction — and the cel within it.
typedef _CelSlot = ({
  String symbol,
  LayerRevise? correction,
  int number,
  String insertion,
});

/// Rules C, D, F and N: the cel files folded into layers.
///
/// Every cel's revisions fold to the LATEST, the older ones listed in its
/// [ParsedCel.olderRevisions]; each layer's cels stand in natural order
/// (number, then insertion letter — the sort 「G3 · G3a · G3b · G4」
/// needs); the layers stand by symbol, each symbol's own before its
/// corrections, the corrections in [LayerRevise] order.
List<ParsedCelLayer> _buildLayers(Map<_CelSlot, List<ParsedCel>> bySlot) {
  final byLayer = <(String, LayerRevise?), List<ParsedCel>>{};
  for (final MapEntry(key: slot, value: revisions) in bySlot.entries) {
    final folded = _foldRevisions(
      revisions,
      rankOf: (cel) => cel.revisionRank,
      fileOf: (cel) => cel.file,
    );
    final latest = folded.latest;
    (byLayer[(slot.symbol, slot.correction)] ??= []).add(
      ParsedCel(
        number: latest.number,
        insertion: latest.insertion,
        revisionRank: latest.revisionRank,
        file: latest.file,
        olderRevisions: folded.olderFiles,
      ),
    );
  }
  int correctionOrder(LayerRevise? correction) =>
      correction == null ? -1 : correction.index;
  return [
    for (final MapEntry(key: (symbol, correction), value: cels)
        in byLayer.entries)
      ParsedCelLayer(
        symbol: symbol,
        correction: correction,
        cells: [...cels]..sort((a, b) {
          final byNumber = a.number.compareTo(b.number);
          if (byNumber != 0) {
            return byNumber;
          }
          return a.insertion.compareTo(b.insertion);
        }),
      ),
  ]..sort((a, b) {
    final bySymbol = a.symbol.compareTo(b.symbol);
    if (bySymbol != 0) {
      return bySymbol;
    }
    return correctionOrder(
      a.correction,
    ).compareTo(correctionOrder(b.correction));
  });
}

/// WHERE EACH FILE IN THE FOLDER LANDS — rule E's table as an object.
///
/// A flat decision cascade: the first rule that recognises the name takes
/// the entry, and anything nothing recognises is excluded as unrecognized
/// rather than guessed at. Reading it top to bottom IS the specification,
/// so it stays one run of tests rather than a tree.
class _EntryBins {
  _EntryBins({required this.config, required this.excluded});

  final CutFolderParseConfig config;
  final List<ParsedExclusion> excluded;

  /// Each cel's place → its revisions seen, top-level cel grammar.
  final celFiles = <_CelSlot, List<ParsedCel>>{};
  final pictureFiles = <String, List<({int rank, String file})>>{};
  final references = <ParsedReference>[];

  late final Set<String> excludeNames = {
    for (final name in config.excludeNames) name.toLowerCase(),
  };

  void take(CutFolderEntry entry) {
    final segments = entry.relativePath.split(RegExp(r'[\\/]'));
    final topSegment = segments.first;
    if (excludeNames.contains(topSegment.toLowerCase())) {
      excluded.add(
        ParsedExclusion(path: entry.relativePath, reason: ExclusionReason.excludedName),
      );
      return;
    }
    if (entry.isDirectory) {
      return; // Directories classify through their files.
    }
    if (segments.length > 1) {
      // Rules G/M: a subfolder (`LO/`, `GEN/`) is the archive of the
      // earlier processes — listed, never brought in (F-429).
      excluded.add(
        ParsedExclusion(
          path: segments.join('/'),
          reason: ExclusionReason.processSubfolder,
        ),
      );
      return;
    }

    final fileName = fileNameOfPath(entry.relativePath);
    final stem = _stemOf(fileName);
    final extension = _extensionOf(fileName);

    // Timing sheets and work files first (extension carries the truth
    // regardless of prefixes).
    if (extension == 'tdts' || extension == 'xdts') {
      references.add(
        ParsedReference(
          file: entry.relativePath,
          kind: ParsedReferenceKind.timingSheet,
        ),
      );
      return;
    }
    if (extension == 'clip' || extension == 'psd') {
      references.add(
        ParsedReference(
          file: entry.relativePath,
          kind: ParsedReferenceKind.workFile,
        ),
      );
      return;
    }
    if (extension == 'mov' || extension == 'mp4' || extension == 'avi') {
      references.add(
        ParsedReference(
          file: entry.relativePath,
          kind: ParsedReferenceKind.movie,
        ),
      );
      return;
    }
    if (extension == 'txt') {
      excluded.add(
        ParsedExclusion(path: entry.relativePath, reason: ExclusionReason.memoText),
      );
      return;
    }

    final lowerStem = stem.toLowerCase();
    // `_TS_e`, `_085_ts_loe`, `_TS_sAc266` — timesheet scans stay
    // references. The token must END at a boundary (`_`, end, or a
    // digit run): `_BG_tsuki` is a picture whose name merely contains
    // 'ts'.
    if (RegExp(r'(^|_)ts(_|$|\d)').hasMatch(lowerStem)) {
      if (_imageExtensions.contains(extension)) {
        references.add(
          ParsedReference(
            file: entry.relativePath,
            kind: ParsedReferenceKind.timesheetScan,
          ),
        );
        return;
      }
    }

    if (stem.startsWith('_')) {
      // Rule E: `_`-prefixed = not a cel. Pictures (`_BG`, `_BOOK2`,
      // `_BG補足`, `_BG_boke`) keep their whole stem as identity, with
      // trailing `_` marks folded as revisions.
      if (_imageExtensions.contains(extension)) {
        var core = stem.substring(1);
        var rank = 0;
        while (core.endsWith('_')) {
          core = core.substring(0, core.length - 1);
          rank += 1;
        }
        if (core.isEmpty) {
          excluded.add(
            ParsedExclusion(path: entry.relativePath, reason: ExclusionReason.unrecognized),
          );
          return;
        }
        (pictureFiles[core] ??= []).add((
          rank: rank,
          file: entry.relativePath,
        ));
        return;
      }
      excluded.add(
        ParsedExclusion(path: entry.relativePath, reason: ExclusionReason.unrecognized),
      );
      return;
    }

    if (_imageExtensions.contains(extension)) {
      final match = _celFilePattern.firstMatch(stem);
      if (match != null &&
          match.group(1)!.length <= config.maxLayerSymbolLength) {
        final symbol = match.group(1)!;
        final number = int.parse(match.group(2)!);
        final (:insertion, :correction, :marks) = _readSuffix(
          match.group(3)!,
          match.group(4)!,
        );
        if (!config.insertionLetters && insertion.isNotEmpty) {
          excluded.add(
            ParsedExclusion(
              path: entry.relativePath,
              reason: ExclusionReason.insertionLettersOff,
            ),
          );
          return;
        }
        final cel = ParsedCel(
          number: number,
          insertion: insertion,
          revisionRank: _revisionRankOf(marks),
          file: entry.relativePath,
        );
        final slot = (
          symbol: symbol,
          correction: correction,
          number: number,
          insertion: insertion,
        );
        (celFiles[slot] ??= []).add(cel);
        return;
      }
    }

    excluded.add(
      ParsedExclusion(path: entry.relativePath, reason: ExclusionReason.unrecognized),
    );
  }
}

/// What the folder name says, before any file is looked at.
typedef CutFolderNameParts = ({
  String? title,
  String? episode,
  String? cutNumber,
  List<String> processTokens,
});

/// Rule A walked left to right: `title_episode_cut_process`.
///
/// The FIRST numeric is the episode only when a TITLE token preceded it —
/// a folder starting with numbers names cuts alone (`069_077_086_loeks`,
/// `264_lo`: the measured no-title shapes). And a titled folder whose only
/// numeric landed as the episode named just the cut (`kht_264`), so that
/// number moves back.
///
/// The FIRST cut number names the cut; the numbers after it (the field's
/// 겸용컷, rule H) are not read — F-429.
CutFolderNameParts _walkNameTokens(List<String> tokens) {
  String? title;
  String? episode;
  String? cutNumber;
  final trailingProcess = <String>[];
  var seenNumeric = false;
  var seenTitle = false;
  for (final token in tokens) {
    if (_numericToken.hasMatch(token)) {
      if (!seenNumeric && seenTitle) {
        episode = token;
      } else {
        cutNumber ??= token;
      }
      seenNumeric = true;
    } else if (!seenNumeric) {
      title = title == null ? token : '${title}_$token';
      seenTitle = true;
    } else {
      trailingProcess.add(token);
    }
  }
  if (cutNumber == null && episode != null) {
    cutNumber = episode;
    episode = null;
  }
  return (
    title: title,
    episode: episode,
    cutNumber: cutNumber,
    processTokens: _decomposeProcess(trailingProcess),
  );
}

/// The folder name under the configured rule, warning into [warnings] when
/// it names no cut at all.
CutFolderNameParts _folderNameParts({
  required String folderName,
  required CutFolderParseConfig config,
  required String? parentFolderName,
  required List<ImportWarning> warnings,
}) {
  final parts = switch (config.nameRule) {
    CutFolderNameRule.titleEpisodeCut => _walkNameTokens(folderName.split('_')),
    CutFolderNameRule.cutNumberOnly => (
      title: null,
      episode: null,
      cutNumber: folderName,
      processTokens: config.parentFolderProcessHint && parentFolderName != null
          ? _decomposeProcess([parentFolderName])
          : <String>[],
    ),
  };
  if (parts.cutNumber == null) {
    warnings.add(
      const ImportWarning(
        'folderNoCutNumber',
        'No cut number found in the folder name.',
      ),
    );
  }
  return parts;
}

/// Parses [folderName] + [entries] under [config]. Pure — the window's
/// preview and the import read a folder through it alike.
CutFolderParseResult parseCutFolder({
  required String folderName,
  required List<CutFolderEntry> entries,
  CutFolderParseConfig config = const CutFolderParseConfig(),
  String? parentFolderName,
}) {
  final warnings = <ImportWarning>[];
  final excluded = <ParsedExclusion>[];

  // --- Folder name --------------------------------------------------------
  final name = _folderNameParts(
    folderName: folderName,
    config: config,
    parentFolderName: parentFolderName,
    warnings: warnings,
  );

  // --- Entry classification ------------------------------------------------
  final bins = _EntryBins(config: config, excluded: excluded);
  for (final entry in entries) {
    bins.take(entry);
  }

  // --- Revision folding + layer grouping -----------------------------------
  final layers = _buildLayers(bins.celFiles);
  final pictures = _foldPictures(bins.pictureFiles);

  return CutFolderParseResult(
    folderName: folderName,
    title: name.title,
    episode: name.episode,
    cutNumber: name.cutNumber,
    processTokens: name.processTokens,
    layers: layers,
    pictures: pictures,
    references: bins.references,
    excluded: excluded,
    warnings: warnings,
  );
}
