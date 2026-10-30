import 'package:flutter_test/flutter_test.dart';

import '../../tool/source_brackets.dart';
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
/// ⛔SO THIS SCANS THE C: no test anywhere runs the Android decoder — CI and
/// every desktop compile it out — and a whole file opened by path again
/// would pass them all.
void main() {
  final code = {
    for (final file in filesUnder('packages/qa_native/src'))
      if (_cSource.hasMatch(file.path))
        file.path: withoutComments(file.readAsStringSync()),
  };

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
      'planted.c': withoutComments('''
// AMediaExtractor_setDataSource(extractor, path) opened a whole file.
static int open_it(AMediaExtractor* e, const char* p, int fd) {
  AMediaExtractor_setDataSourceFd(e, fd, 0, 1);
  return AMediaExtractor_setDataSource(e, p);
}
'''),
      'fine.c': withoutComments('''
/* AMediaExtractor_setDataSource(e, p) */
static int open_it(AMediaExtractor* e, int fd) {
  return AMediaExtractor_setDataSourceFd(e, fd, 0, 1);
}
'''),
    };
    expect(_filesCalling(_javaThreadDoors, planted), ['planted.c']);
  });
}

final _cSource = RegExp(r'\.(c|cpp|h|m)$');

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
