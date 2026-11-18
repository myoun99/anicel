import 'package:flutter_test/flutter_test.dart';

import '../../tool/source_brackets.dart';
import '../helpers/dart_sources.dart';

/// 🚨A WHOLE BUFFER IS ZEROED THROUGH `zeroBytes` (lib/src/core/
/// zero_bytes.dart), never `fillRange(0, length, 0)` — card
/// the-tile-cutter-is-most-of-a-raster-import, 2026-11-16: on bytes that
/// fill is a loop a byte at a time, and it was 180 of the 255 ms an 8K
/// picture took to cut into tiles. Three places zeroed a tile so.
///
/// ⛔A SOURCE SCAN, because a byte loop and a memory move leave the same
/// zeros: no behaviour test can tell them apart, only a clock.
void main() {
  test('no code fills a buffer with 0 from its start', () {
    final hits = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final path = file.path.replaceAll(r'\', '/');
      for (final line in _wholeZeroFills(file.readAsStringSync())) {
        hits.add('$path:$line');
      }
    }
    expect(
      hits,
      isEmpty,
      reason: 'zero it with `zeroBytes` — a copy of zeros, not a byte loop',
    );
  });

  test('the scan sees a planted fill, and not one in a comment or one that '
      'starts past 0 or fills with another byte', () {
    const planted = '''
view.fillRange(0, length, 0);
// ↩️It used to be view.fillRange(0, length, 0).
row.fillRange(start, end, 0);
mask.fillRange(0, length, 255);
bytes
    .fillRange(0, bytes.length, 0x00);
''';
    expect(_wholeZeroFills(planted), [1, 6]);
  });
}

/// The lines of [source] where a `fillRange` starts at 0 and fills with 0.
List<int> _wholeZeroFills(String source) {
  final code = withoutComments(source);
  return [
    for (final call in RegExp(r'\.fillRange\(').allMatches(code))
      if (callArguments(code, call.end - 1) case [
        final start,
        _,
        final value,
      ] when _isZero(start) && _isZero(value))
        '\n'.allMatches(code.substring(0, call.start)).length + 1,
  ];
}

bool _isZero(String argument) => int.tryParse(argument.trim()) == 0;
