import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/cut_deletion_helpers.dart'
    show projectContentEndFrame;
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
import 'package:anicel/src/services/commands/delete_cut_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  // ⑱ (2026-08-12) changed what "the surviving cuts" means: a deletion
  // hands its frames to the next cut's leading gap, so the neighbour is no
  // longer the same VALUE it was. These oracles are about WHICH cuts
  // survive, so they ask for ids; the gap itself has its own group below.
  List<String> cutIdsOf(ProjectRepository repository) => [
    for (final cut in repository.requireProject().tracks.single.cuts)
      cut.id.value,
  ];

  group('DeleteCutCommand', () {
    test('execute deletes the target cut by CutId', () {
      final cutA = _cut(id: 'cut-a', name: 'Cut A');
      final cutB = _cut(id: 'cut-b', name: 'Cut B');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', cuts: [cutA, cutB]),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: cutA.id);

      DeleteCutCommand(
        repository: repository,
        editingSession: editingSession,
        cutId: cutB.id,
      ).execute();

      expect(repository.requireProject().tracks.single.cuts, [cutA]);
      expect(editingSession.activeCutId, cutA.id);
    });

    test('execute uses CutId, not cut name', () {
      final targetCut = _cut(id: 'target-cut', name: 'Shared Name');
      final sameNameCut = _cut(id: 'same-name-cut', name: 'Shared Name');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', cuts: [targetCut, sameNameCut]),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: sameNameCut.id);

      DeleteCutCommand(
        repository: repository,
        editingSession: editingSession,
        cutId: targetCut.id,
      ).execute();

      expect(cutIdsOf(repository), ['same-name-cut']);
      expect(editingSession.activeCutId, sameNameCut.id);
    });

    test('execute returns project state without the deleted cut', () {
      final cutA = _cut(id: 'cut-a', name: 'Cut A');
      final cutB = _cut(id: 'cut-b', name: 'Cut B');
      final cutC = _cut(id: 'cut-c', name: 'Cut C');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', cuts: [cutA, cutB, cutC]),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: cutA.id);

      DeleteCutCommand(
        repository: repository,
        editingSession: editingSession,
        cutId: cutB.id,
      ).execute();

      expect(cutIdsOf(repository), ['cut-a', 'cut-c']);
      expect(cutIdsOf(repository), isNot(contains('cut-b')));
    });

    test('deleting an active middle cut falls back to previous cut', () {
      final cutA = _cut(id: 'cut-a', name: 'Cut A');
      final cutB = _cut(id: 'cut-b', name: 'Cut B');
      final cutC = _cut(id: 'cut-c', name: 'Cut C');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', cuts: [cutA, cutB, cutC]),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: cutB.id);

      DeleteCutCommand(
        repository: repository,
        editingSession: editingSession,
        cutId: cutB.id,
      ).execute();

      expect(editingSession.activeCutId, cutA.id);
      expect(cutIdsOf(repository), ['cut-a', 'cut-c']);
    });

    test('deleting the first active cut falls back to next cut', () {
      final cutA = _cut(id: 'cut-a', name: 'Cut A');
      final cutB = _cut(id: 'cut-b', name: 'Cut B');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', cuts: [cutA, cutB]),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: cutA.id);

      DeleteCutCommand(
        repository: repository,
        editingSession: editingSession,
        cutId: cutA.id,
      ).execute();

      expect(editingSession.activeCutId, cutB.id);
      expect(cutIdsOf(repository), ['cut-b']);
    });

    test('deleting the last active cut falls back to previous cut', () {
      final cutA = _cut(id: 'cut-a', name: 'Cut A');
      final cutB = _cut(id: 'cut-b', name: 'Cut B');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', cuts: [cutA, cutB]),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: cutB.id);

      DeleteCutCommand(
        repository: repository,
        editingSession: editingSession,
        cutId: cutB.id,
      ).execute();

      expect(editingSession.activeCutId, cutA.id);
      expect(repository.requireProject().tracks.single.cuts, [cutA]);
    });

    test('deleting a non-active cut does not change activeCutId', () {
      final cutA = _cut(id: 'cut-a', name: 'Cut A');
      final cutB = _cut(id: 'cut-b', name: 'Cut B');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', cuts: [cutA, cutB]),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: cutA.id);

      DeleteCutCommand(
        repository: repository,
        editingSession: editingSession,
        cutId: cutB.id,
      ).execute();

      expect(editingSession.activeCutId, cutA.id);
    });

    test(
      'R28 #14: deleting the only cut EMPTIES the track and clears the '
      'active cut — no replacement is conjured',
      () {
        final onlyCut = _cut(id: 'only-cut', name: 'Only Cut');
        final repository = ProjectRepository(
          initialProject: _project(
            tracks: [
              _track(id: 'track-1', cuts: [onlyCut]),
            ],
          ),
        );
        final editingSession = EditingSessionState(activeCutId: onlyCut.id);

        DeleteCutCommand(
          repository: repository,
          editingSession: editingSession,
          cutId: onlyCut.id,
        ).execute();

        expect(repository.requireProject().tracks.single.cuts, isEmpty);
        expect(editingSession.activeCutId, isNull);
      },
    );

    test('undo restores the deleted cut at its original track and index', () {
      final cutA = _cut(id: 'cut-a', name: 'Cut A');
      final cutB = _cut(id: 'cut-b', name: 'Cut B');
      final cutC = _cut(id: 'cut-c', name: 'Cut C');
      final cutD = _cut(id: 'cut-d', name: 'Cut D');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', cuts: [cutA]),
            _track(id: 'track-2', cuts: [cutB, cutC, cutD]),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: cutA.id);
      final historyManager = HistoryManager();

      historyManager.execute(
        DeleteCutCommand(
          repository: repository,
          editingSession: editingSession,
          cutId: cutC.id,
        ),
      );
      historyManager.undo();

      expect(repository.requireProject().tracks.first.cuts, [cutA]);
      expect(repository.requireProject().tracks.last.cuts, [cutB, cutC, cutD]);
    });

    test('undo removes a created replacement cut and restores activeCutId', () {
      final onlyCut = _cut(id: 'only-cut', name: 'Only Cut');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', cuts: [onlyCut]),
          ],
        ),
      );
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

      expect(repository.requireProject().tracks.single.cuts, [onlyCut]);
      expect(editingSession.activeCutId, onlyCut.id);
    });

    test('undo restores previous activeCutId after existing-cut fallback', () {
      final cutA = _cut(id: 'cut-a', name: 'Cut A');
      final cutB = _cut(id: 'cut-b', name: 'Cut B');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', cuts: [cutA, cutB]),
          ],
        ),
      );
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
      expect(repository.requireProject().tracks.single.cuts, [cutA, cutB]);
    });

    test('redo deletes the cut again and reapplies active cut fallback', () {
      final cutA = _cut(id: 'cut-a', name: 'Cut A');
      final cutB = _cut(id: 'cut-b', name: 'Cut B');
      final cutC = _cut(id: 'cut-c', name: 'Cut C');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', cuts: [cutA, cutB, cutC]),
          ],
        ),
      );
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

      expect(cutIdsOf(repository), ['cut-a', 'cut-c']);
      expect(editingSession.activeCutId, cutA.id);
    });

    test('R28 #14: undo/redo round-trips the EMPTY track — the real cut '
        'comes back on undo and leaves again on redo', () {
      final onlyCut = _cut(id: 'only-cut', name: 'Only Cut');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', cuts: [onlyCut]),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: onlyCut.id);
      final historyManager = HistoryManager();

      historyManager.execute(
        DeleteCutCommand(
          repository: repository,
          editingSession: editingSession,
          cutId: onlyCut.id,
        ),
      );
      expect(repository.requireProject().tracks.single.cuts, isEmpty);

      historyManager.undo();
      expect(repository.requireProject().tracks.single.cuts, [onlyCut]);
      expect(editingSession.activeCutId, onlyCut.id);

      historyManager.redo();
      expect(repository.requireProject().tracks.single.cuts, isEmpty);
      expect(editingSession.activeCutId, isNull);
    });

    // ⑱ (user, 2026-08-12): 「컷 삭제는 그 자리에서 컷 하나를 지울 뿐이다.
    // 앞으로 재정렬하지 않고 스토리보드 엔드라인도 안 건드린다」.
    group('a deletion leaves a HOLE — nothing after it moves', () {
      List<int> startFramesOf(ProjectRepository repository) {
        final starts = <int>[];
        var next = 0;
        for (final cut in repository.requireProject().tracks.single.cuts) {
          starts.add(next + cut.leadingGapFrames);
          next = starts.last + cut.duration;
        }
        return starts;
      }

      test('the next cut keeps the frame it started on', () {
        final repository = ProjectRepository(
          initialProject: _project(
            tracks: [
              _track(
                id: 'track-1',
                cuts: [
                  _cut(id: 'cut-a', name: 'A', duration: 4),
                  _cut(id: 'cut-b', name: 'B', duration: 6, leadingGap: 2),
                  _cut(id: 'cut-c', name: 'C', duration: 3),
                ],
              ),
            ],
          ),
        );
        expect(startFramesOf(repository), [0, 6, 12]);

        DeleteCutCommand(
          repository: repository,
          editingSession: EditingSessionState(activeCutId: const CutId('cut-a')),
          cutId: const CutId('cut-b'),
        ).execute();

        // B held frames 4..11 (its 2-frame gap included) and C still starts
        // at 12 — the whole point of the item.
        expect(cutIdsOf(repository), ['cut-a', 'cut-c']);
        expect(startFramesOf(repository), [0, 12]);
        expect(
          repository.requireProject().tracks.single.cuts.last.leadingGapFrames,
          8,
          reason: 'C absorbed B\'s gap AND B\'s duration',
        );
      });

      test('deleting the LAST cut holds the movie end line still', () {
        final repository = ProjectRepository(
          initialProject: _project(
            tracks: [
              _track(
                id: 'track-1',
                cuts: [
                  _cut(id: 'cut-a', name: 'A', duration: 4),
                  _cut(id: 'cut-b', name: 'B', duration: 6, leadingGap: 2),
                ],
              ),
            ],
          ),
        );
        // Content ends at 12; the movie ends at 15.
        final before = repository.requireProject();
        expect(projectContentEndFrame(before), 12);

        DeleteCutCommand(
          repository: repository,
          editingSession: EditingSessionState(activeCutId: const CutId('cut-a')),
          cutId: const CutId('cut-b'),
        ).execute();

        final after = repository.requireProject();
        expect(projectContentEndFrame(after), 4);
        expect(
          after.trailingFrames,
          8,
          reason: 'the tail gap took what the track lost, so the end line — '
              'content end plus trailing — is still 12',
        );
        expect(projectContentEndFrame(after) + after.trailingFrames, 12);
      });

      test('undo puts the hole back where it came from', () {
        final repository = ProjectRepository(
          initialProject: _project(
            tracks: [
              _track(
                id: 'track-1',
                cuts: [
                  _cut(id: 'cut-a', name: 'A', duration: 4),
                  _cut(id: 'cut-b', name: 'B', duration: 6, leadingGap: 2),
                  _cut(id: 'cut-c', name: 'C', duration: 3, leadingGap: 1),
                ],
              ),
            ],
          ),
        );
        final before = repository.requireProject();
        final historyManager = HistoryManager();

        historyManager.execute(
          DeleteCutCommand(
            repository: repository,
            editingSession: EditingSessionState(
              activeCutId: const CutId('cut-a'),
            ),
            cutId: const CutId('cut-b'),
          ),
        );
        historyManager.undo();

        // Not "the cuts are back" — the GAPS are back, which is the part a
        // subtract-it-again undo would get wrong.
        expect(repository.requireProject(), before);
      });
    });

    test('missing target CutId causes execute to throw StateError', () {
      final cut = _cut(id: 'cut-a', name: 'Cut A');
      final repository = ProjectRepository(
        initialProject: _project(
          tracks: [
            _track(id: 'track-1', cuts: [cut]),
          ],
        ),
      );
      final editingSession = EditingSessionState(activeCutId: cut.id);

      expect(
        () => DeleteCutCommand(
          repository: repository,
          editingSession: editingSession,
          cutId: const CutId('missing-cut'),
        ).execute(),
        throwsStateError,
      );
    });

    test(
      'R28 #14: last-cut deletion no longer throws — an empty track is a '
      'representable state',
      () {
        final onlyCut = _cut(id: 'only-cut', name: 'Only Cut');
        final project = _project(
          tracks: [
            _track(id: 'track-1', cuts: [onlyCut]),
          ],
        );
        final repository = ProjectRepository(initialProject: project);
        final editingSession = EditingSessionState(activeCutId: onlyCut.id);

        DeleteCutCommand(
          repository: repository,
          editingSession: editingSession,
          cutId: onlyCut.id,
        ).execute();

        expect(repository.requireProject().tracks.single.cuts, isEmpty);
        expect(editingSession.activeCutId, isNull);
      },
    );

    test(
      'failed missing-target execute does not change project or activeCutId',
      () {
        final cut = _cut(id: 'cut-a', name: 'Cut A');
        final project = _project(
          tracks: [
            _track(id: 'track-1', cuts: [cut]),
          ],
        );
        final repository = ProjectRepository(initialProject: project);
        final editingSession = EditingSessionState(activeCutId: cut.id);

        expect(
          () => DeleteCutCommand(
            repository: repository,
            editingSession: editingSession,
            cutId: const CutId('missing-cut'),
          ).execute(),
          throwsStateError,
        );
        expect(repository.requireProject(), project);
        expect(editingSession.activeCutId, cut.id);
      },
    );

    test('undo before execute throws', () {
      final cut = _cut(id: 'cut-a', name: 'Cut A');
      final command = DeleteCutCommand(
        repository: ProjectRepository(
          initialProject: _project(
            tracks: [
              _track(id: 'track-1', cuts: [cut]),
            ],
          ),
        ),
        editingSession: EditingSessionState(activeCutId: cut.id),
        cutId: cut.id,
      );

      expect(command.undo, throwsStateError);
    });
  });
}

Project _project({List<Track>? tracks}) {
  return Project(
    id: const ProjectId('project'),
    name: 'Project',
    tracks: tracks ?? const [],
    createdAt: DateTime.utc(2026),
  );
}

Track _track({required String id, required List<Cut> cuts}) {
  return Track(id: TrackId(id), name: id, cuts: cuts);
}

Cut _cut({
  required String id,
  required String name,
  int duration = 1,
  int leadingGap = 0,
}) {
  return Cut(
    id: CutId(id),
    name: name,
    layers: [
      Layer(
        id: LayerId('$id-layer'),
        name: 'Layer 1',
        frames: const [],
        timeline: const {},
      ),
    ],
    duration: duration,
    leadingGapFrames: leadingGap,
    canvasSize: const CanvasSize(width: 1280, height: 720),
  );
}
