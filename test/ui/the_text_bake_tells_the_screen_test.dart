// A TEXT CEL'S BAKE TELLS THE SCREEN IT HAPPENED.
//
// A survivor of the mutation campaign (2026-09-04, the text-cel sweep
// split): the sweep's `changed` never set, so the notify at its end never
// fired. Setting the text still notified — that is the COMMAND's own
// notify, and it lands before the bake — so every existing test stayed
// green while the freshly baked projection sat in the store with nothing
// asking the canvas to draw it.
//
// The oracle avoids the ordering race by asking INSIDE the listener: a
// notification that arrives when the projection is ALREADY in the store
// can only be the sweep's.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

void main() {
  testWidgets('the sweep notifies AFTER it bakes, so the canvas redraws '
      'with the new projection', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.layerStack.addLayerOfKind(LayerKind.text);
    final layerId = s.requireActiveCut.layers
        .firstWhere((layer) => layer.kind == LayerKind.text)
        .id;
    s.createDrawingAtCurrentFrame();

    Layer layerNow() =>
        s.requireActiveCut.layers.firstWhere((l) => l.id == layerId);
    bool baked() => s.layerStack.celHasContentForLayer(layerNow(), 0);
    expect(baked(), isFalse, reason: 'the cel starts blank');

    // Every notification, asked at the moment it arrives: was the
    // projection already there? The command's own notify answers no; only
    // the sweep's can answer yes.
    var notifiedAfterBake = 0;
    void listener() {
      if (baked()) {
        notifiedAfterBake += 1;
      }
    }

    s.addListener(listener);
    addTearDown(() => s.removeListener(listener));

    s.textCelBakes.setTextCelContentForSelectedFrame(
      const TextCelContent(
        text: 'カット 12',
        style: TextCelStyle(fontSize: 64, bold: true),
        position: Offset(200, 100),
      ),
    );
    for (var i = 0; i < 80 && notifiedAfterBake == 0; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(baked(), isTrue, reason: 'the bake landed at all');
    expect(
      notifiedAfterBake,
      greaterThan(0),
      reason:
          'the sweep must say it changed something — a projection that '
          'reaches the store with nothing asking for a repaint shows up as '
          'a text cel one frame late',
    );
  });
}
