import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';

/// 🗣️I-32 (유저 2026-09-14): 「레이어 선택범위 버튼 일괄조작 … 기존 규칙
/// 로직 최대한 통일하면서 따라서(선택안 버튼조작은 선택전부적용, 그 외 조작은
/// 그것만 적용 등 이런 규칙) … fx펼치기, … 그룹펼치기 … 일괄조작가능하게」.
///
/// The group fold is ONE chevron with two verbs (`timelineGroupFoldFor`): a
/// folder folds itself, a base folds the attach group riding it. Pressed
/// inside the row selection it folds every selected row that has one.
void main() {
  test('pressed inside the selection, a folder and two bases fold together '
      '— as one undo', () {
    final r = _Rig();
    r.select([r.baseA, r.folder, r.baseB]);
    final depth = r.s.historyManager.undoCount;

    r.presses.toggleGroupFold(r.baseA);

    expect(r.open(r.baseA), isFalse);
    expect(r.open(r.baseB), isFalse, reason: '「선택안 버튼조작은 선택전부적용」');
    expect(r.open(r.folder), isFalse, reason: 'a folder is the same chevron');
    expect(r.s.historyManager.undoCount, depth + 1, reason: 'one step');

    r.s.undo();
    expect(
      [r.open(r.baseA), r.open(r.folder), r.open(r.baseB)],
      [true, true, true],
      reason: '「언두하나」',
    );
  });

  test('pressed outside the selection, it is that row\'s alone', () {
    final r = _Rig();
    r.select([r.folder, r.baseB]);

    r.presses.toggleGroupFold(r.baseA);

    expect(r.open(r.baseA), isFalse);
    expect([r.open(r.folder), r.open(r.baseB)], [true, true]);
  });

  test('a row with no group is passed by', () {
    final r = _Rig();
    r.select([r.baseA, r.plain]);

    r.presses.toggleGroupFold(r.baseA);

    expect(r.open(r.baseA), isFalse);
    expect(r.open(r.plain), isNull, reason: 'no chevron, nothing to fold');
  });
}

/// Two bases carrying an attach row each, a folder holding a third cel, and a
/// plain cel with no group.
class _Rig {
  _Rig() : s = EditorSessionManager(initialProject: createDefaultProject()) {
    addTearDown(s.dispose);
    final cels = [
      s.layers.firstWhere((layer) => layer.kind == LayerKind.animation).id,
      for (var i = 0; i < 3; i++) _added(),
    ];
    baseA = cels[0];
    baseB = cels[1];
    plain = cels[3];
    for (final base in [baseA, baseB]) {
      s.selectLayer(base);
      s.folders.addAttachedLayer(AttachedPlacement.above);
    }
    s.selectLayer(cels[2]);
    s.folders.groupActiveLayerIntoFolder();
    folder = s.activeCutOrNull!.layers.folderLayers.single.id;
    expect(
      [open(baseA), open(baseB), open(folder), open(plain)],
      [true, true, true, null],
      reason: 'the premise: three open groups and a row with none',
    );
  }

  final EditorSessionManager s;
  late final LayerId baseA;
  late final LayerId baseB;
  late final LayerId folder;
  late final LayerId plain;

  LayerId _added() {
    final before = {for (final layer in s.layers) layer.id};
    s.layerStack.addLayerOfKind(LayerKind.animation);
    return s.layers.firstWhere((layer) => !before.contains(layer.id)).id;
  }

  SessionRowButtonPresses get presses => SessionRowButtonPresses(s);

  void select(List<LayerId> ids) =>
      s.rowSelection.value = [for (final id in ids) LayerRowAddress(id)];

  /// The chevron's reading — null for a row that has none.
  bool? open(LayerId id) {
    final layer = requireLayerAnywhere(s.repository.requireProject(), id);
    if (layer.kind.groupsLayers) {
      return !layer.collapsed;
    }
    final riders = s.activeCutOrNull!.layers.where(
      (candidate) => candidate.attachedToLayerId == id,
    );
    return riders.isEmpty
        ? null
        : !s.railView.collapsedAttachBaseIds.value.contains(id);
  }
}
