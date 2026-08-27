import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨★★★A FOLDER TAKES A COLOUR KEY — the user-facing end of the round.
///
/// This used to be impossible by rule: `effectKindsFor` hid the colour keys
/// wherever the chain's input was not cel bytes, because a key was a CPU
/// pass over those bytes and there was nothing else it could be. A folder
/// keys the picture it composed now, through a shader proven identical to
/// that pass.
///
/// ⛔The gate is GONE rather than always-true. A predicate that answers yes
/// for every input is not a gate, it is a list allocation per kind per
/// build — and the next reader would have had to work out that it never
/// says no. What replaced it is nothing: the row gate already asks the one
/// question left ("does this row have a chain at all").
void main() {
  EditorSessionManager sessionWithFolder() {
    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
    session.createDrawingAtCurrentFrame();
    session.groupActiveLayerIntoFolder();
    return session;
  }

  test('a FOLDER row accepts Delete Color and Keep Color', () {
    final session = sessionWithFolder();
    final folder = session.activeCutOrNull!.layers.folderLayers.single;
    session.selectLayer(folder.id);
    // ⛔Prove the row under test really is the folder, or this passes on
    // whatever happened to be selected.
    expect(session.activeLayer?.id, folder.id, reason: 'fixture');
    expect(session.canAddEffectToActiveLayer, isTrue);

    session.addEffectToActiveLayer(EffectKind.deleteColor);
    session.addEffectToActiveLayer(EffectKind.keepColor);
    final after = session.activeCutOrNull!.layers.folderLayers.single;
    expect(after.effects.map((e) => e.kind).toList(), [
      EffectKind.deleteColor,
      EffectKind.keepColor,
    ]);
  });

  test('a CEL row still does, and the order it is given is the order it keeps',
      () {
    final session = sessionWithFolder();
    final drawing = session.activeCutOrNull!.layers.firstWhere(
      (layer) => layer.folderId != null,
    );
    session.selectLayer(drawing.id);
    expect(session.activeLayer?.id, drawing.id, reason: 'fixture');

    session.addEffectToActiveLayer(EffectKind.blur);
    session.addEffectToActiveLayer(EffectKind.deleteColor);
    final after = session.activeCutOrNull!.layers.firstWhere(
      (layer) => layer.id == drawing.id,
    );
    // 🚨THE KEY STAYS UNDER THE BLUR. It used to be pulled to the front so
    // the lane list could not lie about an order the composite refused to
    // honour; the composite honours it now.
    expect(after.effects.map((e) => e.kind).toList(), [
      EffectKind.blur,
      EffectKind.deleteColor,
    ]);
  });
}
