import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨MEDIA FOUNDATION IS STARTED IN ONE PLACE AND SHUT DOWN IN NONE.
///
/// 🗣️유저 2026-10-22, board the-trimmed-movie-test-can-hang-on-windows-ci-Q3:
/// 「MF 를 한 번 켜 두고 끄지 않는다」 — the engine starts Media Foundation
/// the first time it uses it, through one function
/// (`qa_win_media_foundation.c`), and nothing stops it when its objects
/// close. Until then every reader, writer and probe paired its own MFStartup
/// with an MFShutdown, and both dumps of the Windows CI hang stood on the
/// first read after MF had gone down to zero and come straight back up.
///
/// ⛔SO THIS SCANS THE C: an MFShutdown put back on one close passes every
/// test that opens a movie — the hang it would bring back never reproduced
/// (13,000 runs, 2026-10-16).
void main() {
  final code = {
    for (final file in filesUnder('packages/qa_native/src'))
      if (_cSource.hasMatch(file.path))
        _srcPath(file.path): _withoutComments(file.readAsStringSync()),
  };

  test('one function starts it', () {
    expect(
      _callsTo('MFStartup', code),
      ['qa_win_media_foundation.c'],
      reason: 'start Media Foundation with qa_win_media_foundation_up()',
    );
  });

  test('and nothing shuts it down', () {
    expect(
      _callsTo('MFShutdown', code),
      isEmpty,
      reason: 'MF stays up until the process ends — down to zero and '
          'straight back up is where the reads hung (Q3)',
    );
  });

  test('the scan sees a call, and not one named in a comment', () {
    final planted = {
      'planted.c': _withoutComments('''
// MFShutdown() on close kept each stream self-contained.
/* MFStartup(MF_VERSION, MFSTARTUP_LITE) */
static void close_it(void) { MFShutdown(); }
'''),
    };
    expect(_callsTo('MFShutdown', planted), ['planted.c']);
    expect(_callsTo('MFStartup', planted), isEmpty);
  });
}

final _cSource = RegExp(r'\.(c|cpp|h|m)$');

/// Each file of [code] once for every call to [function] in it.
List<String> _callsTo(String function, Map<String, String> code) => [
  for (final MapEntry(key: file, value: text) in code.entries)
    for (final _ in RegExp('\\b$function\\s*\\(').allMatches(text)) file,
];

/// [source] with its comments gone — a call named in prose is not a call.
String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// [path] from the engine's `src/` on, with forward slashes.
String _srcPath(String path) =>
    path.replaceAll(r'\', '/').split('packages/qa_native/src/').last;
