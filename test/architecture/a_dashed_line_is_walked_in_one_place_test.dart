import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/project_scratch_folder.dart';

/// 🚨ONE WALK FOR EVERY DASHED LINE (R9-rest, 2026-10-06).
///
/// The selection's ants, the timeline's repeat span and its drop silhouette
/// each walked a path into dashes by hand — three spellings of one
/// algorithm, none of which a search for the others' names would find — and
/// the text tool's resting boxes were about to be the fourth. They read
/// `dashesAlong` (`lib/src/ui/dashed_path.dart`) now.
///
/// ⛔A behaviour test cannot hold this: a fifth walk written by hand draws
/// perfectly good dashes. What gives one away is the tool it has to reach
/// for — a path is only cut into pieces with `extractPath` — so that is
/// what is scanned for.
void main() {
  const walk = 'lib/src/ui/dashed_path.dart';

  /// The files under [root] that cut a path into pieces themselves,
  /// comments apart.
  List<String> cuttersUnder(String root) => [
    for (final file in dartFilesUnder(root))
      if (file.readAsLinesSync().any(
        (line) =>
            !line.trimLeft().startsWith('//') && line.contains('extractPath('),
      ))
        file.path.replaceAll(r'\', '/'),
  ];

  test('nothing under lib/ cuts a path into dashes but the one walk', () {
    expect(
      cuttersUnder('lib'),
      [walk],
      reason:
          'a dashed line is `dashesAlong(path, on: …, off: …)` — or, for '
          'one that has to read on any artwork, `paintDashedOutline`',
    );
  });

  test('🚨the scan sees a walk written by hand when there is one', () {
    final planted = Directory.systemTemp.createTempSync('anicel-dashes');
    deleteAfterSessionEnds(planted);
    File('${planted.path}/by_hand.dart').writeAsStringSync(
      'void dashes(Path path) {\n'
      '  for (final metric in path.computeMetrics()) {\n'
      '    metric.extractPath(0, 5);\n'
      '  }\n'
      '}\n',
    );
    File('${planted.path}/said_only.dart').writeAsStringSync(
      '// extractPath( is what a walk by hand would call\n'
      'void nothing() {}\n',
    );

    expect(cuttersUnder(planted.path), [
      '${planted.path.replaceAll(r'\', '/')}/by_hand.dart',
    ]);
  });
}
