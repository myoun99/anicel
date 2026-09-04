import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_pcm_scale.dart';
import 'package:anicel/src/models/key_range_shift.dart';
import 'package:anicel/src/models/reordered_by_ids.dart';

/// Three laws the audit pulled out of copies, none of which a test named.
///
/// A law extracted from three writers is only as good as its own test: the
/// copies it replaced each had callers exercising them, and folding them
/// together removes those incidental covers all at once.
void main() {
  group('the PCM scale — 32768, not 32767', () {
    test('unity round-trips the int16 a file held', () {
      // A decoder hands back raw / 32768, so multiplying back returns the
      // SAME int16. That is what makes the chain lossless at unity gain.
      for (final raw in <int>[-32768, -32767, -1, 0, 1, 32766, 32767]) {
        expect(int16FromUnitSample(raw / 32768.0), raw);
      }
    });

    test('-32768 survives, which the 32767 convention cannot represent', () {
      expect(int16FromUnitSample(-1.0), -32768);
    });

    test('only +1.0 needs the clamp', () {
      expect(int16FromUnitSample(1.0), 32767);
    });

    test('past unity clips rather than wrapping — the bus is allowed past '
        'it, and only the fixed-point conversion has to decide', () {
      expect(int16FromUnitSample(1.5), 32767);
      expect(int16FromUnitSample(-1.5), -32768);
      expect(int16FromUnitSample(1e9), 32767);
    });

    test('rounding is half away from zero, like C llround', () {
      expect(int16FromUnitSample(0.5 / 32768.0), 1);
      expect(int16FromUnitSample(-0.5 / 32768.0), -1);
    });
  });

  group('reorderedByIds', () {
    test('resequences to exactly the order given', () {
      expect(
        reorderedByIds<String, String>(
          ['a', 'b', 'c'],
          ['c', 'a', 'b'],
          idOf: (item) => item,
          orderName: 'cuts',
        ),
        ['c', 'a', 'b'],
      );
    });

    test('a PARTIAL order throws — a silent drop is rows going missing', () {
      expect(
        () => reorderedByIds<String, String>(
          ['a', 'b', 'c'],
          ['a', 'b'],
          idOf: (item) => item,
          orderName: 'cuts',
        ),
        throwsStateError,
      );
    });

    test('a DUPLICATE in the order throws — one row twice is another lost', () {
      expect(
        () => reorderedByIds<String, String>(
          ['a', 'b'],
          ['a', 'a'],
          idOf: (item) => item,
          orderName: 'layers',
        ),
        throwsStateError,
      );
    });

    test('a FOREIGN id throws, and the message names the ordering', () {
      expect(
        () => reorderedByIds<String, String>(
          ['a', 'b'],
          ['a', 'z'],
          idOf: (item) => item,
          orderName: 'SE rows',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('SE rows'),
          ),
        ),
      );
    });
  });

  group('shiftKeysInRange — all or nothing', () {
    Map<int, String>? shift({
      required Map<int, String> entries,
      required int start,
      required int endExclusive,
      required int delta,
      int extent = 1,
    }) => shiftKeysInRange<String>(
      entries: entries,
      rangeStartIndex: start,
      rangeEndIndexExclusive: endExclusive,
      frameDelta: delta,
      extentOf: (_) => extent,
    );

    test('keys starting in the range move, others stay', () {
      final moved = shift(
        entries: {0: 'a', 5: 'b', 9: 'c'},
        start: 4,
        endExclusive: 7,
        delta: 2,
      );
      expect(moved, {0: 'a', 7: 'b', 9: 'c'});
    });

    test('nothing in range is null, not an unchanged map', () {
      expect(
        shift(entries: {0: 'a'}, start: 4, endExclusive: 7, delta: 2),
        isNull,
      );
    });

    test('a zero delta is null', () {
      expect(
        shift(entries: {5: 'a'}, start: 4, endExclusive: 7, delta: 0),
        isNull,
      );
    });

    test('a landing below zero refuses the WHOLE move', () {
      expect(
        shift(entries: {1: 'a', 5: 'b'}, start: 0, endExclusive: 7, delta: -2),
        isNull,
        reason: 'nothing merges silently — the block discipline',
      );
    });

    test('landing on an UNMOVED entry refuses the whole move', () {
      expect(
        shift(entries: {2: 'a', 4: 'b'}, start: 1, endExclusive: 3, delta: 2),
        isNull,
      );
    });

    test('an EXTENT that overlaps refuses, where a point key would fit', () {
      // Moving 0 to 2 leaves 2..4 covered, which collides with the entry
      // at 3 — a point key at 2 would have been fine.
      expect(
        shift(
          entries: {0: 'a', 3: 'b'},
          start: 0,
          endExclusive: 1,
          delta: 2,
          extent: 3,
        ),
        isNull,
      );
      expect(
        shift(entries: {0: 'a', 3: 'b'}, start: 0, endExclusive: 1, delta: 2),
        {2: 'a', 3: 'b'},
      );
    });
  });
}
