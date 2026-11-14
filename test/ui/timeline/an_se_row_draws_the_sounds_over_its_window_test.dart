import 'dart:typed_data';

import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';
import 'package:flutter_test/flutter_test.dart';

/// An SE row's sounds are windowed like every sibling builder's: a cut's
/// cells ask for the sounds over their frames, and the storyboard's S row,
/// which shows the track end to end, for all of them (I-89 ① ⓕ).
void main() {
  test('a window takes the sounds over it and none wholly outside it — and '
      'no window takes the whole row', () {
    const first = FrameId('first');
    const second = FrameId('second');
    final layer = Layer(
      id: const LayerId('se'),
      name: 'S',
      kind: LayerKind.se,
      frames: [
        Frame(id: first, duration: 12, strokes: const []),
        Frame(id: second, duration: 12, strokes: const []),
      ],
      timeline: {
        0: const TimelineExposure.drawing(first, length: 12),
        24: const TimelineExposure.drawing(second, length: 12),
      },
      audioClips: [
        AudioClip(filePath: 'first.wav', frameId: first),
        AudioClip(filePath: 'second.wav', frameId: second),
      ],
    );
    // Two seconds of sound: longer than either block, so each is heard
    // whole.
    final peaks = AudioPeaks(bucketsPerSecond: 80, peaks: Float32List(160));
    List<int> startsOver([({int startIndex, int endIndexExclusive})? window]) =>
        [
          for (final sound in seRowSounds(
            layer,
            window: window,
            frameRate: ProjectFrameRate.fps24,
            audioPeaksFor: (_) => peaks,
          ))
            sound.startFrame,
        ];

    expect(startsOver((startIndex: 12, endIndexExclusive: 24)), isEmpty);
    expect(startsOver((startIndex: 30, endIndexExclusive: 40)), [24]);
    expect(startsOver(), [0, 24]);
  });
}
