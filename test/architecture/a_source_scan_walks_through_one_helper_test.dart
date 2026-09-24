import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨A SOURCE SCAN WALKS THROUGH ONE HELPER — `dartFilesUnder`
/// (`test/helpers/dart_sources.dart`).
///
/// Board `one-lib-walk-for-source-scans`: the audit found 31 files walking
/// `Directory(…).listSync(recursive: true)` by hand on 2026-09-15, 51 on
/// 09-17 and 55 on 09-23 — the same walk, the same `is File` and `.dart`
/// filter, pasted into each new ratchet while the helper sat unused. Two of
/// the copies skipped a folder that did not exist and measured nothing.
///
/// ⛔SO THIS SCANS SOURCE, like the ratchets it guards: a copy that agrees
/// with the helper today passes every behaviour test there is.
void main() {
  test('no test walks a folder by hand, outside the ledger', () {
    final hits = [
      for (final file in dartFilesUnder('test'))
        ..._handWalks(_testPath(file.path), file.readAsStringSync()),
    ]..removeWhere((hit) => _walksThatAreNotSourceScans.containsKey(hit.$1));
    expect(
      [for (final hit in hits) '${hit.$1}:${hit.$2}'],
      isEmpty,
      reason:
          'walk with `dartFilesUnder(dir)` — it filters to Dart files and '
          'FAILS on a missing folder, where a copy quietly counts nothing. '
          'A walk that is not a source scan goes in the ledger, with why',
    );
  });

  test('every ledger entry still walks, and says why', () {
    for (final entry in _walksThatAreNotSourceScans.entries) {
      expect(
        entry.value.length,
        greaterThan(20),
        reason: '${entry.key} needs a reason, not a slot',
      );
      final walks = _handWalks(
        entry.key,
        dartFilesUnder('test')
            .firstWhere((file) => _testPath(file.path) == entry.key)
            .readAsStringSync(),
      );
      expect(
        walks,
        isNotEmpty,
        reason: '${entry.key} no longer walks by hand — take it off the list',
      );
    }
  });

  test('the scan sees a planted walk, and not one in a comment', () {
    const planted = '''
for (final f in Directory('lib').$_walk) {}
// ↩️It used to be Directory('lib').$_walk.
final files = dartFilesUnder('lib');
''';
    expect(
      [for (final hit in _handWalks('planted.dart', planted)) hit.$2],
      [1],
    );
  });
}

/// Walks that are NOT source scans — they read what a run WROTE, not what
/// the code says — and a fixture the import-graph law reads as text.
const _walksThatAreNotSourceScans = <String, String>{
  'test/architecture/the_import_graph_is_one_law_test.dart':
      'a FIXTURE inside a string: the text another scan is shown, not a '
      'walk this test makes',
  'test/services/a_save_does_not_take_the_undo_with_it_test.dart':
      'walks the SAVE folder a run wrote — files of any kind, no Dart',
  'test/ui/export/export_dialog_queue_test.dart':
      'walks the EXPORT output folder a run wrote — images, not Dart',
  'test/ui/export/export_dialog_test.dart':
      'walks the EXPORT output folder a run wrote — images, not Dart',
};

/// The walk itself, spelled in two pieces so this file does not find
/// itself.
const _walk = 'listSync(' 'recursive: true)';

/// THE walk — the one file allowed to spell it.
const _theHelper = 'test/helpers/dart_sources.dart';

/// Every line of [source] (named [path]) that walks a folder by hand, as
/// `(path, line number)` — a `//` comment is cut off first.
List<(String, int)> _handWalks(String path, String source) => [
  if (path != _theHelper)
    for (final (index, line) in source.split('\n').indexed)
      if (_code(line).contains(_walk)) (path, index + 1),
];

String _code(String line) {
  final comment = line.indexOf('//');
  return comment < 0 ? line : line.substring(0, comment);
}

String _testPath(String path) {
  final forward = path.replaceAll(r'\', '/');
  return forward.substring(forward.indexOf('test/'));
}
