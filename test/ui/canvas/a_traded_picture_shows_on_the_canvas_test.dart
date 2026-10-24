import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/core/tree_nodes.dart' show preorderNodes;
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// F-330 on the canvas — and F-313 (유저 2026-10-08): 「항상 보여야함」.
///
/// While a range is held over another row of its attach group, each cel
/// shows the picture coming to it — the row being drawn on too: its live
/// surface holds its own picture, so it hands the cel to an image until the
/// release, as it does for a block a drag brings under the playhead.
void main() {
  testWidgets('the row being drawn on shows, as an image, the picture its '
      'synced row is trading it — and the brush takes it where it lands', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final base = session.activeLayer!.id;
    session.createDrawingAtCurrentFrame();
    session.folders.addAttachedLayer(AttachedPlacement.above);
    final mirror = session.activeLayer!.id;
    session.selectLayer(base);
    session.selectFrameIndex(0);
    await tester.pumpAndSettle();
    final baseCel = session.layerById(base)!.frames.single.id;
    final mirrorCel = session.layerById(mirror)!.baseFrameLinks[baseCel]!;

    List<CanvasStackRow> rows() => [
      for (final node in preorderNodes(
        tester.widget<CanvasLayerStackView>(find.byType(CanvasLayerStackView))
            .nodes,
      ))
        if (node case CompositeLeaf(:final payload)) payload,
    ];
    CanvasActiveLayerRow? liveRow() =>
        rows().whereType<CanvasActiveLayerRow>().firstOrNull;
    List<(String, String)> images() => [
      for (final request in rows().whereType<CanvasLayerImageRequest>())
        (request.frameKey.layerId.value, request.frameKey.frameId.value),
    ];
    expect(liveRow()?.frameKey?.frameId, baseCel, reason: 'the premise');

    session.updateFrameRangeSelectionDrag(
      layerId: base,
      anchorIndex: 0,
      headIndex: 0,
    );
    expect(session.rangeMove.beginFrameRangeMoveDrag(base), isTrue);
    session.rangeMove.updateFrameRangeMoveDrag(
      frameDelta: 0,
      targetLayerId: mirror,
    );
    await tester.pump();

    expect(
      liveRow(),
      isNull,
      reason: 'the live surface holds the base\'s own picture',
    );
    expect(
      images(),
      containsAll([
        (mirror.value, mirrorCel.value),
        (base.value, baseCel.value),
      ]),
      reason: 'each cel shows the other\'s picture, where it still is',
    );

    session.rangeMove.endFrameRangeMoveDrag();
    await tester.pumpAndSettle();

    expect(
      liveRow()?.frameKey?.frameId,
      mirrorCel,
      reason: 'the brush followed the picture to the row it landed on — as '
          'a block carried across rows takes it',
    );
    expect(images(), contains((base.value, baseCel.value)));
  });
}
