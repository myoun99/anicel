import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/held_blocks.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// F-619 — the blocks a band holds, found again by how many of the row's
/// blocks stand before the first of them and after the last, and the band
/// moved by as far as they moved. The session's verbs are pinned in
/// `test/ui/the_band_follows_the_blocks_it_holds_test.dart`; these pin what
/// no press there reaches: the band's padding, its floor and its width.
void main() {
  /// A row of blocks, each `start: length`.
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

  test('the held blocks are counted from both ends of the row', () {
    expect(
      heldRunOn(row({0: 1, 1: 1, 2: 1, 3: 1, 4: 1}), [1, 2, 3]),
      (before: 1, after: 1),
    );
    expect(heldRunOn(row({0: 1}), [5]), isNull, reason: 'no such block');
  });

  test('a "+" at the held run\'s end is found inside the held span', () {
    final held = heldRunOn(row({0: 1, 1: 1, 4: 1}), [0, 1])!;

    expect(heldSpanOn(row({0: 1, 1: 1, 2: 1, 3: 1, 5: 1}), held), (
      start: 0,
      endExclusive: 4,
    ));
  });

  test('a row left with fewer blocks than it held holds none', () {
    expect(heldSpanOn(row({0: 1}), (before: 0, after: 1)), isNull);
    expect(heldSpanOn(row({0: 1}), (before: 1, after: 0)), isNull);
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
