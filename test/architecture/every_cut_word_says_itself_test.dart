import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// A WORD THE APP CUTS TO `…` SAYS THE WHOLE OF ITSELF (🗣️F-530, 유저
/// 2026-11-01: 「텍스트가 잘려서 ...으로 표시되는 위젯, 기본적으로 표시될땐
/// 툴팁으로 전 문장 표시하도록」): across through `EllipsisText`, down through
/// `VerticalWritingText`. A behaviour test covers the sites it pumps; a
/// `Text` with an ellipsis written tomorrow would look right and pass it.
void main() {
  const home = 'lib/src/ui/widgets/ellipsis_text.dart';

  /// The source without what its comments say — the lines before this rule
  /// are full of the words.
  String code(String source) => source
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  final across = RegExp(r'(?<![A-Za-z0-9_])TextOverflow\.ellipsis');
  final painted = RegExp(r"ellipsis:[^,\n]*'…'");
  final paintedDown = RegExp(r'overflow: VerticalTextOverflow\.ellipsis,');

  /// Everywhere a painter cuts a word, and why that word stays cut with
  /// nothing to say. ⛔A line here is a word nobody can read the end of: it
  /// needs a reason a person could not have hovered it.
  const paintedCuts = <String, String>{
    // The flip HUD's rail: under an IgnorePointer over the canvas, and gone
    // as the flip ends. It passes laidOutGlyph its maxWidth.
    'lib/src/ui/text/laid_out_glyph.dart': 'a cut for the flip HUD',
    'lib/src/ui/canvas/flip_hud_overlay.dart': 'the same HUD, stood up',
    // A block's column is set in as many slots as it has cells, so its
    // ellipsis is never reached.
    'lib/src/ui/timeline/timeline_block_word.dart': 'never cuts',
    // The sheet is a document: this is its print. See card F-530-Q1.
    'lib/src/ui/timesheet/timesheet_document_painter.dart': 'a printed cell',
    'lib/src/ui/timesheet/document_painter/timesheet_bands_pass.dart':
        'a printed memo',
  };

  test('only EllipsisText cuts a line', () {
    final hits = <String>[
      for (final file in dartFilesUnder('lib'))
        if (libPath(file) != home &&
            across.hasMatch(code(file.readAsStringSync())))
          libPath(file),
    ];
    expect(
      hits,
      isEmpty,
      reason:
          'build `EllipsisText(` instead — a cut label has to say the rest '
          'of itself',
    );
  });

  test('only the ledger cuts a painted word', () {
    final hits = <String>{
      for (final file in dartFilesUnder('lib'))
        if (painted.hasMatch(code(file.readAsStringSync())) ||
            paintedDown.hasMatch(code(file.readAsStringSync())))
          libPath(file),
    };
    expect(hits, unorderedEquals(paintedCuts.keys));
  });

  test('no test looks for text the way that misses a cut word', () {
    // `find.byType` asks for the exact type: it misses every EllipsisText,
    // and a test that expects to find NONE would pass for it. `find.anyText`
    // and `find.anyRichText` see them all.
    final blind = RegExp(r'find\.byType\((Rich)?Text\b');
    final hits = <String>[
      for (final file in dartFilesUnder('test'))
        if (!file.path.endsWith('every_cut_word_says_itself_test.dart'))
          if (blind.hasMatch(code(file.readAsStringSync()))) file.path,
    ];
    expect(hits, isEmpty, reason: 'reach for find.anyText');
  });

  test('the scans see what they guard', () {
    expect(across.hasMatch('overflow: TextOverflow.ellipsis,'), isTrue);
    expect(across.hasMatch('VerticalTextOverflow.ellipsis'), isFalse);
    expect(painted.hasMatch("ellipsis: '…',"), isTrue);
    expect(
      painted.hasMatch("ellipsis: maxWidth == null ? null : '…',"),
      isTrue,
    );
    expect(
      paintedDown.hasMatch('overflow: VerticalTextOverflow.ellipsis,'),
      isTrue,
    );
    final source = dartFilesUnder('lib')
        .singleWhere((file) => libPath(file) == home)
        .readAsStringSync();
    expect(source, contains('class EllipsisText extends Text'));
    expect(source, contains('with SummonsTooltip, TooltipBox'));
  });
}
