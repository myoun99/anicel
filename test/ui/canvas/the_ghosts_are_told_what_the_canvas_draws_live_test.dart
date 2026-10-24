import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/core/tree_nodes.dart' show preorderNodes;
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/debug/device_grid_probe.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';

/// The onion's ghosts lie over the frame's one picture in a stack of their
/// own, and the cel the canvas draws live is a ghost the frame after a step
/// — whole on its first frame only when the ghosts' stack was told, the
/// build before, that the canvas drew it live
/// (`a_cel_drawn_live_is_its_ghost_on_the_frame_after_test`).
void main() {
  testWidgets('the ghosts\' stack stands over the canvas with no ghost too, '
      'told the cel the canvas draws live', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();

    final drawnLive = <BrushFrameKey>[
      for (final node in preorderNodes(
        tester.widget<FramePictureView>(find.byType(FramePictureView)).nodes,
      ))
        if (node case CompositeLeaf(
          payload: CanvasActiveLayerRow(frameKey: final cel?),
        ))
          cel,
    ];
    expect(drawnLive, hasLength(1), reason: '⛔premise: a cel is drawn live');

    final ghosts = tester.widget<CanvasLayerStackView>(
      find.descendant(
        of: find.byType(DeviceGridProbe),
        matching: find.byType(CanvasLayerStackView),
      ),
    );
    expect(ghosts.nodes, isEmpty, reason: '⛔premise: no onion skin is on');
    expect(
      ghosts.drawnLive,
      {drawnLive.single},
      reason: 'the ghosts\' stack has to know the cel the canvas drew live '
          'BEFORE the step that makes it a ghost — mounted with that step, '
          'or told nothing, it composes the cel you just drew a frame late',
    );
  });
}
