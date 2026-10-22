import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/visibility_solo.dart';

/// 🚨F-327 — THE SOLO FOLLOWS THE ACTIVE LAYER THROUGH EVERY DOOR.
///
/// 유저 2026-10-09: 「솔로 레이어 on인상태로 레이어만들면 새 레이어에 서는데,
/// 이전 레이어의 그림이 on인채로 있음. 죽 새 레이어랑 이전레이어 둘 다 비지블
/// on인상태로되있음 거기서 레이어 다른곳에서면 정상적으로 돌아옴」.
///
/// The solo followed the layer from the stand alone, and Add Layer seats its
/// new row straight on the controller: the row it was added from kept the
/// solo's ON, and the new one was born on beside it. It follows where the
/// verbs' row does now — at the session's one announcement, which every
/// door passes (F-183 ③).
void main() {
  /// Held by its own type — `tool/mutation_run.dart` picks a file's
  /// witnesses by which tests IMPORT it.
  VisibilitySolo soloOf(EditorSessionManager s) => s.visibilitySolo;

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  /// The eyes the solo answers for — not the camera's, the camera view
  /// (F-363-Q2).
  Map<LayerId, bool> eyesOf(EditorSessionManager s) => {
    for (final layer in s.layers)
      if (layer.kind.hasPictureEye) layer.id: layer.isVisible,
  };

  Set<LayerId> shownIn(EditorSessionManager s) => {
    for (final MapEntry(:key, :value) in eyesOf(s).entries)
      if (value) key,
  };

  test('a row added while soloing is shown alone, and the row it was added '
      'from goes off', () {
    final s = session();
    final from = s.activeLayerId!;
    soloOf(s).toggleLayerVisibilitySolo();
    expect(shownIn(s), {from}, reason: 'the premise: soloed');

    s.layerStack.addLayer();

    final added = s.activeLayerId!;
    expect(added, isNot(from), reason: 'the premise: you stand on it');
    expect(shownIn(s), {added});
  });

  test('an SE row added while soloing too — the other door that seats its '
      'row on the controller', () {
    final s = session();
    soloOf(s).toggleLayerVisibilitySolo();

    s.layerStack.addLayerOfKind(LayerKind.se);

    expect(s.activeLayer!.kind, LayerKind.se, reason: 'the premise');
    expect(shownIn(s), {s.activeLayerId});
  });

  test('leaving the solo puts back the eye each row had — the added one the '
      'eye it was born with', () {
    final s = session();
    final before = eyesOf(s);
    soloOf(s).toggleLayerVisibilitySolo();
    s.layerStack.addLayer();
    final added = s.activeLayerId!;

    soloOf(s).toggleLayerVisibilitySolo();

    expect(eyesOf(s), {...before, added: true});
  });

  test('⛔an eye clicked by hand while you stand still is not fought: the '
      'solo follows the layer when it MOVES, not every announcement', () {
    final s = session();
    final other = s.layers
        .firstWhere(
          (layer) =>
              layer.id != s.activeLayerId && layer.kind != LayerKind.camera,
        )
        .id;
    soloOf(s).toggleLayerVisibilitySolo();
    expect(shownIn(s), isNot(contains(other)), reason: 'the premise');

    s.layerSwitches.toggleLayerVisibility(other);

    expect(shownIn(s), contains(other));
  });
}
