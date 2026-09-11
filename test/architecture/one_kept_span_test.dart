import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨ONE answer for what an IN/OUT pair keeps: `models/kept_span.dart`.
///
/// It was seven hand-written copies of one clamp, spelled three ways — the
/// import doors' frames, pages and sound, the export's run, its label, its
/// scrub bar and a cut's exported range — and the import preview was about
/// to write an eighth. Every copy has to read the END that is not there as
/// the last frame, so this reads the source for exactly that: an OUT or an
/// end resolved with `?? <length> - 1`, or tested with `== null ||`,
/// anywhere but the one answer.
void main() {
  test('🚨no file but the one answer resolves an absent OUT', () {
    final resolvesOut = RegExp(
      r'(?:\bout(?:Frame|Mark|Point)?|\b\w*[Ee]nd(?:Frame|Mark|Index)?|\$2)'
      r'\s*\?\?\s*[\w.$]+\s*-\s*1\b'
      r'|\bout(?:Frame|Mark|Point)?\s*==\s*null\s*\|\|',
    );
    final offenders = <String>[];
    final files = Directory('lib/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    var scanned = 0;
    for (final file in files) {
      final path = file.path.replaceAll(Platform.pathSeparator, '/');
      scanned += 1;
      if (path.endsWith('models/kept_span.dart')) {
        continue;
      }
      // Code only: a comment may talk about OUT all it likes.
      final code = file
          .readAsLinesSync()
          .map((line) {
            final comment = line.indexOf('//');
            return comment < 0 ? line : line.substring(0, comment);
          })
          .join('\n');
      if (resolvesOut.hasMatch(code)) {
        offenders.add(path);
      }
    }
    expect(scanned, greaterThan(500), reason: 'the source scan found lib/src');
    expect(
      offenders,
      isEmpty,
      reason: 'read an IN/OUT pair through KeptSpan — the one answer',
    );
  });
}
