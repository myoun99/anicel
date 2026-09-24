import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/se_take_placement.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show drawingBlocks;
import 'package:anicel/src/models/timeline_exposure.dart';

const _takeId = FrameId('take');
const _sound = 'C:/snd/line.wav';

Layer _seRow({
  required List<Frame> frames,
  required Map<int, TimelineExposure> timeline,
  List<AudioClip> audioClips = const [],
}) {
  return Layer(
    id: const LayerId('se-row'),
    name: 'S1',
    kind: LayerKind.se,
    frames: frames,
    timeline: timeline,
    audioClips: audioClips,
  );
}

Frame _frame(String id) =>
    Frame(id: FrameId(id), duration: 1, strokes: const []);

SeTakePlacement _plan(
  Layer layer, {
  required int start,
  required int length,
}) {
  var minted = 0;
  final plan = planSeTakePlacement(
    layer: layer,
    startFrame: start,
    lengthFrames: length,
    filePath: _sound,
    takeFrameId: _takeId,
    newFrameId: () => FrameId('minted-${minted++}'),
  );
  expect(plan, isNotNull);
  return plan!;
}

void main() {
  test('REC1-B: a take on empty runway adds block, instance and clip', () {
    final plan = _plan(
      _seRow(frames: const [], timeline: const {}),
      start: 4,
      length: 6,
    );
    final block = drawingBlocks(plan.layer.timeline).single;
    expect(block.startIndex, 4);
    expect(block.length, 6);
    expect(block.frameId, _takeId);
    expect(plan.layer.frames.single.id, _takeId);
    final clip = plan.layer.audioClips.single;
    expect(clip.filePath, _sound);
    expect(clip.frameId, _takeId);
    expect(clip.offsetFrames, 0);
  });

  test('REC1-B: the take tail-trims the block it starts inside', () {
    final plan = _plan(
      _seRow(
        frames: [_frame('f1')],
        timeline: const {
          0: TimelineExposure.drawing(FrameId('f1'), length: 6),
        },
        audioClips: [
          AudioClip(filePath: 'C:/snd/old.wav', frameId: const FrameId('f1')),
        ],
      ),
      start: 4,
      length: 4,
    );
    final blocks = drawingBlocks(plan.layer.timeline);
    expect(blocks, hasLength(2));
    expect(blocks[0].startIndex, 0);
    expect(blocks[0].length, 4);
    expect(blocks[0].frameId, const FrameId('f1'));
    expect(blocks[1].startIndex, 4);
    expect(blocks[1].length, 4);
    // The kept head plays its sound untouched from the file's start.
    final oldClip = plan.layer.audioClips
        .firstWhere((clip) => clip.frameId == const FrameId('f1'));
    expect(oldClip.offsetFrames, 0);
  });

  test('REC1-B: the take head-trims the following block and its sound '
      'resumes from inside the file', () {
    final plan = _plan(
      _seRow(
        frames: [_frame('f1')],
        timeline: const {
          4: TimelineExposure.drawing(FrameId('f1'), length: 6),
        },
        audioClips: [
          AudioClip(
            filePath: 'C:/snd/old.wav',
            frameId: const FrameId('f1'),
            offsetFrames: 2,
          ),
        ],
      ),
      start: 0,
      length: 6,
    );
    final blocks = drawingBlocks(plan.layer.timeline);
    expect(blocks, hasLength(2));
    expect(blocks[0].startIndex, 0);
    expect(blocks[0].frameId, _takeId);
    expect(blocks[1].startIndex, 6);
    expect(blocks[1].length, 4);
    expect(blocks[1].frameId, const FrameId('f1'));
    final oldClip = plan.layer.audioClips
        .firstWhere((clip) => clip.frameId == const FrameId('f1'));
    // 2 frames of the block were eaten: the sound skips 2 MORE frames.
    expect(oldClip.offsetFrames, 4);
  });

  test('REC1-B: a fully covered block is erased and its link pruned', () {
    final plan = _plan(
      _seRow(
        frames: [_frame('f1')],
        timeline: const {
          2: TimelineExposure.drawing(FrameId('f1'), length: 2),
        },
        audioClips: [
          AudioClip(filePath: 'C:/snd/old.wav', frameId: const FrameId('f1')),
        ],
      ),
      start: 0,
      length: 8,
    );
    final block = drawingBlocks(plan.layer.timeline).single;
    expect(block.frameId, _takeId);
    expect(plan.layer.frames.single.id, _takeId);
    expect(plan.layer.audioClips.single.frameId, _takeId);
  });

  test('REC1-B: a take inside a long block splits it - the remainder is a '
      'new instance whose sound skips the eaten span', () {
    final plan = _plan(
      _seRow(
        frames: [_frame('f1')],
        timeline: const {
          0: TimelineExposure.drawing(FrameId('f1'), length: 12),
        },
        audioClips: [
          AudioClip(filePath: 'C:/snd/old.wav', frameId: const FrameId('f1')),
        ],
      ),
      start: 4,
      length: 4,
    );
    final blocks = drawingBlocks(plan.layer.timeline);
    expect(blocks, hasLength(3));
    expect(blocks[0].startIndex, 0);
    expect(blocks[0].length, 4);
    expect(blocks[0].frameId, const FrameId('f1'));
    expect(blocks[1].frameId, _takeId);
    expect(blocks[2].startIndex, 8);
    expect(blocks[2].length, 4);
    expect(blocks[2].frameId, const FrameId('minted-0'));
    final headClip = plan.layer.audioClips
        .firstWhere((clip) => clip.frameId == const FrameId('f1'));
    expect(headClip.offsetFrames, 0);
    final tailClip = plan.layer.audioClips
        .firstWhere((clip) => clip.frameId == const FrameId('minted-0'));
    expect(tailClip.filePath, 'C:/snd/old.wav');
    // Head 4 + take 4: the remainder resumes 8 frames into the file.
    expect(tailClip.offsetFrames, 8);
    // The remainder instance exists in the frame bank.
    expect(
      plan.layer.frames.map((frame) => frame.id),
      contains(const FrameId('minted-0')),
    );
  });

  test('REC1-B: head-trimming a SHARED instance clones it so siblings '
      'keep their own sound', () {
    final plan = _plan(
      _seRow(
        frames: [_frame('f1')],
        timeline: const {
          0: TimelineExposure.drawing(FrameId('f1'), length: 3),
          6: TimelineExposure.drawing(FrameId('f1'), length: 6),
        },
        audioClips: [
          AudioClip(filePath: 'C:/snd/foot.wav', frameId: const FrameId('f1')),
        ],
      ),
      start: 4,
      length: 4,
    );
    final blocks = drawingBlocks(plan.layer.timeline);
    expect(blocks, hasLength(3));
    // The untouched sibling keeps the original instance and offset.
    expect(blocks[0].frameId, const FrameId('f1'));
    final sharedClip = plan.layer.audioClips
        .firstWhere((clip) => clip.frameId == const FrameId('f1'));
    expect(sharedClip.offsetFrames, 0);
    // The trimmed survivor got its own instance with the bumped offset.
    expect(blocks[2].startIndex, 8);
    expect(blocks[2].length, 4);
    expect(blocks[2].frameId, const FrameId('minted-0'));
    final clonedClip = plan.layer.audioClips
        .firstWhere((clip) => clip.frameId == const FrameId('minted-0'));
    expect(clonedClip.offsetFrames, 2);
  });

  test('REC1-B: a zero-length take plans nothing', () {
    expect(
      planSeTakePlacement(
        layer: _seRow(frames: const [], timeline: const {}),
        startFrame: 0,
        lengthFrames: 0,
        filePath: _sound,
        takeFrameId: _takeId,
        newFrameId: () => const FrameId('never'),
      ),
      isNull,
    );
  });

  test('a PLACED sound writes its dialogue, its 「SE」 tag and where in the '
      'file it starts — a take leaves all three at their defaults', () {
    final plan = planSeTakePlacement(
      layer: _seRow(frames: const [], timeline: const {}),
      startFrame: 2,
      lengthFrames: 5,
      filePath: _sound,
      takeFrameId: _takeId,
      newFrameId: () => const FrameId('never'),
      name: 'door.wav',
      seName: placedSoundNameTag,
      offsetFrames: 3,
    )!;
    final frame = plan.layer.frames.single;
    expect((frame.name, frame.seName), ('door.wav', 'SE'));
    expect(plan.layer.audioClips.single.offsetFrames, 3);

    final take = _plan(
      _seRow(frames: const [], timeline: const {}),
      start: 2,
      length: 5,
    );
    final takeFrame = take.layer.frames.single;
    expect((takeFrame.name, takeFrame.seName), (null, null));
    expect(take.layer.audioClips.single.offsetFrames, 0);
  });

  group('the row a placed sound takes (「SE1부터 … 겹치지 않는 … 기존 '
      'SE행」)', () {
    Layer row(String id, Map<int, TimelineExposure> timeline) => Layer(
      id: LayerId(id),
      name: id,
      kind: LayerKind.se,
      frames: [
        for (final exposure in timeline.values)
          Frame(id: exposure.frameId!, duration: 1, strokes: const []),
      ],
      timeline: timeline,
    );

    test('the first row, in order, with no block anywhere in the span', () {
      final s1 = row('S1', {
        0: const TimelineExposure.drawing(FrameId('a'), length: 3),
      });
      final s2 = row('S2', const {});
      expect(
        firstSeRowFreeFor([s1, s2], startFrame: 0, lengthFrames: 2)?.id,
        s2.id,
        reason: 'S1 is taken where it would start',
      );
      expect(
        firstSeRowFreeFor([s1, s2], startFrame: 3, lengthFrames: 4)?.id,
        s1.id,
        reason: 'past its block S1 has room — 「뒤든 앞이든 겹치지 않는」',
      );
    });

    test('a block the span runs INTO takes the row too, and a row with no '
        'room anywhere answers nothing', () {
      final s1 = row('S1', {
        5: const TimelineExposure.drawing(FrameId('b'), length: 2),
      });
      expect(firstSeRowFreeFor([s1], startFrame: 2, lengthFrames: 4), isNull);
      expect(
        firstSeRowFreeFor([s1], startFrame: 2, lengthFrames: 3)?.id,
        s1.id,
      );
    });
  });
}
