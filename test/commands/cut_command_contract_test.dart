import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/editing_session_state.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/stroke.dart';
import 'package:anicel/src/models/stroke_id.dart';
import 'package:anicel/src/models/stroke_point.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/create_cut_command.dart';
import 'package:anicel/src/services/commands/delete_cut_command.dart';
import 'package:anicel/src/services/commands/duplicate_cut_command.dart';
import 'package:anicel/src/services/commands/rename_cut_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  group('Cut command contracts', () {
    group('activeCutId safety after execute', () {
      test('create cut makes the created cut active and valid', () {
        final cutA = _cut(id: 'cut-a', name: 'Cut A');
        final repository = _repositoryWithCuts([cutA]);
        final editingSession = EditingSessionState(activeCutId: cutA.id);

        CreateCutCommand(
          repository: repository,
          editingSession: editingSession,
          trackId: _trackId,
          cutId: const CutId('cut-created'),
          layerId: const LayerId('layer-created'),
          name: 'Created Cut',
        ).execute();

        expect(editingSession.activeCutId, const CutId('cut-created'));
        _expectActiveCutExists(repository, editingSession);
      });

      test('rename cut leaves the current active cut valid', () {
        final cutA = _cut(id: 'cut-a', name: 'Cut A');
        final cutB = _cut(id: 'cut-b', name: 'Cut B');
        final repository = _repositoryWithCuts([cutA, cutB]);
        final editingSession = EditingSessionState(activeCutId: cutB.id);

        RenameCutCommand(
          repository: repository,
          cutId: cutA.id,
          newName: 'Renamed Cut A',
        ).execute();

        expect(editingSession.activeCutId, cutB.id);
        _expectActiveCutExists(repository, editingSession);
      });

      test('duplicate cut makes the duplicate active and valid', () {
        final cutA = _cut(id: 'cut-a', name: 'Cut A');
        final repository = _repositoryWithCuts([cutA]);
        final editingSession = EditingSessionState(activeCutId: cutA.id);

        DuplicateCutCommand(
          repository: repository,
          editingSession: editingSession,
          sourceCutId: cutA.id,
          targetTrackId: _trackId,
          newCutId: const CutId('cut-copy'),
          newName: 'Cut A Copy',
          layerIdMap: <LayerId, LayerId>{},
          frameIdMap: <FrameId, FrameId>{},
        ).execute();

        expect(editingSession.activeCutId, const CutId('cut-copy'));
        _expectActiveCutExists(repository, editingSession);
      });

      test('delete inactive cut preserves the current active cut as valid', () {
        final cutA = _cut(id: 'cut-a', name: 'Cut A');
        final cutB = _cut(id: 'cut-b', name: 'Cut B');
        final repository = _repositoryWithCuts([cutA, cutB]);
        final editingSession = EditingSessionState(activeCutId: cutA.id);

        DeleteCutCommand(
          repository: repository,
          editingSession: editingSession,
          cutId: cutB.id,
        ).execute();

        expect(editingSession.activeCutId, cutA.id);
        _expectActiveCutExists(repository, editingSession);
      });

      test('delete active cut falls back to the previous cut first', () {
        final cutA = _cut(id: 'cut-a', name: 'Cut A');
        final cutB = _cut(id: 'cut-b', name: 'Cut B');
        final cutC = _cut(id: 'cut-c', name: 'Cut C');
        final repository = _repositoryWithCuts([cutA, cutB, cutC]);
        final editingSession = EditingSessionState(activeCutId: cutB.id);

        DeleteCutCommand(
          repository: repository,
          editingSession: editingSession,
          cutId: cutB.id,
        ).execute();

        expect(editingSession.activeCutId, cutA.id);
        _expectActiveCutExists(repository, editingSession);
      });

      test('delete active first cut falls back to the next cut', () {
        final cutA = _cut(id: 'cut-a', name: 'Cut A');
        final cutB = _cut(id: 'cut-b', name: 'Cut B');
        final repository = _repositoryWithCuts([cutA, cutB]);
        final editingSession = EditingSessionState(activeCutId: cutA.id);

        DeleteCutCommand(
          repository: repository,
          editingSession: editingSession,
          cutId: cutA.id,
        ).execute();

        expect(editingSession.activeCutId, cutB.id);
        _expectActiveCutExists(repository, editingSession);
      });

      test('R28 #14: deleting the last remaining cut leaves the track EMPTY '
          'and nothing active', () {
        final onlyCut = _cut(id: 'cut-only', name: 'Only Cut');
        final repository = _repositoryWithCuts([onlyCut]);
        final editingSession = EditingSessionState(activeCutId: onlyCut.id);

        DeleteCutCommand(
          repository: repository,
          editingSession: editingSession,
          cutId: onlyCut.id,
        ).execute();

        expect(_allCuts(repository), isEmpty);
        expect(
          editingSession.activeCutId,
          isNull,
          reason: 'no cut exists to be active — the same state a storyboard '
              'gap parks in',
        );
      });
    });

    group('activeCutId safety after undo', () {
      test('undo create cut restores a valid previous active cut', () {
        final cutA = _cut(id: 'cut-a', name: 'Cut A');
        final repository = _repositoryWithCuts([cutA]);
        final editingSession = EditingSessionState(activeCutId: cutA.id);
        final historyManager = HistoryManager();

        historyManager.execute(
          CreateCutCommand(
            repository: repository,
            editingSession: editingSession,
            trackId: _trackId,
            cutId: const CutId('cut-created'),
            layerId: const LayerId('layer-created'),
            name: 'Created Cut',
          ),
        );
        historyManager.undo();

        expect(editingSession.activeCutId, cutA.id);
        _expectActiveCutExists(repository, editingSession);
      });

      test('undo rename cut leaves the active cut valid', () {
        final cutA = _cut(id: 'cut-a', name: 'Cut A');
        final repository = _repositoryWithCuts([cutA]);
        final editingSession = EditingSessionState(activeCutId: cutA.id);
        final historyManager = HistoryManager();

        historyManager.execute(
          RenameCutCommand(
            repository: repository,
            cutId: cutA.id,
            newName: 'Renamed Cut A',
          ),
        );
        historyManager.undo();

        expect(editingSession.activeCutId, cutA.id);
        _expectActiveCutExists(repository, editingSession);
      });

      test('undo delete cut restores the deleted active cut as valid', () {
        final cutA = _cut(id: 'cut-a', name: 'Cut A');
        final cutB = _cut(id: 'cut-b', name: 'Cut B');
        final repository = _repositoryWithCuts([cutA, cutB]);
        final editingSession = EditingSessionState(activeCutId: cutB.id);
        final historyManager = HistoryManager();

        historyManager.execute(
          DeleteCutCommand(
            repository: repository,
            editingSession: editingSession,
            cutId: cutB.id,
          ),
        );
        historyManager.undo();

        expect(editingSession.activeCutId, cutB.id);
        _expectActiveCutExists(repository, editingSession);
      });

      test('undo duplicate cut restores a valid previous active cut', () {
        final cutA = _cut(id: 'cut-a', name: 'Cut A');
        final repository = _repositoryWithCuts([cutA]);
        final editingSession = EditingSessionState(activeCutId: cutA.id);
        final historyManager = HistoryManager();

        historyManager.execute(
          DuplicateCutCommand(
            repository: repository,
            editingSession: editingSession,
            sourceCutId: cutA.id,
            targetTrackId: _trackId,
            newCutId: const CutId('cut-copy'),
            newName: 'Cut A Copy',
            layerIdMap: <LayerId, LayerId>{},
            frameIdMap: <FrameId, FrameId>{},
          ),
        );
        historyManager.undo();

        expect(editingSession.activeCutId, cutA.id);
        _expectActiveCutExists(repository, editingSession);
      });

      test(
        'undo delete last cut restores the cut and the active cut (R28 #14: '
        'there is no replacement to remove first)',
        () {
          final onlyCut = _cut(id: 'cut-only', name: 'Only Cut');
          final repository = _repositoryWithCuts([onlyCut]);
          final editingSession = EditingSessionState(activeCutId: onlyCut.id);
          final historyManager = HistoryManager();

          historyManager.execute(
            DeleteCutCommand(
              repository: repository,
              editingSession: editingSession,
              cutId: onlyCut.id,
            ),
          );
          historyManager.undo();

          expect(_allCuts(repository), [onlyCut]);
          expect(editingSession.activeCutId, onlyCut.id);
          _expectActiveCutExists(repository, editingSession);
        },
      );
    });

    group('activeCutId safety after redo', () {
      test('redo create cut returns to a valid created active cut', () {
        final cutA = _cut(id: 'cut-a', name: 'Cut A');
        final repository = _repositoryWithCuts([cutA]);
        final editingSession = EditingSessionState(activeCutId: cutA.id);
        final historyManager = HistoryManager();

        historyManager.execute(
          CreateCutCommand(
            repository: repository,
            editingSession: editingSession,
            trackId: _trackId,
            cutId: const CutId('cut-created'),
            layerId: const LayerId('layer-created'),
            name: 'Created Cut',
          ),
        );
        historyManager.undo();
        historyManager.redo();

        expect(editingSession.activeCutId, const CutId('cut-created'));
        _expectActiveCutExists(repository, editingSession);
      });

      test('redo rename cut leaves the active cut valid', () {
        final cutA = _cut(id: 'cut-a', name: 'Cut A');
        final repository = _repositoryWithCuts([cutA]);
        final editingSession = EditingSessionState(activeCutId: cutA.id);
        final historyManager = HistoryManager();

        historyManager.execute(
          RenameCutCommand(
            repository: repository,
            cutId: cutA.id,
            newName: 'Renamed Cut A',
          ),
        );
        historyManager.undo();
        historyManager.redo();

        expect(editingSession.activeCutId, cutA.id);
        _expectActiveCutExists(repository, editingSession);
      });

      test('redo delete cut returns to a valid fallback active cut', () {
        final cutA = _cut(id: 'cut-a', name: 'Cut A');
        final cutB = _cut(id: 'cut-b', name: 'Cut B');
        final repository = _repositoryWithCuts([cutA, cutB]);
        final editingSession = EditingSessionState(activeCutId: cutB.id);
        final historyManager = HistoryManager();

        historyManager.execute(
          DeleteCutCommand(
            repository: repository,
            editingSession: editingSession,
            cutId: cutB.id,
          ),
        );
        historyManager.undo();
        historyManager.redo();

        expect(editingSession.activeCutId, cutA.id);
        _expectActiveCutExists(repository, editingSession);
      });

      test('redo duplicate cut returns to a valid duplicate active cut', () {
        final cutA = _cut(id: 'cut-a', name: 'Cut A');
        final repository = _repositoryWithCuts([cutA]);
        final editingSession = EditingSessionState(activeCutId: cutA.id);
        final historyManager = HistoryManager();

        historyManager.execute(
          DuplicateCutCommand(
            repository: repository,
            editingSession: editingSession,
            sourceCutId: cutA.id,
            targetTrackId: _trackId,
            newCutId: const CutId('cut-copy'),
            newName: 'Cut A Copy',
            layerIdMap: <LayerId, LayerId>{},
            frameIdMap: <FrameId, FrameId>{},
          ),
        );
        historyManager.undo();
        historyManager.redo();

        expect(editingSession.activeCutId, const CutId('cut-copy'));
        _expectActiveCutExists(repository, editingSession);
      });
    });

    group('DuplicateCutCommand independent-copy contract', () {
      test('execute remaps identity and preserves authored cut content', () {
        final sourceCut = _authoredSourceCut();
        final repository = _repositoryWithCuts([sourceCut]);
        final editingSession = EditingSessionState(activeCutId: sourceCut.id);

        DuplicateCutCommand(
          repository: repository,
          editingSession: editingSession,
          sourceCutId: sourceCut.id,
          targetTrackId: _trackId,
          newCutId: const CutId('cut-copy'),
          newName: 'Source Copy',
          layerIdMap: {
            const LayerId('layer-line'): const LayerId('layer-line-copy'),
            const LayerId('layer-paint'): const LayerId('layer-paint-copy'),
          },
          frameIdMap: {
            const FrameId('frame-line-a'): const FrameId('frame-line-a-copy'),
            const FrameId('frame-line-b'): const FrameId('frame-line-b-copy'),
            const FrameId('frame-paint-a'): const FrameId('frame-paint-a-copy'),
          },
        ).execute();

        final cuts = _allCuts(repository);
        final source = cuts[0];
        final duplicate = cuts[1];
        final duplicateLineLayer = duplicate.layers[0];
        final duplicatePaintLayer = duplicate.layers[1];

        expect(duplicate.id, const CutId('cut-copy'));
        expect(duplicate.id, isNot(source.id));
        expect(duplicate.name, 'Source Copy');
        expect(duplicate.layers.map((layer) => layer.id), [
          const LayerId('layer-line-copy'),
          const LayerId('layer-paint-copy'),
        ]);
        expect(duplicateLineLayer.frames.map((frame) => frame.id), [
          const FrameId('frame-line-a-copy'),
          const FrameId('frame-line-b-copy'),
        ]);
        expect(duplicatePaintLayer.frames.map((frame) => frame.id), [
          const FrameId('frame-paint-a-copy'),
        ]);
        expect(duplicateLineLayer.timeline.keys, [0, 5]);
        expect(
          duplicateLineLayer.timeline[0],
          TimelineExposure.drawing(
            const FrameId('frame-line-a-copy'),
            length: 2,
          ),
        );
        expect(
          duplicateLineLayer.timeline[5],
          TimelineExposure.drawing(
            const FrameId('frame-line-b-copy'),
            length: 6,
          ),
        );
        expect(duplicatePaintLayer.timeline.keys, [1]);
        expect(
          duplicatePaintLayer.timeline[1],
          TimelineExposure.drawing(
            const FrameId('frame-paint-a-copy'),
            length: 3,
          ),
        );
        expect(duplicateLineLayer.frames.map((frame) => frame.duration), [
          3,
          6,
        ]);
        expect(duplicatePaintLayer.frames.map((frame) => frame.duration), [4]);
        expect(duplicate.duration, source.duration);
        expect(duplicate.canvasSize, source.canvasSize);
        expect(duplicateLineLayer.isVisible, source.layers[0].isVisible);
        expect(duplicateLineLayer.opacity, source.layers[0].opacity);
        expect(duplicateLineLayer.frames[0].strokes.single, _sourceStroke());
        expect(
          identical(
            duplicateLineLayer.frames[0].strokes.single,
            source.layers[0].frames[0].strokes.single,
          ),
          isFalse,
        );
        expect(
          identical(
            duplicateLineLayer.frames[0].strokes.single.brushSettings,
            source.layers[0].frames[0].strokes.single.brushSettings,
          ),
          isFalse,
        );
        expect(
          identical(
            duplicateLineLayer.frames[0].strokes.single.points.single,
            source.layers[0].frames[0].strokes.single.points.single,
          ),
          isFalse,
        );
        expect(editingSession.activeCutId, duplicate.id);
        _expectActiveCutExists(repository, editingSession);
      });

      test(
        'editing source and duplicate content stays isolated by remapped ids',
        () {
          final sourceCut = _authoredSourceCut();
          final repository = _repositoryWithCuts([sourceCut]);
          final editingSession = EditingSessionState(activeCutId: sourceCut.id);

          DuplicateCutCommand(
            repository: repository,
            editingSession: editingSession,
            sourceCutId: sourceCut.id,
            targetTrackId: _trackId,
            newCutId: const CutId('cut-copy'),
            newName: 'Source Copy',
            layerIdMap: {
              const LayerId('layer-line'): const LayerId('layer-line-copy'),
              const LayerId('layer-paint'): const LayerId('layer-paint-copy'),
            },
            frameIdMap: {
              const FrameId('frame-line-a'): const FrameId('frame-line-a-copy'),
              const FrameId('frame-line-b'): const FrameId('frame-line-b-copy'),
              const FrameId('frame-paint-a'): const FrameId(
                'frame-paint-a-copy',
              ),
            },
          ).execute();

          final duplicateBeforeEdit = _allCuts(repository)[1];
          final duplicateLineLayer = duplicateBeforeEdit.layers[0];
          repository.replaceLayer(
            layer: duplicateLineLayer.copyWith(
              frames: [
                duplicateLineLayer.frames[0].copyWith(
                  strokes: [_editedStroke()],
                ),
                duplicateLineLayer.frames[1],
              ],
            ),
          );

          var cuts = _allCuts(repository);
          expect(cuts[0], sourceCut);
          expect(cuts[1].layers[0].frames[0].strokes.single, _editedStroke());

          final sourceLineLayer = cuts[0].layers[0];
          repository.replaceLayer(
            layer: sourceLineLayer.copyWith(
              frames: [
                sourceLineLayer.frames[0].copyWith(
                  duration: 9,
                  name: 'Edited A',
                ),
                sourceLineLayer.frames[1],
              ],
              timeline: {
                0: TimelineExposure.drawing(
                  const FrameId('frame-line-a'),
                  length: 8,
                ),
              },
            ),
          );

          cuts = _allCuts(repository);
          expect(cuts[0].layers[0].frames[0].duration, 9);
          expect(cuts[0].layers[0].frames[0].name, 'Edited A');
          expect(cuts[0].layers[0].timeline.keys, [0]);
          expect(cuts[1].layers[0].frames[0].duration, 3);
          expect(cuts[1].layers[0].frames[0].name, 'Line A');
          expect(cuts[1].layers[0].timeline.keys, [0, 5]);
          expect(cuts[1].layers[0].frames[0].strokes.single, _editedStroke());
        },
      );
    });

    group('Cut rename duplicate-name policy', () {
      test('renaming a cut to another cut display name is allowed', () {
        final cutA = _cut(id: 'cut-a', name: 'Cut A');
        final cutB = _cut(id: 'cut-b', name: 'Shared Name');
        final repository = _repositoryWithCuts([cutA, cutB]);

        RenameCutCommand(
          repository: repository,
          cutId: cutA.id,
          newName: 'Shared Name',
        ).execute();

        expect(_cutNames(repository), ['Shared Name', 'Shared Name']);
        expect(_cutIds(repository), [cutA.id, cutB.id]);
      });

      test('duplicate cut names do not merge cut identities or contents', () {
        final cutA = _cutWithLayer(
          id: 'cut-a',
          name: 'Shared Name',
          layerId: 'layer-a',
        );
        final cutB = _cutWithLayer(
          id: 'cut-b',
          name: 'Cut B',
          layerId: 'layer-b',
        );
        final repository = _repositoryWithCuts([cutA, cutB]);

        RenameCutCommand(
          repository: repository,
          cutId: cutB.id,
          newName: 'Shared Name',
        ).execute();

        final cuts = _allCuts(repository);
        expect(cuts, hasLength(2));
        expect(cuts.map((cut) => cut.name), ['Shared Name', 'Shared Name']);
        expect(cuts.map((cut) => cut.id), [cutA.id, cutB.id]);
        expect(cuts[0].layers.single.id, const LayerId('layer-a'));
        expect(cuts[1].layers.single.id, const LayerId('layer-b'));
      });
    });
  });
}

const _projectId = ProjectId('project-1');
const _trackId = TrackId('track-1');
const _canvasSize = CanvasSize(width: 1280, height: 720);

ProjectRepository _repositoryWithCuts(List<Cut> cuts) {
  return ProjectRepository(
    initialProject: Project(
      id: _projectId,
      name: 'Project',
      tracks: [Track(id: _trackId, name: 'Video', cuts: cuts)],
      createdAt: DateTime.utc(2024),
    ),
  );
}

Cut _cut({required String id, required String name}) {
  return Cut(
    id: CutId(id),
    name: name,
    layers: const [],
    duration: 24,
    canvasSize: _canvasSize,
  );
}

Cut _authoredSourceCut() {
  final lineFrameA = Frame(
    id: const FrameId('frame-line-a'),
    duration: 3,
    strokes: [_sourceStroke()],
    name: 'Line A',
  );
  final lineFrameB = Frame(
    id: const FrameId('frame-line-b'),
    duration: 6,
    strokes: const [],
    name: 'Line B',
  );
  final paintFrameA = Frame(
    id: const FrameId('frame-paint-a'),
    duration: 4,
    strokes: const [],
    name: 'Paint A',
  );

  return Cut(
    id: const CutId('cut-source'),
    name: 'Source Cut',
    layers: [
      Layer(
        id: const LayerId('layer-line'),
        name: 'Line',
        frames: [lineFrameA, lineFrameB],
        timeline: {
          0: TimelineExposure.drawing(lineFrameA.id, length: 2),
          5: TimelineExposure.drawing(lineFrameB.id, length: 6),
        },
        isVisible: false,
        opacity: 0.5,
      ),
      Layer(
        id: const LayerId('layer-paint'),
        name: 'Paint',
        frames: [paintFrameA],
        timeline: {1: TimelineExposure.drawing(paintFrameA.id, length: 3)},
      ),
    ],
    duration: 18,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
  );
}

Stroke _sourceStroke() {
  return Stroke(
    id: const StrokeId('stroke-line-a'),
    points: [const StrokePoint(x: 1, y: 2)],
    brushSettings: BrushSettings(color: 0xFF112233, size: 7, opacity: 0.6),
  );
}

Stroke _editedStroke() {
  return Stroke(
    id: const StrokeId('stroke-edited'),
    points: [const StrokePoint(x: 10, y: 20)],
    brushSettings: BrushSettings(color: 0xFF445566, size: 3, opacity: 0.8),
  );
}

Cut _cutWithLayer({
  required String id,
  required String name,
  required String layerId,
}) {
  return Cut(
    id: CutId(id),
    name: name,
    layers: [Layer(id: LayerId(layerId), name: 'Layer', frames: const [])],
    duration: 24,
    canvasSize: _canvasSize,
  );
}

List<Cut> _allCuts(ProjectRepository repository) {
  return repository
      .requireProject()
      .tracks
      .expand((track) => track.cuts)
      .toList();
}

Iterable<CutId> _cutIds(ProjectRepository repository) {
  return _allCuts(repository).map((cut) => cut.id);
}

Iterable<String> _cutNames(ProjectRepository repository) {
  return _allCuts(repository).map((cut) => cut.name);
}

void _expectActiveCutExists(
  ProjectRepository repository,
  EditingSessionState editingSession,
) {
  expect(_cutIds(repository), contains(editingSession.activeCutId));
}
