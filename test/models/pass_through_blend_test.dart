import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// PASS THROUGH (통과) — Photoshop's and CSP's default group mode, and
/// ours. A folder made to tidy the stack must not change one pixel;
/// buffering the group is what you opt into by giving it a real mode.
void main() {
  test('a fresh folder is PASS THROUGH, and pass-through does not isolate',
      () {
    final folder = createFolderLayer(
      id: const LayerId('f'),
      name: 'F',
    );
    expect(folder.blendMode, LayerBlendMode.passThrough);
    expect(folder.blendMode.isolatesGroup, isFalse);

    for (final mode in LayerBlendMode.values) {
      if (mode == LayerBlendMode.passThrough) {
        continue;
      }
      expect(
        mode.isolatesGroup,
        isTrue,
        reason: '$mode needs the group composed before it has anything to '
            'blend',
      );
    }
  });

  test('only GROUP rows are offered pass-through', () {
    expect(
      LayerBlendMode.optionsFor(isGroup: false),
      isNot(contains(LayerBlendMode.passThrough)),
    );
    expect(
      LayerBlendMode.optionsFor(isGroup: true),
      contains(LayerBlendMode.passThrough),
    );
    expect(
      LayerBlendMode.optionsFor(isGroup: true).first,
      LayerBlendMode.passThrough,
      reason: 'the default leads the list, like PS/CSP',
    );
  });

  test('pass-through round-trips and reads the CSP term in ja', () {
    final folder = createFolderLayer(id: const LayerId('f'), name: 'F');
    expect(folder.toJson()['blendMode'], 'passThrough');
    expect(
      Layer.fromJson(folder.toJson()).blendMode,
      LayerBlendMode.passThrough,
    );
    expect(LayerBlendMode.passThrough.label, 'Pass Through');
    expect(LayerBlendMode.passThrough.labelFor(AppLanguage.ja), '通過');
  });

  test('a pass-through folder contributes NO blend to its members; an '
      'isolating one does', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.createDrawingAtCurrentFrame();
    final memberId = s.activeLayer!.id;
    s.groupActiveLayerIntoFolder();
    final folderId = s.activeCutOrNull!.layers.folderLayers.single.id;

    // Default (pass-through): the member keeps its own normal blend.
    expect(
      s.activeCutOrNull!.layers.folderById(folderId)!.blendMode,
      LayerBlendMode.passThrough,
    );
    expect(s.activeCutOrNull!.layers.byId(memberId)!.blendMode,
        LayerBlendMode.normal);

    // Isolating: the folder's mode reaches the member (flat-path
    // behaviour; the tree gives the group its own buffer).
    s.setLayerBlendMode(folderId, LayerBlendMode.multiply);
    expect(
      s.activeCutOrNull!.layers.folderById(folderId)!.blendMode,
      LayerBlendMode.multiply,
    );
  });
}
