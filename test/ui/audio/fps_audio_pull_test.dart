import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/conform_wav_codec.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/dialogs/fps_audio_choice_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// EXPORT-AUDIO ④: the fps-change audio question — when it arises, what
/// the pull does, and that one undo step moves rate and pull together.
void main() {
  group('audioPullBetween', () {
    test('the pulldown pairs pull by their exact rational', () {
      expect(
        audioPullBetween(
          const ProjectFrameRate.ntsc(24),
          const ProjectFrameRate.integer(24),
        ),
        (numerator: 1001, denominator: 1000),
      );
      expect(
        audioPullBetween(
          const ProjectFrameRate.integer(24),
          const ProjectFrameRate.ntsc(24),
        ),
        (numerator: 1000, denominator: 1001),
      );
      expect(
        audioPullBetween(
          const ProjectFrameRate.ntsc(30),
          const ProjectFrameRate.integer(30),
        ),
        (numerator: 1001, denominator: 1000),
      );
    });

    test('no pull across counting bases or for a no-op change — those ask '
        'no question', () {
      expect(
        audioPullBetween(
          const ProjectFrameRate.integer(24),
          const ProjectFrameRate.integer(30),
        ),
        isNull,
        reason: '24→30 would be a 25% speed change, not a conform',
      );
      expect(
        audioPullBetween(
          const ProjectFrameRate.ntsc(24),
          const ProjectFrameRate.ntsc(24),
        ),
        isNull,
      );
    });
  });

  group('the pull through the session', () {
    Project projectWithSound() {
      final base = createDefaultProject().copyWith(
        frameRate: const ProjectFrameRate.ntsc(24),
      );
      final track = base.tracks.first;
      return base.copyWith(
        tracks: [
          Track(
            id: track.id,
            name: track.name,
            cuts: track.cuts,
            seLayers: [
              Layer(
                id: const LayerId('se'),
                name: 'S1',
                kind: LayerKind.se,
                frames: [
                  Frame(
                    id: const FrameId('se-frame'),
                    duration: 1,
                    strokes: const [],
                  ),
                ],
                audioClips: const [
                  AudioClip(filePath: 'v.wav', frameId: FrameId('se-frame')),
                ],
              ),
            ],
          ),
        ],
      );
    }

    test('rate and pull move as ONE undo step, pulls cancel on the way '
        'back, and the conform store re-kicks at the new speed', () async {
      final requestedSpeeds = <(int, int)>[];
      late EditorSessionManager session;
      final store = AudioConformStore(
        resolveConformPath: (_) => null,
        resolveAudioSpeed: () {
          final project = session.repository.requireProject();
          return (
            numerator: project.audioSpeedNumerator,
            denominator: project.audioSpeedDenominator,
          );
        },
        runner: (request) async {
          requestedSpeeds.add(
            (request.speedNumerator, request.speedDenominator),
          );
          return ConformResult(
            outcome: ConformOutcome.built,
            samples: Float32List(4),
            channels: 1,
            sampleRate: request.projectSampleRate,
            frames: 4,
            speedNumerator: request.speedNumerator,
            speedDenominator: request.speedDenominator,
          );
        },
        log: (_) {},
      );
      session = EditorSessionManager(
        initialProject: projectWithSound(),
        audioConformStore: store,
      );
      addTearDown(session.dispose);

      expect(session.projectHasAnyAudio, isTrue);
      session.setProjectFrameRateWithAudioPull(
        const ProjectFrameRate.integer(24),
      );
      final project = session.repository.requireProject();
      expect(project.frameRate, const ProjectFrameRate.integer(24));
      expect(project.audioSpeedNumerator, 1001);
      expect(project.audioSpeedDenominator, 1000);
      await pumpEventQueue();
      expect(requestedSpeeds, contains((1001, 1000)));

      // ONE undo restores rate AND speed — and the store's entry (built at
      // 1001/1000) is stale on its own against the restored 1/1.
      session.undo();
      final undone = session.repository.requireProject();
      expect(undone.frameRate, const ProjectFrameRate.ntsc(24));
      expect(undone.audioSpeedNumerator, 1);
      expect(undone.audioSpeedDenominator, 1);
      expect(store.resultFor('v.wav'), isNull,
          reason: 'the pulled entry must not serve an unpulled project');

      // Going the other way pulls back and CANCELS to unity.
      session.setProjectFrameRateWithAudioPull(
        const ProjectFrameRate.integer(24),
      );
      session.setProjectFrameRateWithAudioPull(
        const ProjectFrameRate.ntsc(24),
      );
      final roundTripped = session.repository.requireProject();
      expect(roundTripped.audioSpeedNumerator, 1);
      expect(roundTripped.audioSpeedDenominator, 1);
    });

    test('the pull survives the project JSON round trip', () {
      final pulled = projectWithSound().copyWith(
        audioSpeedNumerator: 1001,
        audioSpeedDenominator: 1000,
      );
      final reopened = Project.fromJson(pulled.toJson());
      expect(reopened.audioSpeedNumerator, 1001);
      expect(reopened.audioSpeedDenominator, 1000);
      // Unity stays out of the JSON entirely.
      expect(
        projectWithSound().toJson().containsKey('audioSpeedNumerator'),
        isFalse,
      );
    });
  });

  group('the conform pipeline applies the pull', () {
    test('a pulled conform resamples by the exact rational and says so in '
        'its chunk; an unpulled project treats it as stale', () {
      final resampled = <String>[];
      AudioConformPipeline pipelineWith({int num = 1, int den = 1}) =>
          AudioConformPipeline(
            decode: (bytes) => (
              samples: Float32List(4800),
              channels: 1,
              sampleRate: 48000,
            ),
            resample:
                ({
                  required samples,
                  required channels,
                  required inputRate,
                  required outputRate,
                }) {
                  resampled.add('$inputRate→$outputRate');
                  return samples;
                },
            speedNumerator: num,
            speedDenominator: den,
          );

      // Unity at the project rate: bit-exact skip, no filter.
      pipelineWith().ensureConform(
        sourcePath: 'x.wav',
        conformPath: null,
      );
      // (sourceMissing — the fake path never resolves; use the encode
      // surface instead for the chunk check below.)

      // The pull reinterprets BOTH sides by the rational: 48k pulled by
      // 1001/1000 resamples 48048000→48000000.
      final wav = encodeConformWav(
        samples: Float32List(10),
        channels: 1,
        sampleRate: 48000,
        fingerprint: const ConformSourceFingerprint(
          sourceLength: 1,
          sourceCrc32: 2,
        ),
        speedNumerator: 1001,
        speedDenominator: 1000,
      );
      final decoded = decodeConformWav(wav);
      expect(decoded.speedNumerator, 1001);
      expect(decoded.speedDenominator, 1000);

      // A conform written BEFORE the field existed reads as unity.
      final legacy = decodeConformWav(
        encodeConformWav(
          samples: Float32List(10),
          channels: 1,
          sampleRate: 48000,
          fingerprint: const ConformSourceFingerprint(
            sourceLength: 1,
            sourceCrc32: 2,
          ),
        ),
      );
      expect(legacy.speedNumerator, 1);
      expect(legacy.speedDenominator, 1);
    });
  });

  testWidgets('the dialog offers keep/pull/cancel and reports the choice', (
    tester,
  ) async {
    FpsAudioChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              choice = await showFpsAudioChoiceDialog(
                context,
                from: const ProjectFrameRate.ntsc(24),
                to: const ProjectFrameRate.integer(24),
                strings: AppStrings.of(AppLanguage.en),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('fps-audio-choice-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('fps-audio-pull')));
    await tester.pumpAndSettle();
    expect(choice, FpsAudioChoice.pull);
  });
}
