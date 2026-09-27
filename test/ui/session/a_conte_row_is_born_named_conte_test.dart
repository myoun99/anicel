import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/services/editing/default_layer_helpers.dart'
    show nextCelLayerNameForCut;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';

/// F-76: A CONTE ROW IS BORN NAMED CONTE.
///
/// 🗣️유저 2026-09-11: 「스토리보드레이어의 레이어생성시 이름, 셀 이름
/// 규칙따르는게아니라 Conte 라고 되도록」. The row took the next cel letter
/// instead: its label landed with F-133 (`90f25376`) and its name was left
/// on the cel rule. The conte row a picture's first stroke makes is born
/// through the same function (a_picture_of_a_cut_with_no_conte_row_test).
void main() {
  test('the layer panel\'s conte row is named Conte, and a cel row after it '
      'still takes the next letter', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final nextLetter = nextCelLayerNameForCut(session.requireActiveCut);

    session.layerStack.addLayerOfKind(LayerKind.storyboard);

    expect(storyboardLayerForCut(session.requireActiveCut)!.name, 'Conte');

    session.layerStack.addLayerOfKind(LayerKind.animation);
    final cel = session.layers.firstWhere(
      (layer) => layer.id == session.activeLayerId,
    );
    expect(
      cel.name,
      nextLetter,
      reason: 'the conte row took no letter from the cel rows',
    );
  });
}
