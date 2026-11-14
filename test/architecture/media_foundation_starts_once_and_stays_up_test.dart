import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨MEDIA FOUNDATION IS STARTED IN ONE PLACE AND SHUT DOWN IN NONE.
///
/// 🗣️유저 2026-10-22, board the-trimmed-movie-test-can-hang-on-windows-ci-Q3:
/// 「MF 를 한 번 켜 두고 끄지 않는다」 — the engine starts Media Foundation
/// the first time it uses it, through one function (native/media's
/// `media_foundation.rs`), and nothing stops it when its objects close.
/// Until then every reader, writer and probe paired its own MFStartup with
/// an MFShutdown, and both dumps of the Windows CI hang stood on the first
/// read after MF had gone down to zero and come straight back up.
///
/// ⛔SO THIS SCANS THE SOURCE: an MFShutdown put back on one close passes
/// every test that opens a movie — the hang it would bring back never
/// reproduced (13,000 runs, 2026-10-16).
///
/// ↩️It scanned the C engine (`packages/qa_native/src`, the one start in
/// `qa_win_media_foundation.c`) until the connection round moved the sound
/// decoder, the movie codecs and the span stream to the Rust engine and
/// deleted the C's (connection-round-checklist H, 2026-11-08; 관제 20:18:
/// the same law, over the Rust).
void main() {
  final code = {
    for (final root in [
      'packages/gpu_engine/rust/native',
      'packages/gpu_engine/rust/src',
    ])
      for (final file in filesUnder(root))
        if (file.path.endsWith('.rs'))
          _rustPath(file.path): _withoutComments(file.readAsStringSync()),
  };

  test('one function starts it', () {
    expect(
      _callsTo('MFStartup', code),
      ['native/media/src/media_foundation.rs'],
      reason: 'start Media Foundation with media::media_foundation::up()',
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
      'planted.rs': _withoutComments('''
// MFShutdown() on close kept each stream self-contained.
/* MFStartup(MF_VERSION, MFSTARTUP_LITE) */
/// MFStartup(MF_VERSION, MFSTARTUP_LITE) is the one start.
fn close_it() { unsafe { MFShutdown() }.ok(); }
'''),
    };
    expect(_callsTo('MFShutdown', planted), ['planted.rs']);
    expect(_callsTo('MFStartup', planted), isEmpty);
  });
}

/// Each file of [code] once for every call to [function] in it.
List<String> _callsTo(String function, Map<String, String> code) => [
  for (final MapEntry(key: file, value: text) in code.entries)
    for (final _ in RegExp('\\b$function\\s*\\(').allMatches(text)) file,
];

/// [source] with its comments gone — a call named in prose is not a call.
String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// [path] from the Rust workspace's root on, with forward slashes.
String _rustPath(String path) =>
    path.replaceAll(r'\', '/').split('packages/gpu_engine/rust/').last;
