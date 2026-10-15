import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/conte_group.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨An attach row made from the conte row is a storyboard row — it takes
/// its base's kind — and the cut's conte was found as 「the first storyboard
/// row」. Measured 2026-10-08 on the app, before I-73's attach rows were
/// drawn on the storyboard: after 「어태치 추가 — 아래」 on the conte row the
/// cut's conte was the attach row, which stands before its base in the
/// cut's list.
///
/// The cut's conte is its storyboard row that rides no other
/// ([storyboardLayerForCut]), and the session's own questions ask the same.
void main() {
  /// A session whose cut has a conte row, stood on.
  (EditorSessionManager, LayerId) sessionOnTheConte() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    final conte = storyboardLayerForCut(session.requireActiveCut)!.id;
    session.selectLayer(conte);
    return (session, conte);
  }

  Layer layerOf(EditorSessionManager session, LayerId id) =>
      session.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

  test('🚨an attach row added BELOW the conte leaves the cut\'s conte where '
      'it was', () {
    final (session, conte) = sessionOnTheConte();

    session.folders.addAttachedLayer(AttachedPlacement.below);

    final cut = session.requireActiveCut;
    final below = session.activeLayer!;
    expect(
      (below.kind, below.attachedToLayerId),
      (LayerKind.storyboard, conte),
      reason: 'the premise: a storyboard row, riding the conte',
    );
    expect(
      cut.layers.indexWhere((layer) => layer.id == below.id),
      lessThan(cut.layers.indexWhere((layer) => layer.id == conte)),
      reason: 'the premise: and BEFORE it in the cut\'s list',
    );
    expect(storyboardLayerForCut(cut)?.id, conte);
  });

  test('a cut whose conte carries attach rows still has its ONE conte: no '
      'second is offered', () {
    final (session, conte) = sessionOnTheConte();
    session.folders.addAttachedLayer(AttachedPlacement.above);
    session.selectLayer(conte);
    session.folders.addAttachedLayer(AttachedPlacement.below);

    expect(session.layerStack.canAddLayerOfKind(LayerKind.storyboard), isFalse);
    expect(
      [
        for (final seat in conteGroupOf(session.requireActiveCut))
          (seat.seat, seat.row.name),
      ],
      [(1, 'Conte+1'), (0, 'Conte'), (-1, 'Conte-1')],
      reason: 'the group as the storyboard will draw it, top row first',
    );
  });

  test('the storyboard toggle of ANOTHER row is still refused by the conte '
      'under its attach rows', () {
    final (session, conte) = sessionOnTheConte();
    session.folders.addAttachedLayer(AttachedPlacement.below);
    final cel = session.requireActiveCut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.animation && !isAttachedLayer(layer),
    );

    session.selectLayer(cel.id);

    expect(
      session.layerSwitches.canToggleTargetLayerKind,
      isFalse,
      reason: 'the cut has its conte',
    );
    expect(layerOf(session, conte).kind, LayerKind.storyboard);
  });
}
