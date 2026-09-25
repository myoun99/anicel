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
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/update_cut_mark_command.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _track = TrackId('track');
const _cut1 = CutId('cut-1');
const _cut2 = CutId('cut-2');
const _cut3 = CutId('cut-3');
const _layer1 = LayerId('layer-1');
const _layer2 = LayerId('layer-2');
const _layer3 = LayerId('layer-3');

const _key = LayerMark(process: LayerProcess.key);
const _layout = LayerMark(process: LayerProcess.layout);

Cut _cut(CutId id, LayerId layerId, {LayerMark mark = LayerMark.none}) => Cut(
  id: id,
  name: id.value,
  layers: [Layer(id: layerId, name: 'A', frames: const [])],
  duration: 12,
  canvasSize: const CanvasSize(width: 400, height: 300),
  metadata: CutMetadata(note: '${id.value} note', mark: mark),
);

/// cut-1 and cut-2 are 겸용 (their one layer shares a cel bank); cut-3 is on
/// its own.
ProjectRepository _repository() {
  final repository = ProjectRepository();
  repository.replaceProject(
    Project(
      id: const ProjectId('project'),
      name: 'Project',
      tracks: [
        Track(
          id: _track,
          name: 'Video',
          cuts: [
            _cut(_cut1, _layer1),
            _cut(_cut2, _layer2, mark: _layout),
            _cut(_cut3, _layer3),
          ],
        ),
      ],
      createdAt: DateTime(2020),
      linkRegistry: LayerLinkRegistry(
        groups: [
          LayerLinkGroup(
            id: 'g',
            members: const [
              LayerLinkMember(trackId: _track, cutId: _cut1, layerId: _layer1),
              LayerLinkMember(trackId: _track, cutId: _cut2, layerId: _layer2),
            ],
          ),
        ],
      ),
    ),
  );
  return repository;
}

LayerMark _markOf(ProjectRepository repository, CutId cutId) =>
    requireCut(repository.requireProject(), cutId).metadata.mark;

void main() {
  /// 🗣️유저 2026-09-26: 「겸용컷은 물론 한 컷 취급이니까 같이바뀌고」.
  test('a label set on one 겸용 cut lands on its sibling too, and one undo '
      'puts both back', () {
    final repository = _repository();
    final command = UpdateCutMarkCommand(
      repository: repository,
      cutIds: const [_cut1],
      mark: _key,
    )..execute();

    expect(_markOf(repository, _cut1), _key);
    expect(_markOf(repository, _cut2), _key, reason: 'the 겸용 sibling');
    expect(_markOf(repository, _cut3), LayerMark.none, reason: 'unlinked');
    expect(
      requireCut(repository.requireProject(), _cut2).metadata.note,
      'cut-2 note',
      reason: 'only the label changes',
    );

    command.undo();
    expect(_markOf(repository, _cut1), LayerMark.none);
    expect(_markOf(repository, _cut2), _layout, reason: 'its own label back');
  });

  /// 🗣️「선택범위 한상태로 조작가능한거 물론이고」.
  test('the cuts a selection covers take the label as ONE step', () {
    final repository = _repository();
    final command = UpdateCutMarkCommand(
      repository: repository,
      cutIds: const [_cut1, _cut3],
      mark: _key,
    )..execute();

    for (final cutId in [_cut1, _cut2, _cut3]) {
      expect(_markOf(repository, cutId), _key, reason: '$cutId');
    }
    command.undo();
    expect(_markOf(repository, _cut1), LayerMark.none);
    expect(_markOf(repository, _cut2), _layout);
    expect(_markOf(repository, _cut3), LayerMark.none);
  });

  test('the targets are each cut and its siblings, once each', () {
    final project = _repository().requireProject();
    expect(
      UpdateCutMarkCommand.targetsOf(project, const [_cut1, _cut2]),
      [_cut1, _cut2],
    );
    expect(UpdateCutMarkCommand.targetsOf(project, const [_cut3]), [_cut3]);
  });

  test('the label is saved with the cut, and an unlabelled cut writes none', () {
    const labelled = CutMetadata(mark: _key);
    expect(CutMetadata.fromJson(labelled.toJson()), labelled);
    expect(const CutMetadata().toJson().containsKey('mark'), isFalse);
    expect(
      CutMetadata.fromJson(const {'note': ''}).mark,
      LayerMark.none,
      reason: 'a file from before the label reads as unlabelled',
    );
  });
}
