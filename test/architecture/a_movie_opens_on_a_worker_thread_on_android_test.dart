import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨THE ENGINE NEVER OPENS A MOVIE THROUGH A DOOR THAT NEEDS A JAVA THREAD.
///
/// 🐞유저 2026-10-30 (Galaxy Tab, build 1084): a picked movie's preview stood
/// black and the import placed nothing. The Android decoder opened a whole
/// file with `AMediaExtractor_setDataSource(path)`, which builds an HTTP
/// service through JNI and fails on a thread the JVM does not know — and
/// every decode runs on a Dart worker's (logcat 「http service must be
/// created from Java thread」, measured in that build on an API 37
/// emulator). It opens by descriptor now, as the sound's decoder always did.
///
/// ⛔SO THIS SCANS THE SOURCE: no test anywhere runs the Android decoder —
/// CI and every desktop compile it out — and a whole file opened by path
/// again would pass them all.
///
/// ↩️It scanned the C engine (`packages/qa_native/src`), and went on reading
/// that folder after the decoders had moved to the Rust engine
/// (connection-round-checklist H, 2026-11-08) — where nothing opened a
/// movie any more — till the C went (2026-11-13): the same law, over the
/// Rust, as Media Foundation's
/// (media_foundation_starts_once_and_stays_up_test.dart).
void main() {
  final code = {
    for (final file in filesUnder('packages/gpu_engine/rust/native'))
      if (file.path.endsWith('.rs'))
        file.path.replaceAll(r'\', '/'):
            _withoutComments(file.readAsStringSync()),
  };

  test('the scan reads the Android decoders, the movie\'s and the sound\'s',
      () {
    expect(
      code.keys,
      containsAll([
        endsWith('native/video/src/decode/android.rs'),
        endsWith('native/audio/src/os/ndk.rs'),
      ]),
    );
  });

  test('no source opens an extractor by a path or a URI', () {
    expect(
      _filesCalling(_javaThreadDoors, code),
      isEmpty,
      reason: 'open with AMediaExtractor_setDataSourceFd (a file, a plain '
          'span) or _setDataSourceCustom (a framed span) — the path door '
          'fails on every thread a decode runs on',
    );
  });

  test('the scan sees a call, and not one named in a comment or a '
      'neighbour', () {
    final planted = {
      'planted.rs': _withoutComments('''
// AMediaExtractor_setDataSource(extractor, path) opened a whole file.
unsafe fn open_it(e: *mut AMediaExtractor, p: *const c_char, fd: i32) -> i32 {
    unsafe { AMediaExtractor_setDataSourceFd(e, fd, 0, 1) };
    unsafe { AMediaExtractor_setDataSource(e, p) }
}
'''),
      'fine.rs': _withoutComments('''
/* AMediaExtractor_setDataSource(e, p) */
/// AMediaExtractor_setDataSource(e, p) is the door that fails.
unsafe fn open_it(e: *mut AMediaExtractor, fd: i32) -> i32 {
    unsafe { AMediaExtractor_setDataSourceFd(e, fd, 0, 1) }
}
'''),
    };
    expect(_filesCalling(_javaThreadDoors, planted), ['planted.rs']);
  });
}

/// The NDK's doors that make an HTTP service through JNI: an extractor's
/// source by path or URI, and a data source by URI.
final _javaThreadDoors = RegExp(
  r'\b(AMediaExtractor_setDataSource|AMediaDataSource_newUri)\s*\(',
);

/// Each file of [code] that calls one of [doors].
List<String> _filesCalling(RegExp doors, Map<String, String> code) => [
  for (final MapEntry(key: file, value: text) in code.entries)
    if (doors.hasMatch(text)) file,
];

/// [source] with its comments gone — a call named in prose is not a call
/// (as Media Foundation's scan reads the Rust: two, so not yet one).
String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');
