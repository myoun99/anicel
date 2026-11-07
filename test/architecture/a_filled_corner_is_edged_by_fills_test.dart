import 'package:flutter_test/flutter_test.dart';

import '../../tool/source_brackets.dart';
import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨A FILLED CORNER WITH AN EDGE IS A `SuperellipseFace`
/// (`lib/src/ui/theme/app_theme.dart`) — its edge drawn by fills, never by
/// the stroke [ShapeDecoration] draws a superellipse's side with.
///
/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q9 (유저 2026-11-08, 2): 「가장자리를
/// 정확한 식으로 칠하게 바꿔 그려 본다」 — and 「맞으면 앱의 테두리 전부에 같은
/// 그리기를 씁니다」. A behaviour test of one face cannot hold 「전부」: a
/// `ShapeDecoration` written tomorrow strokes its side perfectly. What gives
/// one away is what it is handed — a colour, and a side (written out, or
/// carried in by another face's `shape`) — so that is what is scanned for.
///
/// ⛔Not a decoration with a side and NO colour — an outline over whatever
/// lies under it. 🗣️a-live-dock-frame-costs-a-whole-draw-Q11 (유저 2026-11-08)
/// fills one with its ground only where that is one colour with nothing
/// passing behind it — the command pill, an outlined icon button — and a
/// clear flyout chip, a pill strip, a group tab or a tip cell has its
/// hover ink behind it and keeps its stroke: no scan tells the two apart.
void main() {
  test('no ShapeDecoration under lib/ is handed both a colour and a side, '
      'outside the ledger — and every ledger entry still is', () {
    expectSetMatchesLedger(
      [
        for (final file in dartFilesUnder('lib'))
          ..._strokedFaces(libPath(file), file.readAsStringSync()),
      ],
      _strokedOnPurpose.keys,
      unledgered:
          'a filled corner with an edge is a `SuperellipseFace(color:, '
          'edge:)` — its edge is drawn by fills. One that must stroke goes '
          'in the ledger, with why',
      paidOff: 'these are gone — take them off the list',
    );
  });

  test('every ledger entry says why', () {
    expectEveryEntrySaysWhy(_strokedOnPurpose);
  });

  test('the scan sees a planted face by its side and by a borrowed shape, '
      'and not an outline, a face or one in a comment', () {
    const planted = '''
final a = ShapeDecoration(
  color: AppColors.surface,
  shape: AppShapes.container(4, side: BorderSide(color: AppColors.hairline)),
);
final b = ShapeDecoration(color: AppColors.backdrop, shape: frame.shape);
final c = ShapeDecoration(
  shape: AppShapes.control(32, side: BorderSide(color: AppColors.hairline)),
);
final d = ShapeDecoration(color: AppColors.surface, shape: AppShapes.control(32));
final e = SuperellipseFace(
  color: AppColors.surface,
  edge: AppShapes.container(4, side: BorderSide(color: AppColors.hairline)),
);
// final f = ShapeDecoration(color: x, shape: AppShapes.control(1, side: s));
''';
    expect(_strokedFaces('planted.dart', planted), [
      'planted.dart #1',
      'planted.dart #2',
    ]);
  });
}

/// Faces handed a colour and a side that stroke it on purpose, by
/// `path #k` — the k-th such face in its file.
const _strokedOnPurpose = <String, String>{
  'lib/src/ui/widgets/panel_flyout.dart #1':
      'never both: a plate has a ground and no side, a clear chip a side and '
      'no colour — and the clear chip keeps its stroke, its hover ink lying '
      'behind it on the button\'s Material '
      '(a-live-dock-frame-costs-a-whole-draw-Q11)',
  'lib/src/ui/export/export_preset_rail.dart #1':
      'a translucent wash or none inside an outline, in the export window — '
      'drawn live, never from an image '
      '(a-live-dock-frame-costs-a-whole-draw-Q11)',
  'lib/src/ui/dialogs/instruction_set_editor_dialog.dart #1':
      'a circle (`CircleBorder`), not a superellipse — a dialog\'s, drawn '
      'live and never from an image, and a circle\'s side was not probed',
};

/// Each `ShapeDecoration(` in [source] handed a colour and a side — written
/// out in it, or carried in by another decoration's `shape` — by
/// `path #k`, the k-th in the file.
List<String> _strokedFaces(String path, String source) {
  final code = withoutComments(source);
  final calls = RegExp(r'\bShapeDecoration\(').allMatches(code);
  final stroked = [
    for (final call in calls)
      if (_strokes(code, call.end - 1)) call,
  ];
  return [for (var k = 1; k <= stroked.length; k += 1) '$path #$k'];
}

bool _strokes(String code, int openAt) {
  if (namedArgument(code, openAt, 'color') == null) {
    return false;
  }
  final side = namedArgumentWithin(code, openAt, 'side');
  final shape = namedArgument(code, openAt, 'shape') ?? '';
  return (side != null && side != 'BorderSide.none') ||
      shape.endsWith('.shape');
}
