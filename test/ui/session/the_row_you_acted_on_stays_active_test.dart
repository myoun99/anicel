import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import '../../helpers/pill_row_clipboard.dart';

/// THE ROW YOU ACTED ON STAYS ACTIVE: unlinking a row leaves you standing
/// on it.
///
/// ↩️Four verbs once shared one envelope — gate, take the ACTIVE row's id,
/// run one coordinator command, then refresh KEEPING THAT ROW ACTIVE — and
/// this file pinned the envelope for all four. They have all left it: 링크
/// 해제 went to the link window (I-25), 링크 복제 is the shared pill's
/// linked PASTE (I-77), and 폴더 생성 · 공정 폴더 생성 went with their menu
/// entries (R5 #14) — a folder is made empty and filled by a drop
/// (layer-menu-strings-outlive-their-entries-Q3). The unlink pin stays, for
/// the row verb the window presses.
void main() {
  test('unlink leaves you standing on the row you unlinked', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final layer = s.layers.firstWhere((l) => l.kind == LayerKind.animation).id;
    s.selectLayer(layer);
    linkDuplicateActiveRow(s);
    expect(s.activeLayerId, layer);
    expect(
      s.layerVerbs.groupIsLinked(s.activeLayer!, s.requireActiveCut),
      isTrue,
    );

    // The menu's unlink is gone (I-25): the link window's button is the door.
    s.layerVerbs.unlinkLayers([layer]);

    expect(s.activeLayerId, layer);
  });
}
