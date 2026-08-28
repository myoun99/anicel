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

    session.toggleLayerVisibility(layerId);
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

    session.toggleLayerVisibility(layerId);
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

    session.setLayerBlendMode(
      layerId,
      beforeBlend == LayerBlendMode.multiply
          ? LayerBlendMode.screen
          : LayerBlendMode.multiply,
    );
    session.setLayerOpacity(layerId: layerId, opacity: 0.25);

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
      session.addLayer();
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

    session.setAllLayersVisibility(false);
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
      session.addLayer();
    }
    final layerId = session.layers.first.id;
    final markerBefore = requireLayerAnywhere(
      session.repository.requireProject(),
      layerId,
    ).opacity;

    session.setLayerOpacity(layerId: layerId, opacity: 0.5);
    session.setAllLayersVisibility(false);

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
}
