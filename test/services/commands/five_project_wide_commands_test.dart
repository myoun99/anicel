import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/commands/update_camera_instruction_set_command.dart';
import 'package:anicel/src/services/commands/update_media_assets_command.dart';
import 'package:anicel/src/services/commands/update_project_audio_sample_rate_command.dart';
import 'package:anicel/src/services/commands/update_project_background_command.dart';
import 'package:anicel/src/services/commands/update_timesheet_info_command.dart';
import 'package:anicel/src/services/project_repository.dart';

/// 🚨FIVE PROJECT-WIDE COMMANDS, SAME THREE PROMISES.
///
/// Each writes one project-level field and each had nothing naming it (the
/// audit's untested-file pass, 2026-09-05). They share a shape, so they
/// share a table: execute writes, undo restores, undo before execute is
/// refused, and executing twice keeps the FIRST previous value — the `??=`
/// that makes undo walk all the way back instead of restoring what the
/// command itself put there.
void main() {
  Project blank() => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 9, 5),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'V',
        cuts: [
          Cut(
            id: const CutId('c'),
            name: 'c',
            layers: [
              Layer(
                id: const LayerId('l'),
                name: 'l',
                frames: const [],
                timeline: const {},
                kind: LayerKind.image,
              ),
            ],
            duration: 12,
            canvasSize: const CanvasSize(width: 100, height: 100),
          ),
        ],
      ),
    ],
  );

  /// One row of the table: how to build the command, and how to read back
  /// the field it owns.
  final table =
      <
        String,
        ({
          Command Function(ProjectRepository repository) build,
          Object? Function(Project project) read,
          Object? written,
        })
      >{
        'the project background': (
          build: (repository) => UpdateProjectBackgroundCommand(
            repository: repository,
            background: const ProjectBackground.color(0xFF102030),
          ),
          read: (project) => project.background.argb,
          written: 0xFF102030,
        ),
        'the audio sample rate': (
          build: (repository) => UpdateProjectAudioSampleRateCommand(
            repository: repository,
            audioSampleRate: 96000,
          ),
          read: (project) => project.audioSampleRate,
          written: 96000,
        ),
        'the timesheet info': (
          build: (repository) => UpdateTimesheetInfoCommand(
            repository: repository,
            info: const TimesheetInfo(title: 'Episode 3'),
          ),
          read: (project) => project.timesheetInfo.title,
          written: 'Episode 3',
        ),
        'the media pool': (
          build: (repository) => UpdateMediaAssetsCommand(
            repository: repository,
            mediaAssets: [MediaAsset(path: '/take.wav', name: 'take')],
          ),
          read: (project) => project.mediaAssets.length,
          written: 1,
        ),
        'the instruction set': (
          build: (repository) => UpdateCameraInstructionSetCommand(
            repository: repository,
            instructionSet: CameraInstructionSet(
              defs: const [
                CameraInstructionDef(id: 'pan', name: 'PAN', iconKey: 'pan'),
              ],
            ),
          ),
          read: (project) => project.cameraInstructions.defs.length,
          written: 1,
        ),
      };

  table.forEach((what, row) {
    group(what, () {
      test('execute writes it', () {
        final repository = ProjectRepository(initialProject: blank());
        row.build(repository).execute();

        expect(row.read(repository.requireProject()), row.written);
      });

      test('undo puts the old value back', () {
        final repository = ProjectRepository(initialProject: blank());
        final before = row.read(repository.requireProject());
        final command = row.build(repository)..execute();

        command.undo();

        expect(row.read(repository.requireProject()), before);
      });

      test('🚨executing TWICE keeps the FIRST previous value', () {
        final repository = ProjectRepository(initialProject: blank());
        final before = row.read(repository.requireProject());
        final command = row.build(repository)
          ..execute()
          ..execute();

        command.undo();

        expect(
          row.read(repository.requireProject()),
          before,
          reason:
              '`=` instead of `??=` would restore what the command '
              'itself wrote, and the history could not be walked past it',
        );
      });

      test('undo before execute is refused', () {
        final repository = ProjectRepository(initialProject: blank());
        expect(row.build(repository).undo, throwsStateError);
      });

      test('the description says something', () {
        final repository = ProjectRepository(initialProject: blank());
        expect(row.build(repository).description, isNotEmpty);
      });
    });
  });

  test('the media pool takes the CALLER\'s description — import, rename and '
      'remove are all pool edits and each says which', () {
    final repository = ProjectRepository(initialProject: blank());
    expect(
      UpdateMediaAssetsCommand(
        repository: repository,
        mediaAssets: const [],
        description: 'Remove media',
      ).description,
      'Remove media',
    );
  });
}
