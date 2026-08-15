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

  /// 🚨★★ 유저 #19 (2026-08-15): 「컷 생성하면 뒤에 모든컷블록인지 모르겠는데
  /// 그만큼 공간 밈. 중요한건 미는건 **뒤에 공간없으면 밀어도되는데, 공간이
  /// 여유분이 있는데도 여유분 뒤의 컷을 밀어버림.**」
  ///
  /// Cut positions are one cumulative pass over `leadingGap + duration`, so a
  /// list splice moves every follower by the new cut's whole footprint —
  /// including when the room was already lying there as the follower's gap.
  ///
  /// ★This is deletion's rule read backwards, and that is why it is a rule
  /// rather than a patch: a removed cut hands its frames TO the next cut's
  /// leading gap so nothing after it moves, and creation takes them back out
  /// of the same gap. The tests are written on the START FRAME, because "뒤의
  /// 컷을 밀어버림" is a statement about where a cut sits, not about a field.
  group('CreateCutCommand takes its room from the gap before it pushes', () {
    int startFrameOf(ProjectRepository repository, String cutId) {
      var start = 0;
      for (final cut in repository.requireProject().tracks.single.cuts) {
        start += cut.leadingGapFrames;
        if (cut.id == CutId(cutId)) {
          return start;
        }
        start += cut.duration;
      }
      throw StateError('no cut $cutId');
    }

    ({ProjectRepository repository, HistoryManager history, int newDuration})
    createBefore(Cut follower) {
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(
              id: 'track-1',
              name: 'Video',
              cuts: [_cut(id: 'cut-a', name: 'Cut A'), follower],
            ),
          ],
        ),
      );
      final history = HistoryManager();
      history.execute(
        CreateCutCommand(
          repository: repository,
          editingSession: EditingSessionState(
            activeCutId: const CutId('cut-a'),
          ),
          trackId: const TrackId('track-1'),
          cutId: const CutId('cut-new'),
          layerId: const LayerId('layer-new'),
          name: 'New Cut',
          index: 1,
        ),
      );
      return (
        repository: repository,
        history: history,
        newDuration: createDefaultCut(
          cutId: const CutId('x'),
          name: 'x',
          layerId: const LayerId('y'),
        ).duration,
      );
    }

    test('a gap big enough to hold the cut absorbs all of it — the follower '
        'does not move at all', () {
      final roomy = _cut(id: 'cut-b', name: 'Cut B', leadingGap: 1000);
      final before = 1000; // cut-a is 24 long and starts at 0.
      final made = createBefore(roomy);

      expect(
        startFrameOf(made.repository, 'cut-b'),
        24 + before,
        reason: 'the follower sits exactly where it sat — the new cut moved '
            'into room that was already free',
      );
      expect(
        made.repository.requireProject().tracks.single.cuts.last
            .leadingGapFrames,
        before - made.newDuration,
        reason: 'and the gap is shorter by exactly what was taken',
      );
    });

    test('no gap means the old push, unchanged — this is not a rule against '
        'pushing', () {
      final tight = _cut(id: 'cut-b', name: 'Cut B');
      final made = createBefore(tight);

      expect(
        startFrameOf(made.repository, 'cut-b'),
        24 + made.newDuration,
        reason: 'there was no room, so the follower moves the full footprint',
      );
    });

    test('a gap smaller than the cut is spent first and only the remainder '
        'pushes', () {
      final made = createBefore(
        _cut(id: 'cut-b', name: 'Cut B', leadingGap: 5),
      );

      expect(
        startFrameOf(made.repository, 'cut-b'),
        24 + 5 + (made.newDuration - 5),
        reason: 'the follower moved by the footprint MINUS the room it had',
      );
      expect(
        made.repository.requireProject().tracks.single.cuts.last
            .leadingGapFrames,
        0,
        reason: 'the gap is spent, not negative',
      );
    });

    test('undo hands the room back — the gap it had, not the gap plus what '
        'was taken', () {
      final made = createBefore(
        _cut(id: 'cut-b', name: 'Cut B', leadingGap: 5),
      );
      made.history.undo();

      final cuts = made.repository.requireProject().tracks.single.cuts;
      expect(cuts.map((cut) => cut.id.value), ['cut-a', 'cut-b']);
      expect(
        cuts.last.leadingGapFrames,
        5,
        reason: 'exactly what it started with — the follower took less room '
            'than the cut needed, so adding the footprint back would invent '
            'frames that were never there',
      );
      expect(startFrameOf(made.repository, 'cut-b'), 24 + 5);
    });
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

Cut _cut({required String id, required String name, int leadingGap = 0}) {
  return Cut(
    id: CutId(id),
    name: name,
    layers: [_layer(id: '$id-layer', name: 'Layer')],
    duration: 24,
    leadingGapFrames: leadingGap,
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
