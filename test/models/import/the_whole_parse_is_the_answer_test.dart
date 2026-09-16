import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/import/cut_folder_parse.dart';

/// 🚨THE WHOLE ANSWER, NOT THE FIELDS A TEST REMEMBERED TO NAME.
///
/// The rule-by-rule tests beside this one each read a handful of fields,
/// so a parser change that quietly moves something they do not look at --
/// an exclusion's reason, a warning, a picture's older revisions, the
/// ORDER of anything -- passes them all. This dumps every field of the
/// result and compares the text, which is what makes it safe to restructure
/// the parser (the audit, 2026-09-05).
///
/// ⚠️When a change to these strings is INTENDED, read the diff and update
/// the expectation. A golden nobody may edit is a golden nobody reads.
void main() {
  test('the measured delivery folders parse to exactly this', () {
    expect(_dump(_upn()), '''
folder: upn_02_063_lo_ss_k
title: upn
episode: 02
cuts: 063
process: lo, ss, k
layer A: A1.png A2.png A3.png A4.png A5.png A6.png A7.png A8.png A9.png A10.png A11.png A12.png A13.png A14.png A15.png A16.png
layer B: B1_ss.png(<B1.png) B2.png B3.png B4.png B5.png B6.png B7.png B8.png B9.png B10.png B11.png
picture BG: _BG.png
reference _TS_e.png: timesheetScan
excluded _old: excluded name
excluded _old/A1.png: excluded name
''');
  });

  test('the compound-symbol folder parses to exactly this', () {
    expect(_dump(_csm068()), '''
folder: csm_13_068_gen
title: csm
episode: 13
cuts: 068
process: gen
layer ABH: ABH1.png
layer C: C1.png
layer G: G1.png G3.png G3a.png G3b.png G11.png G11a.png
picture BG: _BG.png
picture BOOK3: _BOOK3.png
reference _068_ts_gen.clip: workFile
reference _csm_13_068_loek.clip: workFile
reference _mov.mov: movie
excluded LO/A1.png: process subfolder (archive)
''');
  });

  test('a no-title multi-cut folder parses to exactly this', () {
    expect(_dump(_noTitle()), '''
folder: 069_077_086_loeks
cuts: 069, 077, 086
process: lo, e, k, s
layer A: A1.png
''');
  });
}

CutFolderParseResult _upn() => parseCutFolder(
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

CutFolderParseResult _csm068() => parseCutFolder(
  folderName: 'csm_13_068_gen',
  entries: const [
    CutFolderEntry('ABH1.png'),
    CutFolderEntry('C1.png'),
    CutFolderEntry('G1.png'),
    CutFolderEntry('G3.png'),
    CutFolderEntry('G3a.png'),
    CutFolderEntry('G3b.png'),
    CutFolderEntry('G11.png'),
    CutFolderEntry('G11a.png'),
    CutFolderEntry('_BG.png'),
    CutFolderEntry('_BOOK3.png'),
    CutFolderEntry('_068_ts_gen.clip'),
    CutFolderEntry('_csm_13_068_loek.clip'),
    CutFolderEntry('_mov.mov'),
    CutFolderEntry('LO', isDirectory: true),
    CutFolderEntry('LO/A1.png'),
  ],
);

CutFolderParseResult _noTitle() => parseCutFolder(
  folderName: '069_077_086_loeks',
  entries: const [CutFolderEntry('A1.png')],
);

/// Every field, in a fixed order, one line each — absent lists print
/// nothing so the text says what the folder HAS.
String _dump(CutFolderParseResult result) {
  final lines = <String>['folder: ${result.folderName}'];
  void say(String label, String? value) {
    if (value != null && value.isNotEmpty) {
      lines.add('$label: $value');
    }
  }

  say('title', result.title);
  say('episode', result.episode);
  say('cuts', result.cutNumbers.join(', '));
  say('process', result.processTokens.join(', '));
  for (final layer in result.layers) {
    final cells = [
      for (final cell in layer.cells)
        if (cell.olderRevisions.isEmpty)
          cell.file
        else
          '${cell.file}(<${cell.olderRevisions.join(' ')})',
    ];
    lines.add('layer ${layer.symbol}: ${cells.join(' ')}');
  }
  for (final picture in result.pictures) {
    final older = picture.olderRevisions.isEmpty
        ? ''
        : ' (<${picture.olderRevisions.join(' ')})';
    lines.add('picture ${picture.name}: ${picture.file}$older');
  }
  for (final reference in result.references) {
    lines.add('reference ${reference.file}: ${reference.kind.name}');
  }
  for (final group in result.processGroups) {
    for (final layer in group.layers) {
      lines.add(
        'group ${group.process} layer ${layer.symbol}: '
        '${[for (final cell in layer.cells) cell.file].join(' ')}',
      );
    }
  }
  for (final exclusion in result.excluded) {
    lines.add('excluded ${exclusion.path}: ${exclusion.reason.label}');
  }
  for (final warning in result.warnings) {
    lines.add('warning: $warning');
  }
  return '${lines.join('\n')}\n';
}
