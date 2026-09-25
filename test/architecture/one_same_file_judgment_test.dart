import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// 🚨ONE answer to 「do these two paths name the same file」:
/// `services/persistence/same_file.dart` (`namesTheSameFile`).
///
/// It was five spellings — the held handle compared the strings whole,
/// three made the separators one and compared, and the save's own test
/// folded case as well — and they disagreed exactly where it hurt: the same
/// file picked in another case for a Save As let the readers go, kept the
/// session's own handle, and the rename stayed refused (audit 09-25). Every
/// copy made the separators one on the spot, so this reads the source for
/// that: a path with its separators made one, compared (`==`, `!=`) or
/// looked up (`contains`), anywhere but the one answer.
void main() {
  test('🚨no file but the one answer tells a file by its separators', () {
    const oneSeparator =
        r"""\.replaceAll\(\s*(?:r'\\'|'\\\\')\s*,\s*'/'\s*\)""";
    final judgesAFile = RegExp(
      '$oneSeparator(?:\\.toLowerCase\\(\\))?\\s*[!=]='
      '|[!=]=\\s*[\\w.\$]+$oneSeparator'
      '|\\.contains\\(\\s*[\\w.\$]+$oneSeparator',
    );
    expect(
      judgesAFile.hasMatch(r"previousPath.replaceAll(r'\', '/') != path"),
      isTrue,
      reason: 'the premise: it sees the shape the copies had',
    );
    expect(
      judgesAFile.hasMatch(
        r"if (read.contains(archive.replaceAll(r'\', '/')))",
      ),
      isTrue,
    );
    expect(
      judgesAFile.hasMatch(r"final path = file.path.replaceAll(r'\', '/');"),
      isFalse,
      reason: 'making a path\'s separators one is not telling files apart',
    );

    final offenders = <String>[];
    var scanned = 0;
    for (final file in dartFilesUnder('lib/src')) {
      final path = file.path.replaceAll(Platform.pathSeparator, '/');
      scanned += 1;
      if (path.endsWith('services/persistence/same_file.dart')) {
        continue;
      }
      // Code only: a comment may talk about separators all it likes.
      final code = file
          .readAsLinesSync()
          .map((line) {
            final comment = line.indexOf('//');
            return comment < 0 ? line : line.substring(0, comment);
          })
          .join('\n');
      if (judgesAFile.hasMatch(code)) {
        offenders.add(path);
      }
    }
    expect(scanned, greaterThan(500), reason: 'the source scan found lib/src');
    expect(
      offenders,
      isEmpty,
      reason: 'tell two paths apart through namesTheSameFile — the one answer',
    );
  });
}
