import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/services/commands/update_layer_collapsed_command.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';

/// 🗣️F-302 (유저 2026-10-05): 「겸용컷 … 폴더/어태치 접기/펼치기 버튼도
/// 공유 … 펼친 상태 접힌 상태 공유하라는것. 법통일」 — a row's fold is its
/// link group's: one command writes every use, and one undo puts back each
/// use's own.
void main() {
  late ProjectRepository repository;
  late CutId cutId;
  late LayerId first;
  late LayerId second;
  late LayerId third;

  setUp(() {
    final project = createDefaultProject();
    final track = project.tracks.first;
    final cut = track.cuts.first;
    cutId = cut.id;
    // Three rows of the default cut; the first two are made one link group
    // by the table alone — the command asks the table, not how it came.
    final rows = [for (final layer in cut.layers.take(3)) layer.id];
    expect(rows, hasLength(3), reason: 'fixture premise: three rows');
    [first, second, third] = rows;
    repository = ProjectRepository(
      initialProject: project.copyWith(
        linkRegistry: LayerLinkRegistry(
          groups: [
            LayerLinkGroup(
              id: 'g',
              members: [
                for (final row in [first, second])
                  LayerLinkMember(
                    trackId: track.id,
                    cutId: cutId,
                    layerId: row,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  });

  Layer row(LayerId id) =>
      requireLayerAnywhere(repository.requireProject(), id);

  void write(LayerId id, {required bool collapsed}) =>
      UpdateLayerCollapsedCommand.writeCollapsed(
        repository,
        cutId: cutId,
        layerId: id,
        value: collapsed,
      );

  test('folding one use folds every use of the row — and no other row', () {
    UpdateLayerCollapsedCommand(
      repository: repository,
      cutId: cutId,
      layerId: second,
      collapsed: true,
    ).execute();

    expect(row(first).collapsed, isTrue);
    expect(row(second).collapsed, isTrue);
    expect(row(third).collapsed, isFalse);
  });

  test('🚨undo puts back each use\'s OWN fold — uses that stood apart are '
      'apart again', () {
    // A file from before the fold was shared: one use shut, one open.
    write(first, collapsed: true);
    final command = UpdateLayerCollapsedCommand(
      repository: repository,
      cutId: cutId,
      layerId: second,
      collapsed: true,
    )..execute();
    expect([row(first).collapsed, row(second).collapsed], [true, true]);

    command.undo();

    expect([row(first).collapsed, row(second).collapsed], [true, false]);

    command.execute();
    expect([row(first).collapsed, row(second).collapsed], [true, true]);
  });

  test('opening one use opens every use', () {
    write(first, collapsed: true);
    write(second, collapsed: true);

    UpdateLayerCollapsedCommand(
      repository: repository,
      cutId: cutId,
      layerId: first,
      collapsed: false,
    ).execute();

    expect([row(first).collapsed, row(second).collapsed], [false, false]);
  });

  test('a row that is not linked folds alone', () {
    UpdateLayerCollapsedCommand(
      repository: repository,
      cutId: cutId,
      layerId: third,
      collapsed: true,
    ).execute();

    expect(
      [row(first).collapsed, row(second).collapsed, row(third).collapsed],
      [false, false, true],
    );
  });
}
