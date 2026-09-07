import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_splice.dart';
import 'package:anicel/src/ui/session/independent_clip_mint.dart';

/// The kernel behind the independent paste and the independent block
/// duplicate: one mint per distinct source cel, the copy unnamed, the run
/// rebuilt on the new ids, and a cell whose source cannot be resolved
/// DROPPED rather than authored.
void main() {
  Frame cel(String id, {String? name}) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  TimelineClipRow clipOf(Map<int, String> cells, {required int length}) =>
      TimelineClipRow(
        exposures: {
          for (final entry in cells.entries)
            entry.key: TimelineExposure.drawing(
              FrameId(entry.value),
              length: 1,
            ),
        },
        length: length,
      );

  ({TimelineClipRow clip, List<Frame> born, Map<FrameId, FrameId> minted}) mint(
    TimelineClipRow clip,
    List<Frame> sources,
  ) {
    var next = 0;
    return mintIndependentClip(
      clip: clip,
      sources: sources,
      born: <Frame>[],
      mint: () => FrameId('new-${next++}'),
    );
  }

  test('every distinct source is minted ONCE, however often it is exposed', () {
    final result = mint(clipOf({0: 'a', 1: 'a', 2: 'b'}, length: 3), [
      cel('a', name: 'A'),
      cel('b', name: 'B'),
    ]);

    expect(result.minted.length, 2);
    expect(
      result.born.length,
      2,
      reason:
          'one cel per source, not per cell — two cels that look alike '
          'is not one cel exposed twice',
    );
    expect(
      result.clip.exposures[0]?.frameId,
      result.clip.exposures[1]?.frameId,
      reason: 'the repeat still points at the SAME new cel',
    );
    expect(
      result.clip.exposures[2]?.frameId,
      isNot(result.clip.exposures[0]?.frameId),
    );
  });

  test('🚨the copy comes out UNNAMED — a name is a cel\'s identity', () {
    final result = mint(clipOf({0: 'a'}, length: 1), [cel('a', name: 'A')]);
    expect(result.born.single.name, isNull);
    expect(result.born.single.id, isNot(const FrameId('a')));
    expect(result.clip.exposures[0]?.frameId, result.born.single.id);
  });

  test('⛔a cell whose source does not resolve is DROPPED, never authored', () {
    final result = mint(clipOf({0: 'a', 1: 'gone', 2: 'b'}, length: 3), [
      cel('a'),
      cel('b'),
    ]);

    expect(result.clip.exposures.containsKey(1), isFalse);
    expect(result.minted.containsKey(const FrameId('gone')), isFalse);
    expect(result.born.length, 2);
    expect(
      result.clip.length,
      3,
      reason: 'the run keeps its LENGTH — the cell goes empty, not missing',
    );
  });

  test('sources are searched IN ORDER, so the caller states its priority', () {
    final first = cel('a', name: 'first');
    final second = cel('a', name: 'second');
    final result = mint(clipOf({0: 'a'}, length: 1), [first, second]);
    expect(result.minted.keys.single, const FrameId('a'));
    expect(result.born.length, 1);
  });

  test('born is APPENDED to, so a caller can seed it and read it back', () {
    final born = <Frame>[cel('seed')];
    final result = mintIndependentClip(
      clip: clipOf({0: 'a'}, length: 1),
      sources: [cel('a')],
      born: born,
      mint: () => const FrameId('new'),
    );
    expect(result.born.first.id, const FrameId('seed'));
    expect(result.born.length, 2);
    expect(identical(result.born, born), isTrue);
  });
}
