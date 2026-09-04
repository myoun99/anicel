import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/track_se_migration.dart';

/// 🚨A MIGRATION RUNS ONCE, ON SOMEBODY'S FILE, AND CANNOT BE TRIED AGAIN.
///
/// Lifting the legacy per-cut SE rows onto the track's global axis is a
/// one-way door: what it drops is gone from that save. Two properties keep
/// it honest — the OFFSET (a cut's key k becomes global start + k) and the
/// CLAMP (a block hanging past the cut end is cut off, because legacy
/// playback, export and the storyboard all cut it off there, so the clamp
/// reproduces what the file actually played). Without the clamp, merged
/// slots would overlap and one cut's audio would sit on the next cut's.
void main() {
  Layer se(
    String id, {
    Map<int, TimelineExposure> timeline = const {},
    List<Frame> frames = const [],
    List<AudioClip> audioClips = const [],
    bool isVisible = true,
    bool muted = false,
    double opacity = 1.0,
  }) => Layer(
    id: LayerId(id),
    name: id,
    frames: frames,
    timeline: timeline,
    audioClips: audioClips,
    kind: LayerKind.se,
    isVisible: isVisible,
    muted: muted,
    opacity: opacity,
  );

  Cut cut(String id, {required int duration, List<Layer> layers = const []}) =>
      Cut(
        id: CutId(id),
        name: id,
        layers: layers,
        duration: duration,
        canvasSize: const CanvasSize(width: 100, height: 100),
      );

  const trackId = TrackId('t1');

  test('a cut with no SE rows comes back UNTOUCHED — the same instance', () {
    final plain = cut('c1', duration: 10);
    final lift = liftCutSeLayersToTrack(trackId, [plain]);
    expect(
      identical(lift.cuts.single, plain),
      isTrue,
      reason:
          'a migration that rebuilds what it did not change is a '
          'migration that can break what it did not change',
    );
  });

  test('the SE rows leave the cuts', () {
    final lift = liftCutSeLayersToTrack(trackId, [
      cut('c1', duration: 10, layers: [se('S1')]),
    ]);
    expect(
      lift.cuts.single.layers.any((layer) => layer.kind == LayerKind.se),
      isFalse,
    );
  });

  test('keys OFFSET by the cut start, so the second cut lands after the '
      'first', () {
    final lift = liftCutSeLayersToTrack(trackId, [
      cut(
        'c1',
        duration: 10,
        layers: [
          se(
            'S1',
            timeline: {
              0: const TimelineExposure.drawing(FrameId('fa'), length: 1),
            },
          ),
        ],
      ),
      cut(
        'c2',
        duration: 10,
        layers: [
          se(
            'S1',
            timeline: {
              2: const TimelineExposure.drawing(FrameId('fb'), length: 1),
            },
          ),
        ],
      ),
    ]);

    final merged = lift.seLayers.first;
    expect(merged.timeline.keys.toSet().containsAll({0, 12}), isTrue);
  });

  test('a block hanging past the cut end is CLAMPED to the window', () {
    final lift = liftCutSeLayersToTrack(trackId, [
      cut(
        'c1',
        duration: 5,
        layers: [
          se(
            'S1',
            frames: [
              Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
            ],
            timeline: {
              3: const TimelineExposure.drawing(FrameId('f1'), length: 9),
            },
          ),
        ],
      ),
      cut('c2', duration: 5),
    ]);

    final entry = lift.seLayers.first.timeline[3]!;
    expect(
      entry.length,
      2,
      reason:
          'from key 3 the cut has two frames left — a longer block would '
          'sit on the next cut, which is not what the file played',
    );
  });

  test('an entry BEYOND the played window is dropped, not shifted', () {
    final lift = liftCutSeLayersToTrack(trackId, [
      cut(
        'c1',
        duration: 4,
        layers: [
          se(
            'S1',
            timeline: {
              0: const TimelineExposure.drawing(FrameId('fk'), length: 1),
              9: const TimelineExposure.drawing(FrameId('fn'), length: 1),
            },
          ),
        ],
      ),
    ]);

    expect(lift.seLayers.first.timeline.containsKey(0), isTrue);
    expect(lift.seLayers.first.timeline.containsKey(9), isFalse);
  });

  test('SLOTS merge by position: every cut\'s second SE row becomes S2', () {
    final lift = liftCutSeLayersToTrack(trackId, [
      cut('c1', duration: 5, layers: [se('a'), se('b')]),
      cut('c2', duration: 5, layers: [se('c')]),
    ]);

    expect(lift.seLayers.length, greaterThanOrEqualTo(2));
    expect(lift.seLayers[0].name, 'S1');
    expect(lift.seLayers[1].name, 'S2');
  });

  test('the FIRST cut that has the slot supplies its flags', () {
    final lift = liftCutSeLayersToTrack(trackId, [
      cut('c1', duration: 5, layers: [se('a', muted: true, opacity: 0.25)]),
      cut('c2', duration: 5, layers: [se('b')]),
    ]);

    final merged = lift.seLayers.first;
    expect(merged.muted, isTrue);
    expect(
      merged.opacity,
      0.25,
      reason:
          'per-cut divergence cannot map onto one global row, so the '
          'choice is deterministic rather than arbitrary',
    );
  });

  test('audio clips from every cut join the merged row', () {
    final lift = liftCutSeLayersToTrack(trackId, [
      cut(
        'c1',
        duration: 5,
        layers: [
          se(
            'a',
            audioClips: const [
              AudioClip(filePath: 'clip-1.wav', frameId: FrameId('fc1')),
            ],
          ),
        ],
      ),
      cut(
        'c2',
        duration: 5,
        layers: [
          se(
            'b',
            audioClips: const [
              AudioClip(filePath: 'clip-2.wav', frameId: FrameId('fc2')),
            ],
          ),
        ],
      ),
    ]);

    expect(
      lift.seLayers.first.audioClips.map((clip) => clip.filePath),
      containsAll(<String>['clip-1.wav', 'clip-2.wav']),
    );
  });
}
