import 'package:anicel/src/models/canvas_size.dart';
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

    cuts.setCutStaffNames(cutIds: const [cut1, cut3], names: {key: '佐藤'});

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

    cuts.setCutStaffNames(cutIds: const [cut3], names: {layout: '清'});

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

    cuts.setCutStaffNames(cutIds: const [cut2], names: {roughKey: '林'});
    expect(
      artist(cut2),
      '林',
      reason: 'the sheet\'s 作業者 is the cut\'s 러프원화',
    );
    expect(artist(cut3), '');

    cuts.setCutStaffNames(cutIds: const [cut2], names: {key: ''});
    expect(staffOf(repository, cut2), {'rough-key': '林'});
    expect(envelopeKey(cut2), '');
  });

  test('a cut\'s names travel with it through its file — but the conte\'s, '
      'which is the work\'s', () {
    final metadata = const CutMetadata(
      note: 'n',
    ).withStaffName(key, '大川').withStaffName(layout, '清');

    expect(CutMetadata.fromJson(metadata.toJson()), metadata);
    expect(
      CutMetadata.fromJson(const CutMetadata(note: 'n').toJson()).staff,
      isEmpty,
      reason: 'a cut naming no one writes nothing',
    );
    expect(
      CutMetadata.fromJson({
        'note': 'n',
        'staff': {'conte': '콘티', 'key': '大川'},
      }).staff,
      {'key': '大川'},
    );
  });
}
