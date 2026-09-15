import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/se_audio_spans.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_se_window.dart';

/// F-113 (유저 2026-09-12): a sound that runs from cut 1 into cut 2 drew its
/// waveform, on cut 2's timeline, from the FILE's first frame — while the
/// storyboard (the track's own row) and playback placed it right. The cut's
/// clone restarts that block at local 0, and nothing said how far into its
/// sound local 0 already is.
void main() {
  // On the track's axis: one block at frames 10..40 carrying one sound.
  Layer trackRow() => Layer(
    id: const LayerId('se-1'),
    name: 'S1',
    kind: LayerKind.se,
    frames: const [],
    timeline: const {10: TimelineExposure.drawing(FrameId('f'), length: 30)},
    audioClips: const [
      AudioClip(filePath: 'voice.wav', frameId: FrameId('f')),
    ],
  );

  test('🚨the window says how far into the spilling block its first frame '
      'is', () {
    const cut2 = TrackSeWindow(cutStartFrame: 24, cutDurationFrames: 24);
    expect(cut2.spillInLeadFrames(trackRow()), 14);
  });

  test('nothing spills in, no lead: a block that starts inside the window, '
      'or one that ended before it', () {
    const cut1 = TrackSeWindow(cutStartFrame: 0, cutDurationFrames: 24);
    const later = TrackSeWindow(cutStartFrame: 40, cutDurationFrames: 24);
    expect(cut1.spillInLeadFrames(trackRow()), isNull);
    expect(later.spillInLeadFrames(trackRow()), isNull);
  });

  test('🚨the span the clone starts at frame 0 carries that lead, so its '
      'waveform is drawn from that far into the file', () {
    const cut2 = TrackSeWindow(cutStartFrame: 24, cutDurationFrames: 24);
    final spans = seAudioSpans(
      cut2.displayLayer(trackRow()),
      leadInAtStart: cut2.spillInLeadFrames(trackRow())!,
    );
    final span = spans.single;
    expect(span.startFrame, 0);
    expect(span.lengthFrames, 16, reason: 'the rest of the block, 24..40');
    expect(span.leadInFrames, 14);
    expect(span.leadingFrames, 14);
  });

  test('the offset trim and the lead add up, and only the block at frame 0 '
      'takes the lead', () {
    final layer = trackRow().copyWith(
      timeline: const {
        0: TimelineExposure.drawing(FrameId('f'), length: 4),
        8: TimelineExposure.drawing(FrameId('f'), length: 4),
      },
      audioClips: const [
        AudioClip(filePath: 'voice.wav', frameId: FrameId('f'), offsetFrames: 3),
      ],
    );
    final spans = seAudioSpans(layer, leadInAtStart: 5);
    expect(spans.map((span) => span.leadInFrames), [5, 0]);
    expect(spans.map((span) => span.leadingFrames), [8, 3]);
  });
}
