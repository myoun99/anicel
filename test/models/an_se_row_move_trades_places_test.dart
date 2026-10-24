import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/key_range_move.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// F-384 on an SE row: a sound block moved onto a sibling SE row's block
/// trades places with it — the block it lands on goes back to the row it
/// left, and each take goes with its cel ([planSeRangeRowMove]).
void main() {
  Layer seRow(String id, String cel, String file) => Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.se,
    frames: [Frame(id: FrameId(cel), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId(cel), length: 1)},
    audioClips: [AudioClip(filePath: file, frameId: FrameId(cel))],
  );

  test('the sound it lands on goes back to its row, with its take', () {
    final plan = planSeRangeRowMove(
      source: seRow('s1', 'one', 'one.wav'),
      target: seRow('s2', 'two', 'two.wav'),
      rangeStartIndex: 0,
      rangeEndIndexExclusive: 1,
      frameDelta: 0,
    )!;

    expect(plan.sourceAfter.timeline[0]?.frameId, const FrameId('two'));
    expect(plan.sourceAfter.timeline.length, 1);
    expect(plan.sourceAfter.audioClips.map((clip) => clip.filePath), [
      'two.wav',
    ]);
    expect(plan.targetAfter.timeline[0]?.frameId, const FrameId('one'));
    expect(plan.targetAfter.timeline.length, 1);
    expect(plan.targetAfter.audioClips.map((clip) => clip.filePath), [
      'one.wav',
    ]);
  });
}
