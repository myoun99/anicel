import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';

/// 🚨WHAT THE TIMELINE READER REFUSES.
///
/// A file that says something impossible must be REFUSED, not read into a
/// project that then behaves strangely: an index twice means one of the two
/// entries silently disappears, and the reader is the last place that can
/// still tell the user which file was wrong.
///
/// The reader was split into its raw-items pass and its length resolution
/// during the audit (2026-09-05); these are the refusals that pass caught,
/// and the duplicate one had no test before.
///
/// Every entry below is a whole drawing but for the one thing its test is
/// about — so each refusal is the one it names, not a neighbour's.
void main() {
  Layer readWith(Object? timeline) => Layer.fromJson({
    'id': {'value': 'l'},
    'name': 'L',
    'kind': 'image',
    'frames': <Object?>[],
    'isVisible': true,
    'opacity': 1.0,
    'timeline': timeline,
  });

  Map<String, dynamic> drawing(String frameId, {int length = 1}) => {
    'type': 'drawing',
    'frameId': {'value': frameId},
    'length': length,
  };

  test('🚨an index that appears TWICE is refused — one of the two would '
      'silently disappear', () {
    expect(
      () => readWith([
        {'index': 3, 'exposure': drawing('a')},
        {'index': 3, 'exposure': drawing('b')},
      ]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Duplicate'),
        ),
      ),
    );
  });

  test('⛔a NEGATIVE index is refused', () {
    expect(
      () => readWith([
        {'index': -1, 'exposure': drawing('a')},
      ]),
      throwsA(isA<FormatException>()),
    );
  });

  test('⛔an unknown exposure type is refused rather than guessed at — a '
      '`blank` too, which only formats refused by their number wrote', () {
    for (final type in ['somethingelse', 'blank']) {
      expect(
        () => readWith([
          {
            'index': 0,
            'exposure': {...drawing('a'), 'type': type},
          },
        ]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('type'),
          ),
        ),
        reason: type,
      );
    }
  });

  test('⛔a drawing with no frameId is refused — there is no cel to show', () {
    expect(
      () => readWith([
        {
          'index': 0,
          'exposure': {'type': 'drawing', 'length': 1},
        },
      ]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('frameId'),
        ),
      ),
    );
  });

  test('⛔a drawing with no length, or one that is not a whole number of '
      'frames, is refused — every build this format opens wrote one', () {
    for (final length in [null, 0, -2, 2.5, '3']) {
      expect(
        () => readWith([
          {
            'index': 0,
            'exposure': {...drawing('a'), 'length': length},
          },
        ]),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('length'),
          ),
        ),
        reason: '$length',
      );
    }
  });

  test('a length that runs into the next drawing is MENDED, not refused: '
      'the block ends where the next begins', () {
    // The one thing the reader mends — the invariant outranks the file
    // (the unified model, 2026-07-07).
    final layer = readWith([
      {'index': 0, 'exposure': drawing('a', length: 9)},
      {'index': 2, 'exposure': drawing('b')},
    ]);

    expect(layer.timeline[0]!.length, 2);
    expect(layer.timeline[2]!.length, 1);
  });

  test('⛔a timeline that is neither a list nor an object is refused', () {
    expect(() => readWith(7), throwsA(isA<FormatException>()));
  });

  test('⛔an object key that is not a number is refused, and NAMES the key', () {
    expect(
      () => readWith({'notanumber': drawing('a')}),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('notanumber'),
        ),
      ),
    );
  });

  test('🚨both spellings read the same — a list of index/exposure pairs and '
      'an object keyed by index', () {
    final fromList = readWith([
      {'index': 2, 'exposure': drawing('a', length: 3)},
    ]);
    final fromMap = readWith({'2': drawing('a', length: 3)});

    expect(fromList.timeline.keys, fromMap.timeline.keys);
    expect(fromList.timeline[2]!.length, fromMap.timeline[2]!.length);
  });
}
