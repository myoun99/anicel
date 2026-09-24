import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨★★★EVERY LAYER EDIT UNDOES, including the eye.
///
/// 유저 2026-08-28: 「무언가를 바꾸는 동작은 기본 이럼. 프레임블록 편집도
/// 언두 되는게 보통이고 지금 그렇게 되있는데 왜 레이어편집이라고 언두에
/// 안넣은건지 애초에 이해할수없음. **눈을 껏다키든 뭐든 다 언두고
/// 그리는동안 눈 껏다켠뒤 컨트롤z면 당연히 눈이 바뀌는게 맞는거임.**」
///
/// The last sentence is the first test below, verbatim: toggle the eye
/// while drawing, press Ctrl+Z, the eye comes back.
///
/// ⛔THE ORIGINAL REPORT was about BATCHES: 「일괄로 버튼 조작하고 언두하면
/// 바꼈던 레이어들 다 한번에 언두되야하는데 안됨」. Making the writes
/// undoable is only half of that — a bulk action that loops a per-layer
/// call needs one press per row, which is the same complaint wearing a
/// different hat. So the batch tests count PRESSES, not values.
void main() {
  EditorSessionManager newSession() =>
      EditorSessionManager(initialProject: createDefaultProject());

  test('toggling the eye undoes', () {
    final session = newSession();
    addTearDown(session.dispose);
    final layerId = session.layers.first.id;
    final before = requireLayerAnywhere(
      session.repository.requireProject(),
      layerId,
    ).isVisible;

    session.layerSwitches.toggleLayerVisibility(layerId);
    expect(
      requireLayerAnywhere(
        session.repository.requireProject(),
        layerId,
      ).isVisible,
      !before,
      reason: 'fixture: the toggle actually changed something',
    );

    session.historyManager.undo();
    expect(
      requireLayerAnywhere(
        session.repository.requireProject(),
        layerId,
      ).isVisible,
      before,
      reason: 'the eye is an edit — 「눈을 껏다키든 뭐든 다 언두」',
    );
  });

  test('and redo puts it back', () {
    final session = newSession();
    addTearDown(session.dispose);
    final layerId = session.layers.first.id;
    final before = requireLayerAnywhere(
      session.repository.requireProject(),
      layerId,
    ).isVisible;

    session.layerSwitches.toggleLayerVisibility(layerId);
    session.historyManager.undo();
    session.historyManager.redo();

    // ⛔The command captures its previous state ONCE. A capture taken on
    // every execute would record the undone state during redo, and the
    // undo after that would restore the wrong value.
    expect(
      requireLayerAnywhere(
        session.repository.requireProject(),
        layerId,
      ).isVisible,
      !before,
    );
    session.historyManager.undo();
    expect(
      requireLayerAnywhere(
        session.repository.requireProject(),
        layerId,
      ).isVisible,
      before,
      reason: 'undo after redo still restores the ORIGINAL value',
    );
  });

  test('blend mode and opacity undo too', () {
    final session = newSession();
    addTearDown(session.dispose);
    final layerId = session.layers.first.id;
    final project = session.repository.requireProject();
    final beforeBlend = requireLayerAnywhere(project, layerId).blendMode;
    final beforeOpacity = requireLayerAnywhere(project, layerId).opacity;

    session.layerSwitches.setLayerBlendMode(
      layerId,
      beforeBlend == LayerBlendMode.multiply
          ? LayerBlendMode.screen
          : LayerBlendMode.multiply,
    );
    session.opacityVerbs.setLayerOpacity(layerId: layerId, opacity: 0.25);

    session.historyManager.undo();
    expect(
      requireLayerAnywhere(
        session.repository.requireProject(),
        layerId,
      ).opacity,
      beforeOpacity,
      reason: 'renaming a layer already undid; the blend beside it did not',
    );
    session.historyManager.undo();
    expect(
      requireLayerAnywhere(
        session.repository.requireProject(),
        layerId,
      ).blendMode,
      beforeBlend,
    );
  });

  test('a bulk hide undoes in ONE press, not one per row', () {
    // 🚨THE REPORT ITSELF. Undoing a screenful of rows one press at a time
    // is what 유저 called out; the writes becoming undoable does not fix
    // it on its own.
    final session = newSession();
    addTearDown(session.dispose);
    for (var i = 0; i < 3; i += 1) {
      session.layerStack.addLayer();
    }
    final visibleBefore = {
      for (final layer in session.layers)
        layer.id: requireLayerAnywhere(
          session.repository.requireProject(),
          layer.id,
        ).isVisible,
    };
    expect(
      visibleBefore.length,
      greaterThan(1),
      reason: 'fixture: more than one row, or the batch proves nothing',
    );

    session.layerSwitches.setAllLayersVisibility(false);
    session.historyManager.undo();

    for (final entry in visibleBefore.entries) {
      expect(
        requireLayerAnywhere(
          session.repository.requireProject(),
          entry.key,
        ).isVisible,
        entry.value,
        reason: 'ONE undo restored every row the bulk action changed',
      );
    }
  });

  test('the batch is one entry, so a second undo reaches PAST it', () {
    // ⛔THE COUNTER-TEST. If the bulk action still made one entry per row,
    // the test above would pass on its last row alone and this one would
    // fail — the second undo would still be inside the batch.
    final session = newSession();
    addTearDown(session.dispose);
    for (var i = 0; i < 3; i += 1) {
      session.layerStack.addLayer();
    }
    final layerId = session.layers.first.id;
    final markerBefore = requireLayerAnywhere(
      session.repository.requireProject(),
      layerId,
    ).opacity;

    session.opacityVerbs.setLayerOpacity(layerId: layerId, opacity: 0.5);
    session.layerSwitches.setAllLayersVisibility(false);

    session.historyManager.undo(); // the whole batch
    session.historyManager.undo(); // the opacity before it

    expect(
      requireLayerAnywhere(
        session.repository.requireProject(),
        layerId,
      ).opacity,
      markerBefore,
      reason: 'two presses reached two actions — the batch was ONE of them',
    );
  });

  test('the twirl undoes — folder fold AND attach fold are one control', () {
    // 유저 2026-08-29: 「접기도 마찬가지야. 폴더든 어태치든」. ⛔I had argued
    // the twirl was the one to leave out because it changes no output;
    // 유저 said no. Attach needed no separate work: the row comment says
    // "They are one control: a row that holds other rows, folding them" —
    // both fold through `Layer.collapsed`.
    final session = newSession();
    addTearDown(session.dispose);
    final layerId = session.layers.first.id;
    final before = requireLayerAnywhere(
      session.repository.requireProject(),
      layerId,
    ).collapsed;

    session.folders.toggleLayerCollapsed(layerId);
    session.historyManager.undo();

    expect(
      requireLayerAnywhere(
        session.repository.requireProject(),
        layerId,
      ).collapsed,
      before,
    );
  });

  // ↩️F-162 (유저 2026-09-24): 「어니언/비지블솔로 등 내가 말한건 빼도록」. The
  // onion was undoable from 08-29 (「아무튼 레이어에 있는 버튼 싹다」) — the row
  // toggle and, after 유저 asked 「조작끝낸 모든 레이어가 안돌아간단거야
  // 설마?」, the legend sweep too. Both leave the history now, as the
  // visibility solo did (F-125): the onion shows the drawing, it is not an
  // edit of it. The pins below were the two that said it undoes.
  test('the onion toggle banks no undo step — Ctrl+Z takes the edit before '
      'it and leaves the ghosts alone', () {
    final session = newSession();
    addTearDown(session.dispose);
    session.layerStack.addLayer(); // an edit that IS a step
    final rows = session.layers.length;
    // F-145: only a row that can ghost takes the toggle — the stack's last
    // row is the camera, which refuses it.
    final ghosting = session.layers.firstWhere(
      (row) => row.kind.takesOnionSkin,
    );
    final steps = session.historyManager.undoCount;

    session.onionSkin.toggleLayerOnionSkin(ghosting.id);
    expect(
      session.onionSkin.isLayerOnionSkinEnabled(ghosting.id),
      isTrue,
      reason: 'fixture premise: the toggle toggled',
    );
    expect(session.historyManager.undoCount, steps);

    session.historyManager.undo();

    expect(
      session.layers.length,
      rows - 1,
      reason: 'the undo took the Add Layer, the step before the toggle',
    );
    expect(session.onionSkin.isLayerOnionSkinEnabled(ghosting.id), isTrue);
  });

  test('…and neither does the legend sweep over every displayed row', () {
    final session = newSession();
    addTearDown(session.dispose);
    for (var i = 0; i < 3; i += 1) {
      session.layerStack.addLayer();
    }
    final steps = session.historyManager.undoCount;
    final before = {
      for (final layer in session.layers)
        layer.id: session.onionSkin.isLayerOnionSkinEnabled(layer.id),
    };

    session.onionSkin.toggleOnionSkinForDisplayedLayers();
    final swept = {
      for (final layer in session.layers)
        layer.id: session.onionSkin.isLayerOnionSkinEnabled(layer.id),
    };
    expect(swept, isNot(before), reason: 'fixture: the sweep changed rows');
    expect(session.historyManager.undoCount, steps);

    session.onionSkin.toggleOnionSkinForDisplayedLayers();
    expect(
      {
        for (final layer in session.layers)
          layer.id: session.onionSkin.isLayerOnionSkinEnabled(layer.id),
      },
      before,
      reason: 'the second press is the way back — the button, not Ctrl+Z',
    );
  });
}
