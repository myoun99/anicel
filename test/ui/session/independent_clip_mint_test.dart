import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_splice.dart';
import 'package:anicel/src/ui/session/independent_clip_mint.dart';

/// The kernel behind the independent paste and the independent block
/// duplicate: one mint per distinct source cel, the copy unnamed where a name
/// is the row's identity, the sounds of each source instance carried onto its
/// copy, the run rebuilt on the new ids, and a cell whose source cannot be
/// resolved DROPPED rather than authored.
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

  ({
    TimelineClipRow clip,
    List<Frame> born,
    List<AudioClip> bornSounds,
    Map<FrameId, FrameId> minted,
  })
  mint(
    TimelineClipRow clip,
    List<Frame> sources, {
    List<AudioClip> sounds = const [],
    bool namesAreIdentity = true,
  }) {
    var next = 0;
    return mintIndependentClip(
      clip: clip,
      from: [(cels: sources, sounds: sounds)],
      namesAreIdentity: namesAreIdentity,
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

  test('🚨…and KEEPS its name where the name is not an identity — an SE '
      'entry\'s dialogue (F-115)', () {
    final result = mint(
      clipOf({0: 'a'}, length: 1),
      [cel('a', name: 'hello')],
      namesAreIdentity: false,
    );
    expect(result.born.single.name, 'hello');
    expect(result.born.single.id, isNot(const FrameId('a')));
  });

  test('🚨a source instance\'s SOUND comes along as a sound of its copy — and '
      'only the sounds of the sources that were minted (F-115)', () {
    final door = AudioClip(
      filePath: 'C:/sounds/door.wav',
      frameId: const FrameId('a'),
      offsetFrames: 3,
      gain: 0.5,
    );
    final other = AudioClip(
      filePath: 'C:/sounds/other.wav',
      frameId: const FrameId('not-in-the-clip'),
    );
    final result = mint(
      clipOf({0: 'a', 1: 'b'}, length: 2),
      [cel('a'), cel('b')],
      sounds: [door, other],
    );

    final newA = result.minted[const FrameId('a')];
    expect(
      result.bornSounds,
      [door.copyWith(frameId: newA)],
      reason: 'the door sound follows a onto its new id with its trim and '
          'gain; b has none, and a sound on a cel outside the clip stays',
    );
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

  // ↩️「born is APPENDED to, so a caller can seed it and read it back」 went
  // with the parameter (F-115): both callers handed in an empty list, and the
  // linked paste — the one path that re-adds cels — never reaches the kernel.
}
