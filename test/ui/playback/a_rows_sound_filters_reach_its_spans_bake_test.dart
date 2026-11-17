import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/audio/sound_filters.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';

/// 🚨AN S ROW'S SOUND FILTERS ARE WHAT ITS SPANS ARE BAKED THROUGH (board
/// audio-fx-grows-like-the-pros ③ · Q2 design 1): the row's Equalizer and
/// Compressor effects, in its chain's order and read at the span's frames,
/// ride each span's schedule entry to the bake playback and an export
/// both read.
///
/// 🗣️Q2 (유저 2026-11-17): 「시안 3 · 시안 1 + 성격 프리셋」 — design 1: an
/// effect added from the Fx pill's 音声 section stacks under the row, keyed
/// as a picture's effect is, and 「효과 순서가 소리 순서다(위 → 아래)」.
void main() {
  const rate = ProjectFrameRate.fps24;
  const canvas = CanvasSize(width: 64, height: 64);
  const row = LayerId('se');
  const clip = FrameId('f');

  /// The sound sits on track frames 2..7, trimmed three frames into its
  /// file.
  Layer seRow(List<LayerEffect> effects) => Layer(
    id: row,
    name: 'SE',
    frames: const [],
    timeline: {2: const TimelineExposure.drawing(clip, length: 6)},
    kind: LayerKind.se,
    audioClips: [
      AudioClip(filePath: '/take.wav', frameId: clip, offsetFrames: 3),
    ],
    effects: effects,
  );

  ScheduledFilters? filtersOf(List<LayerEffect> effects) =>
      buildAudioPlaybackSchedule(
        window: const PlaybackWindow(
          trackId: TrackId('t'),
          trackStart: 0,
          frames: 10,
        ),
        project: Project(
          id: const ProjectId('p'),
          name: 'P',
          frameRate: rate,
          cameraSize: canvas,
          createdAt: DateTime.utc(2026, 11, 17),
          tracks: [
            Track(
              id: const TrackId('t'),
              name: 'V',
              seLayers: [seRow(effects)],
              cuts: const [],
            ),
          ],
        ),
        rate: rate,
        durationSecondsFor: (_) => 100,
      ).single.filters;

  LayerEffect equalizer(
    String id, {
    Map<String, EffectParameter> parameters = const {},
    bool enabled = true,
  }) => LayerEffect(
    id: EffectId(id),
    kind: EffectKind.equalizer,
    enabled: enabled,
    parameters: parameters,
  );

  AudioEqualizer engineOf({
    double lowCut = 0,
    double highCut = 0,
    double lowDb = 0,
    double highDb = 0,
  }) => AudioEqualizer(
    lowCut: lowCut,
    highCut: highCut,
    lowShelf: equalizerLowShelfHz,
    lowDb: lowDb,
    highShelf: equalizerHighShelfHz,
    highDb: highDb,
  );

  test('a row with no equalizer switched on bakes nothing', () {
    expect(filtersOf(const []), isNull);
    expect(filtersOf([equalizer('off', enabled: false)]), isNull);
  });

  test('🎯an equalizer is the whole span\'s: its trim, its length, its '
      'values and the row\'s clip it is baked for', () {
    expect(
      filtersOf([
        equalizer(
          'eq',
          parameters: {
            'lowCut': EffectParameter(value: 80),
            'highCut': EffectParameter(value: 9000),
            'lowGain': EffectParameter(value: -3),
            'highGain': EffectParameter(value: 6),
          },
        ),
      ]),
      ScheduledFilters(
        spanOffsetFrames: 3,
        spanFrames: 6,
        stages: [
          [
            (
              frame: 0,
              filter: engineOf(
                lowCut: 80,
                highCut: 9000,
                lowDb: -3,
                highDb: 6,
              ),
            ),
          ],
        ],
        slot: (row: row, clip: clip),
      ),
    );
  });

  test('a High Cut at its top cuts nothing, at every rate', () {
    final stage = filtersOf([equalizer('eq')])!.stages.single;
    expect(stage, [(frame: 0, filter: engineOf())]);
    expect(
      EffectKind.equalizer.parameterSpec('highCut')!.maximum,
      equalizerHighCutTop,
    );
  });

  test('🎯a keyed value is read at each frame of the span, a setting where '
      'it changes', () {
    final stage = filtersOf([
      equalizer(
        'eq',
        parameters: {
          'lowGain': EffectParameter(
            // Track frames: 0 dB where the span begins, 12 dB two frames
            // in, held after.
            track: PropertyTrack<double>(
              keys: {
                2: const PropertyKey<double>(0),
                4: const PropertyKey<double>(12),
              },
            ),
          ),
        },
      ),
    ])!.stages.single;
    expect(stage, [
      (frame: 0, filter: engineOf()),
      (frame: 1, filter: engineOf(lowDb: 6)),
      (frame: 2, filter: engineOf(lowDb: 12)),
    ]);
  });

  test('🎯two equalizers are two stages in the chain\'s order; one '
      'switched off is none', () {
    final stages = filtersOf([
      equalizer('a', parameters: {'lowGain': EffectParameter(value: 3)}),
      equalizer('off', enabled: false),
      equalizer('b', parameters: {'highGain': EffectParameter(value: -6)}),
    ])!.stages;
    expect(stages, [
      [(frame: 0, filter: engineOf(lowDb: 3))],
      [(frame: 0, filter: engineOf(highDb: -6))],
    ]);
  });

  LayerEffect compressor(
    String id, {
    Map<String, EffectParameter> parameters = const {},
  }) => LayerEffect(
    id: EffectId(id),
    kind: EffectKind.compressor,
    parameters: parameters,
  );

  test('🎯a compressor is a stage of its own, in the chain\'s order with an '
      'equalizer, its knobs read as the engine takes them', () {
    final stages = filtersOf([
      compressor(
        'comp',
        parameters: {
          'threshold': EffectParameter(value: -24),
          'ratio': EffectParameter(value: 6),
          'attack': EffectParameter(value: 3),
          'release': EffectParameter(value: 250),
          'makeup': EffectParameter(value: 4),
        },
      ),
      equalizer('eq', parameters: {'lowGain': EffectParameter(value: 3)}),
    ])!.stages;
    expect(stages, [
      [
        (
          frame: 0,
          filter: const AudioCompressor(
            thresholdDb: -24,
            ratio: 6,
            attackMs: 3,
            releaseMs: 250,
            makeupDb: 4,
          ),
        ),
      ],
      [(frame: 0, filter: engineOf(lowDb: 3))],
    ]);
  });

  test('a compressor just added is a stage at a ratio of one', () {
    expect(filtersOf([compressor('comp')])!.stages, [
      [
        (
          frame: 0,
          filter: const AudioCompressor(
            thresholdDb: -20,
            ratio: 1,
            attackMs: 10,
            releaseMs: 100,
            makeupDb: 0,
          ),
        ),
      ],
    ]);
  });

  test('a picture\'s effect on the row is no stage', () {
    final blur = LayerEffect(
      id: const EffectId('blur'),
      kind: EffectKind.blur,
      parameters: {'blurriness': EffectParameter(value: 4)},
    );
    expect(filtersOf([blur]), isNull);
    expect(
      () => soundFilterOf(
        sampleLayerEffectAt(blur, frameIndex: 0, blocks: null, worn: null),
      ),
      throwsArgumentError,
    );
  });
}
