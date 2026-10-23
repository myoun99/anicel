import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/audio/sound_cannot_play.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 유저 2026-10-17 (playback-waits-for-its-sound-Q1 a): a sound a run plays
/// without is red on its SE row as a cel that cannot be read is — always,
/// not only while playing — by the one question both ask
/// ([LayerStack.celCannotBeReadForLayer]), answered from the conform store
/// ([AudioConformStore.cannotPlayAt]).
void main() {
  /// The default project's first SE row: `gone.wav` over frames 0–3, and
  /// `here.wav` over 6–9.
  Project withSounds() {
    final project = createDefaultProject();
    final track = project.tracks.single;
    final [first, ...rest] = track.seLayers;
    Frame frame(String id) =>
        Frame(id: FrameId(id), duration: 1, strokes: const []);
    return project.copyWith(
      tracks: [
        track.copyWith(
          seLayers: [
            first.copyWith(
              frames: [frame('gone'), frame('here')],
              timeline: {
                0: const TimelineExposure.drawing(FrameId('gone'), length: 4),
                6: const TimelineExposure.drawing(FrameId('here'), length: 4),
              },
              audioClips: [
                AudioClip(filePath: 'gone.wav', frameId: const FrameId('gone')),
                AudioClip(filePath: 'here.wav', frameId: const FrameId('here')),
              ],
            ),
            ...rest,
          ],
        ),
      ],
    );
  }

  test('🚨a sound that cannot be played is red on its row once that is '
      'known, and the row hears it — the sound beside it is not', () async {
    final session = EditorSessionManager(
      initialProject: withSounds(),
      audioConformStore: AudioConformStore(
        resolveConformPath: (_) => null,
        runner: (request) async => request.sourcePath.endsWith('gone.wav')
            ? const ConformResult(
                outcome: ConformOutcome.sourceMissing,
                error: 'fixture',
              )
            : ConformResult(
                outcome: ConformOutcome.built,
                samples: Float32List(4),
                channels: 1,
                sampleRate: request.projectSampleRate,
                frames: 4,
              ),
        log: (_) {},
      ),
    );
    addTearDown(session.dispose);
    final stack = session.layerStack;
    Layer row() => session.activeTrack.seLayers.first;

    expect(
      stack.celCannotBeReadForLayer(row(), 0),
      isFalse,
      reason: 'on its way, it is waited for — not refused',
    );
    final before = stack.celTintRevision.value;
    for (var turn = 0; turn < 4; turn += 1) {
      await pumpEventQueue();
      stack.celCannotBeReadForLayer(row(), 6);
    }
    expect(
      stack.celTintRevision.value,
      greaterThan(before),
      reason: 'the rows paint again when the answer lands',
    );
    expect(stack.soundCannotPlayAt(row(), 0), SoundCannotPlay.missing);
    expect(
      [
        for (var frame = 0; frame < 12; frame += 1)
          if (stack.celCannotBeReadForLayer(row(), frame)) frame,
      ],
      [0, 1, 2, 3],
      reason: 'red over the block that carries it, and nowhere else',
    );
  });
}
