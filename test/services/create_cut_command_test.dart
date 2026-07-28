import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/controllers/editing_session_state.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/create_cut_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  group('CreateCutCommand', () {
    test('creates a default cut, inserts it, and makes it active', () {
      final existingCut = _cut(id: 'cut-existing', name: 'Existing');
      final project = _project(
        tracks: [
          _track(id: 'track-1', name: 'Video', cuts: [existingCut]),
        ],
      );
      final repository = ProjectRepository(initialProject: project);
      final editingSession = EditingSessionState(
        activeCutId: const CutId('cut-existing'),
      );
      final historyManager = HistoryManager();

      historyManager.execute(
        CreateCutCommand(
          repository: repository,
          editingSession: editingSession,
          trackId: const TrackId('track-1'),
          cutId: const CutId('cut-new'),
          layerId: const LayerId('layer-new'),
          name: 'New Cut',
          canvasSize: const CanvasSize(width: 640, height: 360),
        ),
      );

      final cuts = repository.requireProject().tracks.single.cuts;
      expect(cuts, hasLength(2));
      expect(cuts.first, existingCut);
      expect(cuts.last, _defaultCut());
      expect(editingSession.activeCutId, const CutId('cut-new'));
    });

    test('inserts at the supplied index', () {
      final cutA = _cut(id: 'cut-a', name: 'Cut A');
      final cutB = _cut(id: 'cut-b', name: 'Cut B');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA, cutB]),
          ],
        ),
      );
      final editingSession = EditingSessionState(
        activeCutId: const CutId('cut-a'),
      );

      CreateCutCommand(
        repository: repository,
        editingSession: editingSession,
        trackId: const TrackId('track-1'),
        cutId: const CutId('cut-new'),
        layerId: const LayerId('layer-new'),
        name: 'New Cut',
        index: 1,
      ).execute();

      expect(repository.requireProject().tracks.single.cuts, [
        cutA,
        createDefaultCut(
          cutId: const CutId('cut-new'),
          name: 'New Cut',
          layerId: const LayerId('layer-new'),
        ),
        cutB,
      ]);
      expect(editingSession.activeCutId, const CutId('cut-new'));
    });

    test(
      'undo removes the created cut and restores the previous active cut',
      () {
        final existingCut = _cut(id: 'cut-existing', name: 'Existing');
        final repository = ProjectRepository(
          initialProject: _project(
            tracks: [
              _track(id: 'track-1', name: 'Video', cuts: [existingCut]),
            ],
          ),
        );
        final editingSession = EditingSessionState(
          activeCutId: const CutId('cut-existing'),
        );
        final historyManager = HistoryManager();

        historyManager.execute(
          CreateCutCommand(
            repository: repository,
            editingSession: editingSession,
            trackId: const TrackId('track-1'),
            cutId: const CutId('cut-new'),
            layerId: const LayerId('layer-new'),
            name: 'New Cut',
          ),
        );

        historyManager.undo();

        expect(repository.requireProject().tracks.single.cuts, [existingCut]);
        expect(editingSession.activeCutId, const CutId('cut-existing'));
      },
    );

    test('redo reinserts the same created cut and makes it active', () {
      final cutA = _cut(id: 'cut-a', name: 'Cut A');
      final cutB = _cut(id: 'cut-b', name: 'Cut B');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA, cutB]),
          ],
        ),
      );
      final editingSession = EditingSessionState(
        activeCutId: const CutId('cut-a'),
      );
      final historyManager = HistoryManager();
      final command = CreateCutCommand(
        repository: repository,
        editingSession: editingSession,
        trackId: const TrackId('track-1'),
        cutId: const CutId('cut-new'),
        layerId: const LayerId('layer-new'),
        name: 'New Cut',
        index: 1,
      );

      historyManager.execute(command);
      final createdCut = repository.requireProject().tracks.single.cuts[1];
      historyManager.undo();
      historyManager.redo();

      expect(repository.requireProject().tracks.single.cuts, [
        cutA,
        createdCut,
        cutB,
      ]);
      expect(editingSession.activeCutId, const CutId('cut-new'));
    });

    test('undo before execute throws', () {
      final repository = ProjectRepository(initialProject: _project());
      final editingSession = EditingSessionState(
        activeCutId: const CutId('cut-existing'),
      );
      final command = CreateCutCommand(
        repository: repository,
        editingSession: editingSession,
        trackId: const TrackId('track-1'),
        cutId: const CutId('cut-new'),
        layerId: const LayerId('layer-new'),
        name: 'New Cut',
      );

      expect(command.undo, throwsStateError);
    });

    test(
      'missing target propagates an error and leaves active cut unchanged',
      () {
        final repository = ProjectRepository(initialProject: _project());
        final editingSession = EditingSessionState(
          activeCutId: const CutId('cut-existing'),
        );
        final command = CreateCutCommand(
          repository: repository,
          editingSession: editingSession,
          trackId: const TrackId('missing'),
          cutId: const CutId('cut-new'),
          layerId: const LayerId('layer-new'),
          name: 'New Cut',
        );

        expect(command.execute, throwsStateError);
        expect(editingSession.activeCutId, const CutId('cut-existing'));
      },
    );
  });
}

Project _project({List<Track> tracks = const []}) {
  return Project(
    id: const ProjectId('project-1'),
    name: 'Project',
    tracks: tracks,
    createdAt: DateTime.utc(2026),
  );
}

Track _track({
  required String id,
  required String name,
  List<Cut> cuts = const [],
}) {
  return Track(id: TrackId(id), name: name, cuts: cuts);
}

Cut _cut({required String id, required String name}) {
  return Cut(
    id: CutId(id),
    name: name,
    layers: [_layer(id: '$id-layer', name: 'Layer')],
    duration: 24,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
  );
}

Layer _layer({required String id, required String name}) {
  return Layer(id: LayerId(id), name: name, frames: const []);
}

Cut _defaultCut() {
  return createDefaultCut(
    cutId: const CutId('cut-new'),
    name: 'New Cut',
    layerId: const LayerId('layer-new'),
    canvasSize: const CanvasSize(width: 640, height: 360),
  );
}
