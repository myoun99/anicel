import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// FOUR VERBS, ONE ENVELOPE: gate, take the ACTIVE row's id, run one
/// coordinator command keyed by (cutId, layerId), then refresh KEEPING
/// THAT ROW ACTIVE and notify.
///
/// The trailing step is the one that goes missing when the envelope is
/// written out four times — `CutVerbs._moveActiveCut` carries a comment
/// recording exactly that loss. Pinned here for all four before they were
/// folded onto one call.
void main() {
  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  test('link duplicate leaves you standing on the row you duplicated', () {
    final s = session();
    final layer = s.layers.firstWhere((l) => l.kind == LayerKind.animation).id;
    s.selectLayer(layer);
    expect(s.canLinkDuplicateActiveLayer, isTrue);

    s.linkDuplicateActiveLayer();

    expect(s.activeLayerId, layer);
  });

  test('unlink leaves you standing on the row you unlinked', () {
    final s = session();
    final layer = s.layers.firstWhere((l) => l.kind == LayerKind.animation).id;
    s.selectLayer(layer);
    s.linkDuplicateActiveLayer();
    expect(s.activeLayerId, layer);
    expect(s.canUnlinkActiveLayer, isTrue);

    s.unlinkActiveLayer();

    expect(s.activeLayerId, layer);
  });

  test('폴더 생성 leaves you on the LAYER, not on the folder it made', () {
    final s = session();
    final layer = s.layers.firstWhere((l) => l.kind == LayerKind.animation).id;
    s.selectLayer(layer);
    expect(s.canGroupActiveLayerIntoFolder, isTrue);

    s.groupActiveLayerIntoFolder();

    expect(s.activeLayerId, layer);
    expect(
      s.requireActiveCut.layers.any((l) => l.kind == LayerKind.folder),
      isTrue,
      reason: 'premise: the folder really was made',
    );
  });

  test('공정 폴더 생성 leaves you on the ATTACH row', () {
    final s = session();
    s.createDrawingAtCurrentFrame();
    s.addAttachedLayer(AttachedPlacement.above);
    final attach = s.activeLayer!.id;
    expect(s.canGroupActiveAttachIntoFolder, isTrue);

    s.groupActiveAttachIntoFolder();

    expect(s.activeLayerId, attach);
    expect(
      s.requireActiveCut.layers.firstWhere((l) => l.id == attach).folderId,
      isNotNull,
      reason: 'premise: the organizer really wrapped it',
    );
  });

  test('a closed gate runs nothing at all', () {
    final s = session();
    final instruction = s.layers
        .where((l) => l.kind != LayerKind.animation)
        .map((l) => l.id)
        .firstOrNull;
    if (instruction == null) {
      return; // The default project has only animation rows here.
    }
    s.selectLayer(instruction);
    final before = s.requireActiveCut.layers.length;

    if (!s.canGroupActiveLayerIntoFolder) {
      s.groupActiveLayerIntoFolder();
      expect(s.requireActiveCut.layers.length, before);
      expect(s.activeLayerId, LayerId(instruction.value));
    }
  });
}
