import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨A KEPT PIECE NAMES EVERY FIELD IT HAS IN ITS FACTS
/// (`KeptPiece`, `lib/src/ui/timeline/memo_token.dart`).
///
/// A kept piece is handed back as it was built while its facts hold, so a
/// field its facts leave out is one whose change shows nothing: the piece
/// keeps what it was built from. Mutation found five such (I-57, 10-14) —
/// the corner's size and whether it takes a press, the splitter's extent
/// and the two extents its drag is clamped to — and no behaviour test told
/// them apart, because nothing a test drives changes them while the piece
/// stands. ⛔So this reads the source: every field the class declares is
/// named in its facts (a callback by whether there is one, R13-2).
void main() {
  test('every field a kept piece declares is in its facts', () {
    final pieces = <String>[];
    final missing = <String>[];
    for (final file in dartFilesUnder('lib/src')) {
      for (final piece in _keptPieces(file.readAsStringSync())) {
        pieces.add(piece.name);
        missing.addAll([
          for (final field in _leftOut(piece)) '${libPath(file)}: $field',
        ]);
      }
    }
    expect(
      pieces.length,
      greaterThanOrEqualTo(5),
      reason: 'premise: the scan found the kept pieces',
    );
    expect(
      missing,
      isEmpty,
      reason: 'name each field in `facts` — left out, a change of it leaves '
          'the piece as it was',
    );
  });

  test('the scan sees a field left out, and a static is no field', () {
    const planted = '''
class Planted extends KeptPiece {
  const Planted({super.key, required this.shown, this.onPressed});

  static const double thickness = 4;

  final bool shown;
  final VoidCallback? onPressed;
  final double? left;

  @override
  Object? get facts => (shown, onPressed != null, thickness);

  @override
  Widget buildKept(BuildContext context) => const SizedBox();
}
''';
    final pieces = _keptPieces(planted).toList();

    expect([for (final piece in pieces) piece.fields], [
      ['shown', 'onPressed', 'left'],
    ]);
    expect(_leftOut(pieces.single), ['Planted.left']);
  });
}

typedef _Piece = ({String name, List<String> fields, String facts});

/// Every `class … extends KeptPiece` in [source]: its instance fields, and
/// what its `facts` getter returns.
Iterable<_Piece> _keptPieces(String source) sync* {
  final head = RegExp(r'^class (\w+) extends KeptPiece \{', multiLine: true);
  final field = RegExp(r'^  final .+ (\w+);$', multiLine: true);
  final facts = RegExp('get facts =>([^;]*);');
  for (final match in head.allMatches(source)) {
    final end = source.indexOf('\n}', match.end);
    final body = source.substring(match.end, end < 0 ? source.length : end);
    yield (
      name: match.group(1)!,
      fields: [for (final found in field.allMatches(body)) found.group(1)!],
      facts: facts.firstMatch(body)?.group(1) ?? '',
    );
  }
}

/// [piece]'s fields its facts do not name.
List<String> _leftOut(_Piece piece) => [
  for (final field in piece.fields)
    if (!RegExp('\\b$field\\b').hasMatch(piece.facts)) '${piece.name}.$field',
];
