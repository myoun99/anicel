import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/update_exposure_memo_command.dart';
import 'package:anicel/src/services/project_repository.dart';

/// 🚨HOW THE MEMO COMMAND FINDS ITS BLOCK, and what it refuses.
///
/// The command carried a private copy of the track/cut/layer walk with
/// `project_lookup`'s two StateError strings reproduced word for word.
/// This names the answers before that copy is deleted, so routing through
/// the shared walk has to keep them: the same refusals in the same words,
/// plus the GHOST refusal the shared lookup added and the copy never had
/// (a ghost is rederived by the run pass, so a memo written on it would
/// be gone on the next derive — both writers already ask this first, so
/// the command reaching a ghost is unreachable rather than allowed).
void main() {
  const cutId = CutId('cut-1');
  const layerId = LayerId('layer-1');

  ProjectRepository repositoryWith(Map<int, TimelineExposure> timeline) =>
      ProjectRepository(
        initialProject: Project(
          id: const ProjectId('project-1'),
          name: 'Project',
          createdAt: DateTime.utc(2024),
          tracks: [
            Track(
              id: const TrackId('track-1'),
              name: 'Video',
              cuts: [
                Cut(
                  id: cutId,
                  name: 'Cut A',
                  duration: 2,
                  canvasSize: const CanvasSize(width: 1280, height: 720),
                  layers: [
                    Layer(
                      id: layerId,
                      name: 'A',
                      frames: [
                        Frame(
                          id: const FrameId('frame-1'),
                          duration: 1,
                          strokes: const [],
                        ),
                      ],
                      timeline: timeline,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

  ProjectRepository plainRepository() => repositoryWith({
    0: const TimelineExposure.drawing(FrameId('frame-1'), length: 1),
  });

  UpdateExposureMemoCommand commandAt(
    ProjectRepository repository, {
    CutId cut = cutId,
    LayerId layer = layerId,
    int blockStartIndex = 0,
  }) => UpdateExposureMemoCommand(
    repository: repository,
    cutId: cut,
    layerId: layer,
    blockStartIndex: blockStartIndex,
    memo: const ExposureMemo(note: 'note'),
  );

  Matcher refusalSaying(String message) => throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );

  test('an unknown CUT is refused by name', () {
    expect(
      () => commandAt(plainRepository(), cut: const CutId('nope')).execute(),
      refusalSaying('Cut not found: ${const CutId('nope')}'),
    );
  });

  test('an unknown LAYER is refused by name, and the message says which '
      'cut it looked in', () {
    expect(
      () =>
          commandAt(plainRepository(), layer: const LayerId('nope')).execute(),
      refusalSaying('Layer not found in cut $cutId: ${const LayerId('nope')}'),
    );
  });

  test('an index with no exposure block starting on it is refused', () {
    expect(
      () => commandAt(plainRepository(), blockStartIndex: 9).execute(),
      refusalSaying('No exposure block starts at 9 on $layerId.'),
    );
  });

  test('a GHOST exposure is refused — it is rederived, so a memo written '
      'on it would be gone on the next derive', () {
    final repository = repositoryWith({
      0: const TimelineExposure.drawing(
        FrameId('frame-1'),
        length: 1,
        ghost: true,
      ),
    });
    expect(
      () => commandAt(repository).execute(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('ghost exposure is rederived'),
        ),
      ),
    );
  });

  test('a real block takes its memo, and undo puts the old one back', () {
    final repository = plainRepository();
    final command = commandAt(repository);
    ExposureMemo? memoNow() => repository
        .requireProject()
        .tracks
        .first
        .cuts
        .first
        .layers
        .first
        .timeline[0]
        ?.memo;

    expect(memoNow(), isNull);
    command.execute();
    expect(memoNow(), const ExposureMemo(note: 'note'));
    command.undo();
    expect(memoNow(), isNull);
  });

  test('undoing before executing is refused', () {
    expect(() => commandAt(plainRepository()).undo(), throwsStateError);
  });
}
