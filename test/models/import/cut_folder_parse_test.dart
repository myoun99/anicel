import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/import/cut_folder_parse.dart';

/// The parser against the USER'S REAL delivery folders (measured
/// 2026-07-29 — CSM3 · UPN · KHT) plus the drift cases (rule K): this is
/// the ground truth the whole folder-drop import stands on.
void main() {
  List<CutFolderEntry> files(List<String> paths) => [
    for (final path in paths) CutFolderEntry(path),
  ];

  test('upn_02_063_lo_ss_k: layers A/B by symbol, revision variant folds, '
      '_BG picture, _TS scan reference, _old excluded', () {
    final result = parseCutFolder(
      folderName: 'upn_02_063_lo_ss_k',
      entries: [
        for (var i = 1; i <= 16; i += 1) CutFolderEntry('A$i.png'),
        for (var i = 1; i <= 11; i += 1) CutFolderEntry('B$i.png'),
        const CutFolderEntry('B1_ss.png'),
        const CutFolderEntry('_BG.png'),
        const CutFolderEntry('_TS_e.png'),
        const CutFolderEntry('_old', isDirectory: true),
        const CutFolderEntry('_old/A1.png'),
      ],
    );

    expect(result.title, 'upn');
    expect(result.episode, '02');
    expect(result.cutNumbers, ['063']);
    expect(result.processTokens, ['lo', 'ss', 'k']);

    expect(result.layers.map((l) => l.symbol), ['A', 'B']);
    expect(result.layers[0].cells, hasLength(16));
    expect(result.layers[1].cells, hasLength(11));
    // `B1_ss` is a REVISION of B1 (rule F variant): latest-only keeps it
    // and lists the original as an older revision.
    final b1 = result.layers[1].cells.first;
    expect(b1.file, 'B1_ss.png');
    expect(b1.olderRevisions, ['B1.png']);

    expect(result.pictures.single.name, 'BG');
    expect(
      result.references.single.kind,
      ParsedReferenceKind.timesheetScan,
    );
    expect(
      result.excluded.any((e) => e.path.startsWith('_old')),
      isTrue,
      reason: '_old/ is excluded but LISTED (nothing exits silently)',
    );
  });

  test('csm_13_068_gen: compound symbol ABH, insertion letters G3a..G11a, '
      'skipped numbers survive, _BG補足 own picture, clip/mov references',
      () {
    final result = parseCutFolder(
      folderName: 'csm_13_068_gen',
      entries: files([
        'ABH1.png',
        'C1.png',
        'E1.png', 'E2.png', 'E3.png', 'E4.png',
        'F1.png', 'F2.png',
        for (var i = 1; i <= 13; i += 1) 'G$i.png',
        'G3a.png', 'G3b.png', 'G3c.png', 'G11a.png',
        '_BG.png',
        '_BG補足.png',
        '_BOOK3.png',
        '_068_ts_gen.clip',
        '_068_ts_gen_1.jpg',
        '_csm_13_068_loek.clip',
        '_mov.mov',
      ]),
    );

    expect(result.cutNumbers, ['068']);
    expect(result.processTokens, ['gen']);
    expect(result.layers.map((l) => l.symbol), ['ABH', 'C', 'E', 'F', 'G']);

    final g = result.layers.firstWhere((l) => l.symbol == 'G');
    expect(g.cells, hasLength(17));
    // Rule C natural order: 3 < 3a < 3b < 3c < 4.
    final labels = g.cells.map((c) => c.label).toList();
    final i3 = labels.indexOf('3');
    expect(labels.sublist(i3, i3 + 5), ['3', '3a', '3b', '3c', '4']);

    expect(result.pictures.map((p) => p.name), ['BG', 'BG補足', 'BOOK3']);
    expect(
      result.references.map((r) => r.kind),
      containsAll([
        ParsedReferenceKind.timesheetScan,
        ParsedReferenceKind.workFile,
        ParsedReferenceKind.movie,
      ]),
    );
  });

  test('rule H: csm_13_069_077_086_loeks names THREE cuts sharing one cel '
      'set (the field 겸용컷); process decomposes longest-first', () {
    final result = parseCutFolder(
      folderName: 'csm_13_069_077_086_loeks',
      entries: files(['A1.png', 'A15b.png', 'B1.png']),
    );

    expect(result.cutNumbers, ['069', '077', '086']);
    expect(result.processTokens, ['lo', 'e', 'k', 's']);
    expect(
      parseCutFolder(
        folderName: 'csm_13_070_loekss',
        entries: const [],
      ).processTokens,
      ['lo', 'e', 'k', 'ss'],
      reason: 'ss is 총작감, never s+s (longest-first)',
    );
  });

  test('rule F: revision underscores fold to the LATEST by default; a '
      'revision-only cel (A7_ with no A7) survives every policy', () {
    final entries = files([
      'A1.png',
      'A2.png', 'A2_.jpg', 'A2__.jpg',
      'A7_.png',
    ]);

    final latest = parseCutFolder(
      folderName: 'csm_13_074_gen',
      entries: entries,
    );
    final a = latest.layers.single;
    expect(a.cells.map((c) => c.label), ['1', '2', '7']);
    final a2 = a.cells[1];
    expect(a2.file, 'A2__.jpg', reason: 'extension may change per revision');
    expect(a2.olderRevisions, ['A2.png', 'A2_.jpg']);

    final originals = parseCutFolder(
      folderName: 'csm_13_074_gen',
      entries: entries,
      config: const CutFolderParseConfig(
        revisionPolicy: CelRevisionPolicy.originalOnly,
      ),
    );
    expect(
      originals.layers.single.cells.map((c) => c.file),
      contains('A7_.png'),
      reason: 'no unmarked original — the earliest revision is kept',
    );
    expect(originals.warnings, isNotEmpty);
  });

  test('rule I (KHT): cutNumberOnly folders read the cut from the name and '
      'the process from the parent folder hint; TDTS registers as a '
      'timing sheet', () {
    final result = parseCutFolder(
      folderName: '266',
      parentFolderName: 'LO',
      config: const CutFolderParseConfig(
        nameRule: CutFolderNameRule.cutNumberOnly,
        parentFolderProcessHint: true,
      ),
      entries: files([
        'A1.png',
        '_TS.tdts',
        '_TS_sAc266_266_0001.jpg',
        '_266_lo.mov',
      ]),
    );

    expect(result.cutNumbers, ['266']);
    expect(result.processTokens, ['lo']);
    expect(
      result.references.map((r) => r.kind),
      containsAll([
        ParsedReferenceKind.timingSheet,
        ParsedReferenceKind.timesheetScan,
        ParsedReferenceKind.movie,
      ]),
    );
  });

  test('rule G/M: process subfolders are ARCHIVES — excluded (and listed) '
      'by default, parsed into per-process groups when opted in', () {
    final entries = [
      const CutFolderEntry('LO', isDirectory: true),
      const CutFolderEntry('LO/A1.png'),
      const CutFolderEntry('LO/A2.png'),
      const CutFolderEntry('GEN', isDirectory: true),
      const CutFolderEntry('GEN/A1.png'),
      const CutFolderEntry('A1.png'),
    ];

    final defaults = parseCutFolder(
      folderName: 'csm_13_074_gen',
      entries: entries,
    );
    expect(defaults.processGroups, isEmpty);
    expect(
      defaults.excluded.where((e) => e.reason.contains('archive')),
      hasLength(3),
    );

    final included = parseCutFolder(
      folderName: 'csm_13_074_gen',
      entries: entries,
      config: const CutFolderParseConfig(includeProcessSubfolders: true),
    );
    expect(included.processGroups.map((g) => g.process), ['GEN', 'LO']);
    expect(
      included.processGroups
          .firstWhere((g) => g.process == 'LO')
          .layers
          .single
          .cells,
      hasLength(2),
    );
    expect(included.layers.single.cells, hasLength(1),
        reason: 'the top level stays the main cel set');
  });

  test('drift (rule K): a BOOK revision that lost its underscore prefix '
      'parses as a cel-looking layer — visible in the preview rather than '
      'silently dropped', () {
    final result = parseCutFolder(
      folderName: 'csm_13_084_gen',
      entries: files(['BOOK1_.jpg', 'A1.png']),
    );
    // BOOK exceeds nothing (4 letters) — it lands as a layer the user can
    // see and correct in the preview; the alternative (silent drop) hides
    // the file entirely.
    expect(result.layers.map((l) => l.symbol), ['A', 'BOOK']);
  });

  test('a NO-TITLE multi-cut folder names cuts only — the first number is '
      'never eaten as an episode (the measured 069_077_086 shape)', () {
    final result = parseCutFolder(
      folderName: '069_077_086_loeks',
      entries: files(['A1.png']),
    );
    expect(result.episode, isNull);
    expect(result.cutNumbers, ['069', '077', '086']);
    expect(result.processTokens, ['lo', 'e', 'k', 's']);

    // A titled folder still reads title_episode_cut.
    final titled = parseCutFolder(
      folderName: 'csm_13_085_gen',
      entries: files(['A1.png']),
    );
    expect(titled.title, 'csm');
    expect(titled.episode, '13');
    expect(titled.cutNumbers, ['085']);
  });

  test('the timesheet-scan rule needs a TOKEN boundary: `_BG_tsuki` stays '
      'a picture, `_TS_e` and `_085_ts_loe` are scans', () {
    final result = parseCutFolder(
      folderName: 'csm_13_085_gen',
      entries: files(['_BG_tsuki.png', '_TS_e.png', '_085_ts_loe.jpg']),
    );
    expect(result.pictures.map((p) => p.name), ['BG_tsuki']);
    expect(result.references, hasLength(2));
    expect(
      result.references.every(
        (r) => r.kind == ParsedReferenceKind.timesheetScan,
      ),
      isTrue,
    );
  });

  test('config round-trips through JSON (preset storage)', () {
    const config = CutFolderParseConfig(
      nameRule: CutFolderNameRule.cutNumberOnly,
      parentFolderProcessHint: true,
      multiCutFolders: false,
      maxLayerSymbolLength: 2,
      insertionLetters: false,
      revisionPolicy: CelRevisionPolicy.all,
      includeProcessSubfolders: true,
      excludeNames: ['_old'],
    );
    expect(CutFolderParseConfig.fromJson(config.toJson()), config);
  });
}
