import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/import/cut_folder_parse.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';

/// The parser against the USER'S REAL delivery folders (measured
/// 2026-07-29 — CSM3 · UPN · KHT) plus the drift cases (rule K): this is
/// the ground truth the whole folder-drop import stands on.
void main() {
  List<CutFolderEntry> files(List<String> paths) => [
    for (final path in paths) CutFolderEntry(path),
  ];

  /// Each layer as its symbol and whose correction it is, in stack order.
  List<(String, LayerRevise?)> layersOf(CutFolderParseResult result) => [
    for (final layer in result.layers) (layer.symbol, layer.correction),
  ];

  test('upn_02_063_lo_ss_k: layers A/B by symbol, B1_ss is 총작감 of B1, '
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
    expect(result.cutNumber, '063');
    expect(result.processTokens, ['lo', 'ss', 'k']);

    expect(layersOf(result), [
      ('A', null),
      ('B', null),
      ('B', LayerRevise.chiefAnimationDirector),
    ]);
    expect(result.layers[0].cells, hasLength(16));
    expect(result.layers[1].cells, hasLength(11));
    // `B1_ss` is not a revision of B1 any more but a drawing of its own —
    // B1 keeps its file, and the correction's layer holds B1_ss.
    expect(result.layers[1].cells.first.file, 'B1.png');
    expect(result.layers[1].cells.first.olderRevisions, isEmpty);
    expect(result.layers[2].cells.single.file, 'B1_ss.png');
    expect(result.layers[2].cells.single.label, '1');

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

    expect(result.cutNumber, '068');
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

  test('F-429-Q3: csm_13_069_077_086_loeks is ONE cut, named by its first '
      'number — the rest are not read; process decomposes longest-first',
      () {
    final result = parseCutFolder(
      folderName: 'csm_13_069_077_086_loeks',
      entries: files(['A1.png', 'A15b.png', 'B1.png']),
    );

    expect(result.cutNumber, '069');
    expect(result.warnings, isEmpty, reason: 'nothing was dropped to warn of');
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

  test('rule F: revision underscores fold to the LATEST, always; a '
      'revision-only cel (A7_ with no A7) is still a cel', () {
    final result = parseCutFolder(
      folderName: 'csm_13_074_gen',
      entries: files([
        'A1.png',
        'A2.png', 'A2_.jpg', 'A2__.jpg',
        'A7_.png',
      ]),
    );
    final a = result.layers.single;
    expect(a.cells.map((c) => c.label), ['1', '2', '7']);
    final a2 = a.cells[1];
    expect(a2.file, 'A2__.jpg', reason: 'extension may change per revision');
    expect(a2.olderRevisions, ['A2.png', 'A2_.jpg']);
    expect(a.cells[2].file, 'A7_.png');
    expect(result.warnings, isEmpty);
  });

  group('rule N: the letters after the number say whose correction', () {
    test('A1s and A1_s are both 작감 of A1 — one layer of the symbol, named '
        'by the symbol alone (F-429-Q2)', () {
      final result = parseCutFolder(
        folderName: 'csm_13_074_lo',
        entries: files(['A1.png', 'A2.png', 'A1s.png', 'A2_s.png']),
      );

      expect(layersOf(result), [
        ('A', null),
        ('A', LayerRevise.animationDirector),
      ]);
      final corrections = result.layers[1];
      expect(corrections.cells.map((c) => c.label), ['1', '2']);
      expect(corrections.cells.map((c) => c.file), ['A1s.png', 'A2_s.png']);
      expect(
        result.layers[0].cells.map((c) => c.file),
        ['A1.png', 'A2.png'],
        reason: 'a correction is never a revision of the cel it corrects',
      );
    });

    test('each correction letter names its own layer, standing over the '
        'symbol\'s own in the colour label\'s order', () {
      final result = parseCutFolder(
        folderName: 'csm_13_074_lo',
        entries: files([
          'A1.png',
          'A1k.png',
          'A1_ss.png',
          'A1s.png',
          'A1e.png',
        ]),
      );

      expect(layersOf(result), [
        ('A', null),
        ('A', LayerRevise.direction),
        ('A', LayerRevise.animationDirector),
        ('A', LayerRevise.chiefAnimationDirector),
        ('A', LayerRevise.director),
      ]);
    });

    test('a correction\'s own revisions fold within it (A1s → A1s_; '
        'A2_s → A2_s_)', () {
      final result = parseCutFolder(
        folderName: 'csm_13_074_lo',
        entries: files([
          'A1.png',
          'A2.png',
          'A1s.png',
          'A1s_.png',
          'A2_s.png',
          'A2_s_.png',
        ]),
      );

      final corrections = result.layers.singleWhere(
        (layer) => layer.correction == LayerRevise.animationDirector,
      );
      expect(corrections.cells.map((c) => c.file), [
        'A1s_.png',
        'A2_s_.png',
      ]);
      expect(corrections.cells[0].olderRevisions, ['A1s.png']);
      expect(corrections.cells[1].olderRevisions, ['A2_s.png']);
    });

    test('letters that name no correction stay the insertion they always '
        'read as — G3a, and A1es (two corrections in one run)', () {
      final result = parseCutFolder(
        folderName: 'csm_13_074_lo',
        entries: files(['A1.png', 'A1es.png', 'G3.png', 'G3a.png']),
      );

      expect(layersOf(result), [('A', null), ('G', null)]);
      expect(result.layers[0].cells.map((c) => c.label), ['1', '1es']);
      expect(result.layers[1].cells.map((c) => c.label), ['3', '3a']);
    });

    test('a correction whose symbol has no cels of its own is still its '
        'own layer — the plan decides where it stands', () {
      final result = parseCutFolder(
        folderName: 'csm_13_074_lo',
        entries: files(['B1s.png', 'B2s.png']),
      );

      expect(layersOf(result), [('B', LayerRevise.animationDirector)]);
      expect(result.layers.single.cells.map((c) => c.label), ['1', '2']);
    });
  });

  group('the colour label each layer comes in wearing', () {
    LayerMark markOfFirst(String folderName, String correctionFile) {
      final result = parseCutFolder(
        folderName: folderName,
        entries: files(['A1.png', correctionFile]),
      );
      return result.markOf(result.layers.last);
    }

    test('the folder\'s stage, and the correction its letters name', () {
      final layout = parseCutFolder(
        folderName: 'upn_02_063_lo_ss_k',
        entries: files(['A1.png']),
      );
      expect(layout.stage, LayerProcess.layout);
      expect(layout.markOf(layout.layers.single).process, LayerProcess.layout);
      expect(layout.markOf(layout.layers.single).revise, isNull);

      final corrected = markOfFirst('csm_13_074_gen', 'A1s.png');
      expect(corrected.process, LayerProcess.key);
      expect(corrected.revise, LayerRevise.animationDirector);
    });

    test('원화 wins over LO — the top level is the folder\'s newest work', () {
      final result = parseCutFolder(
        folderName: 'csm_13_074_lo_gen',
        entries: files(['A1.png']),
      );
      expect(result.stage, LayerProcess.key);
      expect(
        parseCutFolder(folderName: 'csm_13_074_g', entries: const []).stage,
        LayerProcess.key,
        reason: 'g is 원화 too',
      );
    });

    test('a folder that names no stage gives what a new animation layer is '
        'born with', () {
      final result = parseCutFolder(
        folderName: 'csm_13_074',
        entries: files(['A1.png', 'A1e.png']),
      );
      expect(result.stage, isNull);
      expect(
        result.markOf(result.layers.first).process,
        LayerMark.bornOfKind(LayerKind.animation).process,
      );
      expect(result.markOf(result.layers.last).revise, LayerRevise.direction);
    });
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

    expect(result.cutNumber, '266');
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

  test('rule G/M: a process subfolder is the ARCHIVE — always excluded, '
      'and every file in it listed (F-429-Q3)', () {
    final result = parseCutFolder(
      folderName: 'csm_13_074_gen',
      entries: [
        const CutFolderEntry('LO', isDirectory: true),
        const CutFolderEntry('LO/A1.png'),
        const CutFolderEntry(r'LO\A2.png'),
        const CutFolderEntry('GEN', isDirectory: true),
        const CutFolderEntry('GEN/A1.png'),
        const CutFolderEntry('A1.png'),
      ],
    );

    expect(
      [
        for (final exclusion in result.excluded)
          if (exclusion.reason == ExclusionReason.processSubfolder)
            exclusion.path,
      ],
      ['LO/A1.png', 'LO/A2.png', 'GEN/A1.png'],
      reason: 'listed by file, in forward slashes whichever the walk spoke',
    );
    expect(
      result.layers.single.cells.single.file,
      'A1.png',
      reason: 'the top level is the folder\'s cel set',
    );
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

  test('a NO-TITLE multi-cut folder names its first cut — the first number '
      'is never eaten as an episode (the measured 069_077_086 shape)', () {
    final result = parseCutFolder(
      folderName: '069_077_086_loeks',
      entries: files(['A1.png']),
    );
    expect(result.episode, isNull);
    expect(result.cutNumber, '069');
    expect(result.processTokens, ['lo', 'e', 'k', 's']);

    // A titled folder still reads title_episode_cut.
    final titled = parseCutFolder(
      folderName: 'csm_13_085_gen',
      entries: files(['A1.png']),
    );
    expect(titled.title, 'csm');
    expect(titled.episode, '13');
    expect(titled.cutNumber, '085');

    // …and a titled folder's ONLY number is its cut.
    final lone = parseCutFolder(folderName: 'kht_264', entries: const []);
    expect(lone.episode, isNull);
    expect(lone.cutNumber, '264');
  });

  test('a folder name with no number names no cut — and says so', () {
    final result = parseCutFolder(
      folderName: 'delivery',
      entries: files(['A1.png']),
    );
    expect(result.cutNumber, isNull);
    expect(result.warnings.map((w) => w.key), ['folderNoCutNumber']);
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
      maxLayerSymbolLength: 2,
      insertionLetters: false,
      excludeNames: ['_old'],
    );
    expect(CutFolderParseConfig.fromJson(config.toJson()), config);
  });
}
