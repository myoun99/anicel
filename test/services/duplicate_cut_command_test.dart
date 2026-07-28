import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/editing_session_state.dart';
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
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/duplicate_cut_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  group('DuplicateCutCommand', () {
    test('duplicates the source cut, appends it, and makes it active', () {
      final sourceCut = _sourceCut();
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [sourceCut]),
          ],
        ),
      );
      final editingSession = EditingSessionState(
        activeCutId: const CutId('cut-source'),
      );
      final historyManager = HistoryManager();

      historyManager.execute(
        DuplicateCutCommand(
          repository: repository,
          editingSession: editingSession,
          sourceCutId: const CutId('cut-source'),
          targetTrackId: const TrackId('track-1'),
          newCutId: const CutId('cut-duplicate'),
          newName: 'Duplicate Cut',
          layerIdMap: {
            const LayerId('layer-source'): const LayerId('layer-copy'),
          },
          frameIdMap: {
            const FrameId('frame-source'): const FrameId('frame-copy'),
          },
        ),
      );

      final cuts = repository.requireProject().tracks.single.cuts;
      expect(cuts, hasLength(2));
      expect(cuts.first, sourceCut);
      expect(cuts.last.id, const CutId('cut-duplicate'));
      expect(cuts.last.name, 'Duplicate Cut');
      expect(cuts.last.metadata, sourceCut.metadata);
      expect(cuts.last.layers.single.id, const LayerId('layer-copy'));
      expect(
        cuts.last.layers.single.frames.single.id,
        const FrameId('frame-copy'),
      );
      expect(
        cuts.last.layers.single.timeline[0],
        TimelineExposure.drawing(const FrameId('frame-copy'), length: 1),
      );
      expect(cuts.last.layers.single.timeline.containsKey(1), isFalse);
      expect(editingSession.activeCutId, const CutId('cut-duplicate'));
    });

    test('preserves metadata through execute', () {
      final sourceCut = _sourceCut().copyWith(
        metadata: const CutMetadata(note: 'FX-heavy cut.'),
      );
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [sourceCut]),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: sourceCut.id);

      DuplicateCutCommand(
        repository: repository,
        editingSession: editingSession,
        sourceCutId: sourceCut.id,
        targetTrackId: const TrackId('track-1'),
        newCutId: const CutId('cut-duplicate'),
        newName: 'Duplicate Cut',
        layerIdMap: {
          const LayerId('layer-source'): const LayerId('layer-copy'),
        },
        frameIdMap: {
          const FrameId('frame-source'): const FrameId('frame-copy'),
        },
      ).execute();

      final duplicatedCut = repository.requireProject().tracks.single.cuts.last;

      expect(duplicatedCut.id, const CutId('cut-duplicate'));
      expect(duplicatedCut.name, 'Duplicate Cut');
      expect(duplicatedCut.metadata, sourceCut.metadata);
    });

    test('inserts the duplicate at the supplied index', () {
      final cutA = _cut(id: 'cut-a', name: 'Cut A');
      final sourceCut = _sourceCut();
      final cutB = _cut(id: 'cut-b', name: 'Cut B');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [cutA, sourceCut, cutB]),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: cutA.id);

      DuplicateCutCommand(
        repository: repository,
        editingSession: editingSession,
        sourceCutId: sourceCut.id,
        targetTrackId: const TrackId('track-1'),
        newCutId: const CutId('cut-duplicate'),
        newName: 'Duplicate Cut',
        layerIdMap: {
          const LayerId('layer-source'): const LayerId('layer-copy'),
        },
        frameIdMap: {
          const FrameId('frame-source'): const FrameId('frame-copy'),
        },
        index: 1,
      ).execute();

      final cuts = repository.requireProject().tracks.single.cuts;
      expect(cuts.map((cut) => cut.id), [
        const CutId('cut-a'),
        const CutId('cut-duplicate'),
        const CutId('cut-source'),
        const CutId('cut-b'),
      ]);
      expect(editingSession.activeCutId, const CutId('cut-duplicate'));
    });

    test('can insert the duplicate into a caller-supplied target track', () {
      final sourceCut = _sourceCut();
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-source', name: 'Source', cuts: [sourceCut]),
            _track(id: 'track-target', name: 'Target'),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: sourceCut.id);

      DuplicateCutCommand(
        repository: repository,
        editingSession: editingSession,
        sourceCutId: sourceCut.id,
        targetTrackId: const TrackId('track-target'),
        newCutId: const CutId('cut-duplicate'),
        newName: 'Duplicate Cut',
        layerIdMap: {
          const LayerId('layer-source'): const LayerId('layer-copy'),
        },
        frameIdMap: {
          const FrameId('frame-source'): const FrameId('frame-copy'),
        },
      ).execute();

      final tracks = repository.requireProject().tracks;
      expect(tracks[0].cuts, [sourceCut]);
      expect(tracks[1].cuts.single.id, const CutId('cut-duplicate'));
      expect(editingSession.activeCutId, const CutId('cut-duplicate'));
    });

    test(
      'undo removes the duplicated cut and restores previous active cut',
      () {
        final sourceCut = _sourceCut();
        final repository = ProjectRepository(
          initialProject: _project(
            tracks: [
              _track(id: 'track-1', name: 'Video', cuts: [sourceCut]),
            ],
          ),
        );
        final editingSession = EditingSessionState(activeCutId: sourceCut.id);
        final historyManager = HistoryManager();

        historyManager.execute(
          DuplicateCutCommand(
            repository: repository,
            editingSession: editingSession,
            sourceCutId: sourceCut.id,
            targetTrackId: const TrackId('track-1'),
            newCutId: const CutId('cut-duplicate'),
            newName: 'Duplicate Cut',
            layerIdMap: {
              const LayerId('layer-source'): const LayerId('layer-copy'),
            },
            frameIdMap: {
              const FrameId('frame-source'): const FrameId('frame-copy'),
            },
          ),
        );

        historyManager.undo();

        expect(repository.requireProject().tracks.single.cuts, [sourceCut]);
        expect(editingSession.activeCutId, const CutId('cut-source'));
      },
    );

    test('redo reinserts the same duplicated cut and makes it active', () {
      final sourceCut = _sourceCut();
      final cutB = _cut(id: 'cut-b', name: 'Cut B');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [sourceCut, cutB]),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: sourceCut.id);
      final historyManager = HistoryManager();
      final command = DuplicateCutCommand(
        repository: repository,
        editingSession: editingSession,
        sourceCutId: sourceCut.id,
        targetTrackId: const TrackId('track-1'),
        newCutId: const CutId('cut-duplicate'),
        newName: 'Duplicate Cut',
        layerIdMap: {
          const LayerId('layer-source'): const LayerId('layer-copy'),
        },
        frameIdMap: {
          const FrameId('frame-source'): const FrameId('frame-copy'),
        },
        index: 1,
      );

      historyManager.execute(command);
      final duplicatedCut = repository.requireProject().tracks.single.cuts[1];
      historyManager.undo();
      historyManager.redo();

      expect(repository.requireProject().tracks.single.cuts, [
        sourceCut,
        duplicatedCut,
        cutB,
      ]);
      expect(editingSession.activeCutId, const CutId('cut-duplicate'));
    });

    test('throws when the source cut cannot be found', () {
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [_track(id: 'track-1', name: 'Video')],
        ),
      );
      final editingSession = EditingSessionState(
        activeCutId: const CutId('cut-source'),
      );
      final command = DuplicateCutCommand(
        repository: repository,
        editingSession: editingSession,
        sourceCutId: const CutId('cut-missing'),
        targetTrackId: const TrackId('track-1'),
        newCutId: const CutId('cut-duplicate'),
        newName: 'Duplicate Cut',
        layerIdMap: const {},
        frameIdMap: const {},
      );

      expect(command.execute, throwsStateError);
    });

    test('undo before execute throws', () {
      final sourceCut = _sourceCut();
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', name: 'Video', cuts: [sourceCut]),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: sourceCut.id);
      final command = DuplicateCutCommand(
        repository: repository,
        editingSession: editingSession,
        sourceCutId: sourceCut.id,
        targetTrackId: const TrackId('track-1'),
        newCutId: const CutId('cut-duplicate'),
        newName: 'Duplicate Cut',
        layerIdMap: {
          const LayerId('layer-source'): const LayerId('layer-copy'),
        },
        frameIdMap: {
          const FrameId('frame-source'): const FrameId('frame-copy'),
        },
      );

      expect(command.undo, throwsStateError);
    });
  });
}

Project _project({List<Track>? tracks}) {
  return Project(
    id: const ProjectId('project-1'),
    name: 'Project',
    tracks: tracks ?? const [],
    createdAt: DateTime.utc(2024),
  );
}

Track _track({required String id, required String name, List<Cut>? cuts}) {
  return Track(id: TrackId(id), name: name, cuts: cuts ?? const []);
}

Cut _sourceCut() {
  final frame = Frame(
    id: const FrameId('frame-source'),
    duration: 3,
    strokes: const [],
    name: 'A',
  );
  final layer = Layer(
    id: const LayerId('layer-source'),
    name: 'Line',
    frames: [frame],
    timeline: {0: TimelineExposure.drawing(frame.id, length: 1)},
    isVisible: false,
    opacity: 0.5,
  );

  return Cut(
    id: const CutId('cut-source'),
    name: 'Source Cut',
    layers: [layer],
    duration: 12,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
  );
}

Cut _cut({required String id, required String name}) {
  return Cut(
    id: CutId(id),
    name: name,
    layers: const [],
    duration: 1,
    canvasSize: const CanvasSize(width: 640, height: 360),
  );
}
