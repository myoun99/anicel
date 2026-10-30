import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_camera_room.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_builder.dart';
import 'package:flutter_test/flutter_test.dart';

/// 컷 설정 — a cut names who does each stage's work but the conte's, the
/// work's (유저 2026-10-08, F-291-Q1: 「원화 작업자나 시아게는 컷마다 다름 …
/// 나머진 컷마다 스태프설정」). A 겸용 pair is one cut to the person naming
/// it, and a pick for several cuts passes on the stages it changed, leaving
/// every other stage as each cut has it. ↩️A stage the cut did not name took
/// the work's (09-25: 작품 설정에는 기본값, 컷 설정에는 컷별 이름).
void main() {
  const track = TrackId('track');
  const cut1 = CutId('cut-1');
  const cut2 = CutId('cut-2');
  const cut3 = CutId('cut-3');
  const key = LayerMark(process: LayerProcess.key);
  const layout = LayerMark(process: LayerProcess.layout);
  const roughKey = LayerMark(process: LayerProcess.roughKey);

  Cut cut(
    CutId id,
    String layerId, [
    CutMetadata metadata = const CutMetadata(),
  ]) => Cut(
    id: id,
    name: id.value,
    layers: [Layer(id: LayerId(layerId), name: 'A', frames: const [])],
    duration: 12,
    canvasSize: const CanvasSize(width: 400, height: 300),
    metadata: metadata,
  );

  /// cut-1 and cut-2 are 겸용 (their one layer shares a cel bank), cut-2
  /// naming its own 原画; cut-3 is on its own, naming its own layout. The
  /// work holds a 原画 name in memory — what a file once held — that no cut
  /// may print.
  ({
    ProjectRepository repository,
    CutCommandCoordinator cuts,
    HistoryManager history,
  })
  fixture() {
    final repository = ProjectRepository()
      ..replaceProject(
        Project(
          id: const ProjectId('project'),
          name: 'Project',
          createdAt: DateTime(2026, 9, 27),
          timesheetInfo: TimesheetInfo.empty.withStaffName(key, '山田'),
          tracks: [
            Track(
              id: track,
              name: 'Video',
              cuts: [
                cut(cut1, 'l1'),
                cut(cut2, 'l2', const CutMetadata().withStaffName(key, '大川')),
                cut(cut3, 'l3', const CutMetadata().withStaffName(layout, '清')),
              ],
            ),
          ],
          linkRegistry: LayerLinkRegistry(
            groups: [
              LayerLinkGroup(
                id: 'g',
                members: const [
                  LayerLinkMember(
                    trackId: track,
                    cutId: cut1,
                    layerId: LayerId('l1'),
                  ),
                  LayerLinkMember(
                    trackId: track,
                    cutId: cut2,
                    layerId: LayerId('l2'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    final history = HistoryManager();
    return (
      repository: repository,
      cuts: CutCommandCoordinator(
        repository: repository,
        editingSession: EditingSessionState(activeCutId: cut1),
        historyManager: history,
      ),
      history: history,
    );
  }

  Map<String, String> staffOf(ProjectRepository repository, CutId id) =>
      requireCut(repository.requireProject(), id).metadata.staff;

  test('a stage named for some cuts lands on each and on its 겸용 sibling; '
      'every stage it does not name keeps each cut its own; ONE undo puts '
      'every cut back', () {
    final (:repository, :cuts, :history) = fixture();

    cuts.saveCutSettings(cutIds: const [cut1, cut3], names: {key: '佐藤'});

    expect(staffOf(repository, cut1), {'key': '佐藤'});
    expect(staffOf(repository, cut2), {'key': '佐藤'}, reason: 'the sibling');
    expect(
      staffOf(repository, cut3),
      {'key': '佐藤', 'layout': '清'},
      reason: 'its layout was not part of the pick',
    );
    expect(history.undoCount, 1);

    history.undo();
    expect(staffOf(repository, cut1), isEmpty);
    expect(staffOf(repository, cut2), {'key': '大川'}, reason: 'its own back');
    expect(staffOf(repository, cut3), {'layout': '清'});
  });

  test('a name every one of the cuts already has is no undo step', () {
    final (:repository, :cuts, :history) = fixture();

    cuts.saveCutSettings(cutIds: const [cut3], names: {layout: '清'});

    expect(history.undoCount, 0);
    expect(staffOf(repository, cut3), {'layout': '清'});
  });

  test('🎯the sheets read the cut\'s own names — the work\'s are no '
      'fallback — and an emptied name prints nothing', () {
    final (:repository, :cuts, history: _) = fixture();
    Cut named(CutId id) => requireCut(repository.requireProject(), id);
    String envelopeKey(CutId id) =>
        buildCutEnvelopeSource(
          project: repository.requireProject(),
          cut: named(id),
        ).staff['key'] ??
        '';
    String artist(CutId id) => TimesheetDocument.fromCut(
      cut: named(id),
      projectName: 'Project',
      fps: 24,
      info: repository.requireProject().timesheetInfo,
    ).artist;

    expect(envelopeKey(cut2), '大川', reason: 'the envelope prints its 原画');
    expect(
      envelopeKey(cut3),
      '',
      reason: '⛔not the work\'s 山田 — a cut names its own',
    );

    cuts.saveCutSettings(cutIds: const [cut2], names: {roughKey: '林'});
    expect(
      artist(cut2),
      '林',
      reason: 'the sheet\'s 作業者 is the cut\'s 러프원화',
    );
    expect(artist(cut3), '');

    cuts.saveCutSettings(cutIds: const [cut2], names: {key: ''});
    expect(staffOf(repository, cut2), {'rough-key': '林'});
    expect(envelopeKey(cut2), '');
  });

  // ↩️It also pinned that a conte's name in a cut's staff, as a file held
  // it, was dropped on reading — what a file from before F-291-Q1 held
  // (format 9). Those formats are refused by their number now (the save
  // law, 유저 2026-10-06), and 컷 설정 offers only the stages a cut keeps.
  test('a cut\'s names travel with it through its file', () {
    final metadata = const CutMetadata(
      pageNotes: ['n'],
    ).withStaffName(key, '大川').withStaffName(layout, '清');

    expect(CutMetadata.fromJson(metadata.toJson()), metadata);
    expect(
      CutMetadata.fromJson(const CutMetadata(pageNotes: ['n']).toJson()).staff,
      isEmpty,
      reason: 'a cut naming no one writes nothing',
    );
  });

  /// 🗣️유저 2026-10-28 (F-291): 「이런 접힘/펼침상태는 컷별로 기억」 ·
  /// F-291-Q4 「파일에, 저장 버튼을 누를 때만」.
  group('the folds 컷 설정 opens on', () {
    Set<LayerProcess> foldsOf(ProjectRepository repository, CutId id) =>
        requireCut(repository.requireProject(), id).metadata.openStaffFolds;

    test('are the rough key\'s alone before a save; a save lands them on '
        'every cut it is about — a 겸용 sibling keeps its own — in the '
        'names\' ONE undo step', () {
      final (:repository, :cuts, :history) = fixture();
      for (final id in [cut1, cut2, cut3]) {
        expect(foldsOf(repository, id), {LayerProcess.roughKey});
      }

      cuts.saveCutSettings(
        cutIds: const [cut1, cut3],
        names: {layout: '林'},
        openFolds: {LayerProcess.key, LayerProcess.layout},
      );
      for (final id in [cut1, cut3]) {
        expect(foldsOf(repository, id), {
          LayerProcess.key,
          LayerProcess.layout,
        }, reason: '$id');
      }
      expect(
        foldsOf(repository, cut2),
        {LayerProcess.roughKey},
        reason: 'a window\'s memory of the cut, not the picture\'s',
      );

      history.undo();
      expect(history.canUndo, isFalse, reason: 'ONE step');
      expect(foldsOf(repository, cut1), {LayerProcess.roughKey});
      expect(foldsOf(repository, cut3), {LayerProcess.roughKey});
      expect(staffOf(repository, cut3), {'layout': '清'});
    });

    test('a save of folds alone is a step; one that changes nothing is '
        'none', () {
      final (:repository, :cuts, :history) = fixture();
      cuts.saveCutSettings(
        cutIds: const [cut1],
        names: const {},
        openFolds: {LayerProcess.roughKey},
      );
      expect(history.canUndo, isFalse);

      cuts.saveCutSettings(
        cutIds: const [cut1],
        names: const {},
        openFolds: const {},
      );
      expect(foldsOf(repository, cut1), isEmpty);
      expect(history.canUndo, isTrue);
    });

    test('travel with the cut through its file — and the rough key\'s '
        'alone write nothing', () {
      const shut = CutMetadata(openStaffFolds: {});
      const open = CutMetadata(
        openStaffFolds: {LayerProcess.key, LayerProcess.finish},
      );
      for (final metadata in [shut, open]) {
        expect(CutMetadata.fromJson(metadata.toJson()), metadata);
      }
      expect(const CutMetadata().toJson(), isEmpty);
    });
  });

  /// 🗣️유저 2026-10-28 (F-291): 「즉 컷마다 개별적임 … 신은 그리고 이름
  /// 비울수있음」 · F-291-Q5 「비어서 시작한다」 · F-291-Q6 「컷마다 따로(컷
  /// 이름처럼)」.
  group('a cut\'s scene', () {
    String sceneOf(ProjectRepository repository, CutId id) =>
        requireCut(repository.requireProject(), id).metadata.scene;

    test('starts empty, is the cut\'s alone — its 겸용 sibling keeps its own '
        '— and empties again', () {
      final (:repository, :cuts, :history) = fixture();
      expect(sceneOf(repository, cut1), isEmpty);

      cuts.setCutScene(cutId: cut1, scene: 'S3');
      expect(sceneOf(repository, cut1), 'S3');
      expect(sceneOf(repository, cut2), isEmpty, reason: 'its own, as names');

      cuts.setCutScene(cutId: cut1, scene: 'S3');
      history.undo();
      expect(history.canUndo, isFalse, reason: 'the same scene is no step');
      expect(sceneOf(repository, cut1), isEmpty);

      cuts.setCutScene(cutId: cut1, scene: 'S3');
      cuts.setCutScene(cutId: cut1, scene: '');
      expect(sceneOf(repository, cut1), isEmpty);
    });

    test('lands with the cut\'s name from the rename window, ONE undo '
        'step', () {
      final (:repository, :cuts, :history) = fixture();
      cuts.nameCut(cutId: cut3, name: 'C3', scene: 'S1');
      final cut = requireCut(repository.requireProject(), cut3);
      expect((cut.name, cut.metadata.scene), ('C3', 'S1'));

      history.undo();
      expect(history.canUndo, isFalse);
      final back = requireCut(repository.requireProject(), cut3);
      expect((back.name, back.metadata.scene), ('cut-3', ''));
    });

    test('travels with the cut through its file — none writes nothing', () {
      const metadata = CutMetadata(scene: 'S12');
      expect(CutMetadata.fromJson(metadata.toJson()), metadata);
      expect(const CutMetadata(scene: '').toJson(), isEmpty);
    });
  });

  /// I-82-Q1 「서식 전체 + 컷마다 덮어쓰기」: a cut keeps a room of its own
  /// over the format window's, and a 겸용 pair keeps one — one cut on paper.
  group('the room a cut\'s conte cells take', () {
    ConteCameraRoom? roomOf(ProjectRepository repository, CutId id) =>
        requireCut(repository.requireProject(), id).metadata.conteCameraRoom;

    test('is the format\'s until a save gives the cuts it is about their '
        'own — a 겸용 sibling too — in the names\' ONE undo step', () {
      final (:repository, :cuts, :history) = fixture();
      for (final id in [cut1, cut2, cut3]) {
        expect(roomOf(repository, id), isNull, reason: '$id');
      }

      cuts.saveCutSettings(
        cutIds: const [cut1, cut3],
        names: {layout: '林'},
        conteCameraRoom: (to: ConteCameraRoom.inCell),
      );
      for (final id in [cut1, cut2, cut3]) {
        expect(roomOf(repository, id), ConteCameraRoom.inCell, reason: '$id');
      }

      history.undo();
      expect(history.canUndo, isFalse, reason: 'ONE step');
      for (final id in [cut1, cut2, cut3]) {
        expect(roomOf(repository, id), isNull, reason: '$id');
      }
      expect(staffOf(repository, cut3), {'layout': '清'});
    });

    test('a null gives the pair back to the format; a room every cut '
        'already keeps is no step', () {
      final (:repository, :cuts, :history) = fixture();
      cuts.saveCutSettings(
        cutIds: const [cut3],
        names: const {},
        conteCameraRoom: (to: null),
      );
      expect(history.canUndo, isFalse);

      cuts.saveCutSettings(
        cutIds: const [cut2],
        names: const {},
        conteCameraRoom: (to: ConteCameraRoom.grows),
      );
      expect(roomOf(repository, cut1), ConteCameraRoom.grows);
      cuts.saveCutSettings(
        cutIds: const [cut2],
        names: const {},
        conteCameraRoom: (to: null),
      );
      expect((roomOf(repository, cut1), roomOf(repository, cut2)), (
        null,
        null,
      ));
    });
  });
}
