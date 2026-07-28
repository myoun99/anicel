import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/editing_session_state.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/stroke.dart';
import 'package:anicel/src/models/stroke_id.dart';
import 'package:anicel/src/models/stroke_point.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/update_cut_note_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  group('UpdateCutNoteCommand', () {
    test('execute updates note and preserves cut contents', () {
      final targetCut = _cut(id: 'cut-target', name: 'Target');
      final otherCut = _cut(id: 'cut-other', name: 'Other');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [targetCut, otherCut]),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: otherCut.id);

      UpdateCutNoteCommand(
        repository: repository,
        cutId: targetCut.id,
        note: 'General note',
      ).execute();

      final updatedCut = requireCut(repository.requireProject(), targetCut.id);
      expect(
        updatedCut,
        targetCut.copyWith(metadata: const CutMetadata(note: 'General note')),
      );
      expect(updatedCut.id, targetCut.id);
      expect(updatedCut.name, targetCut.name);
      expect(updatedCut.duration, targetCut.duration);
      expect(updatedCut.canvasSize, targetCut.canvasSize);
      expect(updatedCut.layers, targetCut.layers);
      expect(updatedCut.layers.single.frames, targetCut.layers.single.frames);
      expect(
        updatedCut.layers.single.frames.single.strokes,
        targetCut.layers.single.frames.single.strokes,
      );
      expect(requireCut(repository.requireProject(), otherCut.id), otherCut);
      expect(editingSession.activeCutId, otherCut.id);
    });

    test('undo restores previous note without changing active cut', () {
      final targetCut = _cut(id: 'cut-target', name: 'Target');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [targetCut]),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: targetCut.id);
      final historyManager = HistoryManager();

      historyManager.execute(
        UpdateCutNoteCommand(
          repository: repository,
          cutId: targetCut.id,
          note: 'General note',
        ),
      );
      historyManager.undo();

      expect(requireCut(repository.requireProject(), targetCut.id), targetCut);
      expect(editingSession.activeCutId, targetCut.id);
    });

    test('redo reapplies note without changing active cut', () {
      final targetCut = _cut(id: 'cut-target', name: 'Target');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [targetCut]),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: targetCut.id);
      final historyManager = HistoryManager();

      historyManager.execute(
        UpdateCutNoteCommand(
          repository: repository,
          cutId: targetCut.id,
          note: 'General note',
        ),
      );
      historyManager.undo();
      historyManager.redo();

      expect(
        requireCut(repository.requireProject(), targetCut.id).metadata.note,
        'General note',
      );
      expect(editingSession.activeCutId, targetCut.id);
    });

    test('replaces existing non-empty note and undo restores it', () {
      final targetCut = _cut(
        id: 'cut-target',
        name: 'Target',
        metadata: const CutMetadata(note: 'Old note'),
      );
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [targetCut]),
          ],
        ),
      );
      final historyManager = HistoryManager();

      historyManager.execute(
        UpdateCutNoteCommand(
          repository: repository,
          cutId: targetCut.id,
          note: 'New note',
        ),
      );

      expect(
        requireCut(repository.requireProject(), targetCut.id).metadata.note,
        'New note',
      );

      historyManager.undo();

      expect(
        requireCut(repository.requireProject(), targetCut.id).metadata.note,
        'Old note',
      );
    });

    test('throws when the target cut id is missing', () {
      final targetCut = _cut(id: 'cut-target', name: 'Target');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [targetCut]),
          ],
        ),
      );
      final command = UpdateCutNoteCommand(
        repository: repository,
        cutId: const CutId('missing'),
        note: 'General note',
      );
      final beforeJson = repository.requireProject().toJson();

      expect(command.execute, throwsStateError);
      expect(repository.requireProject().toJson(), beforeJson);
    });
  });
}

Project _project({required List<Track> tracks}) {
  return Project(
    id: const ProjectId('project-1'),
    name: 'Project',
    tracks: tracks,
    createdAt: DateTime.utc(2024),
  );
}

Track _track({
  required String id,
  required String name,
  List<Cut> cuts = const [],
}) {
  return Track(id: TrackId(id), name: name, cuts: cuts);
}

Cut _cut({
  required String id,
  required String name,
  CutMetadata metadata = const CutMetadata.empty(),
}) {
  return Cut(
    id: CutId(id),
    name: name,
    layers: [
      Layer(
        id: LayerId('layer-$id'),
        name: 'Line',
        frames: [
          Frame(
            id: FrameId('frame-$id'),
            duration: 3,
            strokes: [
              Stroke(
                id: StrokeId('stroke-$id'),
                points: const [StrokePoint(x: 1, y: 2)],
                brushSettings: BrushSettings(size: 6),
              ),
            ],
          ),
        ],
      ),
    ],
    duration: 48,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
    metadata: metadata,
  );
}

