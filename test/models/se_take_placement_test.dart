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
const _sound = r'C:\snd\line.wav';

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
        audioClips: const [
          AudioClip(filePath: r'C:\snd\old.wav', frameId: FrameId('f1')),
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
        audioClips: const [
          AudioClip(
            filePath: r'C:\snd\old.wav',
            frameId: FrameId('f1'),
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
        audioClips: const [
          AudioClip(filePath: r'C:\snd\old.wav', frameId: FrameId('f1')),
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
        audioClips: const [
          AudioClip(filePath: r'C:\snd\old.wav', frameId: FrameId('f1')),
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
    expect(tailClip.filePath, r'C:\snd\old.wav');
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
        audioClips: const [
          AudioClip(filePath: r'C:\snd\foot.wav', frameId: FrameId('f1')),
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
}
