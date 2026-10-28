import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨**A STAND-IN MOVIE IS SPELLED ONCE** — `standInMovieBytes`
/// (`test/helpers/stand_in_movie.dart`).
///
/// Board test-fake-movie-files-are-three-copies (2026-10-29): twenty-five
/// writes across fifteen tests each spelled the four bytes a movie no
/// decoder reads holds — one meaning, agreed on by copy. Every copy passed
/// on its own, so the ratchet is a source scan, and it proves it can see
/// what it forbids.
void main() {
  /// ⚠️Exempt from its own scan: the lines it plants are STRINGS holding
  /// the very spelling the scan matches.
  const itself = 'test/architecture/a_stand_in_movie_is_spelled_once_test.dart';
  const spelling = 'test/helpers/stand_in_movie.dart';

  final spellsIt = RegExp(r'\b0,\s*0,\s*0,\s*24\b');

  test('the scan sees what it forbids', () {
    expect(spellsIt.hasMatch('writeAsBytes(const [0, 0, 0, 24])'), isTrue);
    expect(spellsIt.hasMatch('..writeAsBytesSync([0,0,0,24]);'), isTrue);
    expect(spellsIt.hasMatch('write([\n  0,\n  0,\n  0,\n  24,\n])'), isTrue);
    expect(spellsIt.hasMatch('writeAsBytes(standInMovieBytes)'), isFalse);
    expect(spellsIt.hasMatch('[10, 0, 0, 240]'), isFalse);
  });

  test('no test spells a stand-in movie\'s bytes out itself', () {
    expect(
      [
        for (final file in dartFilesUnder('test'))
          if (file.path.replaceAll(r'\', '/') case final path
              when path != itself &&
                  path != spelling &&
                  spellsIt.hasMatch(file.readAsStringSync()))
            path,
      ],
      isEmpty,
      reason: 'write it with `standInMovieBytes` — a movie the test reads '
          'is written with `writeEncodedMovie`',
    );
  });
}
