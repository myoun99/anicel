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
/// between numbers (rule C: `G3a` between `G3` and `G4`), and one folder
/// may carry SEVERAL cuts (rule H: `069_077_086` — the field's 겸용컷).
library;

import '../../core/collection_equality.dart';
import '../../core/path_names.dart';
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

/// Which revision of a cel survives (rule F/K).
enum CelRevisionPolicy {
  /// The highest revision rank per cel (default — the workflow's answer:
  /// the newest correction is the cel).
  latestOnly('latestOnly'),

  /// Every revision becomes its own cel (audit imports).
  all('all'),

  /// The unmarked original only.
  originalOnly('originalOnly');

  const CelRevisionPolicy(this.jsonValue);

  final String jsonValue;

  String toJson() => jsonValue;

  static CelRevisionPolicy fromJson(Object? json) {
    for (final value in values) {
      if (value.jsonValue == json) {
        return value;
      }
    }
    return latestOnly;
  }
}

/// The parser's knobs — presettable per studio ("CSM3용", "UPN용").
class CutFolderParseConfig {
  const CutFolderParseConfig({
    this.nameRule = CutFolderNameRule.titleEpisodeCut,
    this.parentFolderProcessHint = false,
    this.multiCutFolders = true,
    this.maxLayerSymbolLength = 4,
    this.insertionLetters = true,
    this.revisionPolicy = CelRevisionPolicy.latestOnly,
    this.includeProcessSubfolders = false,
    this.excludeNames = const ['_old', '_3D'],
  });

  final CutFolderNameRule nameRule;

  /// KHT style: the parent folder (`作業/LO/264`) names the process.
  final bool parentFolderProcessHint;

  /// Read `069_077_086` as THREE cuts sharing one cel set (rule H).
  final bool multiCutFolders;

  /// Longest leading uppercase run still read as one layer symbol
  /// (`A` / `ABH` — rule D).
  final int maxLayerSymbolLength;

  /// Read a lowercase letter after the number as an insertion (`G3a`).
  final bool insertionLetters;

  final CelRevisionPolicy revisionPolicy;

  /// Parse process subfolders (`LO/`, `GEN/` — rule G/M: the archive of
  /// earlier processes) instead of excluding them.
  final bool includeProcessSubfolders;

  /// Directory/file names excluded outright (case-insensitive).
  final List<String> excludeNames;

  CutFolderParseConfig copyWith({
    CutFolderNameRule? nameRule,
    bool? parentFolderProcessHint,
    bool? multiCutFolders,
    int? maxLayerSymbolLength,
    bool? insertionLetters,
    CelRevisionPolicy? revisionPolicy,
    bool? includeProcessSubfolders,
    List<String>? excludeNames,
  }) {
    return CutFolderParseConfig(
      nameRule: nameRule ?? this.nameRule,
      parentFolderProcessHint:
          parentFolderProcessHint ?? this.parentFolderProcessHint,
      multiCutFolders: multiCutFolders ?? this.multiCutFolders,
      maxLayerSymbolLength: maxLayerSymbolLength ?? this.maxLayerSymbolLength,
      insertionLetters: insertionLetters ?? this.insertionLetters,
      revisionPolicy: revisionPolicy ?? this.revisionPolicy,
      includeProcessSubfolders:
          includeProcessSubfolders ?? this.includeProcessSubfolders,
      excludeNames: excludeNames ?? this.excludeNames,
    );
  }

  Map<String, dynamic> toJson() => {
    'nameRule': nameRule.toJson(),
    if (parentFolderProcessHint) 'parentFolderProcessHint': true,
    if (!multiCutFolders) 'multiCutFolders': false,
    if (maxLayerSymbolLength != 4)
      'maxLayerSymbolLength': maxLayerSymbolLength,
    if (!insertionLetters) 'insertionLetters': false,
    if (revisionPolicy != CelRevisionPolicy.latestOnly)
      'revisionPolicy': revisionPolicy.toJson(),
    if (includeProcessSubfolders) 'includeProcessSubfolders': true,
    'excludeNames': excludeNames,
  };

  factory CutFolderParseConfig.fromJson(Map<String, dynamic> json) {
    return CutFolderParseConfig(
      nameRule: CutFolderNameRule.fromJson(json['nameRule']),
      parentFolderProcessHint:
          (json['parentFolderProcessHint'] as bool?) ?? false,
      multiCutFolders: (json['multiCutFolders'] as bool?) ?? true,
      maxLayerSymbolLength: (json['maxLayerSymbolLength'] as int?) ?? 4,
      insertionLetters: (json['insertionLetters'] as bool?) ?? true,
      revisionPolicy: CelRevisionPolicy.fromJson(json['revisionPolicy']),
      includeProcessSubfolders:
          (json['includeProcessSubfolders'] as bool?) ?? false,
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
          other.multiCutFolders == multiCutFolders &&
          other.maxLayerSymbolLength == maxLayerSymbolLength &&
          other.insertionLetters == insertionLetters &&
          other.revisionPolicy == revisionPolicy &&
          other.includeProcessSubfolders == includeProcessSubfolders &&
          listEquals(other.excludeNames, excludeNames);

  @override
  int get hashCode => Object.hash(
    nameRule,
    parentFolderProcessHint,
    multiCutFolders,
    maxLayerSymbolLength,
    insertionLetters,
    revisionPolicy,
    includeProcessSubfolders,
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

  /// How corrected this file is (rule F: trailing `_`s and letter
  /// suffixes each add a rank step). 0 = the unmarked original.
  final int revisionRank;

  /// The surviving file (per [CelRevisionPolicy]), relative path.
  final String file;

  /// The revisions the policy dropped (shown in the preview so nothing
  /// disappears silently).
  final List<String> olderRevisions;

  /// The cel's display label (`3a`).
  String get label => '$number$insertion';
}

/// One drawing layer: symbol + naturally-sorted cels.
class ParsedCelLayer {
  const ParsedCelLayer({required this.symbol, required this.cells});

  final String symbol;
  final List<ParsedCel> cells;
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
  subfolderNonCel('subfolder non-cel'),
  unrecognized('unrecognized'),
  excludedName('excluded name'),
  memoText('memo text'),
  insertionLettersOff('insertion letters off');

  const ExclusionReason(this.label);

  /// The English wording, and the fallback for a language that has not
  /// tabled this reason (`ExclusionReasonWords.labelFor`).
  final String label;
}

/// An archived process subfolder's cel set (rule G/M: `LO/`, `GEN/`),
/// parsed with the same grammar when
/// [CutFolderParseConfig.includeProcessSubfolders] is on. The import
/// builds these as ATTACH rows grouped in a per-process organizer folder
/// (the R2 attach-folder structure).
class ParsedProcessGroup {
  const ParsedProcessGroup({required this.process, required this.layers});

  final String process;
  final List<ParsedCelLayer> layers;
}

/// The whole folder, interpreted.
class CutFolderParseResult {
  const CutFolderParseResult({
    required this.folderName,
    this.title,
    this.episode,
    required this.cutNumbers,
    required this.processTokens,
    required this.layers,
    required this.pictures,
    required this.references,
    required this.processGroups,
    required this.excluded,
    required this.warnings,
  });

  final String folderName;
  final String? title;
  final String? episode;

  /// One or MORE cut numbers (rule H: `069_077_086` = three cuts sharing
  /// the cel set — the field's 겸용컷).
  final List<String> cutNumbers;

  /// The process suffix decomposed by the longest-first token table
  /// (rule N: `loekss` → lo, e, k, ss — a SET, order not meaningful).
  final List<String> processTokens;

  final List<ParsedCelLayer> layers;
  final List<ParsedPicture> pictures;
  final List<ParsedReference> references;
  final List<ParsedProcessGroup> processGroups;
  final List<ParsedExclusion> excluded;
  final List<ImportWarning> warnings;
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

int _revisionRankOf(String marks) {
  if (marks.isEmpty) {
    return 0;
  }
  var rank = 0;
  for (var i = 0; i < marks.length; i += 1) {
    rank += 1; // Every mark character deepens the revision.
  }
  return rank;
}

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
({List<T> sorted, T latest, List<String> olderFiles}) _foldRevisions<T>(
  List<T> revisions, {
  required int Function(T revision) rankOf,
  required String Function(T revision) fileOf,
}) {
  final sorted = [...revisions]
    ..sort((a, b) => rankOf(a).compareTo(rankOf(b)));
  final latest = sorted.last;
  return (
    sorted: sorted,
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

/// Rules G and M: a process subfolder is an ARCHIVE unless the import was
/// told to bring it in, and what comes in arrives as its own group of
/// layers under the process the folder is named for.
List<ParsedProcessGroup> _processGroups({
  required Map<String, List<CutFolderEntry>> subfolderFiles,
  required CutFolderParseConfig config,
  required List<ParsedExclusion> excluded,
  required List<ImportWarning> warnings,
}) {
  final processGroups = <ParsedProcessGroup>[];
  for (final entry in subfolderFiles.entries) {
    if (!config.includeProcessSubfolders) {
      for (final file in entry.value) {
        excluded.add(
          ParsedExclusion(
            path: '${entry.key}/${file.relativePath}',
            reason: ExclusionReason.processSubfolder,
          ),
        );
      }
      continue;
    }
    final subCells = <String, List<ParsedCel>>{};
    for (final file in entry.value) {
      final fileName = fileNameOfPath(file.relativePath);
      final stem = _stemOf(fileName);
      final extension = _extensionOf(fileName);
      if (!_imageExtensions.contains(extension) || stem.startsWith('_')) {
        excluded.add(
          ParsedExclusion(
            path: '${entry.key}/${file.relativePath}',
            reason: ExclusionReason.subfolderNonCel,
          ),
        );
        continue;
      }
      final match = _celFilePattern.firstMatch(stem);
      if (match == null ||
          match.group(1)!.length > config.maxLayerSymbolLength) {
        excluded.add(
          ParsedExclusion(
            path: '${entry.key}/${file.relativePath}',
            reason: ExclusionReason.unrecognized,
          ),
        );
        continue;
      }
      final cel = ParsedCel(
        number: int.parse(match.group(2)!),
        insertion: config.insertionLetters ? match.group(3)! : '',
        revisionRank: _revisionRankOf(match.group(4)!),
        file: '${entry.key}/${file.relativePath}',
      );
      (subCells['${match.group(1)!}|${cel.number}|${cel.insertion}'] ??= [])
          .add(cel);
    }
    if (subCells.isNotEmpty) {
      processGroups.add(
        ParsedProcessGroup(
          process: entry.key,
          layers: _buildLayers(
            subCells,
            revisionPolicy: config.revisionPolicy,
            warnings: warnings,
          ),
        ),
      );
    }
  }
  processGroups.sort((a, b) => a.process.compareTo(b.process));
  return processGroups;
}

/// Rules C, D and F: the cel files of one grammar folded into layers.
///
/// Every cell's revisions sort by rank, the policy decides whether the
/// older ones survive as their own cels or fold into the latest's
/// [ParsedCel.olderRevisions], and the layers come out sorted by symbol
/// with each layer's cels in natural order (number, then insertion
/// letter) — the sort rule 「G3 · G3a · G3b · G4」 needs.
List<ParsedCelLayer> _buildLayers(
  Map<String, List<ParsedCel>> byCell, {
  required CelRevisionPolicy revisionPolicy,
  required List<ImportWarning> warnings,
}) {
  final bySymbol = <String, List<ParsedCel>>{};
  for (final entry in byCell.entries) {
    final symbol = entry.key.split('|').first;
    final folded = _foldRevisions(
      entry.value,
      rankOf: (cel) => cel.revisionRank,
      fileOf: (cel) => cel.file,
    );
    switch (revisionPolicy) {
      case CelRevisionPolicy.latestOnly:
        final latest = folded.latest;
        (bySymbol[symbol] ??= []).add(
          ParsedCel(
            number: latest.number,
            insertion: latest.insertion,
            revisionRank: latest.revisionRank,
            file: latest.file,
            olderRevisions: folded.olderFiles,
          ),
        );
      case CelRevisionPolicy.all:
        (bySymbol[symbol] ??= []).addAll(folded.sorted);
      case CelRevisionPolicy.originalOnly:
        final original = folded.sorted.first;
        if (original.revisionRank == 0) {
          (bySymbol[symbol] ??= []).add(original);
        } else {
          // Rule F: a cel may exist only as a revision (`A7_` with no
          // `A7`) — originalOnly keeps the earliest so the cel does
          // not vanish, with a warning.
          (bySymbol[symbol] ??= []).add(original);
          warnings.add(
            ImportWarning(
              'folderNoOriginal',
              '{file}: no unmarked original — kept the earliest revision.',
              {'file': original.file},
            ),
          );
        }
    }
  }
  final layers = [
    for (final entry in bySymbol.entries)
      ParsedCelLayer(
        symbol: entry.key,
        cells: [...entry.value]..sort((a, b) {
          final byNumber = a.number.compareTo(b.number);
          if (byNumber != 0) {
            return byNumber;
          }
          final byInsertion = a.insertion.compareTo(b.insertion);
          if (byInsertion != 0) {
            return byInsertion;
          }
          return a.revisionRank.compareTo(b.revisionRank);
        }),
      ),
  ]..sort((a, b) => a.symbol.compareTo(b.symbol));
  return layers;
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

  /// (symbol, cell label) → revisions seen, top-level cel grammar.
  final celFiles = <String, List<ParsedCel>>{};
  final pictureFiles = <String, List<({int rank, String file})>>{};
  final references = <ParsedReference>[];
  final subfolderFiles = <String, List<CutFolderEntry>>{};

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
      // A process subfolder's file (rule G) — collected per subfolder.
      (subfolderFiles[topSegment] ??= []).add(
        CutFolderEntry(segments.sublist(1).join('/')),
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
        final insertion = config.insertionLetters ? match.group(3)! : '';
        if (!config.insertionLetters && match.group(3)!.isNotEmpty) {
          excluded.add(
            ParsedExclusion(
              path: entry.relativePath,
              reason: ExclusionReason.insertionLettersOff,
            ),
          );
          return;
        }
        final rank = _revisionRankOf(match.group(4)!);
        final cel = ParsedCel(
          number: number,
          insertion: insertion,
          revisionRank: rank,
          file: entry.relativePath,
        );
        (celFiles['$symbol|$number|$insertion'] ??= []).add(cel);
        return;
      }
    }

    excluded.add(
      ParsedExclusion(path: entry.relativePath, reason: ExclusionReason.unrecognized),
    );
  }
}

/// Parses [folderName] + [entries] under [config]. Pure — the preview
/// What the folder name says, before any file is looked at.
typedef CutFolderNameParts = ({
  String? title,
  String? episode,
  List<String> cutNumbers,
  List<String> processTokens,
});

/// Rule A walked left to right: `title_episode_cut_process`.
///
/// The FIRST numeric is the episode only when a TITLE token preceded it —
/// a folder starting with numbers names cuts alone (`069_077_086_loeks`,
/// `264_lo`: the measured no-title shapes). And a titled folder whose only
/// numeric landed as the episode named just the cut (`kht_264`), so that
/// number moves back.
CutFolderNameParts _walkNameTokens(List<String> tokens) {
  String? title;
  String? episode;
  final cutNumbers = <String>[];
  final trailingProcess = <String>[];
  var seenNumeric = false;
  var seenTitle = false;
  for (final token in tokens) {
    if (_numericToken.hasMatch(token)) {
      if (!seenNumeric && seenTitle) {
        episode = token;
      } else {
        cutNumbers.add(token);
      }
      seenNumeric = true;
    } else if (!seenNumeric) {
      title = title == null ? token : '${title}_$token';
      seenTitle = true;
    } else {
      trailingProcess.add(token);
    }
  }
  final loneNumeric = episode;
  if (cutNumbers.isEmpty && loneNumeric != null) {
    cutNumbers.add(loneNumeric);
    episode = null;
  }
  return (
    title: title,
    episode: episode,
    cutNumbers: cutNumbers,
    processTokens: _decomposeProcess(trailingProcess),
  );
}

/// The folder name under the configured rule, warning into [warnings] for
/// what it had to drop (a second cut with multi-cut folders off) or could
/// not find (no cut number at all).
CutFolderNameParts _folderNameParts({
  required String folderName,
  required CutFolderParseConfig config,
  required String? parentFolderName,
  required List<ImportWarning> warnings,
}) {
  var parts = switch (config.nameRule) {
    CutFolderNameRule.titleEpisodeCut => _walkNameTokens(folderName.split('_')),
    CutFolderNameRule.cutNumberOnly => (
      title: null,
      episode: null,
      cutNumbers: <String>[folderName],
      processTokens: config.parentFolderProcessHint && parentFolderName != null
          ? _decomposeProcess([parentFolderName])
          : <String>[],
    ),
  };
  if (!config.multiCutFolders && parts.cutNumbers.length > 1) {
    warnings.add(
      ImportWarning(
        'folderMultiCutOff',
        'Folder names {n} cuts but multi-cut folders are off — only {first} '
        'imports.',
        {'n': '${parts.cutNumbers.length}', 'first': parts.cutNumbers.first},
      ),
    );
    parts = (
      title: parts.title,
      episode: parts.episode,
      cutNumbers: [parts.cutNumbers.first],
      processTokens: parts.processTokens,
    );
  }
  if (parts.cutNumbers.isEmpty) {
    warnings.add(
      const ImportWarning(
        'folderNoCutNumber',
        'No cut number found in the folder name.',
      ),
    );
  }
  return parts;
}

/// re-runs it on every knob change.
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
  final layers = _buildLayers(
    bins.celFiles,
    revisionPolicy: config.revisionPolicy,
    warnings: warnings,
  );
  final pictures = _foldPictures(bins.pictureFiles);

  // --- Process subfolders ---------------------------------------------------
  final processGroups = _processGroups(
    subfolderFiles: bins.subfolderFiles,
    config: config,
    excluded: excluded,
    warnings: warnings,
  );

  return CutFolderParseResult(
    folderName: folderName,
    title: name.title,
    episode: name.episode,
    cutNumbers: name.cutNumbers,
    processTokens: name.processTokens,
    layers: layers,
    pictures: pictures,
    references: bins.references,
    processGroups: processGroups,
    excluded: excluded,
    warnings: warnings,
  );
}
