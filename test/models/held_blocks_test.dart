import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/held_blocks.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// F-619 — the blocks a band holds, found again: by how many of the row's
/// blocks stand before the first of them and after the last when the edit
/// acts on them, by the drawings they show when it is an edit beside them
/// (F-619-Q1), and the band moved by as far as they moved. The session's
/// verbs are pinned in
/// `test/ui/the_band_follows_the_blocks_it_holds_test.dart`; these pin what
/// no press there reaches: the two finders on the same row, a drawing
/// repeated along the row, the band's padding, its floor and its width.
void main() {
  /// A row of one-frame blocks, each `start: drawing`.
  Layer drawn(Map<int, String> blocks) => Layer(
    id: const LayerId('row'),
    name: 'row',
    kind: LayerKind.animation,
    frames: [
      for (final id in blocks.values.toSet())
        Frame(id: FrameId(id), duration: 1, strokes: const []),
    ],
    timeline: {
      for (final MapEntry(key: start, value: id) in blocks.entries)
        start: TimelineExposure.drawing(FrameId(id), length: 1),
    },
  );

  /// A row of blocks, each `start: length`, each its own drawing.
  Layer row(Map<int, int> blocks) => Layer(
    id: const LayerId('row'),
    name: 'row',
    kind: LayerKind.animation,
    frames: [
      for (final start in blocks.keys)
        Frame(id: FrameId('c$start'), duration: 1, strokes: const []),
    ],
    timeline: {
      for (final MapEntry(key: start, value: length) in blocks.entries)
        start: TimelineExposure.drawing(FrameId('c$start'), length: length),
    },
  );

  test('the held blocks are counted from both ends of the row, and the '
      'row\'s drawings are kept in order', () {
    final held = heldRunOn(row({0: 1, 1: 1, 2: 1, 3: 1, 4: 1}), [1, 2, 3])!;
    expect((held.before, held.after), (1, 1));
    expect(held.drawings, [
      for (final start in [0, 1, 2, 3, 4]) FrameId('c$start'),
    ]);
    expect(heldRunOn(row({0: 1}), [5]), isNull, reason: 'no such block');
  });

  group('an edit acting on the held blocks', () {
    test('a "+" at the held run\'s end is found inside the held span, up to '
        'the block after it', () {
      final held = heldRunOn(drawn({0: 'a', 1: 'b', 4: 'c'}), [0, 1])!;

      expect(
        heldSpanOn(drawn({0: 'a', 1: 'b', 2: 'x', 3: 'y', 5: 'c'}), held),
        (start: 0, endExclusive: 4),
      );
    });

    test('🚨the blocks behind swept away: the span is what is left of them '
        'up to the row\'s end', () {
      // A lead edge of the last held block pulled back past it (I-179): it
      // and the block behind it are gone, b followed the edge. Counted, the
      // one behind still stood after b's place, and nothing was found.
      final held = heldRunOn(drawn({0: 'a', 1: 'b', 2: 'c', 3: 'd'}), [1, 2])!;

      expect(
        heldSpanOn(drawn({0: 'a', 1: 'b'}), held),
        (start: 1, endExclusive: 2),
      );
    });

    test('the blocks around them taken too: the span is the row\'s', () {
      final held = heldRunOn(drawn({0: 'a', 1: 'b', 2: 'c'}), [1])!;

      expect(
        heldSpanOn(drawn({0: 'x', 1: 'y'}), held),
        (start: 0, endExclusive: 2),
      );
    });

    test('a row with nothing left between the blocks around them holds '
        'none', () {
      final held = heldRunOn(drawn({0: 'a', 1: 'b', 2: 'c'}), [1])!;

      expect(heldSpanOn(drawn({0: 'a', 1: 'c'}), held), isNull);
      expect(heldSpanOn(drawn({0: 'a'}), held), isNull);
    });
  });

  group('an edit beside the held blocks', () {
    test('🚨two blocks made in front of them: the same row, two answers — '
        'the edit says which', () {
      // The band holds c and d. New blocks x and y land between a and c:
      // a "+" at the end of a's run, or a "+" at the head of the band's.
      final held = heldRunOn(drawn({0: 'a', 3: 'c', 4: 'd'}), [3, 4])!;
      final after = drawn({0: 'a', 1: 'x', 2: 'y', 3: 'c', 4: 'd'});

      expect(
        keptSpanOn(after, held),
        (start: 3, endExclusive: 5),
        reason: 'beside: the blocks it held, where they stand',
      );
      expect(
        heldSpanOn(after, held),
        (start: 1, endExclusive: 5),
        reason: 'acting on it: the blocks the edit added to its run too',
      );
    });

    test('blocks pushed on by new ones in front are found where they went',
        () {
      final held = heldRunOn(drawn({0: 'a', 1: 'b', 2: 'c'}), [1, 2])!;

      expect(
        keptSpanOn(drawn({0: 'a', 1: 'x', 2: 'y', 3: 'b', 4: 'c'}), held),
        (start: 3, endExclusive: 5),
      );
    });

    test('a block taken from in front leaves them found', () {
      final held = heldRunOn(drawn({0: 'a', 1: 'b', 2: 'c', 3: 'd'}), [2, 3])!;

      expect(
        keptSpanOn(drawn({0: 'a', 1: 'c', 2: 'd'}), held),
        (start: 1, endExclusive: 3),
      );
    });

    test('blocks made after them leave them where they were', () {
      final held = heldRunOn(drawn({0: 'a', 1: 'b', 5: 'c'}), [0, 1])!;

      expect(
        keptSpanOn(drawn({0: 'a', 1: 'b', 2: 'x', 3: 'y', 6: 'c'}), held),
        (start: 0, endExclusive: 2),
      );
    });

    test('a row changed in two places, in front of them and after them: '
        'they are found between', () {
      final held = heldRunOn(
        drawn({0: 'a', 1: 'b', 2: 'c', 3: 'd'}),
        [1, 2],
      )!;

      expect(
        keptSpanOn(
          drawn({0: 'x', 1: 'a', 2: 'b', 3: 'c', 4: 'y', 5: 'd'}),
          held,
        ),
        (start: 2, endExclusive: 4),
      );
    });

    test('a held block swept away leaves the span over the ones left', () {
      final held = heldRunOn(
        drawn({0: 'a', 1: 'b', 2: 'c', 3: 'd', 4: 'e'}),
        [1, 2, 3],
      )!;

      expect(
        keptSpanOn(drawn({0: 'a', 1: 'b', 2: 'c', 3: 'e'}), held),
        (start: 1, endExclusive: 3),
        reason: 'b and c are left of the three',
      );
      expect(keptSpanOn(drawn({0: 'a', 1: 'e'}), held), isNull);
    });

    test('a drawing shown again along the row: the blocks held, not the '
        'first that show the same drawings', () {
      // A cycle — 1 2 1 2 — and the band holds its second turn.
      final held = heldRunOn(
        drawn({0: 'one', 1: 'two', 2: 'one', 3: 'two'}),
        [2, 3],
      )!;

      expect(
        keptSpanOn(
          drawn({0: 'x', 1: 'one', 2: 'two', 3: 'one', 4: 'two'}),
          held,
        ),
        (start: 3, endExclusive: 5),
      );
      expect(
        keptSpanOn(
          drawn({0: 'one', 1: 'two', 2: 'one', 3: 'two', 4: 'x'}),
          held,
        ),
        (start: 2, endExclusive: 4),
      );
    });
  });

  test('a band keeps the empty frames it reached over past its blocks', () {
    expect(
      followedBand(
        (start: 0, endExclusive: 10),
        was: (start: 0, endExclusive: 8),
        now: (start: 0, endExclusive: 12),
      ),
      (start: 0, endExclusive: 14),
    );
  });

  test('a band never starts before frame 0 nor ends where it starts', () {
    expect(
      followedBand(
        (start: 0, endExclusive: 4),
        was: (start: 2, endExclusive: 4),
        now: (start: 0, endExclusive: 4),
      ),
      (start: 0, endExclusive: 4),
    );
    expect(
      followedBand(
        (start: 2, endExclusive: 3),
        was: (start: 2, endExclusive: 3),
        now: (start: 5, endExclusive: 5),
      ),
      (start: 5, endExclusive: 6),
    );
  });
}
