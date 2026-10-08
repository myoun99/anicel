import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import '../../helpers/pill_row_clipboard.dart';
import '../../helpers/a_cut_with_a_drawing_row.dart';

/// 🗣️F-302 (유저 2026-10-05): 「겸용컷, 레이어에서 fx 접기펼치기, 폴더/어태치
/// 접기/펼치기 버튼도 공유. 지금 겸용컷별로 독립적임. 펼친 상태 접힌 상태
/// 공유하라는것. 법통일」.
///
/// A linked row is one row seen from several cuts: how it is twirled and
/// folded is the row's, in every cut that shows it. The eye is still each
/// cut's own (F-278: 「보이기만 독립적으로 하고」).
void main() {
  test('🚨a FOLDER folded in one 겸용 cut is folded in the other — and one '
      'undo opens both', () {
    final r = _Rig()..linkACut();
    final depth = r.s.historyManager.undoCount;

    r.presses.toggleGroupFold(r.twinOf(r.folder));

    expect(r.collapsed(r.twinOf(r.folder)), isTrue);
    expect(r.collapsed(r.folder), isTrue, reason: 'the origin cut\'s too');
    expect(r.s.historyManager.undoCount, depth + 1);

    r.s.undo();
    expect(
      [r.collapsed(r.twinOf(r.folder)), r.collapsed(r.folder)],
      [false, false],
      reason: 'each use is put back, in the one step',
    );
  });

  test('🚨an ATTACH group folded in one 겸용 cut is folded in the other — '
      'and one undo opens both', () {
    final r = _Rig()..linkACut();
    final folded = r.s.railView.collapsedAttachBaseIds;
    final depth = r.s.historyManager.undoCount;

    r.presses.toggleGroupFold(r.twinOf(r.base));

    expect(folded.value, {r.base, r.twinOf(r.base)});
    expect(r.s.historyManager.undoCount, depth + 1);

    r.s.undo();
    expect(folded.value, isEmpty);
  });

  test('🚨a row\'s lanes twirled open in one 겸용 cut are open in the '
      'other, shut again with it, and undone as one', () {
    final r = _Rig()..linkACut();
    final open = r.s.railView.expandedLaneLayerIds;

    r.presses.toggleLanes(r.twinOf(r.plain));
    expect(open.value, {r.plain, r.twinOf(r.plain)});

    r.presses.toggleLanes(r.twinOf(r.plain));
    expect(open.value, isEmpty);

    r.s.undo();
    expect(open.value, {r.plain, r.twinOf(r.plain)});
  });

  test('🚨a lane GROUP twirled open inside a row is open in every use of '
      'the row, and shut with it', () {
    final r = _Rig()..linkACut();
    final open = r.s.railView.expandedLaneGroupKeys;
    final group = transformGroupHeaderLane.laneId;

    r.presses.toggleLaneGroup(laneGroupKey(r.twinOf(r.plain), group));
    expect(open.value, {
      laneGroupKey(r.plain, group),
      laneGroupKey(r.twinOf(r.plain), group),
    });

    // …and shut from the OTHER cut, on its own row.
    r.s.selectCut(r.origin);
    r.presses.toggleLaneGroup(laneGroupKey(r.plain, group));
    expect(open.value, isEmpty);
  });

  test('a row no other cut shows twirls alone — a linked row beside it is '
      'not taken along', () {
    final r = _Rig()..linkACut();
    // A cut of its own beside the two: its rows are in no link group.
    r.s.cutVerbs.createCut();
    final alone = r.s.activeLayerId!;
    expect(r.s.layerVerbs.isLayerLinked(alone), isFalse, reason: '⛔전제');

    r.presses.toggleLanes(alone);

    expect(r.s.railView.expandedLaneLayerIds.value, {alone});
  });

  test('🚨a 겸용 cut MADE from a cut wears its twirls and folds from the '
      'start — its rows are new, and nothing was ever folded by them', () {
    final r = _Rig();
    r.presses.toggleLanes(r.plain);
    r.presses.toggleGroupFold(r.base);
    r.presses.toggleLaneGroup(
      laneGroupKey(r.plain, transformGroupHeaderLane.laneId),
    );
    r.presses.toggleGroupFold(r.folder);

    r.linkACut();

    expect(r.s.railView.expandedLaneLayerIds.value, {
      r.plain,
      r.twinOf(r.plain),
    });
    expect(r.s.railView.collapsedAttachBaseIds.value, {
      r.base,
      r.twinOf(r.base),
    });
    expect(r.s.railView.expandedLaneGroupKeys.value, {
      laneGroupKey(r.plain, transformGroupHeaderLane.laneId),
      laneGroupKey(r.twinOf(r.plain), transformGroupHeaderLane.laneId),
    });
    expect(r.collapsed(r.twinOf(r.folder)), isTrue);
  });

  test('a row LINK-DUPLICATED beside its origin wears the origin\'s twirl '
      '— every door a row joins a group through is followed', () {
    final r = _Rig();
    r.presses.toggleLanes(r.plain);
    final before = {for (final layer in r.s.layers) layer.id};
    r.s.selectLayer(r.plain);

    linkDuplicateActiveRow(r.s);

    final copy = r.s.layers.firstWhere((l) => !before.contains(l.id)).id;
    expect(r.s.layerVerbs.isLayerLinked(copy), isTrue, reason: '⛔전제');
    expect(r.s.railView.expandedLaneLayerIds.value, {r.plain, copy});
  });

  test('two cuts made 겸용 of each other fold one way from then on: the '
      'group\'s canonical row is the one followed', () {
    final r = _Rig();
    // A second cut of its own, standing differently: its first cel's lanes
    // are open, the origin's are shut.
    createCutWithADrawingRow(r.s);
    final other = r.s.requireActiveCut.id;
    final otherCel = r.s.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    r.presses.toggleLanes(otherCel);
    r.s.selectCut(r.origin);
    expect(r.s.railView.expandedLaneLayerIds.value, {otherCel}, reason: '⛔전제');

    r.s.cutVerbs.convertActiveCutToLinked(other);

    final links = r.s.repository.requireProject().linkRegistry;
    for (final group in links.groups) {
      final open = [
        for (final member in group.members)
          r.s.railView.expandedLaneLayerIds.value.contains(member.layerId),
      ];
      expect(
        open.toSet(),
        hasLength(1),
        reason: 'every use of ${group.canonical.layerId} twirls one way',
      );
      expect(open.first, group.canonical.layerId == otherCel);
    }
    expect(links.groups, isNotEmpty, reason: '⛔전제: the cuts linked');
  });

  test('🚨the walk that opens what hides the row you are taken to opens it '
      'in every use — a folder and an attach group', () {
    final r = _Rig()..linkACut();
    r.presses.toggleGroupFold(r.twinOf(r.folder));
    r.presses.toggleGroupFold(r.twinOf(r.base));
    expect(r.collapsed(r.folder), isTrue, reason: '⛔전제');

    // An undo's walk lands on the row inside the folder, then on the row
    // riding the base — in the 겸용 cut.
    r.s.standing.standOn(
      (cut: r.linked, layer: r.twinOf(r.inFolder), frame: 0),
    );
    expect(
      [r.collapsed(r.twinOf(r.folder)), r.collapsed(r.folder)],
      [false, false],
      reason: 'the folder opened in the origin cut too',
    );

    r.s.standing.standOn(
      (cut: r.linked, layer: r.twinOf(r.rider), frame: 0),
    );
    expect(
      r.s.railView.collapsedAttachBaseIds.value,
      isEmpty,
      reason: 'the attach group unfolded in the origin cut too',
    );
  });

  test('「보이기만 독립적으로」 — folding a row in one cut leaves the other '
      'cut\'s eye alone', () {
    final r = _Rig()..linkACut();
    final eyeBefore = r.row(r.folder).isVisible;
    r.presses.toggleVisibility(r.twinOf(r.folder));
    r.presses.toggleGroupFold(r.twinOf(r.folder));

    expect(r.row(r.twinOf(r.folder)).isVisible, !eyeBefore);
    expect(r.row(r.folder).isVisible, eyeBefore);
    expect(r.collapsed(r.folder), isTrue);
  });
}

/// A base carrying an attach row, a folder holding a cel, and a plain cel —
/// and, once [linkACut] has run, a 겸용 cut of all of it, in hand.
class _Rig {
  _Rig() : s = EditorSessionManager(initialProject: createDefaultProject()) {
    addTearDown(s.dispose);
    origin = s.requireActiveCut.id;
    base = s.layers.firstWhere((l) => l.kind == LayerKind.animation).id;
    inFolder = _added();
    plain = _added();
    s.selectLayer(base);
    s.folders.addAttachedLayer(AttachedPlacement.above);
    rider = s.requireActiveCut.layers
        .firstWhere((layer) => layer.attachedToLayerId == base)
        .id;
    s.selectLayer(inFolder);
    s.folders.groupActiveLayerIntoFolder();
    folder = s.requireActiveCut.layers.folderLayers.single.id;
  }

  final EditorSessionManager s;
  late final CutId origin;
  late final CutId linked;
  late final LayerId base;
  late final LayerId rider;
  late final LayerId folder;
  late final LayerId inFolder;
  late final LayerId plain;

  LayerId _added() {
    final before = {for (final layer in s.layers) layer.id};
    s.layerStack.addLayerOfKind(LayerKind.animation);
    return s.layers.firstWhere((layer) => !before.contains(layer.id)).id;
  }

  SessionRowButtonPresses get presses => SessionRowButtonPresses(s);

  /// Makes the 겸용 cut and stands in it.
  void linkACut() {
    s.cutVerbs.createLinkedCutFromActiveCut();
    linked = s.activeTrack.cuts.firstWhere((cut) => cut.id != origin).id;
    expect(s.requireActiveCut.id, linked, reason: '⛔전제: the new cut is in '
        'hand');
    for (final id in [base, rider, folder, inFolder, plain]) {
      expect(s.layerVerbs.isLayerLinked(twinOf(id)), isTrue, reason: '⛔전제');
    }
  }

  /// [id]'s use in the 겸용 cut: the other row of its link group.
  LayerId twinOf(LayerId id) => s.repository
      .requireProject()
      .linkRegistry
      .groupOf(cutId: origin, layerId: id)!
      .members
      .firstWhere((member) => member.cutId == linked)
      .layerId;

  Layer row(LayerId id) =>
      requireLayerAnywhere(s.repository.requireProject(), id);

  bool collapsed(LayerId id) => row(id).collapsed;
}
